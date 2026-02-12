# 1. 고정 IP 예약
resource "google_compute_global_address" "default" {
  name = "mervis-lb-ip"
}

# 2. SSL 인증서 (구글이 90일마다 알아서 갱신)
resource "google_compute_managed_ssl_certificate" "default" {
  name = "mervis-ssl-cert"
  managed {
    domains = [var.domain_name, "www.${var.domain_name}"]
  }
}

# 3. 백엔드 서비스 (로드밸런서 -> 서비스 서버 연결)
resource "google_compute_backend_service" "default" {
  name                  = "mervis-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  
  backend {
    group = var.mig_instance_group  # Compute 모듈에서 받은 MIG 연결
  }

  health_checks = [google_compute_health_check.default.id]
}

# 4. 헬스 체크
resource "google_compute_health_check" "default" {
  name = "mervis-http-health-check"
  
  http_health_check {
    port = 80
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 5. URL 맵 (모든 트래픽을 백엔드로 전달)
resource "google_compute_url_map" "default" {
  name            = "mervis-url-map"
  default_service = google_compute_backend_service.default.id
}

# 6. HTTPS 프록시 (SSL 적용)
resource "google_compute_target_https_proxy" "default" {
  name             = "mervis-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

# 7. 포워딩 룰 (443 포트 개방)
resource "google_compute_global_forwarding_rule" "default" {
  name       = "mervis-forwarding-rule"
  target     = google_compute_target_https_proxy.default.id
  port_range = "443"
  ip_address = google_compute_global_address.default.address
}