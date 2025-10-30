#!/bin/bash

# Проверка существования каталога /app/backend
if [ ! -d "/app/backend" ]; then
    echo "Каталог /app/backend не существует. Установка прервана."
    exit 1
fi

cd /app/backend || exit

# Скачивание service_manager.py
echo "Скачивание service_manager.py..."
if ! curl -O https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/service_manager.py; then
    echo "Ошибка при скачивании service_manager.py."
    exit 1
fi

# Патч server.py для добавления новых эндпоинтов
echo "Патч server.py для добавления новых эндпоинтов..."

PATCH_CONTENT=$(cat <<EOF
# Импорт необходимых модулей
from fastapi import FastAPI
from service_manager import start_service, stop_service, service_status

app = FastAPI()

# Добавление новых маршрутов
@app.post("/start_service")
async def api_start_service():
    return start_service()

@app.post("/stop_service")
async def api_stop_service():
    return stop_service()

@app.get("/service_status")
async def api_service_status():
    return service_status()
EOF
)

if ! echo "$PATCH_CONTENT" >> server.py; then
    echo "Ошибка при патче server.py."
    exit 1
fi

echo "Патч успешно применен."

# Установка dante-server (опционально)
read -p "Хотите установить dante-server? (y/n): " install_dante
if [[ "$install_dante" == "y" ]]; then
    echo "Установка dante-server..."
    if ! apt-get install dante-server -y; then
        echo "Ошибка при установке dante-server."
        exit 1
    fi
    echo "dante-server успешно установлен."
fi

# Перезапуск службы через supervisorctl
echo "Перезапуск службы через supervisorctl..."
if ! supervisorctl restart backend_service; then
    echo "Ошибка при перезапуске службы."
    exit 1
fi

echo "Служба успешно перезапущена."
echo "Установка завершена.
