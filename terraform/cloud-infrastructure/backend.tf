# Remote state backend in Yandex Object Storage (S3-compatible).
# The bucket and IAM access keys are created ONCE manually (bootstrap, per ТЗ)
# and are NOT stored here. `terraform init` supplies the non-secret parts
# plus credentials via -backend-config / env (see README):
#   terraform init \
#     -backend-config="bucket=${TF_STATE_BUCKET}" \
#     -backend-config="access_key=${YC_ACCESS_KEY_ID}" \
#     -backend-config="secret_key=${YC_SECRET_ACCESS_KEY}"
# Access key / secret key are deliberately absent here so secrets stay out of Git.
terraform {
  backend "s3" {
    endpoint                    = "https://storage.yandexcloud.net"
    region                      = "ru-central1"
    key                         = "cloud-infrastructure/terraform.tfstate"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
