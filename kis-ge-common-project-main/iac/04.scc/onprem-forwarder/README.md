# SCC PubSub → TCP Forwarder

SCC notification(PubSub)을 받자마자 on-prem TCP endpoint로 실시간 전송하는 Cloud Run Service.

## 아키텍처

```
[SCC Premium / Enterprise tier]
    │ finding event (HIGH/CRITICAL active)
    ▼
[google_scc_notification_config]   ← 04.scc/notification-config (기존)
    │ publishes
    ▼
[PubSub topic: scc-findings-notifications]   ← 기존
    │ push subscription (본 모듈)
    ▼ HTTPS POST + OIDC token
[Cloud Run Service: scc-tcp-forwarder]
    SA: scc-tcp-forwarder
    ingress: ALL (OIDC 검증으로 PubSub만 허용)
    │ Direct VPC egress
    ▼
[VPC subnet /28]
    │
    ▼
[Cloud Router + NAT (기존 예약 IP)]
    │ SNAT
    ▼ raw TCP socket (line-delimited JSON + "\n")
[on-prem IP:port]
```

## ENV (Cloud Run Service)

| ENV | 설명 | 예시 |
|---|---|---|
| `ONPREM_HOST` | 수신 서버 IP/hostname | `siem.internal.koreainvestment.com` |
| `ONPREM_PORT` | 수신 TCP port | `6514` |
| `TCP_TIMEOUT_SEC` | 연결/전송 timeout | `10` |

## 전송 포맷

각 finding은 단건 TCP 연결로 전송 (PubSub message 1건 = TCP write 1회):

```
{"notificationConfigName":"organizations/.../notificationConfigs/...","finding":{...},"resource":{...}}\n
```

→ 한 줄 JSON + `\n`. on-prem 수신 측은 line-delimited JSON으로 처리.

## 배포 절차

### 1. 전제 — SCC notification + PubSub topic 존재

```bash
gcloud pubsub topics list --project=kis-gemini-common-prod | grep scc-findings
# scc-findings-notifications (없으면 apply-scc-notifications 먼저)
```

### 2. NAT 고정 IP 확보 (1회)

```bash
gcloud compute addresses create scc-forwarder-egress-ip \
  --region=asia-northeast3 \
  --project=kis-gemini-common-prod \
  --network-tier=PREMIUM
gcloud compute addresses describe scc-forwarder-egress-ip \
  --region=asia-northeast3 --project=kis-gemini-common-prod \
  --format="value(address)"
```

→ on-prem 방화벽에 이 IP 화이트리스트 등록 + 수신 port 개방.

### 3. terraform tfvars 채우기

```hcl
enable_scc_onprem_forwarder      = true
scc_forwarder_onprem_host        = "siem.internal.koreainvestment.com"
scc_forwarder_onprem_port        = 6514
scc_forwarder_image_uri          = "gcr.io/google-samples/hello-app:1.0"  # 빌드 전 placeholder
scc_forwarder_use_existing_egress_ip = true
```

### 4. apply (Cloud Run Service + Subscription + VPC/NAT 모두 생성)

GitLab CI: `apply-services` → `apply-scc-onprem-forwarder` → `apply-scc-forwarder-info`

### 5. 이미지 빌드 + AR push

```bash
cd iac/04.scc/onprem-forwarder/forwarder/
gcloud builds submit \
  --config=cloudbuild.yaml \
  --project=kis-gemini-common-prod \
  --substitutions=_REGION=asia-northeast3,_TAG=v1 .
```

### 6. image_uri 교체 + 재apply

```hcl
scc_forwarder_image_uri = "asia-northeast3-docker.pkg.dev/kis-gemini-common-prod/scc-forwarder/forwarder:v1"
```

→ Cloud Run Service revision 새로 배포. `lifecycle.ignore_changes`로 평소엔 drift 안 잡지만, image_uri 변수 변경은 명시적 apply.

### 7. 테스트 — PubSub에 강제 메시지 publish

```bash
gcloud pubsub topics publish scc-findings-notifications \
  --message='{"notificationConfigName":"test","finding":{"name":"test/finding","category":"TEST","severity":"HIGH","state":"ACTIVE"},"resource":{"name":"//test"}}' \
  --project=kis-gemini-common-prod
```

→ Cloud Run Logs에서 `forwarded message_id=... to <host>:<port>` 라인 확인. on-prem 측에서도 raw JSON line 수신 확인.

## 로그 모니터링

```bash
gcloud logging tail \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="scc-tcp-forwarder"' \
  --project=kis-gemini-common-prod
```

성공 로그:
```json
{"ts":"2026-05-29T...","level":"INFO","msg":"forwarded message_id=... publish_time=... size=842 to siem.internal.koreainvestment.com:6514"}
```

TCP 실패 로그:
```json
{"ts":"...","level":"ERROR","msg":"TCP timeout to ...:6514 message_id=..."}
```
→ Cloud Run Service가 503 반환 → PubSub이 retry_policy(10s..600s)로 재시도.

## 정지

```bash
# Cloud Run Service min_instance_count=0이면 PubSub이 안 보내면 0으로 idle (비용 0).
# 완전 정지하려면 enable=false로 토글 후 apply.
# 또는 subscription만 일시 pause:
gcloud pubsub subscriptions delete scc-findings-tcp-forwarder \
  --project=kis-gemini-common-prod  # 메시지 buffer 손실 위험 — terraform apply로 복구
```

## 인증/보안

- **PubSub → Cloud Run**: ingress=ALL이지만 OIDC token (pusher SA) 검증. PubSub 외 익명 호출 차단.
- **Cloud Run → on-prem**: raw TCP, 인증 없음. on-prem 측에서 source IP 화이트리스트로 게이트.
- TLS 필요 시 main.py에서 `socket.create_connection` 대신 `ssl.wrap_socket` 사용 — 별도 요청 시 패치 가능.

## 트러블슈팅

| 증상 | 원인 / 조치 |
|---|---|
| Cloud Run Service 응답 없음 | PubSub push 미도착 — subscription 존재 확인 / OIDC IAM 확인 |
| TCP timeout 반복 | on-prem 방화벽이 NAT IP를 차단했거나 port 닫힘 |
| `ONPREM_HOST 미설정` 로그 + 컨테이너 crash | tfvars에 onprem_host/port 입력 누락 |
| 메시지 무한 retry | on-prem 수신 측에서 connection 받지만 응답이 늦음 — TCP_TIMEOUT_SEC 늘리거나 on-prem 쪽 성능 점검 |
| 메시지 누락 | PubSub `retry_policy` 종료 후 ack_deadline 초과 — message_retention_duration 기본 7일 안에 처리 안 되면 drop |
