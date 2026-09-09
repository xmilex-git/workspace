#!/usr/bin/env bash
# rst-lint.sh [-d <git-ref>] <file.rst>... — house-style sweeps for cubrid-manual RST (STYLE.md).
#   -d <ref>   lint only lines ADDED relative to <ref> (git diff -U0), so pre-existing text in the
#              tree does not count against you. Run from inside the manual clone.
# HARD checks (exit 1): versionadded/versionchanged, tab characters, retired engine names,
#   "쿼리" in ko files, British spellings in en files, inline markup directly followed by Hangul
#   (missing "\ " escape — Sphinx renders it as literal asterisks/backticks).
# SOFT checks (printed as "candidate", exit unaffected): duplicated particle after an escape
#   (":ref:`x`\에 결과에"), vague "등" on a list, hyphenated "row-by-row" inside a literal block.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
ref=""
while getopts 'd:' o; do case $o in d) ref="$OPTARG";; *) exit 2;; esac; done
shift $((OPTIND-1))
[ $# -ge 1 ] || { echo "usage: $0 [-d <git-ref>] <file.rst>..." >&2; exit 2; }

retired=$(grep -vE '^\s*(#|$)' "$here/retired-names.txt" | paste -sd'|' -)
hard=0

# emit "lineno<TAB>text" for the lines under review
lines() {
    local f="$1"
    if [ -n "$ref" ]; then
        git diff -U0 "$ref" -- "$f" | awk '
            /^@@/ { split($3, a, /[,+]/); n = a[2]; next }
            /^\+\+\+/ { next }
            /^\+/ { print n "\t" substr($0, 2); n++ }'
    else
        awk '{ print NR "\t" $0 }' "$f"
    fi
}
report() { # severity check file lineno text
    printf '%s %s %s:%s: %s\n' "$1" "[$2]" "$3" "$4" "$5"
}

for f in "$@"; do
    [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }
    lang=other
    case "$f" in */ko/*|ko/*) lang=ko;; */en/*|en/*) lang=en;; esac
    while IFS=$'\t' read -r n t; do
        [ -n "$t" ] || continue
        if printf '%s' "$t" | grep -qE '^\s*\.\. version(added|changed)::'; then report HARD versionadded "$f" "$n" "$t"; hard=1; fi
        if printf '%s' "$t" | grep -q "$(printf '\t')"; then report HARD tab "$f" "$n" "$t"; hard=1; fi
        if [ -n "$retired" ] && printf '%s' "$t" | grep -qE "$retired"; then report HARD retired-name "$f" "$n" "$t"; hard=1; fi
        if [ "$lang" = ko ]; then
            if printf '%s' "$t" | grep -q '쿼리'; then report HARD 쿼리 "$f" "$n" "$t"; hard=1; fi
            # closing ** or ` (or ``) immediately followed by Hangul without "\" — inline markup will not close
            if printf '%s' "$t" | grep -qP '(?<=[^\s*(\[{:"'"'"'])\*\*(?=[가-힣])|(?<=[^\s`(\[{:"'"'"'])`(?=[가-힣])|(?<=[^\s(\[{:"'"'"'])``(?=[가-힣])'; then
                report HARD unescaped-markup "$f" "$n" "$t"; hard=1; fi
            if printf '%s' "$t" | grep -qP '\\ ?(은|는|이|가|을|를|에|의|로|으로|와|과|도)\s+\S+?\1(?=[\s,.;)]|$)'; then
                report soft dup-particle "$f" "$n" "$t"; fi
            if printf '%s' "$t" | grep -qP '(?<=[가-힣,)\]]) 등([이의을과에도 ]|\.|$)'; then
                report soft vague-등 "$f" "$n" "$t"; fi
        fi
        if [ "$lang" = en ]; then
            if printf '%s' "$t" | grep -qiP '\b(parallelis(e|ed|es|ing)|materialis(e|ed|es|ing|ation)|optimis(e|ed|es|ing|ation)|synchronis|minimis(e|ed|es|ing)|maximis(e|ed|es|ing)|initialis(e|ed|es|ing)|serialis(e|ed|es|ing)|normalis(e|ed|es|ing)|utilis(e|ed|es|ing)|analys(e|ed|es|ing)|behaviour|colour|centre|catalogue)\b'; then
                report HARD british-spelling "$f" "$n" "$t"; hard=1; fi
        fi
        if printf '%s' "$t" | grep -qE '^\s{4,}.*\(.*row-by-row'; then report soft trace-string "$f" "$n" "$t"; fi
    done < <(lines "$f")
done
[ $hard -eq 0 ] && echo "lint: OK (hard checks)" || echo "lint: HARD failures above"
exit $hard
