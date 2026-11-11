# OTUS CI/CD — микросервисное приложение в Yandex Cloud

Единый GitLab-проект: приложение + Terraform + Helm + GitLab CI/CD.
Автоматически поднимается инфраструктура в Yandex Cloud, собственный
GitLab Runner, Kubernetes, GitLab Kubernetes Agent, приложение и стек
мониторинга/логирования.

Приложение — из `github.com/Solo157/ms` (`application/user-service` :8081 +
`application/client-service` :8082, Spring Boot, PostgreSQL). Бизнес-логика не
изменена; добавлены только `spring-boot-starter-actuator` +
`micrometer-registry-prometheus` (метрики Prometheus).

## Структура

```
application/            код ms (user-service, client-service) + Dockerfile
  user-service/ client-service/
terraform/
  modules/              network | kubernetes | container-registry | gitlab-runner
  cloud-infrastructure/ state-1: VPC/SG/SA, MGKS+node group, Registry, Runner VM
  kubernetes/           state-2: namespaces dev/prod/monitoring, GitLab Agent
helm/
  application/          чарт приложения (+ in-cluster PostgreSQL), values-dev/prod
  monitoring/           values: ingress-nginx, kube-prometheus-stack, loki, alloy
kubernetes/agent/       (запас; манифесты агента ставит Terraform через helm)
.gitlab/agents/otus-agent/config.yaml   ci_access на текущий проект
.gitlab/ci/infrastructure.yml  .gitlab/ci/application.yml  .gitlab-ci.yml
```

## Архитектура (принятые упрощения для учебного проекта)

- 1 Managed Kubernetes кластер; namespaces `dev`, `prod`, `monitoring`; один
  `otus-agent`.
- Runner: `gitlab_user_runner` (project-scoped) + ВМ Ubuntu 24.04
  (2 vCPU / 4 GB / 40 GB), Docker executor, регистрация по auth-token `glrt-`
  через cloud-init. Теги `yc-runner,docker,terraform`, `untagged=false`,
  `locked=true`.
- Kubernetes-компоненты (`dev/prod/monitoring`, GitLab Agent) ставит Terraform
  (`helm_release`) через bootstrap-доступ (`yc managed-kubernetes cluster
  get-credentials`). Приложение дальше ходит только через `KUBE_CONTEXT`
  (`gitlab:<project-path>/otus-agent`).
- PostgreSQL — одна копия в кластере (`postgres:17-alpine`, конфиг из
  docker-compose), БД разделены логически: `users_db_dev` / `users_db_prod`.
- Мониторинг: kube-prometheus-stack (Prometheus, Grafana, Alertmanager) в
  `monitoring`; логи: Loki + Alloy (DaemonSet, hostPath /var/log).
- Доступ извне через nginx-ingress (LoadBalancer) + wildcard `*.nip.io` без TLS.

## GitLab CI/CD Variables

Не секретные (задать как обычные variables):

| Переменная | Значение |
|---|---|
| `YC_CLOUD_ID` | ID облака |
| `YC_FOLDER_ID` | ID каталога |
| `TF_STATE_BUCKET` | бакет Object Storage для state |
| `GITLAB_BASE_URL` | `https://vasyukov-158.gitlab.yandexcloud.net` |
| `GITLAB_PROJECT_ID` | numeric project id |
| `YC_REGISTRY_HOST` | хост реестра образов (`cr.yandex/<id>`) |
| `KUBE_CONTEXT` | `gitlab:<full-project-path>/otus-agent` |

Секретные (masked; для prod — protected):

| Переменная | Назначение |
|---|---|
| `YC_ACCESS_KEY_ID`, `YC_SECRET_ACCESS_KEY` | ключи IAM-юзера S3-бэкенда state |
| `TF_VAR_yc_token` | YC IAM/OAuth токен провайдера Terraform |
| `TF_VAR_gitlab_token` | GitLab PAT (scope `api`) |
| `TF_VAR_kubeconfig_path` | (в job к8s) путь к bootstrap-конфигу |

Правила безопасности: секреты только в CI Variables, маскируются в логах;
remote state в защищённом Object Storage (доступ ограничен); `glrt-`/agent token
попадают только в Terraform state (не в outputs и не в логи Pipeline); Runner SA
получает минимум ролей (`container-registry.images.pusher/puller`), node SA —
`puller`, master SA — роли MGKS из доков YC.

## Порядок развёртывания

> Первый запуск инфраструктуры нельзя выполнять на том Runner'е, который этот
> Pipeline создаёт. Поэтому **первичный `terraform apply` cloud-infrastructure
> — локально** (или на временном Runner'е). После появления ВМ Runner'а все
> дальнейшие прогоны идут на постоянном `yc-runner`.

### 0. Bootstrap (один раз, вручную, вне Git/CI)
- Создать Service Account для Object Storage, выдать роль `storage.editor`
  (или `admin`).
- Создать бакет `TF_STATE_BUCKET`, запомнить `YC_ACCESS_KEY_ID/SECRET_ACCESS_KEY`.
- Создать GitLab PAT scope `api` → `TF_VAR_gitlab_token`.
- Получить YC IAM-токен: `yc iam create-token` → `TF_VAR_yc_token`.

### 1. Локальный первичный apply cloud-infrastructure
```bash
cd terraform/cloud-infrastructure
cp terraform.tfvars.example terraform.tfvars   # заполнить ID (без секретов)
export TF_VAR_yc_token=... TF_VAR_gitlab_token=...
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="access_key=$YC_ACCESS_KEY_ID" \
  -backend-config="secret_key=$YC_SECRET_ACCESS_KEY"
terraform plan -out=tfplan && terraform apply tfplan
# создадутся VPC/SG/SA, MGKS+nodes, Registry, gitlab_user_runner + ВМ Runner'а
```
Дождаться, пока Runner появится в GitLab → Settings > CI/CD > Runners (online).

### 2. Infrastructure Pipeline (далее — в GitLab)
Задачи (stages `validate → plan → apply → bootstrap`), запускаются при изменении
`terraform/`, `helm/monitoring/**`, `kubernetes/**`:
- `tf-cloud-*` — fmt/validate/plan, ручной `tf-cloud-apply` (state-1);
- `k8s-bootstrap` — `yc ... get-credentials --new` → bootstrap kubeconfig (артефакт);
- `tf-k8s-apply` — namespaces + GitLab Agent (`gitlab_cluster_agent`+token+`helm
  gitlab-agent`) через bootstrap-конфиг; кладёт `KUBE_CONTEXT`;
- `install-monitoring` — helm: ingress-nginx, kube-prometheus-stack, loki, alloy;
  экспортирует IP LB.

### 3. Application Pipeline (`rules:changes`: `application/**`, `helm/application/**`)
`mvn-build → (mvn-test) → docker-build (push $CI_COMMIT_SHA, auth через IMDS-токен
VM SA) → deploy-dev (Helm через KAS в namespace dev, host app.<LB>.nip.io) →
smoke-test-dev (/health) → review-prod (manual) → deploy-prod (тот же тег, без
пересборки, namespace prod)`.

## Демонстрационный сценарий для преподавателя
1. GitLab → CI/CD → Pipelines → выбрать приложение → показать пайплайн до
   `deploy-prod` (manual gate) → Approve → показать `deploy-prod`.
2. `http://app.<LB>.nip.io/health` и `.../users` (создать/прочитать пользователя
   через client-service → он проксирует в user-service → PostgreSQL).
3. Grafana `http://grafana.<LB>.nip.io` (admin / `admin`):
   - метрики Kubernetes и обоих сервисов (`/actuator/prometheus` через
     ServiceMonitor), dashboards kube-prometheus-stack;
   - логи контейнеров из Loki (datasource Loki, Explore → LogQL).
4. Подтвердить, что метрики приложения собираются: в Prometheus
   Target `user-service`/`client-service` state=UP.

## Локальные проверки (выполнены при разработке)
- `terraform fmt -check` / `terraform validate` для обоих state — green.
- `helm lint` + `helm template` (dev/prod) — green.
- CI YAML — парсится, корректные anchors/rules.

## Известные упрощения
- `container-registry.images.*` гранятся на уровне folder (у
  `folder_iam_member` нет per-resource scope) — для демо допустимо.
- Kubernetes-версия master берётся из release_channel (STABLE) провайдера.
- Grafana admin password в значениях чарта (демо) — для реального прода
  вынести в protected variable.
- Ротация `glrt-`/`gitlab_token`: пересоздать ресурс (Terraform) / перевыпустить
  PAT в GitLab после создания нового и прогона пайплайна.
