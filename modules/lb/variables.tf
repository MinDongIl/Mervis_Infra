variable "project_id" {}
variable "region" {}

variable "mig_instance_group" {
  description = "Compute 모듈에서 받아올 MIG 링크"
  type        = string
}

variable "domain_name" {
  description = "연결할 도메인 이름"
  type        = string
  default     = "mervis.cloud"
}