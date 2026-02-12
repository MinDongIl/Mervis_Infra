# 1. 네트워크 모듈
module "network" {
  source     = "./modules/network"
  project_id = var.project_id
  region     = var.region
  lb_ip_address = module.lb.lb_ip_address
}

# 2. 스토리지 모듈
module "storage" {
  source     = "./modules/storage"
  project_id = var.project_id
  region     = var.region
}

# 3. 컴퓨팅 모듈
module "compute" {
  source     = "./modules/compute"
  project_id = var.project_id
  region     = var.region
  
  network_name       = module.network.network_name
  subnet_serving_id  = module.network.subnet_serving_id
  subnet_training_id = module.network.subnet_training_id
  repo_url           = module.storage.repo_url
}

# 4. 로드밸런서 모듈
module "lb" {
  source     = "./modules/lb"
  project_id = var.project_id
  region     = var.region
  
  # Compute 모듈의 출력값(MIG)을 LB에 전달
  mig_instance_group = module.compute.serving_instance_group
  
  # 도메인 이름
  domain_name        = "mervis.cloud"
}