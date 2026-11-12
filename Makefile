# Команды сборки/теста/деплоя приложения. Их же вызывает CI (см. .gitlab-ci.yml).
# Значения берутся из переменных окружения GitLab, поэтому локально можно
# переопределить:  TAG=dev IMAGE=localhost:5000/ms INGRESS_HOST=localhost make docker-build
#
#   make build            # jar'ы обоих микросервисов (Maven reactor)
#   make test            # unit-тесты
#   make docker-build     # образы в локальный/CI docker
#   make docker-push      # login + push в GitLab Container Registry
#   make app-deploy       # helm upgrade -i приложения в ns dev (через агент)
#   make app-smoke        # curl /health и /users через ingress
#   make helm-lint helm-template   # локальная проверка чарта

SHELL := /bin/sh

# Два микросервиса: каталог application/<svc> и образ <IMAGE>/ms-<svc>:<TAG>.
SERVICES := user-service client-service

IMAGE  ?= $(CI_REGISTRY_IMAGE)
TAG    ?= $(CI_COMMIT_SHA)

# Деплой через GitLab Agent (KUBE_CONTEXT = "<путь к проекту>:<имя агента>").
KUBE_CONTEXT ?= $(CI_PROJECT_PATH):otus-agent
NAMESPACE    ?= dev
RELEASE      ?= ms-dev

# Хост приложения подставляет CI (LB ingress-nginx + nip.io).
INGRESS_HOST ?=

MAVEN := mvn --batch-mode --errors -ntp

.PHONY: build test docker-build docker-push app-deploy app-smoke helm-lint helm-template

build:
	cd application && $(MAVEN) -DskipTests package

test:
	cd application && $(MAVEN) test

docker-build:
	@for s in $(SERVICES); do \
	  docker build -t "$(IMAGE)/ms-$$s:$(TAG)" "application/$$s"; \
	done

docker-push:
	@echo "login to $(CI_REGISTRY) as $(CI_DEPLOY_USER)"; \
	echo "$(CI_REGISTRY_PASSWORD)" | docker login -u "$(CI_REGISTRY_USER)" --password-stdin "$(CI_REGISTRY)"; \
	for s in $(SERVICES); do \
	  docker push "$(IMAGE)/ms-$$s:$(TAG)"; \
	done

# imagePullSecret always создаётся registry.* (обязателен) — CI подставляет
# deploy-токен (CI_DEPLOY_USER/CI_DEPLOY_PASSWORD) в registry.username/password.
app-deploy:
	helm upgrade --install $(RELEASE) helm/application -n $(NAMESPACE) \
	  --kube-context $(KUBE_CONTEXT) \
	  --set image.registry=$(IMAGE) --set image.tag=$(TAG) \
	  --set registry.server=$(CI_REGISTRY) \
	  --set registry.username=$(CI_DEPLOY_USER) \
	  --set registry.password=$(CI_DEPLOY_PASSWORD) \
	  --set ingress.host=$(INGRESS_HOST) \
	  --wait --timeout 5m

app-smoke:
	curl -fsS "http://$(INGRESS_HOST)/health"
	curl -fsS "http://$(INGRESS_HOST)/users" -o /dev/null

# --------- локальная проверка чарта (в CI не вызывается) ---------------------
helm-lint:
	helm lint helm/application

helm-template:
	helm template $(RELEASE) helm/application -n $(NAMESPACE) \
	  --set image.registry=$(IMAGE) --set image.tag=$(TAG) \
	  --set registry.server=$(CI_REGISTRY) \
	  --set registry.username=$(CI_DEPLOY_USER) \
	  --set registry.password=$(CI_DEPLOY_PASSWORD) \
	  --set ingress.host=$(or $(INGRESS_HOST),app.example)
