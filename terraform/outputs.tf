output "cluster_id" {
  value = yandex_kubernetes_cluster.this.id
}

output "cluster_name" {
  value = yandex_kubernetes_cluster.this.name
}

output "cluster_external_endpoint" {
  description = "Публичный endpoint master'а (нужен, чтобы вручную собрать kubeconfig)"
  value       = yandex_kubernetes_cluster.this.master[0].external_v4_endpoint
}
