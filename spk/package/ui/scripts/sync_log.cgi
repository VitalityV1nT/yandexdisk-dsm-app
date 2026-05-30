#!/bin/sh

echo "Content-Type: text/plain"
echo ""

LOG_FILE="/var/packages/YandexDisk/var/logs/rclone.log"

if [ -f "$LOG_FILE" ]; then
    tail -n 300 "$LOG_FILE"
else
    echo "Лог синхронизации пуст (rclone bisync ещё не запускался)."
fi
