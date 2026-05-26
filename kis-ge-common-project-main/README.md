# kis-ge-common-project — Org-level Terraform Stack

KRInvest GCP 조직 전체에 영향을 미치는 자원만 다루는 Terraform stack.
자회사별 자원(Discovery Engine, IAM bindings, KMS, GE App, ...)은 별도
자회사 stack(`kis-ge-project`, `kih-ge-project`, ...)에서 관리한다.

## 모듈 구조

```
iac/
├── 01.access-context-manager/
│   └── access-policy/                   # Phase 1: Access Policy (org당 1개)
├── 02.org-policies/
│   ├── storage-policies/                # Phase 2: publicAccessPrevention + UBLA
│   └── cmek-policies/                   # Phase 2: restrictNonCmekServices (조건부)
└── 03.observability/
    ├── aggregated-log-sink/             # Phase 3: 조직 cloudaudit → 중앙 GCS
    └── org-audit-config/                # Phase 3: DATA_READ/WRITE 강제 (조건부)
```

## 책임 범위

| Phase | 모듈 | 자원 | 기본값 | 영향도 |
|---|---|---|---|---|
| 1 | `access-policy` | `google_access_context_manager_access_policy` | 항상 생성 | 낮음 (정책만, 강제 X) |
| 2 | `storage-policies` | `google_org_policy_policy` × 2 (publicAccessPrevention + UBLA) | enforce=true | 중간 (신규 GCS만) |
| 2 | `cmek-policies` | `google_org_policy_policy` (restrictNonCmekServices) | enable=false | 중간 (활성화 시 신규 자원) |
| 3 | `aggregated-log-sink` | `google_storage_bucket` + `google_logging_organization_sink` + IAM | 항상 생성 | 낮음 (수집만, 비용 영향 있음) |
| 3 | `org-audit-config` | `google_organization_iam_audit_config` | enable=false | 중간 (활성화 시 비용 큼) |

## 추가 예정 (향후 차수)

- `gcp.resourceLocations` (asia-northeast3 강제)
- `gcp.restrictServiceUsage` (필수 API 외 차단)
- `iam.disableServiceAccountKeyCreation`
- `iam.disableCrossProjectServiceAccountUsage`
- `iam.allowedPolicyMemberDomains` — ⚠️ 작업자 도메인 lock 위험, 가장 마지막
- SCC Premium/Enterprise 활성화 (ETD, Attack Path, Mandiant)

## 사전 준비

### 1. Service Account (org-level admin)

기존 자회사 stack용 SA와 **분리된** 별도 SA를 권장.

권장 SA: `org-foundation-tf@kis-common-gcp.iam.gserviceaccount.com`

조직 IAM 권한:

```
roles/accesscontextmanager.policyAdmin     # Phase 1
roles/orgpolicy.policyAdmin                # Phase 2
roles/logging.admin                        # Phase 3-A
roles/iam.securityAdmin                    # Phase 3-B
roles/securitycenter.admin                 # (옵션) SCC 활성화 시
```

ops 프로젝트(`kis-common-gcp`) 권한:

```
roles/storage.admin                        # state bucket access (GCS backend)
roles/serviceusage.serviceUsageConsumer    # API 호출 (user_project_override)
```

> Cloud Build 권한은 더 이상 필요 없음 — GitLab runner에서 terraform을 직접 실행.

### 2. GitLab CI/CD Variables

`Settings > CI/CD > Variables`:

| Key | Value | Type | Protected | Masked |
|---|---|---|---|---|
| `GCP_TF_SA_KEY` | 위 SA의 JSON 키 | **File** | ✓ | ✓ |
| `GCP_TF_PROJECT` | `kis-common-gcp` | Variable | ✓ | – |

### 3. State Backend

기존 자회사 stack과 같은 bucket, 다른 prefix:

```
gs://kis-common-gcp-tfstate/lzone/org/default.tfstate
```

## 첫 배포 절차

1. **`terraform.tfvars` 작성**:
   ```bash
   cp iac/terraform.tfvars.example iac/terraform.tfvars
   # 실제 값 확인/수정
   ```

2. **main 브랜치 push** → GitLab 파이프라인 시작

3. **순서대로 ▶ 클릭**:
   - `apply-acm` → Access Policy 생성
   - `apply-storage-policies` → publicAccessPrevention + UBLA 강제
   - `apply-cmek-policies` → (선택) restrictNonCmekServices 활성화 시
   - `apply-aggregated-sink` → 중앙 audit bucket + sink
   - `apply-org-audit-config` → (선택) DATA_READ/WRITE 강제 시
   - `apply-verify` → 전체 plan no-op 확인

4. **outputs 확인**:
   ```bash
   cd iac
   terraform init -backend-config="bucket=kis-common-gcp-tfstate" \
                  -backend-config="prefix=lzone/org"
   terraform output
   # access_policy_id = "123456789"
   # central_audit_bucket = "kis-common-gcp-org-audit-logs"
   # ...
   ```

## 자회사 Stack과 연결

자회사 stack(예: `kis-ge-project`)의 `02.security/vpc-sc/` 모듈이 본 stack의
Access Policy를 참조하도록 수정:

```hcl
# kis-ge-project/iac/envs/prd1/main.tf
data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = "kis-common-gcp-tfstate"
    prefix = "lzone/org"
  }
}

module "vpc_sc" {
  source           = "./02.security/vpc-sc"
  enable_vpc_sc    = true                                                      # 활성화
  access_policy_id = data.terraform_remote_state.org.outputs.access_policy_id  # ← 공유
  # ...
}
```

자회사 stack의 vpc_sc 모듈은 `var.access_policy_id != null` 이면 자체적으로
access policy를 만들지 않고 공유 (`local.managed_policy = false`).

## CI/CD 파이프라인 구조

```
[validate]                    (MR event 시 자동)
        ↓
[plan]                        (MR event 시 자동)
        ↓
[apply-acm]                   ▶ manual — Access Policy
        ↓
[apply-storage-policies]      ▶ manual — publicAccessPrevention + UBLA
        ↓
[apply-cmek-policies]         ▶ manual — restrictNonCmekServices (조건부)
        ↓
[apply-aggregated-sink]       ▶ manual — Org log sink + GCS
        ↓
[apply-org-audit-config]      ▶ manual — DATA_READ/WRITE 강제 (조건부)
        ↓
[apply-verify]                ▶ manual — 전체 plan no-op
```

## 주의

- **`prevent_destroy = true`** (Access Policy): 실수 destroy 방지.
- **조직당 정책 1개 제약**: 이미 다른 도구로 만들어진 Access Policy 있다면
  `terraform import 'module.access_policy.google_access_context_manager_access_policy.this' <numeric_id>`.
- **CMEK 강제 시점**: 자회사 stack의 KMS keyring + key가 먼저 준비된 후에
  `enable_restrict_non_cmek = true`로 활성화 권장.
- **DATA_READ/WRITE 비용 영향**: `enable_org_data_access_audit` 활성화 전 비용
  검토. 자회사 sink와 중복 수집 시 Log Router 필터 활용 권장.
