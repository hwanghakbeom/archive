# === Org identity ===
variable "org_id" {
  description = "GCP 조직 ID (숫자, 예: \"240369219899\")."
  type        = string
}

# === Provider routing ===
variable "billing_project" {
  description = "user_project_override 용 billing/quota 프로젝트. ops 프로젝트(kis-common-gcp) 권장."
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
  description = "중앙 audit bucket이 위치할 ops 프로젝트 ID (예: kis-common-gcp)."
  type        = string
}

variable "central_audit_bucket_name" {
  description = "중앙 audit 로그 GCS bucket 이름. 글로벌 유니크."
  type        = string
  default     = "kis-common-gcp-org-audit-logs"
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
  default     = "state=\"ACTIVE\" AND severity IN [\"HIGH\", \"CRITICAL\"]"
}
