variable "enable_phase6" {
  description = "Phase 6 자원 활성화 마스터 토글. SCC Premium tier가 GCP Console에서 사전 활성화되어 있어야 함."
  type        = bool
  default     = false
}

variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "ops_project_id" {
  description = "PubSub topic이 위치할 ops 프로젝트 ID."
  type        = string
}

variable "notification_topic_name" {
  description = "SCC findings를 발송할 PubSub topic 이름."
  type        = string
  default     = "scc-findings-notifications"
}

variable "notification_config_id" {
  description = "SCC notification config ID (조직 내 유니크)."
  type        = string
  default     = "all-active-findings"
}

variable "notification_filter" {
  description = "Notification에 포함할 finding 필터. CEL 표현식."
  type        = string
  default     = "state=\"ACTIVE\" AND severity IN [\"HIGH\", \"CRITICAL\"]"
}

variable "notification_description" {
  description = "Notification config 설명."
  type        = string
  default     = "Active HIGH/CRITICAL SCC findings → PubSub (SIEM/Slack/Email 연동용)"
}
