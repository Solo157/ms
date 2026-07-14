#!/bin/bash

# REMOTE_HOST - логин и IP виртуальной машины
# SSH_KEY - приватный ключ для подключения к вирт. машине
# DEPLOY_DIR - директория, куда будет копироваться docker-compose.yml
REMOTE_HOST="ubuntu@51.250.108.144"
SSH_KEY="$HOME/.ssh/my_otus_id_rsa_cicd_vms"
DEPLOY_DIR="/home/ubuntu/ms"

chmod 600 $SSH_KEY

# подключаемся к виртулальной машине
ssh -i $SSH_KEY -o IdentitiesOnly=yes $REMOTE_HOST "mkdir -p $DEPLOY_DIR"

# копируем файл DC
scp -i $SSH_KEY -o IdentitiesOnly=yes docker-compose.yml $REMOTE_HOST:$DEPLOY_DIR

# сначала останавливаем все сервисы, если есть и запускаем все сервисы
ssh -i $SSH_KEY -o IdentitiesOnly=yes $REMOTE_HOST "cd $DEPLOY_DIR && docker compose down && docker compose up -d --pull always"