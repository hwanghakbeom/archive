variable "enable" {
  description = "MA 런타임 → SCC findings 파이프라인 활성화. SCC Premium/Enterprise tier 전제 (enable_phase6와 동일)."
  type        = bool
  default     = false
}

variable "project_id" {
  description = "파이프라인(topic/함수) 배치 프로젝트 — common ops."
  type        = string
}

variable "org_id" {
  description = "SCC Source/finding이 속할 조직 ID."
  type        = string
}

variable "region" {
  description = "함수/소스버킷 리전."
  type        = string
  default     = "asia-northeast3"
}

variable "topic_name" {
  description = "중앙 수집 Pub/Sub topic 이름 (자회사 sink destination과 일치해야 함)."
  type        = string
  default     = "ma-detections"
}

variable "subsidiary_project_ids" {
  description = "탐지 로그를 보내는 자회사 프로젝트 ID 목록 — finding resourceName(프로젝트 번호) 매핑용."
  type        = list(string)
  default     = []
}
