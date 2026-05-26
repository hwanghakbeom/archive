variable "enable_perimeter" {
  description = "Service Perimeter 활성화. false 기본 → 자원 0개. true시 모든 subsidiary_project_ids가 perimeter 안에 포함됨."
  type        = bool
  default     = false
}

variable "access_policy_id" {
  description = "Access Policy 숫자 ID (org-stack의 access_policy 모듈 output)."
  type        = string
}

variable "subsidiary_project_ids" {
  description = "Perimeter에 포함될 자회사 GCP 프로젝트 ID 목록. data.google_project로 number 변환."
  type        = list(string)
  default     = []
}

variable "dry_run" {
  description = "true=spec(로깅만), false=status(차단). 운영 시작은 dry_run=true로 1-2주 운영 후 false."
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "Access Level이 허용할 CIDR (회사 IP / VPN)."
  type        = list(string)
  default     = []
}

variable "allowed_members" {
  description = "Access Level이 허용할 identity (user:/group:/serviceAccount:)."
  type        = list(string)
  default     = []
}

variable "ingress_identities" {
  description = "Perimeter ingress 허용 identity (Console/CLI sessions 등)."
  type        = list(string)
  default     = []
}

variable "ingress_source_projects" {
  description = "Perimeter ingress 허용 소스 프로젝트 번호."
  type        = list(string)
  default     = []
}

variable "restricted_services" {
  description = "Perimeter 안에서 제한되는 Google API."
  type        = list(string)
  default = [
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "dlp.googleapis.com",
    "cloudkms.googleapis.com",
  ]
}

variable "perimeter_name" {
  description = "Service Perimeter 이름."
  type        = string
  default     = "krinvest_central"
}

variable "access_level_name" {
  description = "Access Level 이름."
  type        = string
  default     = "corp_access"
}
