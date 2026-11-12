# Единственный remote backend в Yandex Object Storage (S3-совместимом) — один на
# весь проект (одна строка state). Корзину и ключи доступа создают вручную один раз
# до запуска Terraform, здесь их нет.
#
# `terraform init` получает только Некритичный bucket через -backend-config:
#   terraform init -reconfigure -backend-config=bucket=$TF_STATE_BUCKET
#
# access_key/secret_key не передаются ни в файле, ни через -backend-config:
# S3-backend сохраняет разрешённый -backend-config в .terraform/terraform.tfstate,
# поэтому ключи передают через стандартные переменные окружения AWS SDK
# (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY), которые Terraform в state не
# записывает. Задаются в CI-джобе .tf-base из masked-переменных (см. .gitlab-ci.yml).
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
