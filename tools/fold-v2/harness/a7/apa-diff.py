import json,glob,os,sys
d=sorted(glob.glob('/home/cubrid/dev/workspace/.git_ignored_dir/scratch/tla/CBRD-27430-A7-*'),key=os.path.getmtime)[-1]
f=glob.glob(d+'/**/violation.itf.json',recursive=True)[0]
t=json.load(open(f)); st=t['states']
def show(v):
    return json.dumps(v,separators=(',',':'))[:400]
s0,s1=st[0],st[1]
keys=sys.argv[1].split(',') if len(sys.argv)>1 else []
for k in sorted(s0):
    if k.startswith('#'): continue
    if s0[k]!=s1.get(k) or k in keys:
        print(k,'\n  0:',show(s0[k]),'\n  1:',show(s1.get(k)))
