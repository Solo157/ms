output "runner_id" {
  value = gitlab_user_runner.this.id
}

output "runner_sa_id" {
  value = yandex_iam_service_account.runner.id
}

output "runner_vm_id" {
  value = yandex_compute_instance.runner.id
}

output "runner_vm_external_ip" {
  value = yandex_compute_instance.runner.network_interface[0].nat_ip_address
}
