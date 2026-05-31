#!/bin/sh
# common.sh — shared paths and helpers for the Yandex Disk (ARM) package.
#
# SOURCED (not executed) by the yandex-disk wrapper, start-stop-status and
# yandex-logger so the package paths, the config.cfg parser and the log helpers
# live in ONE place instead of being copy-pasted across scripts. All paths honour
# YD_* env overrides (used by the off-NAS tests and manual runs).
#
# shellcheck shell=sh
# shellcheck disable=SC2034  # these vars are consumed by the scripts that source this lib

PKG_DIR="${YD_PKG_DIR:-/var/packages/YandexDisk}"
HOME_DIR="${YD_HOME:-$PKG_DIR/home}"
VAR_DIR="${YD_VAR:-$PKG_DIR/var}"
CONF_DIR="$HOME_DIR/.config/yandex-disk"
CONFIG_FILE="$CONF_DIR/config.cfg"
RCLONE_CONF="${YD_RCLONE_CONF:-$HOME_DIR/.config/rclone/rclone.conf}"
STATE_FILE="$VAR_DIR/sync.state"
LOG_DIR="$VAR_DIR/logs"
RCLONE_LOG="$LOG_DIR/rclone.log"               # real rclone bisync output (diagnosis)
HISTORY_LOG="$LOG_DIR/status_history.log"      # status history shown in the UI "История" tab
RESYNC_MARK="$VAR_DIR/.bisync_resynced"
RCLONE_VER_CACHE="$VAR_DIR/rclone.version"     # cached `rclone version` (avoid per-status spawn)
SYNC_LOCK="$VAR_DIR/sync.lock"

# Rotate a log to "<log>.1" once it grows past this size (one backup; ~2x cap).
LOG_MAX_BYTES="${YD_LOG_MAX_BYTES:-1048576}"

_now() { date "+%d.%m.%Y - %H:%M:%S"; }

# Read a key from config.cfg (tolerates inline "# comments" and surrounding spaces).
cfg() {
    [ -f "$CONFIG_FILE" ] || return 0
    grep -Ei "^[[:space:]]*$1[[:space:]]*=" "$CONFIG_FILE" 2>/dev/null | head -1 \
        | cut -d'=' -f2- \
        | sed -e 's/[[:space:]]\{1,\}#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | tr -d '"'
}

# Rotate $1 to "$1.1" once it exceeds LOG_MAX_BYTES. Keeps a single backup so the
# (future) rclone.log and the status history can't grow without bound on the 1 GB DS124.
rotate_log() {
    [ -f "$1" ] || return 0
    _sz=$(wc -c < "$1" 2>/dev/null | tr -d ' ')
    case "$_sz" in ''|*[!0-9]*) return 0 ;; esac
    [ "$_sz" -gt "$LOG_MAX_BYTES" ] && mv -f "$1" "$1.1" 2>/dev/null
    return 0
}

# One-line human summary of sync.state. Single source of truth for the wrapper's
# `status` output and the logger's history, so the format isn't duplicated.
sync_state_line() {
    if [ -f "$STATE_FILE" ]; then
        _st=$(cut -d'|' -f1 "$STATE_FILE" 2>/dev/null)
        _ts=$(cut -d'|' -f2 "$STATE_FILE" 2>/dev/null)
        _rs=$(cut -d'|' -f3 "$STATE_FILE" 2>/dev/null)
        _sent=$(cut -d'|' -f4 "$STATE_FILE" 2>/dev/null)
        _recv=$(cut -d'|' -f5 "$STATE_FILE" 2>/dev/null)
        _mod=$(cut -d'|' -f6 "$STATE_FILE" 2>/dev/null)
        _del=$(cut -d'|' -f7 "$STATE_FILE" 2>/dev/null)
        printf 'Последняя синхронизация: %s (%s/%s)' "${_ts:--}" "${_st:-?}" "${_rs:--}"
        # Old 3-field state files have no counts -> print only the first line
        # (full backward compatibility).
        if [ -n "$_sent$_recv$_mod$_del" ]; then
            printf '\n  Файлы — NAS → Yandex Disk (отправлено): %s; Yandex Disk → NAS (получено): %s; изменено: %s; удалено: %s' \
                "${_sent:-0}" "${_recv:-0}" "${_mod:-0}" "${_del:-0}"
        fi
    else
        printf 'Последняя синхронизация: ещё не выполнялась'
    fi
}
