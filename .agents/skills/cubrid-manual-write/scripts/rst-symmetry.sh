#!/usr/bin/env bash
# rst-symmetry.sh [-d <git-ref>] <ko.rst> <en.rst> — mechanical ko<->en structure comparison.
# Counts the structural elements that must mirror paragraph-for-paragraph (STYLE.md §8) and exits 1
# on any mismatch.
#   whole-file mode (default): ko and en counts must be equal — the gate for a page that is fully
#                              symmetric (a page you wrote or rewrote end to end).
#   -d <ref> (delta mode):     (HEAD count − count at <ref>) must be equal for ko and en — the gate for
#                              a change on a large page that already has pre-existing ko/en drift.
#                              Run inside the manual clone; paths relative to the current directory.
# Semantic comparison is a separate QA pass (VERIFY.md §6).
set -eu
ref=""
while getopts 'd:' o; do case $o in d) ref="$OPTARG";; *) exit 2;; esac; done
shift $((OPTIND-1))
[ $# -eq 2 ] || { echo "usage: $0 [-d <git-ref>] <ko.rst> <en.rst>" >&2; exit 2; }
ko="$1"; en="$2"
for f in "$ko" "$en"; do [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }; done

ELEMENTS="h1 h2 h3 pseudo-h anchors bullets numbered notes warnings code-blocks literals csv-tables refs"
count() { # name  (reads the document on stdin)
    case "$1" in
        bullets)     grep -cE '^[[:space:]]*\*   ' || true ;;
        numbered)    grep -cE '^[[:space:]]*[0-9]+\.[[:space:]]' || true ;;
        notes)       grep -cE '^[[:space:]]*\.\. note::' || true ;;
        warnings)    grep -cE '^[[:space:]]*\.\. warning::' || true ;;
        code-blocks) grep -cE '^[[:space:]]*\.\. code-block::' || true ;;
        literals)    grep -vE '^[[:space:]]*\.\. ' | grep -cE '::[[:space:]]*$' || true ;;  # "text. ::" openers
        csv-tables)  grep -cE '^[[:space:]]*\.\. csv-table::' || true ;;
        anchors)     grep -cE '^\.\. _[A-Za-z0-9_-]+:[[:space:]]*$' || true ;;
        refs)        grep -oE ':ref:`' | wc -l ;;
        h1)          grep -cE '^=+$' || true ;;
        h2)          grep -cE '^-+$' || true ;;
        h3)          grep -cE '^\^+$' || true ;;
        pseudo-h)    grep -cE '^[[:space:]]*\*\*[^*]+\*\*[[:space:]]*$' || true ;;
    esac
}
anchors_of() { grep -E '^\.\. _[A-Za-z0-9_-]+:' || true; }
base() { git show "$ref:./$1" 2>/dev/null || true; }   # empty when the file is new at <ref>

fail=0
if [ -n "$ref" ]; then
    echo "(delta mode: HEAD minus $ref)"
    printf '%-12s %8s %8s  %s\n' element "ko Δ" "en Δ" status
else
    printf '%-12s %8s %8s  %s\n' element "ko" "en" status
fi
for name in $ELEMENTS; do
    a=$(count "$name" < "$ko"); b=$(count "$name" < "$en")
    if [ -n "$ref" ]; then
        a=$(( a - $(base "$ko" | count "$name") )); b=$(( b - $(base "$en" | count "$name") ))
    fi
    if [ "$a" = "$b" ]; then s=ok; else s=MISMATCH; fail=1; fi
    printf '%-12s %8s %8s  %s\n' "$name" "$a" "$b" "$s"
done

# anchors are shared, language-independent targets: same sequence (whole file) / same additions (delta)
if [ -n "$ref" ]; then
    ak=$(comm -13 <(base "$ko" | anchors_of | sort) <(anchors_of < "$ko" | sort))
    ae=$(comm -13 <(base "$en" | anchors_of | sort) <(anchors_of < "$en" | sort))
    label="added anchors differ:"
else
    ak=$(anchors_of < "$ko"); ae=$(anchors_of < "$en"); label="anchor sequence differs:"
fi
if [ "$ak" != "$ae" ]; then echo "$label"; diff <(echo "$ak") <(echo "$ae") || true; fail=1; fi
[ $fail -eq 0 ] && echo "symmetry: OK" || echo "symmetry: MISMATCH — add to the poorer side, do not delete from the richer"
exit $fail
