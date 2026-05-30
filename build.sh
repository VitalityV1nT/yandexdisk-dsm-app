#!/usr/bin/env bash
# build.sh — rebuild the Yandex Disk (ARM) .spk from sources, with static checks.
#
# Produces (from spk/), where <version> is the spk/INFO version:
#   spk/package/rclone                    native arm64 rclone, fetched + SHA256-verified (NOT in git)
#   spk/package.tgz                       gzip tar of spk/package/ (root-owned, *.backup excluded)
#   YandexDisk-ARM-<version>.spk          GNU tar of INFO/LICENSE/icons/conf/scripts/package.tgz
#   YandexDisk-ARM-<version>.spk.sha256   checksum of the .spk
#
# The .spk file name embeds the package version (e.g. YandexDisk-ARM-0.1.6.1080-14.spk)
# so GitHub Release assets are self-describing and revisions never silently overwrite.
# The rclone binary and the .spk are NOT committed (released as GitHub assets); this
# script reconstructs rclone from the official release by checksum, so a fresh clone
# can build with only network access on first run (the zip is then cached locally).
#
# Functional sync against a live Yandex account is validated ONLY on a real NAS
# (test-on-nas-*.sh). Here we run the checks that work off-device: shell syntax,
# JSON control files, exec bits, ELF arch of rclone, and package re-assembly.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# The .spk file name embeds the package version (read from spk/INFO) so Release
# assets are self-describing and old revisions aren't silently overwritten.
VER="$(sed -n 's/^version="\(.*\)"/\1/p' spk/INFO)"
[ -n "$VER" ] || { echo "ERROR: version missing in spk/INFO" >&2; exit 1; }
SPK="YandexDisk-ARM-${VER}.spk"
PKG_TGZ="spk/package.tgz"

# rclone release pinned for this build (must stay in sync with INFO/README).
RCLONE_VERSION="v1.74.2"
RCLONE_ZIP="rclone-${RCLONE_VERSION}-linux-arm64.zip"
RCLONE_ZIP_URL="https://downloads.rclone.org/${RCLONE_VERSION}/${RCLONE_ZIP}"
RCLONE_ZIP_SHA256="bc2b2eb8269b743ed7bcea869f3782cfb4931e41efa53fc8befc6dc8308b7a50"  # official zip
RCLONE_BIN_SHA256="1e87350a2c6d5dbbac7d5e8847cd95790791959fbc1151b25cb044dc64924508"  # extracted binary

# #!/bin/sh scripts (incl. the sourced common.sh lib) -> validate with dash.
# All package scripts are POSIX sh now (the old bash yandex-cleaner is gone).
POSIX_SH="spk/package/common.sh spk/package/yandex-disk spk/scripts/start-stop-status spk/scripts/yandex-logger spk/package/ui/scripts/clear_log.cgi spk/package/ui/scripts/log.cgi spk/package/ui/scripts/status.cgi spk/package/ui/scripts/sync_log.cgi"

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# Reconstruct spk/package/rclone from the official release (not tracked in git).
# No-op when the binary is already present and its checksum matches.
fetch_rclone() {
    if [ -f spk/package/rclone ] && [ "$(sha_of spk/package/rclone)" = "$RCLONE_BIN_SHA256" ]; then
        echo "  ok (bin)  spk/package/rclone present, sha256 verified"
        return 0
    fi
    echo "  fetch: reconstructing spk/package/rclone from $RCLONE_ZIP"
    mkdir -p downloads
    # Reuse a valid cached zip (canonical or the legacy short name) before downloading.
    if [ ! -f "downloads/$RCLONE_ZIP" ] || [ "$(sha_of "downloads/$RCLONE_ZIP")" != "$RCLONE_ZIP_SHA256" ]; then
        if [ -f downloads/rclone-linux-arm64.zip ] && [ "$(sha_of downloads/rclone-linux-arm64.zip)" = "$RCLONE_ZIP_SHA256" ]; then
            cp -f downloads/rclone-linux-arm64.zip "downloads/$RCLONE_ZIP"
        else
            echo "  download: $RCLONE_ZIP_URL"
            if command -v curl >/dev/null 2>&1; then curl -fsSL -o "downloads/$RCLONE_ZIP" "$RCLONE_ZIP_URL";
            elif command -v wget >/dev/null 2>&1; then wget -qO "downloads/$RCLONE_ZIP" "$RCLONE_ZIP_URL";
            else echo "  ERROR: need curl or wget to fetch rclone"; exit 1; fi
        fi
    fi
    [ "$(sha_of "downloads/$RCLONE_ZIP")" = "$RCLONE_ZIP_SHA256" ] \
        || { echo "  ERROR: $RCLONE_ZIP sha256 mismatch (expected $RCLONE_ZIP_SHA256)"; exit 1; }
    command -v unzip >/dev/null 2>&1 || { echo "  ERROR: need unzip to extract rclone"; exit 1; }
    _tmp="downloads/.rclone_extract"
    rm -rf "$_tmp"; mkdir -p "$_tmp"
    unzip -qo "downloads/$RCLONE_ZIP" -d "$_tmp"
    _bin="$(find "$_tmp" -type f -name rclone | head -1)"
    [ -n "$_bin" ] || { echo "  ERROR: rclone binary not found inside $RCLONE_ZIP"; exit 1; }
    cp -f "$_bin" spk/package/rclone
    chmod +x spk/package/rclone
    rm -rf "$_tmp"
    [ "$(sha_of spk/package/rclone)" = "$RCLONE_BIN_SHA256" ] \
        || { echo "  ERROR: extracted rclone sha256 mismatch (expected $RCLONE_BIN_SHA256)"; exit 1; }
    echo "  ok (bin)  spk/package/rclone reconstructed, sha256 verified"
}

echo "==> Static checks"
SH_POSIX="$(command -v dash || command -v sh)"
# Plain for-loop (no pipe subshell): under set -e a syntax error aborts the build.
for f in $POSIX_SH; do "$SH_POSIX" -n "$f"; echo "  ok (sh)   $f"; done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning $POSIX_SH || echo "  (shellcheck warnings above — informational)"
else
    echo "  skip: shellcheck not installed (informational)"
fi

if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json; json.load(open("spk/conf/privilege")); print("  ok (json) spk/conf/privilege")'
else
    echo "  skip: python3 not found (JSON check)"
fi

echo "  INFO version: $VER  ->  $SPK"

echo "==> Fetch / verify rclone (not committed to git)"
fetch_rclone

# rclone must be a native aarch64 ELF (e_machine 183) or the package is useless.
if [ -f spk/package/rclone ]; then
    EM="$(od -An -tu1 -j18 -N1 spk/package/rclone 2>/dev/null | tr -d ' ')"
    if [ "$EM" = "183" ]; then echo "  ok (elf)  rclone e_machine=183 (AArch64)";
    else echo "  WARN: rclone e_machine=$EM (expected 183 = AArch64)"; fi
fi

echo "==> Exec bits"
chmod +x spk/package/yandex-disk spk/package/rclone \
         spk/scripts/start-stop-status spk/scripts/yandex-logger \
         spk/package/ui/scripts/*.cgi

echo "==> Build $PKG_TGZ (root-owned, *.backup excluded, reproducible)"
# --sort/--mtime + `gzip -n` make package.tgz byte-reproducible: stable entry order,
# pinned timestamps and no gzip name/mtime header -> a stable .spk checksum.
tar -C spk/package --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --exclude='*.backup' -cf - . | gzip -n -9 > "$PKG_TGZ"

echo "==> Build $SPK (GNU tar, root-owned, reproducible)"
# Keep INFO first (DSM reads it from the stream); --mtime pins timestamps so a clean
# rebuild reproduces the same archive and the same SHA-256.
tar -C spk --format=gnu --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$ROOT/$SPK" \
    INFO LICENSE PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG conf scripts package.tgz

echo "==> Checksum"
sha256sum "$SPK" > "$SPK.sha256"

echo "==> Done"
ls -l "$SPK" "$PKG_TGZ" 2>/dev/null || true
cat "$SPK.sha256"
