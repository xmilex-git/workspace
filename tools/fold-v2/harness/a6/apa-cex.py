import sys,re,glob,os
d=sorted(glob.glob('/home/cubrid/dev/workspace/.git_ignored_dir/scratch/tla/CBRD-27430-A6-*'),key=os.path.getmtime)[-1]
f=glob.glob(d+'/**/violation.tla',recursive=True)
if not f: print('no violation'); sys.exit()
t=open(f[0]).read()
parts=re.split(r'\(\* Transition', t)
for i,p in enumerate(parts[:3]):
    print('=== part',i)
    for line in p.splitlines():
        if re.search(r'/\\ \w+ = ',line) and 'SetAsFun({ <<1, FALSE>>, <<2, FALSE>>, <<3' not in line:
            l=line.strip()
            if l.startswith('/\\ xdel') or l.startswith('/\\ xpost'): l=l[:120]
            print(l[:200])
