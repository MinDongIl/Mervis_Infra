# 이메일 알림 채널
resource "google_monitoring_notification_channel" "email_alert" {
  display_name = "Mervis SRE Email Alert"
  type         = "email"
  labels = {
    email_address = "ehddlf9685@gmail.com"
  }
}

# 디스코드 웹훅 데이터 호출
data "google_secret_manager_secret_version" "discord_webhook" {
  secret  = "mervis-discord-webhook"
  project = var.project_id
}

# 디스코드 알림 채널 구성
resource "google_monitoring_notification_channel" "discord_channel" {
  display_name = "Mervis Discord Alerts"
  type         = "webhook_tokenauth"
  labels = {
    url = "${data.google_secret_manager_secret_version.discord_webhook.secret_data}/slack"
  }
}

# 디스크 사용량 50% 초과 경보
resource "google_monitoring_alert_policy" "disk_space_high" {
  display_name = "Mervis Disk Usage Alert (> 50%)"
  combiner     = "OR"
  
  conditions {
    display_name = "Disk usage is over 50%"
    condition_threshold {
      filter          = "metric.type=\"agent.googleapis.com/disk/percent_used\" AND resource.type=\"gce_instance\" AND metric.labels.state=\"used\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 50.0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alert.id]
}

# CPU 사용률 50% 초과 경보
resource "google_monitoring_alert_policy" "cpu_usage_high" {
  display_name = "Mervis CPU Usage Alert (> 50%)"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization is over 50%"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.5
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_alert.id]
}

# 로드밸런서 5xx 에러 발생 경보
resource "google_monitoring_alert_policy" "lb_5xx_errors" {
  display_name = "Mervis LB 500 Error Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "HTTP 5xx on Load Balancer"
    condition_matched_log {
      filter = "resource.type=\"http_load_balancer\" AND httpRequest.status >= 500"
    }
  }
  
  notification_channels = [
    google_monitoring_notification_channel.email_alert.id,
    google_monitoring_notification_channel.discord_channel.id
  ]
  
  alert_strategy {
    notification_rate_limit {
      period = "300s" 
    }
  }
}

# HTTPS 가동시간 확인
resource "google_monitoring_uptime_check_config" "https_uptime_check" {
  display_name = "Mervis HTTPS Uptime Check"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path           = "/"
    port           = 443
    use_ssl        = true
    validate_ssl   = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = "mervis.cloud"
    }
  }
}

# 가동시간 확인 실패 경보
resource "google_monitoring_alert_policy" "uptime_alert" {
  display_name = "Mervis Uptime Check Failed"
  combiner     = "OR"
  
  conditions {
    display_name = "Uptime check failed"
    condition_threshold {
      filter     = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.\"check_id\"=\"${google_monitoring_uptime_check_config.https_uptime_check.uptime_check_id}\""
      duration   = "60s"
      comparison = "COMPARISON_LT"
      threshold_value = 1
      
      aggregations {
        alignment_period     = "60s"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
      }
    }
  }
  
  notification_channels = [
    google_monitoring_notification_channel.email_alert.id,
    google_monitoring_notification_channel.discord_channel.id
  ]
}