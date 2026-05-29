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

`forwarder/` 디렉터리에 다음 구조로 앱 코드 작성 (예시):

```
forwarder/
├── Dockerfile
├── requirements.txt   # google-cloud-securitycenter, requests
└── main.py            # SCC list + on-prem POST
```

빌드 + 푸시 (placeholder가 아닌 실제 이미지):

```bash
PROJECT=kis-gemini-common-prod
REGION=asia-northeast3

gcloud auth configure-docker ${REGION}-docker.pkg.dev

cd forwarder/
docker buildx build --platform linux/amd64 \
  -t ${REGION}-docker.pkg.dev/${PROJECT}/scc-forwarder/forwarder:v1 .

docker push ${REGION}-docker.pkg.dev/${PROJECT}/scc-forwarder/forwarder:v1
```

또는 Cloud Build로:

```bash
gcloud builds submit ./forwarder \
  --tag=${REGION}-docker.pkg.dev/${PROJECT}/scc-forwarder/forwarder:v1 \
  --project=${PROJECT}
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

앱은 다음을 수행:
1. SCC v2 API `organizations/{ORG_ID}/sources/-/findings.list` 호출
2. filter = `SCC_FILTER` AND `event_time > (now - LOOKBACK_MINUTES)`
3. paginated 결과 수집
4. JSON 배열로 묶어 `ONPREM_ENDPOINT`에 HTTPS POST
5. 성공: exit 0 / 실패: exit non-zero (Cloud Run Job 재시도 1회)

## 인증 / 보안

- Cloud Run Job ↔ SCC API: SA의 `roles/securitycenter.findingsViewer` (org-level)
- Cloud Scheduler ↔ Cloud Run Job: SA의 `roles/run.invoker` (resource-level)
- Cloud Run Job ↔ on-prem: HTTPS + (선택) mTLS / Bearer / HMAC 헤더는 앱 구현
  - Secret Manager에 토큰 저장 후 Cloud Run Job에 secret 마운트 권장 (이 모듈에 추가하려면 var 확장 필요)

## 정지 / 비활성화

`enable_scc_onprem_forwarder = false` → 모든 자원 destroy (고정 IP 포함). on-prem 화이트리스트에 IP 정보가 박혀있으면 영향. 일시 정지는 Scheduler만 끄는 게 안전:

```bash
gcloud scheduler jobs pause scc-forwarder-schedule \
  --project=kis-gemini-common-prod --location=asia-northeast3
```
