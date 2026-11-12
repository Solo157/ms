# Единый Terraform-конфиг проекта (один state). Создаёт только облачную часть:
# сеть, Managed Kubernetes, Node Group и Service Accounts с IAM-ролями.
# Runner, контейнерный реестр и GitLab-ресурсы здесь НЕ создаются — они
# подготовлены вручную заранее. Kubernetes Provider / Helm Provider НЕ
# используются: helm-компоненты (gitlab-agent, ingress, мониторинг, логи) и
# приложение ставит CI-пайплайн через Helm (gitlab-agent / KUBE_CONTEXT).
# output cluster_id передётся дальше по цепочке (dotenv) в job установки агента.

# --- Сеть ---
resource "yandex_vpc_network" "this" {
  name = "${var.name}-net"
}

resource "yandex_vpc_subnet" "this" {
  count          = length(var.zones)
  name           = "${var.name}-subnet-${count.index}"
  zone           = var.zones[count.index]
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.subnet_cidrs[count.index]]
}

# Разрешительная для демо security group: весь intra-VPC трафик + egress, и
# наружу K8s API / ingress на 443/80 (публичный доступ через nginx-ingress и nip.io
# — требование учебного курса).
resource "yandex_vpc_security_group" "this" {
  name       = "${var.name}-sg-default"
  network_id = yandex_vpc_network.this.id

  # Внутри облака (VPC + pod/service CIDR в 10/8) — разрешить всё.
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

# --- Service Accounts кластера ---
# SA managed-master (роли из доков YC MGKS).
resource "yandex_iam_service_account" "master" {
  name = "${var.name}-master-sa"
}

# SA, работающий НА воркерах. Роль puller YCR НЕ выдаётся — образы тянутся из
# GitLab Container Registry через imagePullSecret, Yandex Registry не используется.
resource "yandex_iam_service_account" "node" {
  name = "${var.name}-node-sa"
}

resource "yandex_resourcemanager_folder_iam_member" "master_cluster" {
  folder_id = var.yc_folder_id
  role      = "k8s.cluster-api.cluster"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_vpc" {
  folder_id = var.yc_folder_id
  role      = "vpc.privateAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_logging" {
  folder_id = var.yc_folder_id
  role      = "logging.writer"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "node_vpc" {
  folder_id = var.yc_folder_id
  role      = "vpc.privateUser"
  member    = "serviceAccount:${yandex_iam_service_account.node.id}"
}

# --- Managed Kubernetes ---
resource "yandex_kubernetes_cluster" "this" {
  name                    = "${var.name}-cluster"
  network_id              = yandex_vpc_network.this.id
  service_account_id      = yandex_iam_service_account.master.id
  node_service_account_id = yandex_iam_service_account.node.id
  release_channel         = "STABLE"

  master {
    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.this.id]

    zonal {
      zone      = yandex_vpc_subnet.this[0].zone
      subnet_id = yandex_vpc_subnet.this[0].id
    }

    maintenance_policy {
      auto_upgrade = true
    }
  }

  # Кластер должен удалиться раньше, чем будут сняты SA/роли.
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
      subnet_ids         = [yandex_vpc_subnet.this[0].id]
      security_group_ids = [yandex_vpc_security_group.this.id]
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
      zone = yandex_vpc_subnet.this[0].zone
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
