# 1. 서비스 계정 및 권한 설정
resource "google_service_account" "sa" {
  account_id   = "mervis-compute-sa"
  display_name = "Mervis Compute Service Account"
}

# IAM 권한들...
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

# 공통 Startup Script 정의 (재사용을 위해 변수로 빼거나 locals 사용 가능하지만, 여기선 직관성을 위해 각각 넣음)
# Training은 mervis_server_manager.py 실행, Serving은 app.py 실행

# 로드밸런서용 헬스 체크와 별개로, 관리자가 서버 생사를 판단하는 기준
resource "google_compute_health_check" "autohealing" {
  name                = "mervis-autohealing-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2 # 10초 연속 응답 없으면 사망 판정

  http_health_check {
    port = 80 # 컨테이너가 80(또는 8080) 포트로 응답하는지 감시
  }
}

# ==========================================
# 2. Serving Zone (MIG + Auto-scaling)
# ==========================================
resource "google_compute_instance_template" "serving_tpl" {
  name_prefix  = "mervis-serving-tpl-"
  machine_type = "e2-micro"
  region       = var.region

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    subnetwork = var.subnet_serving_id # [Private Subnet A]
    # access_config {} 블록 삭제 -> 공인 IP 제거 (보안)
  }

  service_account {
    email  = google_service_account.sa.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible       = true
    automatic_restart = false
    provisioning_model = "SPOT"
  }

  # Startup Script: 서비스용
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y docker.io
    gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet
    
    # 시크릿 로드
    export KIS_APP_KEY_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-key-real")
    export KIS_APP_SECRET_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-secret-real")
    export KIS_CANO_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-cano-real")
    export KIS_ACNT_PRDT_CD_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-prdt-real")
    export GEMINI_API_KEY=$(gcloud secrets versions access latest --secret="mervis-gemini-api-key")
    export DISCORD_WEBHOOK_URL=$(gcloud secrets versions access latest --secret="mervis-discord-webhook")
    
    # Docker 실행: 서비스 모드
    docker run -d --restart always --name mervis-core \
      -e KIS_APP_KEY_REAL="$KIS_APP_KEY_REAL" \
      -e KIS_APP_SECRET_REAL="$KIS_APP_SECRET_REAL" \
      -e KIS_CANO_REAL="$KIS_CANO_REAL" \
      -e KIS_ACNT_PRDT_CD_REAL="$KIS_ACNT_PRDT_CD_REAL" \
      -e GEMINI_API_KEY="$GEMINI_API_KEY" \
      -e DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL" \
      -e GOOGLE_CLOUD_PROJECT="${var.project_id}" \
      -e USER_NAME="Admin" \
      -p 80:8080 \
      ${var.repo_url}/mervis-core:latest python app.py
  EOT
  
  lifecycle { create_before_destroy = true }
}

resource "google_compute_region_instance_group_manager" "serving_mig" {
  name               = "mervis-serving-mig"
  base_instance_name = "mervis-serving"
  region             = var.region
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.serving_tpl.id
  }
  
  named_port {
    name = "http"
    port = 80
  }
}

# ==========================================
# 3. Training Zone (Standalone VM)
# ==========================================
resource "google_compute_instance" "brain_vm" {
  name         = "mervis-brain"
  machine_type = "e2-medium"
  zone         = "${var.region}-a"

  # 스펙 변경 시 서버 자동 정지 허용
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    subnetwork = var.subnet_training_id # [Private Subnet B]
    # 공인 IP 없음
  }

  service_account {
    email  = google_service_account.sa.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible       = true
    automatic_restart = false
    provisioning_model = "SPOT"
  }

  # Startup Script: 학습용
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y docker.io
    gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet
    
    # 시크릿 로드
    export KIS_APP_KEY_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-key-real")
    export KIS_APP_SECRET_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-secret-real")
    export KIS_CANO_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-cano-real")
    export KIS_ACNT_PRDT_CD_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-prdt-real")
    export GEMINI_API_KEY=$(gcloud secrets versions access latest --secret="mervis-gemini-api-key")
    export DISCORD_WEBHOOK_URL=$(gcloud secrets versions access latest --secret="mervis-discord-webhook")
    
    # Docker 실행: 학습 모드
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