# =============================================================
# Import blocks — 이미 org에 존재하는 자원을 state로 흡수 (brownfield).
# koreainvestment.com org는 GCP secure-by-default로 일부 정책이 이미
# 설정돼 있어, terraform 신규 생성 시 409(already exists) 발생.
# import 후 terraform이 관리하며, 설정이 같으면 no-op.
#
# import 성공 후에는 이 파일을 삭제해도 됨 (state에 이미 들어가므로).
# enforce_* = true 기본이라 count[0] 인스턴스가 존재.
# =============================================================

import {
  to = module.storage_policies.google_org_policy_policy.public_access_prevention[0]
  id = "organizations/457872813001/policies/storage.publicAccessPrevention"
}

import {
  to = module.storage_policies.google_org_policy_policy.uniform_bucket_level_access[0]
  id = "organizations/457872813001/policies/storage.uniformBucketLevelAccess"
}

# ── IAM org policies (secure-by-default로 이미 존재 가능) ──
import {
  to = module.iam_policies.google_org_policy_policy.disable_sa_key_creation[0]
  id = "organizations/457872813001/policies/iam.disableServiceAccountKeyCreation"
}

import {
  to = module.iam_policies.google_org_policy_policy.disable_cross_project_sa[0]
  id = "organizations/457872813001/policies/iam.disableCrossProjectServiceAccountUsage"
}

import {
  to = module.iam_policies.google_org_policy_policy.disable_auto_iam_default_sa[0]
  id = "organizations/457872813001/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
}
