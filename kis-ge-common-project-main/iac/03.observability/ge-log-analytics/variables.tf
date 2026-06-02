variable "bq_project_id" {
  description = "BigQuery 데이터셋/external table이 생성될 프로젝트 (common ops project)."
  type        = string
}

variable "location" {
  description = "BigQuery 데이터셋 location. 자회사 GCS 버킷과 동일 리전이어야 external table 가능 (asia-northeast3)."
  type        = string
  default     = "asia-northeast3"
}

variable "dataset_id" {
  description = "GE 로그 분석 데이터셋 ID."
  type        = string
  default     = "ge_logs"
}

variable "subsidiary_project_ids" {
  description = "자회사 프로젝트 ID 목록. 각 프로젝트의 audit 버킷(<id>-audit-logs)을 external table 소스로 사용."
  type        = list(string)
}

variable "viewer_members" {
  description = "external table 조회 주체 (예: user:.../group:...). dataset dataViewer + (grant_bucket_iam=true 시) 8개 버킷 objectViewer 부여."
  type        = list(string)
  default     = []
}

variable "grant_bucket_iam" {
  description = "true면 viewer_members에게 각 자회사 버킷 objectViewer를 이 stack이 직접 부여(타 프로젝트 버킷 — apply 주체에 storage.admin 필요). false면 버킷 권한은 별도(자회사 stack/수동)로 부여."
  type        = bool
  default     = false
}
