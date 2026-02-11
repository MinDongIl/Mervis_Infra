terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
  # 상태 파일(State) 저장을 위한 GCS 버킷 설정 (나중에 활성화 예정, 지금은 주석)
  # backend "gcs" {
  #   bucket  = "mervis-terraform-state"
  #   prefix  = "terraform/state"
  # }
}

provider "google" {
  credentials = file(var.credentials_file)
  project     = var.project_id
  region      = var.region
  zone        = var.zone
}