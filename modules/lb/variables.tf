variable "project_id" {}
variable "region" {}

variable "mig_instance_group" {
  description = "Compute 모듈에서 받아올 서울 리전 MIG 링크"
  type        = string
}

variable "mig_instance_group_tokyo" {
  description = "Compute 모듈에서 받아올 도쿄 리전 MIG 링크"
  type        = string
}

variable "domain_name" {
  description = "연결할 도메인 이름"
  type        = string
  default     = "mervis.cloud"
}

variable "security_policy_id" {
  description = "Cloud Armor security policy ID"
  type        = string
}