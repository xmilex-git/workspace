# Replay the file-writing tool calls of past fold sessions into ./tree, each Bash call inside a bwrap
# sandbox (read-only /, no network, own pid namespace, runtime binaries stubbed).
import json, os, re, subprocess, sys, signal
HERE = os.path.dirname(os.path.abspath(__file__))
TREE = HERE + '/tree'
ORIG = '/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2'
SHELL = sys.argv[1]
START = int(sys.argv[2]) if len(sys.argv) > 2 else 0
WR = re.compile(r'<<|sed -i|\b(cp|mv|rm|mkdir|chmod|ln|tee|patch|touch|install)\b|>(?!&)|git apply|open\(|write_text')
rows = [json.loads(l) for l in open(HERE + '/calls.jsonl')]
def fold(r):
    return 'fold-v2' in json.dumps(r['input']) or 'fold-v2' in r['cwd']
sel = [r for r in rows if fold(r) and (r['name'] != 'Bash' or WR.search(r['input'].get('command', '')))]
print('selected', len(sel), file=sys.stderr)
log = open(HERE + '/replay.log', 'a')
def mp(p):
    return TREE + p[len(ORIG):] if p.startswith(ORIG) else None
for i, r in enumerate(sel):
    if i < START:
        continue
    inp = r['input']; rc = ''; note = ''
    if r['name'] == 'Write':
        p = mp(inp.get('file_path', ''))
        if not p: continue
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'w').write(inp['content']); rc = 'W'
    elif r['name'] == 'Edit':
        p = mp(inp.get('file_path', ''))
        if not p: continue
        try:
            s = open(p).read()
            if inp['old_string'] not in s:
                rc = 'E-MISS'
            else:
                s = s.replace(inp['old_string'], inp['new_string']) if inp.get('replace_all') else s.replace(inp['old_string'], inp['new_string'], 1)
                open(p, 'w').write(s); rc = 'E'
        except FileNotFoundError:
            rc = 'E-NOFILE'
        note = inp.get('file_path', '')
    else:
        cwd = r['cwd'] or '/home/cubrid/dev/workspace'
        if cwd.startswith(ORIG):
            os.makedirs(TREE + cwd[len(ORIG):], exist_ok=True)
        elif not os.path.isdir(cwd):
            cwd = '/home/cubrid/dev/workspace'
        cmd = ['bwrap', '--ro-bind', '/', '/', '--dev', '/dev', '--proc', '/proc', '--tmpfs', '/tmp',
               '--tmpfs', '/home/cubrid/optdebug', '--tmpfs', '/home/cubrid/release',
               '--bind', TREE, ORIG, '--unshare-pid', '--unshare-net', '--unshare-ipc', '--die-with-parent',
               '--setenv', 'PATH', HERE + '/stubs:' + os.environ['PATH'], '--chdir', cwd,
               SHELL, '-c', inp.get('command', '')]
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                out, _ = p.communicate(timeout=30); rc = str(p.returncode)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL); out, _ = p.communicate(); rc = 'TMO'
            note = out[-300:].decode(errors='replace').replace('\n', ' | ')
        except Exception as e:
            rc = 'EXC'; note = str(e)
    log.write(json.dumps({'i': i, 'ts': r['ts'], 'sid': r['sid'][:8], 'name': r['name'], 'rc': rc, 'note': note, 'cmd': (inp.get('command') or inp.get('file_path') or '')[:200]}, ensure_ascii=False) + '\n')
    log.flush()
print('done', file=sys.stderr)
