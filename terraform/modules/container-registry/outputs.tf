output "registry_id" {
  value = yandex_container_registry.this.id
}

output "registry_host" {
  description = "Fully qualified host for docker push/pull"
  value       = "cr.yandex/${yandex_container_registry.this.id}"
}
