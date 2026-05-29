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

resource "google_compute_address" "scc_egress_nat" {
  count = var.enable ? 1 : 0

  project      = var.project_id
  name         = var.egress_ip_name
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

resource "google_compute_router_nat" "scc_egress" {
  count = var.enable ? 1 : 0

  project                            = var.project_id
  name                               = "scc-forwarder-nat"
  router                             = google_compute_router.scc_egress[0].name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.scc_egress_nat[0].self_link]
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
