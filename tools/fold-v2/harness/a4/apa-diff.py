import sys,re,glob,os
d=sorted(glob.glob('/home/cubrid/dev/workspace/.git_ignored_dir/scratch/tla/CBRD-27430-A4-*'),key=os.path.getmtime)[-1]
v=glob.glob(d+'/**/violation1.tla',recursive=True)[0]
t=open(v).read()
def st(name):
    m=re.search(name+r' ==\n(.*?)\n\n',t,re.S)
    body=m.group(1)
    out={}
    for part in re.split(r'\n\s*/\\ ',body):
        part=part.strip().lstrip('/\\ ').strip()
        k,_,val=part.partition('=')
        out[k.strip()]=' '.join(val.split())
    return out
s0=st('State0'); s1=st('State1')
for k in s0:
    if s0[k]!=s1.get(k): print(k,':',s0[k],'->',s1.get(k))
print('pc0',s0['pc'])
for k in sys.argv[1:]: print(k, s0.get(k))
print(t[t.index('InvariantViolation'):][:600])
