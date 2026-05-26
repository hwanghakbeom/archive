variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "ops_project_id" {
  description = "중앙 audit bucket이 위치할 ops 프로젝트 ID."
  type        = string
}

variable "central_audit_bucket_name" {
  description = "중앙 audit 로그 저장 GCS bucket 이름. 글로벌 유니크."
  type        = string
}

variable "region" {
  description = "Audit bucket location."
  type        = string
}

variable "retention_days" {
  description = "감사 로그 보관 일수. 2555 = 7년."
  type        = number
  default     = 2555
}

variable "lock_retention" {
  description = "Retention policy 잠금 (IRREVERSIBLE). 사인오프 후 true."
  type        = bool
  default     = false
}

variable "sink_name" {
  description = "Organization log sink 이름."
  type        = string
  default     = "krinvest-org-audit-to-gcs"
}
