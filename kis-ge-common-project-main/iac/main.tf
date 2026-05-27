# =============================================================
# Phase 1: Access Context Manager Access Policy
# =============================================================
module "access_policy" {
  source = "./01.access-context-manager/access-policy"

  org_id = var.org_id
  title  = var.access_policy_title

  depends_on = [google_project_service.required]
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

  depends_on = [google_project_service.required]
}

# =============================================================
# Phase 2: Storage / CMEK Org Policies
# =============================================================

module "storage_policies" {
  source = "./02.org-policies/storage-policies"

  org_id                              = var.org_id
  enforce_public_access_prevention    = var.enforce_public_access_prevention
  enforce_uniform_bucket_level_access = var.enforce_uniform_bucket_level_access

  depends_on = [google_project_service.required]
}

module "cmek_policies" {
  source = "./02.org-policies/cmek-policies"

  org_id                   = var.org_id
  enable_restrict_non_cmek = var.enable_restrict_non_cmek
  cmek_required_services   = var.cmek_required_services

  depends_on = [google_project_service.required]
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

  depends_on = [google_project_service.required]
}

module "org_audit_config" {
  source = "./03.observability/org-audit-config"

  org_id                   = var.org_id
  enable_data_access_audit = var.enable_org_data_access_audit

  depends_on = [google_project_service.required]
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

  depends_on = [google_project_service.required]
}

# =============================================================
# Phase 4: Additional Org Policies (location / service / IAM)
# =============================================================

module "location_policies" {
  source = "./02.org-policies/location-policies"

  org_id                    = var.org_id
  enable_resource_locations = var.enable_resource_locations
  allowed_locations         = var.allowed_locations

  depends_on = [google_project_service.required]
}

module "service_restriction_policies" {
  source = "./02.org-policies/service-restriction-policies"

  org_id                        = var.org_id
  enable_restrict_service_usage = var.enable_restrict_service_usage
  allowed_services              = var.allowed_services

  depends_on = [google_project_service.required]
}

module "iam_policies" {
  source = "./02.org-policies/iam-policies"

  org_id                                      = var.org_id
  disable_service_account_key_creation        = var.disable_service_account_key_creation
  disable_cross_project_service_account_usage = var.disable_cross_project_service_account_usage
  disable_automatic_iam_grants_default_sa     = var.disable_automatic_iam_grants_default_sa

  depends_on = [google_project_service.required]
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

  depends_on = [google_project_service.required]
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

  depends_on = [google_project_service.required]
}
