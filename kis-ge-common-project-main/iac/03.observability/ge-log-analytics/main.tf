# GE 로그 federation — 적재는 각 자회사 stack(log-analytics 모듈)이 자기 프로젝트
# BigQuery(ge_logs.{data_access,activity,obs_activity})로 수행하고, common은
# 8개 자회사 테이블을 **UNION ALL 뷰로 federation**(데이터 복제 없음).
#
# 흐름: (자회사) GCS → BQ 파티션 테이블  →  (common) cross-project UNION 뷰 → Looker Studio
#
# 전제:
#  - 각 자회사 stack에서 log-analytics 모듈 apply 완료(테이블 존재) 후 본 뷰 생성 가능.
#  - 조회 주체는 common 뷰 + 8개 자회사 ge_logs 데이터셋 read 권한 필요(또는 authorized view).
#  - 동일 리전(asia-northeast3) + 동일 perimeter(krinvest_central) 내 cross-project 조회.

locals {
  # 로그타입 => 자회사 테이블ID
  log_types = ["data_access", "activity", "obs_activity"]

  # 로그타입별 UNION ALL 쿼리 (8개 자회사 <project>.<subsidiary_dataset>.<table>)
  union_queries = {
    for t in local.log_types :
    t => join("\nUNION ALL\n", [
      for p in var.subsidiary_project_ids :
      "SELECT * FROM `${p}.${var.subsidiary_dataset_id}.${t}`"
    ])
  }
}

resource "google_bigquery_dataset" "ge_logs" {
  project       = var.bq_project_id
  dataset_id    = var.dataset_id
  location      = var.location
  friendly_name = "GE Logs (federation)"
  description   = "8개 자회사 ge_logs 테이블을 UNION ALL로 federation한 뷰. 적재는 자회사 stack에서 수행. Looker Studio 소스."
}

# federation 뷰 3종 (data_access / activity / obs_activity)
resource "google_bigquery_table" "federated" {
  for_each            = toset(local.log_types)
  project             = var.bq_project_id
  dataset_id          = google_bigquery_dataset.ge_logs.dataset_id
  table_id            = each.value
  deletion_protection = false

  view {
    query          = local.union_queries[each.value]
    use_legacy_sql = false
  }
}

# 조회 주체 → common dataset dataViewer.
# (주의: 일반 뷰라 조회자는 8개 자회사 ge_logs 데이터셋에도 read 권한 필요.
#  권한 단순화하려면 authorized view로 전환 — 자회사 dataset에서 본 뷰를 authorize.)
resource "google_bigquery_dataset_iam_member" "viewers" {
  for_each   = toset(var.viewer_members)
  project    = var.bq_project_id
  dataset_id = google_bigquery_dataset.ge_logs.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}
