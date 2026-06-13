#!/bin/sh
# test/mutate.sh — мутационное тестирование ядра пакета (идейный аналог Stryker).
#
# Зрелого мутатора для POSIX sh нет, поэтому — свой детерминированный харнесс.
# Для каждой мутации common.sh/yandex-disk прогоняется герметичный набор
# test/run-hermetic.sh и ОЖИДАЕТСЯ его падение: мутант «убит» (killed), если хоть
# одна проверка упала; «выжил» (survived), если набор остался зелёным — значит,
# в этой точке тесты ничего не проверяют. mutation score = killed / total.
#
# Операторы — безопасные посимвольные замены токенов (синтаксис не ломают):
#   флипы сравнений -eq/-ne, -gt/-le/-ge, -lt/-ge/-le, -ge/-lt, -le/-gt;
#   логические && / ||; коды возврата return/exit 0<->1;
#   плюс точечные мутации строк-КОНТРАКТОВ (CLAUDE.md): маркеры лога rclone,
#   exclude-маски, conflict-resolve path1, --check-sync=false, триггеры recovery.
# Чисто-комментарные строки пропускаются (мутация в комментарии = эквивалентный
# мутант, который выжил бы и занизил score без пользы).
#
# Детерминирован (нет случайности/времени): порядок файлов и операторов фиксирован
# => два прогона дают один список мутантов и один score. Тяжёлый (полный набор на
# каждого мутанта) — запускать ON-DEMAND / ночным заданием CI, не на каждый push.
#
# Порог (минимальный mutation score, %) — YD_MUT_MIN, по умолчанию ниже.
set -eu
cd "$(dirname "$0")/.."

MIN="${YD_MUT_MIN:-90}"
SUITE="test/run-hermetic.sh"
TARGETS="spk/package/common.sh spk/package/yandex-disk"
ALLOW="test/mutate.equiv"   # вет­тированные ЭКВИВАЛЕНТНЫЕ мутанты (исключаются)
TAB=$(printf '\t')

# Мутант в аллоулисте? Ключ — «file:line:label»; в файле допускается « # причина».
is_equiv() {
    [ -f "$ALLOW" ] || return 1
    awk -v k="$1" '
        { sub(/[ \t]*#.*$/,""); sub(/[ \t]+$/,""); if ($0==k) f=1 }
        END { exit(f?0:1) }
    ' "$ALLOW"
}

WORK=$(mktemp -d)
mangle() { printf '%s' "$1" | tr / _; }
orig_of() { printf '%s/%s.orig' "$WORK" "$(mangle "$1")"; }

for f in $TARGETS; do cp "$f" "$(orig_of "$f")"; done
restore() { for f in $TARGETS; do cp "$(orig_of "$f")" "$f"; done; }
trap 'restore; rm -rf "$WORK"' EXIT INT TERM HUP

# --- Генерация списка мутантов: file<TAB>line<TAB>search<TAB>replace<TAB>label --
MUT="$WORK/mutants.tsv"
: > "$MUT"

# Общие операторы (посимвольные флипы) по всем НЕкомментарным строкам.
gen_generic() {
    awk -v F="$1" -v T="$TAB" '
        function emit(s,r,lab){ if(index($0,s)>0) printf "%s%s%d%s%s%s%s%s%s\n", F,T,NR,T,s,T,r,T,lab }
        /^[ \t]*#/ { next }
        {
            emit(" -eq "," -ne ","cmp:eq>ne")
            emit(" -ne "," -eq ","cmp:ne>eq")
            emit(" -gt "," -le ","cmp:gt>le")
            emit(" -gt "," -ge ","cmp:gt>ge")
            emit(" -lt "," -ge ","cmp:lt>ge")
            emit(" -lt "," -le ","cmp:lt>le")
            emit(" -ge "," -lt ","cmp:ge>lt")
            emit(" -le "," -gt ","cmp:le>gt")
            emit(" && "," || ","logic:and>or")
            emit(" || "," && ","logic:or>and")
            emit("return 0","return 1","ret:0>1")
            emit("return 1","return 0","ret:1>0")
            emit("exit 0","exit 1","exit:0>1")
            emit("exit 1","exit 0","exit:1>0")
        }
    ' "$1" >> "$MUT"
}

# Точечная мутация строки-контракта: ищем ПЕРВУЮ некомментарную строку с литералом.
gen_target() { # $1=file $2=search $3=replace $4=label
    ln=$(awk -v s="$2" '/^[ \t]*#/{next} index($0,s)>0{print NR; exit}' "$1")
    [ -n "$ln" ] && printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$ln" "$2" "$3" "$4" >> "$MUT"
    return 0
}

for f in $TARGETS; do gen_generic "$f"; done

YD="spk/package/yandex-disk"
gen_target "$YD" "--conflict-resolve path1" "--conflict-resolve path2" "contract:conflict-resolve"
gen_target "$YD" "@eaDir/**"            "@eaDirZ/**"            "contract:exclude-eaDir"
gen_target "$YD" "#recycle/**"          "#recycleZ/**"         "contract:exclude-recycle"
gen_target "$YD" '"Thumbs.db"'          '"ThumbsZ.db"'         "contract:exclude-thumbs"
gen_target "$YD" "--check-sync=false"   "--check-sync=true"    "contract:check-sync"
gen_target "$YD" "Queue copy to Path2"  "Queue copy to PathZ"  "contract:marker-sent"
gen_target "$YD" "Queue copy to Path1"  "Queue copy to PathZ"  "contract:marker-recv"
gen_target "$YD" "Copied (replaced existing)" "Copied (replaced existingZ)" "contract:marker-mod"
gen_target "$YD" "Queue delete"         "Queue deleteZ"        "contract:marker-del"
gen_target "$YD" "cannot find prior"    "cannot find priorZ"   "contract:trigger-prior"
gen_target "$YD" "Must run --resync"    "Must run --resyncZ"   "contract:trigger-resync"

# --- Применение одного мутанта: пишем pristine+правку в реальный файл ----------
apply() { # $1=file $2=line $3=search $4=replace
    awk -v L="$2" -v s="$3" -v r="$4" '
        NR==L { i=index($0,s); if(i>0) $0=substr($0,1,i-1) r substr($0,i+length(s)) }
        { print }
    ' "$(orig_of "$1")" > "$1"
}

# --- Прогон ------------------------------------------------------------------
# Легенда прогресс-строки: «.» убит, «=» выжил, но вет­тирован как эквивалентный
# (исключён), «S» выжил И не в аллоулисте — настоящий пробел тестов.
total=0; killed=0; excluded=0; survivors=""
echo "== Мутационное тестирование ядра (порог score ${MIN}%) =="
printf 'мутанты ('
while IFS="$TAB" read -r F L S R LAB; do
    [ -n "${F:-}" ] || continue
    total=$((total + 1))
    restore
    apply "$F" "$L" "$S" "$R"
    if sh "$SUITE" >/dev/null 2>&1; then
        # набор остался зелёным => мутант ВЫЖИЛ
        if is_equiv "$F:$L:$LAB"; then
            excluded=$((excluded + 1)); printf '='
        else
            survivors="$survivors
  SURVIVED  $F:$L  [$LAB]  '$S' -> '$R'"
            printf 'S'
        fi
    else
        killed=$((killed + 1)); printf '.'
    fi
done < "$MUT"
printf ')\n'
restore

if [ "$total" -eq 0 ]; then
    echo "FAIL(mutation): не сгенерировано ни одного мутанта" >&2
    exit 1
fi
considered=$((total - excluded))
[ "$considered" -gt 0 ] || { echo "FAIL(mutation): все мутанты исключены — пустой знаменатель" >&2; exit 1; }
score=$(( killed * 100 / considered ))
echo "  убито $killed/$considered (исключено $excluded эквивалентных из $total) => mutation score = ${score}%"
if [ -n "$survivors" ]; then
    echo "  ВЫЖИВШИЕ вне аллоулиста (тесты их НЕ ловят):$survivors"
fi
if [ "$score" -lt "$MIN" ]; then
    echo "FAIL(mutation): score ${score}% < ${MIN}%" >&2
    exit 1
fi
echo "  ok (mut)  mutation score ${score}% >= ${MIN}%"
