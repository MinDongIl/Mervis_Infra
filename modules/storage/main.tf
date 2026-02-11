# Docker 이미지를 저장할 저장소 생성
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "mervis-repo"
  description   = "Mervis Project Docker Repository"
  format        = "DOCKER"
}