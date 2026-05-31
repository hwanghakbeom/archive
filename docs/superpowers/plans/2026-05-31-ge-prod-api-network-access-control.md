# GE Prod API 네트워크 접근 제어 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gemini Enterprise(`discoveryengine.googleapis.com`)를 중앙 VPC-SC perimeter의 restricted_service로 넣고, 자회사별 ingress로 kih·kis는 사내망 IP + VIP 그룹만 허용, 나머지 6개는 전면 허용(현재 동작 유지)하도록 강제한다.

**Architecture:** org-stack(`kis-ge-common-project-main`)의 단일 중앙 Service Perimeter를 유지. corp IP는 perimeter-level이 아닌 자회사별 access level에 담고, 프로젝트 단위 ingress 3종(통제 IP / 통제 VIP 그룹 / 비통제 전면허용)으로 정책을 표현한다. corp IP를 perimeter-level access_levels에 넣지 않아 기존 5개 서비스 동작은 불변. `perimeter_dry_run = false`(enforce 직행, 사용자 확정).

**Tech Stack:** Terraform, `google`/`google-beta` provider, GCP Access Context Manager(VPC Service Controls), GitLab CI(manual apply job).

**Spec:** `docs/superpowers/specs/2026-05-31-ge-prod-api-network-access-control-design.md`

**작업 위치(전부 동일 repo):** `kis-ge-common-project-main/iac/`

---

## ⚠️ Task 0: Pre-flight — 현재 live 상태 확인 (apply 전 필수)

이 plan은 enforce 직행이고 8개 prod 자회사에 영향을 주므로, 코드만으로 알 수 없는 live 상태를 먼저 확인한다.

**Files:** (없음 — 조사/확인만)

- [ ] **Step 1: 중앙 perimeter가 이미 enable 되어 있는지 확인**

Run:
```bash
cd kis-ge-common-project-main/iac
grep -n "enable_central_perimeter\|perimeter_dry_run" terraform.tfvars.example
gcloud access-context-manager perimeters list \
  --policy="$(gcloud access-context-manager policies list --format='value(name)' | head -1)" \
  --format="table(name, status.restrictedServices, spec.restrictedServices)" 2>/dev/null || echo "조회 권한/정책 확인 필요"
```
Expected: 현재 `krinvest_central` perimeter가 존재하는지, restricted_services에 5개(aiplatform/storage/bigquery/dlp/cloudkms)가 들어 enforce 중인지 확인. `discoveryengine`은 아직 없어야 함.

- [ ] **Step 2: 5개 서비스 enforcement 위치 확인 (org-stack vs subsidiary-stack)**

`kis-ge-project-main/iac/main.tf`의 주석(line 84–88)대로 perimeter가 org-stack으로 이관됐는지, 자회사 stack에 잔존 perimeter가 없는지 확인.
Run:
```bash
grep -rn "service_perimeter\|enable_vpc_sc" ../kis-ge-project-main/iac/*.tf 2>/dev/null || echo "subsidiary stack에 perimeter 없음(정상)"
```
Expected: 자회사 stack엔 perimeter 리소스가 없음(주석 처리/이관 완료).

- [ ] **Step 3: apply 주체(SA/사용자)와 quota-project 핀 확인**

2026-05-22 gotcha(Terraform billing-project 귀속이 외부 호출을 perimeter 안으로 끌어들임) 방지.
Run:
```bash
gcloud config get-value billing/quota_project 2>/dev/null
gcloud auth application-default set-quota-project kis-common-gcp  # state ops용 핀 (필요 시)
```
Expected: state 읽기/apply가 perimeter에 막히지 않도록 quota-project 핀 확인.

- [ ] **Step 4: 8개 GE 프로젝트 존재 + apply SA 접근 가능 확인**

Run:
```bash
for p in kih-ge-prod kis-ge-prod kisb-ge-prod kic-ge-prod kim-ge-prod vam-ge-prod kit-ge-prod kip-ge-prod; do
  gcloud projects describe "$p" --format="value(projectNumber)" 2>/dev/null && echo "  ✓ $p" || echo "  ✗ $p 없음/권한없음"
done
```
Expected: 8개 모두 projectNumber 출력. 하나라도 없으면 그 자회사 entry를 맵에서 빼거나 프로젝트 생성 선행.

- [ ] **Step 5: VIP 그룹 8개 존재 확인 (선택, 가능하면)**

Run:
```bash
for g in kih kis kisb kic kim vam kit kip; do echo "${g}-vip@koreainvestment.com"; done
# Workspace Admin 권한 있으면: gcloud identity groups describe <group> (없으면 Admin 콘솔로 확인)
```
Expected: kih-vip / kis-vip 존재 확인(통제 자회사용). 나머지는 통제 전환 시 필요.

> **게이트:** Step 1에서 perimeter가 아직 enable 안 됐거나(=이번 apply가 5+1 서비스를 처음 enforce) 5개 서비스 상태가 예상과 다르면, **멈추고 사용자에게 보고**한다. 이 경우 영향 범위가 discoveryengine만이 아니다.

---

## Task 1: 모듈 변수 + GE 프로젝트 data source

**Files:**
- Modify: `kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/variables.tf`
- Modify: `kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/data.tf`

- [ ] **Step 1: `subsidiary_ge_access` 변수 추가**

`variables.tf` 맨 끝에 추가:
```hcl
variable "subsidiary_ge_access" {
  description = <<-EOT
    자회사별 GE(discoveryengine) 접근 정책 맵. key = 자회사 키.
      project_id        : 해당 자회사 GCP 프로젝트 ID
      controlled        : true=사내망 IP + VIP 그룹만 허용, false=전면 허용(현재 동작 유지)
      allowed_ip_ranges : controlled=true일 때 사내망 egress CIDR (access level로 감쌈)
      external_members  : controlled=true일 때 외부(맨몸) 허용 identity (group:/user:)
  EOT
  type = map(object({
    project_id        = string
    controlled        = bool
    allowed_ip_ranges = optional(list(string), [])
    external_members  = optional(list(string), [])
  }))
  default = {}
}
```

- [ ] **Step 2: GE 프로젝트 number 조회 data source 추가**

`data.tf` 맨 끝에 추가 (자회사 키로 조회 가능하도록 별도 data source):
```hcl
# GE 접근 제어 대상 프로젝트 ID → number (subsidiary_ge_access 키로 조회).
data "google_project" "ge" {
  for_each = var.enable_perimeter ? var.subsidiary_ge_access : {}

  project_id = each.value.project_id
}
```

- [ ] **Step 3: fmt + validate (init 필요)**

Run:
```bash
cd kis-ge-common-project-main/iac
terraform fmt -recursive 01.access-context-manager/service-perimeter
cd 01.access-context-manager/service-perimeter && terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.` (`optional()`는 Terraform ≥1.3 필요 — 에러 시 버전 확인.)

- [ ] **Step 4: Commit**

```bash
cd /Users/mzs02-andy/Projects/mz_external/kis/zips
git add kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/variables.tf \
        kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/data.tf
git commit -m "$(printf 'feat(vpc-sc): subsidiary_ge_access 변수 + GE 프로젝트 data source\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 2: 자회사별 access level + ingress locals

**Files:**
- Modify: `kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/local.tf`
- Modify: `kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/main.tf`

- [ ] **Step 1: locals 추가 (`local.tf`)**

기존 `locals { ... }` 블록 안, `perimeter_resources` 아래에 추가:
```hcl
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
    # (2) 통제: VIP 그룹(소스 무관) → 해당 프로젝트 (그룹 있을 때만)
    [for k, v in local.ge_controlled : {
      identities   = v.external_members
      access_level = null
      resource     = "projects/${local.ge_project_number[k]}"
    } if length(v.external_members) > 0],
    # (3) 비통제: 전면 허용(any identity, 소스 무관) → 해당 프로젝트
    [for k, v in local.ge_uncontrolled : {
      identities   = null
      access_level = null
      resource     = "projects/${local.ge_project_number[k]}"
    }],
  )
```

- [ ] **Step 2: 자회사별 access level 리소스 추가 (`main.tf`)**

기존 `resource "google_access_context_manager_access_level" "corp"` 블록 **아래에** 추가:
```hcl
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
```

- [ ] **Step 3: fmt + validate**

Run:
```bash
cd kis-ge-common-project-main/iac
terraform fmt -recursive 01.access-context-manager/service-perimeter
cd 01.access-context-manager/service-perimeter && terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`
(이 시점엔 `local.ge_ingress`가 아직 perimeter에서 미사용 → validate는 통과하나 unused 경고 없음. 다음 Task에서 소비.)

- [ ] **Step 4: Commit**

```bash
cd /Users/mzs02-andy/Projects/mz_external/kis/zips
git add kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/local.tf \
        kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/main.tf
git commit -m "$(printf 'feat(vpc-sc): 자회사별 GE access level + ingress locals\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 3: perimeter status/spec에 GE ingress 연결

**Files:**
- Modify: `kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/main.tf:31-80` (perimeter 리소스)

기존 `status`/`spec` dynamic 블록은 admin ingress 1개만 갖는다. 둘 다에 `local.ge_ingress` 기반 dynamic ingress를 추가한다(dry_run=true 롤백 시에도 정확하도록 spec도 동일하게).

- [ ] **Step 1: `status` 블록에 GE ingress dynamic 추가**

`main.tf`의 `dynamic "status"` → `content { ... }` 안, 기존 `ingress_policies { ... }`(admin) **바로 아래에** 추가:
```hcl
      # GE 자회사별 ingress (통제 IP / 통제 VIP / 비통제 전면허용) — discoveryengine 한정
      dynamic "ingress_policies" {
        for_each = local.ge_ingress
        content {
          ingress_from {
            identity_type = "ANY_IDENTITY"
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
```

- [ ] **Step 2: `spec` 블록을 status와 동일 구조로 보강**

`dynamic "spec"` → `content { ... }`는 현재 `resources`/`restricted_services`/`access_levels`만 있다. admin ingress + GE ingress를 status와 동일하게 추가한다. `content { ... }` 안을 다음으로 교체:
```hcl
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
            identity_type = "ANY_IDENTITY"
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
```

- [ ] **Step 3: fmt + validate**

Run:
```bash
cd kis-ge-common-project-main/iac
terraform fmt -recursive 01.access-context-manager/service-perimeter
cd 01.access-context-manager/service-perimeter && terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
cd /Users/mzs02-andy/Projects/mz_external/kis/zips
git add kis-ge-common-project-main/iac/01.access-context-manager/service-perimeter/main.tf
git commit -m "$(printf 'feat(vpc-sc): status/spec에 GE 자회사별 ingress 연결\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 4: root wiring

**Files:**
- Modify: `kis-ge-common-project-main/iac/variables.tf`
- Modify: `kis-ge-common-project-main/iac/main.tf:13-25` (module "service_perimeter")

- [ ] **Step 1: root 변수 추가 (`variables.tf`)**

`variable "perimeter_restricted_services"` 블록 아래에 추가:
```hcl
variable "perimeter_subsidiary_ge_access" {
  description = "자회사별 GE(discoveryengine) 접근 정책 맵. service-perimeter 모듈의 subsidiary_ge_access로 전달."
  type = map(object({
    project_id        = string
    controlled        = bool
    allowed_ip_ranges = optional(list(string), [])
    external_members  = optional(list(string), [])
  }))
  default = {}
}
```

- [ ] **Step 2: module 호출에 인자 추가 (`main.tf`)**

`module "service_perimeter"` 블록 안, `restricted_services = var.perimeter_restricted_services` 줄 아래에 추가:
```hcl
  subsidiary_ge_access    = var.perimeter_subsidiary_ge_access
```

- [ ] **Step 3: fmt + validate (root)**

Run:
```bash
cd kis-ge-common-project-main/iac
terraform fmt -recursive .
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
cd /Users/mzs02-andy/Projects/mz_external/kis/zips
git add kis-ge-common-project-main/iac/variables.tf kis-ge-common-project-main/iac/main.tf
git commit -m "$(printf 'feat(vpc-sc): root에 perimeter_subsidiary_ge_access 와이어링\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 5: tfvars.example 값 설정 (CI source of truth)

**Files:**
- Modify: `kis-ge-common-project-main/iac/terraform.tfvars.example`

> ⚠️ CI는 `cp -f terraform.tfvars.example terraform.tfvars`로 **example을 항상 source of truth**로 쓴다. 값은 반드시 example에 넣는다.

- [ ] **Step 1: enable + enforce + restricted_services + 맵 설정**

`terraform.tfvars.example`에서 다음을 수정한다.

(a) perimeter 활성 + enforce 직행:
```hcl
enable_central_perimeter = true
perimeter_dry_run        = false
```

(b) `perimeter_restricted_services` 리스트에 한 줄 추가:
```hcl
perimeter_restricted_services = [
  "aiplatform.googleapis.com",
  "storage.googleapis.com",
  "bigquery.googleapis.com",
  "dlp.googleapis.com",
  "cloudkms.googleapis.com",
  "discoveryengine.googleapis.com",
]
```

(c) `perimeter_restricted_services` 블록 아래에 맵 추가:
```hcl
perimeter_subsidiary_ge_access = {
  # 통제 자회사 (사내망 IP + VIP 그룹만)
  kih = { project_id = "kih-ge-prod", controlled = true, allowed_ip_ranges = ["219.255.206.0/24", "175.113.102.0/24"], external_members = ["group:kih-vip@koreainvestment.com"] }
  kis = { project_id = "kis-ge-prod", controlled = true, allowed_ip_ranges = ["219.255.206.0/24", "175.113.102.0/24"], external_members = ["group:kis-vip@koreainvestment.com"] }
  # 비통제 자회사 (전면 허용 — 현재 동작 유지). 망 통제 필요 시 controlled=true + IP 추가.
  kisb = { project_id = "kisb-ge-prod", controlled = false }
  kic  = { project_id = "kic-ge-prod", controlled = false }
  kim  = { project_id = "kim-ge-prod", controlled = false }
  vam  = { project_id = "vam-ge-prod", controlled = false }
  kit  = { project_id = "kit-ge-prod", controlled = false }
  kip  = { project_id = "kip-ge-prod", controlled = false }
}
```

- [ ] **Step 2: fmt 확인**

Run:
```bash
cd kis-ge-common-project-main/iac
terraform fmt -check terraform.tfvars.example || terraform fmt terraform.tfvars.example
```
Expected: 변경 없음(이미 정렬) 또는 정렬 후 통과.

- [ ] **Step 3: Commit**

```bash
cd /Users/mzs02-andy/Projects/mz_external/kis/zips
git add kis-ge-common-project-main/iac/terraform.tfvars.example
git commit -m "$(printf 'feat(vpc-sc): GE 접근 제어 값 설정 — enforce + 8개 자회사 맵\n\nperimeter enable + dry_run=false, discoveryengine 제한, kih/kis 통제\n(IP+VIP), 6개 비통제. example=CI source of truth.\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 6: plan 검증 (apply 전 최종 게이트)

**Files:** (없음 — plan 출력 검사)

- [ ] **Step 1: 인증 후 targeted plan 생성**

권장 경로 — **CI의 plan/validate job**(default 브랜치 push 시 자동, `tfplan.binary` 아티팩트 생성)으로
plan을 만들고 그 출력을 검토한다. CI가 backend(`TF_STATE_BUCKET`/`TF_STATE_PREFIX` = GitLab CI 변수)와
토큰 발급을 처리한다.

로컬에서 직접 보려면(backend 값은 CI 변수/`backend.tf` 참조):
```bash
cd kis-ge-common-project-main/iac
export GOOGLE_OAUTH_ACCESS_TOKEN="$(bash ../ci/mint-gcp-token.sh)"   # 또는 gcloud ADC
cp -f terraform.tfvars.example terraform.tfvars
terraform init -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="prefix=$TF_STATE_PREFIX"
terraform plan -target=module.service_perimeter -out=tfplan.binary
```
Expected: plan 성공. `data.google_project.ge` 8개 조회 성공.

- [ ] **Step 2: plan 내용 검사 — 정확히 무엇이 바뀌는지 확인**

Run:
```bash
terraform show -json tfplan.binary | jq -r '
  .resource_changes[] | select(.address|test("service_perimeter")) |
  "\(.change.actions|join(",")) \(.address)"'
```
검증 체크리스트:
- `google_access_context_manager_access_level.ge_corp["kih"]`, `["kis"]` 2개 **create**.
- `google_access_context_manager_service_perimeter.central[0]` **update**.
- perimeter의 `status[0].restricted_services`에 `discoveryengine.googleapis.com` 포함, 기존 5개 유지.
- `status[0].ingress_policies` 개수 = admin 1 + GE(통제IP 2 + 통제VIP 2 + 비통제 6 = 10) = **11**.
- `status[0].access_levels` = corp 1개만(ge_corp_* 미포함 — 격리 핵심).
- **기존 5개 서비스 / corp access level 변경 없음**(회귀 0).

- [ ] **Step 3: 게이트 판단**

위 체크 중 하나라도 어긋나면 **멈추고 원인 분석**. 특히 ingress 개수/리소스 한정(projects/<number>)·access_levels에 ge_corp 미포함을 반드시 확인. 이상 없으면 Task 7로.

> 커밋 없음(plan 검증 단계).

---

## Task 7: apply + 라이브 검증 + 롤백 런북

**Files:** (없음 — 운영 절차)

> 🔴 enforce 직행. **저트래픽 시간대 + 담당자 대기 + 롤백 diff 준비** 상태에서 수행.

- [ ] **Step 1: 롤백 diff 미리 준비**

apply 전에 롤백 tfvars를 미리 만들어 둔다(즉시 적용 가능하도록):
```bash
# 롤백안 A (가장 빠름): perimeter_dry_run = true 로만 변경
# 롤백안 B: perimeter_restricted_services 에서 "discoveryengine.googleapis.com" 제거
# 두 diff를 메모/스태시로 대기.
```

- [ ] **Step 2: apply 실행**

방법 1 — CI manual job(권장, 직렬화/lock 안전):
```
GitLab → Pipelines → 최신(default 브랜치) → stage "vpc-sc" → apply-service-perimeter 수동 실행
```
방법 2 — 로컬:
```bash
cd kis-ge-common-project-main/iac
terraform apply tfplan.binary
```
Expected: apply 성공. perimeter update + ge_corp 2개 create.

- [ ] **Step 3: 라이브 검증 (apply 직후 수 분 내)**

순서대로 즉시 확인:
1. **비통제 회귀(최우선):** kisb/kic/kim/vam/kit/kip 중 하나에서 GE 정상 사용되는지(위반 없어야 함).
2. **통제 kih/kis:** 사내망(219.255.206.0/24 또는 175.113.102.0/24)에서 GE 정상.
3. **통제 외부 차단:** 사내망 밖(비VIP)에서 kih/kis GE 접근 시 차단.
4. **VIP 외부 허용:** kih-vip/kis-vip 멤버가 외부에서 정상.

로그 모니터링:
```bash
gcloud logging read \
  'protoPayload.metadata."@type"="type.googleapis.com/google.cloud.audit.VpcServiceControlAuditMetadata" AND severity>=ERROR' \
  --project=kis-gemini-common-prod --freshness=15m --limit=50 \
  --format="table(timestamp, protoPayload.metadata.violationReason, protoPayload.resourceName)"
```
검증: 비통제 6개·정상 사내망 사용자에 위반이 뜨면 → **즉시 Step 4 롤백**.

- [ ] **Step 4: (장애 시) 롤백**

가장 빠른 해제:
```bash
# A: dry_run=true 로 변경 후 재apply (enforce 해제, 로깅만)
#    terraform.tfvars.example: perimeter_dry_run = false → true
# 또는 B: discoveryengine.googleapis.com 제거 후 재apply (line 417 상태 복귀)
git checkout -b hotfix/ge-perimeter-rollback   # 필요 시
# example 수정 후
cd kis-ge-common-project-main/iac
cp -f terraform.tfvars.example terraform.tfvars
terraform apply -target=module.service_perimeter
```
Expected: 차단 즉시 해제. 이후 원인 분석 → dry-run으로 재검증.

- [ ] **Step 5: content-discoveryengine / clients6 확인**

로그에서 `content-discoveryengine.googleapis.com` 관련 위반/우회가 보이는지 확인:
- 정상 사용자에 content-discoveryengine 위반 → `perimeter_restricted_services`에 추가 검토.
- Deep Research/영상생성(`discoveryengine.clients6.google.com`)이 통제 자회사에서 우회되는지 확인(PSC 미지원 도메인 — VPC-SC 커버리지 한계 가능).

- [ ] **Step 6: 운영 로그 기록**

`kis-ge-project-main/docs/security-checklist.md` 변경 이력 표에 한 줄 추가(날짜/내용/담당). discoveryengine 재포함 + 자회사별 ingress + enforce 직행 결정 기록(line 417 번복 사유 포함).

```bash
cd /Users/mzs02-andy/Projects/mz_external/kis/zips
git add kis-ge-project-main/docs/security-checklist.md
git commit -m "$(printf 'docs(security): GE discoveryengine 접근 제어 enforce 이력 기록\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## 부록: 향후 작업 (이 plan 범위 밖)

- 비통제 6개 자회사 망 통제: `controlled=true` + `allowed_ip_ranges` 입력으로 동일 패턴 적용.
- LB Cloud Armor IP allowlist(defense-in-depth) 추가 검토.
- 신규 자회사: `subsidiary_project_ids` + `perimeter_subsidiary_ge_access` 항목 추가.
