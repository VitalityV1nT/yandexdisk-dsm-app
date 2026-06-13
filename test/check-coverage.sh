#!/bin/sh
# test/check-coverage.sh — построчное покрытие ядра пакета герметичным набором.
#
# kcov/bashcov в проект не тянем (внешний бинарь + sudo, к тому же kcov не
# инструментирует dash). Вместо них — встроенная трассировка bash: набор
# test/run-hermetic.sh прогоняется так, что КАЖДЫЙ вызов пакетного скрипта
# исполняется под bash (PATH-шим `sh`->bash), а bash через BASH_XTRACEFD пишет
# по строке на каждую исполненную команду в общий лог. Из лога собираем номера
# исполненных строк common.sh и yandex-disk, сверяем с «исполнимыми» строками
# исходника и считаем процент. POSIX-чистота при этом не страдает: она отдельно
# форсится `dash -n` + checkbashisms в build.sh, а покрытие лишь ИЗМЕРЯЕТСЯ под
# bash. Запускать ПОСЛЕ run-hermetic.sh отдельным шагом цепочки.
#
# Порог (минимальный процент по каждому файлу) — YD_COV_MIN, по умолчанию ниже.
set -eu
cd "$(dirname "$0")/.."

MIN="${YD_COV_MIN:-90}"

command -v bash >/dev/null 2>&1 \
    || { echo "FAIL(coverage): требуется bash (нужен для измерения покрытия)" >&2; exit 1; }

ROOT=$(pwd)
TARGETS="spk/package/common.sh spk/package/yandex-disk"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# PATH-шим: bare `sh` внутри run-hermetic.sh -> bash (не posix-режим), чтобы
# трассировка bash видела пакетные скрипты и sourced common.sh.
mkdir -p "$WORK/shim"
printf '#!/bin/bash\nexec /bin/bash "$@"\n' > "$WORK/shim/sh"
chmod +x "$WORK/shim/sh"

RAW="$WORK/cov.raw"
# fd 8 наследуется во все дочерние процессы и не конфликтует с fd 9 (flock в T6).
exec 8>"$RAW"

# Верх — настоящий dash (SHELLOPTS им игнорируется => без самотрассировки), а
# дочерние bash наследуют SHELLOPTS/BASH_XTRACEFD/PS4 и пишут трассу в fd 8.
# Маркер PS4 однозначно грепается: @KC@<файл>@<строка>@KC@.
set +e
PATH="$WORK/shim:$PATH" \
SHELLOPTS=xtrace BASH_XTRACEFD=8 \
PS4='@KC@${BASH_SOURCE}@${LINENO}@KC@ ' \
    /bin/sh test/run-hermetic.sh >"$WORK/suite.out" 2>&1
suite_rc=$?
set -e
if [ "$suite_rc" -ne 0 ]; then
    echo "FAIL(coverage): герметичный набор упал под bash (rc=$suite_rc):" >&2
    tail -n 20 "$WORK/suite.out" >&2
    exit 1
fi

# Номера исполненных строк по каждому целевому файлу (уникальные, по абс. пути).
grep -oE '@KC@[^@]+@[0-9]+@KC@' "$RAW" \
    | sed -E 's/@KC@(.+)@([0-9]+)@KC@/\1 \2/' > "$WORK/hits.all"

# Классификатор «исполнимых» строк. xtrace печатает по строке на каждую
# ИСПОЛНЕННУЮ простую команду, но НЕ печатает: пустые/комментарии; чисто
# структурные токены (then/do/done/fi/esac/else/{/}/;;/in); заголовки функций;
# строки-продолжения многострочной команды (предыдущая строка кончается «\»);
# закрывающую «}» с перенаправлением; метку ветки case с ПУСТЫМ телом
# («sync)» или «*) ;;»). Всё это исключаем, иначе они дали бы ложный недобор.
# Метка case с командой («*) return 0 ;;») — исполнима, остаётся в знаменателе.
exec_lines() {
    awk '
    function pat_label(str,   i,p) {
        # внутри case: метка-шаблон с пустым телом (ничего, кроме necessary «;;»)
        if (str !~ /\)[ \t]*(;;)?$/) return 0
        i=index(str,")"); p=substr(str,1,i-1)
        if (p=="" || p ~ /[$(=]/) return 0   # не шаблон: подстановка/присваивание/подоболочка
        return 1
    }
    BEGIN { depth=0; prevcont=0 }
    {
        raw=$0
        s=raw; sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s)
        thiscont=(raw ~ /\\$/)
        e=1
        if (prevcont) e=0
        else if (s=="") e=0
        else if (substr(s,1,1)=="#") e=0
        else if (s=="then"||s=="do"||s=="done"||s=="fi"||s=="esac"||s=="else" \
                 ||s=="{"||s=="}"||s==";;"||s=="in"||s=="(") e=0
        else if (s ~ /^}/) e=0
        else if (s ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{?$/) e=0
        else if (depth>0 && pat_label(s)) e=0
        if (e) print FNR
        # глубина case считается ПОСЛЕ (строка «case X in» сама исполнима/печатается)
        if (s ~ /(^|[ \t;])case[ \t]/) depth++
        if (s ~ /(^|[ \t;])esac([ \t;]|$)/ && depth>0) depth--
        prevcont=thiscont
    }' "$1"
}

rc=0
echo "== Покрытие ядра пакета герметичным набором (порог ${MIN}% на файл) =="
for f in $TARGETS; do
    abs="$ROOT/$f"
    exec_lines "$f" | sort -un > "$WORK/exec.lst"
    awk -v p="$abs" '$1==p{print $2}' "$WORK/hits.all" | sort -un > "$WORK/hit.lst"

    total=$(wc -l < "$WORK/exec.lst" | tr -d ' ')
    # covered = исполнимые строки, попавшие в трассу; uncovered = остальные.
    # Множества считаем в awk (надёжнее comm: нет завязки на коллацию sort).
    covered=$(awk 'FNR==NR{h[$1]=1;next} ($1 in h){c++} END{print c+0}' \
        "$WORK/hit.lst" "$WORK/exec.lst")
    uncovered=$(awk 'FNR==NR{h[$1]=1;next} !($1 in h){print $1}' \
        "$WORK/hit.lst" "$WORK/exec.lst")

    if [ "$total" -eq 0 ]; then pct=0; else pct=$(( covered * 100 / total )); fi
    printf '  %-26s %s/%s строк = %s%%\n' "$f" "$covered" "$total" "$pct"
    if [ -n "$uncovered" ]; then
        echo "      не покрыты (строки): $(echo "$uncovered" | tr '\n' ' ')"
    fi
    if [ "$pct" -lt "$MIN" ]; then
        echo "FAIL(coverage): $f покрыт на $pct% < ${MIN}%" >&2
        rc=1
    fi
done

[ "$rc" -eq 0 ] && echo "  ok (cov)  покрытие ядра >= ${MIN}% по каждому файлу"
exit "$rc"
