#!/bin/bash
# test-on-nas-functional.sh — РУЧНАЯ ПРОВЕРКА работы на Synology NAS (aarch64).
# Запускать ПО SSH на самом NAS ПОСЛЕ настройки и запуска пакета.
# Рекомендуется запускать от root (или через sudo).
#
#   ./test-on-nas-functional.sh
#
# Проверяет: демон синхронизации, logger/cleaner, status, логи, и делает
# безопасный тест синхронизации (создать → синхронизировать → проверить → удалить).

PKG="/var/packages/YandexDisk"
RCLONE="/usr/local/bin/rclone";  [ -x "$RCLONE" ] || RCLONE="$PKG/target/rclone"
YD="/usr/local/bin/yandex-disk"; [ -x "$YD" ]     || YD="$PKG/target/yandex-disk"
RCLONE_CONF="$PKG/home/.config/rclone/rclone.conf"
CONFIG="$PKG/home/.config/yandex-disk/config.cfg"
LOGDIR="$PKG/var/logs"
PKG_USER="sc-yandexdisk"

PASS=0; FAIL=0; SKIP=0
ck()   { if eval "$2" >/dev/null 2>&1; then echo "✓ $1"; PASS=$((PASS+1)); else echo "✗ $1"; FAIL=$((FAIL+1)); fi; }
skip() { echo "⊘ ПРОПУЩЕНО: $1"; SKIP=$((SKIP+1)); }
info() { echo "    $*"; }

cfg() { [ -f "$CONFIG" ] && grep -Ei "^$1=" "$CONFIG" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"'; }

echo "================================================================"
echo "  Yandex Disk (ARM) — ФУНКЦИОНАЛЬНАЯ проверка на NAS"
echo "================================================================"

# 1. Процессы: демон, logger, cleaner
echo "--- 1. Запущенные процессы ---"
ck "демон синхронизации [y]andex-disk запущен" "ps -eo cmd | grep -q '[y]andex-disk'"
ck "[y]andex-logger запущен"                    "ps -eo cmd | grep -q '[y]andex-logger'"
ck "[y]andex-cleaner запущен"                   "ps -eo cmd | grep -q '[y]andex-cleaner'"

# 2. status
echo "--- 2. yandex-disk status ---"
ST=$(sudo -u "$PKG_USER" "$YD" status 2>&1)
echo "$ST" | sed 's/^/    /'
ck "status НЕ сообщает 'daemon not started'" "! echo \"$ST\" | grep -q 'daemon not started'"

# 3. Логи
echo "--- 3. Логи в $LOGDIR ---"
ck "каталог логов существует"        "[ -d '$LOGDIR' ]"
ck "status_history.log присутствует" "[ -f '$LOGDIR/status_history.log' ]"
ck "last_status.log присутствует"    "[ -f '$LOGDIR/last_status.log' ]"
[ -f "$LOGDIR/rclone.log" ] && info "rclone.log: $(wc -l < "$LOGDIR/rclone.log") строк"

# 4. Тест синхронизации (безопасный, с уникальным именем файла)
echo "--- 4. Тест синхронизации ---"
LOCAL_DIR="$(cfg dir)"
REMOTE="$(cfg remote)"; [ -n "$REMOTE" ] || REMOTE="yandexdisk:"

if [ -z "$LOCAL_DIR" ] || [ ! -d "$LOCAL_DIR" ]; then
    skip "локальная папка синхронизации не задана/не существует (dir= в config.cfg)"
elif [ ! -f "$RCLONE_CONF" ]; then
    skip "rclone remote не настроен ($RCLONE_CONF)"
else
    STAMP=$(date +%Y%m%d-%H%M%S)
    TESTNAME=".ydtest-${STAMP}.txt"
    TESTFILE="${LOCAL_DIR%/}/${TESTNAME}"
    info "локальная папка: $LOCAL_DIR"
    info "remote:          $REMOTE"
    info "тестовый файл:   $TESTNAME"

    # 4a. создаём тестовый файл локально (от имени пользователя пакета)
    sudo -u "$PKG_USER" sh -c "echo 'yandexdisk-arm test $STAMP' > '$TESTFILE'"
    ck "тестовый файл создан локально" "[ -f '$TESTFILE' ]"

    # 4b. синхронизируем (разово) и ждём
    info "запускаю разовую синхронизацию (yandex-disk sync)..."
    sudo -u "$PKG_USER" "$YD" sync >/dev/null 2>&1
    sleep 5

    # 4c. проверяем, что файл появился на удалённом Диске
    if sudo -u "$PKG_USER" "$RCLONE" --config "$RCLONE_CONF" lsf "$REMOTE" 2>/dev/null | grep -q "$TESTNAME"; then
        echo "✓ тестовый файл найден на Яндекс Диске (синхронизация ВВЕРХ работает)"; PASS=$((PASS+1))
    else
        echo "✗ тестовый файл НЕ найден на Яндекс Диске (см. $LOGDIR/rclone.log)"; FAIL=$((FAIL+1))
    fi

    # 4d. удаляем локально, синхронизируем, проверяем удаление на Диске
    sudo -u "$PKG_USER" rm -f "$TESTFILE"
    sudo -u "$PKG_USER" "$YD" sync >/dev/null 2>&1
    sleep 5
    if sudo -u "$PKG_USER" "$RCLONE" --config "$RCLONE_CONF" lsf "$REMOTE" 2>/dev/null | grep -q "$TESTNAME"; then
        echo "✗ тестовый файл всё ещё на Диске после удаления (двусторонняя синхронизация неполна)"; FAIL=$((FAIL+1))
        info "Очистите вручную: rclone --config $RCLONE_CONF delete $REMOTE$TESTNAME"
    else
        echo "✓ тестовый файл удалён и на Диске (синхронизация удаления работает)"; PASS=$((PASS+1))
    fi
fi

echo "================================================================"
echo "ИТОГ: ✓ $PASS   ✗ $FAIL   ⊘ $SKIP"
if [ "$FAIL" -eq 0 ]; then
    echo "РЕЗУЛЬТАТ: функционально пакет работает."
    [ "$SKIP" -gt 0 ] && echo "(часть проверок пропущена — настройте remote/папку и повторите)"
    exit 0
else
    echo "РЕЗУЛЬТАТ: есть проблемы — см. ✗ выше и лог $LOGDIR/rclone.log"
    exit 1
fi
