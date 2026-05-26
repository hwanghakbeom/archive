output "perimeter_name" {
  description = "Service Perimeter 리소스 이름 (enable_perimeter=false면 null)."
  value       = local.enabled ? google_access_context_manager_service_perimeter.central[0].name : null
}

output "access_level_name" {
  description = "Access Level 리소스 이름 (enable_perimeter=false면 null)."
  value       = local.enabled ? google_access_context_manager_access_level.corp[0].name : null
}

output "included_projects" {
  description = "Perimeter에 포함된 자회사 프로젝트 ID 목록."
  value       = local.enabled ? var.subsidiary_project_ids : []
}
