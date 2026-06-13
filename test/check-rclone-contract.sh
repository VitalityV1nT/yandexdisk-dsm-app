#!/bin/sh
# test/check-rclone-contract.sh — log-marker contract between the wrapper and rclone.
#
# count_run_transfers() in spk/package/yandex-disk counts transferred files by
# grepping the bisync log for exact substrings, and the auto-recover path fires
# on two error phrases. All of them originate inside the rclone binary, so an
# engine bump that drops any substring silently breaks the sync counters or the
# self-heal. This gate greps the binary itself (grep -a — no binutils needed)
# and replaces the old hand-checked note "confirmed present in v1.74.2".
#
# Markers must stay in sync with: spk/package/yandex-disk (count_run_transfers,
# run_bisync) and test/fake-rclone.
set -eu
cd "$(dirname "$0")/.."

BIN="spk/package/rclone"
[ -f "$BIN" ] \
    || { echo "FAIL(rclone-contract): $BIN is missing — run 'bash build.sh' to fetch it" >&2; exit 1; }

rc=0
for m in 'Queue copy to Path1' 'Queue copy to Path2' 'Copied (replaced existing)' \
         'Queue delete' 'cannot find prior' 'Must run --resync'; do
    if grep -qaF -- "$m" "$BIN"; then
        echo "  ok (mark) rclone contains: $m"
    else
        echo "FAIL(rclone-contract): marker absent from rclone binary (counters/self-heal break): $m" >&2
        rc=1
    fi
done
exit "$rc"
