output "topic_id" {
  description = "중앙 ma-detections topic 전체 경로 (자회사 sink destination용)."
  value       = var.enable ? google_pubsub_topic.ma_detections[0].id : null
}

output "scc_source_id" {
  description = "SCC 커스텀 Source ID."
  value       = var.enable ? local.scc_source_id : null
}

output "bridge_sa_email" {
  description = "브리지 함수 실행 SA."
  value       = var.enable ? google_service_account.ma_scc_bridge[0].email : null
}
