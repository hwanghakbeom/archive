# =============================================================
# 필수 GCP API 활성화 (ops/billing project 기준)
# user_project_override = true 라서 org-level API 호출도 billing_project로
# quota 라우팅됨 → 해당 API들을 billing_project에 활성화해야 함.
#
# 각 module이 depends_on 으로 이걸 참조하므로, CI의 -target=module.X 실행
# 시에도 API 활성화가 먼저 일어남.
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
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_services)

  project = var.billing_project
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}
