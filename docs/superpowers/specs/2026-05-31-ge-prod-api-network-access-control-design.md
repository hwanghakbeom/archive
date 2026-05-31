# GE Prod 접근 제어: API 레이어 네트워크 게이트 (VPC-SC + Access Context Manager)

- 작성일: 2026-05-31
- 대상 stack: `kis-ge-common-project-main` (org-stack, 중앙 통합 perimeter)
- 상태: 설계 승인됨 → 구현 계획 작성 전

## 1. 요구사항

prod 환경에서:

- **전체 유저**는 회사 **사내망(고정 공인 egress IP 대역)** 에서만 Gemini Enterprise(GE)에 접근 가능해야 한다.
- **일부 Google Workspace 그룹**의 유저는 **외부(VPN 없는 맨몸 접근 포함, 임의 네트워크)** 에서도 접근 가능해야 한다.

## 2. 강제 지점 결정 — 왜 API 레이어인가

GE 웹앱은 External HTTPS LB + 커스텀 도메인(`{key}-gemini.koreainvestment.com`)으로
노출되고 인증은 Google Workspace(GSUITE IdP)로 일어난다. 후보 강제 지점을 검토한 결과:

| 메커니즘 | end-user 접근 제어 | 그룹 예외 |
|---|---|---|
| Workspace Context-Aware Access | ❌ GE/Agentspace는 CAA 지원 서비스 목록에 **없음** | — |
| GE IAM (`agentspaceUser`) | 신원(누가)만, IP/위치 조건 없음 | 신원 O, IP 무관 |
| GE Private UI access (PSC+VPN/Interconnect) | UI 전체를 사설망으로 — **바이너리, 그룹 예외 불가** | ❌ |
| LB Cloud Armor | IP allowlist 가능하나 **요청이 Google 로그인 전이라 그룹 신원을 모름** | ❌ |
| **VPC-SC + Access Context Manager (선택)** | discoveryengine API 호출을 **IP+신원 컨텍스트**로 평가 | **ingress 규칙으로 그룹 carve-out 가능** |

**결정 근거:** LB 엣지는 사용자의 Workspace 그룹을 알 수 없다(Google 로그인이 downstream
위젯 안에서 일어남). 반면 GE 웹 UI가 호출하는 `discoveryengine.googleapis.com` 호출에는
**사용자의 네트워크 IP + 인증된 신원**이 함께 실린다. 따라서 강제 지점을 LB가 아니라
**GE API 호출**로 옮기면 "전체는 IP, 그룹은 신원" 을 한 메커니즘으로 네이티브하게 표현할 수 있다.

> 사용자 의사결정 인용: "LB는 몰라도 상관없습니다. Gemini enterprise api 만 호출하지 못하면 됩니다."

## 3. 의도적 결정 번복 (line 417)

`kis-ge-project-main/docs/security-checklist.md`의 2026-05-22 로그(line 417)는
`discoveryengine.googleapis.com`을 VPC-SC `restricted_services`에서 **제거**했다.
사유: "GE end-user가 글로벌 LB로 들어오고 corporate access level에 없으므로,
discoveryengine을 제한하면 정상 end-user 트래픽이 enforce 모드에서 차단된다."

당시에는 "그룹 예외" 요구가 없어 end-user 전체 차단이 곧 서비스 중단이었다.
**이번 요구는 정확히 그 차단을 원하되(사내망 외 차단), 특정 그룹만 ingress로 carve-out** 한다.
즉 line 417의 관찰("discoveryengine 제한 = end-user 차단")은 이번 설계의 **레버**이며,
그룹 ingress 규칙이 그때 없던 안전판이다. 본 설계는 이 결정을 **의도적으로 되돌린다.**

## 4. 아키텍처 — 통제(kih/kis) vs 비통제(6개) 자회사

강제는 org-stack의 중앙 통합 Service Perimeter
(`iac/01.access-context-manager/service-perimeter/`)에서 일어난다. **단일 중앙 perimeter는
유지**하되, `discoveryengine`을 perimeter의 restricted_service로 넣고 **프로젝트 단위 ingress 규칙**으로
자회사별 정책을 표현한다.

### 4.1 핵심 제약 — restricted_services는 perimeter 전역
VPC-SC `restricted_services`는 perimeter 전체에 일괄 적용된다(프로젝트별 토글 불가). 8개 자회사
프로젝트가 모두 한 perimeter 안에 있으므로, discoveryengine을 제한하면 **8개 전부**가 영향을 받는다.
따라서 "kih/kis만 통제, 6개는 비통제"는 다음과 같이 표현한다:

- **통제 자회사(kih, kis):** 사내망 IP ingress + VIP 그룹 ingress만 부여 → 그 외 차단.
- **비통제 자회사(kisb/kic/kim/vam/kit/kip):** **전면 허용 ingress**(any identity, 소스 무관)를 부여 →
  discoveryengine 제한이 사실상 무력화되어 **현재 동작(누구나 인증되면 사용) 유지**. ← 미부여 시 막혀버림.

VPC-SC 접근 허용은 `(perimeter 내부) OR (perimeter-level access_levels) OR (ingress 매칭)`의 OR이다.
corp IP는 **perimeter-level `access_levels`가 아니라 자회사별 access level**에 담아 ingress로 묶는다
(perimeter-level에 넣으면 전 프로젝트로 통과 → kih/kis 한정 불가). ingress `sources`는 raw IP를 못
받고 access level만 받으므로 IP는 access level로 감싼다.

```
        discoveryengine.googleapis.com (perimeter restricted_service, 전역)
   ┌──────────────────────────────────────────────────────────────┐
   │ [통제: kih]  access level ge_corp_kih (ip 219.255.206/24,175.113.102/24)
   │   ingress(IP):    sources.access_level=ge_corp_kih → projects/<kih>
   │   ingress(그룹):  identities=group:kih-vip, 소스무관 → projects/<kih>
   │ [통제: kis]  access level ge_corp_kis (동일 IP)
   │   ingress(IP):    → projects/<kis>     ingress(그룹): kis-vip → projects/<kis>
   ├──────────────────────────────────────────────────────────────┤
   │ [비통제: kisb/kic/kim/vam/kit/kip]
   │   ingress(전면): identity_type=ANY_IDENTITY, 소스무관 → projects/<each>
   │                  → 제한 무력화, 현재 동작 유지
   └──────────────────────────────────────────────────────────────┘
   perimeter-level access_levels = [corp_access]  ← 기존 admin level, corp IP 안 넣음
```

### 4.2 판정 흐름
**통제 자회사 X(kih/kis)의 discoveryengine 호출:**
- X 사내망 사용자 → `ge_corp_X` IP 충족 ingress → 통과.
- X VIP 그룹 → 그룹 ingress(소스무관) → 어디서든 통과.
- 그 외(외부 비그룹) → 어떤 ingress에도 미해당 → **차단**.

**비통제 자회사의 호출:** 전면 허용 ingress → 항상 통과(인증만 되면). 사실상 제한 없음.

**기존 5개 서비스(aiplatform/storage/bigquery/dlp/cloudkms):** perimeter-level `corp_access`
(admin members)로 동작 불변 — corp IP를 거기 넣지 않으므로 영향 없음.

## 5. 구체적 변경 (Terraform)

### 5.1 `service-perimeter` 모듈 (`01.access-context-manager/service-perimeter/`)

**(a) 신규 변수 `subsidiary_ge_access`** (`variables.tf`) — 자회사별 GE 접근 맵

```hcl
variable "subsidiary_ge_access" {
  description = <<-EOT
    자회사별 GE(discoveryengine) 접근 정책 맵. key = 자회사 키.
      project_id        : 해당 자회사 GCP 프로젝트 ID (project number로 변환해 ingress resources에 사용)
      controlled        : true=사내망 IP + VIP 그룹만 허용(통제), false=전면 허용(비통제, 현재 동작 유지)
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

**(b) 자회사별 access level** (`main.tf`) — 통제 자회사에만 생성. **perimeter-level
`access_levels`에는 넣지 않는다**(kih/kis 한정 보존).

```hcl
resource "google_access_context_manager_access_level" "ge_corp" {
  for_each = local.enabled ? { for k, v in var.subsidiary_ge_access : k => v if v.controlled } : {}

  parent = local.parent
  name   = "${local.parent}/accessLevels/ge_corp_${each.key}"
  title  = "GE corp access (${each.key})"
  basic {
    conditions { ip_subnetworks = each.value.allowed_ip_ranges }
  }
}
```

**(c) 프로젝트 단위 ingress policy** (`main.tf`의 `status` 블록 안, 기존 admin ingress와 별도)

세 종류의 ingress를 생성한다. 모두 `ingress_to.resources`를 **해당 자회사 프로젝트로 한정**하고
`operations`를 discoveryengine으로 좁힌다.

```hcl
locals {
  ge_controlled   = { for k, v in var.subsidiary_ge_access : k => v if v.controlled }
  ge_uncontrolled = { for k, v in var.subsidiary_ge_access : k => v if !v.controlled }
  ge_with_group   = { for k, v in local.ge_controlled : k => v if length(v.external_members) > 0 }
}

# (1) 통제: 사내망 IP(access level) → 해당 프로젝트
dynamic "ingress_policies" {
  for_each = local.ge_controlled
  content {
    ingress_from {
      identity_type = "ANY_IDENTITY"
      sources { access_level = google_access_context_manager_access_level.ge_corp[ingress_policies.key].name }
    }
    ingress_to {
      operations { service_name = "discoveryengine.googleapis.com"; method_selectors { method = "*" } }
      resources = ["projects/${data.google_project.subsidiary[ingress_policies.key].number}"]
    }
  }
}

# (2) 통제: VIP 그룹 → 소스 무관(맨몸) → 해당 프로젝트
dynamic "ingress_policies" {
  for_each = local.ge_with_group
  content {
    ingress_from {
      identity_type = "ANY_IDENTITY"
      identities    = ingress_policies.value.external_members
      # sources 없음 → 임의 네트워크
    }
    ingress_to {
      operations { service_name = "discoveryengine.googleapis.com"; method_selectors { method = "*" } }
      resources = ["projects/${data.google_project.subsidiary[ingress_policies.key].number}"]
    }
  }
}

# (3) 비통제: 전면 허용(any identity, 소스 무관) → 해당 프로젝트 → 제한 무력화(현재 동작 유지)
dynamic "ingress_policies" {
  for_each = local.ge_uncontrolled
  content {
    ingress_from {
      identity_type = "ANY_IDENTITY"
      # identities/sources 없음 → 누구든, 어디서든
    }
    ingress_to {
      operations { service_name = "discoveryengine.googleapis.com"; method_selectors { method = "*" } }
      resources = ["projects/${data.google_project.subsidiary[ingress_policies.key].number}"]
    }
  }
}
```

> 주의 1: `subsidiary_ge_access`의 key는 `data.google_project.subsidiary`(현재
> `subsidiary_project_ids` 기반)와 정렬돼야 한다. `data.tf`를 맵 key로 조회 가능하게 맞춘다.
> 주의 2: 기존 GCP 제약(`access_level="*"` + `sources.resource` 공존 불가)은 본 설계에서
> 회피됨 — 명명된 access level만 쓰고 `sources.resource`는 안 쓴다.
> 주의 3: 현재 모듈의 `spec`(dry-run) 블록은 ingress_policies가 없다. 충실한 dry-run 시뮬레이션을
> 위해 **동일한 ingress_policies를 `spec` 블록에도 복제**해야 한다(안 그러면 ingress로 허용될
> 트래픽까지 위반으로 잡혀 신호가 흐려짐). status/spec 공통 ingress는 local로 묶어 중복 제거 권장.
> 주의 4: 비통제 전면 허용 ingress는 discoveryengine을 그 프로젝트에 대해 사실상 개방한다.
> 6개 자회사가 "통제 비대상"이라는 명시적 결정의 반영이며, 추후 통제 전환 시 `controlled=true`로 바꾼다.

### 5.2 root wiring (`iac/main.tf`, `variables.tf`)

- `module "service_perimeter"`에 `subsidiary_ge_access = var.perimeter_subsidiary_ge_access` 추가.
- root에 `variable "perimeter_subsidiary_ge_access"` (위 (a)와 동일 타입, default `{}`) 추가.

### 5.3 tfvars (`terraform.tfvars`)

- `perimeter_restricted_services`에 `"discoveryengine.googleapis.com"` 추가.
  (`content-discoveryengine.googleapis.com`은 §7 dry-run 검증 후 추가 판단.)
- `perimeter_subsidiary_ge_access` 채움 (확정된 IP):

```hcl
perimeter_subsidiary_ge_access = {
  # 통제 자회사 (사내망 IP + VIP 그룹만)
  kih  = { project_id = "kih-ge-prod",  controlled = true,  allowed_ip_ranges = ["219.255.206.0/24", "175.113.102.0/24"], external_members = ["group:kih-vip@koreainvestment.com"] }
  kis  = { project_id = "kis-ge-prod",  controlled = true,  allowed_ip_ranges = ["219.255.206.0/24", "175.113.102.0/24"], external_members = ["group:kis-vip@koreainvestment.com"] }
  # 비통제 자회사 (전면 허용 — 현재 동작 유지). VIP 그룹은 통제 전환 시 사용.
  kisb = { project_id = "kisb-ge-prod", controlled = false }
  kic  = { project_id = "kic-ge-prod",  controlled = false }
  kim  = { project_id = "kim-ge-prod",  controlled = false }
  vam  = { project_id = "vam-ge-prod",  controlled = false }
  kit  = { project_id = "kit-ge-prod",  controlled = false }
  kip  = { project_id = "kip-ge-prod",  controlled = false }
}
```

> 참고 1: kih·kis의 `allowed_ip_ranges`가 동일하므로 **IP 차원의 kih↔kis 격리는 없다**
> (같은 corp 망 egress). 남는 격리 경계 = (1) 외부 비corp망 전면 차단, (2) VIP 그룹의 자회사별 분리.
> 참고 2: **8개 자회사 전부 항목 필수.** discoveryengine restricted_services는 perimeter 전역이라,
> 맵에 없는 자회사는 ingress 미존재로 **전면 차단**된다. 비통제 6개는 `controlled=false`로 전면 허용 ingress 부여.
> 참고 3: 통제 대상은 kih/kis만(사용자 확정). 6개 자회사 IP는 해당 없음 → `controlled=false`.
> 참고 4: VIP 그룹 8개 입력 완료, `kip-vip`(오타 `Kkp-vip` 정정). 비통제 6개 그룹은 통제 전환 시 활성.

## 6. 설계 결정 (확정)

- **통제 대상 = kih, kis만** (사용자 확정). 두 자회사 GE는 사내망 IP + VIP 그룹만 허용.
- **비통제 = 6개**(kisb/kic/kim/vam/kit/kip). IP 해당 없음 → `controlled=false`로 **전면 허용 ingress** 부여,
  현재 동작(인증되면 누구나) 유지. discoveryengine restricted_services가 perimeter 전역이라
  미부여 시 오히려 막히므로 전면 허용 ingress가 **필수**.
- **확정 IP:** kih·kis 모두 `219.255.206.0/24` + `175.113.102.0/24` (동일). kih↔kis IP 격리 없음(같은 corp 망).
- **VIP 그룹:** kih→`kih-vip`, kis→`kis-vip`. (오타 정정: 8번째는 `kip-vip`.) 비통제 6개 그룹은
  통제 전환 시 활성. 통제 자회사의 VIP 그룹 carve-out은 해당 프로젝트로만 ingress → 자회사별 분리 유지.
- **기존 5개 서비스 동작 불변.** corp IP를 perimeter-level `access_levels`에 넣지 않으므로
  enforce 중인 aiplatform/storage/bigquery/dlp/cloudkms 접근 패턴에 영향 없음.

## 7. Load-bearing 가정과 검증 계획

**가정:** "VPC-SC가 Agentspace 웹 UI end-user의 discoveryengine 호출을 사용자
네트워크/신원 컨텍스트로 평가한다." (1차 증거 = line 417 운영 관찰.)

**검증(필수, enforce 전):**
1. `perimeter_dry_run = true`로 적용.
2. 1–2주 위반 로그(Logs Explorer, `vpcServiceControlsUniqueIdentifier` / `violationReason`) 수집.
3. 검증 항목:
   - **통제(kih/kis):** 사내망(IP) 호출이 ingress로 통과 / 외부 비그룹 호출이
     `NO_MATCHING_ACCESS_LEVEL`로 위반 기록(=enforce 시 차단) / VIP 그룹 호출이 그룹 ingress로 통과.
   - **비통제(6개):** 전면 허용 ingress로 **위반이 없어야** 한다(= enforce 후에도 안 막힘). ← 회귀 방지 핵심.
   - **그룹 격리:** kih VIP가 kis GE 호출 시 위반 기록되는가(그룹 ingress가 프로젝트별로 묶이는지).
4. `content-discoveryengine.googleapis.com` 포함 여부 결정(누락 시 우회 경로 생기는지).
5. 이상 없으면 `perimeter_dry_run = false`로 enforce 전환.

## 8. 리스크

- **`discoveryengine.clients6.google.com`** (Deep Research / 영상 생성)은 PSC 미지원으로 확인됨 →
  VPC-SC에서도 누수 또는 기능 저하 가능. dry-run에서 해당 기능 동작/위반을 별도 확인.
- **운영(Terraform/CI) 경로:** discoveryengine 제한 시 applier가 GE 리소스를 만들 때도
  perimeter 적용 → applier SA용 ingress 필요. 기존 admin ingress(`perimeter_ingress_identities`)에
  applier 신원이 포함되는지 확인·확장.
- **enforce 전환 = 서비스 차단 변경.** 반드시 dry-run 검증을 거친 후, 변경 시 dry-run 재가동 원칙(모듈 주석)을 따른다.
- **8개 전부 맵에 있어야 함.** `restricted_services`에 discoveryengine 추가는 perimeter 전역이라,
  `subsidiary_ge_access`에 없는 자회사 GE는 ingress 미존재로 **전면 차단**된다. 비통제 6개를
  `controlled=false`로 반드시 포함(전면 허용 ingress). 신규 자회사 추가 시에도 동일.
- **비통제 6개는 discoveryengine이 개방됨.** 전면 허용 ingress = 인증된 누구나 접근. "통제 비대상"
  결정의 직접 반영이며, 망 제한이 필요해지면 `controlled=true`로 전환.

## 9. 인수 기준 (Acceptance Criteria)

1. `discoveryengine.googleapis.com`이 perimeter `restricted_services`에 포함된다.
2. 통제 자회사(kih/kis)에 access level `ge_corp_<key>`가 생성되고 `ip_subnetworks` =
   `219.255.206.0/24` + `175.113.102.0/24`. corp IP는 perimeter-level `access_levels`에 안 들어간다.
3. ingress policy 3종이 생성된다: 통제 IP(kih/kis) / 통제 VIP 그룹(kih/kis) / 비통제 전면허용(6개).
   모두 `ingress_to.resources`가 해당 자회사 프로젝트로 한정. 통제 자회사만 access level 생성.
4. dry-run 로그로 §7 시나리오 확인: 통제(사내망 통과·외부비그룹 차단·VIP 통과), 비통제(위반 없음), 그룹 격리.
5. enforce 후: kih/kis는 corp망 + 각 VIP 그룹만 사용 가능, 외부 비그룹 차단. 비통제 6개는 영향 없음.
6. 기존 enforce 중인 5개 서비스 접근 패턴이 회귀 없이 유지된다.

## 10. 범위 밖 (Out of scope)

- LB Cloud Armor IP allowlist(defense-in-depth로 추후 추가 가능하나 본 요구 충족엔 불필요).
- IAP / Cloud Run 프록시 등 엣지 신원 게이트(API 레이어 강제로 대체됨).
- 비통제 6개 자회사의 망 통제(추후 `controlled=true` 전환 + IP 입력으로 동일 패턴 적용).
- 신규 자회사: `subsidiary_project_ids` + `subsidiary_ge_access` 항목 추가.
