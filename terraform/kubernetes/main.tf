# Confirm the cluster exists and expose its endpoint/CA for reference + so
# this state depends on the cluster being up before touching the API.
data "yandex_kubernetes_cluster" "this" {
  name      = var.cluster_name
  folder_id = var.yc_folder_id
}

# Three environment namespaces. (The agent itself is installed by Helm into
# its own namespace.)
resource "kubernetes_namespace_v1" "env" {
  for_each = toset(var.namespaces)
  metadata {
    name = each.value
  }
}

# --- GitLab Kubernetes Agent, fully managed by the GitLab Terraform provider.
data "gitlab_project" "this" {
  path_with_namespace = var.gitlab_project_path
}

resource "gitlab_cluster_agent" "this" {
  project = data.gitlab_project.this.id
  name    = var.agent_name
}

# glrt/agent auth token. Sensitive → sent to Helm via set_sensitive, never an
# output, never printed. (Still present in state — backend must be protected.)
resource "gitlab_cluster_agent_token" "this" {
  project     = data.gitlab_project.this.id
  agent_id    = gitlab_cluster_agent.this.agent_id
  name        = "${var.agent_name}-token"
  description = "Token for ${var.agent_name} (OTUS demo) used by gitlab-agent Helm chart"
}

# wss endpoint for a self-managed GitLab: wss://<host>/-/kubernetes-agent/
locals {
  gitlab_host    = regex("^https?://([^/]+)", trimsuffix(var.gitlab_base_url, "/"))
  agent_grpc_url = "wss://${local.gitlab_host}/-/kubernetes-agent/"
}

resource "helm_release" "gitlab_agent" {
  name             = "gitlab-agent"
  namespace        = var.agent_namespace
  create_namespace = true
  repository       = "https://charts.gitlab.io"
  chart            = "gitlab-agent"
  version          = var.agent_chart_version != "" ? var.agent_chart_version : null

  depends_on = [gitlab_cluster_agent_token.this]

  set {
    name  = "config.gitlabAddress"
    value = local.agent_grpc_url
  }

  set_sensitive {
    name  = "config.token"
    value = gitlab_cluster_agent_token.this.token
  }
}
