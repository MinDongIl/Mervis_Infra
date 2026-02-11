# 1. VPC 생성
resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = false # 수동 모드 (보안 필수)
}

# 2. Subnet 생성 (3개로 분리)
# 2-1. Public Subnet (로드밸런서용)
resource "google_compute_subnetwork" "public" {
  name          = "${var.project_id}-subnet-public"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# 2-2. Private Subnet A (Serving Zone - 서비스용)
resource "google_compute_subnetwork" "private_serving" {
  name          = "${var.project_id}-subnet-serving"
  ip_cidr_range = "10.0.10.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  private_ip_google_access = true # 구글 API 내부 통신 허용
}

# 2-3. Private Subnet B (Training Zone - 학습용)
resource "google_compute_subnetwork" "private_training" {
  name          = "${var.project_id}-subnet-training"
  ip_cidr_range = "10.0.20.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  private_ip_google_access = true
}

# 3. Cloud NAT (사설망 서버들이 인터넷으로 나가는 유일한 통로)
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

# 4. 방화벽 규칙
# 4-1. IAP를 통한 SSH 허용 (보안: 22번 포트를 아무나 못 열게 함)
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.project_id}-allow-ssh-iap"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"] # Google IAP 전용 IP 대역
}

# 4-2. 로드밸런서 헬스체크 허용
resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.project_id}-allow-lb-health-check"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"] # Google LB 전용 IP 대역
}

# 4-3. 내부 통신 허용 (서버끼리)
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.project_id}-allow-internal"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  source_ranges = ["10.0.0.0/16"] # VPC 내부 대역 전체
}

# Output
output "network_name" { value = google_compute_network.vpc.name }
output "subnet_serving_id" { value = google_compute_subnetwork.private_serving.id }
output "subnet_training_id" { value = google_compute_subnetwork.private_training.id }