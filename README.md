# OTUS CI/CD — приложение + выкатка через GitLab

Учебный демо-проект в **одном GitLab-проекте**: микросервисное приложение + один
GitLab CI pipeline, который **только собирает и выкатывает приложение** на
подготовленный Kubernetes-стенд.

> **Развёртывание инфраструктуры (кластер, ingress-контроллер, мониторинг) в этот
> проект НЕ входит.** Кластер и ingress подготавливаются снаружи (оператор /
> отдельный проект). Здесь остаётся только приложение и pipeline его деплоя.

Приложение — два Spring Boot сервиса:

- `application/user-service` — REST на `:8081`, данные H2 in-memory (без БД);
- `application/client-service` — REST-прокси на `:8082`, ходит в user-service.

## Структура

```
application/                 исходники + Dockerfile обоих сервисов (Maven reactor)
  user-service/  client-service/
helm/application/            чарт приложения (name: ms-application):
  Chart.yaml  values.yaml
  templates/  user-service.yaml  client-service.yaml  ingress.yaml
              image-pull-secret.yaml
Makefile                     build / test / docker-build / docker-push /
                             app-deploy / app-smoke / helm-lint / helm-template
.gitlab-ci.yml               pipeline приложения: build -> image -> deploy
```

## GitLab CI/CD pipeline

Стадии: **build -> image -> deploy**.

1. `build_application` (стадия `build`, **manual**): `make build`, артефакты — jar'ы
   обоих сервисов.
2. `build_images` (стадия `image`): `make docker-build docker-push` — образы в GitLab
   Container Registry (`CI_REGISTRY` / `CI_REGISTRY_IMAGE`).
3. `deploy_application` (стадия `deploy`): получает временный kubeconfig до
   существующего кластера, `make app-deploy app-smoke` — helm-релиз приложения в
   namespace `dev` по хосту `INGRESS_HOST`, затем проверочные запросы.

## GitLab CI/CD Variables

Auto (предопределённые GitLab — руками не задавать): `CI_PROJECT_PATH`,
`CI_PIPELINE_SOURCE`, `CI_COMMIT_BRANCH`, `CI_OPEN_MERGE_REQUESTS`, `CI_REGISTRY`,
`CI_REGISTRY_IMAGE`, `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD`, `CI_DEPLOY_USER`,
`CI_DEPLOY_PASSWORD` (последние два выдаёт Deploy Token `gitlab-deploy-token` на
protected-ветке).

Non-secret (задаёт оператор):

| Переменная | Значение |
|---|---|
| `YC_FOLDER_ID` | ID каталога YC (для `yc get-credentials` до готового кластера) |
| `INGRESS_HOST` | **внешний ingress-хост приложения** (см. «Как получить INGRESS_HOST в YC») |

Secret (masked):

| Переменная | Назначение |
|---|---|
| `YC_SA_KEY` | JSON-ключ сервисного аккаунта YC, **типа File**: путь к нему для `yc config set service-account-key` |

Параметр `CLUSTER_NAME` (имя готового кластера) задан дефолтом в `.gitlab-ci.yml`
(`otus-ms-cluster`); переопределяется переменной CI/CD при другом имени.

## Как получить INGRESS_HOST в YC

`INGRESS_HOST` — это DNS-имя, по которому приложение доступно снаружи стенда. ingress
`type: LoadBalancer` получает внешний IP от Yandex Cloud; хост собирается как
`app.<IP>.nip.io` (wildcard-DNS `*.nip.io` указывает на любой IPv4, отдельная зона не
нужна). Значит достаточно узнать внешний IP балансировщика ingress.

Способ 1 — через `kubectl` (самый простой, если есть kubeconfig до кластера):

```bash
LB=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
       -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "app.$LB.nip.io"
```

Способ 2 — через Yandex Cloud CLI (для MGKS Service `type: LoadBalancer` создаёт
сетевой балансировщик в каталоге; внешний адрес — в его `listeningAddresses`):

```bash
# найти балансировщик, созданный для ingress-контроллера, и взять внешний IP
yc lb load-balancer list --folder-id "$YC_FOLDER_ID" --format json \
  | jq -r '.[] | select(.name|test("ingress";"i"))
           | .networkLoadBalancer.listeningAddresses[]?.external.address'
```

Затем: `INGRESS_HOST = app.<тот-же-IP>.nip.io`.

Способ 3 — консоль YC: **Managed Service for Load Balancer** (или **Compute →
Load balancers**) в нужном каталоге → балансировщик, созданный для кластера
(обычно в имени содержит id кластера / namespace) → вкладка/listening address →
внешний IPv4-адрес.

Полученное `app.<IP>.nip.io` записать в CI/CD-переменную `INGRESS_HOST`.
(Если ingress-сервис ещё не `LoadBalancer` или IP не проставился — он будет пустым;
сначала убедитесь, что внешний адрес выдан.)

> Локально / без nip.io можно задать `INGRESS_HOST` равным просто `<IP>` (запросы по
> IP без virtual-host тоже пройдут через ingress), но для корректной маршрутизации по
> host лучше использовать `<host>.nip.io`.

## Проверка после развёртывания

Приложение: `http://$INGRESS_HOST/health` и `http://$INGRESS_HOST/users`.

`make app-smoke` делает ровно эти две проверки через curl.

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
`RELEASE`, `INGRESS_HOST`. Доступ к кластеру — через `KUBECONFIG`/current-context
(`KUBE_CONTEXT` пусто => helm берёт текущий контекст).

## Мониторинг (ServiceMonitor)

В шаблонах сервисов есть `ServiceMonitor` — он разворачивается **всегда** и требует
наличия Prometheus Operator (CRD `monitoring.coreos.com`) в кластере; сам
Prometheus/стек мониторинга готовится снаружи, как и кластер.

## Известные ограничения демо

- H2 in-memory: данные user-service живут только внутри пода.
- Стенд (кластер, ingress,Issuer/сертификаты при необходимости) готовится снаружи —
  pipeline их не создаёт.
