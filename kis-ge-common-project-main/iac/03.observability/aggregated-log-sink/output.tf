output "central_audit_bucket" {
  description = "중앙 audit 로그 bucket 이름."
  value       = google_storage_bucket.central_audit.name
}

output "sink_name" {
  description = "Organization log sink 이름."
  value       = google_logging_organization_sink.audit.name
}

output "sink_writer_identity" {
  description = "Sink의 unique writer SA."
  value       = google_logging_organization_sink.audit.writer_identity
}
