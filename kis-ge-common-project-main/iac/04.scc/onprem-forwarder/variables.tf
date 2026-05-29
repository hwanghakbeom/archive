variable "enable" {
  description = "SCC on-prem forwarder 활성화. false면 모든 자원 0개."
  type        = bool
  default     = false
}

variable "project_id" {
  description = "ops project (예: kis-gemini-common-prod)."
  type        = string
}

variable "org_id" {
  description = "GCP organization ID — SCC org-level findings 조회 권한 부여 대상."
  type        = string
}

variable "region" {
  description = "리전 (예: asia-northeast3)."
  type        = string
}

variable "image_uri" {
  description = "Cloud Run Job 컨테이너 이미지 URI. 초기 placeholder는 GCP의 public hello-app. Artifact Registry 빌드 후 실제 이미지로 교체."
  type        = string
  default     = "gcr.io/google-samples/hello-app:1.0"
}

variable "schedule_cron" {
  description = "Cloud Scheduler cron 표현식. 기본: 매시 정각."
  type        = string
  default     = "0 * * * *"
}

variable "schedule_timezone" {
  description = "스케줄러 timezone."
  type        = string
  default     = "Asia/Seoul"
}

variable "scc_filter" {
  description = "SCC findings 쿼리 filter (organizations/{org}/sources/-/findings.list 파라미터)."
  type        = string
  default     = "state=\"ACTIVE\" AND (severity=\"HIGH\" OR severity=\"CRITICAL\")"
}

variable "onprem_endpoint" {
  description = "On-prem 수신 HTTPS URL. 빈 문자열이면 컨테이너 ENV에 빈 값 주입 (앱 측 가드 필요)."
  type        = string
  default     = ""
}

variable "lookback_minutes" {
  description = "각 실행에서 조회할 findings 시간 범위 (분). schedule_cron 주기보다 약간 더 길게 잡아 누락 방지."
  type        = number
  default     = 75
}

variable "vpc_cidr" {
  description = "Cloud Run Direct VPC egress용 subnet CIDR. /28 권장 (16 IP만 사용)."
  type        = string
  default     = "10.200.0.0/28"
}

variable "egress_ip_name" {
  description = "Cloud NAT 외부 정적 IP 이름. on-prem 방화벽 화이트리스트 대상."
  type        = string
  default     = "scc-forwarder-egress-ip"
}

variable "job_timeout_seconds" {
  description = "Cloud Run Job 타임아웃 (s)."
  type        = number
  default     = 600
}

variable "job_memory" {
  description = "Cloud Run Job 컨테이너 메모리."
  type        = string
  default     = "512Mi"
}

variable "job_cpu" {
  description = "Cloud Run Job 컨테이너 CPU."
  type        = string
  default     = "1"
}
