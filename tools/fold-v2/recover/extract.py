# Dump every tool call (Bash/Write/Edit) of the fold sessions, in time order, as JSON lines.
import json, sys, glob, os
P = '/home/cubrid/.claude/projects/-home-cubrid-dev-workspace/'
ME = '3a24cd71-b960-454c-963b-585c5d30b565'
out = []
for f in glob.glob(P + '*.jsonl'):
    sid = os.path.basename(f)[:-6]
    if sid == ME:
        continue
    txt = open(f, errors='replace').read()
    if 'fold-v2' not in txt:
        continue
    for line in txt.split('\n'):
        if not line or '"tool_use"' not in line:
            continue
        try:
            o = json.loads(line)
        except Exception:
            continue
        if o.get('type') != 'assistant':
            continue
        for c in o.get('message', {}).get('content', []) or []:
            if c.get('type') == 'tool_use' and c.get('name') in ('Bash', 'Write', 'Edit'):
                out.append({'ts': o.get('timestamp', ''), 'sid': sid, 'cwd': o.get('cwd', ''), 'name': c['name'], 'id': c['id'], 'input': c['input']})
out.sort(key=lambda r: r['ts'])
with open('calls.jsonl', 'w') as w:
    for r in out:
        w.write(json.dumps(r, ensure_ascii=False) + '\n')
print(len(out))
