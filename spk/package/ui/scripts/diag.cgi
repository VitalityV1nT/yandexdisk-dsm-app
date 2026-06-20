#!/bin/sh

echo "Content-Type: text/plain; charset=utf-8"
echo ""

# Phase 0 spike: this CGI runs as the webman CGI's euid, so delegating to the
# wrapper here reports that euid (whoami/id) and probes whether it can write the
# package config dirs — answering branch A vs B of the migration plan (§3.1).
# Reachable (in an authenticated DSM admin session) at:
#   /webman/3rdparty/YandexDisk/scripts/diag.cgi
# Thin by canon: all logic lives in `yandex-disk diag` (covered by hermetic tests).
yandex-disk diag 2>&1
