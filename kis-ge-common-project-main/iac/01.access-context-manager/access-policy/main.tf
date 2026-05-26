# Access Context Manager Access Policy.
# 조직당 정책 1개만 허용 (GCP API 제약). 본 stack이 단독으로 관리하며
# 자회사 stack(kis-ge-project 등)은 terraform_remote_state로 이 정책의
# ID를 참조하여 자기 Service Perimeter에 첨부한다.
#
# Org-level 권한 요구: roles/accesscontextmanager.policyAdmin (조직 IAM)
#
# 주의:
# - 이미 다른 도구로 만들어진 access policy가 있다면 terraform import 필요.
# - 정책 삭제는 모든 자회사 stack의 perimeter가 제거된 후에만 가능.
resource "google_access_context_manager_access_policy" "this" {
  parent = "organizations/${var.org_id}"
  title  = var.title

  lifecycle {
    prevent_destroy = true
  }
}
