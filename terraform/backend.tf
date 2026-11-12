# Один-единственный remote backend в Yandex Object Storage (S3-совместимом) —
# для всего проекта (одна state-строка). Корзина и ключи доступа создаются вручную
# один раз до запуска Terraform и здесь НЕ хранятся.
#
# `terraform init` подаёт НЕСЕКРЕТHyй bucket через -backend-config:
#   terraform init -reconfigure -backend-config=bucket=$TF_STATE_BUCKET
#
# access_key/secret_key НЕ передаются ни в файле, ни через -backend-config:
# S3-backend разрешённый -backend-config пишет в .terraform/terraform.tfstate,
# поэтому креды подаются через стандартные env AWS SDK (AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY), которые terraform в стейт не сохраняет. Задаются в
# CI-джобе .tf-base из masked-переменных (см. .gitlab-ci.yml).
terraform {
  backend "s3" {
    endpoint                    = "https://storage.yandexcloud.net"
    region                      = "ru-central1"
    key                         = "terraform.tfstate"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
