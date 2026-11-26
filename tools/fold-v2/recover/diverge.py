# Replayed calls that raised a Python traceback (or timed out) while the original run of the same call did not.
import json,re,glob,os
P='/home/cubrid/.claude/projects/-home-cubrid-dev-workspace/'
WR = re.compile(r'<<|sed -i|\b(cp|mv|rm|mkdir|chmod|ln|tee|patch|touch|install)\b|>(?!&)|git apply|open\(|write_text')
calls=[json.loads(l) for l in open('calls.jsonl')]
sel=[r for r in calls if ('fold-v2' in json.dumps(r['input']) or 'fold-v2' in r['cwd']) and (r['name']!='Bash' or WR.search(r['input'].get('command','')))]
need={c['id']:None for c in sel}
for sid in {c['sid'] for c in sel}:
    for line in open(P+sid+'.jsonl', errors='replace'):
        if '"tool_result"' not in line: continue
        try: o=json.loads(line)
        except Exception: continue
        m=o.get('message',{}).get('content')
        if not isinstance(m,list): continue
        for c in m:
            if c.get('type')=='tool_result' and c.get('tool_use_id') in need:
                t=c.get('content'); 
                if isinstance(t,list): t=' '.join(x.get('text','') for x in t if isinstance(x,dict))
                need[c['tool_use_id']]=str(t)
n=0
for l in open('replay.log'):
    r=json.loads(l); c=sel[r['i']]
    if c['name']!='Bash': continue
    orig=need.get(c['id']) or ''
    rtb=bool(re.search(r'Traceback|AssertionError',r['note'])) or r['rc']=='TMO'
    otb=bool(re.search(r'Traceback|AssertionError',orig))
    if rtb and not otb:
        if 'Read-only file system' in r['note']: continue
        n+=1
        print(r['i'], r['ts'][5:16], r['sid'], r['rc'], '|', c['input']['command'][:160].replace('\n',' ⏎ '), '||', r['note'][-230:]); print()
print('divergent', n)
