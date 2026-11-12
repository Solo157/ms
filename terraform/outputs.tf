output "cluster_id" {
  description = "ID кластера — передаётся в CI через dotenv (cluster.env) в job установки агента"
  value       = yandex_kubernetes_cluster.main.id
}
