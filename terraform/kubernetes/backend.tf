# Second Terraform state (Kubernetes components). Same Object Storage bucket
# as cloud-infrastructure, different state key. Credentials supplied at
# `terraform init` via -backend-config / env (see README) — never in Git.
terraform {
  backend "s3" {
    endpoint                    = "https://storage.yandexcloud.net"
    region                      = "ru-central1"
    key                         = "kubernetes/terraform.tfstate"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
