-- BigQuery table DDL
-- Replace PROJECT_ID with your Google Cloud project ID before running.
-- If your project ID contains hyphens, wrap each fully qualified table name with backticks.

CREATE TABLE IF NOT EXISTS PROJECT_ID.location_raw.google_places_raw (
  collected_at TIMESTAMP,
  query STRING,
  place_id STRING,
  raw_json JSON,
  source STRING
)
PARTITION BY DATE(collected_at)
CLUSTER BY place_id, source;

CREATE TABLE IF NOT EXISTS PROJECT_ID.location_raw.seoul_realtime_population (
  collected_at TIMESTAMP,
  area_name STRING,
  raw_json JSON,
  source STRING
)
PARTITION BY DATE(collected_at)
CLUSTER BY area_name, source;

CREATE TABLE IF NOT EXISTS PROJECT_ID.location_mart.dim_place (
  place_id STRING,
  place_resource_name STRING,
  display_name STRING,
  formatted_address STRING,
  lat FLOAT64,
  lng FLOAT64,
  geom GEOGRAPHY,
  types ARRAY<STRING>,
  rating FLOAT64,
  user_rating_count INT64,
  regular_opening_hours JSON,
  business_status STRING,
  source STRING,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
)
CLUSTER BY place_id;

CREATE TABLE IF NOT EXISTS PROJECT_ID.location_mart.fact_population_hourly (
  base_time TIMESTAMP,
  base_date DATE,
  base_hour INT64,
  area_id STRING,
  area_name STRING,
  source STRING,
  congestion_level STRING,
  congestion_message STRING,
  min_population INT64,
  max_population INT64,
  population_total INT64,
  male_count INT64,
  female_count INT64,
  age_10 INT64,
  age_20 INT64,
  age_30 INT64,
  age_40 INT64,
  age_50 INT64,
  age_60_plus INT64,
  geom GEOGRAPHY,
  loaded_at TIMESTAMP
)
PARTITION BY base_date
CLUSTER BY area_name, base_hour, source;

CREATE TABLE IF NOT EXISTS PROJECT_ID.location_mart.fact_place_popularity_hourly (
  base_date DATE,
  base_hour INT64,
  place_id STRING,
  place_name STRING,
  source STRING,
  population_nearby INT64,
  popularity_index FLOAT64,
  baseline_avg FLOAT64,
  day_of_week STRING,
  is_holiday BOOL,
  weather STRING,
  event_name STRING,
  loaded_at TIMESTAMP
)
PARTITION BY base_date
CLUSTER BY place_id, base_hour;
