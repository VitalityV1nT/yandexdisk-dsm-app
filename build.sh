#!/usr/bin/env bash
# build.sh — rebuild the Yandex Disk (ARM) .spk from sources, with static checks.
#
# Produces (from spk/):
#   spk/package.tgz            gzip tar of spk/package/ (root-owned, *.backup excluded)
#   YandexDisk-ARM.spk         GNU tar of INFO/LICENSE/icons/conf/scripts/package.tgz
#   YandexDisk-ARM.spk.sha256  checksum of the .spk
#
# Functional sync against a live Yandex account is validated ONLY on a real NAS
# (test-on-nas-*.sh). Here we run the checks that work off-device: shell syntax,
# JSON control files, exec bits, ELF arch of rclone, and package re-assembly.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SPK="YandexDisk-ARM.spk"
PKG_TGZ="spk/package.tgz"

# #!/bin/sh scripts -> validate with dash (catches accidental bashisms).
# #!/bin/bash scripts -> validate with bash. Paths contain no spaces (word-split ok).
POSIX_SH="spk/package/yandex-disk spk/scripts/start-stop-status spk/package/ui/scripts/clear_log.cgi spk/package/ui/scripts/last_status.cgi spk/package/ui/scripts/log.cgi spk/package/ui/scripts/status.cgi"
BASH_SH="spk/scripts/yandex-logger spk/scripts/yandex-cleaner"

echo "==> Static checks"
SH_POSIX="$(command -v dash || command -v sh)"
# Plain for-loops (no pipe subshell): under set -e a syntax error aborts the build.
for f in $POSIX_SH; do "$SH_POSIX" -n "$f"; echo "  ok (sh)   $f"; done
for f in $BASH_SH;  do bash -n "$f";        echo "  ok (bash) $f"; done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning $POSIX_SH $BASH_SH || echo "  (shellcheck warnings above — informational)"
else
    echo "  skip: shellcheck not installed (informational)"
fi

if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json; json.load(open("spk/conf/privilege")); print("  ok (json) spk/conf/privilege")'
else
    echo "  skip: python3 not found (JSON check)"
fi

VER="$(sed -n 's/^version="\(.*\)"/\1/p' spk/INFO)"
[ -n "$VER" ] || { echo "  ERROR: version missing in spk/INFO"; exit 1; }
echo "  INFO version: $VER"

# rclone must be a native aarch64 ELF (e_machine 183) or the package is useless.
if [ -f spk/package/rclone ]; then
    EM="$(od -An -tu1 -j18 -N1 spk/package/rclone 2>/dev/null | tr -d ' ')"
    if [ "$EM" = "183" ]; then echo "  ok (elf)  rclone e_machine=183 (AArch64)";
    else echo "  WARN: rclone e_machine=$EM (expected 183 = AArch64)"; fi
fi

echo "==> Exec bits"
chmod +x spk/package/yandex-disk spk/package/rclone \
         spk/scripts/start-stop-status spk/scripts/yandex-logger spk/scripts/yandex-cleaner \
         spk/package/ui/scripts/*.cgi

echo "==> Build $PKG_TGZ (root-owned, *.backup excluded)"
tar -C spk/package --owner=0 --group=0 --exclude='*.backup' -czf "$PKG_TGZ" .

echo "==> Build $SPK (GNU tar, root-owned)"
tar -C spk --format=gnu --owner=0 --group=0 -cf "$ROOT/$SPK" \
    INFO LICENSE PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG conf scripts package.tgz

echo "==> Checksum"
sha256sum "$SPK" > "$SPK.sha256"

echo "==> Done"
ls -l "$SPK" "$PKG_TGZ" 2>/dev/null || true
cat "$SPK.sha256"
