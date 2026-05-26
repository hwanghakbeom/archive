# 조직에서 활성화 가능한 GCP API를 화이트리스트로 제한한다.
# Gemini Enterprise stack 운영에 필요한 API + 일반 기반 API 목록.
#
# 주의: 본 정책 활성화 후 새로운 API를 사용하려면 allowed_services에
# 명시적으로 추가해야 한다. 누락 시 자회사 stack의 apply-bootstrap 실패.
resource "google_org_policy_policy" "restrict_service_usage" {
  count = var.enable_restrict_service_usage ? 1 : 0

  name   = "organizations/${var.org_id}/policies/gcp.restrictServiceUsage"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = var.allowed_services
      }
    }
  }
}
