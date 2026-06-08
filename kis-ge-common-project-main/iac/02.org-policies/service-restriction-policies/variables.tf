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
    # GCS→BQ 로그 적재 (자회사 log-analytics 모듈의 Data Transfer Service).
    # 누락 시 transfer config 생성이 403 "resource usage restriction violated".
    "is:bigquerydatatransfer.googleapis.com",

    # SCC + on-prem forwarder (기존 04.scc/notification-config, onprem-forwarder).
    # ⚠️ 아래는 effective org policy(2026-06-08 실측)엔 있었으나 IaC default엔
    #    누락돼 있던 항목 — 동기화. 빠지면 기존 forwarder(run)/notification(scc) 마비.
    "is:securitycenter.googleapis.com",
    "is:securitycentermanagement.googleapis.com",
    "is:pubsub.googleapis.com",
    "is:run.googleapis.com",
    "is:artifactregistry.googleapis.com",
    "is:cloudasset.googleapis.com",
    "is:clouderrorreporting.googleapis.com",

    # MA 런타임 → SCC 브리지 (04.scc/ma-runtime-findings, gen2 Cloud Function).
    # cloudfunctions/eventarc는 effective에도 없던 신규 — 누락 시 함수 배포 403.
    "is:cloudfunctions.googleapis.com",
    "is:eventarc.googleapis.com",
  ]
}
