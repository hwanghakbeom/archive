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
    # (2) 통제: VIP 예외(어느 IP서나) → 해당 프로젝트. external_members(group:/user:)를
    #     ingress identities로 지정 + sources access_level="*"(any network).
    #     VPC-SC는 sources가 필수이며 "*"는 모든 네트워크 출처 허용.
    [for k, v in local.ge_controlled : {
      identities   = v.external_members
      access_level = "*"
      resource     = "projects/${local.ge_project_number[k]}"
    } if length(v.external_members) > 0],
    # (3) 비통제: 전면 허용 → access_level="*"(any network) 소스 필수.
    [for k, v in local.ge_uncontrolled : {
      identities   = null
      access_level = "*"
      resource     = "projects/${local.ge_project_number[k]}"
    }],
  )

  # ingress_from의 identity_type/identities 제약 때문에 두 그룹으로 분리:
  #  - identities 지정(VIP 그룹/유저): ingress_from에 identity_type 미지정
  #  - 그 외(IP access_level / 전면허용): identity_type=ANY_IDENTITY
  ge_ingress_identity = [for e in local.ge_ingress : e if e.identities != null]
  ge_ingress_source   = [for e in local.ge_ingress : e if e.identities == null]
}
