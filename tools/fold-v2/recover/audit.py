# audit.py <basename>...: every replayed call that mentions the file, with its replay rc and note tail.
import json,re,sys
WR = re.compile(r'<<|sed -i|\b(cp|mv|rm|mkdir|chmod|ln|tee|patch|touch|install)\b|>(?!&)|git apply|open\(|write_text')
calls=[json.loads(l) for l in open('calls.jsonl')]
sel=[r for r in calls if ('fold-v2' in json.dumps(r['input']) or 'fold-v2' in r['cwd']) and (r['name']!='Bash' or WR.search(r['input'].get('command','')))]
log={}
for l in open('replay.log'):
    r=json.loads(l); log[r['i']]=r
for name in sys.argv[1:]:
    print('=====', name)
    for i,c in enumerate(sel):
        full=c['input'].get('command') or c['input'].get('file_path') or ''
        if name not in full: continue
        # a write to it: python/sed/heredoc/cp/Write/Edit in the same command
        w = c['name']!='Bash' or re.search(r"sed -i|open\(|<<|\bcp\b|\bmv\b|>\s*\S*"+re.escape(name), full)
        if not w: continue
        r=log.get(i,{'rc':'SKIP','note':''})
        kinds=[]
        if c['name']!='Bash': kinds.append(c['name'])
        if re.search(r">\s*\S*"+re.escape(name)+r"\s*<<|cat\s*>\s*\S*"+re.escape(name), full): kinds.append('CREATE')
        if 'sed -i' in full: kinds.append('sed')
        if re.search(r"open\(", full): kinds.append('py')
        flag = '!!' if (r['rc'] not in ('0','W','E') or re.search('Traceback|AssertionError', r['note'])) else '  '
        print(flag, i, c['ts'][5:16], r['rc'], ','.join(kinds), '|', full[:100].replace('\n',' ⏎ '), ('|| '+r['note'][-160:]) if flag=='!!' else '')
