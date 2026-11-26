#!/bin/bash
# syn.sh <worktree> <file>... : optdebug -fsyntax-only and release -c -o /dev/null of each TU, every lib that compiles it
ws=$1; shift
for f in "$@"; do
  for mode in optdebug release; do
    python3 - "$ws" "$mode" "$f" <<'PY'
import json,sys,subprocess,shlex
ws,mode,f=sys.argv[1:]
cc=json.load(open(f'{ws}/build_preset_{mode}/compile_commands.json'))
n=0
for e in cc:
    if e['file'].endswith('/'+f):
        cmd=e['command']
        a=shlex.split(cmd)
        if '-o' in a:
            i=a.index('-o'); out=a[i+1]; del a[i:i+2]
        else: out='?'
        a += (['-fsyntax-only','-fmax-errors=0'] if mode=='optdebug' else ['-o','/dev/null'])
        r=subprocess.run(a,cwd=e['directory'],capture_output=True,text=True)
        n+=1
        tag=out.split('/')[1] if '/' in out else out
        print(f"{'OK ' if r.returncode==0 else 'ERR'} {mode} {f} [{out[:40]}]")
        if r.returncode: print(r.stderr[-3000:])
if n==0: print('NOTU',mode,f)
PY
  done
done
