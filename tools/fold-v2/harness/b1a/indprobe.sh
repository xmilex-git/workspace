#!/bin/bash
# run the reachable-state check of every IndInv conjunct; print the first violated one and the tail of the trace
cd /home/cubrid/dev/workspace
timeout 3500 tools/tla/tla-check --only 'Handoff.witness-probe' --workers 12 docs/tla/CBRD-27430-B1a 2>&1 | /usr/bin/grep -E '^(PASS|FAIL) Handoff' | cut -c1-110
L=$(ls -td .git_ignored_dir/scratch/tla/CBRD-27430-B1a-* | head -1)/Handoff.witness-probe.log
v=$(/usr/bin/grep -o -E 'Invariant Inv[0-9]+ is violated' $L | head -1 | awk '{print $2}')
[ -n "$v" ] && { sed -n "/^$v ==/,/^Inv[0-9]* ==/p" docs/tla/CBRD-27430-B1a/Handoff.tla | head -12; python3 .git_ignored_dir/scratch/fold-v2/b1a/steps.py $L ${1:-tokens,s2b,b2s,dpc,published,latest} | tail -${2:-6} | cut -c1-600; }
/usr/bin/grep -m3 -E 'Error|rror:' $L | /usr/bin/grep -v 'is violated\|behavior up to' | head -3
