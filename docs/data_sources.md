# 데이터 확보 방안

## 1. 핵심 결론

Google Maps 화면에 보이는 `인기 시간대(Popular times)` 데이터는 Google Places API 공식 필드로 직접 제공되지 않습니다. 따라서 다음 방식으로 데이터를 확보합니다.

```text
Google Places API        -> 장소 마스터, 좌표, 업종, 평점, 영업시간
서울 실시간 도시데이터 API -> 실시간 인구/혼잡도/교통/날씨/행사
서울 생활인구              -> 과거 시간대별 생활인구
공공데이터포털/TourAPI      -> 관광지, 행사, 축제, 날씨
민간 통신/카드 데이터       -> 고정밀 시간대별 유동인구
```

## 2. Google Places API

### 용도

- 유명지역/상권/관광지의 Place ID 확보
- 위도/경도 좌표 확보
- 장소 유형 분류
- 주소, 평점, 리뷰 수, 영업시간 확보

### 추천 API

| API | 용도 |
|---|---|
| Text Search | `강남역 서울`, `명동 관광특구` 등 텍스트 기반 장소 검색 |
| Place Details | Place ID 기준 상세 정보 조회 |
| Nearby Search | 특정 좌표 반경 내 음식점/카페/상점 수집 |

### PoC 추천 FieldMask

최소형:

```text
id,formattedAddress,location,types
```

대시보드용 추천형:

```text
id,displayName,formattedAddress,location,types
```

상권 분석형:

```text
id,displayName,formattedAddress,location,types,rating,userRatingCount,regularOpeningHours,businessStatus
```

### Text Search 예시

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Goog-Api-Key: ${GOOGLE_MAPS_API_KEY}" \
  -H "X-Goog-FieldMask: places.id,places.displayName,places.formattedAddress,places.location,places.types" \
  -d '{
    "textQuery": "강남역 서울",
    "languageCode": "ko",
    "regionCode": "KR"
  }' \
  "https://places.googleapis.com/v1/places:searchText"
```

### Place Details 예시

```bash
curl -X GET \
  -H "Content-Type: application/json" \
  -H "X-Goog-Api-Key: ${GOOGLE_MAPS_API_KEY}" \
  -H "X-Goog-FieldMask: id,displayName,formattedAddress,location,types,rating,userRatingCount" \
  "https://places.googleapis.com/v1/places/PLACE_ID"
```

## 3. 서울 실시간 도시데이터 API

### 용도

서울 주요 장소의 실시간 인구, 혼잡도, 교통, 날씨, 행사 정보를 수집합니다.

### 주요 API

| 서비스명 | 용도 |
|---|---|
| `citydata` | 인구, 상권, 교통, 날씨, 행사 통합 데이터 |
| `citydata_ppltn` | 실시간 인구/혼잡도 데이터 |
| `citydata_cmrcl` | 실시간 상권 현황 데이터 |

### URL 형식

```text
http://openapi.seoul.go.kr:8088/{SEOUL_API_KEY}/json/citydata_ppltn/1/5/{AREA_NAME}
```

예시:

```bash
curl "http://openapi.seoul.go.kr:8088/${SEOUL_API_KEY}/json/citydata_ppltn/1/5/광화문·덕수궁"
```

### 수집 대상 예시

```yaml
areas:
  - 광화문·덕수궁
  - 명동 관광특구
  - 홍대 관광특구
  - 강남 MICE 관광특구
  - 잠실 관광특구
  - 이태원 관광특구
  - 여의도
  - 성수카페거리
```

## 4. 서울 생활인구 / 공공데이터포털

### 용도

- 과거 시간대별 생활인구 분석
- 행정동/집계구 단위 인구 분석
- 연령/성별 분포 분석
- 평일/주말/공휴일 패턴 분석

### 활용 데이터

| 데이터 | 용도 |
|---|---|
| 서울 생활인구 | 시간대별 행정동/집계구 인구 |
| 관광공사 TourAPI | 관광지, 축제, 행사 위치 정보 |
| 기상청/공공 날씨 API | 비/눈/기온에 따른 유동인구 영향 |
| 지하철 승하차 정보 | 역세권 유동인구 보정 |
| 문화행사 정보 | 행사일 유동인구 증가 분석 |

## 5. 민간 데이터 확보 방안

정확한 유동인구 분석이 필요한 경우 민간 데이터 계약을 검토합니다.

| 데이터 | 제공 가능 정보 | 활용 |
|---|---|---|
| 통신사 유동인구 | 시간대/연령/성별/지역별 인구 | 고정밀 상권 분석 |
| 카드 매출 데이터 | 시간대/업종/지역별 매출 | 유동인구와 소비 상관분석 |
| Wi-Fi/AP 센서 | 실내 방문자 추정 | 쇼핑몰/매장 분석 |
| CCTV 카운터 | 출입 인원 카운트 | 특정 지점 정확도 향상 |

## 6. 데이터 적재 전략

### Raw Zone

- 원본 JSON/CSV를 Cloud Storage에 날짜별 저장
- 장애 발생 시 재처리 가능

```text
gs://BUCKET/raw/source=seoul_api/date=2026-06-28/hour=10/data.json
```

### BigQuery Raw

- 원본 JSON을 JSON 타입 또는 STRING 타입으로 저장
- 수집 시각, API명, 장소명, HTTP 상태코드 저장

### BigQuery Staging

- JSON에서 분석 컬럼 추출
- 날짜/시간/장소명/인구/혼잡도 정규화

### BigQuery Mart

- 대시보드와 분석용 테이블
- 날짜 파티션, 장소/시간 클러스터링 적용

## 7. 데이터 품질 체크

| 체크 항목 | 설명 |
|---|---|
| API 응답 코드 | 정상/오류 응답 구분 |
| 수집 시간 | 누락 구간 확인 |
| 장소명 매핑 | Google Place와 서울 API 장소명 매핑 |
| 좌표 유효성 | 위도/경도 범위 검증 |
| 중복 데이터 | 같은 장소/시간 중복 제거 |
| 비정상 인구 | 0 또는 급격한 튐값 확인 |

## 8. Google Popular Times 대체 전략

Google Popular Times 자체를 저장하지 않고 다음 지표를 만듭니다.

```text
혼잡도 지수 = 현재 또는 해당 시간 인구 / 해당 장소의 기준 최대 인구 * 100
```

보정 요소:

- 평일/주말
- 공휴일
- 날씨
- 행사 여부
- 지하철 승하차
- 주변 POI 수
- Google Places 평점/리뷰 수

## 9. 추천 1차 데이터 조합

PoC에서는 아래 3개만 사용해도 충분합니다.

| 데이터 | 이유 |
|---|---|
| Google Places API | 장소 좌표 확보 |
| 서울 실시간 인구 API | 실시간 유동인구 확보 |
| BigQuery GIS | 장소 반경 유동인구 분석 |
