#!/bin/bash
# usage: tools/skills/check-pitfalls-drift.sh .agents/skills/<name> — every "- Rule:" sentence in PITFALLS.md must appear verbatim in another .md of the skill, and every (P<n>) referenced there must have a PITFALLS.md entry (ADR 0033)
d="$1"; rc=0
others=$(ls "$d"/*.md "$d"/*/*.md 2>/dev/null | /usr/bin/grep -v '/PITFALLS.md$')
while IFS= read -r line; do
  s="${line#- Rule: }"
  /usr/bin/grep -qF -- "$s" $others || { echo "MISSING rule text: ${s:0:80}"; rc=1; }
done < <(/usr/bin/grep '^- Rule: ' "$d/PITFALLS.md")
for p in $(cat $others | /usr/bin/grep -oE '\(P[0-9]+\)' | tr -d '()' | sort -u); do
  /usr/bin/grep -qE "^### $p —" "$d/PITFALLS.md" || { echo "NO ENTRY for $p"; rc=1; }
done
echo "rules: $(/usr/bin/grep -c '^- Rule: ' "$d/PITFALLS.md"), refs: $(cat $others | /usr/bin/grep -oE '\(P[0-9]+\)' | sort -u | wc -l), SKILL.md bytes: $(wc -c < "$d/SKILL.md")"
exit $rc
