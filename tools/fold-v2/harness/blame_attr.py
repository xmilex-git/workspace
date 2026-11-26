#!/usr/bin/env python3
# Attribute each of cas-merge's non-merge commits to a fold stage.
# Stage PR commits (#181..#225) take their PR's stage; every later commit is attributed
# by blaming the lines it changes (or the lines around an insertion) at its parent.
import collections, re, subprocess, sys

R = '/home/cubrid/dev/cubrid-worktree/develop'
OUT = '/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2'
STAGES = ['S0', 'A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'B1', 'B2', 'B3', 'B4', 'B5']
PR_STAGE = {181: 'S0', 182: 'A1', 183: 'A2', 189: 'A4', 192: 'A6'}
for n in range(184, 189): PR_STAGE[n] = 'A3'
for n in (190, 191): PR_STAGE[n] = 'A5'
for n in (193, 194): PR_STAGE[n] = 'A7'
for n in (195, 196): PR_STAGE[n] = 'A8'
for n in range(197, 203): PR_STAGE[n] = 'B1'
for n in range(203, 210): PR_STAGE[n] = 'B2'
for n in range(210, 214): PR_STAGE[n] = 'B3'
for n in range(214, 219): PR_STAGE[n] = 'B4'
for n in range(219, 226): PR_STAGE[n] = 'B5'


def git(*a):
    return subprocess.run(['git', '-C', R, *a], check=True, capture_output=True, text=True,
                          errors='replace').stdout


rows = [l.rstrip('\n').split('\t') for l in open(f'{OUT}/raw.tsv')]
stage = {}      # full sha -> stage
how = {}
for sha, fp, kind, subj in rows:
    m = re.match(r'Merge pull request #(\d+)', subj)
    if m and int(m.group(1)) in PR_STAGE:
        stage[sha] = PR_STAGE[int(m.group(1))]
        how[sha] = 'pr'

HUNK = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@')


def blame_votes(sha):
    votes = collections.Counter()
    newfiles = []
    diff = git('diff', '-U0', '-M', f'{sha}^', sha)
    old = None
    hunks = collections.defaultdict(list)
    for line in diff.splitlines():
        if line.startswith('--- '):
            old = None if line == '--- /dev/null' else line[6:]
        elif line.startswith('+++ '):
            if old is None and line != '+++ /dev/null':
                newfiles.append(line[6:])
        elif old and (m := HUNK.match(line)):
            s, c = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
            if c > 0:
                hunks[old].append((s, s + c - 1, c))
            else:  # pure insertion after line s: blame its two neighbours, weight 1
                hunks[old].append((max(s, 1), s + 1, 0))
    for path, hs in hunks.items():
        for a, b, w in hs:
            try:
                out = git('blame', '-l', '-s', '-L', f'{a},{b}', f'{sha}^', '--', path)
            except subprocess.CalledProcessError:
                try:
                    out = git('blame', '-l', '-s', '-L', f'{a},{a}', f'{sha}^', '--', path)
                except subprocess.CalledProcessError:
                    continue
            shas = [l.split()[0].lstrip('^') for l in out.splitlines() if l.strip()]
            per = 1.0 / len(shas) if w == 0 else 1.0
            for s in shas:
                st = stage.get(s)
                if st is None:
                    st = 'dev' if s not in known else 'post?'
                votes[st] += per
    return votes, newfiles


known = {r[0] for r in rows}
res = []
for sha, fp, kind, subj in rows:
    csubj = git('log', '-1', '--format=%s', sha).strip()
    if sha in stage:
        res.append((sha, fp, stage[sha], 'pr', '', csubj))
        continue
    votes, newfiles = blame_votes(sha)
    stv = {k: v for k, v in votes.items() if k in STAGES}
    dev = votes.get('dev', 0)
    if stv:
        ranked = sorted(stv.items(), key=lambda kv: -kv[1])
        win, wv = ranked[0]
        amb = len(ranked) > 1 and ranked[1][1] >= 0.5 * wv
        flag = 'AMB' if amb else ''
        if dev > wv:
            flag = (flag + ',DEVMAJ').strip(',')
    else:
        win, flag = '?', 'NOSTAGE'
    if newfiles:
        flag = (flag + ',NEW').strip(',')
    stage[sha] = win
    detail = ' '.join(f'{k}:{v:g}' for k, v in sorted(votes.items(), key=lambda kv: -kv[1]))
    if newfiles:
        detail += ' new=' + ','.join(newfiles)
    res.append((sha, fp, win, 'blame', flag + ' | ' + detail, csubj))

with open(f'{OUT}/commit-stage.tsv', 'w') as f:
    f.write('sha\tintroduced_by\tstage\tmethod\tflags|votes\tsubject\n')
    for r in res:
        f.write('\t'.join([r[0][:10], r[1], *r[2:]]) + '\n')
print(collections.Counter(r[2] for r in res))
print(collections.Counter(r[3] for r in res))
