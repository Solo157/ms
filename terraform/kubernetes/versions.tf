terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.145"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = ">= 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13, < 3.0.0"
    }
  }
  required_version = ">= 1.5.0"
}
