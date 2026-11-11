resource "yandex_container_registry" "this" {
  name = var.name
}

# Folder-scoped role grants on the SAs (simple and demo-appropriate).
resource "yandex_resourcemanager_folder_iam_member" "puller" {
  count     = length(var.sa_puller_ids)
  folder_id = yandex_container_registry.this.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${var.sa_puller_ids[count.index]}"
}

resource "yandex_resourcemanager_folder_iam_member" "pusher" {
  count     = length(var.sa_pusher_ids)
  folder_id = yandex_container_registry.this.folder_id
  role      = "container-registry.images.pusher"
  member    = "serviceAccount:${var.sa_pusher_ids[count.index]}"
}
