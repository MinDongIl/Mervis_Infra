# VPC 생성
resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = false
}

# Public Subnet (로드밸런서용)
resource "google_compute_subnetwork" "public" {
  name          = "${var.project_id}-subnet-public"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Private Subnet A (서울 Serving Zone)
resource "google_compute_subnetwork" "private_serving" {
  name                     = "${var.project_id}-subnet-serving"
  ip_cidr_range            = "10.0.10.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Private Subnet B (서울 Training Zone)
resource "google_compute_subnetwork" "private_training" {
  name                     = "${var.project_id}-subnet-training"
  ip_cidr_range            = "10.0.20.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Private Subnet C (도쿄 Serving Zone - DR용)
resource "google_compute_subnetwork" "private_serving_tokyo" {
  name                     = "${var.project_id}-subnet-serving-tokyo"
  ip_cidr_range            = "10.0.30.0/24"
  region                   = "asia-northeast1"
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# 서울 리전 Cloud NAT
resource "google_compute_router" "router" {
  name    = "${var.project_id}-router"
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.project_id}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# 도쿄 리전 Cloud NAT
resource "google_compute_router" "router_tokyo" {
  name    = "${var.project_id}-router-tokyo"
  network = google_compute_network.vpc.id
  region  = "asia-northeast1"
}

resource "google_compute_router_nat" "nat_tokyo" {
  name                               = "${var.project_id}-nat-tokyo"
  router                             = google_compute_router.router_tokyo.name
  region                             = "asia-northeast1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# IAP SSH 방화벽
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.project_id}-allow-ssh-iap"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}

# Health Check 방화벽
resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.project_id}-allow-lb-health-check"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}

# 내부 통신 방화벽
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.project_id}-allow-internal"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  source_ranges = ["10.0.0.0/16"]
}

output "network_name" { value = google_compute_network.vpc.name }
output "subnet_serving_id" { value = google_compute_subnetwork.private_serving.id }
output "subnet_training_id" { value = google_compute_subnetwork.private_training.id }
output "subnet_serving_tokyo_id" { value = google_compute_subnetwork.private_serving_tokyo.id }