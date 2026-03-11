variable "project_id" {}
variable "region" {}

variable "network_name" {
  description = "네트워크 모듈에서 넘겨받을 VPC 이름"
  type        = string
}

variable "subnet_serving_id" {
  description = "네트워크 모듈에서 넘겨받을 서울 서빙용 서브넷 ID"
  type        = string
}

variable "subnet_training_id" {
  description = "네트워크 모듈에서 넘겨받을 서울 학습용 서브넷 ID"
  type        = string
}

variable "subnet_serving_tokyo_id" {
  description = "네트워크 모듈에서 넘겨받을 도쿄 리전 서빙용 서브넷 ID"
  type        = string
}

variable "repo_url" {
  description = "스토리지 모듈에서 넘겨받을 Artifact Registry URL"
  type        = string
}

variable "image_tag" {
  description = "배포할 도커 이미지 태그"
  type        = string
}