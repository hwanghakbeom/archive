# 조직 전체에 SA key 생성 차단. Workload Identity Federation으로 대체 권장.
resource "google_org_policy_policy" "disable_sa_key_creation" {
  count = var.disable_service_account_key_creation ? 1 : 0

  name   = "organizations/${var.org_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# 다른 프로젝트의 SA를 본 프로젝트에서 attach/use 하는 행위 차단.
# 자회사 격리 + 우회 권한 부여 방지.
resource "google_org_policy_policy" "disable_cross_project_sa" {
  count = var.disable_cross_project_service_account_usage ? 1 : 0

  name   = "organizations/${var.org_id}/policies/iam.disableCrossProjectServiceAccountUsage"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# 새 프로젝트 생성 시 Compute Default SA / App Engine Default SA에 자동으로
# Editor 권한이 부여되는 GCP 기본 동작을 차단.
resource "google_org_policy_policy" "disable_auto_iam_default_sa" {
  count = var.disable_automatic_iam_grants_default_sa ? 1 : 0

  name   = "organizations/${var.org_id}/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
