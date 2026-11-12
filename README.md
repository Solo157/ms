# OTUS CI/CD — микросервисное приложение в Yandex Cloud

Единый GitLab-проект: приложение + Terraform + Helm + Makefile + GitLab CI/CD.

- **Terraform** создаёт **только** облачную часть Yandex Cloud: VPC, Subnets,
  Security Group, Managed Kubernetes, Node Group, Service Accounts и IAM-биндинги.
  Один root `terraform/`, один remote state в Object Storage (S3-backend).
  **Не использует** Kubernetes- и Helm-provider.
- **Установка GitLab Agent** (`install_gitlab_agent`) — отдельный job, внутри
  YC CLI + Helm; временный kubeconfig по `yc get-credentials`, Ansible и
  постоянный `KUBE_CONFIG` **не** используются.
- **Кластерные Helm-компоненты** (`install_cluster_components`) через
  `KUBE_CONTEXT` (KAS): ingress-nginx, kube-prometheus-stack, Loki, Alloy.
- **Приложение**: Makefile + Dockerfile + Helm-чарт. CI собирает два образа в
  GitLab Container Registry и деплоит через GitLab Agent.

Приложение — `application/user-service` (:8081, in-memory H2) +
`application/client-service` (:8082, REST-прокси), Spring Boot.

## Что Terraform / CI / вручную

| Что | Кто делает |
|---|---|
| VPC / Subnets / Security Group / MGKS + Node Group / SA + IAM | Terraform `terraform/` |
| GitLab Agent (`gitlab-agent`) | CI (`install_gitlab_agent`, YC CLI + Helm) |
| ingress-nginx, kube-prometheus-stack, Loki, Alloy | CI (`install_cluster_components`, Helm/KAS) |
| mvn build/test, docker build/push (GitLab Registry), helm deploy app | CI (`Makefile` + jobs `build_application`/`build_images`/`deploy_application`) |
| Object Storage bucket + статические ключи (backend state) | оператор, разово |
| SA YC (`editor` на каталог) + JSON-ключ | оператор, разово |
| Внешний GitLab Runner (`tags: yc-runner`) | оператор, разово |
| Deploy Token (`read_registry`) | оператор, разово |
| GitLab Agent `otus-agent` + token `glagent-…` (только через GitLab UI) | оператор, разово |

## Namespaces (разделение ответственности)

| Namespace | Содержимое |
|---|---|
| `gitlab-agent` | GitLab Agent |
| `ingress-nginx` | nginx-ingress |
| `monitoring`   | Prometheus, Grafana (без Alertmanager) |
| `logging`      | Loki, Alloy |
| `dev`          | приложение (`ms-user-service`, `ms-client-service`) |

## Структура

```
application/                 исходники + Dockerfile обоих сервисов
  user-service/  client-service/
terraform/                   ЕДИНЫЙ state: backend.tf main.tf variables.tf versions.tf
                             providers.tf outputs.tf  (k8s/helm providers НЕТ)
helm/application/            чарт приложения + values.yaml
                             templates: 2 Deployment/Service, Ingress,
                             ServiceMonitor, image-pull-secret
helm/monitoring/             values-ingress-nginx / kube-prometheus-stack /
                             loki / alloy
.gitlab/agents/otus-agent/config.yaml   ci_access на проект
Makefile                     build/test/docker-build/push/app-deploy/app-smoke
                             + helm-lint/helm-template (локально)
.gitlab-ci.yml               единый pipeline (9 стадий), rules:changes-разделение
```

## Архитектура (принятые решения)

### Terraform
- Yandex Cloud provider, **один state** (backend `s3`, key=`terraform.tfstate`,
  bucket из `-backend-config`, креды Object Storage — через env AWS SDK
  `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, а не `-backend-config`, чтобы
  не попадали в `.terraform/terraform.tfstate`).
- Выход: `cluster_id`, `cluster_name`, `cluster_external_endpoint`. `cluster_id`
  передаётся дальше через **dotenv артефакт** (`cluster.env`, `CLUSTER_ID=…`) в
  job `install_gitlab_agent`.
- **Только** облачные ресурсы: VPC/Subnets/SG/MGKS/NodeGroup/SA/IAM. Никакого
  k8s/helm/gitlab provider'а. Runner/реестр/GitLab — не здесь.

### Установочный job GitLab Agent (без Ansible)
- Образ job'а: `debian:bookworm-slim`, в before_script ставятся `yc`, `helm`,
  `kubectl` (кэш `$CI_PROJECT_DIR/.cache/bootstrap`).
- Авторизация YC CLI **из существующего SA**: `yc config set service-account-key
  <файл>` (+ `folder-id`). Это задокументированный non-interactive путь.
- Временный kubeconfig: `yc managed-kubernetes cluster get-credentials --id
  "$CLUSTER_ID" --external --force --kubeconfig $CI_PROJECT_DIR/kubeconfig`.
  После job'а он не сохраняется и в GitLab Variables никогда не кладётся.
- Helm: чарт `gitlab/gitlab-agent` `--version 2.33.0` `--set image.tag=v19.5.0`
  в ns `gitlab-agent`, `config.token=$GITLAB_AGENT_TOKEN`,
  `config.kasAddress=$GITLAB_KAS_ADDRESS` (в чарте 2.33.0 ключ называется
  `config.kasAddress`; `config.gitlabAddress` отсутствует и молча игнорируется).
- Проверка связности: `kubectl rollout status deployment/otus-agent-gitlab-agent`
  и grep логов `connected|started`.

### GitLab Agent config (`ci_access`)
`.gitlab/agents/otus-agent/config.yaml` даёт доступ только текущему проекту.
Дальше все K8s-job'ы работают через KAS:
`KUBE_CONTEXT = "$CI_PROJECT_PATH:otus-agent"`.

### Cluster components
Обычные GitLab CI jobs, `helm upgrade --install` (+ `values.yaml` в git):
- **ingress-nginx** `4.15.1` в `ingress-nginx` — LoadBalancer YC; IP нужен для
  nip.io (`grafana.<LB>.nip.io`, `app.<LB>.nip.io`).
- **kube-prometheus-stack** `69.8.2` в `monitoring`, **без Alertmanager**
  (`alertmanager.enabled=false`, `defaultRules.create=false`). Grafana Ingress
  host — `<LB>.nip.io`; Loki datasource — `http://loki.logging.svc.cluster.local:3100`.
- **Loki** `6.55.0` в `logging` — `deploymentMode: SingleBinary`, `replicas: 1`,
  filesystem, retention 48h. Service в кластере: `loki.logging.svc.cluster.local:3100`.
- **Grafana Alloy** `1.15.0` в `logging` — **один Deployment** (`replicas: 1`,
  образ `alloy:v1.21.3`), `loki.source.kubernetes` (watch API pod/log), RBAC
  создаётся чартом, дублей нет (не DaemonSet/hostPath), push по адресу Loki.

### Приложение (Makefile + Dockerfiles + Helm)
- **Dockerfile** обоих сервисов — `eclipse-temurin:21-jre`, COPY `target/app.jar`
 (не multi-stage: child-pom наследует `<parent>` из `../pom.xml`, поэтому Docker
 build берёт готовые jar как артефакты Maven-job).
- **Makefile** — единая точка входа приложения. CI вызывает только `make <target>`
  (`terraform fmt/validate` job `terraform_validate` выполняет напрямую, не через Makefile):
  - `build` / `test` — Maven reactor (jar в `application/<svc>/target/app.jar`),
  - `docker-build` / `docker-push` — образы `$(IMAGE)/ms-user-service:$(TAG)`
    и `.../ms-client-service:$(TAG)`; логин + push одной target'ой `docker-push`
    через `CI_REGISTRY_USER/PASSWORD`,
  - `app-deploy` — `helm upgrade --install ms-dev -n dev --kube-context=$CI_PROJECT_PATH:otus-agent`
    с `--set image.registry=$CI_REGISTRY_IMAGE --set image.tag=$CI_COMMIT_SHA
    --set registry.server=$CI_REGISTRY --set registry.username/password=$CI_DEPLOY_*`
    (imagePullSecret) `--set ingress.host=$INGRESS_HOST`,
  - `app-smoke` — curl `/health`, `/users`,
  - `helm-lint` / `helm-template` — локальная проверка чарта (в CI не вызывается).
- **Docker-in-Docker** — `docker:27` + `docker:27-dind`, `DOCKER_TLS_CERTDIR=/certs`.
- **Push** — GitLab Container Registry (`$CI_REGISTRY_IMAGE`) built-in токеном.
- **Pull из Kubernetes** — GitLab Deploy Token (`gitlab-deploy-token`, scope
  `read_registry`) через predefined `CI_DEPLOY_USER` / `CI_DEPLOY_PASSWORD`
  (заполняются GitLab только на protected-refs) кладётся в Templated-секрет
  `gitlab-registry` чарта `application` (типа `kubernetes.io/dockerconfigjson`).
  Job-токен `CI_REGISTRY_PASSWORD` для этого не годится — он истекает с job'ом,
  а образ должен переживать рестарт Pod'а.
- Yandex Container Registry не используется.

## GitLab CI/CD Variables

Auto (built-in) — **не задавать**: `CI_SERVER_URL`, `CI_PROJECT_PATH`, `CI_PIPELINE_SOURCE`,
`CI_COMMIT_BRANCH`, `CI_OPEN_MERGE_REQUESTS`, `CI_REGISTRY`, `CI_REGISTRY_IMAGE`,
`CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD`, `CI_DEPLOY_USER`, `CI_DEPLOY_PASSWORD`
(последние две — predefined от Deploy Token `gitlab-deploy-token`; заполняются
только на protected-refs). `KUBE_CONTEXT` строится прямо в job'ах.

Non-secret:

| Переменная | Значение |
|---|---|
| `YC_CLOUD_ID` | ID облака YC |
| `YC_FOLDER_ID` | ID каталога YC |
| `TF_STATE_BUCKET` | бакет Object Storage (state) |
| `GITLAB_KAS_ADDRESS` | `wss://<gitlab-host>/-/kubernetes-agent/` |

Secret (masked; Protected — по необходимости):

| Переменная | Назначение |
|---|---|
| `YC_SA_KEY` | JSON-ключ SA — перменная **типа File**: GitLab пишет ключ во временный файл и кладёт путь в `$YC_SA_KEY`. Terraform provider (`YC_SERVICE_ACCOUNT_KEY_FILE`) и `yc config set service-account-key` получают этот путь как есть |
| `YC_ACCESS_KEY_ID` / `YC_SECRET_ACCESS_KEY` | статические ключи Object Storage; подаются в S3-backend только как env `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (в `-backend-config` и стейт не пишутся) |
| `GITLAB_AGENT_TOKEN` | `glagent-…` — создаётся **только** в UI GitLab (`User → Access Tokens → Agent token`). Не путать с `glrt-…` — это Runner authentication token, агент его не примет |

> `CI_DEPLOY_USER` / `CI_DEPLOY_PASSWORD` в этой таблице **нет** намеренно: их
> нельзя создать руками (префикс `CI_` зарезервирован). Их выдаёт сам GitLab из
> Deploy Token `gitlab-deploy-token` (protected-refs). См. блок **Auto** выше.

## Bootstrap (разово, руками, вне Git/CI)

1. **SA YC** с ролью `editor` на каталог + JSON-ключ → переменная `YC_SA_KEY`
   **типа File** (GitLab сам положит JSON во временный файл и отдаст путь в `$YC_SA_KEY`).
2. **Object Storage**: bucket (например `otus-ms-tfstate`) + пользователь с
   ролью `storage.editor` + статические ключи → `YC_ACCESS_KEY_ID` /
   `YC_SECRET_ACCESS_KEY`. `TF_STATE_BUCKET` — non-secret.
3. **Внешний Runner**: зарегистрировать в проекте, теги `yc-runner`,
   untagged=false, locked=true, Docker executor. Никакой логики YC-реестра на
   хосте раннера — push идёт по built-in GitLab-переменным.
4. **Deploy Token**: Settings → Repository → Deploy Tokens. **Имя токена
   `gitlab-deploy-token`**, scope `read_registry`, срок по политике. Свои
   переменные создавать НЕ нужно: GitLab сам предоставляет `CI_DEPLOY_USER` и
   `CI_DEPLOY_PASSWORD` как predefined-переменные пайплайна (имена с префиксом
   `CI_` в UI создать нельзя — они зарезервированы). Важно: GitLab заполняет
   их **только на protected-refs** — ветка, из которой крутится `deploy_application`
   (сборка imagePullSecret), должна быть protected; иначе переменные придут
   пустыми и pull-секрет не соберётся.
5. **GitLab Agent** (в UI): Build → Pipeline editors → Kubernetes → Add an agent,
   имя `otus-agent`. После сохранения — создать **Agent token** (Scope=Default
   Agent access) → masked `GITLAB_AGENT_TOKEN`. В `.gitlab/agents/otus-agent/config.yaml`
   (уже в репо) прописан `ci_access.projects[].id` — при следующем коннекте агент
   подтянет конфиг.
6. Задать **несекретные** переменные: `YC_CLOUD_ID`, `YC_FOLDER_ID`,
   `TF_STATE_BUCKET`, `GITLAB_KAS_ADDRESS`.
7. **Первый запуск pipeline** (коммит, затрагивающий `terraform/`) —
   `terraform_validate` → `terraform_plan` → **вручную** `terraform_apply`.
   После apply появятся kubeconfig-параметры. **Постоянный kubeconfig не забираем**:
   следующий job сам его получает по SA CLI.
8. Запустить `install_gitlab_agent` (автоматический, после apply) и дождаться,
   пока в GitLab UI появится: Agent online.
9. Запустить `install_cluster_components` (автоматически, после agent) и дождаться,
   пока в трёх namespace поднимутся все компоненты.
10. Далее — штатные push-пайплайны.

## Порядок запуска pipeline (ожидаемый)

### Инфраструктурный пайплайн (`rules:changes: terraform/**/*, helm/monitoring/**/*, .gitlab/agents/otus-agent/config.yaml`)

1. `terraform_validate`   — stage `validate` (fmt + init -backend=false + validate).
2. `terraform_plan`       — stage `plan` (init+plan, артефакт `terraform/tfplan`).
3. `terraform_apply`      — stage `apply`, `when: manual`. Артефакт `cluster.env` (dotenv: `CLUSTER_ID`).
4. `install_gitlab_agent` — stage `bootstrap`, needs `terraform_apply` (dotenv
   `CLUSTER_ID`). YC CLI авторизация → `get-credentials --external` → helm `gitlab-agent`
   → проверки `kubectl`/`logs`. Временный kubeconfig живёт только в job'е.
5. `install_cluster_components` — stage `infrastructure`, needs `install_gitlab_agent`.
   Helm через `KUBE_CONTEXT`. Идемпотентен.

### Приложенческий пайплайн (`rules:changes: application/**/*, helm/application/**/*` — и `when: never`, если в коммите тронута инфраструктура)

6. `build_application` (stage `build`, `make build`) → артефакты jar'ов.
   `test_application`   (stage `test`, `make test`) — needs `build_application`.
7. `build_images`        (stage `image`, `docker:27 + dind`; `make docker-build
   docker-push`). needs `build_application`.
8. `deploy_application`  (stage `deploy`, `dtzar/helm-kubectl`, `make app-deploy
   app-smoke`). needs `build_images`. Читает LB из namespace `ingress-nginx`.

Кросс-контура: `deploy_application` логически требует установленные cluster
components (LB/CRD). CI-нужд это не связывает (разные пайплайны). При первичной
настройке сначала проходят 1–5, только затем 6–8. Идемпотентные `helm upgrade
--install` и `terraform apply` делают повторный запуск безопасным.

## Что уже проверено локально vs. требует реального YC

**Проверено локально (в песочнице):**
- Terraform: `terraform fmt -check`, `terraform validate` (с provider-кэшем).
- helm lint + helm template: `application` (с заполненными registry-cred и
  ingress.host); kube-prometheus-stack 69.8.2, loki 6.55.0, alloy 1.15.0 (values
  корректно рендерятся: 0 Alertmanager-объектов, Loki Service `loki.<ns>` :3100,
  Alloy — Deployment с RBAC `pods`+`pods/log`).
- YAML: `.gitlab-ci.yml` парсится (единый pipeline, 9 стадий, rules:changes-разделение).
- Makefile: `make -n` для `build/test/docker-build/docker-push/app-deploy/app-smoke`
  (POSIX-`/bin/sh`, работает и в Alpine-образах CI), все `make <target>` из CI существуют.
- `yc config set service-account-key <файл>` корректно парсит SA-ключ (проверено
  isolated-профилем; ошибка возникает только на подписи фейковым private key).
- Флаги `yc managed-kubernetes cluster get-credentials --id --external
  --force --kubeconfig` валидны (вывод `yc ... --help`).
- Версии чартов/образов совпадают с зафиксированными: `gitlab-agent 2.33.0 →
  image.tag=v19.5.0`, `alloy 1.15.0 → tag=v1.21.3`.

**Требует реального запуска в Yandex Cloud (подтвердить в ран-тайме):**
- Полный `terraform plan/apply` (IAM-роли для SA в каталоге, квоты).
- Авторизация YC CLI реальным SA-ключом + `yc get-credentials`:
  **IP GitLab Runner должен быть добавлен в master-allowlist кластера**, иначе
  внешний endpoint не пропустит; kubeconfig не создастся.
- Реальный Helm-релиз `gitlab-agent`: online-агент в GitLab + KASENDPOINT доступен
  из кластера (`GITLAB_KAS_ADDRESS`).
- Реальный ingress LB IP (Yandex LoadBalancer отдаёт адрес асинхронно).
- Реальный Prometheus/Grafana/Loki: поды готовы, ServiceMonitor CRD уже в кластере.
- Деплой приложения и smoke через `app.<LB>.nip.io`.
- `mvn build/test` локально в песочнице не запускался (нет TLS к Maven Central).
- Docker build локально не выполнялся (DinD/push — только в CI на Runner'е).

## Известные упрощения / ограничения

- Terraform: версии K8s — из `release_channel` (STABLE), фиксированный размер узла.
- Grafana admin-пароль в значениях — для демо; в «реале» вынести в protected var.
- Loki: `filesystem` + retention 48h, один `SingleBinary`-под, без HA.
- Alloy: один Deployment, не DaemonSet.
- GitLab Agent SA по умолчанию получает `cluster-admin` для KAS-операций (chart's
  default `rbac:`). Для продакшена — сузить до реальных нужд.
- H2 in-memory у `user-service`: данные живут только в Pod'е.
- Ротация `glagent-`: перевыпустить токен в UI, обновить `GITLAB_AGENT_TOKEN`,
  перезапустить `install_gitlab_agent`.
- Ротация Deploy Token: то же через UI + `install_cluster_components` не нужен —
  достаточно `app-deploy`.
