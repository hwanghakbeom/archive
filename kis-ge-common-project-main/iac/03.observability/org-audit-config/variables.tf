variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "enable_data_access_audit" {
  description = "조직 전체에 DATA_READ + DATA_WRITE 감사 로그 강제 활성화 여부. 비용 영향 있음."
  type        = bool
  default     = false
}
