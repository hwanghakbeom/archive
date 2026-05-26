variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "disable_service_account_key_creation" {
  description = "iam.disableServiceAccountKeyCreation — SA key 생성 차단. Workload Identity Federation 권장."
  type        = bool
  default     = true
}

variable "disable_cross_project_service_account_usage" {
  description = "iam.disableCrossProjectServiceAccountUsage — 다른 프로젝트의 SA를 본 프로젝트에서 사용 차단."
  type        = bool
  default     = true
}

variable "disable_automatic_iam_grants_default_sa" {
  description = "iam.automaticIamGrantsForDefaultServiceAccounts — 새 프로젝트 생성 시 Default SA에 owner 자동 부여 차단."
  type        = bool
  default     = true
}
