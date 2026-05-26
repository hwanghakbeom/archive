output "discovery_config_name" {
  description = "DLP Discovery Config resource name (enable=false 또는 모든 scan_targets=false면 null)."
  value       = local.discovery_enabled ? google_data_loss_prevention_discovery_config.org[0].name : null
}

output "inspect_template_id" {
  description = "Org-level Inspect Template ID (Discovery 전용, scan_targets 모두 false면 null)."
  value       = local.discovery_enabled ? google_data_loss_prevention_inspect_template.org_pii[0].id : null
}
