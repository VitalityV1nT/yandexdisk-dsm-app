#!/bin/sh

echo "Content-Type: text/plain"
echo ""

LOG_DIR="/var/packages/YandexDisk/var/logs"
LOG_FILE="${LOG_DIR}/status_history.log"

if [ -f "$LOG_FILE" ]; then
    cat "$LOG_FILE"
else
    echo "Лог-файл не найден: $LOG_FILE"
fi