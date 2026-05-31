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

## 4. 아키텍처

강제는 org-stack의 중앙 통합 Service Perimeter
(`iac/01.access-context-manager/service-perimeter/`)에서 일어난다.

```
                discoveryengine.googleapis.com (perimeter restricted_service)
                              │
   ┌──────────────────────────┼───────────────────────────┐
   │ access level corp_access  │  ingress policy (신규)      │
   │  ip_subnetworks = corp     │  identities = 외부허용 그룹  │
   │  → 사내망 호출 통과          │  sources 무관 → 어디서든 통과 │
   └──────────────────────────┴───────────────────────────┘
                              │
   그 외(외부 + 비그룹) → access level 불충족 + ingress 미해당 → 차단
```

- **전체 유저(사내망):** access level `corp_access`의 `ip_subnetworks` 충족 → 통과.
  사내망 밖이면 불충족 → discoveryengine 호출 차단 → GE 사용 불가.
- **외부 허용 그룹:** 신규 ingress policy가 `identities=[group:...]`를 소스 무관하게 허용 → 어디서든 통과.
- **그 외 외부:** access level 불충족 + 어떤 ingress에도 미해당 → 차단.

## 5. 구체적 변경 (Terraform)

### 5.1 `service-perimeter` 모듈 (`01.access-context-manager/service-perimeter/`)

**(a) 신규 변수 `ge_external_members`** (`variables.tf`)

```hcl
variable "ge_external_members" {
  description = "외부(사내망 밖)에서도 GE discoveryengine 호출이 허용되는 identity (group:/user:). 비면 그룹 carve-out 없음."
  type        = list(string)
  default     = []
}
```

**(b) 신규 ingress policy** (`main.tf`의 `status` 블록 안, 기존 admin ingress와 **별도 블록**)

기존에 발견된 GCP 제약(`access_level="*"` 과 `sources.resource`는 한 `ingress_from`에 공존 불가)을
피하기 위해 그룹 carve-out은 독립된 `ingress_policies` 블록으로 추가한다. 소스 제한 없이
신원만으로 허용하며, `ingress_to`는 discoveryengine 작업으로 좁힌다.

```hcl
dynamic "ingress_policies" {
  for_each = length(var.ge_external_members) > 0 ? [1] : []
  content {
    ingress_from {
      identity_type = "ANY_IDENTITY"
      identities    = var.ge_external_members
      # sources 없음 → 임의 네트워크(맨몸 외부) 허용
    }
    ingress_to {
      operations {
        service_name = "discoveryengine.googleapis.com"
        method_selectors { method = "*" }
      }
      resources = ["*"]
    }
  }
}
```

> 주: 기존 `status` 블록의 dry-run/enforce 분기 구조를 유지한다. dry-run(`spec`) 모드에서는
> ingress가 평가되지 않으므로(로깅만), enforce 검증 전에 위반 로그로 차단 대상/허용 대상을 먼저 본다.

### 5.2 root wiring (`iac/main.tf`, `variables.tf`)

- `module "service_perimeter"`에 `ge_external_members = var.perimeter_ge_external_members` 추가.
- root에 `variable "perimeter_ge_external_members"` (list(string), default `[]`) 추가.

### 5.3 tfvars (`terraform.tfvars`)

- `perimeter_restricted_services`에 `"discoveryengine.googleapis.com"` 추가.
  (`content-discoveryengine.googleapis.com`은 §7 dry-run 검증 후 추가 판단.)
- `perimeter_allowed_ip_ranges` = corp egress CIDR 채움(현재 `[]`).
- `perimeter_ge_external_members` = 외부 허용 Workspace 그룹 주소.

## 6. 설계 결정 (열린 항목에 대한 확정)

- **블래스트 반경 = org-wide.** perimeter는 중앙 통합(전 자회사 프로젝트 포함)이므로
  discoveryengine 제한은 모든 자회사에 적용된다. `ge_external_members`는 **단일 평면 리스트**
  (자회사 그룹들의 합집합)로 둔다. 자회사별 차등이 필요해지면 그때 분리한다(YAGNI).
- **corp CIDR / 그룹 주소**는 코드의 placeholder가 아니라 **apply 시 주입하는 입력값**으로 취급한다.
  enforce(`dry_run=false`) 전환 전 반드시 실제 값으로 채운다.

## 7. Load-bearing 가정과 검증 계획

**가정:** "VPC-SC가 Agentspace 웹 UI end-user의 discoveryengine 호출을 사용자
네트워크/신원 컨텍스트로 평가한다." (1차 증거 = line 417 운영 관찰.)

**검증(필수, enforce 전):**
1. `perimeter_dry_run = true`로 적용.
2. 1–2주 위반 로그(Logs Explorer, `vpcServiceControlsUniqueIdentifier` / `violationReason`) 수집.
3. 검증 항목:
   - 사내망 사용자 호출이 access level로 통과(위반 없음)하는가.
   - 외부 비그룹 사용자 호출이 `NO_MATCHING_ACCESS_LEVEL`로 위반 기록되는가(= enforce 시 차단될 것).
   - 외부 그룹 사용자 호출이 ingress로 통과하는가.
4. `content-discoveryengine.googleapis.com` 포함 여부 결정.
5. 이상 없으면 `perimeter_dry_run = false`로 enforce 전환.

## 8. 리스크

- **`discoveryengine.clients6.google.com`** (Deep Research / 영상 생성)은 PSC 미지원으로 확인됨 →
  VPC-SC에서도 누수 또는 기능 저하 가능. dry-run에서 해당 기능 동작/위반을 별도 확인.
- **운영(Terraform/CI) 경로:** discoveryengine 제한 시 applier가 GE 리소스를 만들 때도
  perimeter 적용 → applier SA용 ingress 필요. 기존 admin ingress(`perimeter_ingress_identities`)에
  applier 신원이 포함되는지 확인·확장.
- **enforce 전환 = 서비스 차단 변경.** 반드시 dry-run 검증을 거친 후, 변경 시 dry-run 재가동 원칙(모듈 주석)을 따른다.
- **org-wide 적용.** 한 자회사의 잘못된 CIDR/그룹이 전 자회사에 영향. tfvars 변경 리뷰 필수.

## 9. 인수 기준 (Acceptance Criteria)

1. `discoveryengine.googleapis.com`이 perimeter `restricted_services`에 포함된다.
2. `corp_access` access level의 `ip_subnetworks`에 실제 corp egress CIDR이 설정된다.
3. 외부 허용 그룹용 ingress policy가 생성되고, `ge_external_members`가 비면 0개로 토글된다.
4. dry-run 위반 로그로 §7의 3개 시나리오(사내망 통과 / 외부 비그룹 차단 / 외부 그룹 통과)가 실측 확인된다.
5. enforce 전환 후: 외부 비그룹 사용자는 GE 사용 불가, 외부 그룹 사용자는 사용 가능, 사내망 전체 사용 가능.

## 10. 범위 밖 (Out of scope)

- LB Cloud Armor IP allowlist(defense-in-depth로 추후 추가 가능하나 본 요구 충족엔 불필요).
- IAP / Cloud Run 프록시 등 엣지 신원 게이트(API 레이어 강제로 대체됨).
- 자회사별 그룹 차등(현재 평면 리스트, 필요 시 후속).
