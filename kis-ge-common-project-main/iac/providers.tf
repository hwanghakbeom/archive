provider "google" {
  region = var.region_primary

  # ops project(kis-gemini-common-prod)를 통해 quota/billing 라우팅. org-level 자원
  # (Access Context Manager, Org Policy, Organization Log Sink 등) 호출 시
  # x-goog-user-project 헤더가 필요한 API가 있어 user_project_override = true.
  user_project_override = true
  billing_project       = var.billing_project

  # userinfo.email scope 필수 — provider가 토큰 검증 시 호출.
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
  ]
  # www.googleapis.com allowlist 추가 전 임시 우회 — userinfo 호출 skip.
  add_terraform_attribution_label = false
}

provider "google-beta" {
  region                = var.region_primary
  user_project_override = true
  billing_project       = var.billing_project

  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
  ]
  add_terraform_attribution_label = false
}
