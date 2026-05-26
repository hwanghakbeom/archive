# 명시된 서비스에 대해 CMEK 사용을 강제한다 (Google-managed key 거부).
# 활성화 시 신규 자원만 영향. 기존 자원은 별도 재생성/마이그레이션 필요.
#
# 주의: 자회사 stack(kis-ge-project 등)의 KMS keyring + key가 이미 생성되어
# 있어야 신규 자원이 정상 적용 가능 (kis-ge-project의 02.security/kms 모듈).
resource "google_org_policy_policy" "restrict_non_cmek_services" {
  count = var.enable_restrict_non_cmek ? 1 : 0

  name   = "organizations/${var.org_id}/policies/gcp.restrictNonCmekServices"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        denied_values = var.cmek_required_services
      }
    }
  }
}
