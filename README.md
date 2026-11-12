# OTUS CI/CD — микросервисное приложение в Yandex Cloud

Учебный демо-проект в **одном GitLab-проекте**: приложение + Terraform + Helm +
Makefile + один GitLab CI pipeline. Всё разворачивается в один Managed Kubernetes
кластер Yandex Cloud.

Приложение — два Spring Boot сервиса:

- `application/user-service` — REST на `:8081`, данные H2 in-memory (без БД);
- `application/client-service` — REST-прокси на `:8082`, ходит в user-service.

## Архитектура

- **Terraform** (`terraform/`) создаёт только облако: одну VPC, одну подсеть в
  одной зоне, Security Group, один Managed Kubernetes (zonal) с одной Node Group,
  два сервисных аккаунта (master и node) и их IAM-роли. Terraform-провайдеры
  Kubernetes/Helm не используются. Один корень, один remote state в Yandex Object
  Storage (S3-backend).
- **CI разворачивает всё в кластер.** Сначала bootstrap-джоба ставит GitLab Agent
  for Kubernetes (`install_gitlab_agent`). Дальше доступ к Kubernetes идёт только
  через `KUBE_CONTEXT` (`<project-path>:otus-agent`) — временного kubeconfig в
  дальнейших джобах нет.
- **Один GitLab Runner** (внешний, тег `yc-runner`) создаётся и настраивается
  вручную оператором до первого запуска.
- **Образы** — в GitLab Container Registry (`CI_REGISTRY` / `CI_REGISTRY_IMAGE`).
  Kubernetes скачивает их через dockerconfigjson-Secret из Deploy Token.
- Не используются: PostgreSQL (данные в H2 in-memory), Yandex Container Registry,
  prod-окружение/namespace, Terraform modules, GitLab Runner из Terraform.

### Кто что делает

| Что | Чем |
|---|---|
| VPC, подсеть, SG, MGKS + Node Group, SA + IAM | Terraform (`terraform/`) |
| GitLab Runner | оператор, вручную (регистрация в проект, тег `yc-runner`) |
| GitLab Agent | CI `install_gitlab_agent` (YC CLI + Helm в ns `gitlab-agent`) |
| ingress-nginx, kube-prometheus-stack, Loki, Alloy | CI `install_cluster_components` (Helm через агент) |
| build/test, docker build/push, деплой приложения | CI-джобы + `Makefile` |
| bucket Object Storage + ключи, SA YC + ключ, Deploy Token, агент-токен | оператор, разово (см. «Первоначальная настройка») |

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
application/                 исходники + Dockerfile обоих сервисов (Maven reactor)
  user-service/  client-service/
terraform/                   один корень, один state, без модулей:
  main.tf           сеть, SG, кластер, node group, SA + IAM
  variables.tf  outputs.tf  providers.tf  versions.tf  backend.tf
  terraform.tfvars.example   образец terraform.tfvars (реальный tfvars не коммитим)
helm/application/            чарт приложения (name: ms-application):
  Chart.yaml  values.yaml
  templates/  user-service.yaml  client-service.yaml  ingress.yaml
              image-pull-secret.yaml
helm/monitoring/             только values для внешних чартов (своих чартов нет):
  values-ingress-nginx.yaml  values-kube-prometheus-stack.yaml
  values-loki.yaml  values-alloy.yaml
.gitlab/agents/otus-agent/config.yaml   ci_access на проект
Makefile                     build / test / docker-build / docker-push /
                             app-deploy / app-smoke / helm-lint / helm-template
.gitlab-ci.yml               один pipeline, 9 стадий, rules:changes
```

## GitLab CI/CD Variables

Auto (предопределённые GitLab — руками не задавать): `CI_PROJECT_PATH`,
`CI_PIPELINE_SOURCE`, `CI_COMMIT_BRANCH`, `CI_OPEN_MERGE_REQUESTS`, `CI_REGISTRY`,
`CI_REGISTRY_IMAGE`, `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD`, `CI_DEPLOY_USER`,
`CI_DEPLOY_PASSWORD`. `CI_DEPLOY_USER`/`CI_DEPLOY_PASSWORD` выдаёт сам GitLab из
Deploy Token `gitlab-deploy-token` на protected-ветке (сами переменные с префиксом
`CI_` не создаются). `KUBE_CONTEXT` = `$CI_PROJECT_PATH:otus-agent` собирается в
джобах.

Non-secret (задаёт оператор; значения берутся из GitLab/YC):

| Переменная | Значение |
|---|---|
| `YC_CLOUD_ID` | ID облака YC (из Yandex Cloud) |
| `YC_FOLDER_ID` | ID каталога YC (из Yandex Cloud) |
| `TF_STATE_BUCKET` | имя bucket Object Storage под state |
| `GITLAB_KAS_ADDRESS` | адрес KAS из UI GitLab (`wss://…/-/kubernetes-agent/`) |

Secret (masked):

| Переменная | Назначение |
|---|---|
| `YC_SA_KEY` | JSON-ключ сервисного аккаунта YC, **типа File**: GitLab отдаёт путь к файлу; его читают Terraform (`YC_SERVICE_ACCOUNT_KEY_FILE`) и `yc config set service-account-key` |
| `YC_ACCESS_KEY_ID` / `YC_SECRET_ACCESS_KEY` | статические ключи Object Storage; передаются в S3-backend только как env `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, чтобы не попасть в state |
| `GITLAB_AGENT_TOKEN` | токен агента (`glagent-…`) из UI GitLab. Не путать с токеном раннера (`glrt-…`) |

## Первоначальная настройка (разово, руками)

1. Сервисный аккаунт YC с ролью `editor` на каталог + JSON-ключ → `YC_SA_KEY`
   (тип File).
2. Object Storage: bucket под state + статические ключи (пользователь с
   `storage.editor`) → `YC_ACCESS_KEY_ID`/`YC_SECRET_ACCESS_KEY`, non-secret
   `TF_STATE_BUCKET`.
3. Зарегистрировать существующий внешний GitLab Runner с тегом `yc-runner`
   (Docker executor) в проекте. Runner в Terraform не создаётся.
4. Создать Deploy Token с именем `gitlab-deploy-token` и scope `read_registry`.
   Отдельные переменные не нужны — GitLab сам отдаст `CI_DEPLOY_USER`/
   `CI_DEPLOY_PASSWORD` на protected-ветке.
5. Создать GitLab Agent `otus-agent` в UI + токен агента → `GITLAB_AGENT_TOKEN`.
   В `.gitlab/agents/otus-agent/config.yaml` уже прописан `ci_access` на проект.
6. Задать non-secret: `YC_CLOUD_ID`, `YC_FOLDER_ID`, `TF_STATE_BUCKET`,
   `GITLAB_KAS_ADDRESS`. Ветка деплоя (обычно `main`) — protected.

Порядок файлов Terraform и переменные: значения по умолчанию заданы в
`variables.tf`; в CI required-значения (`yc_cloud_id`, `yc_folder_id`) и bucket
backend'а подаются отдельными переменными, секреты — через env (см. `.gitlab-ci.yml`
джобу `.tf-base`). Локально — скопировать `terraform.tfvars.example` в
`terraform.tfvars` (не коммитить).

## Порядок запуска инфраструктурного пайплайна

Триггер — коммит, затрагивающий `terraform/**`, `helm/monitoring/**` или конфиг
агента.

1. `terraform_validate` (стадия `validate`): `cd terraform && terraform fmt -check
   && terraform init -backend=false && terraform validate`.
2. `terraform_plan` (стадия `plan`): `terraform init -reconfigure
   -backend-config=bucket=$TF_STATE_BUCKET` и `terraform plan -out=tfplan`
   (артефакт `terraform/tfplan`).
3. `terraform_apply` (стадия `apply`, **manual** — сам не запускается): применяет
   `tfplan` и пишет `CLUSTER_ID` в `cluster.env` (dotenv-артефакт).
4. `install_gitlab_agent` (стадия `bootstrap`, после apply, берёт `CLUSTER_ID`):
   YC CLI получает временный kubeconfig (файл `0600`, живёт только во время джобы) и
   ставит GitLab Agent в namespace `gitlab-agent`. kubeconfig удаляется в
   `after_script`.
5. `install_cluster_components` (стадия `infrastructure`, после агента): разворачивает
   ingress-nginx (ждёт внешний IP балансировщика), kube-prometheus-stack (Grafana на
   `grafana.<LB>.nip.io`), Loki и Alloy. Все установки через `helm upgrade
   --install` — повторный запуск безопасен.

Дальнейший доступ к кластеру — через `KUBE_CONTEXT` (GitLab Agent), временный
kubeconfig больше не используется.

## Порядок запуска прикладного пайплайна

Триггер — коммит, затрагивающий `application/**`, `helm/application/**` или
`Makefile` (и только если в том же коммите не менялась инфраструктура).

6. `build_application` (стадия `build`): `make build`, артефакты jar.
7. `test_application` (стадия `test`): `make test`.
8. `build_images` (стадия `image`): ждёт **и** `build_application`, **и**
   `test_application`; `make docker-build docker-push` (образы в GitLab Registry).
9. `deploy_application` (стадия `deploy`): читает внешний IP ingress-nginx, ставит
   `INGRESS_HOST=app.<LB>.nip.io` и вызывает `make app-deploy app-smoke` —
   helm-релиз в namespace `dev` через агент, затем проверочные запросы.

При первом развёртывании сначала полностью прогоняется инфраструктурный пайплайн
(шаги 1–5), только потом — прикладной push (шаги 6–9). Изменения приложения
Terraform не запускают.

## Основные команды Makefile

Значения берутся из переменных GitLab; локально переопределяются через окружение
(`make -n` показывает команды без выполнения):

```
make build          # jar обоих сервисов (Maven, -DskipTests package)
make test           # unit-тесты (Maven test)
make docker-build   # docker build образов user- и client-service
make docker-push    # docker login в GitLab Registry + docker push обоих образов
make app-deploy     # helm upgrade --install релиза приложения в namespace dev
make app-smoke      # curl /health и /users через ingress-хост
make helm-lint      # helm lint helm/application
make helm-template  # helm template helm/application (проверка рендера)
```

Переопределяемые переменные: `IMAGE`, `TAG`, `KUBE_CONTEXT`, `NAMESPACE`,
`RELEASE`, `INGRESS_HOST`.

## Проверка после развёртывания

- Grafana: `http://grafana.<LB>.nip.io` (`admin`/`admin`). Готовые панели
  kube-prometheus-stack; источник данных Loki добавлен значениями чарта.
- Prometheus: `kubectl -n monitoring get servicemonitors` — видны `user-service` и
  `client-service`; в Targets они `UP` (метрики собираются через ServiceMonitor,
  отдельных аннотаций `prometheus.io/*` не требуется).
- Loki: в Explore Grafana (источник `Loki`) видны логи подов с метками `namespace`,
  `pod`, `container`.
- Приложение: `http://app.<LB>.nip.io/health` и `/users`.

IP балансировщика: `kubectl -n ingress-nginx get svc ingress-nginx-controller`.

## Известные ограничения демо

- Одна зона (по умолчанию `ru-central1-a`), фиксированный размер Node Group.
- H2 in-memory: данные user-service живут только внутри пода.
- Grafana admin-пароль в значениях чарта (только демо).
- Loki — SingleBinary, `filesystem`, retention 48h, без HA; сбор логов одним
  Alloy Deployment (не DaemonSet).
- Alertmanager намеренно выключен.
- GitLab Agent получает широкие RBAC-права в кластере — для продакшена их сузить.

## Локальные проверки и реальный YC

Локально проходят: `terraform fmt`/`validate`, `helm lint`/`template` приложения,
проверка синтаксиса `.gitlab-ci.yml`, `make -n`. Полный `terraform apply`,
развёртывание агента, получение внешнего IP, реальная работа
Prometheus/Grafana/Loki и самого приложения проверяются только запуском в Yandex
Cloud. Для `yc get-credentials` адрес GitLab Runner должен быть в allowlist
master-узла кластера.
