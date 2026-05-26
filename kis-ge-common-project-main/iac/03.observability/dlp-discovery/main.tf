# 조직 레벨 DLP Discovery — 모든 자회사 프로젝트의 BQ/Cloud SQL/GCS 자원을
# 지속 자동 스캔하여 PII/금융정보 등 민감 데이터 분포를 식별한다.
#
# 체크리스트 #48 매핑: "Discovery Engine/BigQuery/GCS 자원 전수의 PII/금융
# 정보 분류 누락"의 사전 제어.
#
# 활성화 절차:
#   1. SCC Premium tier 활성화 (Console)
#   2. SA에 roles/dlp.organizationsAdmin 부여 (조직 레벨)
#   3. terraform.tfvars 에서 enable_dlp_discovery = true 변경
#   4. apply-dlp-discovery stage 실행
#
# 비용 영향:
#   - BigQuery: 스캔 byte당 과금. 대형 dataset에서 큼.
#   - Cloud Storage: 스캔 byte당.
#   - Cloud SQL: 인스턴스/시간.
#   - cadence_frequency=MONTHLY 기본 (비용 절감).
#
# 발견 결과:
#   - SCC findings로 자동 발송 (publish_to_scc)
#   - Sensitivity Score (HIGH/MEDIUM/LOW) 자동 산정

# 조직 레벨 Inspect Template (KR PII + 금융 detector).
# Discovery config 생성될 때만 만들어진다 (target 0개면 무용지물).
resource "google_data_loss_prevention_inspect_template" "org_pii" {
  count = local.discovery_enabled ? 1 : 0

  parent       = "organizations/${var.org_id}/locations/global"
  display_name = "KIS Org PII Discovery Inspect"
  description  = "KR PII + Finance info types for org-level Discovery Config"

  inspect_config {
    info_types {
      name = "KOREA_RRN"
    }
    info_types {
      name = "KOREA_DRIVERS_LICENSE_NUMBER"
    }
    info_types {
      name = "KOREA_PASSPORT"
    }
    info_types {
      name = "KOREA_BRN"
    }
    info_types {
      name = "KOREA_ARN"
    }
    info_types {
      name = "KOREA_NHI_NUMBER"
    }
    info_types {
      name = "CREDIT_CARD_NUMBER"
    }
    info_types {
      name = "IBAN_CODE"
    }
    info_types {
      name = "FINANCIAL_ACCOUNT_NUMBER"
    }
    info_types {
      name = "EMAIL_ADDRESS"
    }
    info_types {
      name = "PHONE_NUMBER"
    }
    min_likelihood = "POSSIBLE"
  }
}

locals {
  # scan_targets 중 하나라도 true여야 discovery config 자원 생성.
  has_any_target = (
    lookup(var.scan_targets, "bigquery", false) ||
    lookup(var.scan_targets, "cloud_sql", false) ||
    lookup(var.scan_targets, "cloud_storage", false)
  )

  discovery_enabled = var.enable_dlp_discovery && local.has_any_target
}

# Discovery Config (조직 레벨). enable 토글 + scan_targets 둘 다 만족해야 생성.
resource "google_data_loss_prevention_discovery_config" "org" {
  count = local.discovery_enabled ? 1 : 0

  parent       = "organizations/${var.org_id}/locations/global"
  location     = "global"
  display_name = "KIS Org PII Discovery"
  status       = "RUNNING"

  inspect_templates = [
    google_data_loss_prevention_inspect_template.org_pii[0].id,
  ]

  org_config {
    project_id = var.ops_project_id
    location {
      organization_id = var.org_id
    }
  }

  # BigQuery 자동 프로파일링.
  dynamic "targets" {
    for_each = lookup(var.scan_targets, "bigquery", true) ? [1] : []
    content {
      big_query_target {
        filter {
          other_tables {}
        }
        cadence {
          schema_modified_cadence {
            types     = ["SCHEMA_NEW_COLUMNS"]
            frequency = var.cadence_frequency
          }
        }
      }
    }
  }

  # Cloud Storage 자동 프로파일링.
  dynamic "targets" {
    for_each = lookup(var.scan_targets, "cloud_storage", true) ? [1] : []
    content {
      cloud_storage_target {
        filter {
          cloud_storage_resource_reference {
            project_id = var.ops_project_id
          }
        }
        cadence {
          refresh_frequency = var.cadence_frequency
        }
      }
    }
  }

  # Cloud SQL 자동 프로파일링 (자회사 프로젝트만 매치).
  dynamic "targets" {
    for_each = lookup(var.scan_targets, "cloud_sql", true) ? [1] : []
    content {
      cloud_sql_target {
        filter {
          collection {
            include_regexes {
              patterns {
                project_id_regex = var.subsidiary_project_id_regex
              }
            }
          }
        }
        cadence {
          schema_modified_cadence {
            types     = ["NEW_COLUMNS"]
            frequency = var.cadence_frequency
          }
        }
      }
    }
  }

  # 발견 시 SCC findings로 publish.
  actions {
    publish_to_scc {}
  }
}
