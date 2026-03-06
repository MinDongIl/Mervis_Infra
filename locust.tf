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
      image = "debian-cloud/debian-11"
    }
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
    
    # 예매 시나리오 파이썬 파일 생성
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

    # Systemd 서비스로 Master 등록
    cat << 'EOF_SVC' > /etc/systemd/system/locust-master.service
[Unit]
Description=Locust Master Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m locust -f /home/locustfile.py --master --host=https://mervis.cloud
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF_SVC

    systemctl daemon-reload
    systemctl enable locust-master
    systemctl start locust-master
  EOF
}

# 3. Locust Worker 인스턴스 템플릿 (실제 부하 발생기)
resource "google_compute_instance_template" "locust_worker_tpl" {
  name_prefix  = "locust-worker-tpl-"
  machine_type = "e2-highcpu-4" 
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

    # Systemd 서비스로 Worker 등록 (Master IP 자동 주입)
    cat << 'EOF_SVC' > /etc/systemd/system/locust-worker.service
[Unit]
Description=Locust Worker Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m locust -f /home/locustfile.py --worker --master-host=${google_compute_instance.locust_master.network_interface.0.network_ip}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF_SVC

    systemctl daemon-reload
    systemctl enable locust-worker
    systemctl start locust-worker
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

  target_size = 3 
}