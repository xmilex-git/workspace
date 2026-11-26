#!/bin/bash
# syntax.sh <worktree> <file>...: optdebug -fsyntax-only and release -c -o /dev/null of every compile command of each file
W="$1"; shift
python3 -I - "$W" "$@" <<'PY'
import json,sys,subprocess,shlex,os
W=sys.argv[1]; files=[os.path.join(W,f) for f in sys.argv[2:]]
rc=0
for mode,extra in (('optdebug',' -fsyntax-only -fmax-errors=0'),('release',' -o /dev/null')):
    cc=json.load(open(f'{W}/build_preset_{mode}/compile_commands.json'))
    for e in cc:
        if e['file'] in files:
            cmd=e['command']
            if mode=='release':
                import re
                cmd=re.sub(r' -o \S+',' ',cmd)
            r=subprocess.run(cmd+extra,shell=True,cwd=e['directory'],capture_output=True,text=True)
            tgt=[t for t in cmd.split() if t.startswith('-D') and ('SERVER_MODE' in t or 'SA_MODE' in t or 'CS_MODE' in t)]
            print(mode,os.path.relpath(e['file'],W),' '.join(tgt),'rc=%d'%r.returncode)
            if r.returncode: rc=1; print(r.stderr[-3000:])
sys.exit(rc)
PY
