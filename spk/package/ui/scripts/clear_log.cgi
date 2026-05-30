#!/bin/sh

echo "Content-Type: text/plain"
echo ""

# Clears the status history shown in the UI "Лог" tab. The real bisync log
# (rclone.log, "Синхронизация" tab) self-rotates and is left intact for diagnosis.
LOG_FILE="/var/packages/YandexDisk/var/logs/status_history.log"

: > "$LOG_FILE"

echo "OK"
