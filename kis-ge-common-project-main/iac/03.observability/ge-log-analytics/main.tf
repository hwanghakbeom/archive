# GE 로그 분석 — 8개 자회사 GCS 버킷(audit/data_access/observability)을
# common 프로젝트의 BigQuery 네이티브 파티션 테이블로 sync(적재).
#
# 흐름: 각 자회사 sink → 자기 GCS 버킷 <id>-audit-logs (NDJSON)
#        → BigQuery Data Transfer Service(GCS→BQ, 주기적 load)
#        → common BQ 네이티브 테이블(DAY 파티션, JSON 컬럼) → 뷰 → Looker Studio
#
# 설계 포인트:
#  - external table 아님 → 네이티브 테이블로 적재(쿼리 빠름, 파티션 pruning 가능).
#  - 각 테이블 DAY 파티션(field=timestamp = 이벤트 시각) → 비용/성능 최적.
#  - 중첩 구조(protoPayload/jsonPayload)는 JSON 타입 컬럼으로 흡수 → 스키마 변화에 견고.
#  - 로그타입(3) × 자회사 버킷(8) = transfer config 24개 (write_disposition=APPEND, 파일 중복 적재 방지).

data "google_project" "bq" {
  project_id = var.bq_project_id
}

locals {
  buckets = [for p in var.subsidiary_project_ids : "${p}-audit-logs"]

  # 테이블ID => GCS 로그 폴더(logName 경로)
  log_types = {
    obs_activity = "discoveryengine.googleapis.com/gemini_enterprise_user_activity"
    data_access  = "cloudaudit.googleapis.com/data_access"
    activity     = "cloudaudit.googleapis.com/activity"
  }

  # (로그타입 × 버킷) transfer 정의
  transfers = {
    for pair in setproduct(keys(local.log_types), local.buckets) :
    "${pair[0]}__${replace(pair[1], ".", "_")}" => {
      table = pair[0]
      uri   = "gs://${pair[1]}/${local.log_types[pair[0]]}/*"
    }
  }

  # LogEntry 공통 스키마 — 중첩부는 JSON 타입으로 흡수(audit=protoPayload / observability=jsonPayload).
  log_schema = jsonencode([
    { name = "timestamp", type = "TIMESTAMP" },
    { name = "receiveTimestamp", type = "TIMESTAMP" },
    { name = "logName", type = "STRING" },
    { name = "insertId", type = "STRING" },
    { name = "severity", type = "STRING" },
    { name = "resource", type = "JSON" },
    { name = "labels", type = "JSON" },
    { name = "operation", type = "JSON" },
    { name = "protoPayload", type = "JSON" },
    { name = "jsonPayload", type = "JSON" },
  ])

  # DTS 서비스 에이전트 (GCS 읽기 권한 필요)
  dts_sa = "serviceAccount:service-${data.google_project.bq.number}@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com"
}

resource "google_bigquery_dataset" "ge_logs" {
  project       = var.bq_project_id
  dataset_id    = var.dataset_id
  location      = var.location
  friendly_name = "GE Logs"
  description   = "8개 자회사 GCS 로그(audit/data_access/observability)를 sync한 네이티브 파티션 테이블. Looker Studio 소스."
}

# --- 네이티브 파티션 테이블 (로그타입 3종) ---
resource "google_bigquery_table" "logs" {
  for_each            = local.log_types
  project             = var.bq_project_id
  dataset_id          = google_bigquery_dataset.ge_logs.dataset_id
  table_id            = each.key
  deletion_protection = false
  schema              = local.log_schema

  # 이벤트 시각(timestamp) 기준 DAY 파티션.
  time_partitioning {
    type          = "DAY"
    field         = "timestamp"
    expiration_ms = var.partition_expiration_days > 0 ? var.partition_expiration_days * 86400000 : null
  }
  require_partition_filter = var.require_partition_filter

  # 자회사(project) 단위 조회가 많으면 logName 클러스터링으로 가속.
  clustering = ["logName"]
}

# --- GCS → BQ sync (Data Transfer Service, 로그타입 × 버킷) ---
resource "google_bigquery_data_transfer_config" "gcs_to_bq" {
  for_each = local.transfers

  project                = var.bq_project_id
  location               = var.location
  display_name           = "ge-sync-${each.key}"
  data_source_id         = "google_cloud_storage"
  destination_dataset_id = google_bigquery_dataset.ge_logs.dataset_id
  schedule               = var.sync_schedule

  params = {
    data_path_template              = each.value.uri
    destination_table_name_template = each.value.table
    file_format                     = "JSON"
    write_disposition               = "APPEND"
    max_bad_records                 = "0"
    ignore_unknown_values           = "true"
    delete_source_files             = "false"
  }

  depends_on = [google_bigquery_table.logs]
}

# --- IAM ---

# DTS 서비스 에이전트 → 8개 자회사 버킷 읽기 (GCS load). grant_bucket_iam=true 시 부여.
resource "google_storage_bucket_iam_member" "dts_reader" {
  for_each = var.grant_bucket_iam ? toset(local.buckets) : toset([])
  bucket   = each.value
  role     = "roles/storage.objectViewer"
  member   = local.dts_sa
}

# 조회 주체 → dataset dataViewer.
resource "google_bigquery_dataset_iam_member" "viewers" {
  for_each   = toset(var.viewer_members)
  project    = var.bq_project_id
  dataset_id = google_bigquery_dataset.ge_logs.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}
