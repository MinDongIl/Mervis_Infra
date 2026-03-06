# 1. 방화벽 규칙: Locust UI(8089) 및 Master-Worker 통신(5557, 5558) 포트 개방
resource "google_compute_firewall" "locust_fw" {
  name    = "allow-locust"
  network = module.network.network_name

  allow {
    protocol = "tcp"
    ports    = ["8089", "5557", "5558"] # 5558(Heartbeat 포트) 추가
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
    
    # 대기열 통과 -> 10초 체류 -> 방 빼기 시나리오 적용
    cat << 'FILE' > /home/locustfile.py
import time
from locust import HttpUser, task, between

class WebsiteUser(HttpUser):
    wait_time = between(0.5, 1.5)

    @task
    def reserve_ticket(self):
        # 1. 메인 페이지 진입 시도
        with self.client.get("/", catch_response=True) as response:
            if "대기 순서 확인" in response.text:
                response.success()
                # 2. 대기열에 걸렸다면 3초마다 폴링하며 차례 기다리기
                while True:
                    time.sleep(3)
                    poll_resp = self.client.get("/api/wait_status", name="/api/wait_status")
                    if poll_resp.status_code == 200:
                        data = poll_resp.json()
                        if data.get("status") == "allowed":
                            break  # 차례가 되어 통과
                        elif data.get("status") == "waiting":
                            continue
                    else:
                        break
        
        # 3. 통과 완료 10초 동안 예매 작업 진행 (체류)
        time.sleep(10)

        # 4. 예매 완료 후 방 빼기 (퇴장) - 다음 사람 입장
        self.client.get("/api/exit", name="/api/exit")
FILE

    # PATH 문제 회피를 위해 python3 -m 사용 및 nohup으로 무중단 실행
    nohup python3 -m locust -f /home/locustfile.py --master --host=https://mervis.cloud > /var/log/locust-master.log 2>&1 &
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
    
    # Master와 동일한 스크립트 삽입
    cat << 'FILE' > /home/locustfile.py
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

    # Worker 모드 실행 (nohup 적용, Master IP 자동 매핑)
    nohup python3 -m locust -f /home/locustfile.py --worker --master-host=${google_compute_instance.locust_master.network_interface.0.network_ip} > /var/log/locust-worker.log 2>&1 &
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

  target_size = 3 # 3대의 Worker 동시 구동
}