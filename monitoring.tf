# 1. 알림을 받을 이메일 채널 설정
resource "google_monitoring_notification_channel" "email_alert" {
  display_name = "Mervis SRE Email Alert"
  type         = "email"
  labels = {
    email_address = "ehddlf9685@gmail.com" #
  }
}

# 2. 디스크 사용량 80% 초과 경보 정책
resource "google_monitoring_alert_policy" "disk_space_high" {
  display_name = "Mervis Disk Usage Alert (> 80%)"
  combiner     = "OR"
  
  conditions {
    display_name = "Disk usage is over 80%"
    condition_threshold {
      # Ops Agent가 수집하는 디스크 사용량(%) 지표
      filter          = "metric.type=\"agent.googleapis.com/disk/percent_used\" AND resource.type=\"gce_instance\" AND metric.labels.state=\"used\""
      duration        = "60s" # 테스트를 위해 1분간 지속 시 즉시 알림 발송
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