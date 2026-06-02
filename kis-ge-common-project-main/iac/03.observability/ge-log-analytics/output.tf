output "dataset_id" {
  value = google_bigquery_dataset.ge_logs.dataset_id
}

output "federated_views" {
  description = "8개 자회사 테이블을 UNION한 federation 뷰."
  value       = { for k, t in google_bigquery_table.federated : k => t.table_id }
}

output "federated_projects" {
  value = var.subsidiary_project_ids
}

output "bq_console_url" {
  value = "https://console.cloud.google.com/bigquery?project=${var.bq_project_id}&ws=!1m4!1m3!3m2!1s${var.bq_project_id}!2s${var.dataset_id}"
}
