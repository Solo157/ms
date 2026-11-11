output "cluster_id" {
  value = yandex_kubernetes_cluster.this.id
}

output "cluster_name" {
  value = yandex_kubernetes_cluster.this.name
}

output "master_external_endpoint" {
  value = yandex_kubernetes_cluster.this.master[0].external_v4_endpoint
}

# CA cert is public-ish (needed to build a kubeconfig); not a secret.
output "cluster_ca_certificate" {
  value = yandex_kubernetes_cluster.this.master[0].cluster_ca_certificate
}

output "node_service_account_id" {
  value = yandex_iam_service_account.node.id
}

output "master_service_account_id" {
  value = yandex_iam_service_account.master.id
}
