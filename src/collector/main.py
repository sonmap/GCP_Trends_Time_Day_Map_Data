import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from urllib.parse import quote

import requests
import yaml
from flask import Flask, jsonify, request
from google.cloud import bigquery, storage

app = Flask(__name__)

PROJECT_ID = os.environ.get("PROJECT_ID")
BQ_RAW_DATASET = os.environ.get("BQ_RAW_DATASET", "location_raw")
GCS_BUCKET = os.environ.get("GCS_BUCKET")
GOOGLE_MAPS_API_KEY = os.environ.get("GOOGLE_MAPS_API_KEY")
SEOUL_API_KEY = os.environ.get("SEOUL_API_KEY")
AREA_CONFIG = os.environ.get("AREA_CONFIG", "config/areas.yaml")

bigquery_client = bigquery.Client(project=PROJECT_ID) if PROJECT_ID else None
storage_client = storage.Client(project=PROJECT_ID) if PROJECT_ID and GCS_BUCKET else None


class CollectorError(Exception):
    pass


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def load_config() -> Dict[str, Any]:
    with open(AREA_CONFIG, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def request_json(method: str, url: str, **kwargs: Any) -> Dict[str, Any]:
    response = requests.request(method, url, timeout=30, **kwargs)
    response.raise_for_status()
    return response.json()


def save_raw_to_gcs(source: str, name: str, payload: Dict[str, Any]) -> Optional[str]:
    if not storage_client or not GCS_BUCKET:
        return None

    now = utc_now()
    safe_name = name.replace("/", "_").replace(" ", "_")
    object_name = (
        f"raw/source={source}/date={now.date().isoformat()}/"
        f"hour={now.hour:02d}/{safe_name}-{now.strftime('%Y%m%dT%H%M%SZ')}.json"
    )
    bucket = storage_client.bucket(GCS_BUCKET)
    blob = bucket.blob(object_name)
    blob.upload_from_string(
        json.dumps(payload, ensure_ascii=False, indent=2),
        content_type="application/json; charset=utf-8",
    )
    return f"gs://{GCS_BUCKET}/{object_name}"


def insert_raw_bigquery(table_name: str, row: Dict[str, Any]) -> None:
    if not bigquery_client or not PROJECT_ID:
        return

    table_id = f"{PROJECT_ID}.{BQ_RAW_DATASET}.{table_name}"
    errors = bigquery_client.insert_rows_json(table_id, [row])
    if errors:
        raise CollectorError(f"BigQuery insert error: {errors}")


def collect_google_places(query_text: str) -> Dict[str, Any]:
    if not GOOGLE_MAPS_API_KEY:
        raise CollectorError("GOOGLE_MAPS_API_KEY is not set")

    url = "https://places.googleapis.com/v1/places:searchText"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": GOOGLE_MAPS_API_KEY,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.formattedAddress,"
            "places.location,places.types,places.rating,places.userRatingCount"
        ),
    }
    body = {
        "textQuery": query_text,
        "languageCode": "ko",
        "regionCode": "KR",
    }
    payload = request_json("POST", url, headers=headers, json=body)
    now = utc_now().isoformat()

    first_place_id = None
    if payload.get("places"):
        first_place_id = payload["places"][0].get("id")

    save_raw_to_gcs("google_places", query_text, payload)
    insert_raw_bigquery(
        "google_places_raw",
        {
            "collected_at": now,
            "query": query_text,
            "place_id": first_place_id,
            "raw_json": payload,
            "source": "google_places_text_search",
        },
    )
    return payload


def collect_seoul_population(area_name: str) -> Dict[str, Any]:
    if not SEOUL_API_KEY:
        raise CollectorError("SEOUL_API_KEY is not set")

    encoded_area = quote(area_name)
    url = f"http://openapi.seoul.go.kr:8088/{SEOUL_API_KEY}/json/citydata_ppltn/1/5/{encoded_area}"
    payload = request_json("GET", url)
    now = utc_now().isoformat()

    save_raw_to_gcs("seoul_population", area_name, payload)
    insert_raw_bigquery(
        "seoul_realtime_population",
        {
            "collected_at": now,
            "area_name": area_name,
            "raw_json": payload,
            "source": "seoul_citydata_ppltn",
        },
    )
    return payload


def collect_all() -> Dict[str, Any]:
    config = load_config()
    place_queries: List[str] = config.get("google_place_queries", [])
    seoul_areas: List[str] = config.get("seoul_realtime_areas", [])

    result = {
        "collected_at": utc_now().isoformat(),
        "google_places": [],
        "seoul_population": [],
        "errors": [],
    }

    for query_text in place_queries:
        try:
            collect_google_places(query_text)
            result["google_places"].append({"query": query_text, "status": "ok"})
        except Exception as exc:
            result["errors"].append({"source": "google_places", "name": query_text, "error": str(exc)})

    for area_name in seoul_areas:
        try:
            collect_seoul_population(area_name)
            result["seoul_population"].append({"area_name": area_name, "status": "ok"})
        except Exception as exc:
            result["errors"].append({"source": "seoul_population", "name": area_name, "error": str(exc)})

    return result


@app.route("/", methods=["GET"])
def health() -> Any:
    return jsonify({"status": "ok", "service": "gcp-trends-time-day-map-data"})


@app.route("/collect", methods=["GET", "POST"])
def collect_endpoint() -> Any:
    result = collect_all()
    status_code = 207 if result["errors"] else 200
    return jsonify(result), status_code


if __name__ == "__main__":
    # Local execution: python main.py
    # Cloud Run execution: gunicorn --bind :$PORT main:app
    if os.environ.get("RUN_ONCE", "false").lower() == "true":
        print(json.dumps(collect_all(), ensure_ascii=False, indent=2))
    else:
        app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
