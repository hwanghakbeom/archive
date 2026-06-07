# =============================================================
# Phase 1: Access Context Manager Access Policy
# =============================================================
module "access_policy" {
  source = "./01.access-context-manager/access-policy"

  org_id = var.org_id
  title  = var.access_policy_title
}

# 중앙 통합 Service Perimeter — 모든 자회사 프로젝트를 한 perimeter에 포함.
# 자회사 stack에서 perimeter를 만들지 않고 본 모듈이 단독 관리.
module "service_perimeter" {
  source = "./01.access-context-manager/service-perimeter"

  enable_perimeter        = var.enable_central_perimeter
  access_policy_id        = module.access_policy.policy_id
  subsidiary_project_ids  = var.subsidiary_project_ids
  dry_run                 = var.perimeter_dry_run
  allowed_ip_ranges       = var.perimeter_allowed_ip_ranges
  allowed_members         = var.perimeter_allowed_members
  ingress_identities      = var.perimeter_ingress_identities
  ingress_source_projects = var.perimeter_ingress_source_projects
  restricted_services     = var.perimeter_restricted_services
  subsidiary_ge_access    = var.perimeter_subsidiary_ge_access
}

# =============================================================
# Phase 2: Storage / CMEK Org Policies
# =============================================================

module "storage_policies" {
  source = "./02.org-policies/storage-policies"

  org_id                              = var.org_id
  enforce_public_access_prevention    = var.enforce_public_access_prevention
  enforce_uniform_bucket_level_access = var.enforce_uniform_bucket_level_access
}

module "cmek_policies" {
  source = "./02.org-policies/cmek-policies"

  org_id                   = var.org_id
  enable_restrict_non_cmek = var.enable_restrict_non_cmek
  cmek_required_services   = var.cmek_required_services
}

# =============================================================
# Phase 3: Observability
# =============================================================

module "aggregated_log_sink" {
  source = "./03.observability/aggregated-log-sink"

  org_id                    = var.org_id
  ops_project_id            = var.ops_project_id
  central_audit_bucket_name = var.central_audit_bucket_name
  region                    = var.region_primary
  retention_days            = var.retention_days
  lock_retention            = var.lock_retention
  sink_name                 = var.aggregated_sink_name
}

module "org_audit_config" {
  source = "./03.observability/org-audit-config"

  org_id                   = var.org_id
  enable_data_access_audit = var.enable_org_data_access_audit
}

# GE 로그 federation — 적재는 각 자회사 stack(log-analytics)이 자기 프로젝트 BQ로 수행하고,
# common은 8개 자회사 테이블을 UNION ALL 뷰로 federation(데이터 복제 없음). Looker Studio 소스.
module "ge_log_analytics" {
  count  = var.enable_ge_log_analytics ? 1 : 0
  source = "./03.observability/ge-log-analytics"

  bq_project_id          = var.ops_project_id
  location               = var.region_primary
  dataset_id             = var.ge_logs_dataset_id
  subsidiary_project_ids = var.subsidiary_project_ids
  viewer_members         = var.ge_logs_viewer_members
}

# 조직 레벨 DLP Discovery — BQ/Cloud SQL/GCS의 PII/금융정보 자동 분류.
# SCC Premium tier 활성화 + roles/dlp.organizationsAdmin 권한 필요.
module "dlp_discovery" {
  source = "./03.observability/dlp-discovery"

  enable_dlp_discovery        = var.enable_dlp_discovery
  org_id                      = var.org_id
  ops_project_id              = var.ops_project_id
  scan_targets                = var.dlp_scan_targets
  cadence_frequency           = var.dlp_cadence_frequency
  subsidiary_project_id_regex = var.dlp_subsidiary_project_id_regex
}

# =============================================================
# Phase 4: Additional Org Policies (location / service / IAM)
# =============================================================

module "location_policies" {
  source = "./02.org-policies/location-policies"

  org_id                    = var.org_id
  enable_resource_locations = var.enable_resource_locations
  allowed_locations         = var.allowed_locations
}

module "service_restriction_policies" {
  source = "./02.org-policies/service-restriction-policies"

  org_id                        = var.org_id
  enable_restrict_service_usage = var.enable_restrict_service_usage
  allowed_services              = var.allowed_services
}

module "iam_policies" {
  source = "./02.org-policies/iam-policies"

  org_id                                      = var.org_id
  disable_service_account_key_creation        = var.disable_service_account_key_creation
  disable_cross_project_service_account_usage = var.disable_cross_project_service_account_usage
  disable_automatic_iam_grants_default_sa     = var.disable_automatic_iam_grants_default_sa
}

# =============================================================
# Phase 5: Domain Restriction (⚠️ 위험, plan-only stage)
# =============================================================
# CI에서는 plan만 수행, apply는 별도 수동. enable=false 기본.
module "domain_policies" {
  source = "./02.org-policies/domain-restriction-policies"

  org_id                    = var.org_id
  enable_domain_restriction = var.enable_domain_restriction
  allowed_member_domains    = var.allowed_member_domains
}

# =============================================================
# Phase 6: SCC Premium 자원
# =============================================================
# 전제: SCC tier가 Premium/Enterprise로 사전 활성화됨 (Console 수동).
# enable_phase6 = false 기본 → SCC tier 활성화 전에는 자원 0개.
module "scc_notifications" {
  source = "./04.scc/notification-config"

  enable_phase6            = var.enable_phase6
  org_id                   = var.org_id
  ops_project_id           = var.ops_project_id
  notification_topic_name  = var.scc_notification_topic_name
  notification_config_id   = var.scc_notification_config_id
  notification_filter      = var.scc_notification_filter
  notification_description = "Active HIGH/CRITICAL SCC findings → PubSub (SIEM/Slack/Email 연동용)"
}

# =============================================================
# Phase 6-B: SCC On-prem Forwarder (Cloud Run Job + NAT 고정 IP → on-prem)
# =============================================================
# Cloud Run Job이 주기적으로 SCC findings 조회 후 Direct VPC egress 경유로
# Cloud NAT의 고정 외부 IP로 SNAT되어 on-prem HTTPS endpoint에 POST.
# 컨테이너 이미지는 별도 빌드/푸시 (terraform은 인프라만 관리).
module "scc_onprem_forwarder" {
  source = "./04.scc/onprem-forwarder"

  enable                 = var.enable_scc_onprem_forwarder
  project_id             = var.ops_project_id
  region                 = var.region_primary
  image_uri              = var.scc_forwarder_image_uri
  pubsub_topic_name      = var.scc_notification_topic_name
  onprem_host            = var.scc_forwarder_onprem_host
  onprem_port            = var.scc_forwarder_onprem_port
  tcp_timeout_sec        = var.scc_forwarder_tcp_timeout_sec
  min_instance_count     = var.scc_forwarder_min_instance_count
  max_instance_count     = var.scc_forwarder_max_instance_count
  vpc_cidr               = var.scc_forwarder_vpc_cidr
  egress_ip_name         = var.scc_forwarder_egress_ip_name
  use_existing_egress_ip = var.scc_forwarder_use_existing_egress_ip
}

# =============================================================
# Phase 6-C: MA 런타임 탐지 → SCC findings 브리지 (scctest PoC 이식)
# =============================================================
# 자회사 Model Armor SanitizeOperation(MATCH_FOUND) 로그를 SCC finding으로 변환.
# 생성된 finding(HIGH/ACTIVE)은 기존 scc_notifications filter에 자동 매치되어
# onprem-forwarder 경로로 SIEM/온프렘에 전달된다. 상세: SCC - ARCHITECTURE.md.
# 자회사측 sink는 자회사 stack의 ma-detections-sink 모듈(③)이 담당.
module "ma_runtime_findings" {
  source = "./04.scc/ma-runtime-findings"

  enable                 = var.enable_ma_runtime_findings
  project_id             = var.ops_project_id
  org_id                 = var.org_id
  region                 = var.region_primary
  topic_name             = var.ma_detections_topic_name
  subsidiary_project_ids = var.ma_subsidiary_project_ids
}
