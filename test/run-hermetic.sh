#!/bin/sh
# test/run-hermetic.sh — поведенческий прогон пакета БЕЗ NAS и без живого rclone.
#
# Весь пакет запускается во временном каталоге через YD_*-оверрайды (см.
# spk/package/common.sh), движок подменяется шимом test/fake-rclone через
# переменную RCLONE. Покрывается самая хрупкая логика:
#   - машина состояний run_bisync (первый прогон/--resync, ошибка, авто-recover);
#   - окно счётчиков count_run_transfers (только последний прогон);
#   - формат sync.state: 7 полей + обратная совместимость с 3-полевым;
#   - ротация лога, single-run guard (flock), is_configured/resolve_remote;
#   - парсер cfg() из common.sh (таблица входов);
#   - контракт CLI-флагов _bisync, включая 6 exclude-масок (security-инвариант);
#   - clean_thumbs: выкл по умолчанию, удаляет только Thumbs.db/.DS_Store (T20);
#   - второй триггер авто-recovery «Must run --resync» (T15);
#   - is_configured при пустом dir; resolve_remote при ≥2 чужих remote (T16/T17);
#   - кэш rclone.version: запись при промахе, чтение при попадании (T14);
#   - роутинг подкоманд version/rclone/start|stop/usage (T18);
#   - граница ротации лога: ровно на лимите не ротируем (T19);
#   - провал первого --resync => error/resync-failed (T21);
#   - вывод/создание config.cfg в setup; без tty не спрашивает (T22);
#   - is_configured: conf без секции при заданном dir => not configured (T23);
#   - golden-снимки человекочитаемого вывода (test/golden/).
#
# ПОРЯДОК СЦЕНАРИЕВ ЗНАЧИМ: T3 обязан идти ДО T4/T5 — те оставляют в хвосте
# rclone.log строки-триггеры recovery, и T3 после них поймал бы ложный
# авто-resync (обёртка ищет триггер в tail -n 100 лога). Новые сценарии,
# пишущие триггер в лог, добавлять только после T5. Сценарии T14+ работают в
# изолированных YD_VAR/YD_HOME (собственный rclone.log), поэтому от порядка
# относительно T1–T13 не зависят.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

YD="$ROOT/spk/package/yandex-disk"
RCLONE="$ROOT/test/fake-rclone"
export RCLONE
chmod +x "$RCLONE"   # без exec-бита обёртка молча упала бы на системный rclone

export YD_PKG_DIR="$WORK/pkg" YD_HOME="$WORK/home" YD_VAR="$WORK/var"
export YD_RCLONE_CONF="$WORK/home/.config/rclone/rclone.conf"

T=""
fail() { echo "FAIL[$T]: $*" >&2; exit 1; }
ok()   { echo "ok: $T $*"; }
field() { cut -d'|' -f"$1" "$YD_VAR/sync.state"; }

# Чистый старт: настроенный пакет (непустой rclone.conf + локальная папка), пустой var.
clean_start() {
    rm -rf "$YD_VAR" "$YD_HOME" "$WORK/local"
    mkdir -p "$YD_HOME/.config/rclone" "$YD_HOME/.config/yandex-disk" "$YD_VAR" "$WORK/local"
    printf '[yandexdisk]\ntype = yandex\n' > "$YD_RCLONE_CONF"
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$WORK/local" \
        > "$YD_HOME/.config/yandex-disk/config.cfg"
}

# Прочитать ключ $2 через cfg() из common.sh при YD_HOME=$1 (изолированная подоболочка).
cfg_probe() {
    YD_HOME="$1" sh -c '. "$1"; shift; cfg "$1"' probe "$ROOT/spk/package/common.sh" "$2"
}

# Вывод sync_state_line из common.sh при YD_VAR=$1.
state_line_probe() {
    YD_VAR="$1" sh -c '. "$1"; sync_state_line' probe "$ROOT/spk/package/common.sh"
}

t01_first_run_resync() {
    T=T1
    clean_start
    FAKE_SENT=2 FAKE_RECV=1 sh "$YD" sync >/dev/null || fail "exit $? (ожидался 0)"
    [ "$(field 1)" = idle ] || fail "f1=$(field 1), ожидался idle"
    [ "$(field 3)" = ok ]   || fail "f3=$(field 3), ожидался ok"
    [ "$(field 4)" = 2 ]    || fail "f4=$(field 4) (sent), ожидалось 2"
    [ "$(field 5)" = 1 ]    || fail "f5=$(field 5) (received), ожидалось 1"
    [ "$(field 6)" = 0 ]    || fail "f6=$(field 6) (modified), ожидалось 0"
    [ "$(field 7)" = 0 ]    || fail "f7=$(field 7) (deleted), ожидалось 0"
    [ -f "$YD_VAR/.bisync_resynced" ] || fail "не создан маркер baseline .bisync_resynced"
    grep -q '^===== sync started ' "$YD_VAR/logs/rclone.log" \
        || fail "нет заголовка '===== sync started' в rclone.log"
    ok "первый прогон => --resync, idle/ok, счётчики 2/1/0/0, baseline создан"
}

t02_counter_window() {
    T=T2
    FAKE_MOD=3 FAKE_DEL=1 sh "$YD" sync >/dev/null || fail "exit $? (ожидался 0)"
    [ "$(field 4)" = 0 ] || fail "f4=$(field 4) — счётчик захватил маркеры прошлого прогона"
    [ "$(field 5)" = 0 ] || fail "f5=$(field 5) — счётчик захватил маркеры прошлого прогона"
    [ "$(field 6)" = 3 ] || fail "f6=$(field 6) (modified), ожидалось 3"
    [ "$(field 7)" = 1 ] || fail "f7=$(field 7) (deleted), ожидалось 1"
    ok "окно счётчиков = только последний прогон (0/0/3/1)"
}

t03_error_no_trigger() {
    T=T3
    rc=0; FAKE_RC=7 sh "$YD" sync >/dev/null 2>&1 || rc=$?
    [ "$rc" = 7 ] || fail "rc=$rc, ожидался 7"
    [ "$(field 1)" = error ]  || fail "f1=$(field 1), ожидался error"
    [ "$(field 3)" = "rc=7" ] || fail "f3=$(field 3), ожидалось rc=7"
    ok "падение без триггера => error/rc=7, авто-recover не запускался"
}

t04_auto_recover_ok() {
    T=T4
    out=$(FAKE_RC=1 FAKE_NEED_RESYNC=1 sh "$YD" sync) \
        || fail "exit $? (ожидался 0 после успешного recovery)"
    case "$out" in *"[auto-recover]"*) ;; *) fail "в stdout нет строки [auto-recover]";; esac
    [ "$(field 1)" = idle ] || fail "f1=$(field 1), ожидался idle после recovery"
    [ "$(field 3)" = ok ]   || fail "f3=$(field 3), ожидался ok после recovery"
    ok "триггер в логе => авто --resync => idle/ok"
}

t05_auto_recover_fail() {
    T=T5
    rc=0; FAKE_RC=1 FAKE_NEED_RESYNC=1 FAKE_RESYNC_RC=1 sh "$YD" sync >/dev/null 2>&1 || rc=$?
    [ "$rc" = 1 ] || fail "rc=$rc, ожидался 1"
    [ "$(field 1)" = error ]  || fail "f1=$(field 1), ожидался error"
    [ "$(field 3)" = "rc=1" ] || fail "f3=$(field 3), ожидалось rc=1"
    ok "recovery тоже падает => error/rc=1"
}

t13_bisync_cli_contract() {
    T=T13
    FAKE_ARGS_FILE="$WORK/args" sh "$YD" sync >/dev/null || fail "exit $? (ожидался 0)"
    # grep -qxF --: разделитель опций обязателен — маски, начинающиеся с '--',
    # иначе прочитались бы как опции самого grep.
    for want in --conflict-resolve path1 --inplace --max-lock 15m \
                --config --log-file --log-format date,time -v \
                --create-empty-src-dirs --resilient --recover \
                --check-sync=false --transfers --checkers \
                '#recycle/**' '@eaDir/**' '#snapshot/**' '@tmp/**' .DS_Store Thumbs.db; do
        grep -qxF -- "$want" "$WORK/args" \
            || fail "в вызове bisync нет аргумента '$want' (сломан контракт _bisync / урезан exclude)"
    done
    ok "контракт CLI _bisync: все флаги (config/log/conflict/resilient/recover/inplace/max-lock/check-sync/transfers/checkers) и 6 exclude-масок"
}

t06_single_run_guard() {
    T=T6
    command -v flock >/dev/null 2>&1 || fail "flock недоступен в тестовой среде"
    flock "$YD_VAR/sync.lock" sleep 3 &
    bg=$!
    sleep 1
    out=$(sh "$YD" sync) || fail "exit $? (ожидался 0 при skip)"
    case "$out" in *"sync already running, skip"*) ;; *) fail "нет 'sync already running, skip'";; esac
    grep -q '^===== sync skipped ' "$YD_VAR/logs/rclone.log" \
        || fail "skip не записан в rclone.log"
    wait "$bg" || true
    ok "второй параллельный sync пропущен и записан в лог"
}

t07_log_rotation() {
    T=T7
    printf '%0200d\n' 0 >> "$YD_VAR/logs/rclone.log"   # гарантированно превысить лимит
    YD_LOG_MAX_BYTES=100 sh "$YD" sync >/dev/null || fail "exit $? (ожидался 0)"
    [ -f "$YD_VAR/logs/rclone.log.1" ] || fail "нет rclone.log.1 после превышения YD_LOG_MAX_BYTES"
    ok "ротация: rclone.log -> rclone.log.1 при YD_LOG_MAX_BYTES=100"
}

t08_not_configured() {
    T=T8
    h="$WORK/t8home"
    mkdir -p "$h/.config/rclone"
    : > "$h/.config/rclone/rclone.conf"   # без секций
    rc=0
    out=$(YD_HOME="$h" YD_VAR="$WORK/t8var" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
          sh "$YD" sync 2>&1) || rc=$?
    [ "$rc" = 1 ] || fail "rc=$rc, ожидался 1"
    case "$out" in *"not configured"*) ;; *) fail "нет понятной ошибки 'not configured'";; esac
    ok "пустой rclone.conf => 'not configured', rc=1"
}

t09_resolve_remote() {
    T=T9
    h="$WORK/t9home"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk" "$WORK/t9local"
    printf '[mydisk]\ntype = yandex\n' > "$h/.config/rclone/rclone.conf"
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$WORK/t9local" > "$h/.config/yandex-disk/config.cfg"
    out=$(YD_HOME="$h" YD_VAR="$WORK/t9var" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
          sh "$YD" status) || fail "status exit $?"
    case "$out" in *"mydisk:"*) ;; *) fail "status не подхватил единственный remote [mydisk]";; esac
    ok "единственный чужой remote (mydisk) подхвачен вместо yandexdisk"
}

t10_cfg_parser() {
    T=T10
    h="$WORK/t10home"
    mkdir -p "$h/.config/yandex-disk"
    printf 'dir="/volume1/d"\n' > "$h/.config/yandex-disk/config.cfg"
    val=$(cfg_probe "$h" dir)
    [ "$val" = "/volume1/d" ] || fail "кавычки: '$val', ожидалось /volume1/d"
    printf 'dir = /v/d # коммент\n' > "$h/.config/yandex-disk/config.cfg"
    val=$(cfg_probe "$h" dir)
    [ "$val" = "/v/d" ] || fail "пробелы + инлайн-комментарий: '$val', ожидалось /v/d"
    printf 'DIR="x"\n' > "$h/.config/yandex-disk/config.cfg"
    val=$(cfg_probe "$h" dir)
    [ "$val" = "x" ] || fail "регистронезависимость: '$val', ожидалось x"
    printf 'other=1\n' > "$h/.config/yandex-disk/config.cfg"
    rc=0; val=$(cfg_probe "$h" dir) || rc=$?
    [ "$rc" = 0 ]  || fail "отсутствующий ключ: rc=$rc, ожидался 0"
    [ -z "$val" ]  || fail "отсутствующий ключ: '$val', ожидалась пустая строка"
    ok "cfg(): кавычки, пробелы, инлайн-комментарий, регистр, отсутствующий ключ"
}

t11_state_line_3field() {
    T=T11
    v="$WORK/t11var"; mkdir -p "$v"
    printf 'idle|01.01.2026 - 00:00:00|ok\n' > "$v/sync.state"
    out=$(state_line_probe "$v")
    n=$(printf '%s\n' "$out" | wc -l)
    [ "$n" = 1 ] || fail "строк: $n, ожидалась 1"
    case "$out" in *"Файлы —"*) fail "3-полевой state не должен печатать счётчики";; esac
    ok "старый 3-полевой sync.state: одна строка, без счётчиков"
}

t12_state_line_7field() {
    T=T12
    v="$WORK/t12var"; mkdir -p "$v"
    printf 'idle|01.01.2026 - 00:00:00|ok|2|1|0|0\n' > "$v/sync.state"
    out=$(state_line_probe "$v")
    n=$(printf '%s\n' "$out" | wc -l)
    [ "$n" = 2 ] || fail "строк: $n, ожидались 2"
    line2=$(printf '%s\n' "$out" | sed -n 2p)
    case "$line2" in *"отправлено): 2"*) ;; *) fail "нет 'отправлено): 2' во 2-й строке: $line2";; esac
    case "$line2" in *"получено): 1"*)  ;; *) fail "нет 'получено): 1' во 2-й строке: $line2";; esac
    ok "7-полевой sync.state: 2 строки, счётчики разобраны"
}

# --- Дополнительное покрытие веток обёртки (T14+, изолированный YD_VAR) ------
# Каждый сценарий поднимает собственный YD_HOME/YD_VAR, поэтому не зависит от
# порядка относительно T1–T13 и не делит с ними rclone.log.

t14_version_cache() {
    T=T14
    h="$WORK/t14home"; v="$WORK/t14var"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk" "$WORK/t14local"
    printf '[yandexdisk]\ntype = yandex\n' > "$h/.config/rclone/rclone.conf"
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$WORK/t14local" > "$h/.config/yandex-disk/config.cfg"
    # Промах: породить движок и записать кэш версии.
    YD_HOME="$h" YD_VAR="$v" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
        sh "$YD" status >/dev/null || fail "status (промах кэша) exit $?"
    [ -f "$v/rclone.version" ] || fail "кэш rclone.version не записан при промахе"
    grep -q 'rclone v1.74.3-fake' "$v/rclone.version" \
        || fail "в кэше rclone.version не строка версии движка"
    # Попадание: прочитать кэш дословно, не порождая движок заново.
    printf 'CACHED-SENTINEL\n' > "$v/rclone.version"
    out=$(YD_HOME="$h" YD_VAR="$v" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
          sh "$YD" status) || fail "status (попадание кэша) exit $?"
    case "$out" in *CACHED-SENTINEL*) ;; *) fail "status не прочитал кэш rclone.version (повторный spawn?)";; esac
    ok "rclone.version: запись при промахе, чтение из кэша при попадании"
}

t15_auto_recover_alt_trigger() {
    T=T15
    h="$WORK/t15home"; v="$WORK/t15var"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk" "$WORK/t15local"
    printf '[yandexdisk]\ntype = yandex\n' > "$h/.config/rclone/rclone.conf"
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$WORK/t15local" > "$h/.config/yandex-disk/config.cfg"
    YD_HOME="$h" YD_VAR="$v" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
        sh "$YD" sync >/dev/null || fail "подготовительный sync exit $?"
    # Инкрементальный прогон падает со ВТОРОЙ фразой-триггером => авто --resync.
    out=$(YD_HOME="$h" YD_VAR="$v" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
          FAKE_RC=1 FAKE_NEED_RESYNC=1 FAKE_RESYNC_MSG='Must run --resync' \
          sh "$YD" sync) || fail "exit $? (ожидался 0 после recovery по второму триггеру)"
    case "$out" in *"[auto-recover]"*) ;; *) fail "нет [auto-recover] на триггер 'Must run --resync'";; esac
    [ "$(cut -d'|' -f1 "$v/sync.state")" = idle ] || fail "статус != idle после recovery"
    [ "$(cut -d'|' -f3 "$v/sync.state")" = ok ]   || fail "результат != ok после recovery"
    ok "второй триггер recovery 'Must run --resync' => авто --resync => idle/ok"
}

t16_configured_needs_dir() {
    T=T16
    h="$WORK/t16home"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk"
    printf '[yandexdisk]\ntype = yandex\n' > "$h/.config/rclone/rclone.conf"     # секция есть
    printf 'dir=""\nremote="yandexdisk:"\n' > "$h/.config/yandex-disk/config.cfg" # но dir пуст
    rc=0
    out=$(YD_HOME="$h" YD_VAR="$WORK/t16var" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
          sh "$YD" sync 2>&1) || rc=$?
    [ "$rc" = 1 ] || fail "rc=$rc, ожидался 1 (секция есть, но dir пуст)"
    case "$out" in *"not configured"*) ;; *) fail "нет 'not configured' при пустом dir";; esac
    ok "rclone.conf с секцией, но пустой dir => 'not configured', rc=1"
}

t17_resolve_remote_ambiguous() {
    T=T17
    h="$WORK/t17home"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk" "$WORK/t17local"
    printf '[one]\ntype = yandex\n[two]\ntype = s3\n' > "$h/.config/rclone/rclone.conf"
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$WORK/t17local" > "$h/.config/yandex-disk/config.cfg"
    out=$(YD_HOME="$h" YD_VAR="$WORK/t17var" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
          sh "$YD" status) || fail "status exit $?"
    case "$out" in
        *"'yandexdisk:'"*) ;;   # REMOTE оставлен как есть — при неоднозначности не угадываем
        *) fail "при 2 чужих remote REMOTE подменён (не должен угадывать): $out";;
    esac
    ok "≥2 чужих remote, ни один не совпал => REMOTE не подменяется"
}

t18_subcommand_routing() {
    T=T18
    out=$(sh "$YD" version) || fail "version exit $?"
    case "$out" in *"rclone v1.74.3-fake"*) ;; *) fail "version не делегировал движку: $out";; esac
    out=$(sh "$YD" rclone version) || fail "rclone passthrough exit $?"
    case "$out" in *"rclone v1.74.3-fake"*) ;; *) fail "rclone <args> не проброшен движку: $out";; esac
    out=$(sh "$YD" start) || fail "start exit $?"
    case "$out" in *"No resident daemon"*) ;; *) fail "start: нет 'No resident daemon'";; esac
    out=$(sh "$YD" stop) || fail "stop exit $?"
    case "$out" in *"No resident daemon"*) ;; *) fail "stop: нет 'No resident daemon'";; esac
    rc=0; out=$(sh "$YD" frobnicate 2>&1) || rc=$?
    [ "$rc" = 1 ] || fail "неизвестная подкоманда: rc=$rc, ожидался 1"
    case "$out" in *"Usage: yandex-disk"*) ;; *) fail "нет 'Usage:' для неизвестной подкоманды";; esac
    ok "роутинг: version/rclone -> движок, start|stop -> no-daemon, неизвестная -> usage rc=1"
}

t19_rotate_boundary() {
    T=T19
    h="$WORK/t19home"; v="$WORK/t19var"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk" "$v/logs" "$WORK/t19local"
    printf '[yandexdisk]\ntype = yandex\n' > "$h/.config/rclone/rclone.conf"
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$WORK/t19local" > "$h/.config/yandex-disk/config.cfg"
    printf '%050d' 0 > "$v/logs/rclone.log"   # ровно 50 байт (без перевода строки)
    YD_HOME="$h" YD_VAR="$v" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" YD_LOG_MAX_BYTES=50 \
        sh "$YD" sync >/dev/null || fail "sync exit $?"
    [ ! -f "$v/logs/rclone.log.1" ] \
        || fail "ротация сработала на границе (=лимит), а должна лишь при превышении (-gt)"
    ok "rotate_log: размер ровно на лимите => НЕ ротируем"
}

t20_clean_thumbs() {
    T=T20
    h="$WORK/t20home"; v="$WORK/t20var"; loc="$WORK/t20local"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk" "$loc/@eaDir" "$v"
    printf '[yandexdisk]\ntype = yandex\n' > "$h/.config/rclone/rclone.conf"
    # По умолчанию clean_thumbs ВЫКЛ -> мусор обязан уцелеть.
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$loc" > "$h/.config/yandex-disk/config.cfg"
    : > "$loc/Thumbs.db"; : > "$loc/.DS_Store"; : > "$loc/keep.dat"; : > "$loc/@eaDir/keep"
    YD_HOME="$h" YD_VAR="$v" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
        sh "$YD" sync >/dev/null || fail "sync (clean_thumbs выкл) exit $?"
    [ -f "$loc/Thumbs.db" ] || fail "по умолчанию Thumbs.db не должен удаляться"
    [ -f "$loc/.DS_Store" ] || fail "по умолчанию .DS_Store не должен удаляться"
    # clean_thumbs=1 -> удалить ТОЛЬКО Thumbs.db/.DS_Store, @eaDir и прочее не трогать.
    printf 'dir="%s"\nremote="yandexdisk:"\nclean_thumbs=1\n' "$loc" > "$h/.config/yandex-disk/config.cfg"
    YD_HOME="$h" YD_VAR="$v" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
        sh "$YD" sync >/dev/null || fail "sync (clean_thumbs=1) exit $?"
    [ ! -f "$loc/Thumbs.db" ] || fail "clean_thumbs=1: Thumbs.db не удалён"
    [ ! -f "$loc/.DS_Store" ] || fail "clean_thumbs=1: .DS_Store не удалён"
    [ -f "$loc/keep.dat" ]    || fail "clean_thumbs удалил посторонний файл keep.dat"
    [ -f "$loc/@eaDir/keep" ] || fail "clean_thumbs тронул @eaDir (нельзя — индексатор Synology)"
    ok "clean_thumbs: выкл по умолчанию; вкл => удалены только Thumbs.db/.DS_Store, @eaDir и прочее целы"
}

t21_first_run_resync_fail() {
    T=T21
    h="$WORK/t21home"; v="$WORK/t21var"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk" "$WORK/t21local"
    printf '[yandexdisk]\ntype = yandex\n' > "$h/.config/rclone/rclone.conf"
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$WORK/t21local" > "$h/.config/yandex-disk/config.cfg"
    # Первый прогон => --resync; делаем его проваленным (нет baseline -> ветка else).
    rc=0
    YD_HOME="$h" YD_VAR="$v" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
        FAKE_RESYNC_RC=1 sh "$YD" sync >/dev/null 2>&1 || rc=$?
    [ "$rc" = 1 ] || fail "rc=$rc, ожидался 1 (провал первого --resync)"
    [ "$(cut -d'|' -f1 "$v/sync.state")" = error ]         || fail "статус != error"
    [ "$(cut -d'|' -f3 "$v/sync.state")" = resync-failed ] || fail "результат != resync-failed"
    [ ! -f "$v/.bisync_resynced" ] || fail "baseline-маркер создан при провале --resync"
    ok "первый --resync провалился => error/resync-failed, baseline не создан"
}

t22_setup_output() {
    T=T22
    h="$WORK/t22home"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk"
    # </dev/null: stdin не tty => интерактивная ветка setup пропускается.
    out=$(YD_HOME="$h" YD_VAR="$WORK/t22var" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
          sh "$YD" setup </dev/null) || fail "setup exit $?"
    case "$out" in *"rclone authorize"*) ;; *) fail "в setup нет шага авторизации rclone";; esac
    case "$out" in *"Task Scheduler"*)   ;; *) fail "в setup нет шага про Task Scheduler";; esac
    # Без tty интерактивный вопрос задавать нельзя (иначе под Планировщиком зависнет).
    case "$out" in *"Run interactive"*) fail "setup печатает интерактивный вопрос без tty";; *) ;; esac
    [ -f "$h/.config/yandex-disk/config.cfg" ] || fail "setup не создал config.cfg по умолчанию"
    ok "setup: инструкция (authorize/Task Scheduler), config.cfg по умолчанию, без tty не спрашивает интерактивно"
}

t23_configured_needs_section() {
    T=T23
    h="$WORK/t23home"
    mkdir -p "$h/.config/rclone" "$h/.config/yandex-disk" "$WORK/t23local"
    : > "$h/.config/rclone/rclone.conf"   # файл есть, но БЕЗ секции [..]
    printf 'dir="%s"\nremote="yandexdisk:"\n' "$WORK/t23local" > "$h/.config/yandex-disk/config.cfg"
    rc=0
    out=$(YD_HOME="$h" YD_VAR="$WORK/t23var" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
          sh "$YD" sync 2>&1) || rc=$?
    [ "$rc" = 1 ] || fail "rc=$rc, ожидался 1 (conf без секции, хотя dir задан)"
    case "$out" in *"not configured"*) ;; *) fail "нет 'not configured' при conf без секции";; esac
    ok "rclone.conf без секции, но dir задан => 'not configured', rc=1"
}

# --- Golden-снимки наблюдаемого контракта (test/golden/) --------------------
# Фиксируют ТОЧНЫЙ человекочитаемый вывод, который видят пользователь и UI.
# Переменные части нормализуются: путь WORK -> <WORK>, таймстемп -> <TS>.

norm() {
    sed -e "s#$WORK#<WORK>#g" \
        -e 's/[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9][0-9][0-9] - [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/<TS>/g'
}

golden_cmp() {
    diff -u "$ROOT/test/golden/$1" "$2" \
        || fail "golden '$1': контракт изменился — обнови эталон осознанно, в том же коммите, с объяснением"
    ok "вывод совпал с эталоном $1"
}

g01_status_configured() {
    T=G1
    clean_start
    sh "$YD" sync >/dev/null || fail "подготовительный sync: exit $?"
    rm -f "$YD_VAR/rclone.version"   # сбросить кэш версии перед снимком (Г-2 W7)
    sh "$YD" status | norm > "$WORK/actual"
    golden_cmp status-configured.txt "$WORK/actual"
}

g02_status_unconfigured() {
    T=G2
    h="$WORK/gUhome"
    mkdir -p "$h/.config/rclone"
    : > "$h/.config/rclone/rclone.conf"
    YD_HOME="$h" YD_VAR="$WORK/gUvar" YD_RCLONE_CONF="$h/.config/rclone/rclone.conf" \
        sh "$YD" status | norm > "$WORK/actual"
    golden_cmp status-unconfigured.txt "$WORK/actual"
}

g03_state_line_7field() {
    T=G3
    v="$WORK/g3var"; mkdir -p "$v"
    printf 'idle|01.01.2026 - 00:00:00|ok|2|1|0|0\n' > "$v/sync.state"
    { state_line_probe "$v"; echo; } | norm > "$WORK/actual"
    golden_cmp state-line-7field.txt "$WORK/actual"
}

g04_state_line_3field() {
    T=G4
    v="$WORK/g4var"; mkdir -p "$v"
    printf 'idle|01.01.2026 - 00:00:00|ok\n' > "$v/sync.state"
    { state_line_probe "$v"; echo; } | norm > "$WORK/actual"
    golden_cmp state-line-3field.txt "$WORK/actual"
}

echo "== Герметичный прогон: fake-rclone + YD_*-оверрайды (WORK=$WORK) =="
t01_first_run_resync
t02_counter_window
t03_error_no_trigger
t04_auto_recover_ok
t05_auto_recover_fail
t13_bisync_cli_contract
t06_single_run_guard
t07_log_rotation
t08_not_configured
t09_resolve_remote
t10_cfg_parser
t11_state_line_3field
t12_state_line_7field
t14_version_cache
t15_auto_recover_alt_trigger
t16_configured_needs_dir
t17_resolve_remote_ambiguous
t18_subcommand_routing
t19_rotate_boundary
t20_clean_thumbs
t21_first_run_resync_fail
t22_setup_output
t23_configured_needs_section
g01_status_configured
g02_status_unconfigured
g03_state_line_7field
g04_state_line_3field

echo "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ"
