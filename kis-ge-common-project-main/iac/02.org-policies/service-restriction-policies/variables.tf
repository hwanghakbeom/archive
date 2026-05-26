variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "enable_restrict_service_usage" {
  description = "gcp.restrictServiceUsage 활성화. 명시된 서비스 외 API 활성화 차단."
  type        = bool
  default     = true
}

variable "allowed_services" {
  description = "조직에서 활성화 허용되는 GCP API 목록. allowedValues 형식 (is:<service>)."
  type        = list(string)
  default = [
    # Foundation
    "is:cloudresourcemanager.googleapis.com",
    "is:serviceusage.googleapis.com",
    "is:iam.googleapis.com",
    "is:storage.googleapis.com",
    "is:cloudbilling.googleapis.com",
    "is:logging.googleapis.com",
    "is:monitoring.googleapis.com",
    "is:cloudkms.googleapis.com",
    "is:cloudbuild.googleapis.com",

    # Gemini Enterprise stack 필수 API
    "is:discoveryengine.googleapis.com",
    "is:aiplatform.googleapis.com",
    "is:modelarmor.googleapis.com",
    "is:dlp.googleapis.com",
    "is:datacatalog.googleapis.com",

    # VPC-SC
    "is:accesscontextmanager.googleapis.com",

    # 외부 LB
    "is:compute.googleapis.com",
    "is:certificatemanager.googleapis.com",

    # BigQuery (자회사 stack에서 추후 활성화 가능)
    "is:bigquery.googleapis.com",
    "is:bigquerystorage.googleapis.com",
  ]
}
