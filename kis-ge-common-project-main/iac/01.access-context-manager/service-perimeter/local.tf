locals {
  enabled = var.enable_perimeter

  parent = "accessPolicies/${var.access_policy_id}"

  # 모든 자회사 프로젝트의 perimeter 자원 표현.
  perimeter_resources = [
    for k, p in data.google_project.subsidiary : "projects/${p.number}"
  ]
}
