variable "project_id" {}
variable "region" {}

variable "lb_ip_address" {
  description = "로드밸런서 모듈에서 넘겨받을 IP 주소"
  type        = string
}