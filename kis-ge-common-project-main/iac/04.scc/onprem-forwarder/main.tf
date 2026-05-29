# ────────────────────────────────────────────────────────────────────
# Artifact Registry — 컨테이너 이미지 push 대상
# 운영자는 본인의 forwarder 이미지를 빌드해 이 repo로 push:
#   gcloud auth configure-docker ${region}-docker.pkg.dev
#   docker buildx build --platform linux/amd64 -t \
#     ${region}-docker.pkg.dev/${project_id}/scc-forwarder/forwarder:v1 .
#   docker push <위 태그>
# 이후 var.image_uri를 해당 태그로 교체 후 재apply.
# ────────────────────────────────────────────────────────────────────
resource "google_artifact_registry_repository" "scc_forwarder" {
  count = var.enable ? 1 : 0

  project       = var.project_id
  location      = var.region
  repository_id = "scc-forwarder"
  format        = "DOCKER"
  description   = "SCC on-prem forwarder Cloud Run Job 이미지"
}

# ────────────────────────────────────────────────────────────────────
# Cloud Run Job — 스케줄러가 트리거하는 batch worker
# Direct VPC egress: 모든 outbound 트래픽을 VPC subnet 경유 →
# Cloud NAT → scc_egress_nat (정적 외부 IP)로 SNAT
# ────────────────────────────────────────────────────────────────────
resource "google_cloud_run_v2_job" "scc_forwarder" {
  count = var.enable ? 1 : 0

  project  = var.project_id
  name     = "scc-forwarder"
  location = var.region

  template {
    template {
      service_account = google_service_account.scc_forwarder[0].email
      timeout         = "${var.job_timeout_seconds}s"
      max_retries     = 1

      vpc_access {
        network_interfaces {
          network    = google_compute_network.scc_egress[0].id
          subnetwork = google_compute_subnetwork.scc_egress[0].id
        }
        egress = "ALL_TRAFFIC"
      }

      containers {
        image = var.image_uri

        resources {
          limits = {
            cpu    = var.job_cpu
            memory = var.job_memory
          }
        }

        env {
          name  = "ORG_ID"
          value = var.org_id
        }
        env {
          name  = "SCC_FILTER"
          value = var.scc_filter
        }
        env {
          name  = "ONPREM_ENDPOINT"
          value = var.onprem_endpoint
        }
        env {
          name  = "LOOKBACK_MINUTES"
          value = tostring(var.lookback_minutes)
        }

        # Secret Manager에서 on-prem 인증 헤더 주입.
        # var.enable_secret=false면 ENV 미주입 → 앱은 ONPREM_AUTH_HEADER 빈 값으로 동작 (헤더 없이 POST).
        dynamic "env" {
          for_each = var.enable_secret ? [1] : []
          content {
            name = var.secret_env_var_name
            value_source {
              secret_key_ref {
                secret  = google_secret_manager_secret.onprem_auth[0].secret_id
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    # 이미지는 별도 build pipeline으로 push되고 tag(:latest 등) 갱신이
    # 빈번할 수 있으므로 terraform drift로 감지하지 않음.
    # 명시적으로 이미지 교체하려면 var.image_uri 변경 + apply.
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }

  depends_on = [
    google_compute_router_nat.scc_egress,
    google_organization_iam_member.scc_findings_viewer,
    google_secret_manager_secret_iam_member.forwarder_accessor,
  ]
}

# ────────────────────────────────────────────────────────────────────
# Cloud Scheduler — 주기적 트리거 (Cloud Run Jobs v2 :run API 호출)
# ────────────────────────────────────────────────────────────────────
resource "google_cloud_scheduler_job" "scc_forwarder" {
  count = var.enable ? 1 : 0

  project   = var.project_id
  name      = "scc-forwarder-schedule"
  region    = var.region
  schedule  = var.schedule_cron
  time_zone = var.schedule_timezone

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.scc_forwarder[0].name}:run"

    oauth_token {
      service_account_email = google_service_account.scc_scheduler[0].email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  retry_config {
    retry_count = 1
  }

  depends_on = [
    google_cloud_run_v2_job_iam_member.scheduler_invoker,
  ]
}
