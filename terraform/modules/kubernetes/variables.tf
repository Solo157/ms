variable "name" {
  description = "Cluster / node group base name"
  type        = string
}

variable "folder_id" {
  description = "Folder where the cluster lives (for IAM bindings)"
  type        = string
}

variable "network_id" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "master_zone" {
  type = string
}

variable "master_subnet_id" {
  type = string
}

variable "node_subnet_ids" {
  type = list(string)
}

variable "node_zone" {
  type = string
}

variable "release_channel" {
  type    = string
  default = "STABLE"
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

variable "node_core_fraction" {
  type    = number
  default = 100
}

variable "node_disk_size" {
  type    = number
  default = 64
}

variable "public_master" {
  description = "Give the master a public IP (needed for bootstrap kubectl/agent install)"
  type        = bool
  default     = true
}
