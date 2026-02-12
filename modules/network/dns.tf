# ==============================================================================
# Cloud DNS Zone (도메인 관리 영역)
# ==============================================================================
resource "google_dns_managed_zone" "mervis_zone" {
  name        = "mervis-cloud-zone"
  dns_name    = "mervis.cloud."
  description = "Mervis Trading System DNS Zone"
  visibility  = "public"

  labels = {
    env = "prod"
  }
}

# ==============================================================================
# DNS Records (도메인 연결)
# ==============================================================================
# 1. mervis.cloud -> 로드밸런서 IP
resource "google_dns_record_set" "mervis_root" {
  name         = "mervis.cloud."
  managed_zone = google_dns_managed_zone.mervis_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = [var.lb_ip_address]
}

# 2. www.mervis.cloud -> 로드밸런서 IP
resource "google_dns_record_set" "mervis_www" {
  name         = "www.mervis.cloud."
  managed_zone = google_dns_managed_zone.mervis_zone.name
  type         = "A"
  ttl          = 300
  rrdatas      = [var.lb_ip_address]
}

# Output
output "name_servers" {
  value = google_dns_managed_zone.mervis_zone.name_servers
}