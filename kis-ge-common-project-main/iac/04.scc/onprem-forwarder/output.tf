output "egress_ip_address" {
  description = "Cloud NAT 정적 외부 IP. on-prem 방화벽에 화이트리스트로 등록."
  value       = local.egress_ip_address
}

output "artifact_registry_repo" {
  description = "Cloud Run Service 이미지 push 대상 Artifact Registry repo URI."
  value       = length(google_artifact_registry_repository.scc_forwarder) > 0 ? "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.scc_forwarder[0].repository_id}" : null
}

output "service_name" {
  description = "Cloud Run Service 이름."
  value       = length(google_cloud_run_v2_service.scc_forwarder) > 0 ? google_cloud_run_v2_service.scc_forwarder[0].name : null
}

output "service_url" {
  description = "Cloud Run Service URL (PubSub push_endpoint로 사용)."
  value       = length(google_cloud_run_v2_service.scc_forwarder) > 0 ? google_cloud_run_v2_service.scc_forwarder[0].uri : null
}

output "subscription_name" {
  description = "PubSub push subscription 이름."
  value       = length(google_pubsub_subscription.scc_findings) > 0 ? google_pubsub_subscription.scc_findings[0].name : null
}

output "forwarder_service_account_email" {
  description = "Cloud Run Service 실행용 SA."
  value       = length(google_service_account.scc_forwarder) > 0 ? google_service_account.scc_forwarder[0].email : null
}

output "pubsub_pusher_service_account_email" {
  description = "PubSub → Run 호출용 SA."
  value       = length(google_service_account.scc_pubsub_pusher) > 0 ? google_service_account.scc_pubsub_pusher[0].email : null
}
