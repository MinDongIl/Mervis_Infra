# ./modules/lb/main.tf

# 1. 외부 접속용 고정 IP (Premium Tier)
resource "google_compute_global_address" "default" {
  name = "mervis-lb-ip"
}

# 2. 백엔드 서비스 (MIG와 연결)
resource "google_compute_backend_service" "default" {
  name                  = "mervis-backend-service"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30

  backend {
    group = var.serving_mig_url
    balancing_mode = "UTILIZATION"
  }

  health_checks = [google_compute_health_check.default.id]
}

# 3. 헬스 체크 (서버가 살아있는지 확인)
resource "google_compute_health_check" "default" {
  name = "mervis-health-check"
  
  tcp_health_check {
    port = "80" # 혹은 앱 포트 8080
  }
}

# 4. URL 맵 (라우팅 규칙)
resource "google_compute_url_map" "default" {
  name            = "mervis-url-map"
  default_service = google_compute_backend_service.default.id
}

# 5. 프록시 및 포워딩 규칙 (HTTP)
# (추후 도메인 연결 시 HTTPS로 변경)
resource "google_compute_target_http_proxy" "default" {
  name    = "mervis-http-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "mervis-forwarding-rule"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
  ip_address = google_compute_global_address.default.id
}