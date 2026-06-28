# 배포 가이드

## 1. 프로젝트 설정

```bash
PROJECT_ID="your-gcp-project-id"
REGION="asia-northeast3"
gcloud config set project ${PROJECT_ID}
```

## 2. API 활성화

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

## 3. Secret Manager 설정

```bash
echo -n "YOUR_GOOGLE_MAPS_API_KEY" | gcloud secrets create google-maps-api-key --data-file=-
echo -n "YOUR_SEOUL_API_KEY" | gcloud secrets create seoul-api-key --data-file=-
```

이미 Secret이 있으면 새 버전을 추가합니다.

```bash
echo -n "YOUR_GOOGLE_MAPS_API_KEY" | gcloud secrets versions add google-maps-api-key --data-file=-
echo -n "YOUR_SEOUL_API_KEY" | gcloud secrets versions add seoul-api-key --data-file=-
```

## 4. BigQuery 생성

SQL 파일의 `PROJECT_ID`를 실제 프로젝트 ID로 변경한 뒤 실행합니다.

```bash
sed "s/PROJECT_ID/${PROJECT_ID}/g" sql/01_create_datasets.sql | bq query --use_legacy_sql=false
sed "s/PROJECT_ID/${PROJECT_ID}/g" sql/02_create_tables.sql | bq query --use_legacy_sql=false
```

프로젝트 ID에 하이픈이 있으면 BigQuery SQL에서 전체 테이블명을 백틱으로 감싸세요.

```sql
CREATE SCHEMA IF NOT EXISTS `my-project.location_raw`;
```

## 5. Collector 이미지 빌드

```bash
REPOSITORY="location-trends"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/collector:latest"

gcloud artifacts repositories create ${REPOSITORY} \
  --repository-format=docker \
  --location=${REGION}

cd src/collector
gcloud builds submit --tag ${IMAGE}
cd ../..
```

## 6. Cloud Run 배포

```bash
gcloud run deploy location-trends-dev-collector \
  --image=${IMAGE} \
  --region=${REGION} \
  --no-allow-unauthenticated \
  --set-env-vars PROJECT_ID=${PROJECT_ID},BQ_RAW_DATASET=location_raw \
  --set-secrets GOOGLE_MAPS_API_KEY=google-maps-api-key:latest,SEOUL_API_KEY=seoul-api-key:latest
```

Cloud Storage Raw Zone을 쓰려면 버킷을 만들고 `GCS_BUCKET` 환경변수를 추가합니다.

```bash
BUCKET="${PROJECT_ID}-location-trends-dev-raw"
gsutil mb -l ${REGION} gs://${BUCKET}

gcloud run services update location-trends-dev-collector \
  --region=${REGION} \
  --set-env-vars GCS_BUCKET=${BUCKET}
```

## 7. Cloud Scheduler

Cloud Run URL을 확인합니다.

```bash
SERVICE_URL=$(gcloud run services describe location-trends-dev-collector \
  --region=${REGION} \
  --format='value(status.url)')
```

10분마다 `/collect`를 호출합니다. 운영에서는 OIDC 인증용 서비스 계정을 별도로 지정하세요.

```bash
gcloud scheduler jobs create http collect-location-data-10min \
  --schedule="*/10 * * * *" \
  --time-zone="Asia/Seoul" \
  --uri="${SERVICE_URL}/collect" \
  --http-method=GET \
  --location=${REGION}
```

## 8. Terraform 배포

```bash
cd terraform
terraform init
terraform plan \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="collector_image=${IMAGE}"

terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="collector_image=${IMAGE}"
```

Terraform은 Secret 리소스만 만들고 Secret 값은 저장하지 않습니다. Secret 값은 `gcloud secrets versions add`로 별도 등록하세요.

## 9. Looker Studio

1. Looker Studio 접속
2. BigQuery 연결
3. `location_mart.fact_place_popularity_hourly` 선택
4. 지도 차트, 시간대별 그래프, 요일별 비교 차트 구성

추천 필터:

- 날짜
- 시간대
- 장소명
- 요일
- 혼잡도 구간
