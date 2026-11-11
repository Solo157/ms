# Registers a project-scoped Runner in the current GitLab project via the
# GitLab Terraform Provider. The `token` (glrt- auth token) is consumed as a
# sensitive value by the VM cloud-init below; it is never printed to an
# output. NOTE: like all Terraform values it is still present in state —
# protect the remote backend / restrict access (course requirement).
resource "gitlab_user_runner" "this" {
  project_id      = var.gitlab_project_id
  runner_type     = "project_type"
  description     = var.runner_description
  untagged        = false
  locked          = true
  access_level    = "not_protected"
  tag_list        = var.runner_tags
  maximum_timeout = 3600
}

# Service account attached to the Runner VM so pipelines running on it can
# docker-login into Yandex Container Registry without static keys.
# push/pull bindings are created in the container-registry module.
resource "yandex_iam_service_account" "runner" {
  name = "${var.name}-runner-sa"
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

resource "yandex_compute_instance" "runner" {
  name        = "${var.name}-runner-vm"
  platform_id = "standard-v3"
  zone        = var.zone

  service_account_id = yandex_iam_service_account.runner.id

  resources {
    cores  = var.cores
    memory = var.memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.image_id
      type     = "network-ssd"
      size     = var.disk_size
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    nat                = true
    security_group_ids = var.security_group_ids
  }

  metadata = {
    ssh-keys = var.ssh_public_key != "" ? "ubuntu:${var.ssh_public_key}" : ""
    # user-data carries the glrt- auth token (see header note about state)
    user-data = templatefile("${path.module}/templates/cloud-init.tftpl", {
      token       = gitlab_user_runner.this.token
      gitlab_url  = var.gitlab_base_url
      description = var.runner_description
      tag_list    = join(",", var.runner_tags)
    })
  }
}
