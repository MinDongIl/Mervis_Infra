# 고정 IP 예약
resource "google_compute_global_address" "default" {
  name = "mervis-lb-ip"
}

# SSL 인증서
resource "google_compute_managed_ssl_certificate" "default" {
  name = "mervis-ssl-cert"
  managed {
    domains = [var.domain_name, "www.${var.domain_name}"]
  }
}

# 백엔드 서비스
resource "google_compute_backend_service" "default" {
  name                  = "mervis-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  
  security_policy = var.security_policy_id

  # Main Region (서울)
  backend {
    group = var.mig_instance_group
  }

  # Standby Region (도쿄)
  backend {
    group = var.mig_instance_group_tokyo
  }

  health_checks = [google_compute_health_check.default.id]
}

# Health Check
resource "google_compute_health_check" "default" {
  name = "mervis-http-health-check"
  
  http_health_check {
    port = 80
  }

  lifecycle {
    create_before_destroy = true
  }
}

# URL Map
resource "google_compute_url_map" "default" {
  name            = "mervis-url-map"
  default_service = google_compute_backend_service.default.id
}

# HTTPS 프록시
resource "google_compute_target_https_proxy" "default" {
  name             = "mervis-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

# Forwarding Rule
resource "google_compute_global_forwarding_rule" "default" {
  name       = "mervis-forwarding-rule"
  target     = google_compute_target_https_proxy.default.id
  port_range = "443"
  ip_address = google_compute_global_address.default.address
}