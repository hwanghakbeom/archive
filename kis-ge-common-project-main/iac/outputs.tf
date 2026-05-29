# === Phase 1: Access Context Manager ===
output "access_policy_id" {
  description = "Access Context Manager Access Policy의 숫자 ID. 자회사 stack의 vpc_sc 모듈이 terraform_remote_state로 참조."
  value       = module.access_policy.policy_id
}

output "access_policy_name" {
  description = "Access Policy의 fully qualified name (예: accessPolicies/123456789)."
  value       = module.access_policy.policy_name
}

# Central perimeter
output "central_perimeter_name" {
  description = "통합 Service Perimeter 이름 (enable_central_perimeter=false면 null)."
  value       = module.service_perimeter.perimeter_name
}

output "perimeter_included_projects" {
  description = "Perimeter에 포함된 자회사 프로젝트 ID 목록."
  value       = module.service_perimeter.included_projects
}

# === Phase 3: Aggregated Log Sink ===
output "central_audit_bucket" {
  description = "중앙 audit 로그 GCS bucket 이름."
  value       = module.aggregated_log_sink.central_audit_bucket
}

output "aggregated_sink_writer_identity" {
  description = "Organization log sink의 unique writer SA."
  value       = module.aggregated_log_sink.sink_writer_identity
}

output "dlp_discovery_config" {
  description = "조직 레벨 DLP Discovery config 이름 (enable=false면 null)."
  value       = module.dlp_discovery.discovery_config_name
}

# === Phase 6: SCC Notification ===
output "scc_pubsub_topic" {
  description = "SCC findings notification PubSub topic 이름 (enable_phase6=false면 null)."
  value       = module.scc_notifications.pubsub_topic
}

output "scc_notification_config" {
  description = "SCC notification config 전체 이름 (enable_phase6=false면 null)."
  value       = module.scc_notifications.notification_config_name
}

# === Phase 6-B: SCC PubSub → TCP Forwarder ===
output "scc_forwarder_egress_ip" {
  description = "Cloud NAT 정적 IP — on-prem 방화벽 화이트리스트 대상 (enable=false면 null)."
  value       = module.scc_onprem_forwarder.egress_ip_address
}

output "scc_forwarder_artifact_registry" {
  description = "Cloud Run Service 이미지 push 대상 Artifact Registry repo URI."
  value       = module.scc_onprem_forwarder.artifact_registry_repo
}

output "scc_forwarder_service_name" {
  description = "Cloud Run Service 이름."
  value       = module.scc_onprem_forwarder.service_name
}

output "scc_forwarder_service_url" {
  description = "Cloud Run Service URL (PubSub push endpoint)."
  value       = module.scc_onprem_forwarder.service_url
}

output "scc_forwarder_subscription_name" {
  description = "PubSub push subscription 이름."
  value       = module.scc_onprem_forwarder.subscription_name
}

output "scc_forwarder_service_account" {
  description = "Cloud Run Service 실행용 SA."
  value       = module.scc_onprem_forwarder.forwarder_service_account_email
}
