-- Build place popularity mart table.
-- Replace PROJECT_ID with your Google Cloud project ID before running.
-- If your project ID contains hyphens, wrap each fully qualified table name with backticks.

-- 1) Convert dim_place lat/lng into GEOGRAPHY.
UPDATE PROJECT_ID.location_mart.dim_place
SET geom = ST_GEOGPOINT(lng, lat)
WHERE geom IS NULL
  AND lat IS NOT NULL
  AND lng IS NOT NULL;

-- 2) Example view: population within 500m of each place.
CREATE OR REPLACE VIEW PROJECT_ID.location_mart.v_place_population_500m AS
SELECT
  p.place_id,
  p.display_name AS place_name,
  f.base_date,
  f.base_hour,
  SUM(COALESCE(f.population_total, f.max_population, 0)) AS population_500m
FROM PROJECT_ID.location_mart.dim_place p
JOIN PROJECT_ID.location_mart.fact_population_hourly f
  ON p.geom IS NOT NULL
 AND f.geom IS NOT NULL
 AND ST_DWITHIN(p.geom, f.geom, 500)
GROUP BY
  p.place_id,
  place_name,
  f.base_date,
  f.base_hour;

-- 3) Create normalized 0~100 popularity index.
CREATE OR REPLACE TABLE PROJECT_ID.location_mart.fact_place_popularity_hourly
PARTITION BY base_date
CLUSTER BY place_id, base_hour AS
WITH base AS (
  SELECT
    place_id,
    place_name,
    base_date,
    base_hour,
    population_500m,
    AVG(population_500m) OVER (PARTITION BY place_id, base_hour) AS baseline_avg,
    MAX(population_500m) OVER (PARTITION BY place_id) AS max_population
  FROM PROJECT_ID.location_mart.v_place_population_500m
)
SELECT
  base_date,
  base_hour,
  place_id,
  place_name,
  'population_500m' AS source,
  population_500m AS population_nearby,
  SAFE_DIVIDE(population_500m, NULLIF(max_population, 0)) * 100 AS popularity_index,
  baseline_avg,
  FORMAT_DATE('%A', base_date) AS day_of_week,
  FALSE AS is_holiday,
  CAST(NULL AS STRING) AS weather,
  CAST(NULL AS STRING) AS event_name,
  CURRENT_TIMESTAMP() AS loaded_at
FROM base;
