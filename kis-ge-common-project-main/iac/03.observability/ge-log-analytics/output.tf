output "dataset_id" {
  value = google_bigquery_dataset.ge_logs.dataset_id
}

output "external_tables" {
  value = {
    observability = google_bigquery_table.obs_activity.table_id
    data_access   = google_bigquery_table.data_access.table_id
    activity      = google_bigquery_table.activity.table_id
  }
}

output "source_buckets" {
  value = local.buckets
}

output "bq_console_url" {
  value = "https://console.cloud.google.com/bigquery?project=${var.bq_project_id}&ws=!1m4!1m3!3m2!1s${var.bq_project_id}!2s${var.dataset_id}"
}
