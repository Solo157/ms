provider "yandex" {
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  # Аутентификация — JSON-ключ сервисного аккаунта: провайдер читает путь к ключу
  # из env YC_SERVICE_ACCOUNT_KEY_FILE (или сам JSON из YC_SERVICE_ACCOUNT_KEY).
  # В коде и стейте токенов нет (см. CI-джобу .tf-base и README).
}
