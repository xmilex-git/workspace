import sys
p='src/transaction/boot_cl.c'
s=open(p).read()
def rep(old,new,cnt=1,region=None):
    global s
    if region:
        a=s.index(region[0]); b=s.index(region[1],a)
        seg=s[a:b]
        assert seg.count(old)==cnt,(old[:100],seg.count(old))
        s=s[:a]+seg.replace(old,new)+s[b:]
        return
    assert s.count(old)==cnt, (old[:120], s.count(old))
    s=s.replace(old,new)
exec(open(sys.argv[1]).read())
open(p,'w').write(s)
