# ────────────────────────────────────────────────────────────────────
# Cloud Run Job 실행용 SA — SCC findings 조회 + on-prem 호출
# ────────────────────────────────────────────────────────────────────
resource "google_service_account" "scc_forwarder" {
  count = var.enable ? 1 : 0

  project      = var.project_id
  account_id   = "scc-forwarder-job"
  display_name = "SCC On-prem Forwarder Job"
  description  = "Cloud Run Job이 SCC findings 조회 및 on-prem 전송 시 사용"
}

# org-level: SCC findings 조회 권한 (organizations/{org}/sources/-/findings.list)
resource "google_organization_iam_member" "scc_findings_viewer" {
  count = var.enable ? 1 : 0

  org_id = var.org_id
  role   = "roles/securitycenter.findingsViewer"
  member = "serviceAccount:${google_service_account.scc_forwarder[0].email}"
}

# ────────────────────────────────────────────────────────────────────
# Cloud Scheduler용 SA — Cloud Run Job 호출
# ────────────────────────────────────────────────────────────────────
resource "google_service_account" "scc_scheduler" {
  count = var.enable ? 1 : 0

  project      = var.project_id
  account_id   = "scc-forwarder-scheduler"
  display_name = "SCC Forwarder Scheduler Invoker"
}

# Scheduler가 특정 Cloud Run Job 실행 권한 보유
resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  count = var.enable ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.scc_forwarder[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scc_scheduler[0].email}"
}
