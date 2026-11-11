variable "name" {
  type = string
}

variable "gitlab_base_url" {
  description = "Self-managed GitLab base URL (for the Runner register --url)"
  type        = string
}

variable "gitlab_project_id" {
  description = "Numeric ID of the project the Runner is registered to"
  type        = string
}

variable "runner_description" {
  type    = string
  default = "otus-yc-runner"
}

variable "runner_tags" {
  type    = list(string)
  default = ["yc-runner", "docker", "terraform"]
}

variable "subnet_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  description = "GB"
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "GB"
  type        = number
  default     = 40
}

variable "ssh_public_key" {
  description = "Optional SSH public key for debugging the runner VM (user: key)"
  type        = string
  default     = ""
}
