import json,sys,glob
def norm(v):
    if isinstance(v,dict):
        if '#map' in v: return {json.dumps(norm(k)):norm(x) for k,x in v['#map']}
        if '#set' in v: return sorted([norm(x) for x in v['#set']],key=json.dumps)
        if '#tup' in v: return [norm(x) for x in v['#tup']]
        if '#bigint' in v: return int(v['#bigint'])
        return {k:norm(x) for k,x in v.items() if not k.startswith('#')}
    if isinstance(v,list): return [norm(x) for x in v]
    return v
f=glob.glob(sys.argv[1]+'/out/*/*/violation1.itf.json')[0]
t=json.load(open(f))['states']
a,b=[{k:norm(v) for k,v in s.items() if not k.startswith('#')} for s in t[:2]]
for k in a:
    if a[k]!=b[k]:
        if isinstance(a[k],dict):
            for kk in a[k]:
                if a[k][kk]!=b[k].get(kk): print(f'  {k}[{kk}]: {json.dumps(a[k][kk])} -> {json.dumps(b[k][kk])}')
        else: print(f'  {k}: {json.dumps(a[k])} -> {json.dumps(b[k])}')
for k in sys.argv[2:]: print('  S0',k,'=',json.dumps(a[k]))
