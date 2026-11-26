#!/usr/bin/env python3
# reground.py <engine worktree> <new rev> <MAP.md> <old rev> [--write]
# Move every `file.ext:N[-M]` (and the bare `:N` that follows it in the same line) from <old rev> to <new rev>
# through the hunks of `git diff -U0 old new -- path`. A line the diff changed or deleted is reported, not moved.
import re, subprocess, sys

W, NEW, MAP, OLD = sys.argv[1:5]
WRITE = '--write' in sys.argv


def git(*a):
    return subprocess.run(['git', '-C', W] + list(a), capture_output=True, text=True).stdout


paths = {}
for p in git('ls-tree', '-r', '--name-only', OLD, 'src').splitlines():
    paths.setdefault(p.rsplit('/', 1)[-1], []).append(p)

hunks = {}


def mapper(base):
    if base not in hunks:
        ps = paths.get(base, [])
        if len(ps) != 1:
            hunks[base] = None
        else:
            hs = []
            for l in git('diff', '-U0', OLD, NEW, '--', ps[0]).splitlines():
                m = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', l)
                if m:
                    o, oc, n, nc = int(m[1]), int(m[2] or 1), int(m[3]), int(m[4] or 1)
                    hs.append((o, oc, n, nc))
            hunks[base] = hs
    return hunks[base]


def move(base, n):
    hs = mapper(base)
    if hs is None:
        return None
    delta = 0
    for o, oc, nn, nc in hs:
        if oc == 0:  # pure insertion after old line o
            if n > o:
                delta += nc
            continue
        if n < o:
            break
        if n < o + oc:
            return None  # the line itself changed
        delta += nc - oc
    return n + delta


moved = same = bad = 0
out = []
for ln, line in enumerate(open(MAP).read().split('\n'), 1):
    cur = [None]

    def rep(m):
        global moved, same, bad
        if m.group('file'):
            cur[0] = m.group('file')
        if cur[0] is None:
            return m.group(0)
        a = int(m.group('a'))
        b = m.group('b')
        na = move(cur[0], a)
        nb = move(cur[0], int(b)) if b else None
        if na is None or (b and nb is None):
            bad += 1
            print('UNMOVED %s:%d  %s:%s%s' % (MAP.rsplit('/', 2)[-2], ln, cur[0], a, '-' + b if b else ''))
            return m.group(0)
        if na == a and (not b or nb == int(b)):
            same += 1
        else:
            moved += 1
        return '%s:%d%s' % (m.group('file') or '', na, '-%d' % nb if b else '')

    out.append(re.sub(r'(?P<file>[A-Za-z_0-9]+\.(?:cpp|hpp|c|h|y|l))?:(?P<a>\d+)(?:-(?P<b>\d+))?(?![\d:])', rep, line))
print('%s moved=%d same=%d unmoved=%d' % (MAP, moved, same, bad))
if WRITE:
    open(MAP, 'w').write('\n'.join(out))
