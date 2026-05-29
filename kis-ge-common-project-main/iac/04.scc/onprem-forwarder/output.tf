output "egress_ip_address" {
  description = "Cloud NAT 정적 외부 IP. on-prem 방화벽에 화이트리스트로 등록."
  value       = length(google_compute_address.scc_egress_nat) > 0 ? google_compute_address.scc_egress_nat[0].address : null
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
