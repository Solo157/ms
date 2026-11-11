output "network_id" {
  value = yandex_vpc_network.this.id
}

# subnet[0] = zone-a (k8s master + nodes), subnet[1] = zone-b (runner VM)
output "subnet_ids" {
  value = yandex_vpc_subnet.this[*].id
}

output "subnet_zones" {
  value = yandex_vpc_subnet.this[*].zone
}

output "security_group_id" {
  value = yandex_vpc_security_group.this.id
}
