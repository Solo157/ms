provider "yandex" {
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  token     = var.yc_token # IAM or OAuth token via TF_VAR_yc_token (sensitive)
}

# The GitLab provider talks to the REST API; base_url must end with /api/v4/.
provider "gitlab" {
  base_url = "${trimsuffix(var.gitlab_base_url, "/")}/api/v4/"
  token    = var.gitlab_token # Project/Group PAT with `api` scope
}
