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

data "google_project" "ops" {
  count      = var.enable_phase6 ? 1 : 0
  project_id = var.ops_project_id
}

# SCC service agent에 PubSub publisher 권한 부여 (config 생성의 precondition).
# v2 CreateNotificationConfig는 SCC 서비스 에이전트가 topic에 publish 가능해야
# 통과한다(아니면 FAILED_PRECONDITION). 따라서 config보다 먼저 부여.
# 에이전트: service-org-<ORG_ID>@gcp-sa-scc-notification.iam.gserviceaccount.com
#   SCC tier 활성화 시 자동 생성됨. 활성화 직후엔 전파 지연으로 "does not exist"가
#   날 수 있는데, 그 경우 잠시 후 재apply하면 됨 (에이전트는 곧 provisioning됨).
resource "google_pubsub_topic_iam_member" "scc_publisher" {
  count = var.enable_phase6 ? 1 : 0

  project = var.ops_project_id
  topic   = google_pubsub_topic.scc_notifications[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-org-${var.org_id}@gcp-sa-scc-notification.iam.gserviceaccount.com"

  depends_on = [google_pubsub_topic.scc_notifications]
}

# publisher IAM 전파 대기 — 부여 직후 SCC precondition 체크가 아직 못 볼 수 있음.
resource "time_sleep" "scc_publisher_propagation" {
  count = var.enable_phase6 ? 1 : 0

  create_duration = "60s"
  depends_on      = [google_pubsub_topic_iam_member.scc_publisher]
}

# SCC notification config (v2) — finding을 PubSub으로 발송.
# v1 API는 종료되어("no longer available") v2 org 리소스 사용 (location=global).
# publisher 권한 부여 + 전파 후 생성 (precondition 충족).
resource "google_scc_v2_organization_notification_config" "active_findings" {
  count = var.enable_phase6 ? 1 : 0

  config_id    = var.notification_config_id
  organization = var.org_id
  location     = "global"
  description  = var.notification_description
  pubsub_topic = google_pubsub_topic.scc_notifications[0].id

  streaming_config {
    filter = var.notification_filter
  }

  depends_on = [time_sleep.scc_publisher_propagation]
}
