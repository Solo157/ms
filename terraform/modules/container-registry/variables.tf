variable "name" {
  description = "Container registry name"
  type        = string
}

variable "sa_puller_ids" {
  description = "Service accounts that may pull images (node SA, runner SA)"
  type        = list(string)
  default     = []
}

variable "sa_pusher_ids" {
  description = "Service accounts that may push images (runner SA)"
  type        = list(string)
  default     = []
}
