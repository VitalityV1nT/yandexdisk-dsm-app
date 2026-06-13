#!/usr/bin/env bash
# build.sh — rebuild the Yandex Disk (ARM) .spk from sources, with static checks.
#
# Produces (from spk/), where <version> is the spk/INFO version:
#   spk/package/rclone                    native arm64 rclone, fetched + SHA256-verified (NOT in git)
#   spk/package.tgz                       gzip tar of spk/package/ (root-owned, *.backup excluded)
#   YandexDisk-ARM-<version>.spk          GNU tar of INFO/LICENSE/LICENSE.rclone/icons/conf/scripts/package.tgz
#   YandexDisk-ARM-<version>.spk.sha256   checksum of the .spk
#
# The .spk file name embeds the package version (e.g. YandexDisk-ARM-1.1.0.spk)
# so GitHub Release assets are self-describing and revisions never silently overwrite.
# The rclone binary and the .spk are NOT committed (released as GitHub assets); this
# script reconstructs rclone from the official release by checksum, so a fresh clone
# can build with only network access on first run (the zip is then cached locally).
#
# Functional sync against a live Yandex account is validated ONLY on a real NAS
# (test-on-nas-*.sh). Off-device checks run here and are ALL mandatory — a check
# that silently skips when a tool is missing gives a machine-dependent verdict:
# CRLF + shell syntax + shellcheck + checkbashisms, JSON control files,
# version drift across docs, rclone log-marker contract, ELF arch of rclone,
# exec bits, reproducible package re-assembly.
# Behavioural (hermetic) tests live in test/run-hermetic.sh and run separately.
set -eu

# Hermetic build environment: locale affects sort order and sed/grep/sort
# behaviour; TZ and umask leak into archive metadata. Pin them so the verdict
# and the produced bytes are machine-independent (reproducible-builds.org).
export LC_ALL=C LANG=C TZ=UTC
umask 022

# Canonical mtime for all archive entries (reproducible-builds.org convention).
# Default 0 == the historical --mtime="@${SOURCE_DATE_EPOCH}", so published checksums are unchanged.
: "${SOURCE_DATE_EPOCH:=0}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# The .spk file name embeds the package version (read from spk/INFO) so Release
# assets are self-describing and old revisions aren't silently overwritten.
VER="$(sed -n 's/^version="\(.*\)"/\1/p' spk/INFO)"
[ -n "$VER" ] || { echo "ERROR: version missing in spk/INFO" >&2; exit 1; }
SPK="YandexDisk-ARM-${VER}.spk"
PKG_TGZ="spk/package.tgz"

# rclone release pinned for this build (must stay in sync with INFO/README).
RCLONE_VERSION="v1.74.3"
RCLONE_ZIP="rclone-${RCLONE_VERSION}-linux-arm64.zip"
RCLONE_ZIP_URL="https://downloads.rclone.org/${RCLONE_VERSION}/${RCLONE_ZIP}"
RCLONE_ZIP_SHA256="8f8d47446e061f80c3256659fe8e21f56d72d96aaefe1275d088ea5eb6b42aa7"  # official zip
RCLONE_BIN_SHA256="646d2db7e701a4d41d39ed38a71f63373ab051b270ee5f0d6ae14b24cc17c923"  # extracted binary

# #!/bin/sh scripts (incl. the sourced common.sh lib) -> validate with dash.
# All package scripts are POSIX sh now (the old bash yandex-cleaner is gone).
# test/ gate scripts are POSIX sh too and are linted with the same rigour.
POSIX_SH="spk/package/common.sh spk/package/yandex-disk spk/scripts/start-stop-status spk/scripts/yandex-logger spk/scripts/preupgrade spk/scripts/postupgrade spk/package/ui/scripts/clear_log.cgi spk/package/ui/scripts/log.cgi spk/package/ui/scripts/status.cgi spk/package/ui/scripts/sync_log.cgi test/check-rclone-contract.sh test/check-version-drift.sh test/check-reproducible.sh test/check-coverage.sh test/mutate.sh test/fake-rclone test/run-hermetic.sh"

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

# CRLF gate: a CRLF-infected script (core.autocrlf on a Windows/WSL checkout +
# a path missing from .gitattributes) fails dash with a cryptic "word unexpected"
# and would ship as non-executable on the NAS. Fail fast with a clear action.
CR="$(printf '\r')"
for f in $POSIX_SH; do
    if grep -q "$CR" "$f"; then
        echo "ERROR: $f has CRLF line endings." >&2
        echo "  Fix: list the file in .gitattributes ('text eol=lf'), then re-checkout:" >&2
        echo "       git rm --cached \"$f\" >/dev/null && git checkout -- \"$f\"" >&2
        exit 1
    fi
done
echo "  ok (lf)   no CRLF in POSIX_SH scripts"

# Plain for-loop (no pipe subshell): under set -e a syntax error aborts the build.
for f in $POSIX_SH; do "$SH_POSIX" -n "$f"; echo "  ok (sh)   $f"; done

# Linters are REQUIRED: skipping when not installed makes the verdict depend on
# the machine (green locally, red in CI). shellcheck warnings are blocking.
command -v shellcheck >/dev/null 2>&1 \
    || { echo "ERROR: shellcheck is required (install: sudo apt install shellcheck)" >&2; exit 1; }
shellcheck -S warning $POSIX_SH
echo "  ok (lint) shellcheck -S warning clean"

# checkbashisms enforces the "POSIX sh only" canon: dash -n validates syntax
# but misses portability bashisms; this catches them mechanically.
command -v checkbashisms >/dev/null 2>&1 \
    || { echo "ERROR: checkbashisms is required (install: sudo apt install devscripts)" >&2; exit 1; }
checkbashisms $POSIX_SH
echo "  ok (posix) checkbashisms clean"

command -v python3 >/dev/null 2>&1 \
    || { echo "ERROR: python3 is required (validates spk/conf JSON control files)" >&2; exit 1; }
python3 -c 'import json; json.load(open("spk/conf/privilege")); print("  ok (json) spk/conf/privilege")'

# Version drift gate: INFO / CHANGELOG-ARM.md / RELEASE-INFO-ARM.txt / README
# must agree on the package and engine versions (single source of truth).
"$SH_POSIX" test/check-version-drift.sh

echo "  INFO version: $VER  ->  $SPK"

echo "==> Fetch / verify rclone (not committed to git)"
fetch_rclone

# rclone must be a native aarch64 ELF (e_machine 183) or the package is useless.
# Hard failure: an x86 binary inside an ARM package is defective, not a warning.
EM="$(od -An -tu1 -j18 -N1 spk/package/rclone 2>/dev/null | tr -d ' ')"
[ "$EM" = "183" ] \
    || { echo "ERROR: rclone e_machine=$EM, expected 183 = AArch64 (wrong-arch binary)" >&2; exit 1; }
echo "  ok (elf)  rclone e_machine=183 (AArch64)"

# Marker contract: the wrapper's counters/self-heal grep exact substrings that
# must exist inside this rclone build (else an engine bump silently breaks them).
"$SH_POSIX" test/check-rclone-contract.sh

echo "==> Exec bits"
chmod +x spk/package/yandex-disk spk/package/rclone \
         spk/scripts/start-stop-status spk/scripts/yandex-logger \
         spk/scripts/preupgrade spk/scripts/postupgrade \
         spk/package/ui/scripts/*.cgi

echo "==> Build $PKG_TGZ (root-owned, *.backup excluded, reproducible)"
# --sort/--mtime + `gzip -n` make package.tgz byte-reproducible: stable entry order,
# pinned timestamps and no gzip name/mtime header -> a stable .spk checksum.
tar -C spk/package --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner \
    --exclude='*.backup' -cf - . | gzip -n -9 > "$PKG_TGZ"

echo "==> Build $SPK (GNU tar, root-owned, reproducible)"
# Keep INFO first (DSM reads it from the stream); --mtime pins timestamps so a clean
# rebuild reproduces the same archive and the same SHA-256.
tar -C spk --format=gnu --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner -cf "$ROOT/$SPK" \
    INFO LICENSE LICENSE.rclone PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG conf scripts package.tgz

echo "==> Checksum"
sha256sum "$SPK" > "$SPK.sha256"

echo "==> Done"
ls -l "$SPK" "$PKG_TGZ" 2>/dev/null || true
cat "$SPK.sha256"
