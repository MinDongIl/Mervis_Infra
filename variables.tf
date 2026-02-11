variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "Default Region (Seoul)"
  type        = string
  default     = "asia-northeast3"
}

variable "zone" {
  description = "Default Zone"
  type        = string
  default     = "asia-northeast3-a"
}

variable "credentials_file" {
  description = "Path to the service account key file"
  type        = string
  default     = "./service_account.json"
}