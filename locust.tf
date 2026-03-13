/*
# 1. 방화벽 규칙: Locust UI(8089) 및 Master-Worker 통신(5557, 5558) 포트 개방
resource "google_compute_firewall" "locust_fw" {
  name    = "allow-locust"
  network = module.network.network_name

  allow {
    protocol = "tcp"
    ports    = ["8089", "5557", "5558"]
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
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    subnetwork = module.network.subnet_serving_id
    access_config {} 
  }

  # replace 함수를 사용해 윈도우 줄바꿈 문자(\r)제거
  metadata_startup_script = replace(<<-EOF
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Docker 설치
apt-get update -y
apt-get install -y docker.io

mkdir -p /mnt/locust

# 파이썬 파일 생성
cat << 'FILE' > /mnt/locust/locustfile.py
import time
from locust import HttpUser, task, between

class WebsiteUser(HttpUser):
    wait_time = between(0.5, 1.5)

    @task
    def reserve_ticket(self):
        with self.client.get("/", catch_response=True) as response:
            if "대기 순서 확인" in response.text:
                response.success()
                while True:
                    time.sleep(3)
                    poll_resp = self.client.get("/api/wait_status", name="/api/wait_status")
                    if poll_resp.status_code == 200:
                        data = poll_resp.json()
                        if data.get("status") == "allowed":
                            break 
                        elif data.get("status") == "waiting":
                            continue
                    else:
                        break
        
        time.sleep(10)
        self.client.get("/api/exit", name="/api/exit")
FILE

# 마스터 실행
docker run -d --name locust-master --restart always \
  -p 8089:8089 -p 5557:5557 -p 5558:5558 \
  -v /mnt/locust:/mnt/locust \
  locustio/locust -f /mnt/locust/locustfile.py --master --host=https://mervis.cloud
EOF
  , "\r", "")
}

# 3. Locust Worker 인스턴스 템플릿 (실제 부하 발생기)
resource "google_compute_instance_template" "locust_worker_tpl" {
  name_prefix  = "locust-worker-tpl-"
  machine_type = "e2-highcpu-4" 
  tags         = ["locust-worker"]

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = module.network.subnet_serving_id
    access_config {} 
  }

  # 워커 스크립트도 동일하게 \r 제거
  metadata_startup_script = replace(<<-EOF
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io

mkdir -p /mnt/locust

cat << 'FILE' > /mnt/locust/locustfile.py
import time
from locust import HttpUser, task, between

class WebsiteUser(HttpUser):
    wait_time = between(0.5, 1.5)

    @task
    def reserve_ticket(self):
        with self.client.get("/", catch_response=True) as response:
            if "대기 순서 확인" in response.text:
                response.success()
                while True:
                    time.sleep(3)
                    poll_resp = self.client.get("/api/wait_status", name="/api/wait_status")
                    if poll_resp.status_code == 200:
                        data = poll_resp.json()
                        if data.get("status") == "allowed":
                            break 
                        elif data.get("status") == "waiting":
                            continue
                    else:
                        break
        
        time.sleep(10)
        self.client.get("/api/exit", name="/api/exit")
FILE

# 워커 실행 (Master IP 매핑)
docker run -d --name locust-worker --restart always \
  -v /mnt/locust:/mnt/locust \
  locustio/locust -f /mnt/locust/locustfile.py --worker --master-host=${google_compute_instance.locust_master.network_interface.0.network_ip}
EOF
  , "\r", "")

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

  target_size = 3 
}
*/