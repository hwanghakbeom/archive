output "pubsub_topic" {
  description = "SCC findings notification PubSub topic 이름."
  value       = var.enable_phase6 ? google_pubsub_topic.scc_notifications[0].name : null
}

output "notification_config_name" {
  description = "SCC notification config 전체 이름."
  value       = var.enable_phase6 ? google_scc_v2_organization_notification_config.active_findings[0].name : null
}
