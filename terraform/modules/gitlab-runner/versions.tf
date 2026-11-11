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
  }
  required_version = ">= 1.5.0"
}
