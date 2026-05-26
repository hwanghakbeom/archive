variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "enable_restrict_non_cmek" {
  description = "gcp.restrictNonCmekServices 활성화 여부. 활성화 시 cmek_required_services 목록의 서비스는 반드시 CMEK 사용."
  type        = bool
  default     = false
}

variable "cmek_required_services" {
  description = "CMEK 사용을 강제할 GCP 서비스 목록. 본 값에 명시된 서비스는 Google-managed key로 자원 생성 불가."
  type        = list(string)
  default = [
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "discoveryengine.googleapis.com",
    "aiplatform.googleapis.com",
  ]
}
