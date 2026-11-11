variable "name" {
  description = "Base name for network objects"
  type        = string
}

variable "zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["ru-central1-a", "ru-central1-b"]
}

variable "subnet_cidrs" {
  description = "CIDR blocks aligned to zones"
  type        = list(string)
  default     = ["10.10.0.0/24", "10.10.1.0/24"]
}
