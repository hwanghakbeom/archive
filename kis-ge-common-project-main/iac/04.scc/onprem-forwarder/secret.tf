# On-prem endpoint 인증용 시크릿.
# 운영자는 terraform apply 후 별도 명령으로 시크릿 버전을 추가해야 함:
#   echo -n "Authorization: Bearer <TOKEN>" | gcloud secrets versions add \
#     scc-forwarder-onprem-auth --data-file=- \
#     --project=kis-gemini-common-prod
#
# 또는 HMAC key, Basic auth("Basic base64(user:pass)") 등 헤더 한 줄 형식으로.
# 앱은 ":"가 있으면 header_name:header_value로 split, 없으면 Authorization 헤더로 인식.

resource "google_secret_manager_secret" "onprem_auth" {
  count = var.enable && var.enable_secret ? 1 : 0

  project   = var.project_id
  secret_id = var.secret_id

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

# Cloud Run Job SA에 시크릿 read 권한
resource "google_secret_manager_secret_iam_member" "forwarder_accessor" {
  count = var.enable && var.enable_secret ? 1 : 0

  project   = var.project_id
  secret_id = google_secret_manager_secret.onprem_auth[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.scc_forwarder[0].email}"
}
