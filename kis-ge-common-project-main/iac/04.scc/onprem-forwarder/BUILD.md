# SCC → on-prem TCP Forwarder 구축 상세 가이드

SCC(Security Command Center) finding 이벤트를 **실시간**으로 on-prem SIEM(raw TCP)으로
전달하는 Cloud Run Service forwarder의 전체 구축 문서.

- **모듈 경로**: `iac/04.scc/onprem-forwarder/`
- **루트 wiring**: `iac/main.tf` `module "scc_onprem_forwarder"`
- **활성화 플래그**: `enable_scc_onprem_forwarder = true` (tfvars)
- **대상 프로젝트**: `kis-gemini-common-prod` / region `asia-northeast3`
- **on-prem 수신처**: `219.255.63.27:1514` (raw TCP, line-delimited JSON)

> 운영 요약/명령 헬퍼는 `README.md` 참조. 본 문서는 **구축 전 과정 + 설계 의도 +
> 실제 구축 중 부딪힌 문제와 해결**까지 상세히 다룬다.

## 0. 배포 상태 (2026-05-30 기준: 배포 완료)

| 항목 | 값 |
|---|---|
| Cloud Run Service | `scc-tcp-forwarder` — **Ready**, image `scc-forwarder/forwarder:v1` |
| Service URL | `https://scc-tcp-forwarder-wf4qxb2qiq-du.a.run.app` |
| egress 고정 IP (방화벽 화이트리스트 대상) | **`35.216.58.131`** (`scc-forword-siem`) |
| subnet | `scc-forwarder-subnet` `10.200.0.0/24` |
| topic / subscription | `scc-findings-notifications` / `scc-findings-tcp-forwarder` (OIDC push) |
| SCC notification config | v2 `all-active-findings`, filter `state="ACTIVE" AND (severity="HIGH" OR severity="CRITICAL")` |
| on-prem 수신처 | `219.255.63.27:1514` (raw TCP) |

**남은 운영 작업**: ① on-prem 방화벽에 `35.216.58.131 → 1514` 화이트리스트 ② end-to-end 테스트(§8).

---

## 1. 아키텍처

```
[SCC Premium / Enterprise tier]
    │ finding event (state=ACTIVE, severity HIGH/CRITICAL)
    ▼
[google_scc_notification_config]        ← 04.scc/notification-config (별도 모듈)
    │ publishes NotificationMessage(JSON)
    ▼
[PubSub topic: scc-findings-notifications]
    │ push subscription (scc-findings-tcp-forwarder)
    ▼ HTTPS POST + OIDC token (pusher SA)
[Cloud Run v2 Service: scc-tcp-forwarder]   (Flask + gunicorn, main.py)
    SA: scc-tcp-forwarder
    ingress: ALL  (OIDC 검증으로 PubSub만 허용)
    │ Direct VPC egress (ALL_TRAFFIC)
    ▼
[VPC: scc-forwarder-vpc / subnet: scc-forwarder-subnet (10.200.0.0/24)]
    │
    ▼
[Cloud Router + Cloud NAT (MANUAL_ONLY, 고정 예약 IP)]
    │ SNAT → 고정 외부 IP 1개
    ▼ raw TCP socket (1줄 JSON + "\n")
[on-prem 219.255.63.27:1514]   ← 방화벽에 NAT IP 화이트리스트 필요
```

**핵심 설계 결정**

| 결정 | 이유 |
|---|---|
| Cloud Run **Service** (Job/Scheduler 아님) | SCC finding을 받자마자 **실시간** 전송. 폴링/배치 지연 제거. |
| **PubSub push** (pull 아님) | 서버리스 — finding 없으면 인스턴스 0개(비용 0), 들어오면 자동 기동. |
| **Direct VPC egress** (Serverless VPC Connector 아님) | connector 인스턴스 비용/관리 제거. 단, **subnet IP를 직접 소모**(§6 주의). |
| **Cloud NAT + 고정 IP** | on-prem 방화벽이 화이트리스트할 **단일 고정 출발지 IP** 확보. |
| **OIDC token 검증** | ingress=ALL이지만 pusher SA token 없는 익명 호출 차단. |
| finding 데이터가 **메시지 본문에 포함** | forwarder가 SCC를 다시 조회할 필요 없음 → `securitycenter.findingsViewer` 불필요. |

---

## 2. 구성 요소 (Terraform 리소스)

모든 리소스는 `count = var.enable ? 1 : 0` — `enable=false`면 0개.

### 2-1. 컴퓨트 / 레지스트리 (`main.tf`)
- `google_artifact_registry_repository.scc_forwarder` — 이미지 push 대상 (`scc-forwarder`, DOCKER).
- `google_cloud_run_v2_service.scc_forwarder` — 이름 `scc-tcp-forwarder`.
  - `ingress = INGRESS_TRAFFIC_ALL`
  - `deletion_protection = true` (실수 삭제 방지; §7 참고)
  - `scaling`: `min_instance_count` / `max_instance_count` (= 2)
  - `vpc_access`: Direct VPC egress, `egress = ALL_TRAFFIC`
  - env: `ONPREM_HOST`, `ONPREM_PORT`, `TCP_TIMEOUT_SEC`
  - `lifecycle.ignore_changes = [template[0].containers[0].image]`
    → 이미지는 별도 빌드 파이프라인이 push하므로 terraform이 drift로 잡지 않음.
- `google_pubsub_subscription.scc_findings` — `scc-findings-tcp-forwarder`.
  - `push_config.push_endpoint = <service.uri>`, `oidc_token` = pusher SA
  - `retry_policy` 10s..600s, `expiration_policy.ttl = ""` (무기한)

### 2-2. 네트워크 (`network.tf`)
- `google_compute_network.scc_egress` — `scc-forwarder-vpc` (auto subnet off, REGIONAL).
- `google_compute_subnetwork.scc_egress` — `scc-forwarder-subnet`, `ip_cidr_range = var.vpc_cidr` (**`10.200.0.0/24`**).
- `google_compute_router.scc_egress` — `scc-forwarder-router`.
- `google_compute_router_nat.scc_egress` — `scc-forwarder-nat`, `MANUAL_ONLY`, `nat_ips = [고정 IP]`, `ALL_IP_RANGES`.
- **고정 IP 두 모드** (`use_existing_egress_ip`):
  - `true`(기본): `data.google_compute_addresses`로 region 내 예약 IP 자동 discover.
    - `egress_ip_name` 지정 시 이름 매칭, 비우면 region에 IP 1개일 때 자동 선택.
  - `false`: `google_compute_address.scc_egress_nat`로 신규 생성.
- `check "egress_ip_resolved"` — IP가 0개/2+개라 자동 선택 불가하면 명확한 에러.

### 2-3. IAM (`iam.tf`)
- `google_service_account.scc_forwarder` — `scc-tcp-forwarder` (서비스 실행용).
- `google_service_account.scc_pubsub_pusher` — `scc-pubsub-pusher` (PubSub→Run 호출용).
- `google_cloud_run_v2_service_iam_member.pubsub_invoker` — pusher SA에 `roles/run.invoker`.
- `google_service_account_iam_member.pubsub_token_creator` — PubSub service agent
  (`service-{PROJECT_NUM}@gcp-sa-pubsub.iam.gserviceaccount.com`)가 pusher SA token mint 가능.

### 2-4. 출력 (`output.tf`)
`egress_ip_address`, `artifact_registry_repo`, `service_name`, `service_url`,
`subscription_name`, `forwarder_service_account_email`, `pubsub_pusher_service_account_email`.

### 2-5. 변수 (`variables.tf` / 루트 `iac/variables.tf`)
| 모듈 변수 | 루트 변수 | 기본값 | 비고 |
|---|---|---|---|
| `enable` | `enable_scc_onprem_forwarder` | false | true로 활성화 |
| `image_uri` | `scc_forwarder_image_uri` | hello-app placeholder | 빌드 후 교체 |
| `onprem_host` | `scc_forwarder_onprem_host` | "" | `219.255.63.27` |
| `onprem_port` | `scc_forwarder_onprem_port` | 0 | `1514` |
| `tcp_timeout_sec` | `scc_forwarder_tcp_timeout_sec` | 10 | |
| `min_instance_count` | `scc_forwarder_min_instance_count` | 0 | scale-to-zero |
| `max_instance_count` | `scc_forwarder_max_instance_count` | **2** | IP 소모 제한 |
| `vpc_cidr` | `scc_forwarder_vpc_cidr` | **`10.200.0.0/24`** | §6 — `/26` 이상 필수 |
| `egress_ip_name` | `scc_forwarder_egress_ip_name` | "" | 비우면 자동 discover |
| `use_existing_egress_ip` | `scc_forwarder_use_existing_egress_ip` | true | |

> 실제 적용값은 **루트 변수**가 결정. CI는 `terraform.tfvars`가 없으면
> `terraform.tfvars.example`를 복사해 사용하므로 example이 사실상 source of truth.

---

## 3. 컨테이너 앱 (`forwarder/`)

- `main.py` — Flask 앱.
  - `POST /` : PubSub push envelope 수신 → `message.data`(base64) 디코드 →
    JSON 1줄 + `\n`을 `socket.create_connection`으로 on-prem에 전송 → close.
    - 성공 → `204` (PubSub ack)
    - base64 디코드 실패 → `204` (영구 에러라 retry 무의미, drop)
    - TCP timeout / 연결 실패 → `503` (PubSub가 retry_policy로 재시도)
  - `GET /healthz` : `200 ok`
  - 기동 시 `ONPREM_HOST`/`ONPREM_PORT` 없으면 `sys.exit(1)` (fail-fast).
- `requirements.txt` — `flask==3.0.3`, `gunicorn==21.2.0`.
- `Dockerfile` — `python:3.12-slim`, gunicorn (`--workers 1 --threads 8 --timeout 30`), PORT 8080.
- `cloudbuild.yaml` — `--platform=linux/amd64`로 빌드, `:${_TAG}` + `:latest` 두 태그 push.

전송 포맷 (한 줄 JSON):
```
{"notificationConfigName":"organizations/.../notificationConfigs/...","finding":{...},"resource":{...}}\n
```

---

## 4. CI/CD 파이프라인 (`.gitlab-ci.yml`, `scc` stage)

모든 job은 `when: manual`(main push 또는 web 트리거에서만), `resource_group: tfstate`로
직렬화, `needs: []`라 stage 순서 무시하고 개별 실행 가능. GCS backend.

| Job | 역할 |
|---|---|
| `enable-scc-tier` | SCC Premium/Enterprise tier 활성화 확인 수동 게이트 |
| `apply-scc-notifications` | SCC notification config + PubSub topic 생성 |
| `apply-scc-onprem-forwarder` | 본 모듈 apply (VPC/NAT/IP/AR/SA/Service/Subscription) + output 출력 |
| `build-forwarder-image` | Cloud Build로 컨테이너 빌드 + AR push (로컬 docker 불필요) |
| `apply-scc-forwarder-info` | 배포 상태(고정 IP/SA/URL 등) + 운영 명령 헬퍼 출력 |
| `heal-scc-forwarder` | **[임시]** IP 부족으로 배포 실패한 서비스 복구 (§7) |

---

## 5. 구축 절차 (처음부터 끝까지)

> 닭-달걀: 이미지를 push하려면 AR repo가 있어야 하고, AR repo는 forwarder apply가
> 만든다. 따라서 **forwarder apply(1차) → 빌드 → 재apply(2차)** 순서다.

### 0. 전제
- SCC tier가 Premium/Enterprise로 활성화 (`enable-scc-tier` 게이트 통과).
- `apply-services`로 API enable: `run`, `cloudbuild`, `artifactregistry`, `compute`, `pubsub` 등.
- region에 NAT용 **예약 외부 IP**가 있거나(자동 discover) `use_existing_egress_ip=false`로 신규 생성.

### 1. SCC notification + PubSub topic
```
CI: apply-scc-notifications
```
`scc-findings-notifications` topic 존재 확인:
```bash
gcloud pubsub topics list --project=kis-gemini-common-prod | grep scc-findings
```

### 2. tfvars 설정
```hcl
enable_scc_onprem_forwarder      = true
scc_forwarder_onprem_host        = "219.255.63.27"
scc_forwarder_onprem_port        = 1514
scc_forwarder_vpc_cidr           = "10.200.0.0/24"   # /26 이상 필수 (§6)
scc_forwarder_max_instance_count = 2
scc_forwarder_use_existing_egress_ip = true
scc_forwarder_image_uri          = "gcr.io/google-samples/hello-app:1.0"  # placeholder
```

### 3. forwarder apply (1차) — 인프라 + AR repo
```
CI: apply-scc-onprem-forwarder
```
완료 후 output에서 `egress_ip_address` 확인 → **on-prem 방화벽에 이 IP 화이트리스트 +
1514 port 개방** 요청.

### 4. 이미지 빌드 + AR push
```
CI: build-forwarder-image   (Run Pipeline 변수 IMAGE_TAG=v1)
```
또는 로컬:
```bash
cd iac/04.scc/onprem-forwarder/forwarder/
gcloud builds submit --config=cloudbuild.yaml \
  --project=kis-gemini-common-prod \
  --substitutions=_REGION=asia-northeast3,_TAG=v1 .
```

### 5. image_uri 교체 + 재apply (2차)
```hcl
scc_forwarder_image_uri = "asia-northeast3-docker.pkg.dev/kis-gemini-common-prod/scc-forwarder/forwarder:v1"
```
```
CI: apply-scc-onprem-forwarder
```
→ Cloud Run revision이 실제 이미지로 갱신. (image 변수 변경은 `ignore_changes`와
무관하게 명시적 apply로 반영)

### 6. 검증
```
CI: apply-scc-forwarder-info   (URL/IP/SA 출력)
```
PubSub 강제 메시지로 end-to-end 테스트:
```bash
gcloud pubsub topics publish scc-findings-notifications \
  --message='{"finding":{"category":"TEST","severity":"HIGH","state":"ACTIVE"},"resource":{"name":"//test"}}' \
  --project=kis-gemini-common-prod
```
로그:
```bash
gcloud logging tail \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="scc-tcp-forwarder"' \
  --project=kis-gemini-common-prod
```
성공 시 `forwarded message_id=... size=... to 219.255.63.27:1514` 라인 + on-prem 수신 확인.

---

## 6. ⚠️ 네트워크 IP 사이징 (가장 중요한 교훈)

**Cloud Run Direct VPC egress는 인스턴스마다 subnet IP를 1개 소모**하며, revision
롤아웃(blue-green) 중에는 추가 IP가 필요하다. 그래서 subnet이 작으면 배포 자체가 실패한다.

- **증상**: `error code 9 / health check failed for the deployment / there is no sufficient IP in the VPC network`
- **원인**: subnet `/28`(가용 ~11개)은 Direct VPC egress에 부족.
- **해결**: `vpc_cidr`를 **`/26` 이상**으로. 본 모듈은 여유 있게 **`/24`(256개)** 사용.

> `max_instance_count`를 줄이는 것만으로는 부족하다 (롤아웃 시점 IP 부족 발생).
> subnet 자체를 키워야 한다.

**subnet 확장 특성**: 같은 base(`10.200.0.0`)에서 prefix를 줄이는 확장(`/28`→`/24`)은
google provider에서 **in-place 확장**(재생성 없음)으로 처리된다. NAT는 `ALL_IP_RANGES`라
subnet 확장을 자동으로 따라간다.

---

## 7. 트러블슈팅 — `deletion_protection` × `taint` 데드락

실제 구축 중 다음 연쇄가 발생했다(원인은 §6의 IP 부족):

```
subnet /28 IP 부족
  → Cloud Run 배포 health check 실패 (no sufficient ip)
  → 리소스가 tainted ("is tainted, so must be replaced")
  → 강제 replace (destroy + create)
  → replace의 destroy가 deletion_protection=true에 막힘 ("cannot destroy ...")
  → (-refresh=false 탓에) service.uri가 state에서 null
     → "push_config.0.push_endpoint is required, but no definition was found"
```

### 핵심 메커니즘
- **`deletion_protection`**: google provider는 destroy 시 **state의 값**을 읽는다.
  - 순수 destroy/replace의 destroy 단계는 **옛 state 값(true)** 을 보므로,
    config만 false로 바꿔도 같은 apply에서 막힌다.
  - 따라서 `false`가 **state에 먼저 반영(persist)** 돼야 destroy가 허용된다.
- **`taint`**: 배포 실패가 남긴 흔적. tainted면 in-place update가 불가하고 무조건 replace.
- **`-refresh=false`**(CI 속도용): state의 computed 값(`service.uri`)이 비어 있으면
  live에서 다시 안 읽어와 `null`로 남는다 → required 인자에 null = "정의 없음" 에러.

### ✅ 실제 최종 해결 (heal 불필요)

위 연쇄의 진짜 뿌리는 두 가지였고, 아래로 해결됨 (`heal-scc-forwarder` job은
중간 시도였으며 제거됨):

1. **subnet `/28` → `/24`** — Direct VPC egress IP 부족 해소 (배포 health check 통과).
2. **`lifecycle.ignore_changes = [image]` 제거** — 이게 placeholder(hello-app)에서
   실제 이미지(`forwarder:v1`)로의 갱신을 막아 서비스가 Ready=False에 갇혀 있었다.
   제거하니 image 변경이 **in-place revision 업데이트(destroy 없음)** 로 적용 →
   `deletion_protection`/`taint`/`-replace`가 전부 무관해지고, 평범한
   `apply-scc-onprem-forwarder` 한 번으로 정상화됨.
3. **`apply-scc-onprem-forwarder`의 `-refresh=false` 제거** — service.uri를 stale ""로
   plan해 subscription `push_endpoint`가 "inconsistent final plan"이 되던 문제 해소.

> 아래는 당시 시도했던 heal 절차의 기록 (현재 job은 없음).

### (참고) 당시 시도: `heal-scc-forwarder` job
선행(코드): `vpc_cidr` 확대(/24), `deletion_protection`을 임시 `false`로.
job이 순서대로:
1. `terraform untaint <service>` — taint 제거 → in-place 가능 (이미 정상이면 `|| true`로 무시)
2. `terraform apply -refresh-only` — live 읽어 `service.uri` 등 computed 복구
3. `terraform apply -target=module` — subnet 확장 + `deletion_protection=false`를 in-place로 state에 반영
   - **검증**: 직후 `terraform state show`로 subnet `ip_cidr_range`가 `/24`인지 로그 출력
4. `terraform apply -replace=<service>` — 서비스만 clean 재생성
   (destroy는 state=false라 통과, create는 IP 충분(/24)해 health check 통과)

### heal 후 마무리 (필수)
서비스 정상(새 revision Ready) 확인 후:
1. `deletion_protection = true` 복원 (`main.tf`)
2. `heal-scc-forwarder` job 제거 (`.gitlab-ci.yml`)
3. `apply-scc-onprem-forwarder`로 deletion_protection true 재반영

### 트러블슈팅 표
| 증상 | 원인 / 조치 |
|---|---|
| `no sufficient ip in the VPC network` | subnet 너무 작음 → `vpc_cidr` `/26`↑ (본 모듈 `/24`) |
| `cannot destroy ... deletion_protection` | state의 deletion_protection=true. heal로 untaint+false 반영 후 진행 |
| `is tainted, so must be replaced` | 이전 배포 실패 흔적. `terraform untaint` |
| `push_config.0.push_endpoint is required` | `service.uri`가 state에서 null. `apply -refresh-only`로 복구 |
| `region에 reserved IP 2개 이상` (check 실패) | `egress_ip_name` 명시 |
| 컨테이너 crash + `ONPREM_HOST 미설정` | tfvars에 onprem_host/port 입력 |
| TCP timeout 반복 | on-prem 방화벽이 NAT IP 차단 / port 닫힘 / `TCP_TIMEOUT_SEC` 조정 |

---

## 8. 운영

### 모니터링
```bash
gcloud logging tail \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="scc-tcp-forwarder"' \
  --project=kis-gemini-common-prod
```
- 성공: `{"...","msg":"forwarded message_id=... size=... to 219.255.63.27:1514"}`
- 실패: `{"...","level":"ERROR","msg":"TCP timeout to ...:1514 ..."}` → 503 → PubSub retry

### 정지 / 비활성화
- `min_instance_count=0`이라 finding 없으면 자동 0 인스턴스(비용 0).
- 완전 정지: `enable_scc_onprem_forwarder=false` → apply (단, deletion_protection=true면
  서비스 destroy 전 false 선행 필요 — §7).

### 보안
- **PubSub → Run**: ingress=ALL이나 OIDC token(pusher SA) 검증으로 익명 차단.
- **Run → on-prem**: raw TCP, 인증 없음 → on-prem이 **source IP 화이트리스트**로 게이트.
- TLS 필요 시 `main.py`의 `socket.create_connection`을 `ssl`로 래핑 (별도 패치).

---

## 9. 파일 맵
```
iac/04.scc/onprem-forwarder/
├── BUILD.md          # 본 문서 — 구축 상세 + 트러블슈팅
├── README.md         # 운영 요약 + 명령 헬퍼
├── main.tf           # AR repo + Cloud Run v2 Service + PubSub subscription
├── network.tf        # VPC + subnet(/24) + Router + NAT + 고정 IP discover
├── iam.tf            # forwarder SA + pusher SA + OIDC 권한
├── output.tf         # egress IP / service URL / SA 등
├── variables.tf      # 모듈 변수
├── provider.tf       # google ~> 7.20
└── forwarder/        # 컨테이너 앱
    ├── main.py       # Flask: PubSub push → raw TCP
    ├── Dockerfile    # python:3.12-slim + gunicorn
    ├── cloudbuild.yaml
    └── requirements.txt

iac/main.tf            # module "scc_onprem_forwarder" wiring
iac/variables.tf       # scc_forwarder_* 루트 변수
iac/terraform.tfvars.example  # 활성화 값 (CI source of truth)
.gitlab-ci.yml         # scc stage jobs
```
