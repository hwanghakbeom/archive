output "policy_id" {
  description = "Access Policy의 숫자 ID (예: \"123456789\"). 자회사 stack이 perimeter에서 참조."
  value       = google_access_context_manager_access_policy.this.name
}

output "policy_name" {
  description = "Access Policy의 fully qualified name (예: \"accessPolicies/123456789\")."
  value       = "accessPolicies/${google_access_context_manager_access_policy.this.name}"
}
