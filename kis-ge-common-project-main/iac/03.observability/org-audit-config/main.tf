# 조직 전체에 ADMIN_READ + DATA_READ + DATA_WRITE 감사 로그를 강제 활성화한다.
# 모든 자회사 프로젝트가 자동으로 영향받음.
#
# 주의:
# - DATA_READ/WRITE는 비용 영향 큼. 단계적 적용 권장.
# - 본 자원이 적용된 후 자회사 stack의 google_project_iam_audit_config는
#   중복이 되므로 자회사 stack의 enable_data_access_audit = false로 두는 것을 권장.
resource "google_organization_iam_audit_config" "all_services" {
  count = var.enable_data_access_audit ? 1 : 0

  org_id  = var.org_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
