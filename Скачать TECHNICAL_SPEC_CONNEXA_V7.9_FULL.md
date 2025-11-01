# 🧩 CONNEXA v7.9 — FULL TECHNICAL SPECIFICATION (COMPLETE)

**Цель:**  
Интегрировать патч **v7.9** в рабочую версию **v7.4.6** без поломки существующей логики.  
Добавить полноценный **Start/Stop Service**, рабочий SOCKS, корректный PPP routing и MS-CHAP-V2 авторизацию.  
Использовать старую админ-панель как базу. Все новые функции внедряются поверх, без замены рабочей базы данных и кода сервера.

---

## **A. PREPARATION (Backup & Merge)**

1. Сделать полную резервную копию:  
   - `/root/backend/`, `/etc/ppp/`, `/var/log/connexa-*`, `/var/lib/supervisor/conf.d/`, `/root/FIX-CONNEXXA/`  
   - Базу SQLite/Postgres (nodes, tests, statuses, configs)
2. Использовать стабильную базу версии **7.4.6** (backend port 8001, frontend port 3000).
3. Все патчи из **FIX-CONNEXXA-main/** применять частично — ничего не удалять из рабочей структуры.
4. Создать файл конфигурации:
   ```
   FRONTEND_PORT=3000
   BACKEND_HOST=127.0.0.1
   BACKEND_PORT=8001
   BACKEND_BASE_URL=http://127.0.0.1:8001
   ```
   Он используется и фронтендом, и бэкендом.

---

## **B. INTEGRATION (Patch 7.9 → Base 7.4.6)**

### **B.1 Backend merge**
- Использовать существующий `server.py` из 7.4.6. Не заменять его файлами из 7.9.  
- Добавить только следующие модули:
  - `pptp_tunnel_manager.py`  
  - `service_manager_geo.py`  
  - `connexa_watchdog.py` (если отсутствует)  
  - PPP scripts (`ip-up`, `ip-down`)  
- Проверить совместимость всех импортов с FastAPI/Uvicorn.

---

### **B.2 Watchdog service**
- Если в 7.4.6 есть внутренний мониторинг, расширить его функциями из 7.9:
  - Проверка порта backend (:8001)
  - Проверка активных PPP/SOCKS процессов
  - Автоматический перезапуск при падении
- Если watchdog отсутствует — создать `/usr/local/bin/connexa_watchdog.py`
- Добавить supervisor-сервис:
  ```
  [program:watchdog]
  command=python3 /usr/local/bin/connexa_watchdog.py
  autostart=true
  autorestart=true
  stdout_logfile=/var/log/connexa-watchdog.log
  stderr_logfile=/var/log/connexa-watchdog.log
  ```

---

### **B.3 PPP scripts**

#### `/etc/ppp/ip-up`
```bash
#!/bin/bash
PPP_IFACE=$1
LOCALIP=$4
REMOTEIP=$5
LOG="/var/log/ppp-up.log"

echo "$(date): [PPP-UP] Interface=$PPP_IFACE Local=$LOCALIP Remote=$REMOTEIP" >> $LOG

# Добавляем маршрут только для удалённого адреса
if [ -n "$REMOTEIP" ]; then
  ip route replace $REMOTEIP/32 dev $PPP_IFACE
  echo "$(date): ✅ Added route for $REMOTEIP via $PPP_IFACE" >> $LOG
else
  echo "$(date): ⚠️ No remote IP detected for $PPP_IFACE" >> $LOG
fi

# Логирование SOCKS-поднятия
/usr/local/bin/socks_start.sh $PPP_IFACE $LOCALIP >> $LOG 2>&1

exit 0
```

#### `/etc/ppp/ip-down`
```bash
#!/bin/bash
PPP_IFACE=$1
REMOTEIP=$5
LOG="/var/log/ppp-down.log"

echo "$(date): [PPP-DOWN] Interface=$PPP_IFACE Remote=$REMOTEIP" >> $LOG

if [ -n "$REMOTEIP" ]; then
  ip route del $REMOTEIP/32 dev $PPP_IFACE
  echo "$(date): ❌ Removed route for $REMOTEIP ($PPP_IFACE)" >> $LOG
fi

/usr/local/bin/socks_stop.sh $PPP_IFACE >> $LOG 2>&1

exit 0
```

#### **Notes**
- Не изменять `default via eth0`.  
- Все маршруты PPP создаются и удаляются только на основании `$REMOTEIP`.  
- Все логи записываются в `/var/log/ppp-up.log` и `/var/log/ppp-down.log`.

---

### **B.4 CHAP secrets generation**
- Использовать **существующие** логины и пароли из базы (`nodes`).
- Не генерировать `admin admin`.  
- Формат `/etc/ppp/chap-secrets`:
  ```
  client   *   secret   *
  ```
- Бэкэнд сам обновляет файл при старте узлов.

---

## **C. START / STOP SERVICE**

### **C.1 Frontend UI**
- Добавить в таблицу узлов две кнопки:  
  🟢 **Start Service** — запускает туннель  
  🔴 **Stop Service** — останавливает туннель  
- Кнопки отправляют запросы:
  - `POST /service/start` с JSON `{ "ids": [список ID узлов] }`
  - `POST /service/stop` с JSON `{ "ids": [список ID узлов] }`
- Показ прогресса в окне Testing.  
- Кнопка Pause/Resume (одна, с переключением состояния).

---

### **C.2 Backend logic**

#### `/service/start`
1. Получает список ID узлов.  
2. Для каждого узла:
   - Берёт IP, login, password из базы.  
   - Создаёт файл `/etc/ppp/peers/<id>`:
     ```
     pty "pptp {ip} --nolaunchpppd"
     name {login}
     remotename {ip}
     require-mppe
     ```
   - Добавляет в `/etc/ppp/chap-secrets` строку с логином и паролем.  
   - Запускает `pppd call <id>` асинхронно.  
   - После `ip-up` создаёт SOCKS-соединение, записывает PID и порт в базу.  
   - Меняет статус узла → `online`.

#### `/service/stop`
1. Завершает процессы PPPD и SOCKS по PID из базы.  
2. Удаляет временные файлы и маршруты.  
3. Меняет статус узла → `ping_ok`.

#### Ошибки
- `peer refused to authenticate` → статус `auth_failed`
- `Nexthop invalid gateway` → автоматически перезапускает маршрут
- Все ошибки логируются в `/var/log/connexa-backend.log`.

---

### **C.3 SOCKS lifecycle**
- SOCKS поднимается **после ip-up**, автоматически.  
- Порт назначается из пула, PID записывается в базу.  
- Проверка каждые 30 секунд.  
- При падении SOCKS — перезапуск.

---

### **C.4 Batch режим**
- Массовое выполнение до 50–100 узлов за один цикл.  
- Прогресс отображается в UI Testing.  
- При паузе — текущая партия ставится на ожидание.

---

## **D. FRONTEND CONFIGURATION UPDATE**

1. Конфигурация хранится в `config/connexa.env` или `config.json`:  
   ```json
   {
     "FRONTEND_PORT": 3000,
     "BACKEND_PORT": 8001,
     "BACKEND_BASE_URL": "http://127.0.0.1:8001"
   }
   ```
2. Все API-запросы читают `BACKEND_BASE_URL`.  
3. Добавить раздел “Server Info” в панели:
   - Backend URL  
   - Текущий IP сервера  
   - Рекомендуемое количество нод  
   - Порты фронтенда и бэкенда.

---

## **E. ACCEPTANCE CRITERIA**

| Параметр | Ожидаемый результат |
|-----------|----------------------|
| **Supervisor** | backend RUNNING, watchdog RUNNING >10 мин, порт :8001 слушает |
| **PPP интерфейсы** | После старта виден pppX, маршрут `$REMOTEIP/32` активен |
| **Авторизация** | Валидные узлы проходят MS-CHAP-V2, невалидные → `auth_failed` |
| **SOCKS** | SOCKS стартует после ip-up, PID/порт в БД, мониторинг каждые 30 сек |
| **Frontend** | Кнопки Start/Stop/Pause/Resume работают, отображается прогресс |
| **Порты/конфиг** | Frontend :3000, Backend :8001 (или по connexa.env) |
| **Логи** | `/var/log/connexa-backend.log`, `/var/log/connexa-watchdog.log`, `/var/log/ppp-up.log` |
| **Регрессия** | Импорт, PingLight, SpeedOK работают как в 7.4.6, ничего не сломано |

---

## **F. QUICK COMMANDS (для тестов)**

```bash
# Проверка supervisor
supervisorctl status

# Проверка портов
ss -lntp | egrep '(:3000|:8001)'

# Проверка PPP-интерфейсов
ip a | grep ppp

# Проверка маршрутов PPP
for i in $(ip -o link show | awk -F': ' '/ppp/{print $2}'); do
  echo "--- $i ---"
  ip addr show $i | grep inet
  ip route show dev $i
done

# Проверка логов PPP
tail -n 20 /var/log/ppp-up.log
tail -n 20 /var/log/ppp-down.log
```