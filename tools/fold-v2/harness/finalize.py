#!/usr/bin/env python3
# Merge blame attribution with manual overrides; emit commit-stage.tsv (final) and stage-range.tsv.
import collections, subprocess

R = '/home/cubrid/dev/cubrid-worktree/develop'
OUT = '/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fold-v2'
ORDER = ['S0', 'A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'B1', 'B2', 'B3', 'B4', 'B5',
         'CI', 'DEV-FIXED', 'DEV-BUG']


def git(*a):
    return subprocess.run(['git', '-C', R, *a], check=True, capture_output=True, text=True,
                          errors='replace').stdout


rows = [l.rstrip('\n').split('\t') for l in open(f'{OUT}/commit-stage.tsv')][1:]
ov = {}
for l in open(f'{OUT}/overrides.tsv'):
    p = l.rstrip('\n').split('\t')
    ov[p[0][:9]] = p[1:]
final = []
used = set()
for sha, intro, st, method, votes, subj in rows:
    flags, why = '', ''
    if method == 'blame':
        flags = votes.split(' | ')[0]
        why = 'blame ' + votes.split(' | ', 1)[1] if ' | ' in votes else ''
    k = sha[:9]
    if k in ov:
        used.add(k)
        st, oflag, why = ov[k][0], ov[k][1], ov[k][2]
        method, flags = 'manual', oflag
    elif method == 'blame' and flags.replace('NEW', '').strip(','):
        method = 'blame-review'  # flagged by blame but kept after reading
    final.append([sha, intro, st, method, flags, why, subj])
missing = set(ov) - used
assert not missing, missing
assert all(r[2] in ORDER for r in final), [r for r in final if r[2] not in ORDER]

# file -> owning stage: first stage (in fold order) whose non-CI commits touch it
numstat = {}
for r in final:
    numstat[r[0]] = [l.split('\t') for l in git('show', '--format=', '--numstat', '-M', r[0]).splitlines() if l]
owner = {}
for st in ORDER[:14]:
    for r in final:
        if r[2] == st:
            for a, d, f in numstat[r[0]]:
                owner.setdefault(f, st)
rng = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0, 0]))
for r in final:
    for a, d, f in numstat[r[0]]:
        st = r[2] if r[2] != 'CI' else owner.get(f, 'CI')
        a = int(a) if a != '-' else 0
        d = int(d) if d != '-' else 0
        e = rng[st][f]
        e[0] += a; e[1] += d; e[2] += 1

with open(f'{OUT}/commit-stage.tsv', 'w') as f:
    f.write('sha\tintroduced_by\tstage\tmethod\tflags\twhy\tsubject\n')
    for r in final:
        f.write('\t'.join([r[0][:10], *r[1:]]) + '\n')
with open(f'{OUT}/stage-range.tsv', 'w') as f:
    f.write('stage\tfile\tadded\tdeleted\tcommits\n')
    for st in ORDER:
        for fn, (a, d, c) in sorted(rng[st].items()):
            f.write(f'{st}\t{fn}\t{a}\t{d}\t{c}\n')

cnt = collections.Counter(r[2] for r in final)
pr = collections.Counter(r[2] for r in final if r[3] == 'pr')
for st in ORDER:
    files = rng[st]
    print(f'{st:9} commits={cnt[st]:3} (pr {pr[st]:3} / post {cnt[st]-pr[st]:3})  files={len(files):3}  '
          f'+{sum(v[0] for v in files.values())} -{sum(v[1] for v in files.values())}')
print('total', sum(cnt.values()))
print('flags', collections.Counter(r[4] for r in final if r[4]))
print('methods', collections.Counter(r[3] for r in final))
