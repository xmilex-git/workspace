import sys
# resolve.py <file> <mode>... : per conflict hunk in order, mode = ours|theirs|both
p=sys.argv[1]; modes=sys.argv[2:]
s=open(p).read(); out=[]; i=0; k=0
while True:
    a=s.find('<<<<<<< ',i)
    if a<0: out.append(s[i:]); break
    m=s.index('\n=======\n',a); b=s.index('\n>>>>>>> ',m); e=s.index('\n',b+1)+1
    ours=s[s.index('\n',a)+1:m+1]; theirs=s[m+9:b+1]
    mode=modes[k] if k<len(modes) else modes[-1]; k+=1
    out.append(s[i:a]); out.append({'ours':ours,'theirs':theirs,'both':ours+theirs}[mode]); i=e
open(p,'w').write(''.join(out)); print(p,k,'hunks')
