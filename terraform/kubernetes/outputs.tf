output "cluster_external_endpoint" {
  value = data.yandex_kubernetes_cluster.this.master[0].external_v4_endpoint
}

output "namespaces" {
  value = [for ns in kubernetes_namespace_v1.env : ns.metadata[0].name]
}

output "agent_name" {
  value = gitlab_cluster_agent.this.name
}

output "agent_id" {
  value = gitlab_cluster_agent.this.agent_id
}

# The value CI must expose as KUBE_CONTEXT. No secret material here.
output "kube_context" {
  description = "Value to set as KUBE_CONTEXT in the Application/Infra pipelines"
  value       = "gitlab:${var.gitlab_project_path}/${var.agent_name}"
}

output "agent_address" {
  description = "wss KasGRPC endpoint passed to the gitlab-agent Helm chart"
  value       = local.agent_grpc_url
}
