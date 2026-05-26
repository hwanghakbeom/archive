terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  # 로컬 state 사용 — bucket이 만들어지기 전이므로 remote backend 불가.
  # 결과 state는 CI artifact (30일) + (선택) bucket 내 prefix로 마이그레이션.
}

variable "project_id" {
  type        = string
  default     = "kis-gemini-common-prod"
  description = "ops/공용 GCP 프로젝트"
}

variable "region" {
  type        = string
  default     = "asia-northeast3"
  description = "state bucket 위치"
}

variable "bucket_name" {
  type        = string
  default     = "kis-gemini-common-prod-tfstate"
  description = "Terraform state bucket"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ----------------------------------------------------------------
# SA 인증 + 프로젝트 접근 검증
# google_client_config 가 토큰 발급을 시도하므로, oauth 실패 시
# plan 단계에서 즉시 에러로 노출됨.
# google_project 가 프로젝트 metadata를 조회하므로, 권한/존재 검증도 동시.
# ----------------------------------------------------------------
data "google_client_config" "current" {}

data "google_project" "current" {
  project_id = var.project_id
}

# ----------------------------------------------------------------
# Terraform state bucket
# ----------------------------------------------------------------
resource "google_storage_bucket" "tfstate" {
  name     = var.bucket_name
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  labels = {
    purpose = "terraform-state"
    stack   = "org-foundation"
    managed = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ----------------------------------------------------------------
# Outputs — CI 로그에서 결과 확인
# ----------------------------------------------------------------
output "sa_verification" {
  description = "SA 인증/프로젝트 접근 검증 결과 (값이 출력되면 성공)"
  value = {
    project_id     = data.google_project.current.project_id
    project_number = data.google_project.current.number
    project_name   = data.google_project.current.name
  }
}

output "state_bucket" {
  value = google_storage_bucket.tfstate.name
}

output "state_bucket_url" {
  value = google_storage_bucket.tfstate.url
}

output "next_step" {
  value = "iac/ 에서 terraform init 가능. backend prefix: lzone/org"
}
