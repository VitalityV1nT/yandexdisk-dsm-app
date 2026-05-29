#!/bin/sh

echo "Content-Type: text/plain"
echo ""

LOG_DIR="/var/packages/YandexDisk/var/logs"
LOG_FILE="${LOG_DIR}/status_history.log"
LAST_STATUS_FILE="${LOG_DIR}/last_status.log"

> "$LOG_FILE"
> "$LAST_STATUS_FILE"

echo "OK"
