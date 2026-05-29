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
#   var.use_existing_egress_ip = true  (default) → 기존 예약 IP를 data로 lookup만 함.
#                                                  (gcloud로 미리 만들어 두거나 콘솔에서 예약된 자원)
#   var.use_existing_egress_ip = false           → terraform이 신규 생성.
# IP 이름은 두 모드 모두 var.egress_ip_name 사용.

data "google_compute_address" "scc_egress_nat_existing" {
  count = var.enable && var.use_existing_egress_ip ? 1 : 0

  project = var.project_id
  name    = var.egress_ip_name
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
  # enable=false면 둘 다 0개 → null. 그 외엔 활성 쪽에서 값 추출.
  egress_ip_self_link = length(google_compute_address.scc_egress_nat) > 0 ? (
    google_compute_address.scc_egress_nat[0].self_link
    ) : (
    length(data.google_compute_address.scc_egress_nat_existing) > 0
    ? data.google_compute_address.scc_egress_nat_existing[0].self_link
    : null
  )

  egress_ip_address = length(google_compute_address.scc_egress_nat) > 0 ? (
    google_compute_address.scc_egress_nat[0].address
    ) : (
    length(data.google_compute_address.scc_egress_nat_existing) > 0
    ? data.google_compute_address.scc_egress_nat_existing[0].address
    : null
  )
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
