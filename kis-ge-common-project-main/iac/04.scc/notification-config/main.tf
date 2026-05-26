# SCC Premium tier 자원 (Phase 6).
#
# 전제: SCC Premium 또는 Enterprise tier가 GCP Console에서 사전 활성화되어 있음.
# 활성화 절차:
#   1. GCP Console > Security > Security Command Center > Settings
#   2. Tier > "Activate Premium" 또는 "Activate Enterprise"
#   3. Billing account 연결 및 비용 승인 (결제 권한 있는 사용자 작업)
#   4. 활성화 완료 후 CI의 enable-scc-tier 게이트 통과 → 본 자원 apply
#
# Tier가 STANDARD인 상태에서 본 자원을 apply하면 API 오류 발생.

# SCC findings를 발송할 PubSub topic.
resource "google_pubsub_topic" "scc_notifications" {
  count = var.enable_phase6 ? 1 : 0

  project = var.ops_project_id
  name    = var.notification_topic_name
}

# SCC service agent에 PubSub publisher 권한 부여.
# SCC가 자동 생성하는 service agent: service-org-<ORG_ID>@gcp-sa-scc-notification.iam.gserviceaccount.com
data "google_project" "ops" {
  count      = var.enable_phase6 ? 1 : 0
  project_id = var.ops_project_id
}

resource "google_pubsub_topic_iam_member" "scc_publisher" {
  count = var.enable_phase6 ? 1 : 0

  project = var.ops_project_id
  topic   = google_pubsub_topic.scc_notifications[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-org-${var.org_id}@gcp-sa-scc-notification.iam.gserviceaccount.com"
}

# SCC notification config — finding을 PubSub으로 발송.
resource "google_scc_notification_config" "active_findings" {
  count = var.enable_phase6 ? 1 : 0

  config_id    = var.notification_config_id
  organization = var.org_id
  description  = var.notification_description
  pubsub_topic = google_pubsub_topic.scc_notifications[0].id

  streaming_config {
    filter = var.notification_filter
  }

  depends_on = [google_pubsub_topic_iam_member.scc_publisher]
}
