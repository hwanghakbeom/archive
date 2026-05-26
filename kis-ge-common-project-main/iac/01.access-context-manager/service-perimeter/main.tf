# 중앙 통합 Service Perimeter — 모든 자회사 프로젝트를 한 perimeter에 포함.
#
# 자회사 stack에서 별도 perimeter를 만들지 않고 이 모듈이 단독으로 모든
# 자회사 프로젝트의 VPC-SC 경계를 정의한다.
#
# 자회사 추가 시:
#   1. 자회사 stack의 apply-project로 GCP 프로젝트 생성
#   2. terraform.tfvars의 subsidiary_project_ids에 추가
#   3. 본 org-stack 재 apply-service-perimeter 실행
#
# perimeter 적용 절차:
#   1. dry_run = true로 시작 (1-2주 운영, 로그로 위반 검토)
#   2. 위반 분석 후 dry_run = false로 enforcement 전환
#   3. 새로운 ingress / restricted_services 변경은 dry_run 다시 켜고 검증

resource "google_access_context_manager_access_level" "corp" {
  count = local.enabled ? 1 : 0

  parent = local.parent
  name   = "${local.parent}/accessLevels/${var.access_level_name}"
  title  = "Corp access"

  basic {
    conditions {
      ip_subnetworks = var.allowed_ip_ranges
      members        = var.allowed_members
    }
  }
}

resource "google_access_context_manager_service_perimeter" "central" {
  count = local.enabled ? 1 : 0

  parent = local.parent
  name   = "${local.parent}/servicePerimeters/${var.perimeter_name}"
  title  = "KRInvest central perimeter"

  perimeter_type            = "PERIMETER_TYPE_REGULAR"
  use_explicit_dry_run_spec = var.dry_run

  # 운영 모드 (dry_run = false) — status block만 활성.
  dynamic "status" {
    for_each = var.dry_run ? [] : [1]
    content {
      resources           = local.perimeter_resources
      restricted_services = var.restricted_services
      access_levels       = [google_access_context_manager_access_level.corp[0].name]

      ingress_policies {
        ingress_from {
          identity_type = "ANY_IDENTITY"
          identities    = var.ingress_identities

          dynamic "sources" {
            for_each = var.ingress_source_projects
            content {
              resource = "projects/${sources.value}"
            }
          }
        }
        ingress_to {
          operations {
            service_name = "*"
          }
          resources = ["*"]
        }
      }
    }
  }

  # Dry-run 모드 (dry_run = true) — spec block만 활성, 위반은 로깅만.
  dynamic "spec" {
    for_each = var.dry_run ? [1] : []
    content {
      resources           = local.perimeter_resources
      restricted_services = var.restricted_services
      access_levels       = [google_access_context_manager_access_level.corp[0].name]
    }
  }
}
