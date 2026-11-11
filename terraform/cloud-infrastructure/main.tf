module "network" {
  source       = "../modules/network"
  name         = var.name
  zones        = var.zones
  subnet_cidrs = var.subnet_cidrs
}

module "kubernetes" {
  source     = "../modules/kubernetes"
  name       = var.name
  folder_id  = var.yc_folder_id
  network_id = module.network.network_id

  master_zone      = module.network.subnet_zones[0]
  master_subnet_id = module.network.subnet_ids[0]

  node_zone          = module.network.subnet_zones[0]
  node_subnet_ids    = [module.network.subnet_ids[0]]
  security_group_ids = [module.network.security_group_id]

  node_count  = var.node_count
  node_cores  = var.node_cores
  node_memory = var.node_memory
}

# Registry pull/push bindings reference the node SA and runner SA, so the
# registry is wired after those (no cycle: they do not read the registry).
module "container_registry" {
  source = "../modules/container-registry"
  name   = var.registry_name

  sa_puller_ids = [
    module.kubernetes.node_service_account_id,
    module.gitlab_runner.runner_sa_id,
  ]
  sa_pusher_ids = [module.gitlab_runner.runner_sa_id]
}

module "gitlab_runner" {
  source = "../modules/gitlab-runner"
  name   = var.name

  gitlab_base_url   = var.gitlab_base_url
  gitlab_project_id = var.gitlab_project_id

  subnet_id          = module.network.subnet_ids[0]
  zone               = module.network.subnet_zones[0]
  security_group_ids = [module.network.security_group_id]

  ssh_public_key = var.ssh_public_key
}
