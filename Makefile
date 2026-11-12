# Команды сборки/теста/деплоя приложения. Их же вызывает CI (.gitlab-ci.yml).
# Значения берутся из переменных GitLab; локально переопределяем через окружение:
#   TAG=dev IMAGE=localhost:5000/ms INGRESS_HOST=localhost make app-deploy
#
#   make build          - jar'ы обоих сервисов (Maven reactor)
#   make test           - unit-тесты
#   make docker-build   - собрать два образа локально
#   make docker-push    - login в GitLab Registry + push
#   make app-deploy     - helm upgrade -i в namespace dev через GitLab Agent
#   make app-smoke      - curl /health и /users через ingress
#   make helm-lint helm-template - локальная проверка чарта

SHELL := /bin/sh

IMAGE ?= $(CI_REGISTRY_IMAGE)
TAG   ?= $(CI_COMMIT_SHA)

KUBE_CONTEXT ?= $(CI_PROJECT_PATH):otus-agent
NAMESPACE    ?= dev
RELEASE      ?= ms-dev

# Хост приложения (LB ingress-nginx + nip.io) подставляет CI.
INGRESS_HOST ?=

MAVEN := mvn --batch-mode --errors -ntp

.PHONY: build test docker-build docker-push app-deploy app-smoke helm-lint helm-template

build:
	cd application && $(MAVEN) -DskipTests package

test:
	cd application && $(MAVEN) test

docker-build:
	docker build -t "$(IMAGE)/ms-user-service:$(TAG)" application/user-service
	docker build -t "$(IMAGE)/ms-client-service:$(TAG)" application/client-service

docker-push:
	echo "$(CI_REGISTRY_PASSWORD)" | docker login -u "$(CI_REGISTRY_USER)" --password-stdin "$(CI_REGISTRY)"
	docker push "$(IMAGE)/ms-user-service:$(TAG)"
	docker push "$(IMAGE)/ms-client-service:$(TAG)"

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

helm-lint:
	helm lint helm/application

helm-template:
	helm template $(RELEASE) helm/application -n $(NAMESPACE) \
	  --set image.registry=$(IMAGE) --set image.tag=$(TAG) \
	  --set registry.server=$(CI_REGISTRY) \
	  --set registry.username=$(CI_DEPLOY_USER) \
	  --set registry.password=$(CI_DEPLOY_PASSWORD) \
	  --set ingress.host=$(or $(INGRESS_HOST),app.example)
