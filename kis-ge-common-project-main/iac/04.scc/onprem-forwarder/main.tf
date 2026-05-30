# Artifact Registry — Cloud Run Service 이미지 push 대상.
resource "google_artifact_registry_repository" "scc_forwarder" {
  count = var.enable ? 1 : 0

  project       = var.project_id
  location      = var.region
  repository_id = "scc-forwarder"
  format        = "DOCKER"
  description   = "SCC PubSub→TCP forwarder Cloud Run Service 이미지"
}

# ─────────────────────────────────────────────────────────────────────
# Cloud Run Service — PubSub push 수신 + TCP egress
# ─────────────────────────────────────────────────────────────────────
resource "google_cloud_run_v2_service" "scc_forwarder" {
  count = var.enable ? 1 : 0

  project  = var.project_id
  name     = "scc-tcp-forwarder"
  location = var.region

  # PubSub push는 외부 HTTPS로 들어오므로 ingress=ALL + OIDC auth로 제한.
  ingress = "INGRESS_TRAFFIC_ALL"

  # 실수로 인한 서비스 삭제 방지. 삭제/교체하려면 false로 변경 후 apply.
  deletion_protection = true

  template {
    service_account = google_service_account.scc_forwarder[0].email

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    # Direct VPC egress — 모든 outbound가 VPC subnet → NAT → 고정 IP로.
    vpc_access {
      network_interfaces {
        network    = google_compute_network.scc_egress[0].id
        subnetwork = google_compute_subnetwork.scc_egress[0].id
      }
      egress = "ALL_TRAFFIC"
    }

    timeout = "${var.request_timeout_sec}s"

    containers {
      image = var.image_uri

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      env {
        name  = "ONPREM_HOST"
        value = var.onprem_host
      }
      env {
        name  = "ONPREM_PORT"
        value = tostring(var.onprem_port)
      }
      env {
        name  = "TCP_TIMEOUT_SEC"
        value = tostring(var.tcp_timeout_sec)
      }
    }
  }

  # NOTE: 이미지는 var.image_uri(태그)로 terraform이 관리한다.
  #   초기 이전엔 ignore_changes=[image]를 걸었으나, 그러면 placeholder에서
  #   실제 이미지로 갱신이 안 돼 서비스가 Ready=False에 갇혔다(uri 비어 subscription도 실패).
  #   태그 기반이라 image_uri가 바뀔 때만 새 revision 배포(in-place, destroy 없음).

  depends_on = [
    google_compute_router_nat.scc_egress,
  ]
}

# ─────────────────────────────────────────────────────────────────────
# PubSub push subscription — 기존 scc-findings-notifications topic에 attach
# ─────────────────────────────────────────────────────────────────────
resource "google_pubsub_subscription" "scc_findings" {
  count = var.enable ? 1 : 0

  project = var.project_id
  name    = "scc-findings-tcp-forwarder"
  topic   = "projects/${var.project_id}/topics/${var.pubsub_topic_name}"

  ack_deadline_seconds = 30

  push_config {
    push_endpoint = google_cloud_run_v2_service.scc_forwarder[0].uri

    oidc_token {
      service_account_email = google_service_account.scc_pubsub_pusher[0].email
    }
  }

  # 503 (TCP 실패) 시 backoff 재시도.
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # 무기한 보존 (운영 중 비활성화하더라도 만료 안 함).
  expiration_policy {
    ttl = ""
  }

  depends_on = [
    google_cloud_run_v2_service_iam_member.pubsub_invoker,
    google_service_account_iam_member.pubsub_token_creator,
  ]
}
