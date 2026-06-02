variable "bq_project_id" {
  description = "federation 뷰가 생성될 프로젝트 (common ops project)."
  type        = string
}

variable "location" {
  description = "BigQuery 데이터셋 location. 자회사 테이블과 동일 리전(asia-northeast3)."
  type        = string
  default     = "asia-northeast3"
}

variable "dataset_id" {
  description = "common federation 데이터셋 ID."
  type        = string
  default     = "ge_logs"
}

variable "subsidiary_project_ids" {
  description = "자회사 프로젝트 ID 목록. 각 프로젝트의 <subsidiary_dataset_id> 테이블을 UNION federation."
  type        = list(string)
}

variable "subsidiary_dataset_id" {
  description = "자회사 stack(log-analytics)이 만든 데이터셋 ID. 기본 ge_logs."
  type        = string
  default     = "ge_logs"
}

variable "viewer_members" {
  description = "federation 뷰 조회 주체 (user:/group:). common dataset dataViewer 부여. (일반 뷰라 자회사 데이터셋 read도 필요)"
  type        = list(string)
  default     = []
}
