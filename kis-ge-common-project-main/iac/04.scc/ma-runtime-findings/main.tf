# Model Armor 런타임 탐지 → SCC findings 브리지 파이프라인 (④⑤ 단계).
# scctest PoC(SCC - ARCHITECTURE.md, 2026-06-06 E2E 검증)의 KIS 운영 이식.
#
# 흐름: 자회사 sink(③, 자회사 stack ma-detections-sink 모듈)
#       → 이 모듈의 중앙 topic → Cloud Function gen2 → SCC v2 findings.create
#       → 기존 notification-config(⑥, filter HIGH/ACTIVE 매치) → scc-tcp-forwarder(⑦) → 온프렘(⑧)
#
# 전제: SCC Premium/Enterprise tier 활성 (enable_phase6와 동일 전제).

data "google_project" "this" {
  count      = var.enable ? 1 : 0
  project_id = var.project_id
}

# 자회사 프로젝트 번호 lookup — finding resourceName용 (id→number 맵을 함수 env로 주입)
data "google_project" "subsidiary" {
  for_each   = var.enable ? toset(var.subsidiary_project_ids) : toset([])
  project_id = each.value
}

locals {
  project_number  = var.enable ? data.google_project.this[0].number : ""
  compute_sa      = "serviceAccount:${local.project_number}-compute@developer.gserviceaccount.com"
  pubsub_agent    = "serviceAccount:service-${local.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  project_numbers = { for k, p in data.google_project.subsidiary : k => p.number }
  # source name = organizations/{org}/sources/{source_id} → 마지막 세그먼트 추출
  scc_source_id = var.enable ? element(split("/", google_scc_v2_organization_source.ma_runtime[0].name), 3) : ""
}

# ── 중앙 수집 topic (topic-A) — 자회사 sink들의 목적지 ──
resource "google_pubsub_topic" "ma_detections" {
  count   = var.enable ? 1 : 0
  project = var.project_id
  name    = var.topic_name
}

# ── 브리지 함수 실행 SA ──
resource "google_service_account" "ma_scc_bridge" {
  count        = var.enable ? 1 : 0
  project      = var.project_id
  account_id   = "ma-scc-bridge"
  display_name = "Model Armor → SCC findings bridge"
}

# ── SCC v2 커스텀 Source (org 레벨) ──
resource "google_scc_v2_organization_source" "ma_runtime" {
  count        = var.enable ? 1 : 0
  organization = var.org_id
  display_name = "Model Armor Runtime"
  description  = "GE Model Armor 런타임 sanitize 탐지(MATCH_FOUND)를 SCC finding으로 변환 (ma-scc-bridge)"
}

# 함수 SA → Source 한정 findings 생성 권한
resource "google_scc_v2_organization_source_iam_member" "bridge_findings_editor" {
  count        = var.enable ? 1 : 0
  organization = var.org_id
  source       = local.scc_source_id
  role         = "roles/securitycenter.findingsEditor"
  member       = "serviceAccount:${google_service_account.ma_scc_bridge[0].email}"
}

# ── 함수 소스 패키징 (src/ → zip → GCS) ──
data "archive_file" "function_src" {
  count       = var.enable ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/ma-scc-bridge.zip"
}

resource "google_storage_bucket" "function_src" {
  count                       = var.enable ? 1 : 0
  project                     = var.project_id
  name                        = "${var.project_id}-ma-scc-bridge-src"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

resource "google_storage_bucket_object" "function_src" {
  count  = var.enable ? 1 : 0
  name   = "ma-scc-bridge-${data.archive_file.function_src[0].output_sha}.zip"
  bucket = google_storage_bucket.function_src[0].name
  source = data.archive_file.function_src[0].output_path
}

# ── gen2 빌드 SA(compute default) 권한 — PoC 운영노트의 빌드실패 4종 ──
resource "google_project_iam_member" "build_sa" {
  for_each = var.enable ? toset([
    "roles/cloudbuild.builds.builder",
    "roles/logging.logWriter",
    "roles/artifactregistry.writer",
    "roles/storage.objectViewer",
  ]) : toset([])
  project = var.project_id
  role    = each.value
  member  = local.compute_sa
}

# ── Cloud Function gen2 — 로그 파싱 → SCC v2 findings.create ──
resource "google_cloudfunctions2_function" "ma_scc_bridge" {
  count    = var.enable ? 1 : 0
  project  = var.project_id
  name     = "ma-scc-bridge"
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "handle"
    source {
      storage_source {
        bucket = google_storage_bucket.function_src[0].name
        object = google_storage_bucket_object.function_src[0].name
      }
    }
  }

  service_config {
    available_memory      = "256M"
    timeout_seconds       = 60
    max_instance_count    = 3
    service_account_email = google_service_account.ma_scc_bridge[0].email
    environment_variables = {
      SCC_ORG_ID             = var.org_id
      SCC_SOURCE_ID          = local.scc_source_id
      FINDING_LOCATION       = "global"
      PROJECT_NUMBERS_JSON   = jsonencode(local.project_numbers)
      DEFAULT_PROJECT_NUMBER = local.project_number
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.ma_detections[0].id
    service_account_email = google_service_account.ma_scc_bridge[0].email
    retry_policy          = "RETRY_POLICY_RETRY"
  }

  depends_on = [google_project_iam_member.build_sa]
}

# Eventarc push가 함수(내부 Run 서비스)를 호출할 수 있게 — PoC 운영노트 403(run.invoke) 대응
resource "google_cloud_run_v2_service_iam_member" "bridge_invoker" {
  count    = var.enable ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.ma_scc_bridge[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.ma_scc_bridge[0].email}"
}

# Pub/Sub 서비스 에이전트가 push OIDC 토큰을 발급할 수 있게
resource "google_service_account_iam_member" "pubsub_token_creator" {
  count              = var.enable ? 1 : 0
  service_account_id = google_service_account.ma_scc_bridge[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.pubsub_agent
}
