#!/bin/bash
# cex.sh <log>: the counterexample of a TLC log as one line per step (action + changed variables)
python3 - "$1" <<'PY'
import sys,re
t=open(sys.argv[1]).read()
states=re.split(r'\nState (\d+): ',t)
prev={}
for i in range(1,len(states),2):
    n=states[i]; body=states[i+1]
    head=body.split('\n')[0]
    cur=dict(re.findall(r'/\\ (\w+) = (.*)',body))
    diff={k:v for k,v in cur.items() if prev.get(k)!=v}
    act=re.sub(r' line (\d+).*',r'@\1',head)
    print(n,act,' '.join(f'{k}={v}' for k,v in diff.items()) if i>1 else '')
    prev=cur
PY
