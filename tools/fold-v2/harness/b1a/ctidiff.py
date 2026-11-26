import json,sys,glob,os
d=sorted(glob.glob('/home/cubrid/dev/workspace/.git_ignored_dir/scratch/tla/CBRD-27430-B1a-*'),key=os.path.getmtime)[-1]
f=sorted(glob.glob(d+'/**/violation1.itf.json',recursive=True),key=os.path.getmtime)[-1]
t=json.load(open(f)); st=t['states']
def norm(v):
    if isinstance(v,dict):
        if '#map' in v: return {json.dumps(norm(k)):norm(x) for k,x in v['#map']}
        if '#set' in v: return sorted([norm(x) for x in v['#set']],key=json.dumps)
        if '#tup' in v: return [norm(x) for x in v['#tup']]
        if '#bigint' in v: return int(v['#bigint'])
        return {k:norm(x) for k,x in v.items() if not k.startswith('#')}
    if isinstance(v,list): return [norm(x) for x in v]
    return v
s0={k:norm(v) for k,v in st[0].items() if not k.startswith('#')}
s1={k:norm(v) for k,v in st[1].items() if not k.startswith('#')}
show=sys.argv[1].split(',') if len(sys.argv)>1 else []
for k in s0:
    if s0[k]!=s1[k]:
        if isinstance(s0[k],dict):
            for kk in s0[k]:
                if s0[k][kk]!=s1[k].get(kk): print(f'{k}[{kk}]: {json.dumps(s0[k][kk])}\n   -> {json.dumps(s1[k][kk])}')
        else: print(f'{k}: {json.dumps(s0[k])} -> {json.dumps(s1[k])}')
for k in show: print('S0',k,'=',json.dumps(s0[k]))
