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

## 4. 아키텍처 — 자회사별 IP 격리

강제는 org-stack의 중앙 통합 Service Perimeter
(`iac/01.access-context-manager/service-perimeter/`)에서 일어난다. **단일 중앙 perimeter는
유지**하되, discoveryengine 접근은 **자회사별 access level + 프로젝트 단위 ingress 규칙**으로 격리한다.

### 4.1 왜 자회사별 access level + ingress인가
VPC-SC에서 protected resource 접근 허용은 `(perimeter 내부) OR (perimeter-level access_levels 충족)
OR (ingress policy 매칭)`의 합집합(OR)이다. 따라서 corp IP를 **perimeter-level `access_levels`** 에
넣으면 그 IP는 perimeter의 **모든** 프로젝트(전 자회사 discoveryengine)에 통과 → 격리 불가.

해결: corp IP를 perimeter-level이 아니라 **자회사별 access level**에 담고, **ingress policy의
`ingress_to.resources`를 해당 자회사 프로젝트로 한정**한다. (ingress `sources`는 raw IP를 못 받고
access level 또는 resource만 받으므로 IP는 반드시 access level로 감싼다.)

```
        discoveryengine.googleapis.com (perimeter restricted_service)
   ┌──────────────────────────────────────────────────────────────┐
   │ [자회사 kih]                                                    │
   │  access level ge_corp_kih (ip 219.255.206.0/24,175.113.102/24) │
   │     └─ ingress: sources.access_level=ge_corp_kih               │
   │                 to: projects/<kih>, ops=discoveryengine        │
   │  ingress(그룹): identities=group:kih_external, sources 무관      │
   │                 to: projects/<kih>, ops=discoveryengine        │
   ├──────────────────────────────────────────────────────────────┤
   │ [자회사 kis]                                                    │
   │  access level ge_corp_kis (ip 219.255.206.0/24,175.113.102/24) │
   │     └─ ingress: → to: projects/<kis>, ops=discoveryengine      │
   │  ingress(그룹): identities=group:kis_external → projects/<kis>  │
   └──────────────────────────────────────────────────────────────┘
   perimeter-level access_levels = [corp_access]  ← 기존 admin level(members),
                                                     corp IP는 여기 넣지 않음(격리 보존)
```

### 4.2 판정 흐름 (자회사 X의 discoveryengine 호출)
- **X 사내망 사용자:** `ge_corp_X` IP 충족 + ingress가 `projects/<X>`로 한정 → 통과. **타 자회사 IP는 매칭 안 됨.**
- **X 외부 허용 그룹:** 그룹 ingress가 소스 무관 + `projects/<X>` → 어디서든 통과.
- **그 외(외부 비그룹 / 타 자회사 사내망):** access level 불충족 + 어떤 ingress에도 미해당 → 차단.
- 기존 enforce 중인 5개 서비스(aiplatform/storage/bigquery/dlp/cloudkms)는 perimeter-level
  `corp_access`(admin members)로 **동작 불변** — corp IP를 거기 넣지 않으므로 영향 없음.

## 5. 구체적 변경 (Terraform)

### 5.1 `service-perimeter` 모듈 (`01.access-context-manager/service-perimeter/`)

**(a) 신규 변수 `subsidiary_ge_access`** (`variables.tf`) — 자회사별 GE 접근 맵

```hcl
variable "subsidiary_ge_access" {
  description = <<-EOT
    자회사별 GE(discoveryengine) 접근 제어 맵. key = 자회사 키.
      project_id        : 해당 자회사 GCP 프로젝트 ID (project number로 변환해 ingress resources에 사용)
      allowed_ip_ranges : 사내망 egress CIDR (이 자회사 GE는 이 IP에서만 허용)
      external_members  : 외부(맨몸) 허용 identity (group:/user:). 비면 그룹 carve-out 없음.
  EOT
  type = map(object({
    project_id        = string
    allowed_ip_ranges = list(string)
    external_members  = list(string)
  }))
  default = {}
}
```

**(b) 자회사별 access level** (`main.tf`) — corp IP를 자회사별로 분리. **perimeter-level
`access_levels`에는 넣지 않는다**(격리 보존).

```hcl
resource "google_access_context_manager_access_level" "ge_corp" {
  for_each = local.enabled ? var.subsidiary_ge_access : {}

  parent = local.parent
  name   = "${local.parent}/accessLevels/ge_corp_${each.key}"
  title  = "GE corp access (${each.key})"
  basic {
    conditions { ip_subnetworks = each.value.allowed_ip_ranges }
  }
}
```

**(c) 프로젝트 단위 ingress policy** (`main.tf`의 `status` 블록 안, 기존 admin ingress와 별도)

`status` 블록을 자회사별 ingress로 확장한다. 각 자회사마다 (1) 사내망 IP ingress,
(2) 외부 그룹 ingress 두 종류를 생성하며, 둘 다 `ingress_to.resources`를 **해당 자회사
프로젝트로 한정**하고 `operations`를 discoveryengine으로 좁힌다.

```hcl
# (1) 사내망: access level(IP) → 해당 프로젝트
dynamic "ingress_policies" {
  for_each = var.subsidiary_ge_access
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

# (2) 외부 그룹: 소스 무관(맨몸) → 해당 프로젝트 (external_members 있을 때만)
dynamic "ingress_policies" {
  for_each = { for k, v in var.subsidiary_ge_access : k => v if length(v.external_members) > 0 }
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
```

> 주의 1: `subsidiary_ge_access`의 key는 `data.google_project.subsidiary` (현재
> `subsidiary_project_ids` 기반)와 정렬돼야 한다. `data.tf`를 맵 key로 조회 가능하게 맞춘다.
> 주의 2: 기존 GCP 제약(`access_level="*"` + `sources.resource` 공존 불가)은 본 설계에서
> 회피됨 — 명명된 access level만 쓰고 `sources.resource`는 안 쓴다.
> 주의 3: 현재 모듈의 `spec`(dry-run) 블록은 ingress_policies가 없다. 충실한 dry-run 시뮬레이션을
> 위해 **동일한 ingress_policies를 `spec` 블록에도 복제**해야 한다(안 그러면 ingress로 허용될
> 트래픽까지 위반으로 잡혀 신호가 흐려짐). status/spec 공통 ingress는 local로 묶어 중복 제거 권장.

### 5.2 root wiring (`iac/main.tf`, `variables.tf`)

- `module "service_perimeter"`에 `subsidiary_ge_access = var.perimeter_subsidiary_ge_access` 추가.
- root에 `variable "perimeter_subsidiary_ge_access"` (위 (a)와 동일 타입, default `{}`) 추가.

### 5.3 tfvars (`terraform.tfvars`)

- `perimeter_restricted_services`에 `"discoveryengine.googleapis.com"` 추가.
  (`content-discoveryengine.googleapis.com`은 §7 dry-run 검증 후 추가 판단.)
- `perimeter_subsidiary_ge_access` 채움 (확정된 IP):

```hcl
perimeter_subsidiary_ge_access = {
  # 공통 corp CIDR (kih·kis 확인됨, 나머지 6개는 동일 여부 확인 필요)
  kih  = { project_id = "kih-ge-prod",  allowed_ip_ranges = ["219.255.206.0/24", "175.113.102.0/24"], external_members = ["group:kih-vip@koreainvestment.com"] }
  kis  = { project_id = "kis-ge-prod",  allowed_ip_ranges = ["219.255.206.0/24", "175.113.102.0/24"], external_members = ["group:kis-vip@koreainvestment.com"] }
  kisb = { project_id = "kisb-ge-prod", allowed_ip_ranges = [], external_members = ["group:kisb-vip@koreainvestment.com"] }  # IP 입력 대기
  kic  = { project_id = "kic-ge-prod",  allowed_ip_ranges = [], external_members = ["group:kic-vip@koreainvestment.com"] }   # IP 입력 대기
  kim  = { project_id = "kim-ge-prod",  allowed_ip_ranges = [], external_members = ["group:kim-vip@koreainvestment.com"] }   # IP 입력 대기
  vam  = { project_id = "vam-ge-prod",  allowed_ip_ranges = [], external_members = ["group:vam-vip@koreainvestment.com"] }   # IP 입력 대기
  kit  = { project_id = "kit-ge-prod",  allowed_ip_ranges = [], external_members = ["group:kit-vip@koreainvestment.com"] }   # IP 입력 대기
  kip  = { project_id = "kip-ge-prod",  allowed_ip_ranges = [], external_members = ["group:Kkp-vip@koreainvestment.com"] }   # ⚠ 그룹명 kip vs Kkp 확인 / IP 입력 대기
}
```

> 참고 1: kih·kis의 `allowed_ip_ranges`가 동일하므로 **IP 차원의 자회사 간 격리는 없다**
> (같은 corp 망 egress). 남는 격리 경계 = (1) 외부 비corp망 전면 차단, (2) 외부 그룹의
> 자회사별 분리(ingress가 프로젝트별로 묶임).
> 참고 2: **8개 자회사 전부 항목이 있어야 한다.** discoveryengine restricted_services 추가는
> perimeter 전역이므로, `subsidiary_ge_access`에 없는(또는 `allowed_ip_ranges`가 빈) 자회사는
> 사내망에서도 ingress 미존재로 **전면 차단**된다. enforce 전 6개 자회사 IP 확정 필수.
> 참고 3: `Kkp-vip` 그룹명은 자회사 키 `kip`과 철자 불일치 — 실제 그룹 주소 확인 후 확정.

## 6. 설계 결정 (열린 항목에 대한 확정)

- **자회사별 IP 격리.** 단일 중앙 perimeter를 유지하되 corp IP는 자회사별 access level에 담고
  프로젝트 단위 ingress로 한정 → 자회사 간 IP 교차 통과 차단. (사용자 확정: "자회사별 격리 필요")
- **확정 IP:** kih·kis 모두 `219.255.206.0/24` + `175.113.102.0/24` (동일 집합).
  → **IP 차원 자회사 격리는 없음**(같은 corp 망). 격리 경계는 외부 차단 + 외부그룹 자회사별 분리.
- **외부 허용 그룹은 자회사별 VIP 그룹**(`subsidiary_ge_access[*].external_members`). 그룹 carve-out은
  해당 자회사 프로젝트로만 ingress → 이 차원에서는 자회사 격리 유지. 8개 그룹 매핑:
  kih→`kih-vip`, kis→`kis-vip`, kisb→`kisb-vip`, kic→`kic-vip`, kim→`kim-vip`,
  vam→`vam-vip`, kit→`kit-vip`, kip→`Kkp-vip`(⚠ 철자 확인).
- **기존 5개 서비스 동작 불변.** corp IP를 perimeter-level `access_levels`에 넣지 않으므로
  enforce 중인 aiplatform/storage/bigquery/dlp/cloudkms 접근 패턴에 영향 없음.
- **적용 범위 = 8개 자회사 전부** (kih/kis/kisb/kic/kim/vam/kit/kip). discoveryengine 제한이
  perimeter 전역이라 부분 적용 불가 — enforce 전 8개 모두 IP·그룹 확정 필요.
  IP는 kih·kis만 확인됨, 나머지 6개 입력 대기.

## 7. Load-bearing 가정과 검증 계획

**가정:** "VPC-SC가 Agentspace 웹 UI end-user의 discoveryengine 호출을 사용자
네트워크/신원 컨텍스트로 평가한다." (1차 증거 = line 417 운영 관찰.)

**검증(필수, enforce 전):**
1. `perimeter_dry_run = true`로 적용.
2. 1–2주 위반 로그(Logs Explorer, `vpcServiceControlsUniqueIdentifier` / `violationReason`) 수집.
3. 검증 항목 (자회사별):
   - X 사내망(X IP) 사용자 호출이 ingress로 통과(위반 없음)하는가.
   - 외부 비그룹 사용자 호출이 `NO_MATCHING_ACCESS_LEVEL`로 위반 기록되는가(= enforce 시 차단될 것).
   - 외부 그룹 사용자 호출이 그룹 ingress로 통과하는가.
   - **외부 그룹 격리 실측:** kih 외부그룹이 kis GE를 호출하면 위반(차단)되는가(그룹 carve-out이
     프로젝트별로 묶이는지). *IP 차원은 kih·kis 동일 집합이라 inter-subsidiary 격리 테스트 해당 없음.*
4. `content-discoveryengine.googleapis.com` 포함 여부 결정.
5. 이상 없으면 `perimeter_dry_run = false`로 enforce 전환.

## 8. 리스크

- **`discoveryengine.clients6.google.com`** (Deep Research / 영상 생성)은 PSC 미지원으로 확인됨 →
  VPC-SC에서도 누수 또는 기능 저하 가능. dry-run에서 해당 기능 동작/위반을 별도 확인.
- **운영(Terraform/CI) 경로:** discoveryengine 제한 시 applier가 GE 리소스를 만들 때도
  perimeter 적용 → applier SA용 ingress 필요. 기존 admin ingress(`perimeter_ingress_identities`)에
  applier 신원이 포함되는지 확인·확장.
- **enforce 전환 = 서비스 차단 변경.** 반드시 dry-run 검증을 거친 후, 변경 시 dry-run 재가동 원칙(모듈 주석)을 따른다.
- **블래스트 반경은 자회사 단위로 한정됨.** ingress가 프로젝트별로 묶여 한 자회사의 잘못된
  CIDR/그룹은 그 자회사 GE에만 영향. 단 `restricted_services`에 discoveryengine 추가 자체는
  perimeter 전역 변경이므로, `subsidiary_ge_access`에 **없는** 자회사의 discoveryengine은
  ingress가 없어 전면 차단될 수 있음 → 롤아웃 전 해당 자회사 항목 선반영 필수.

## 9. 인수 기준 (Acceptance Criteria)

1. `discoveryengine.googleapis.com`이 perimeter `restricted_services`에 포함된다.
2. 자회사별 access level `ge_corp_<key>`가 생성되고 `ip_subnetworks`에 해당 자회사 CIDR이 설정된다
   (kih·kis 모두 `219.255.206.0/24` + `175.113.102.0/24`). corp IP는 perimeter-level `access_levels`에 들어가지 않는다.
3. 자회사별 ingress policy 2종(사내망 IP / 외부 그룹)이 생성되고, `ingress_to.resources`가 해당
   자회사 프로젝트로 한정된다. `external_members`가 비면 그룹 ingress는 0개로 토글된다.
4. dry-run 위반 로그로 §7 시나리오(사내망 통과 / 외부 비그룹 차단 / 외부 그룹 통과 / **외부그룹 자회사 격리**)가 실측 확인된다.
5. enforce 전환 후: 자회사 X는 X corp망 + X 외부그룹만 GE 사용 가능, 외부 비그룹은 차단.
   (kih·kis IP 동일이므로 corp망 내 inter-subsidiary 접근은 허용됨 — 의도된 동작.)
6. 기존 enforce 중인 5개 서비스 접근 패턴이 회귀 없이 유지된다.

## 10. 범위 밖 (Out of scope)

- LB Cloud Armor IP allowlist(defense-in-depth로 추후 추가 가능하나 본 요구 충족엔 불필요).
- IAP / Cloud Run 프록시 등 엣지 신원 게이트(API 레이어 강제로 대체됨).
- 8개 자회사 외 신규 자회사: 동일 패턴으로 `subsidiary_project_ids` + `subsidiary_ge_access` 항목 추가.
