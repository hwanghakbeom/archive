variable "enable" {
  description = "SCC TCP forwarder 활성화. false면 모든 자원 0개."
  type        = bool
  default     = false
}

variable "project_id" {
  description = "ops project (예: kis-gemini-common-prod). PubSub topic도 같은 프로젝트에 있어야 함."
  type        = string
}

variable "region" {
  description = "리전 (예: asia-northeast3)."
  type        = string
}

variable "image_uri" {
  description = "Cloud Run Service 컨테이너 이미지 URI. 빌드 후 AR push한 본인 이미지로 교체."
  type        = string
  default     = "gcr.io/google-samples/hello-app:1.0" # placeholder (실제 동작은 빌드한 이미지)
}

variable "pubsub_topic_name" {
  description = "SCC notification config가 publish하는 PubSub topic 이름 (같은 project_id 내). scc_notifications 모듈의 notification_topic_name과 일치해야 함."
  type        = string
  default     = "scc-findings-notifications"
}

# === on-prem TCP target ===
variable "onprem_host" {
  description = "on-prem 수신 서버 IP 또는 hostname (DNS 해석 가능해야 함)."
  type        = string
  default     = ""
}

variable "onprem_port" {
  description = "on-prem 수신 TCP port."
  type        = number
  default     = 0
}

variable "tcp_timeout_sec" {
  description = "TCP 연결/전송 timeout (s)."
  type        = number
  default     = 10
}

# === Cloud Run Service tuning ===
variable "request_timeout_sec" {
  description = "Cloud Run Service request timeout (s). PubSub push 한 건당 처리 시간 한도."
  type        = number
  default     = 30
}

variable "cpu" {
  description = "Cloud Run Service 컨테이너 CPU."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Cloud Run Service 컨테이너 메모리."
  type        = string
  default     = "512Mi"
}

variable "min_instance_count" {
  description = "최소 인스턴스 수. 0 = scale to zero (cost↓). 1+ = always warm (latency↓)."
  type        = number
  default     = 0
}

variable "max_instance_count" {
  description = "최대 인스턴스 수. SCC finding burst 대비."
  type        = number
  default     = 10
}

# === Network ===
variable "vpc_cidr" {
  description = "Direct VPC egress용 subnet CIDR. on-prem 사설망과 겹치지 않게."
  type        = string
  default     = "10.200.0.0/28"
}

variable "egress_ip_name" {
  description = "Cloud NAT 외부 정적 IP 이름. 빈 문자열이면 region 내 reserved IP가 정확히 1개일 때 자동 선택. use_existing_egress_ip=false면 신규 생성 이름."
  type        = string
  default     = ""
}

variable "use_existing_egress_ip" {
  description = "이미 예약된 IP를 data로 lookup해 NAT에 attach. false면 terraform이 신규 생성."
  type        = bool
  default     = true
}
