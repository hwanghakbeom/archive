# 조직 전체에 자원이 생성될 수 있는 리전을 제한한다.
# 한국 데이터 주권 / 금융권 가이드라인 / 전자금융감독규정 대응.
#
# 주의: DLP/Model Armor templates는 us multi-region에서만 KR_* 빌트인
# detector가 동작하므로, allowed_locations에 in:us-locations 또는
# in:asia-locations 같은 multi-region이 포함되어야 한다.
resource "google_org_policy_policy" "resource_locations" {
  count = var.enable_resource_locations ? 1 : 0

  name   = "organizations/${var.org_id}/policies/gcp.resourceLocations"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = var.allowed_locations
      }
    }
  }
}
