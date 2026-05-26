# 조직 IAM 정책에 허용되는 멤버 도메인을 화이트리스트로 제한한다.
# (체크리스트 #9 GE App 비인가 사용자 접근 / #15 BQ Authorized Dataset 외부 공유)
#
# ⚠️ 위험: 작업자 계정의 도메인 customer ID가 allowed_member_domains에 포함되지
# 않으면 작업자 자신이 IAM 정책 변경 권한을 잃는다. 본 정책이 enforce 된 후에는
# IAM 정책 추가/삭제 시 멤버의 도메인이 화이트리스트 안에 있어야 한다.
#
# 적용 절차 (안전한 순서):
#   1. 현재 조직의 모든 운영자 도메인 customer ID 수집 (gcloud organizations list)
#   2. mz.co.kr 등 외부 도메인 작업자가 권한 정리 (정식 koreainvestment.com 계정으로 전환)
#      또는 mz.co.kr customer ID도 일시적으로 allowed_member_domains에 포함
#   3. terraform.tfvars 에서 allowed_member_domains 값 채우기
#   4. plan 결과 확인 (이 모듈에 대해 GitLab CI는 plan-only stage만 제공)
#   5. 별도 수동 apply (로컬 또는 별도 trigger):
#      cd iac && terraform apply -target=module.domain_policies
#
# 기본 enable=false라 plan/apply 시 모두 no-op (count=0).
resource "google_org_policy_policy" "allowed_policy_member_domains" {
  count = var.enable_domain_restriction ? 1 : 0

  name   = "organizations/${var.org_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = var.allowed_member_domains
      }
    }
  }
}
