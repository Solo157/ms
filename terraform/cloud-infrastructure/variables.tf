variable "name" {
  description = "Prefix for all cloud objects"
  type        = string
  default     = "otus-ms"
}

variable "yc_cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
}

variable "yc_folder_id" {
  description = "Yandex Cloud folder ID"
  type        = string
}

variable "yc_token" {
  description = "Yandex Cloud IAM/OAuth token for the provider"
  type        = string
  sensitive   = true
}

variable "gitlab_base_url" {
  description = "Self-managed GitLab URL, e.g. https://gitlab.example.com"
  type        = string
}

variable "gitlab_token" {
  description = "GitLab PAT (api scope) used by the GitLab provider"
  type        = string
  sensitive   = true
}

variable "gitlab_project_id" {
  description = "Numeric project id the Runner is registered to"
  type        = string
}

variable "subnet_cidrs" {
  type    = list(string)
  default = ["10.10.0.0/24", "10.10.1.0/24"]
}

variable "zones" {
  type    = list(string)
  default = ["ru-central1-a", "ru-central1-b"]
}

variable "registry_name" {
  type    = string
  default = "otus-ms-registry"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_cores" {
  type    = number
  default = 4
}

variable "node_memory" {
  description = "GB"
  type        = number
  default     = 8
}

variable "ssh_public_key" {
  description = "Optional SSH public key (user: key) for debugging the runner VM"
  type        = string
  default     = ""
}
