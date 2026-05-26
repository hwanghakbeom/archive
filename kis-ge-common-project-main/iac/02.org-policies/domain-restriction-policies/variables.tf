variable "org_id" {
  description = "GCP 조직 ID."
  type        = string
}

variable "enable_domain_restriction" {
  description = "iam.allowedPolicyMemberDomains 활성화 여부. ⚠️ 작업자 도메인이 allowed_member_domains에 포함되지 않으면 즉시 IAM 사용 불가."
  type        = bool
  default     = false
}

variable "allowed_member_domains" {
  description = <<-EOT
    iam.allowedPolicyMemberDomains의 허용 값. Cloud Identity customer ID
    (C0xxxxxx 형식). 도메인 자체가 아닌 customer ID이며 다음 명령으로 확인:

      gcloud organizations list  # 조직의 customer_id 컬럼 확인
      또는
      gcloud identity customers describe customers/<id>

    예시: ["C0abc1234"] — koreainvestment.com의 Cloud Identity customer ID.

    ⚠️ 작업자 계정의 도메인 customer ID가 누락되면 작업자가 IAM 정책 변경 불가
    상태로 lock 됨. 활성화 전 반드시 모든 KRInvest 운영자 도메인 customer ID
    포함 + mz.co.kr 외부 작업자 정리 또는 임시 추가 필요.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.allowed_member_domains) > 0 || true
    error_message = "allowed_member_domains에 최소 1개의 Cloud Identity customer ID가 필요. 활성화 전 작업자 도메인 customer ID 확인 필수."
  }
}
