#!/bin/bash
# inductive check of IndInv split into groups run in parallel (iteration aid; the record is tla-check's single run)
# usage: indgrp.sh [GROUPS]  — prints, per group, PASS or the violated formula and the CTI step diff
R=/home/cubrid/dev/workspace; S=$R/docs/tla/CBRD-27430-B1a; tools=$R/.git_ignored_dir/tla/tools
G=${1:-7}; base=$R/.git_ignored_dir/scratch/fold-v2/b1a/indgrp/$(date +%H%M%S); mkdir -p $base
n=$(/usr/bin/grep -c -E '^  /\\ Inv[0-9]+$' $S/Handoff.tla)
for g in $(seq 1 $G); do
  d=$base/g$g; mkdir -p $d/tmp; cp $S/*.tla $d/
  for f in $d/*.tla; do $R/tools/tla/apalache-types $f; done
  sel(){ if [ -n "$LIST" ]; then echo $LIST | tr ' ' '\n' | awk -v g=$1 -v G=$G '(NR-1)%G==g-1'; else seq $1 $G $n; fi; }
  conj=$(for i in $(sel $g); do printf ' /\\ Inv%02d' $i; done)
  sed -i 's/^=\{10,\}$//' $d/HandoffInd.tla; printf 'Grp ==%s\n=============================================================================\n' "$conj" >> $d/HandoffInd.tla
  printf 'INIT IndInit\nNEXT Next\nINVARIANT Grp\n' > $d/g.cfg
  (cd $d && timeout ${TL:-3600} /usr/bin/env -u LD_LIBRARY_PATH -u JAVA_HOME -u CLASSPATH -u JAVA_TOOL_OPTIONS TMPDIR=$d/tmp JVM_ARGS=-Xmx6g \
     $tools/bin/apalache-mc check --out-dir=$d/out --config=g.cfg --cinit=CInit --length=1 HandoffInd.tla > $d/log 2>&1; echo "rc=$?" >> $d/log) &
done
wait
sel(){ if [ -n "$LIST" ]; then echo $LIST | tr ' ' '\n' | awk -v g=$1 -v G=$G '(NR-1)%G==g-1'; else seq $1 $G $n; fi; }
for g in $(seq 1 $G); do
  d=$base/g$g; echo "== g$g ($(for i in $(sel $g); do printf 'Inv%02d ' $i; done)) $(tail -1 $d/log) $(/usr/bin/grep -o 'Total time: [0-9.]* sec' $d/log)"
  v=$(ls $d/out/*/*/violation1.tla 2>/dev/null | head -1)
  if [ -n "$v" ]; then sed -n '/^InvariantViolation/,/^====/p' $v | head -25
    python3 - "$v" <<'PY'
import json,sys
t=json.load(open(sys.argv[1][:-4]+'.itf.json'))['states']
def norm(v):
    if isinstance(v,dict):
        if '#map' in v: return {json.dumps(norm(k)):norm(x) for k,x in v['#map']}
        if '#set' in v: return sorted([norm(x) for x in v['#set']],key=json.dumps)
        if '#tup' in v: return [norm(x) for x in v['#tup']]
        if '#bigint' in v: return int(v['#bigint'])
        return {k:norm(x) for k,x in v.items() if not k.startswith('#')}
    if isinstance(v,list): return [norm(x) for x in v]
    return v
a,b=[{k:norm(v) for k,v in s.items() if not k.startswith('#')} for s in t[:2]]
for k in a:
    if a[k]!=b[k]:
        if isinstance(a[k],dict):
            for kk in a[k]:
                if a[k][kk]!=b[k].get(kk): print(f'  {k}[{kk}]: {json.dumps(a[k][kk])} -> {json.dumps(b[k][kk])}')
        else: print(f'  {k}: {json.dumps(a[k])} -> {json.dumps(b[k])}')
PY
  else /usr/bin/grep -m2 -E 'rror' $d/log; fi
done
echo "base=$base"
