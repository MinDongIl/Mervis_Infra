# ==============================================================================
# Cloud DNS Zone (도메인 관리 영역)
# ==============================================================================
resource "google_dns_managed_zone" "mervis_zone" {
  name        = "mervis-cloud-zone"
  dns_name    = "mervis.cloud."
  description = "Mervis Trading System DNS Zone"
  
  visibility = "public"

  labels = {
    env = "prod"
  }
}

# ==============================================================================
# Output (네임서버 주소 출력용)
# ==============================================================================
output "name_servers" {
  description = "도메인 등록기관(가비아 등)에 입력해야 할 구글 네임서버 주소 목록"
  value       = google_dns_managed_zone.mervis_zone.name_servers
}