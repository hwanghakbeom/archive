# SCC On-prem Forwarder

SCC findings를 주기적으로 조회해 on-prem HTTPS endpoint로 전달하는 Cloud Run Job + NAT 인프라.

## 아키텍처

```
[Cloud Scheduler (cron)]
        │ POST + OAuth(SA: scc-forwarder-scheduler)
        ▼
[Cloud Run Jobs v2 :run API]
        │ creates execution
        ▼
[Cloud Run Job (scc-forwarder)]
   SA: scc-forwarder-job
   org-level: roles/securitycenter.findingsViewer
        │ Direct VPC egress (all traffic)
        ▼
[VPC subnet /28]
        │
        ▼
[Cloud Router + NAT — MANUAL_ONLY]
        │
        ▼
[고정 외부 IP (scc-forwarder-egress-ip)]
        │
        ▼ HTTPS POST
[On-premise SIEM/ingest endpoint]
```

## 배포 절차

### 1. 모듈 활성화 (인프라만)

`terraform.tfvars`에서:

```hcl
enable_scc_onprem_forwarder   = true
scc_forwarder_onprem_endpoint = "https://siem.internal.koreainvestment.com/scc-ingest"
# image_uri는 일단 placeholder 그대로 (gcr.io/google-samples/hello-app:1.0)
```

Apply → VPC, NAT, 고정 IP, Artifact Registry, Cloud Run Job (placeholder image), Scheduler 모두 생성.

### 2. 고정 IP 확인 → on-prem 방화벽 화이트리스트 등록

```bash
terraform output -raw -module=scc_onprem_forwarder egress_ip_address
# 또는
gcloud compute addresses describe scc-forwarder-egress-ip \
  --project=kis-gemini-common-prod --region=asia-northeast3 \
  --format="value(address)"
```

이 IP를 on-prem 수신 서버 방화벽에 등록.

### 3. 컨테이너 이미지 빌드 + 푸시

앱 코드는 본 모듈 내 `forwarder/` 서브디렉터리에 포함되어 있음:

```
forwarder/
├── Dockerfile          # python:3.12-slim + entrypoint
├── requirements.txt    # google-cloud-securitycenter, requests
├── main.py             # SCC v2 list_findings → batched HTTPS POST
├── cloudbuild.yaml     # gcloud builds submit 용
└── .dockerignore
```

**(권장) Cloud Build로 빌드 + 푸시** — 외부 docker 환경 불필요, 외부망 차단 환경에서도 동작:

```bash
cd iac/04.scc/onprem-forwarder/forwarder/
gcloud builds submit \
  --config=cloudbuild.yaml \
  --project=kis-gemini-common-prod \
  --substitutions=_REGION=asia-northeast3,_TAG=v1 \
  .
```

**또는 로컬 docker로:**

```bash
PROJECT=kis-gemini-common-prod
REGION=asia-northeast3

gcloud auth configure-docker ${REGION}-docker.pkg.dev

cd iac/04.scc/onprem-forwarder/forwarder/
docker buildx build --platform linux/amd64 \
  -t ${REGION}-docker.pkg.dev/${PROJECT}/scc-forwarder/forwarder:v1 .

docker push ${REGION}-docker.pkg.dev/${PROJECT}/scc-forwarder/forwarder:v1
```

### 4. image_uri 변경 + 재apply

```hcl
scc_forwarder_image_uri = "asia-northeast3-docker.pkg.dev/kis-gemini-common-prod/scc-forwarder/forwarder:v1"
```

> `lifecycle.ignore_changes`로 image 변경은 drift로 감지하지 않음. 명시적 apply로만 교체.

### 5. 수동 실행 테스트

```bash
gcloud run jobs execute scc-forwarder \
  --project=kis-gemini-common-prod \
  --region=asia-northeast3 \
  --wait
```

Cloud Run Logs에서 결과 확인:

```bash
gcloud logging read \
  'resource.type="cloud_run_job" AND resource.labels.job_name="scc-forwarder"' \
  --project=kis-gemini-common-prod --limit=20 \
  --format="value(jsonPayload.message,textPayload)"
```

## 앱 동작 사양 (참고)

컨테이너가 받는 ENV 변수:

| ENV | 설명 | 예시 |
|---|---|---|
| `ORG_ID` | GCP org ID | `457872813001` |
| `SCC_FILTER` | findings 쿼리 필터 | `state="ACTIVE" AND severity="HIGH"` |
| `ONPREM_ENDPOINT` | on-prem 수신 URL | `https://siem.internal.koreainvestment.com/scc-ingest` |
| `LOOKBACK_MINUTES` | 조회 시간 범위 | `75` |
| `ONPREM_AUTH_HEADER` | (선택) on-prem 인증 헤더 | `Authorization: Bearer xxx` |
| `BATCH_SIZE` | 배치당 finding 수 | `100` |
| `HTTP_TIMEOUT_SEC` | POST 타임아웃 | `30` |
| `HTTP_RETRIES` | POST 재시도 횟수 (exponential backoff) | `3` |

앱은 다음을 수행:
1. SCC v2 API `organizations/{ORG_ID}/sources/-/findings.list` 호출
2. filter = `SCC_FILTER` AND `event_time > (now - LOOKBACK_MINUTES)`
3. paginated 결과 수집
4. `BATCH_SIZE`개씩 묶어 `ONPREM_ENDPOINT`에 HTTPS POST (재시도 + backoff)
5. 성공: exit 0 / 부분 실패: exit 2 (Cloud Run Job max_retries=1로 1회 재시도)

POST 페이로드 (JSON):
```json
{
  "org_id": "457872813001",
  "exported_at": "2026-05-29T01:00:00.000+00:00",
  "count": 42,
  "findings": [
    {
      "name": "organizations/.../findings/...",
      "category": "PUBLIC_BUCKET_ACL",
      "severity": "HIGH",
      "state": "ACTIVE",
      "resource_name": "//storage.googleapis.com/projects/_/buckets/xxx",
      "event_time": "2026-05-29T00:55:23+00:00",
      "create_time": "2026-05-29T00:55:23+00:00",
      "description": "...",
      "external_uri": "https://...",
      "finding_class": "MISCONFIGURATION",
      "source_properties": { "...": "..." }
    }
  ]
}
```

## 인증 / 보안

- Cloud Run Job ↔ SCC API: SA의 `roles/securitycenter.findingsViewer` (org-level)
- Cloud Scheduler ↔ Cloud Run Job: SA의 `roles/run.invoker` (resource-level)
- Cloud Run Job ↔ on-prem: HTTPS + (선택) Bearer/HMAC/Basic 헤더는 Secret Manager 경유

### Secret Manager 연동 (on-prem 인증 헤더)

`scc_forwarder_enable_secret = true`로 두고 apply하면 시크릿 **자원만** 생성됨 (버전/값 없음).
시크릿 버전은 평문이 terraform state에 남지 않도록 별도 명령으로 추가:

```bash
# Bearer 토큰
echo -n "Authorization: Bearer eyJhbGc..." | gcloud secrets versions add \
  scc-forwarder-onprem-auth --data-file=- \
  --project=kis-gemini-common-prod

# HMAC 키 (앱이 X-Signature 헤더로 인식하도록)
echo -n "X-Signature: abc123def..." | gcloud secrets versions add \
  scc-forwarder-onprem-auth --data-file=- \
  --project=kis-gemini-common-prod

# Basic auth
echo -n "Authorization: Basic $(echo -n 'user:pass' | base64)" | gcloud secrets versions add \
  scc-forwarder-onprem-auth --data-file=- \
  --project=kis-gemini-common-prod
```

> 값 형식: `key:value` (":"있으면 해당 헤더) 또는 `value` (":"없으면 Authorization 헤더)로 main.py가 자동 인식.

Cloud Run Job 컨테이너에 `ONPREM_AUTH_HEADER` ENV로 자동 마운트됨 (`version=latest`).
Job 실행 시점에 최신 버전을 읽으므로 시크릿 rotate 시 Cloud Run 재배포 불필요.

시크릿 값 교체:
```bash
echo -n "Authorization: Bearer <NEW_TOKEN>" | gcloud secrets versions add \
  scc-forwarder-onprem-auth --data-file=- \
  --project=kis-gemini-common-prod

# (선택) 옛 버전 비활성화
gcloud secrets versions disable <OLD_VERSION_NUMBER> \
  --secret=scc-forwarder-onprem-auth --project=kis-gemini-common-prod
```

시크릿 값 확인 (운영자가 권한 있을 때 디버깅용):
```bash
gcloud secrets versions access latest \
  --secret=scc-forwarder-onprem-auth --project=kis-gemini-common-prod
```

## 정지 / 비활성화

`enable_scc_onprem_forwarder = false` → 모든 자원 destroy (고정 IP 포함). on-prem 화이트리스트에 IP 정보가 박혀있으면 영향. 일시 정지는 Scheduler만 끄는 게 안전:

```bash
gcloud scheduler jobs pause scc-forwarder-schedule \
  --project=kis-gemini-common-prod --location=asia-northeast3
```
