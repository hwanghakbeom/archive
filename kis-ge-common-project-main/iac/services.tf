# =============================================================
# 필수 GCP API 활성화 (ops/billing project 기준)
# user_project_override = true 라서 org-level API 호출도 billing_project로
# quota 라우팅됨 → 해당 API들을 billing_project에 활성화해야 함.
#
# CI의 `apply-services` job(-target=google_project_service.required)으로
# 한 번만 활성화. 이후 다른 apply job들은 depends_on 없이 자기 모듈만 처리
# (매 job마다 10개 서비스 refresh 안 해서 빠름). apply-services를 먼저 실행할 것.
# =============================================================
locals {
  required_services = [
    "serviceusage.googleapis.com",         # API enable 자체
    "cloudresourcemanager.googleapis.com", # provider / org metadata
    "accesscontextmanager.googleapis.com", # Phase 1 (Access Policy / Perimeter)
    "orgpolicy.googleapis.com",            # Phase 2 (Org Policies)
    "logging.googleapis.com",              # Phase 3 (Org Log Sink)
    "storage.googleapis.com",              # Phase 3 (Audit Bucket)
    "iam.googleapis.com",                  # Phase 3-B (Audit Config)
    "securitycenter.googleapis.com",       # Phase 6 (SCC, 선택)
    "pubsub.googleapis.com",               # Phase 6 (SCC notification, 선택)
    "dlp.googleapis.com",                  # DLP Discovery (선택)
    # ─── GE provider의 billing_project=kis-gemini-common-prod + user_project_override
    # 때문에 GE side API 호출의 quota가 여기로 라우팅됨.
    # resource project(kis-ge-prod) 뿐 아니라 quota project(여기)에도
    # 활성화돼야 "API has not been used in project kis-gemini-common-prod" 회피.
    "discoveryengine.googleapis.com", # Gemini Enterprise
    "modelarmor.googleapis.com",      # Model Armor 템플릿
    "aiplatform.googleapis.com",      # Vertex AI (향후 Agent / Reasoning Engine)
    "cloudkms.googleapis.com",        # KMS
    "datacatalog.googleapis.com",     # Data Catalog
    # ─── Phase 6-B: SCC On-prem Forwarder (Cloud Run Job + NAT 고정 IP)
    "run.googleapis.com",              # Cloud Run Jobs
    "cloudscheduler.googleapis.com",   # cron 트리거
    "artifactregistry.googleapis.com", # 컨테이너 이미지 repo
    "compute.googleapis.com",          # VPC / Router / NAT / 고정 IP
    "secretmanager.googleapis.com",    # on-prem 인증 시크릿
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_services)

  project = var.billing_project
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}
