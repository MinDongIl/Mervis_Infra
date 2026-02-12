output "repository_url" {
  value       = module.storage.repo_url
  description = "Docker Image Repository URL"
}

output "serving_group_name" {
  value       = module.compute.serving_instance_group
  description = "Serving MIG Name"
}

output "cloud_dns_name_servers" {
  description = "이 주소들을 복사해서 도메인 구매 사이트의 '네임서버 설정'에 붙여넣으세요."
  value       = module.network.name_servers  # module.network 안에 있는 출력을 가져옴
}