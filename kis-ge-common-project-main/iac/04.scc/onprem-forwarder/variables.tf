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

variable "batch_size" {
  description = "한 POST 당 findings 개수. 1 = 단건 전송 (on-prem이 단건 처리 가정). 늘리면 throughput↑, 부분 실패 시 재시도 단위 커짐."
  type        = number
  default     = 1

  validation {
    condition     = var.batch_size >= 1 && var.batch_size <= 500
    error_message = "batch_size must be 1..500."
  }
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

variable "use_existing_egress_ip" {
  description = "이미 예약된 외부 정적 IP를 data source로 lookup해 NAT에 attach (gcloud로 사전 reserve된 IP 재사용). false면 terraform이 신규 생성."
  type        = bool
  default     = true
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

# === Secret Manager 연동 (on-prem 인증 헤더) ===
variable "enable_secret" {
  description = "Secret Manager 시크릿 생성 + Cloud Run Job 환경변수 주입 활성화. false면 Cloud Run Job에 ONPREM_AUTH_HEADER ENV 미주입."
  type        = bool
  default     = false
}

variable "secret_id" {
  description = "Secret Manager secret_id (project 내 유니크). 시크릿 버전은 별도 명령으로 추가."
  type        = string
  default     = "scc-forwarder-onprem-auth"
}

variable "secret_env_var_name" {
  description = "Cloud Run Job 컨테이너에 주입할 ENV 이름. 앱(main.py)이 ONPREM_AUTH_HEADER를 사용함."
  type        = string
  default     = "ONPREM_AUTH_HEADER"
}
