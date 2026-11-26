import sys,re
L=open(sys.argv[1]).read()
want=sys.argv[2].split(',') if len(sys.argv)>2 else ['tokens','jobs','published','s2b','latest']
states=re.split(r'\nState (\d+): <(\w+)',L)
prev={}
for i in range(1,len(states)-2,3):
    n,act,body=states[i],states[i+1],states[i+2]
    body=body.split('\nThe coverage')[0]
    vals={}
    for m in re.finditer(r'^/\\ (\w+) = (.*?)(?=^/\\ |\Z)',body,re.S|re.M):
        vals[m.group(1)]=' '.join(m.group(2).split())
    ch=[k for k in vals if prev.get(k)!=vals[k]]
    shown='; '.join(f"{k}={vals[k][:260]}" for k in ch if k in want)
    others=','.join(k for k in ch if k not in want)
    print(f"{n} {act}: {shown} [{others}]")
    prev.update(vals)
