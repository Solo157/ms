# ms

1. Подготовка
Логинимся к реестру (реестр может быть любым, в данном случае github):
echo "TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
Сборка проектов: mvn clean package

2. Создание образов и пуш в реестр
docker build -t ghcr.io/solo157/ms-client-service:latest ./client-service
docker build -t ghcr.io/solo157/ms-user-service:latest ./user-service
docker push ghcr.io/solo157/ms-user-service:latest
docker push ghcr.io/solo157/ms-client-service:latest

3. Выполить команды в VM
Создаем общую сеть для сервисов и постгреса: docker network create ms-network
Создаем вольюм для постгреса: docker volume create ms-postgres-volume
docker run -d -v ms-postgres-volume:/var/lib/postgresql/data --name postgres --network ms-network -e POSTGRES_PASSWORD=postgres -e POSTGRES_USER=postgres postgres:16
docker run --pull=always -d -p 8081:8081 --name user-service --network ms-network ghcr.io/solo157/ms-user-service:latest
docker run --pull=always -d -p 8082:8082 --name client-service --network ms-network ghcr.io/solo157/ms-client-service:latest

4. Проверить с помощью Curl:
   51.250.25.164 - публичный адрес виртуальной машины в интернете.
curl -X POST http://51.250.25.164:8081/users -H "Content-Type: application/json" -d '{"name": "John Doe", "email": "john@example.com"}'
curl http://51.250.25.164:8081/users
