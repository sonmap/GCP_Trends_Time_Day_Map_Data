# GCP Trends Time Day Map Data

Google Places API, Seoul/Open Data population APIs, and BigQuery를 이용해 유명지역의 시간대별 유동인구와 혼잡도 지수를 수집·저장·분석하는 GCP 기반 설계/PoC 저장소입니다.

> 중요: Google Maps 화면에 표시되는 `인기 시간대(Popular times)` 데이터는 Google Places API 공식 필드로 직접 제공되지 않습니다. 이 저장소는 Google Places API를 장소 마스터 수집용으로 사용하고, 시간대별 유동인구는 서울/공공/민간 유동인구 API를 저장하여 자체 혼잡도 지수를 만드는 구조입니다.

## 1. 목표

- 유명지역, 관광지, 상권, 지하철역 주변의 시간대별 유동인구 비교
- 장소별/요일별/시간대별 혼잡도 지수 생성
- BigQuery GIS를 이용한 반경 500m 또는 행정동/격자 기반 분석
- Looker Studio 지도 대시보드 구성
- 향후 BigQuery ML 또는 Vertex AI 기반 혼잡도 예측 확장

## 2. 기본 아키텍처

```text
External APIs
  ├─ Google Places API              : 장소명, Place ID, 좌표, 업종, 평점, 영업시간
  ├─ 서울 실시간 도시데이터 API       : 실시간 인구, 혼잡도, 교통, 날씨, 행사
  ├─ 공공데이터포털                  : 생활인구, 관광지, 행사, 날씨
  └─ 민간 유동인구 데이터             : 통신사, 카드, 센서 데이터

GCP
  ├─ Cloud Scheduler                : 5분/10분/1일 주기 실행
  ├─ Cloud Run Collector             : Python API 수집기
  ├─ Secret Manager                  : API Key 보관
  ├─ Cloud Storage                   : Raw JSON/CSV 원본 보관
  ├─ Pub/Sub                         : 수집 이벤트 큐, 운영 확장 시 사용
  ├─ Dataflow                        : 정제/검증/변환, 운영 확장 시 사용
  ├─ BigQuery                        : Raw/Staging/Mart 분석 저장소
  ├─ BigQuery GIS                    : 반경/행정동/격자 공간 분석
  ├─ BigQuery ML                     : 혼잡도 예측
  └─ Looker Studio                   : 지도/그래프 대시보드
```

Mermaid 구성도는 `diagrams/` 디렉터리에 있습니다.

## 3. 추천 PoC 범위

| 단계 | 내용 |
|---|---|
| 1 | 서울 주요지역 20~100개 선정 |
| 2 | Google Places API로 Place ID/좌표/업종 수집 |
| 3 | 서울 실시간 인구 API를 5~10분마다 호출 |
| 4 | Cloud Storage에 원본 JSON 저장 |
| 5 | BigQuery Raw/Staging/Mart 테이블 구성 |
| 6 | 장소 반경 500m 기준 유동인구 계산 |
| 7 | 0~100 혼잡도 지수 생성 |
| 8 | Looker Studio 대시보드 구성 |

## 4. 디렉터리 구조

```text
.
├── README.md
├── docs/
│   ├── architecture.md
│   ├── data_sources.md
│   └── cost_security.md
├── diagrams/
│   ├── system-flow.mmd
│   ├── poc-flow.mmd
│   └── data-model.mmd
├── sql/
│   ├── 01_create_datasets.sql
│   ├── 02_create_tables.sql
│   └── 03_mart_popularity_index.sql
├── src/
│   └── collector/
│       ├── main.py
│       ├── requirements.txt
│       ├── Dockerfile
│       └── config/
│           └── areas.yaml
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── .gitignore
```

## 5. 필요한 API Key

| Key | 발급 위치 | 용도 |
|---|---|---|
| `GOOGLE_MAPS_API_KEY` | Google Cloud Console > APIs & Services > Credentials | Google Places API 호출 |
| `SEOUL_API_KEY` | 서울 열린데이터광장 | 서울 실시간 도시데이터/인구 API 호출 |
| `PUBLIC_DATA_API_KEY` | 공공데이터포털 | 생활인구, 관광지, 행사, 날씨 API 호출 |

## 6. GCP API 활성화

```bash
gcloud services enable \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  secretmanager.googleapis.com \
  bigquery.googleapis.com \
  storage.googleapis.com \
  pubsub.googleapis.com \
  dataflow.googleapis.com \
  cloudbuild.googleapis.com \
  places.googleapis.com
```

## 7. Secret Manager 저장 예시

```bash
echo -n "YOUR_GOOGLE_MAPS_API_KEY" | gcloud secrets create google-maps-api-key --data-file=-
echo -n "YOUR_SEOUL_API_KEY" | gcloud secrets create seoul-api-key --data-file=-
```

## 8. BigQuery SQL 실행 순서

```bash
bq query --use_legacy_sql=false < sql/01_create_datasets.sql
bq query --use_legacy_sql=false < sql/02_create_tables.sql
bq query --use_legacy_sql=false < sql/03_mart_popularity_index.sql
```

`PROJECT_ID` 문자열은 실제 GCP 프로젝트 ID로 변경해서 사용합니다.

## 9. Collector 로컬 실행 예시

```bash
cd src/collector
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export PROJECT_ID="your-gcp-project"
export GOOGLE_MAPS_API_KEY="your-google-maps-key"
export SEOUL_API_KEY="your-seoul-key"
python main.py
```

## 10. 비용 설계 원칙

- Google Places API는 장소 마스터 수집에만 사용합니다.
- 장소 데이터는 최초 수집 후 캐시하고, 매일/매시간 반복 호출하지 않습니다.
- 실시간 유동인구는 서울/공공/민간 API를 BigQuery에 직접 저장합니다.
- BigQuery 테이블은 날짜 파티션과 장소/시간 클러스터링을 적용합니다.
- `photos`, `reviews`, `generativeSummary` 등 고비용 필드는 PoC에서 제외합니다.

## 11. 향후 확장

- Pub/Sub + Dataflow 기반 실시간 파이프라인
- BigQuery GIS 기반 격자/상권/행정동 공간 분석
- BigQuery ML 기반 혼잡도 예측
- Vertex AI Forecasting 또는 AutoML 확장
- Looker Studio 운영 대시보드
- Terraform 기반 GCP 리소스 자동 생성
