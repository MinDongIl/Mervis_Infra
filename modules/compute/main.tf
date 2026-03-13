# 서비스 계정 및 권한 설정
resource "google_service_account" "sa" {
  account_id   = "mervis-compute-sa"
  display_name = "Mervis Compute Service Account"
}

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

# Autohealing Health Check
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

data "google_compute_network" "mervis_vpc" {
  name = var.network_name
}

# Redis Queue (서울 리전 공용)
resource "google_redis_instance" "queue_cache" {
  name           = "mervis-waiting-queue"
  memory_size_gb = 1
  region         = var.region
  tier           = "BASIC"
  
  authorized_network = data.google_compute_network.mervis_vpc.id
}

# 서울 리전 Serving 템플릿 및 MIG
resource "google_compute_instance_template" "serving_tpl" {
  name_prefix  = "mervis-serving-tpl-"
  machine_type = "e2-standard-2" 
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

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y docker.io
    gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet
    
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    bash add-google-cloud-ops-agent-repo.sh --also-install
    
    export KIS_APP_KEY_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-key-real")
    export KIS_APP_SECRET_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-secret-real")
    export KIS_CANO_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-cano-real")
    export KIS_ACNT_PRDT_CD_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-prdt-real")
    export GEMINI_API_KEY=$(gcloud secrets versions access latest --secret="mervis-gemini-api-key")
    export DISCORD_WEBHOOK_URL=$(gcloud secrets versions access latest --secret="mervis-discord-webhook")
    export REDIS_HOST=${google_redis_instance.queue_cache.host}
    
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
      ${var.repo_url}/mervis-core:${var.image_tag} gunicorn -w 4 -k gevent --worker-connections 1000 -b 0.0.0.0:8080 app:app
  EOT
  
  lifecycle { create_before_destroy = true }
}

resource "google_compute_region_instance_group_manager" "serving_mig" {
  name               = "mervis-serving-mig"
  base_instance_name = "mervis-serving"
  region             = var.region
  
  version {
    instance_template = google_compute_instance_template.serving_tpl.id
    name              = "primary"
  }
  
  named_port {
    name = "http"
    port = 80
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3            
    max_unavailable_fixed = 0
    replacement_method    = "SUBSTITUTE"
  }
}

resource "google_compute_region_autoscaler" "serving_autoscaler" {
  name   = "mervis-serving-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.serving_mig.id

  autoscaling_policy {
    max_replicas    = 10
    min_replicas    = 1  
    cooldown_period = 60
    cpu_utilization {
      target = 0.8 # 0.5에서 0.8로 상향
    }
    scaling_schedules {
      name                  = "business-hours-prewarming"
      min_required_replicas = 3
      schedule              = "0 9 * * 1-5" 
      time_zone             = "Asia/Seoul"
      duration_sec          = 32400 
    }
  }
}

# 도쿄 리전 Serving 템플릿 및 MIG (DR용)
resource "google_compute_instance_template" "serving_tpl_tokyo" {
  name_prefix  = "mervis-serving-tpl-tokyo-"
  machine_type = "e2-standard-2" 
  region       = "asia-northeast1"

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
  }

  network_interface {
    subnetwork = var.subnet_serving_tokyo_id
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
    
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    bash add-google-cloud-ops-agent-repo.sh --also-install
    
    export KIS_APP_KEY_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-key-real")
    export KIS_APP_SECRET_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-app-secret-real")
    export KIS_CANO_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-cano-real")
    export KIS_ACNT_PRDT_CD_REAL=$(gcloud secrets versions access latest --secret="mervis-kis-prdt-real")
    export GEMINI_API_KEY=$(gcloud secrets versions access latest --secret="mervis-gemini-api-key")
    export DISCORD_WEBHOOK_URL=$(gcloud secrets versions access latest --secret="mervis-discord-webhook")
    export REDIS_HOST=${google_redis_instance.queue_cache.host}
    
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
      ${var.repo_url}/mervis-core:${var.image_tag} gunicorn -w 4 -k gevent --worker-connections 1000 -b 0.0.0.0:8080 app:app
  EOT
  
  lifecycle { create_before_destroy = true }
}

resource "google_compute_region_instance_group_manager" "serving_mig_tokyo" {
  name               = "mervis-serving-mig-tokyo"
  base_instance_name = "mervis-serving-tokyo"
  region             = "asia-northeast1"
  
  version {
    instance_template = google_compute_instance_template.serving_tpl_tokyo.id
    name              = "primary"
  }
  
  named_port {
    name = "http"
    port = 80
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3            
    max_unavailable_fixed = 0
    replacement_method    = "SUBSTITUTE"
  }
}

resource "google_compute_region_autoscaler" "serving_autoscaler_tokyo" {
  name   = "mervis-serving-autoscaler-tokyo"
  region = "asia-northeast1"
  target = google_compute_region_instance_group_manager.serving_mig_tokyo.id

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 0
    cooldown_period = 60
    cpu_utilization {
      target = 0.8 # 0.5에서 0.8로 상향
    }
  }
}

# 학습용 Brain VM
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
      ${var.repo_url}/mervis-core:${var.image_tag}
  EOT
}

output "serving_instance_group" { value = google_compute_region_instance_group_manager.serving_mig.instance_group }
output "serving_instance_group_tokyo" { value = google_compute_region_instance_group_manager.serving_mig_tokyo.instance_group }
output "redis_host_ip" { value = google_redis_instance.queue_cache.host }