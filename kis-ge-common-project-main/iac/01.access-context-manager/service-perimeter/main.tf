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

# 통제 자회사별 GE access level (사내망 IP). perimeter-level access_levels에는 넣지 않음.
resource "google_access_context_manager_access_level" "ge_corp" {
  for_each = local.enabled ? local.ge_controlled : {}

  parent = local.parent
  name   = "${local.parent}/accessLevels/ge_corp_${each.key}"
  title  = "GE corp access (${each.key})"

  basic {
    conditions {
      ip_subnetworks = each.value.allowed_ip_ranges
    }
  }
}

# 참고: VPC-SC access level members / ingress identities는 그룹(group:)을 지원하지 않음
# (user:/serviceAccount:만). 따라서 VIP "그룹" 예외는 VPC-SC로 표현 불가 → 제거.
# kih/kis는 ge_corp(사내망 IP)로만 통제. VIP 예외 필요 시 개별 user 또는 앱 레이어에서 처리.

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

      # GE 자회사별 ingress (통제 IP / 통제 VIP / 비통제 전면허용) — discoveryengine 한정
      dynamic "ingress_policies" {
        for_each = local.ge_ingress
        content {
          ingress_from {
            identity_type = ingress_policies.value.identities == null ? "ANY_IDENTITY" : null
            identities    = ingress_policies.value.identities

            dynamic "sources" {
              for_each = ingress_policies.value.access_level == null ? [] : [ingress_policies.value.access_level]
              content {
                access_level = sources.value
              }
            }
          }
          ingress_to {
            operations {
              service_name = "discoveryengine.googleapis.com"
              method_selectors {
                method = "*"
              }
            }
            resources = [ingress_policies.value.resource]
          }
        }
      }
    }
  }

  # Dry-run 모드 (dry_run = true) — spec block만 활성, 위반은 로깅만.
  # status와 동일 구조(admin + GE ingress)로 두어 dry-run 시뮬레이션이 정확하도록.
  dynamic "spec" {
    for_each = var.dry_run ? [1] : []
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

      dynamic "ingress_policies" {
        for_each = local.ge_ingress
        content {
          ingress_from {
            identity_type = ingress_policies.value.identities == null ? "ANY_IDENTITY" : null
            identities    = ingress_policies.value.identities

            dynamic "sources" {
              for_each = ingress_policies.value.access_level == null ? [] : [ingress_policies.value.access_level]
              content {
                access_level = sources.value
              }
            }
          }
          ingress_to {
            operations {
              service_name = "discoveryengine.googleapis.com"
              method_selectors {
                method = "*"
              }
            }
            resources = [ingress_policies.value.resource]
          }
        }
      }
    }
  }
}
