# 1. 방화벽 규칙: Locust UI(8089) 및 Master-Worker 통신(5557) 포트 개방
resource "google_compute_firewall" "locust_fw" {
  name    = "allow-locust"
  network = module.network.network_name

  allow {
    protocol = "tcp"
    ports    = ["8089", "5557"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["locust-master", "locust-worker"]
}

# 2. Locust Master 인스턴스 (트래픽 지휘 및 웹 UI 제공)
resource "google_compute_instance" "locust_master" {
  name         = "locust-master"
  machine_type = "e2-medium"
  zone         = "${var.region}-a"

  tags = ["locust-master"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = module.network.subnet_serving_id
    access_config {} # 외부 IP 할당 (웹 접속용)
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y python3-pip
    pip3 install locust
    
    # 파이썬 부하 테스트 스크립트 자동 생성
    cat << 'FILE' > /home/locustfile.py
    from locust import HttpUser, task, between
    class WebsiteUser(HttpUser):
        wait_time = between(0.1, 0.5)
        @task(3)
        def load_index(self):
            self.client.get("/")
        @task(1)
        def load_status_api(self):
            self.client.get("/api/status")
    FILE

    # Master 모드로 백그라운드 실행
    locust -f /home/locustfile.py --master --host=https://mervis.cloud > /var/log/locust-master.log 2>&1 &
  EOF
}

# 3. Locust Worker 인스턴스 템플릿 (실제 부하 발생기)
resource "google_compute_instance_template" "locust_worker_tpl" {
  name_prefix  = "locust-worker-tpl-"
  machine_type = "e2-highcpu-4" # 트래픽 생성을 위한 고성능 4코어 CPU
  tags         = ["locust-worker"]

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = module.network.subnet_serving_id
    access_config {} 
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y python3-pip
    pip3 install locust
    
    cat << 'FILE' > /home/locustfile.py
    from locust import HttpUser, task, between
    class WebsiteUser(HttpUser):
        wait_time = between(0.1, 0.5)
        @task(3)
        def load_index(self):
            self.client.get("/")
        @task(1)
        def load_status_api(self):
            self.client.get("/api/status")
    FILE

    # Worker 모드로 실행하여 Master 노드의 내부 IP와 자동 연결
    locust -f /home/locustfile.py --worker --master-host=${google_compute_instance.locust_master.network_interface.0.network_ip} > /var/log/locust-worker.log 2>&1 &
  EOF

  lifecycle {
    create_before_destroy = true
  }
}

# 4. Locust Worker용 Managed Instance Group (MIG)
resource "google_compute_region_instance_group_manager" "locust_worker_mig" {
  name               = "locust-worker-mig"
  base_instance_name = "locust-worker"
  region             = var.region
  
  version {
    instance_template = google_compute_instance_template.locust_worker_tpl.id
  }

  target_size = 3 # 3대의 Worker 동시 구동 (필요시 이 숫자를 늘려 화력 집중 가능)
}