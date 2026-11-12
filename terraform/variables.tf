# Все параметры с дефолтами; секреты сюда не попадают.
# В CI (кроме секретов) используются дефолты — значения задаются через tfvars.

variable "name" {
  description = "Префикс имён облачных объектов"
  type        = string
  default     = "otus-ms"
}

variable "yc_cloud_id" {
  description = "ID облака Yandex Cloud"
  type        = string
}

variable "yc_folder_id" {
  description = "ID каталога Yandex Cloud"
  type        = string
}

variable "zone" {
  description = "Зона доступности (одна для подсети, master и нод)"
  type        = string
  default     = "ru-central1-a"
}

variable "subnet_cidr" {
  description = "CIDR единственной подсети"
  type        = string
  default     = "10.10.10.0/24"
}

variable "node_count" {
  description = "Число воркеров"
  type        = number
  default     = 3
}

variable "node_cores" {
  description = "vCPU на воркер"
  type        = number
  default     = 4
}

variable "node_memory" {
  description = "Память на воркер, ГБ"
  type        = number
  default     = 8
}
