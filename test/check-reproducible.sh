#!/bin/sh
# test/check-reproducible.sh — rebuild-twice-and-compare.
#
# Воспроизводимость байт-в-байт — контракт build.sh (--sort, --mtime,
# --numeric-owner, gzip -n). Этот гейт собирает пакет дважды с чистого листа и
# сравнивает SHA256: расхождение значит, что в сборку просочилась
# недетерминированность (время, владелец, порядок файлов, локаль).
# Запускается ПОСЛЕ build.sh (отдельным шагом цепочки, не из build.sh — иначе
# рекурсия). Работает только с артефактами ТЕКУЩЕЙ версии из spk/INFO, чтобы
# не задеть отложенные артефакты других версий.
set -eu
cd "$(dirname "$0")/.."

VER=$(sed -n 's/^version="\(.*\)"/\1/p' spk/INFO)
[ -n "$VER" ] || { echo "FAIL(reproducible): no version= in spk/INFO" >&2; exit 1; }
SPK="YandexDisk-ARM-${VER}.spk"

bash build.sh >/dev/null
s1=$(sha256sum "$SPK" | cut -d' ' -f1)

rm -f "$SPK" "$SPK.sha256" spk/package.tgz
bash build.sh >/dev/null
s2=$(sha256sum "$SPK" | cut -d' ' -f1)

if [ "$s1" != "$s2" ]; then
    echo "FAIL(reproducible): сборка НЕ воспроизводима: $s1 != $s2" >&2
    echo "  В build.sh просочился источник недетерминированности (mtime/owner/порядок/локаль)." >&2
    exit 1
fi
echo "  ok (repro) сборка воспроизводима: $s1"
