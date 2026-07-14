# ms

1. Подготовка
Логинимся к реестру (реестр может быть любым, в данном случае github):
echo "TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
Сборка проектов: mvn clean package

2. Создание образов и пуш в реестр (выполнить, если в реестре нет образов)
docker build -t ghcr.io/solo157/ms-client-service:latest ./client-service
docker build -t ghcr.io/solo157/ms-user-service:latest ./user-service
docker push ghcr.io/solo157/ms-user-service:latest
docker push ghcr.io/solo157/ms-client-service:latest

3. Выполнить ./script.sh на хостовой машине в корне проекта
   
4. Проверить с помощью Curl:
   51.250.108.144 - публичный адрес виртуальной машины в интернете.
curl -X POST http://51.250.108.144:8081/users -H "Content-Type: application/json" -d '{"name": "John Doe", "email": "john@example.com"}'
curl http://51.250.108.144:8081/users
