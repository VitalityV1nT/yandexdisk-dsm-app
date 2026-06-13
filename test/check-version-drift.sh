#!/bin/sh
# test/check-version-drift.sh — one version, many files: fail on any drift.
#
# Package version: spk/INFO is the single source; CHANGELOG-ARM.md (first
# entry), RELEASE-INFO-ARM.txt ("Version :" line and every YandexDisk-ARM-*.spk
# reference) must match it.
# Engine version: RCLONE_VERSION in build.sh is the single source; every
# versioned rclone mention in RELEASE-INFO-ARM.txt and README.md must match.
# CHANGELOG entries and docs/test.md are frozen history — NOT checked.
set -eu
cd "$(dirname "$0")/.."

fail() { echo "FAIL(version-drift): $*" >&2; exit 1; }

VER=$(sed -n 's/^version="\(.*\)"/\1/p' spk/INFO)
[ -n "$VER" ] || fail "no version= in spk/INFO"

CHG=$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' CHANGELOG-ARM.md | head -1)
[ "$CHG" = "$VER" ] \
    || fail "CHANGELOG-ARM.md first entry is [$CHG], spk/INFO says $VER"

REL=$(sed -n 's/^Version[[:space:]]*:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' RELEASE-INFO-ARM.txt | head -1)
[ "$REL" = "$VER" ] \
    || fail "RELEASE-INFO-ARM.txt 'Version : $REL' != spk/INFO $VER"

STALE=$(grep -o 'YandexDisk-ARM-[0-9][0-9.]*\.spk' RELEASE-INFO-ARM.txt | grep -v "^YandexDisk-ARM-$VER\.spk\$" || true)
[ -z "$STALE" ] \
    || fail "stale .spk reference(s) in RELEASE-INFO-ARM.txt: $STALE (expected YandexDisk-ARM-$VER.spk)"

RCV=$(sed -n 's/^RCLONE_VERSION="\(v[0-9][0-9.]*\)".*/\1/p' build.sh)
[ -n "$RCV" ] || fail "no RCLONE_VERSION= in build.sh"

REL_RCV=$(grep -o 'rclone v[0-9][0-9.]*' RELEASE-INFO-ARM.txt | sort -u | grep -v "^rclone $RCV\$" || true)
[ -z "$REL_RCV" ] \
    || fail "RELEASE-INFO-ARM.txt mentions '$REL_RCV', build.sh pins $RCV"

MD_RCV=$(grep -o '`rclone` v[0-9][0-9.]*' README.md | sort -u | grep -v "^\`rclone\` $RCV\$" || true)
[ -z "$MD_RCV" ] \
    || fail "README.md mentions '$MD_RCV', build.sh pins $RCV"

echo "  ok (ver)  package $VER (INFO=CHANGELOG=RELEASE-INFO), engine rclone $RCV (build.sh=RELEASE-INFO=README)"
