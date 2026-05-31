locals {
  enabled = var.enable_perimeter

  parent = "accessPolicies/${var.access_policy_id}"

  # 모든 자회사 프로젝트의 perimeter 자원 표현.
  perimeter_resources = [
    for k, p in data.google_project.subsidiary : "projects/${p.number}"
  ]

  # GE 접근 제어 — 통제/비통제 분리
  ge_controlled   = { for k, v in var.subsidiary_ge_access : k => v if v.controlled }
  ge_uncontrolled = { for k, v in var.subsidiary_ge_access : k => v if !v.controlled }

  # 통제 자회사 중 IP 외 예외 user가 지정된 것 → ge_vip access level(members)로 처리.
  ge_vip = { for k, v in local.ge_controlled : k => v if length(v.external_members) > 0 }

  # 프로젝트 number
  ge_project_number = { for k, v in var.subsidiary_ge_access : k => data.google_project.ge[k].number }

  # ingress 3종 → 단일 리스트(status/spec 공통 사용)
  ge_ingress = concat(
    # (1) 통제: 사내망 IP (access level) → 해당 프로젝트
    [for k, v in local.ge_controlled : {
      identities   = null
      access_level = google_access_context_manager_access_level.ge_corp[k].name
      resource     = "projects/${local.ge_project_number[k]}"
    }],
    # (2) 통제: 예외 user(어느 IP서나) → 해당 프로젝트. user는 ge_vip access level members로 제한.
    [for k, v in local.ge_controlled : {
      identities   = null
      access_level = google_access_context_manager_access_level.ge_vip[k].name
      resource     = "projects/${local.ge_project_number[k]}"
    } if length(v.external_members) > 0],
    # (3) 비통제: 전면 허용(any identity, 소스 무관) → 해당 프로젝트
    [for k, v in local.ge_uncontrolled : {
      identities   = null
      access_level = null
      resource     = "projects/${local.ge_project_number[k]}"
    }],
  )
}
