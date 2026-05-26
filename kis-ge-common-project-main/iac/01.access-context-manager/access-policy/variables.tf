variable "org_id" {
  description = "GCP 조직 ID (숫자)."
  type        = string
}

variable "title" {
  description = "Access Policy의 title. 조직당 1개만 허용."
  type        = string
}
