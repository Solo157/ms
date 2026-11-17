# OTUS CI/CD — приложение + выкатка через GitLab

Учебный демо-проект в **одном GitLab-проекте**: микросервисное приложение + один
GitLab CI pipeline, который **собирает и выкатывает приложение** на подготовленный
Kubernetes-стенд.

Приложение состоит из **двух сервисов**:

- `user-service` — REST-сервис на Spring Boot (`:8081`), данные H2 in-memory (без БД);
- `client-service` — REST-прокси на Spring Boot (`:8082`), ходит в user-service.

Основные технологии: **Java / Spring Boot**, сборка **Maven**, контейнеризация
**Docker**, дистрибуция образов через **GitLab Container Registry**, деплой через
**Helm** в Kubernetes (managed-кластер Yandex Cloud), вход в приложение —
**ingress-nginx** (`type: LoadBalancer`).

> Развёртывание инфраструктуры (кластер, ingress-контроллер, мониторинг) в этот
> проект НЕ входит — стенд подготавливается снаружи.

## GitLab CI/CD pipeline

Стадии: **build -> image -> deploy**.

1. `build_application` (стадия `build`, **manual**): `make build`, артефакты — jar'ы
   обоих сервисов.
2. `build_images` (стадия `image`): `make docker-build docker-push` — образы в GitLab
   Container Registry (`CI_REGISTRY` / `CI_REGISTRY_IMAGE`).
3. `deploy_application` (стадия `deploy`): получает временный kubeconfig до
   существующего кластера, `make app-deploy app-smoke` — helm-релиз приложения в
   namespace `dev` по хосту `INGRESS_HOST`, затем проверочные запросы.

## GitLab CI/CD Variables (задаваемые вручную)

- `YC_FOLDER_ID` — ID каталога Yandex Cloud (для получения credentials до готового кластера).
- `INGRESS_HOST` — внешний ingress-хост приложения (см. ниже).
- `YC_SA_KEY` (masked, типа File) — JSON-ключ сервисного аккаунта YC для
  `yc config set service-account-key`.
- `CLUSTER_NAME` (опционально) — имя готового кластера; по умолчанию задан в
  `.gitlab-ci.yml` (`otus-ms-cluster`), переопределяется при другом имени.

## INGRESS_HOST

`INGRESS_HOST` — это внешний DNS-хост, по которому приложение доступно снаружи
стенда. По факту это **внешний IP балансировщика (LoadBalancer)** ingress-контроллера,
полученный от Yandex Cloud. Значение задаётся вручную в CI/CD-переменной GitLab
`INGRESS_HOST`.

Формат значения — `app.<IP>.nip.io`, а не «голый» IP, потому что ingress
маршрутизирует запросы по HTTP-заголовку `Host`: сервису нужно имя хоста, а не
адрес. Сервис `nip.io` — wildcard-DNS, который резолвит любой `<что-угодно>.<IP>.nip.io`
в вписанный в имя IPv4-адрес, поэтому собственный DNS-зон не нужен: доменное имя
получается «бесплатно» из IP балансировщика.

## Проверка после развёртывания

`http://$INGRESS_HOST/health`

## Мониторинг

Приложение логируется и отдаёт метрики.
