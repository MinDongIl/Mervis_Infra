# 1. 알림을 받을 이메일 채널 설정
resource "google_monitoring_notification_channel" "email_alert" {
  display_name = "Mervis SRE Email Alert"
  type         = "email"
  labels = {
    email_address = "ehddlf9685@gmail.com"
  }
}

# 2. 디스크 사용량 80% 초과 경보 정책
resource "google_monitoring_alert_policy" "disk_space_high" {
  display_name = "Mervis Disk Usage Alert (> 80%)"
  combiner     = "OR"
  
  conditions {
    display_name = "Disk usage is over 80%"
    condition_threshold {
      filter          = "metric.type=\"agent.googleapis.com/disk/percent_used\" AND resource.type=\"gce_instance\" AND metric.labels.state=\"used\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 80.0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alert.id]
}

# 3. CPU 사용률 70% 초과 경보 정책
resource "google_monitoring_alert_policy" "cpu_usage_high" {
  display_name = "Mervis CPU Usage Alert (> 70%)"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization is over 70%"
    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.7
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_alert.id]
}