# Service account used by the managed master.
resource "yandex_iam_service_account" "master" {
  name = "${var.name}-master-sa"
}

resource "yandex_resourcemanager_folder_iam_member" "master_cluster" {
  folder_id = var.folder_id
  role      = "k8s.cluster-api.cluster"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_vpc" {
  folder_id = var.folder_id
  role      = "vpc.privateAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_logging" {
  folder_id = var.folder_id
  role      = "logging.writer"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

# Service account running ON the worker nodes (image pull etc.).
# container-registry.images.puller is granted in the container-registry module.
resource "yandex_iam_service_account" "node" {
  name = "${var.name}-node-sa"
}

resource "yandex_kubernetes_cluster" "this" {
  name                    = "${var.name}-cluster"
  network_id              = var.network_id
  service_account_id      = yandex_iam_service_account.master.id
  node_service_account_id = yandex_iam_service_account.node.id
  release_channel         = var.release_channel

  master {
    public_ip          = var.public_master
    security_group_ids = var.security_group_ids

    zonal {
      zone      = var.master_zone
      subnet_id = var.master_subnet_id
    }

    maintenance_policy {
      auto_upgrade = true
    }
  }

  # Deletion of the cluster must happen before the SA/roles are torn down.
  depends_on = [
    yandex_resourcemanager_folder_iam_member.master_vpc,
  ]
}

resource "yandex_kubernetes_node_group" "this" {
  cluster_id = yandex_kubernetes_cluster.this.id
  name       = "${var.name}-nodes"

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat                = true
      subnet_ids         = var.node_subnet_ids
      security_group_ids = var.security_group_ids
    }

    resources {
      cores         = var.node_cores
      memory        = var.node_memory
      core_fraction = var.node_core_fraction
    }

    boot_disk {
      type = "network-ssd"
      size = var.node_disk_size
    }

    scheduling_policy {
      preemptible = false
    }
  }

  allocation_policy {
    location {
      zone = var.node_zone
    }
  }

  scale_policy {
    fixed_scale {
      size = var.node_count
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
  }
}
