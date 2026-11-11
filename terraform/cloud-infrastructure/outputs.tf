output "network_id" {
  value = module.network.network_id
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "security_group_id" {
  value = module.network.security_group_id
}

output "registry_id" {
  value = module.container_registry.registry_id
}

output "registry_host" {
  value = module.container_registry.registry_host
}

output "cluster_id" {
  value = module.kubernetes.cluster_id
}

output "cluster_name" {
  value = module.kubernetes.cluster_name
}

output "master_external_endpoint" {
  value = module.kubernetes.master_external_endpoint
}

output "cluster_ca_certificate" {
  value = module.kubernetes.cluster_ca_certificate
}

output "runner_id" {
  value = module.gitlab_runner.runner_id
}

output "runner_vm_external_ip" {
  value = module.gitlab_runner.runner_vm_external_ip
}
