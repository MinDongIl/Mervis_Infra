output "lb_ip_address" {
  description = "생성된 로드밸런서의 고정 IP"
  value       = google_compute_global_address.default.address
}