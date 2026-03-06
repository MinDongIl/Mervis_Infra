# 1. 서비스 계정 및 권한 설정
resource "google_service_account" "sa" {
  account_id   = "mervis-compute-sa"
  display_name = "Mervis Compute Service Account"
}

# IAM 권한들
resource "google_project_iam_member" "artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.sa.email}"
}
resource "google_project_iam_member" "bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.sa.email}"
}
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.sa.email}"
}

# 로드밸런서용 헬스 체크
resource "google_compute_health_check" "autohealing" {
  name                = "mervis-autohealing-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port = 80
  }
}

# 대기열(Queue)용 Managed Redis 추가
# variables.tf에 이미 있는 network_name을 가져와서 ID를 자동 추출
data "google_compute_network" "mervis_vpc" {
  name = var.network_name
}

resource "google_redis_instance" "queue_cache" {
  name           = "mervis-waiting-queue"
  memory_size_gb = 1
  region         = var.region
  tier           = "BASIC"
  
  # data 블록에서 추출한 네트워크 ID를 자동으로 주입
  authorized_network = data.google_compute_network.mervis_vpc.id
}

# ==========================================
# 2. Serving Zone (MIG + Auto-scaling)
# ==========================================
resource "google_compute_instance_template" "serving_tpl" {
  name_prefix  = "mervis-serving-tpl-"
  machine_type = "e2-standard-4" # 대규모 스파이크 방어를 위한 체급 상향
  region       = var.region

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    subnetwork = var.subnet_serving_id
  }

  service_account {
    email  = google_service_account.sa.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible        = true
    automatic_restart  = false
    provisioning_model = "SPOT"
  }

  # Startup Script: 서비스용
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y docker.io
    gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet
    
    # 디스크/메모리 지표 수집용
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    bash add-google-cloud-ops-agent-repo.sh --also-install
    
    # 시크릿 로드 및 Redis Host 추가
    export KIS_APP_KEY_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-key-real")
    export KIS_APP_SECRET_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-secret-real")
    export KIS_CANO_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-cano-real")
    export KIS_ACNT_PRDT_CD_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-prdt-real")
    export GEMINI_API_KEY=$(gcloud secrets versions access latest --secret="mervis-gemini-api-key")
    export DISCORD_WEBHOOK_URL=$(gcloud secrets versions access latest --secret="mervis-discord-webhook")
    export REDIS_HOST=${google_redis_instance.queue_cache.host}
    
    # Docker 실행: 서비스 모드 (REDIS_HOST 환경변수 주입)
    docker run -d --restart always --name mervis-core \
      -e KIS_APP_KEY_REAL="$KIS_APP_KEY_REAL" \
      -e KIS_APP_SECRET_REAL="$KIS_APP_SECRET_REAL" \
      -e KIS_CANO_REAL="$KIS_CANO_REAL" \
      -e KIS_ACNT_PRDT_CD_REAL="$KIS_ACNT_PRDT_CD_REAL" \
      -e GEMINI_API_KEY="$GEMINI_API_KEY" \
      -e DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL" \
      -e GOOGLE_CLOUD_PROJECT="${var.project_id}" \
      -e USER_NAME="Admin" \
      -e REDIS_HOST="$REDIS_HOST" \
      -p 80:8080 \
      ${var.repo_url}/mervis-core:latest python app.py
  EOT
  
  lifecycle { create_before_destroy = true }
}

resource "google_compute_region_instance_group_manager" "serving_mig" {
  name               = "mervis-serving-mig"
  base_instance_name = "mervis-serving"
  region             = var.region
  
  version {
    instance_template = google_compute_instance_template.serving_tpl.id
  }
  
  named_port {
    name = "http"
    port = 80
  }
}

# Auto-scaling 정책 및 비용 최적화 스케줄링
resource "google_compute_region_autoscaler" "serving_autoscaler" {
  name   = "mervis-serving-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.serving_mig.id

  autoscaling_policy {
    max_replicas    = 20
    min_replicas    = 1  # 비용 최적화: 야간/새벽 트래픽 없을 때는 1대로 축소

    cooldown_period = 60

    cpu_utilization {
      target = 0.5 # CPU 50% 초과 시 선제적 스케일아웃 (무중단 방어)
    }

    # 낮 시간대에는 대규모 트래픽 대비 5대 예열
    scaling_schedules {
      name                  = "business-hours-prewarming"
      min_required_replicas = 4  # 주간 4대 유지
      schedule              = "0 9 * * 1-5" # 평일 오전 9시
      time_zone             = "Asia/Seoul"
      duration_sec          = 32400 # 9시간 지속 (오후 6시까지)
      description           = "Scale up minimum instances during business hours for spike defense"
    }
  }
}

# ==========================================
# 3. Training Zone (Standalone VM)
# ==========================================
resource "google_compute_instance" "brain_vm" {
  name         = "mervis-brain"
  machine_type = "e2-medium"
  zone         = "${var.region}-a"

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    subnetwork = var.subnet_training_id
  }

  service_account {
    email  = google_service_account.sa.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible        = true
    automatic_restart  = false
    provisioning_model = "SPOT"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y docker.io
    gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet
    
    # 디스크/메모리 지표 수집용
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    bash add-google-cloud-ops-agent-repo.sh --also-install
    
    export KIS_APP_KEY_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-key-real")
    export KIS_APP_SECRET_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-secret-real")
    export KIS_CANO_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-cano-real")
    export KIS_ACNT_PRDT_CD_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-prdt-real")
    export GEMINI_API_KEY=$(gcloud secrets versions access latest --secret="mervis-gemini-api-key")
    export DISCORD_WEBHOOK_URL=$(gcloud secrets versions access latest --secret="mervis-discord-webhook")
    
    docker run -d --restart always --name mervis-brain \
      -e KIS_APP_KEY_REAL="$KIS_APP_KEY_REAL" \
      -e KIS_APP_SECRET_REAL="$KIS_APP_SECRET_REAL" \
      -e KIS_CANO_REAL="$KIS_CANO_REAL" \
      -e KIS_ACNT_PRDT_CD_REAL="$KIS_ACNT_PRDT_CD_REAL" \
      -e GEMINI_API_KEY="$GEMINI_API_KEY" \
      -e DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL" \
      -e GOOGLE_CLOUD_PROJECT="${var.project_id}" \
      -e USER_NAME="Admin" \
      ${var.repo_url}/mervis-core:latest
  EOT
}

output "serving_instance_group" { value = google_compute_region_instance_group_manager.serving_mig.instance_group }
output "redis_host_ip" { value = google_redis_instance.queue_cache.host }