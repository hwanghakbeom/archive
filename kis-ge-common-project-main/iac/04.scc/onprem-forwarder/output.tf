output "egress_ip_address" {
  description = "Cloud NAT 정적 외부 IP. on-prem 방화벽에 화이트리스트로 등록. (data lookup or 신규 생성, enable=false면 null)"
  value       = local.egress_ip_address
}

output "artifact_registry_repo" {
  description = "Cloud Run Job 이미지 push 대상 Artifact Registry repo URI."
  value       = length(google_artifact_registry_repository.scc_forwarder) > 0 ? "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.scc_forwarder[0].repository_id}" : null
}

output "job_name" {
  description = "생성된 Cloud Run Job 이름."
  value       = length(google_cloud_run_v2_job.scc_forwarder) > 0 ? google_cloud_run_v2_job.scc_forwarder[0].name : null
}

output "scheduler_job_name" {
  description = "Cloud Scheduler 이름."
  value       = length(google_cloud_scheduler_job.scc_forwarder) > 0 ? google_cloud_scheduler_job.scc_forwarder[0].name : null
}

output "forwarder_service_account_email" {
  description = "Cloud Run Job 실행용 SA. (debugging용)"
  value       = length(google_service_account.scc_forwarder) > 0 ? google_service_account.scc_forwarder[0].email : null
}

output "secret_id" {
  description = "On-prem 인증 시크릿 ID. 시크릿 버전 추가 명령에 사용."
  value       = length(google_secret_manager_secret.onprem_auth) > 0 ? google_secret_manager_secret.onprem_auth[0].secret_id : null
}

output "add_secret_version_command" {
  description = "Secret 첫 버전 추가 명령 (헬퍼)."
  value = length(google_secret_manager_secret.onprem_auth) > 0 ? join(" ", [
    "echo -n '<HEADER_VALUE_HERE>' | gcloud secrets versions add",
    google_secret_manager_secret.onprem_auth[0].secret_id,
    "--data-file=-",
    "--project=${var.project_id}"
  ]) : null
}
