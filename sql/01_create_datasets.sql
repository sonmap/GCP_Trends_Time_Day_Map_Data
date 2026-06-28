-- BigQuery dataset creation SQL
-- Replace PROJECT_ID with your Google Cloud project ID before running.

CREATE SCHEMA IF NOT EXISTS PROJECT_ID.location_raw
OPTIONS(
  location = 'asia-northeast3',
  description = 'Raw API payloads for location and population data'
);

CREATE SCHEMA IF NOT EXISTS PROJECT_ID.location_stg
OPTIONS(
  location = 'asia-northeast3',
  description = 'Staging tables normalized from raw JSON payloads'
);

CREATE SCHEMA IF NOT EXISTS PROJECT_ID.location_mart
OPTIONS(
  location = 'asia-northeast3',
  description = 'Analytics mart tables for place popularity and mobility dashboard'
);

CREATE SCHEMA IF NOT EXISTS PROJECT_ID.location_ml
OPTIONS(
  location = 'asia-northeast3',
  description = 'BigQuery ML models and prediction outputs'
);
