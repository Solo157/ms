variable "kubeconfig_path" {
  description = "Path to a kubeconfig with admin access (from `yc managed-kubernetes cluster get-credentials --new`)"
  type        = string
}

variable "yc_folder_id" {
  type = string
}

variable "yc_token" {
  type      = string
  sensitive = true
}

variable "cluster_name" {
  description = "Managed K8s cluster name (from cloud-infrastructure output)"
  type        = string
}

variable "gitlab_base_url" {
  type = string
}

variable "gitlab_token" {
  type      = string
  sensitive = true
}

variable "gitlab_project_path" {
  description = "Project path_with_namespace, e.g. devops/devops-otus-app/ms (used for ci_access)"
  type        = string
}

variable "agent_name" {
  type    = string
  default = "otus-agent"
}

variable "agent_namespace" {
  type    = string
  default = "gitlab-agent"
}

variable "agent_chart_version" {
  description = "gitlab-agent Helm chart version (empty = latest)"
  type        = string
  default     = ""
}

variable "namespaces" {
  type    = list(string)
  default = ["dev", "prod", "monitoring"]
}
