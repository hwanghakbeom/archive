# Cloud Run Job egress가 Direct VPC를 통해 NAT의 정적 IP로 SNAT되도록 구성.
# on-prem 방화벽은 google_compute_address.scc_egress_nat 의 address 한 개만
# 화이트리스트로 등록하면 됨.

resource "google_compute_network" "scc_egress" {
  count = var.enable ? 1 : 0

  project                 = var.project_id
  name                    = "scc-forwarder-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "scc_egress" {
  count = var.enable ? 1 : 0

  project                  = var.project_id
  name                     = "scc-forwarder-subnet"
  region                   = var.region
  ip_cidr_range            = var.vpc_cidr
  network                  = google_compute_network.scc_egress[0].id
  private_ip_google_access = true
}

resource "google_compute_router" "scc_egress" {
  count = var.enable ? 1 : 0

  project = var.project_id
  name    = "scc-forwarder-router"
  region  = var.region
  network = google_compute_network.scc_egress[0].id
}

# NAT용 외부 정적 IP — 두 가지 모드 toggle.
#   var.use_existing_egress_ip = true  (default) → 같은 region의 reserved IP를 auto-discover.
#                                                  - egress_ip_name이 비어있으면 region의 첫번째 IP 사용 (정확히 1개일 때 안전)
#                                                  - egress_ip_name 지정 시 그 이름으로 정확 match
#   var.use_existing_egress_ip = false           → terraform이 신규 생성.

# 같은 region의 모든 reserved address 조회 — 이름 모르거나 변경된 경우에도 동작.
data "google_compute_addresses" "scc_egress_candidates" {
  count = var.enable && var.use_existing_egress_ip ? 1 : 0

  project = var.project_id
  region  = var.region
}

resource "google_compute_address" "scc_egress_nat" {
  count = var.enable && !var.use_existing_egress_ip ? 1 : 0

  project      = var.project_id
  name         = var.egress_ip_name
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

locals {
  # use_existing 모드에서 region 안의 reserved IP 목록.
  egress_candidates = length(data.google_compute_addresses.scc_egress_candidates) > 0 ? data.google_compute_addresses.scc_egress_candidates[0].addresses : []

  # egress_ip_name이 지정되면 이름 매칭. 아니면 region에 reserved IP가 1개일 때 그것 자동 선택.
  egress_matched = (
    var.egress_ip_name != "" ?
    [for a in local.egress_candidates : a if a.name == var.egress_ip_name] :
    local.egress_candidates
  )

  # 결과: terraform이 만든 자원(self_link) 또는 discover된 IP의 self_link/address.
  egress_ip_self_link = length(google_compute_address.scc_egress_nat) > 0 ? (
    google_compute_address.scc_egress_nat[0].self_link
    ) : (
    length(local.egress_matched) > 0 ? local.egress_matched[0].self_link : null
  )

  egress_ip_address = length(google_compute_address.scc_egress_nat) > 0 ? (
    google_compute_address.scc_egress_nat[0].address
    ) : (
    length(local.egress_matched) > 0 ? local.egress_matched[0].address : null
  )
}

# discover 결과 sanity check — 0개 / 2+개일 때 명확한 에러.
check "egress_ip_resolved" {
  assert {
    condition     = !var.enable || !var.use_existing_egress_ip || length(local.egress_matched) >= 1
    error_message = "use_existing_egress_ip=true 인데 region(${var.region})에 reserved IP가 없거나 egress_ip_name과 일치하는 게 없습니다. gcloud compute addresses list로 확인."
  }
  assert {
    condition     = !var.enable || !var.use_existing_egress_ip || var.egress_ip_name != "" || length(local.egress_candidates) <= 1
    error_message = "region(${var.region})에 reserved IP가 2개 이상 있는데 egress_ip_name이 비어있어 자동 선택 불가. egress_ip_name 지정 필요."
  }
}

resource "google_compute_router_nat" "scc_egress" {
  count = var.enable ? 1 : 0

  project                            = var.project_id
  name                               = "scc-forwarder-nat"
  router                             = google_compute_router.scc_egress[0].name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [local.egress_ip_self_link]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.scc_egress[0].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
