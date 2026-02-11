# 1. 네트워크 모듈 (VPC, Subnet, NAT, Firewall)
module "network" {
  source     = "./modules/network"
  project_id = var.project_id
  region     = var.region
}

# 2. 스토리지 모듈 (Artifact Registry - 기존 유지)
module "storage" {
  source     = "./modules/storage"
  project_id = var.project_id
  region     = var.region
}

# 3. 컴퓨팅 모듈 (Serving MIG + Training VM)
module "compute" {
  source     = "./modules/compute"
  project_id = var.project_id
  region     = var.region
  
  # 네트워크 정보 전달
  network_name       = module.network.network_name
  subnet_serving_id  = module.network.subnet_serving_id
  subnet_training_id = module.network.subnet_training_id
  
  # 이미지 저장소 정보 전달
  repo_url           = module.storage.repo_url
}

# 4. 로드밸런서 모듈
module "lb" {
  source            = "./modules/lb"
  project_id        = var.project_id
  region            = var.region
  
  # 컴퓨팅 모듈에서 생성한 MIG를 연결
  serving_mig_url   = module.compute.serving_instance_group
}