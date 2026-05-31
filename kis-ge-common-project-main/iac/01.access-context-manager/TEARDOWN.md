# VPC-SC 중앙 perimeter(GE 접근 통제) 삭제 runbook

GE 접근 통제(중앙 service perimeter + access level)를 제거해 **전 자회사 GE/제한
서비스 접근을 무제한(통제 이전 상태)으로 되돌리는** 절차. enforce 적용이 계속 실패할
때의 철수(teardown)용.

> ⚠️ 이 문서는 설명용. 실제 삭제는 아래 ①(변수 플립) + ②(apply)로만 트리거됨.

## 무엇이 삭제되나

`enable_central_perimeter = false` 로 두면 `module.service_perimeter`의 자원이 전부
count=0 / for_each={} 가 되어 파괴된다:

- `google_access_context_manager_service_perimeter.central[0]` — perimeter
- `google_access_context_manager_access_level.corp[0]` — corp_access
- `google_access_context_manager_access_level.ge_corp["kih"|"kis"]` — 사내망 IP
- (코드에서 이미 제거된) `...access_level.ge_vip[...]` 잔존분도 함께 파괴

**유지되는 것**: access policy(`accessPolicies/919798527878`, `prevent_destroy=true`),
콘솔 수동 생성 stray access level(`ip_*`, terraform 비관리 → 콘솔에서 별도 삭제).

## ① 변수 플립

`iac/terraform.tfvars.example`:
```hcl
enable_central_perimeter = false
```

## ② 적용 (단일 실행 — 삭제 순서는 terraform이 처리)

GitLab `apply-service-perimeter` (REFRESH=true).
perimeter가 access level을 참조하므로 terraform이 **perimeter 먼저, access level 나중**
순으로 파괴 → "must first remove the reference" 에러 없이 한 번에 정리됨.

예상 plan:
```
Plan: 0 to add, 0 to change, N to destroy
  - service_perimeter.central[0]
  - access_level.corp[0]
  - access_level.ge_corp["kih"], ["kis"]
  - access_level.ge_vip["kih"], ["kis"]   # 잔존분
```

## ③ (fallback) 파괴 순서 에러 시 2단계

만약 access level이 먼저 삭제되려다 "must first remove the reference"가 나면,
perimeter를 먼저 파괴한 뒤 나머지를 정리:
```bash
# 1) perimeter만 먼저 파괴 (enable=false 상태에서 perimeter 리소스 타깃)
terraform apply -target='module.service_perimeter.google_access_context_manager_service_perimeter.central[0]'
# 2) 나머지 access level 파괴
terraform apply -target=module.service_perimeter
```
(CI에선 PERIMETER_ONLY=true 로 ①에 해당하는 perimeter-only 실행 가능.)

## ④ 검증

- `gcloud access-context-manager perimeters list --policy=919798527878` → 0개
- `gcloud access-context-manager levels list --policy=919798527878` → corp/ge_corp/ge_vip 없음
- 전 자회사 GE 접근이 IP/그룹 제한 없이 가능(통제 해제) 확인

## ⑤ 정리

- stray `ip_*` access level은 콘솔에서 수동 삭제(원하면).
- 재도입 시 `enable_central_perimeter = true` + apply (단, GE 호환 ingress(sources
  access_level="*") 가 반영된 상태여야 enforce 차단 재발 안 함).
