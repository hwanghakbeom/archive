# 조직 전체에 GCS 버킷의 public 노출을 차단한다.
# 신규 버킷에만 영향, 기존 public 버킷은 별도 점검 필요.
resource "google_org_policy_policy" "public_access_prevention" {
  count = var.enforce_public_access_prevention ? 1 : 0

  name   = "organizations/${var.org_id}/policies/storage.publicAccessPrevention"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# 조직 전체에 GCS 버킷의 ACL 사용을 차단하고 IAM만 허용한다.
# 신규 버킷에만 영향. 기존 ACL은 별도 마이그레이션 필요.
resource "google_org_policy_policy" "uniform_bucket_level_access" {
  count = var.enforce_uniform_bucket_level_access ? 1 : 0

  name   = "organizations/${var.org_id}/policies/storage.uniformBucketLevelAccess"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
