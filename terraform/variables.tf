# Все параметры с дефолтами; секреты сюда не попадают.
# В CI значения (кроме секретов) не задаются — используются дефолты.

variable "name" {
  description = "Префикс для всех облачных объектов"
  type        = string
  default     = "otus-ms"
}

variable "yc_cloud_id" {
  description = "ID облака Yandex Cloud (для провайдера)"
  type        = string
}

variable "yc_folder_id" {
  description = "ID каталога Yandex Cloud: здесь создаются объекты и IAM-биндинги"
  type        = string
}

variable "subnet_cidrs" {
  description = "CIDR-блоки подсетей (по числу зон); подсеть [0] используется master и нодами"
  type        = list(string)
  default     = ["10.10.10.0/24", "10.10.11.0/24"]
}

variable "zones" {
  description = "Зоны доступности подсетей (одна и та же для master/нод и резервная)"
  type        = list(string)
  default     = ["ru-central1-a", "ru-central1-b"]
}

variable "node_count" {
  description = "Число воркеров в фиксированном масштабе"
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
