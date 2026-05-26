locals {
  audit_filter = <<-EOT
    logName:"/logs/cloudaudit.googleapis.com%2Factivity"
    OR logName:"/logs/cloudaudit.googleapis.com%2Fdata_access"
    OR logName:"/logs/cloudaudit.googleapis.com%2Fsystem_event"
    OR logName:"/logs/cloudaudit.googleapis.com%2Fpolicy"
  EOT
}

# 중앙 audit GCS bucket. 모든 자회사 cloudaudit 로그가 여기로 모인다.
# 자회사별 프로젝트 단위 sink(03.observability/audit-log-export)와 병행 운영 가능
# — 자회사 sink는 자회사 운영팀이 접근, 중앙 sink는 보안팀이 접근.
resource "google_storage_bucket" "central_audit" {
  project                     = var.ops_project_id
  name                        = var.central_audit_bucket_name
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  retention_policy {
    is_locked        = var.lock_retention
    retention_period = var.retention_days * 86400 # 일 → 초
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age        = var.retention_days
      with_state = "ANY"
    }
  }
}

# Organization sink — include_children=true 로 조직 하위 모든 폴더/프로젝트
# 로그가 모인다.
resource "google_logging_organization_sink" "audit" {
  name             = var.sink_name
  org_id           = var.org_id
  include_children = true

  destination = "storage.googleapis.com/${google_storage_bucket.central_audit.name}"
  filter      = local.audit_filter
}

# Sink의 unique writer SA에 중앙 bucket 쓰기 권한 부여.
resource "google_storage_bucket_iam_member" "sink_writer" {
  bucket = google_storage_bucket.central_audit.name
  role   = "roles/storage.objectCreator"
  member = google_logging_organization_sink.audit.writer_identity
}
