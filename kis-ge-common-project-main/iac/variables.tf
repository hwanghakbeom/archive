# === Org identity ===
variable "org_id" {
  description = "GCP 조직 ID (숫자, 예: \"240369219899\")."
  type        = string
}

# === Provider routing ===
variable "billing_project" {
  description = "user_project_override 용 billing/quota 프로젝트. ops 프로젝트(kis-gemini-common-prod) 권장."
  type        = string
}

variable "region_primary" {
  description = "주 GCP 리전."
  type        = string
  default     = "asia-northeast3"
}

# === Phase 1: Access Context Manager ===
variable "access_policy_title" {
  description = "Access Context Manager Access Policy의 title (org당 1개만 허용)."
  type        = string
  default     = "krinvest-lzone-policy"
}

# === Phase 1-B: Central Service Perimeter (모든 자회사 통합) ===
variable "enable_central_perimeter" {
  description = "통합 Service Perimeter 활성화. 모든 subsidiary_project_ids가 perimeter 안에 포함."
  type        = bool
  default     = false
}

variable "subsidiary_project_ids" {
  description = "Perimeter에 포함될 자회사 GCP 프로젝트 ID 목록 (자회사 stack apply 후 채움)."
  type        = list(string)
  default     = []
}

variable "perimeter_dry_run" {
  description = "true=dry_run(로깅만), false=enforcement(차단). 시작은 true."
  type        = bool
  default     = true
}

variable "perimeter_allowed_ip_ranges" {
  description = "Access Level이 허용할 CIDR (회사 IP / VPN)."
  type        = list(string)
  default     = []
}

variable "perimeter_allowed_members" {
  description = "Access Level이 허용할 identity."
  type        = list(string)
  default     = []
}

variable "perimeter_ingress_identities" {
  description = "Perimeter ingress 허용 identity."
  type        = list(string)
  default     = []
}

variable "perimeter_ingress_source_projects" {
  description = "Perimeter ingress 허용 소스 프로젝트 번호."
  type        = list(string)
  default     = []
}

variable "perimeter_restricted_services" {
  description = "Perimeter 안에서 제한되는 Google API."
  type        = list(string)
  default = [
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "dlp.googleapis.com",
    "cloudkms.googleapis.com",
  ]
}

variable "perimeter_subsidiary_ge_access" {
  description = "자회사별 GE(discoveryengine) 접근 정책 맵. service-perimeter 모듈의 subsidiary_ge_access로 전달."
  type = map(object({
    project_id        = string
    controlled        = bool
    allowed_ip_ranges = optional(list(string), [])
    external_members  = optional(list(string), [])
  }))
  default = {}
}

# === Phase 2: Storage Org Policies ===
variable "enforce_public_access_prevention" {
  description = "storage.publicAccessPrevention=enforced 조직 전체 강제."
  type        = bool
  default     = true
}

variable "enforce_uniform_bucket_level_access" {
  description = "storage.uniformBucketLevelAccess=true 조직 전체 강제."
  type        = bool
  default     = true
}

# === Phase 2: CMEK Org Policies ===
variable "enable_restrict_non_cmek" {
  description = "gcp.restrictNonCmekServices 활성화 — 명시된 서비스는 CMEK 필수. 신규 자원만 영향."
  type        = bool
  default     = false
}

variable "cmek_required_services" {
  description = "CMEK 강제할 GCP 서비스 목록."
  type        = list(string)
  default = [
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "discoveryengine.googleapis.com",
    "aiplatform.googleapis.com",
  ]
}

# === Phase 3: Aggregated Log Sink ===
variable "ops_project_id" {
  description = "중앙 audit bucket이 위치할 ops 프로젝트 ID (예: kis-gemini-common-prod)."
  type        = string
}

variable "central_audit_bucket_name" {
  description = "중앙 audit 로그 GCS bucket 이름. 글로벌 유니크."
  type        = string
  default     = "kis-gemini-common-prod-org-audit-logs"
}

# === GE 로그 federation (8개 자회사 BQ 테이블 UNION 뷰) ===
variable "enable_ge_log_analytics" {
  description = "8개 자회사 ge_logs 테이블을 UNION federation 뷰로 묶는 모듈 활성화."
  type        = bool
  default     = false
}

variable "ge_logs_dataset_id" {
  description = "common federation 데이터셋 ID (ops project)."
  type        = string
  default     = "ge_logs"
}

variable "ge_logs_viewer_members" {
  description = "federation 뷰 조회 주체 (user:/group:). common dataset dataViewer (일반 뷰라 자회사 데이터셋 read도 필요)."
  type        = list(string)
  default     = []
}

variable "retention_days" {
  description = "감사 로그 보관 일수. 2555 = 7년."
  type        = number
  default     = 2555
}

variable "lock_retention" {
  description = "감사 bucket retention 잠금 (IRREVERSIBLE). 사인오프 후 true."
  type        = bool
  default     = false
}

variable "aggregated_sink_name" {
  description = "Organization log sink 이름."
  type        = string
  default     = "krinvest-org-audit-to-gcs"
}

# === Phase 3: Org IAM AuditConfig ===
variable "enable_org_data_access_audit" {
  description = "조직 전체 DATA_READ + DATA_WRITE 감사 로그 강제. 비용 영향 있음."
  type        = bool
  default     = false
}

# === DLP Discovery (조직 레벨) ===
variable "enable_dlp_discovery" {
  description = "조직 레벨 DLP Discovery 활성화. SCC Premium tier 활성화 필수, 비용 영향 큼."
  type        = bool
  default     = false
}

variable "dlp_scan_targets" {
  description = "DLP Discovery가 스캔할 자원 타입."
  type = object({
    bigquery      = optional(bool, true)
    cloud_sql     = optional(bool, true)
    cloud_storage = optional(bool, true)
  })
  default = {}
}

variable "dlp_cadence_frequency" {
  description = "DLP scan 주기. DAILY/WEEKLY/MONTHLY. 비용 영향."
  type        = string
  default     = "UPDATE_FREQUENCY_MONTHLY"
}

variable "dlp_subsidiary_project_id_regex" {
  description = "Cloud SQL DLP 스캔할 자회사 프로젝트 ID regex."
  type        = string
  default     = ".*-(kis|kih)$"
}

# === Phase 4-A: Location Restrictions ===
variable "enable_resource_locations" {
  description = "gcp.resourceLocations 활성화 — 한국 데이터 주권 / 금융권 가이드라인."
  type        = bool
  default     = true
}

variable "allowed_locations" {
  description = "허용 리전/멀티리전 목록 (LIST org policy 형식)."
  type        = list(string)
  default = [
    "in:asia-northeast3-locations",
    "in:asia-locations",
  ]
}

# === Phase 4-B: Service Usage Restriction ===
variable "enable_restrict_service_usage" {
  description = "gcp.restrictServiceUsage 활성화 — 허용 API 화이트리스트."
  type        = bool
  default     = true
}

variable "allowed_services" {
  description = "조직에서 활성화 허용되는 GCP API 목록 (is:<service> 형식)."
  type        = list(string)
  default = [
    "is:cloudresourcemanager.googleapis.com",
    "is:serviceusage.googleapis.com",
    "is:iam.googleapis.com",
    "is:storage.googleapis.com",
    "is:cloudbilling.googleapis.com",
    "is:logging.googleapis.com",
    "is:monitoring.googleapis.com",
    "is:cloudkms.googleapis.com",
    "is:cloudbuild.googleapis.com",
    "is:discoveryengine.googleapis.com",
    "is:aiplatform.googleapis.com",
    "is:modelarmor.googleapis.com",
    "is:dlp.googleapis.com",
    "is:datacatalog.googleapis.com",
    "is:accesscontextmanager.googleapis.com",
    "is:compute.googleapis.com",
    "is:certificatemanager.googleapis.com",
    "is:bigquery.googleapis.com",
    "is:bigquerystorage.googleapis.com",
  ]
}

# === Phase 4-C: IAM Policies ===
variable "disable_service_account_key_creation" {
  description = "iam.disableServiceAccountKeyCreation — SA key 생성 차단."
  type        = bool
  default     = true
}

variable "disable_cross_project_service_account_usage" {
  description = "iam.disableCrossProjectServiceAccountUsage — 다른 프로젝트 SA 사용 차단."
  type        = bool
  default     = true
}

variable "disable_automatic_iam_grants_default_sa" {
  description = "iam.automaticIamGrantsForDefaultServiceAccounts — Default SA에 자동 owner 부여 차단."
  type        = bool
  default     = true
}

# === Phase 5: Domain Restriction (⚠️ mz.co.kr lock 위험) ===
variable "enable_domain_restriction" {
  description = "iam.allowedPolicyMemberDomains 활성화. ⚠️ 작업자 도메인 lock 위험. CI에는 plan-only stage만 제공."
  type        = bool
  default     = false
}

variable "allowed_member_domains" {
  description = "iam.allowedPolicyMemberDomains 허용 값. Cloud Identity customer ID (C0xxxxxx 형식)."
  type        = list(string)
  default     = []
}

# === Phase 6: SCC Premium/Enterprise 자원 ===
# 전제: SCC tier가 Premium 또는 Enterprise로 GCP Console에서 사전 활성화됨.
# CI의 enable-scc-tier 게이트 통과 후 apply-scc-notifications stage 실행.
variable "enable_phase6" {
  description = "Phase 6 (SCC notification config) 활성화. SCC Premium tier 사전 활성화 필요."
  type        = bool
  default     = false
}

variable "scc_notification_topic_name" {
  description = "SCC findings를 발송할 PubSub topic 이름."
  type        = string
  default     = "scc-findings-notifications"
}

variable "scc_notification_config_id" {
  description = "SCC notification config ID."
  type        = string
  default     = "all-active-findings"
}

variable "scc_notification_filter" {
  description = "SCC notification에 포함할 finding 필터 (CEL)."
  type        = string
  default     = "state=\"ACTIVE\" AND (severity=\"HIGH\" OR severity=\"CRITICAL\")"
}

# === Phase 6-B: SCC On-prem Forwarder (Cloud Run Job + NAT) ===
# Cloud Run Job이 주기적으로 SCC findings 조회 → Direct VPC egress → Cloud NAT
# → 고정 외부 IP로 SNAT → on-prem HTTPS endpoint로 POST.
# 별도 이미지 빌드 후 활성화 (placeholder image 그대로 두면 Job 실행 시 hello-app 동작 후 종료).

variable "enable_scc_onprem_forwarder" {
  description = "SCC on-prem forwarder 활성화. false면 VPC/NAT/Run/Scheduler 모두 0개."
  type        = bool
  default     = false
}

variable "scc_forwarder_image_uri" {
  description = "Cloud Run Service 이미지 URI. Artifact Registry로 자체 이미지 push 후 변경. 기본은 placeholder."
  type        = string
  default     = "gcr.io/google-samples/hello-app:1.0"
}

variable "scc_forwarder_onprem_host" {
  description = "on-prem 수신 서버 IP 또는 hostname."
  type        = string
  default     = ""
}

variable "scc_forwarder_onprem_port" {
  description = "on-prem 수신 TCP port."
  type        = number
  default     = 0
}

variable "scc_forwarder_tcp_timeout_sec" {
  description = "TCP 연결/전송 timeout (s)."
  type        = number
  default     = 10
}

variable "scc_forwarder_min_instance_count" {
  description = "Cloud Run Service 최소 인스턴스 수. 1+ 권장 시 latency↓ but 비용↑."
  type        = number
  default     = 0
}

variable "scc_forwarder_max_instance_count" {
  description = "Cloud Run Service 최대 인스턴스 수. SCC finding burst 대응. Direct VPC egress는 인스턴스당 subnet IP 1개를 소모하므로 scc_forwarder_vpc_cidr(/28 = 가용 ~11~12개) 한도 내로 제한."
  type        = number
  default     = 2
}

variable "scc_forwarder_vpc_cidr" {
  description = "Direct VPC egress용 subnet CIDR. Cloud Run Direct VPC egress는 인스턴스 + revision 롤아웃 IP가 필요해 /26 이상 권장(/28은 health check 'no sufficient ip' 실패). on-prem 사설망과 겹치지 않게 설정."
  type        = string
  default     = "10.200.0.0/24"
}

variable "scc_forwarder_egress_ip_name" {
  description = "Cloud NAT 고정 IP 이름. 빈 문자열이면 region에 reserved IP가 1개일 때 자동 선택. use_existing=false면 신규 생성 이름."
  type        = string
  default     = ""
}

variable "scc_forwarder_use_existing_egress_ip" {
  description = "기존 예약된 IP(같은 이름)를 lookup해 NAT에 attach. false면 terraform이 신규 생성."
  type        = bool
  default     = true
}

# Secret Manager 연동 변수는 PubSub→TCP 구조에서 제거됨 (HTTP 헤더 인증 없음).
# 추후 TCP 핸드셰이크 토큰 등 필요하면 재도입 가능.

# ─── Phase 6-C: MA 런타임 → SCC findings 브리지 ───
variable "enable_ma_runtime_findings" {
  description = "MA 런타임 탐지 → SCC findings 파이프라인. SCC Premium tier 전제(enable_phase6와 동일)."
  type        = bool
  default     = false
}

variable "ma_detections_topic_name" {
  description = "MA 탐지 로그 중앙 수집 topic 이름 (자회사 sink destination과 일치)."
  type        = string
  default     = "ma-detections"
}

variable "ma_subsidiary_project_ids" {
  description = "MA 탐지를 보내는 자회사 프로젝트 목록 — finding resourceName 매핑용."
  type        = list(string)
  default = [
    "kih-ge-prod", "kis-ge-prod", "kisb-ge-prod", "kic-ge-prod",
    "kim-ge-prod", "vam-ge-prod", "kit-ge-prod", "kip-ge-prod",
  ]
}
