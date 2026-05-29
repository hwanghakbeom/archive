# ────────────────────────────────────────────────────────────────────
# Cloud Run Service 실행용 SA
# PubSub-based 구조에선 SCC findings 직접 조회 불필요 (메시지 본문에 finding
# 데이터가 포함돼 있음) → org-level securitycenter.findingsViewer 부여 안 함.
# ────────────────────────────────────────────────────────────────────
resource "google_service_account" "scc_forwarder" {
  count = var.enable ? 1 : 0

  project      = var.project_id
  account_id   = "scc-tcp-forwarder"
  display_name = "SCC TCP Forwarder Cloud Run Service"
  description  = "PubSub push 수신 + on-prem TCP 전송"
}

# ────────────────────────────────────────────────────────────────────
# PubSub → Cloud Run 호출용 SA
# PubSub service agent가 이 SA의 OIDC token을 mint해서 Cloud Run에 Authorization 헤더로 전달.
# ────────────────────────────────────────────────────────────────────
resource "google_service_account" "scc_pubsub_pusher" {
  count = var.enable ? 1 : 0

  project      = var.project_id
  account_id   = "scc-pubsub-pusher"
  display_name = "SCC PubSub → Run Service pusher"
}

# 이 SA에 run.invoker 부여 → PubSub이 mint한 OIDC token으로 Cloud Run 호출 가능.
resource "google_cloud_run_v2_service_iam_member" "pubsub_invoker" {
  count = var.enable ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.scc_forwarder[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scc_pubsub_pusher[0].email}"
}

# PubSub service agent가 pusher SA의 token을 mint할 수 있도록 권한 부여.
# service-{PROJECT_NUM}@gcp-sa-pubsub.iam.gserviceaccount.com 패턴.
data "google_project" "this" {
  count = var.enable ? 1 : 0

  project_id = var.project_id
}

resource "google_service_account_iam_member" "pubsub_token_creator" {
  count = var.enable ? 1 : 0

  service_account_id = google_service_account.scc_pubsub_pusher[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this[0].number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
