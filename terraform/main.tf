# Облачная часть проекта: одна сеть, Managed Kubernetes, Node Group и сервисные
# аккаунты с IAM-ролями. Kubernetes/Helm-объекты (agent, ingress, мониторинг,
# приложение) ставит CI через GitLab Agent — здесь их нет.

resource "yandex_vpc_network" "main" {
  name = "${var.name}-net"
}

resource "yandex_vpc_subnet" "main" {
  name           = "${var.name}-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidr]
}

# Intra-VPC (10/8) целиком + наружу 80/443: доступ к API кластера и ingress.
resource "yandex_vpc_security_group" "main" {
  name       = "${var.name}-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "ANY"
    v4_cidr_blocks = ["10.0.0.0/8"]
  }
  ingress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_iam_service_account" "master" {
  name = "${var.name}-master-sa"
}

resource "yandex_iam_service_account" "node" {
  name = "${var.name}-node-sa"
}

resource "yandex_resourcemanager_folder_iam_member" "master_cluster" {
  folder_id = var.yc_folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_vpc" {
  folder_id = var.yc_folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_logging" {
  folder_id = var.yc_folder_id
  role      = "logging.writer"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_kubernetes_cluster" "main" {
  name                    = "${var.name}-cluster"
  network_id              = yandex_vpc_network.main.id
  service_account_id      = yandex_iam_service_account.master.id
  node_service_account_id = yandex_iam_service_account.node.id
  release_channel         = "STABLE"

  master {
    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.main.id]

    zonal {
      zone      = yandex_vpc_subnet.main.zone
      subnet_id = yandex_vpc_subnet.main.id
    }

    maintenance_policy {
      auto_upgrade = true
    }
  }

  # Сначала удаляется кластер, и только потом снимаются IAM-роли master SA.
  depends_on = [
    yandex_resourcemanager_folder_iam_member.master_cluster,
    yandex_resourcemanager_folder_iam_member.master_vpc,
    yandex_resourcemanager_folder_iam_member.master_logging
  ]
}

resource "yandex_kubernetes_node_group" "main" {
  cluster_id = yandex_kubernetes_cluster.main.id
  name       = "${var.name}-nodes"

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.main.id]
      security_group_ids = [yandex_vpc_security_group.main.id]
    }

    resources {
      cores         = var.node_cores
      memory        = var.node_memory
      core_fraction = 100
    }

    boot_disk {
      type = "network-ssd"
      size = 64
    }

    scheduling_policy {
      preemptible = false
    }
  }

  allocation_policy {
    location {
      zone = yandex_vpc_subnet.main.zone
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
