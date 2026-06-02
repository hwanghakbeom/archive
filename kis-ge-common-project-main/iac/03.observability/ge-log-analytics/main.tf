# GE 로그 분석 — common 프로젝트에서 8개 자회사 GCS 버킷을 가리키는 BigQuery
# 일반(External, BigLake 미사용) external table.
#
# 구조: 각 자회사 sink(audit-log-export)가 자기 버킷 <id>-audit-logs 에
#   audit/data_access/observability 로그(NDJSON)를 적재 → 여기서 external table로 페더레이션.
#
# 주의:
#  - BigLake connection 없음 → 조회 주체(viewer_members)가 각 버킷에 storage.objectViewer 직접 보유해야 함.
#  - 데이터셋 location == 버킷 location(asia-northeast3) 이어야 함.
#  - external table은 GCS의 NDJSON을 직접 읽음(데이터 복제 없음). Cloud Logging GCS는
#    YYYY/MM/DD 폴더(hive 아님)라 파티션 pruning 불가 → 날짜는 JSON timestamp로 필터.

locals {
  buckets = [for p in var.subsidiary_project_ids : "${p}-audit-logs"]

  obs_uris = [for b in local.buckets : "gs://${b}/discoveryengine.googleapis.com/gemini_enterprise_user_activity/*"]
  da_uris  = [for b in local.buckets : "gs://${b}/cloudaudit.googleapis.com/data_access/*"]
  act_uris = [for b in local.buckets : "gs://${b}/cloudaudit.googleapis.com/activity/*"]

  # viewer_members × buckets — grant_bucket_iam=true 일 때만 cross-project 버킷 IAM 부여.
  bucket_grants = var.grant_bucket_iam ? {
    for pair in setproduct(local.buckets, var.viewer_members) :
    "${pair[0]}|${pair[1]}" => { bucket = pair[0], member = pair[1] }
  } : {}
}

resource "google_bigquery_dataset" "ge_logs" {
  project       = var.bq_project_id
  dataset_id    = var.dataset_id
  location      = var.location
  friendly_name = "GE Logs (external)"
  description   = "8개 자회사 GCS audit 버킷(audit/data_access/observability)을 external table로 조회. Looker Studio 소스."
}

# --- External tables (자회사 8개 버킷 멀티-URI) ---

resource "google_bigquery_table" "obs_activity" {
  project             = var.bq_project_id
  dataset_id          = google_bigquery_dataset.ge_logs.dataset_id
  table_id            = "obs_activity_ext"
  deletion_protection = false
  description         = "GE observability 로그(gemini_enterprise_user_activity) — 질문/세션/에이전트 상세."

  external_data_configuration {
    autodetect            = true
    source_format         = "NEWLINE_DELIMITED_JSON"
    source_uris           = local.obs_uris
    ignore_unknown_values = true
  }
}

resource "google_bigquery_table" "data_access" {
  project             = var.bq_project_id
  dataset_id          = google_bigquery_dataset.ge_logs.dataset_id
  table_id            = "data_access_ext"
  deletion_protection = false
  description         = "Data Access 감사로그(discoveryengine 사용/조회)."

  external_data_configuration {
    autodetect            = true
    source_format         = "NEWLINE_DELIMITED_JSON"
    source_uris           = local.da_uris
    ignore_unknown_values = true
  }
}

resource "google_bigquery_table" "activity" {
  project             = var.bq_project_id
  dataset_id          = google_bigquery_dataset.ge_logs.dataset_id
  table_id            = "activity_ext"
  deletion_protection = false
  description         = "Admin Activity 감사로그(쓰기/관리 동작)."

  external_data_configuration {
    autodetect            = true
    source_format         = "NEWLINE_DELIMITED_JSON"
    source_uris           = local.act_uris
    ignore_unknown_values = true
  }
}

# --- 조회 권한 ---

resource "google_bigquery_dataset_iam_member" "viewers" {
  for_each   = toset(var.viewer_members)
  project    = var.bq_project_id
  dataset_id = google_bigquery_dataset.ge_logs.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}

# 일반 external table은 조회 주체 본인 자격으로 GCS를 읽음 → 각 버킷 objectViewer 필요.
# grant_bucket_iam=true 일 때만 이 stack이 부여(타 프로젝트 버킷 — 권한 필요).
resource "google_storage_bucket_iam_member" "viewer_bucket" {
  for_each = local.bucket_grants
  bucket   = each.value.bucket
  role     = "roles/storage.objectViewer"
  member   = each.value.member
}
