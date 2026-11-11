provider "yandex" {
  folder_id = var.yc_folder_id
  token     = var.yc_token
}

provider "gitlab" {
  base_url = "${trimsuffix(var.gitlab_base_url, "/")}/api/v4/"
  token    = var.gitlab_token
}

# Bootstrap access to the cluster is provided by a short-lived kubeconfig
# generated with:
#   yc managed-kubernetes cluster get-credentials --id <cluster> --new
# (kubeconfig_path is produced by the k8s-bootstrap pipeline step / locally
# before `terraform apply`). This is the only direct-API phase; the application
# itself is deployed through the GitLab Agent afterwards.
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}
