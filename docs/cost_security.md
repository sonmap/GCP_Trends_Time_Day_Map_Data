# 비용 및 보안 설계

## 1. 비용 구조 요약

이 프로젝트의 비용은 크게 4개 영역에서 발생합니다.

| 영역 | 서비스 | 비용 영향 |
|---|---|---|
| API 호출 | Google Places API | 호출량과 FieldMask에 따라 증가 |
| 수집 실행 | Cloud Run, Cloud Scheduler | 보통 낮음 |
| 저장 | Cloud Storage, BigQuery Storage | 데이터 보관량에 따라 증가 |
| 분석 | BigQuery Query, Looker Studio | 쿼리량과 스캔량에 따라 증가 |

## 2. Google Places API 비용 절감

### 원칙

- 장소 마스터 수집에만 사용합니다.
- 같은 장소는 반복 호출하지 않습니다.
- Place ID를 저장하고 캐시합니다.
- 최소 FieldMask만 사용합니다.
- 사진, 리뷰, 요약 등 고비용 필드는 PoC에서 제외합니다.

### 추천 FieldMask

최소 비용형:

```text
id,formattedAddress,location,types
```

실무 PoC형:

```text
id,displayName,formattedAddress,location,types
```

상권 분석형:

```text
id,displayName,formattedAddress,location,types,rating,userRatingCount,regularOpeningHours,businessStatus
```

### 호출 주기

| API | 추천 주기 |
|---|---:|
| Text Search | 최초 구축 시 또는 신규 장소 추가 시 |
| Place Details | 최초 1회, 이후 주 1회 또는 월 1회 |
| Nearby Search | 초기 주변 POI 분석 시 제한적으로 사용 |

## 3. BigQuery 비용 절감

### 파티션 전략

시간대별 유동인구 테이블은 날짜 기준 파티션을 적용합니다.

```sql
PARTITION BY base_date
CLUSTER BY area_name, base_hour, source
```

### 클러스터링 전략

| 테이블 | 클러스터링 컬럼 |
|---|---|
| `fact_population_hourly` | `area_name`, `base_hour`, `source` |
| `fact_place_popularity_hourly` | `place_id`, `base_hour` |
| `dim_place` | `place_id` |

### 대시보드용 Mart 테이블

Looker Studio가 Raw JSON을 직접 조회하지 않도록 Mart 테이블을 미리 만듭니다.

```text
Raw JSON -> Staging 정제 -> Mart 집계 -> Looker Studio
```

## 4. Cloud Run 비용 절감

- 요청 기반 실행 사용
- 최소 인스턴스 0 유지
- 수집 대상 지역을 설정 파일로 관리
- API 실패 시 무한 재시도 방지
- Timeout을 짧게 설정

권장값:

```text
CPU: 1 vCPU
Memory: 512Mi ~ 1Gi
Min instances: 0
Max instances: 1~3
Timeout: 300s
```

## 5. Secret 관리

API Key는 코드, README, Terraform 변수 파일에 직접 저장하지 않습니다.

```bash
echo -n "YOUR_GOOGLE_MAPS_API_KEY" | gcloud secrets create google-maps-api-key --data-file=-
echo -n "YOUR_SEOUL_API_KEY" | gcloud secrets create seoul-api-key --data-file=-
```

Cloud Run 서비스 계정에만 Secret Access 권한을 부여합니다.

```bash
gcloud secrets add-iam-policy-binding google-maps-api-key \
  --member="serviceAccount:location-collector-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

## 6. API Key 제한

### Google Maps API Key

Google Cloud Console에서 다음을 설정합니다.

```text
APIs & Services -> Credentials -> API Key 선택
  - API restrictions: Places API만 허용
  - Application restrictions: 서버 IP 또는 적절한 제한 적용
```

Cloud Run에서 서버 IP 고정이 필요하면 Serverless VPC Access + Cloud NAT 구조를 검토합니다.

## 7. IAM 최소 권한

### Cloud Run 수집기 서비스 계정

| 권한 | 용도 |
|---|---|
| `roles/secretmanager.secretAccessor` | API Key 조회 |
| `roles/bigquery.dataEditor` | BigQuery 테이블 적재 |
| `roles/bigquery.jobUser` | BigQuery Job 실행 |
| `roles/storage.objectCreator` | Raw JSON 저장 |
| `roles/pubsub.publisher` | Pub/Sub 메시지 발행, 운영 구성 시 |

### 분석 사용자

| 권한 | 용도 |
|---|---|
| `roles/bigquery.dataViewer` | 분석 테이블 조회 |
| `roles/bigquery.jobUser` | 쿼리 실행 |

## 8. 네트워크 보안

PoC에서는 Cloud Run이 외부 API를 호출하므로 Outbound 인터넷이 필요합니다.

운영 환경에서는 다음을 검토합니다.

- Cloud Run egress 제어
- Serverless VPC Access
- Cloud NAT 고정 IP
- API Key IP 제한
- VPC Service Controls는 BigQuery/GCS 보호에 검토

## 9. 모니터링 항목

| 항목 | 기준 |
|---|---|
| API 실패율 | 5xx/4xx 증가 |
| 수집 지연 | 마지막 수집 시각 기준 |
| BigQuery 적재 오류 | insert 실패 또는 스키마 오류 |
| Cloud Run 오류 | 500 응답, Timeout |
| 비용 증가 | 예산 알림 50/80/100% |
| 데이터 누락 | 장소별 시간대 누락 |

## 10. 예산 알림

GCP Billing Budget을 설정합니다.

권장:

```text
PoC: 월 50,000원 ~ 100,000원 수준 예산 알림
운영: 예상 호출량/쿼리량 기준으로 별도 산정
알림 기준: 50%, 80%, 100%
```

## 11. 개인정보/민감정보 주의

- 공공/민간 유동인구 데이터는 반드시 집계 데이터만 사용합니다.
- 개인 식별자, 단말 ID, 원시 위치 로그는 저장하지 않습니다.
- 민간 통신/카드 데이터는 계약서상 재식별 금지, 보관 기간, 제3자 제공 제한을 확인합니다.
- 대시보드는 집계 단위가 너무 작아 개인 추정이 가능하지 않도록 주의합니다.
