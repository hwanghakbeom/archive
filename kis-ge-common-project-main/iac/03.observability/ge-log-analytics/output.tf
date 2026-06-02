output "dataset_id" {
  value = google_bigquery_dataset.ge_logs.dataset_id
}

output "tables" {
  description = "네이티브 파티션 테이블 (DAY, field=timestamp)."
  value       = { for k, t in google_bigquery_table.logs : k => t.table_id }
}

output "transfer_configs" {
  description = "GCS→BQ Data Transfer config 수 (로그타입 × 버킷)."
  value       = length(google_bigquery_data_transfer_config.gcs_to_bq)
}

output "source_buckets" {
  value = local.buckets
}

output "dts_service_agent" {
  description = "GCS 읽기 권한이 필요한 BigQuery Data Transfer 서비스에이전트."
  value       = local.dts_sa
}

output "bq_console_url" {
  value = "https://console.cloud.google.com/bigquery?project=${var.bq_project_id}&ws=!1m4!1m3!3m2!1s${var.bq_project_id}!2s${var.dataset_id}"
}
