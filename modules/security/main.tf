# Cloud Armor 보안 정책 정의

resource "google_compute_security_policy" "mervis_ddos_armor" {
  name        = "mervis-ddos-protection-policy"
  description = "Cloud Armor policy to mitigate DDoS attacks and rate limit IPs"

  # 기본 규칙: 모든 트래픽 허용 (우선순위가 가장 낮음)
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow all rule"
  }

  # Rate Limiting 규칙: 단일 IP에서 1분 동안 100회 초과 요청 시 차단 (403 반환)
  rule {
    action   = "rate_based_ban"
    priority = "100"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      conform_action = "allow"
      exceed_action  = "deny(403)"
      enforce_on_key = "IP"
      
      ban_duration_sec = 300 # 차단 시 5분 동안 유지
    }
    description = "Rate limit: Ban IP for 5 mins if requests > 100 per min"
  }
}

output "security_policy_id" {
  value = google_compute_security_policy.mervis_ddos_armor.id
}