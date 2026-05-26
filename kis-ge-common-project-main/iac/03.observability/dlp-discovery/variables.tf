variable "enable_dlp_discovery" {
  description = "조직 레벨 DLP Discovery 활성화. SCC Premium tier 활성화 필수. 비용 영향 큼."
  type        = bool
  default     = false
}

variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "ops_project_id" {
  description = "DLP findings publish 대상 ops 프로젝트 ID."
  type        = string
}

variable "scan_targets" {
  description = <<-EOT
    DLP Discovery가 스캔할 자원 타입. 기본 모두 false — 사용하는 자원만
    명시적으로 true로 override. 모두 false면 enable_dlp_discovery=true 라도
    discovery config 자원이 생성되지 않는다.

    KIS 환경 기본값(모두 false) 근거:
      - bigquery       : BQ 데이터는 로그성, PII 분류 대상 아님
      - cloud_storage  : GCS 데이터는 로그성, PII 분류 대상 아님
      - cloud_sql      : Cloud SQL 미사용
    추후 PII 가능성 있는 자원 도입 시 해당 type만 true로.
  EOT
  type = object({
    bigquery      = optional(bool, false)
    cloud_sql     = optional(bool, false)
    cloud_storage = optional(bool, false)
  })
  default = {}
}

variable "cadence_frequency" {
  description = "스캔 주기 — DAILY / WEEKLY / MONTHLY. 비용 영향 (DAILY가 가장 비쌈)."
  type        = string
  default     = "UPDATE_FREQUENCY_MONTHLY"

  validation {
    condition = contains([
      "UPDATE_FREQUENCY_DAILY",
      "UPDATE_FREQUENCY_WEEKLY",
      "UPDATE_FREQUENCY_MONTHLY",
    ], var.cadence_frequency)
    error_message = "cadence_frequency must be one of: UPDATE_FREQUENCY_DAILY / WEEKLY / MONTHLY."
  }
}

variable "subsidiary_project_id_regex" {
  description = "Cloud SQL discovery에서 스캔할 자회사 프로젝트 ID regex 패턴."
  type        = string
  default     = ".*-(kis|kih)$"
}
