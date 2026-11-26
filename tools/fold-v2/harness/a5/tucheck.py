# usage: python3 tucheck.py <worktree> <file>...  -> optdebug -fsyntax-only + release -c -o /dev/null for every entry of each file
import json, subprocess, sys, os, shlex
from concurrent.futures import ThreadPoolExecutor
ws=os.path.abspath(sys.argv[1]); files=[os.path.join(ws,f) for f in sys.argv[2:]]
jobs=[]
for preset,extra in [('optdebug',' -fsyntax-only -fmax-errors=0'),('release',None)]:
    cc=json.load(open(f'{ws}/build_preset_{preset}/compile_commands.json'))
    for e in cc:
        if e['file'] in files:
            cmd=e['command']
            if extra: cmd=cmd.replace(' -o ',' -o /dev/null -UNUSED_',1) if False else cmd
            args=shlex.split(cmd)
            # drop -o <out>
            if '-o' in args:
                i=args.index('-o'); del args[i:i+2]
            if extra: args+=extra.split()
            else: args+=['-o','/dev/null']
            jobs.append((preset,e['file'],e['directory'],args))
def run(j):
    preset,f,d,args=j
    r=subprocess.run(args,cwd=d,capture_output=True,text=True)
    tgt=[a for a in args if a.startswith('-DSERVER_MODE') or a.startswith('-DSA_MODE') or a.startswith('-DCS_MODE')]
    return preset,f,' '.join(tgt),r.returncode,r.stderr
with ThreadPoolExecutor(8) as ex:
    for preset,f,tgt,rc,err in ex.map(run,jobs):
        lines=[l for l in err.splitlines() if 'error' in l or 'warning' in l]
        print(f"{'OK ' if rc==0 and not lines else 'BAD'} {preset} {os.path.relpath(f,ws)} {tgt} rc={rc}")
        for l in lines[:15]: print('   ',l)
print('jobs',len(jobs))
