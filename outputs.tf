output "repository_url" {
  value       = module.storage.repo_url
  description = "Docker Image Repository URL"
}

output "serving_group_name" {
  value       = module.compute.serving_instance_group
  description = "Serving MIG Name"
}