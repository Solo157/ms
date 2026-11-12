# OTUS CI/CD — микросервисное приложение в Yandex Cloud

Учебный демо-проект: приложение + Terraform + Helm + Makefile + один GitLab CI
pipeline. Всё разворачивается в один Managed Kubernetes кластер Yandex Cloud.

Приложение — два Spring Boot сервиса:

- `application/user-service` — REST на `:8081`, данные in-memory (H2);
- `application/client-service` — REST-прокси на `:8082`, ходит в user-service.

## Архитектура

- **Terraform** создаёт только облако: сеть, подсеть, Security Group, Managed
  Kubernetes, Node Group, сервисные аккаунты и IAM-роли. Terraform-провайдеры
  Kubernetes/Helm не используются. Один корень `terraform/`, один remote state в
  Object Storage (S3-backend).
- **CI ставит всё в кластер** через GitLab Agent for Kubernetes (`KUBE_CONTEXT`):
  сам агент, ingress-nginx, Prometheus+Grafana, Loki+Alloy и приложение.
- **Приложение** собирается `make`/Maven, образы — в GitLab Container Registry,
  скачивание образов из Kubernetes — через dockerconfigjson-Secret из Deploy Token.
- Yandex Container Registry, отдельный PostgreSQL, prod-окружение — **не**
  используются.

### Кто что делает

| Что | Чем |
|---|---|
| VPC, подсеть, SG, MGKS + Node Group, SA + IAM | Terraform (`terraform/`) |
| GitLab Agent | CI `install_gitlab_agent` (YC CLI + Helm) |
| ingress-nginx, kube-prometheus-stack, Loki, Alloy | CI `install_cluster_components` (Helm через агент) |
| build/test, docker build/push, деплой приложения | CI jobs + `Makefile` |
| bucket Object Storage + ключи, SA YC + ключ, внешний Runner, Deploy Token, агент-токен | оператор, разово (см. Bootstrap) |

### Namespace'ы

| Namespace | Содержимое |
|---|---|
| `gitlab-agent` | GitLab Agent |
| `ingress-nginx` | ingress-nginx (LoadBalancer) |
| `monitoring` | Prometheus, Grafana (Alertmanager выключен) |
| `logging` | Loki, Alloy |
| `dev` | приложение (`user-service`, `client-service`) |

## Структура

```
application/                 исходники + Dockerfile обоих сервисов
  user-service/  client-service/
terraform/                   один корень, один state, без модулей:
  backend.tf  main.tf  outputs.tf  providers.tf  variables.tf  versions.tf
helm/application/            чарт приложения
  values.yaml
  templates/  user-service.yaml  client-service.yaml  ingress.yaml
              image-pull-secret.yaml
helm/monitoring/             values-ingress-nginx.yaml  values-kube-prometheus-stack.yaml
              values-loki.yaml  values-alloy.yaml
.gitlab/agents/otus-agent/config.yaml   ci_access на проект
Makefile                     build / test / docker-build / docker-push /
                             app-deploy / app-smoke / helm-lint / helm-template
.gitlab-ci.yml               один pipeline, 9 стадий, rules:changes
```

## CI/CD Variables

Auto (предопределённые GitLab — руками не задавать): `CI_PROJECT_PATH`,
`CI_PIPELINE_SOURCE`, `CI_COMMIT_BRANCH`, `CI_OPEN_MERGE_REQUESTS`, `CI_REGISTRY`,
`CI_REGISTRY_IMAGE`, `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD`, `CI_DEPLOY_USER`,
`CI_DEPLOY_PASSWORD` (последние две — из Deploy Token, заполняются только на
protected-ветках). `KUBE_CONTEXT` = `$CI_PROJECT_PATH:otus-agent` собирается в job'ах.

Non-secret:

| Переменная | Значение |
|---|---|
| `YC_CLOUD_ID` | ID облака YC |
| `YC_FOLDER_ID` | ID каталога YC |
| `TF_STATE_BUCKET` | bucket Object Storage под state |
| `GITLAB_KAS_ADDRESS` | `wss://<gitlab-host>/-/kubernetes-agent/` |

Secret (masked):

| Переменная | Назначение |
|---|---|
| `YC_SA_KEY` | JSON-ключ сервисного аккаунта, **типа File**: GitLab кладёт файл во временный путь и отдаёт путь в `$YC_SA_KEY`. Его читают Terraform (`YC_SERVICE_ACCOUNT_KEY_FILE`) и `yc config set service-account-key` |
| `YC_ACCESS_KEY_ID` / `YC_SECRET_ACCESS_KEY` | статические ключи Object Storage; подаются в S3-backend только как env `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, чтобы не попасть в state |
| `GITLAB_AGENT_TOKEN` | `glagent-…` (Agent token из UI GitLab). Не путать с `glrt-…` — это токен раннера, агент его не примет |

`CI_DEPLOY_USER`/`CI_DEPLOY_PASSWORD` вручную не создаются: префикс `CI_`
зарезервирован, их выдаёт сам GitLab из Deploy Token `gitlab-deploy-token`.

## Первоначальная настройка (разово, руками)

1. Сервисный аккаунт YC с ролью `editor` на каталог + JSON-ключ → `YC_SA_KEY`
   (тип File).
2. Object Storage: bucket под state + пользователь `storage.editor` + статические
   ключи → `YC_ACCESS_KEY_ID`/`YC_SECRET_ACCESS_KEY`, non-secret `TF_STATE_BUCKET`.
3. Внешний GitLab Runner с тегом `yc-runner` (Docker executor).
4. Deploy Token с именем `gitlab-deploy-token`, scope `read_registry`. Отдельные
   переменные не нужны — GitLab сам отдаст `CI_DEPLOY_USER`/`CI_DEPLOY_PASSWORD`
   на protected-ветке (без protected ветки pull-секрет соберётся пустым).
5. GitLab Agent `otus-agent` в UI + Agent token → `GITLAB_AGENT_TOKEN`. В
   `.gitlab/agents/otus-agent/config.yaml` прописан `ci_access` на проект.
6. Задать non-secret: `YC_CLOUD_ID`, `YC_FOLDER_ID`, `TF_STATE_BUCKET`,
   `GITLAB_KAS_ADDRESS`. Ветка с деплоем (обычно `main`) — protected.

## Порядок запуска инфраструктурного пайплайна

Триггер — коммит, затрагивающий `terraform/**`, `helm/monitoring/**` или конфиг
агента.

1. `terraform_validate` — стадия `validate`: `cd terraform && fmt -check && init -backend=false && validate`.
2. `terraform_plan` — стадия `plan`: init (backend-config=bucket) + `plan -out=tfplan`, артефакт `terraform/tfplan`.
3. `terraform_apply` — стадия `apply`, **manual** (не запускается сам): применяет
   `tfplan` и записывает `CLUSTER_ID` в `cluster.env` (dotenv-артефакт).
4. `install_gitlab_agent` — стадия `bootstrap`, запускается после apply (берёт из
   него `CLUSTER_ID`): YC CLI получает временный kubeconfig и устанавливает
   `gitlab-agent` в namespace `gitlab-agent`. kubeconfig живёт только во время job'а.
5. `install_cluster_components` — стадия `infrastructure`, запускается после
   агента: разворачивает ingress-nginx (ждёт внешний IP балансировщика),
   kube-prometheus-stack (`grafana.<LB>.nip.io`), Loki и Alloy. Повторный запуск
   безопасен — используется `helm upgrade --install`.

## Порядок запуска приложения

Триггер — коммит, затрагивающий `application/**`, `helm/application/**` или
`Makefile` (и только если в том же коммите не менялась инфраструктура).

6. `build_application` — `make build`, артефакты jar.
7. `test_application` — `make test` (после успешной сборки).
8. `build_images` — только после сборки **и** тестов: `make docker-build docker-push`.
9. `deploy_application` — `make app-deploy app-smoke`: установка helm-релиза в
   namespace `dev` через агент, адрес `app.<LB>.nip.io`, затем проверочные запросы.

При первом развёртывании сначала полностью прогоняется инфраструктурный
пайплайн (steps 1–5), только потом — прикладной push (6–9). Дальнейшие изменения
приложения Terraform не запускают.

## Проверка после развёртывания

- Grafana: `http://grafana.<LB>.nip.io` (имя `admin`, пароль `admin`). Готовые
  панели по кластеру и узлам из kube-prometheus-stack; источник данных **Loki**
  добавлен настройками чарта.
- Prometheus: `kubectl -n monitoring get servicemonitors` — видны `user-service`
  и `client-service`; в разделе Targets они в состоянии `UP` (метрики приложения
  собираются через ServiceMonitor, отдельных аннотаций `prometheus.io/*` не нужно).
- Loki: в разделе Explore в Grafana (источник данных `Loki`) видны логи подов с
  метками `namespace`, `pod`, `container`.
- Приложение: `http://app.<LB>.nip.io/health` и `/users`.

IP балансировщика: `kubectl -n ingress-nginx get svc ingress-nginx-controller`.

## Известные ограничения демо

- Одна зона (по умолчанию `ru-central1-a`), фиксированный размер Node Group.
- H2 in-memory: данные user-service живут только внутри пода.
- Grafana admin-пароль в значениях чарта (только демо).
- Loki — SingleBinary, `filesystem`, retention 48h, без HA; сбор логов одним
  Deployment Alloy (не DaemonSet).
- Alertmanager намеренно выключен.
- GitLab-агент по умолчанию получает широкие права в кластере (настройку чарта
  `rbac`) — для продакшена их нужно сузить.

## Локальные проверки и реальный YC

Локально проходят: `terraform fmt`/`validate`, `helm lint`/`template`, проверка
синтаксиса `.gitlab-ci.yml`, `make -n`. Полный `terraform apply`, развёртывание
агента, получение внешнего IP, реальная работа Prometheus/Grafana/Loki и самого
приложения проверяются только запуском в Yandex Cloud. Для `yc get-credentials`
адрес GitLab Runner должен быть в списке разрешённых (allowlist) master-узла
кластера.
