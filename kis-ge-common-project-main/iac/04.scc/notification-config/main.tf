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

# SCC notification config — finding을 PubSub으로 발송.
# ⚠️ v2 API 사용: SCC v1 NotificationConfig API는 종료됨("no longer available").
#   v2는 location 스코프(global)가 추가됨 → google_scc_v2_organization_notification_config.
# ⚠️ 순서 주의: org SCC notification 서비스 에이전트
#   (service-org-<ORG>@gcp-sa-scc-notification.iam.gserviceaccount.com)는
#   "첫 NotificationConfig 생성 시점"에 lazy하게 만들어진다 (tier 활성화만으론 X).
#   따라서 publisher IAM(scc_publisher)보다 이 리소스가 먼저 생성되어야 한다.
#   (GCP: config 생성 자체는 publisher 권한 없이 성공하고, 권한 부여 전까지 발송만 보류됨)
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

  depends_on = [google_pubsub_topic.scc_notifications]
}

# 서비스 에이전트 생성/전파 대기 — config 생성 직후엔 IAM에서 아직 안 보일 수 있음.
resource "time_sleep" "scc_agent_propagation" {
  count = var.enable_phase6 ? 1 : 0

  create_duration = "60s"
  depends_on      = [google_scc_v2_organization_notification_config.active_findings]
}

# SCC service agent에 PubSub publisher 권한 부여.
# service agent: service-org-<ORG_ID>@gcp-sa-scc-notification.iam.gserviceaccount.com
# config 생성으로 에이전트가 만들어지고 전파된 뒤 실행 (없는 SA에 binding하면 400).
resource "google_pubsub_topic_iam_member" "scc_publisher" {
  count = var.enable_phase6 ? 1 : 0

  project = var.ops_project_id
  topic   = google_pubsub_topic.scc_notifications[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-org-${var.org_id}@gcp-sa-scc-notification.iam.gserviceaccount.com"

  depends_on = [time_sleep.scc_agent_propagation]
}
