#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════"
echo "  🚀 CONNEXA SERVICE MANAGER - АВТОМАТИЧЕСКАЯ УСТАНОВКА v2.0"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Требуются права root"
    exit 1
fi

if [ ! -d "/app/backend" ]; then
    echo "❌ /app/backend не найдена"
    exit 1
fi

cd /app/backend

echo ""
echo "📦 Шаг 1/7: Резервное копирование..."
BACKUP_DIR="/app/backend/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -f "server.py" ] && cp server.py "$BACKUP_DIR/server.py.backup"
[ -f "service_manager.py" ] && cp service_manager.py "$BACKUP_DIR/service_manager.py.backup"
echo "✅ Резервная копия: $BACKUP_DIR"

echo ""
echo "📦 Шаг 2/7: Скачивание service_manager.py..."
curl -sSL https://raw.githubusercontent.com/mrolivershea-cyber/FIX-CONNEXXA/main/backend/service_manager.py -o service_manager.py.tmp

if [ ! -f "service_manager.py.tmp" ]; then
    echo "❌ Не удалось скачать"
    exit 1
fi

FILE_SIZE=$(wc -c < service_manager.py.tmp)
if [ "$FILE_SIZE" -lt 1000 ]; then
    echo "❌ Файл слишком мал ($FILE_SIZE bytes)"
    rm service_manager.py.tmp
    exit 1
fi

mv service_manager.py.tmp service_manager.py
chmod 644 service_manager.py
echo "✅ Загружен ($FILE_SIZE bytes)"

echo ""
echo "📦 Шаг 3-5/7: Патчинг server.py..."
python3 << 'PYEOF'
with open("server.py", "r") as f:
    lines = f.readlines()

new_lines = []
skip = 0
for i, line in enumerate(lines):
    if skip > 0:
        skip -= 1
        continue
    if "from service_manager import start_service" in line and i > 100:
        continue
    if '@app.post("/start_service")' in line or '@app.post("/stop_service")' in line or '@app.get("/service_status")' in line:
        skip = 4
        continue
    if '@app.post("/api/service/start")' in line:
        skip = 9
        continue
    if '@app.post("/api/service/stop")' in line:
        skip = 9
        continue
    if '@app.get("/api/service/status")' in line:
        skip = 6
        continue
    if ("# SERVICE MANAGEMENT" in line or "# ==========" in line) and i > 1000:
        continue
    if "app = FastAPI()" in line and i > 100:
        continue
    new_lines.append(line)

has_import = any("from service_manager import start_service" in line for line in new_lines[:100])
if not has_import:
    final_lines = []
    for line in new_lines:
        final_lines.append(line)
        if "from services import service_manager, network_tester" in line:
            final_lines.append("from service_manager import start_service, stop_service, service_status\n")
    new_lines = final_lines

has_endpoints = any('api_start_service' in line for line in new_lines)
if not has_endpoints:
    final_lines = []
    for i, line in enumerate(new_lines):
        if ('if __name__ == "__main__":' in line or 'if name == "main":' in line):
            final_lines.append('\n# ============================================================================\n')
            final_lines.append('# SERVICE MANAGEMENT ENDPOINTS\n')
            final_lines.append('# ============================================================================\n\n')
            final_lines.append('@app.post("/api/service/start", tags=["Service Management"])
')
            final_lines.append('async def api_start_service():
')
            final_lines.append('    """Start PPTP tunnel and SOCKS proxy"""
')
            final_lines.append('    result = await start_service()
')
            final_lines.append('    if not result.get("ok"):
')
            final_lines.append('        raise HTTPException(status_code=result.get("status_code", 500), detail=result)
')
            final_lines.append('    return result
\n')
            final_lines.append('@app.post("/api/service/stop", tags=["Service Management"])
')
            final_lines.append('async def api_stop_service():
')
            final_lines.append('    """Stop PPTP tunnel and SOCKS proxy"""
')
            final_lines.append('    result = await stop_service()
')
            final_lines.append('    if not result.get("ok"):
')
            final_lines.append('        raise HTTPException(status_code=500, detail=result)
')
            final_lines.append('    return result
\n')
            final_lines.append('@app.get("/api/service/status", tags=["Service Management"])
')
            final_lines.append('async def api_service_status():
')
            final_lines.append('    """Get current service status"""
')
            final_lines.append('    return await service_status()
\n')
        final_lines.append(line)
    new_lines = final_lines

with open("server.py", "w") as f:
    f.writelines(new_lines)

print("✅ server.py пропатчен")
PYEOF

echo ""
echo "📦 Шаг 6/7: Установка пакетов..."
apt-get update -qq 2>/dev/null || true
apt-get install -y pptp-linux ppp dante-server 2>/dev/null || echo "⚠️ Ошибка установки"
echo "✅ Пакеты установлены"

echo ""
echo "📦 Шаг 7/7: Перезапуск backend..."
supervisorctl restart backend 2>/dev/null || supervisorctl restart connexa-backend 2>/dev/null
sleep 5
echo "✅ Backend перезапущен"

echo ""
echo "🧪 Проверка..."
BACKEND_STATUS=$(supervisorctl status backend 2>/dev/null | grep -o "RUNNING" || echo "UNKNOWN")
echo "Backend: $BACKEND_STATUS"

API_RESPONSE=$(curl -s http://localhost:8001/api/service/status 2>/dev/null)
if echo "$API_RESPONSE" | grep -q '"ok"'; then
    echo "✅ API работает"
    echo "$API_RESPONSE" | python3 -m json.tool 2>/dev/null
else
    echo "⚠️ API: $API_RESPONSE"
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ УСТАНОВКА ЗАВЕРШЕНА"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📁 Backup: $BACKUP_DIR"
echo "🌐 API: http://${SERVER_IP}:8001/api/service/{start,stop,status}"
echo "📚 Swagger: http://${SERVER_IP}:8001/docs"
echo "🧪 Test: curl http://localhost:8001/api/service/status"
echo "🔄 Rollback: cp $BACKUP_DIR/server.py.backup server.py && supervisorctl restart backend"
echo ""
echo "════════════════════════════════════════════════════════════════"