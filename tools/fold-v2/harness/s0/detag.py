# strip design-note tags from comments added by the fold (develop has none of these strings)
import re,subprocess,sys
files=subprocess.run(['git','diff','--name-only','f846c3634','--','src','cubrid'],capture_output=True,text=True).stdout.split()
drop_lines={'/* wf119: unguarded — client half now compiled into server */','/* wf119: end of former !SERVER_MODE region */',
 '/* wf119: end of former CS/SA region */','/* wf119: was #if !SERVER_MODE — client half now compiled into server */'}
subs=[(r'\s*/\* wf119(: un-gated)? \*/$',''),
      (r'\s*/\* wf119: un-gated; ws_pin is a no-op when db_on_server \*/$','\t/* ws_pin is a no-op when db_on_server */'),
      (r'\s*/\* wf119: server build uses boot_sr\.c\'s \*/$',''),
      (r'\(crash[- ]\d+( family)?(, round-\d+ (core|assert))?\) ?',''),(r' \(round-\d+ (core|assert)\)',''),(r'\(round-\d+ core: ([^)]*)\)',r'(\1)'),
      (r' ?\(wf119\)',''),(r'wf119: ',''),(r'\(wf119 tracer\)','(tracer)'),(r'wf119 milestone-0 tracer','in-process compile tracer'),
      (r' \(thread_local, D5\)',' (thread_local)'),(r'; concurrent parser creation is #123/#124 scope\.',''),]
changed=0
for f in files:
    try: s=open(f).read()
    except FileNotFoundError: continue
    out=[]
    for l in s.split('\n'):
        if l.strip() in drop_lines: changed+=1; continue
        n=l
        for a,b in subs: n=re.sub(a,b,n)
        if n!=l: changed+=1
        out.append(n)
    t='\n'.join(out)
    if t!=s: open(f,'w').write(t)
print('changed lines',changed)
