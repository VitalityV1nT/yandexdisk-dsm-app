#!/bin/bash
# test-on-nas-install.sh — РУЧНАЯ ПРОВЕРКА установки на Synology NAS (aarch64).
# Запускать ПО SSH на самом NAS после установки YandexDisk-ARM.spk.
# Рекомендуется запускать от root (или через sudo).
#
#   ./test-on-nas-install.sh
#
# Каждая проверка печатает ✓/✗. Ненулевой код выхода = есть провалы.

PKG="/var/packages/YandexDisk"
RCLONE="/usr/local/bin/rclone";        [ -x "$RCLONE" ] || RCLONE="$PKG/target/rclone"
YD="/usr/local/bin/yandex-disk";       [ -x "$YD" ]     || YD="$PKG/target/yandex-disk"
RCLONE_CONF="$PKG/home/.config/rclone/rclone.conf"
CONFIG_DIR="$PKG/home/.config/yandex-disk"
PKG_USER="sc-yandexdisk"

PASS=0; FAIL=0
ck()   { if eval "$2" >/dev/null 2>&1; then echo "✓ $1"; PASS=$((PASS+1)); else echo "✗ $1"; FAIL=$((FAIL+1)); fi; }
info() { echo "    $*"; }

echo "================================================================"
echo "  Yandex Disk (ARM) — проверка УСТАНОВКИ на NAS"
echo "================================================================"

# 1. Статус пакета
echo "--- 1. synopkg status YandexDisk ---"
if command -v synopkg >/dev/null 2>&1; then
    STATUS=$(synopkg status YandexDisk 2>&1)
    info "$STATUS"
    ck "пакет YandexDisk установлен (synopkg знает о нём)" \
       "synopkg status YandexDisk 2>&1 | grep -qiE 'running|stop|status|started'"
else
    echo "✗ synopkg недоступен (это точно Synology DSM?)"; FAIL=$((FAIL+1))
fi

# 2. Нативный бинарник rclone = aarch64
echo "--- 2. Архитектура движка rclone ---"
ck "rclone присутствует ($RCLONE)" "[ -x '$RCLONE' ]"
if command -v file >/dev/null 2>&1; then
    info "file: $(file -b "$RCLONE" 2>/dev/null)"
    ck "file сообщает aarch64" "file -b '$RCLONE' | grep -qi aarch64"
else
    # Без утилиты file: читаем e_machine из ELF-заголовка (offset 18). 183 = AArch64.
    EM=$(od -An -tu1 -j18 -N1 "$RCLONE" 2>/dev/null | tr -d ' ')
    info "ELF e_machine=$EM (ожидается 183 = AArch64)"
    ck "ELF e_machine = 183 (AArch64)" "[ \"$EM\" = '183' ]"
fi
# Самая надёжная проверка: rclone реально запускается и сообщает linux/arm64
RCV=$("$RCLONE" version 2>/dev/null | head -2 | tr '\n' ' ')
info "rclone version: $RCV"
ck "rclone запускается и сообщает arm64" "\"$RCLONE\" version 2>/dev/null | grep -qi 'arm64'"

# 3. Обёртка yandex-disk и её версия (под пользователем пакета)
echo "--- 3. Обёртка yandex-disk ---"
ck "yandex-disk присутствует ($YD)" "[ -x '$YD' ]"
if id "$PKG_USER" >/dev/null 2>&1; then
    VOUT=$(sudo -u "$PKG_USER" "$YD" --version 2>&1 | head -2 | tr '\n' ' ')
    info "yandex-disk --version: $VOUT"
    ck "sudo -u $PKG_USER yandex-disk --version работает (arm64)" \
       "sudo -u '$PKG_USER' '$YD' --version 2>/dev/null | grep -qi 'arm64'"
fi

# 4. Системный пользователь пакета
echo "--- 4. Пользователь $PKG_USER ---"
info "$(id "$PKG_USER" 2>&1)"
ck "пользователь $PKG_USER существует" "id '$PKG_USER'"

# 5. Каталоги конфигурации
echo "--- 5. Конфигурация ---"
ck "каталог конфига существует: $CONFIG_DIR" "[ -d '$CONFIG_DIR' ]"
ck "config.cfg существует"                   "[ -f '$CONFIG_DIR/config.cfg' ]"
ck "rclone.conf существует (remote настроен)" "[ -f '$RCLONE_CONF' ]"
if [ -f "$RCLONE_CONF" ]; then
    info "remotes в rclone.conf: $(grep -c '^\[' "$RCLONE_CONF" 2>/dev/null)"
    ck "в rclone.conf есть хотя бы один remote" "grep -q '^\[' '$RCLONE_CONF'"
fi
if [ -f "$CONFIG_DIR/config.cfg" ]; then
    info "config.cfg: $(grep -E '^(dir|remote|interval)=' "$CONFIG_DIR/config.cfg" 2>/dev/null | tr '\n' '  ')"
fi

echo "================================================================"
echo "ИТОГ: ✓ $PASS   ✗ $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "РЕЗУЛЬТАТ: установка выглядит корректно. Запустите test-on-nas-functional.sh"
    exit 0
else
    echo "РЕЗУЛЬТАТ: есть проблемы — см. ✗ выше."
    echo "Подсказка: если не настроен remote/папка — выполните: sudo -u $PKG_USER yandex-disk setup"
    exit 1
fi
