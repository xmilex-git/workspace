# Map a raw TLATRACE log of the instrumented 8436 build to the model's events (MAP.md "Trace validation").
import sys, re
ev = []
for line in open(sys.argv[1]):
    if 'TLATRACE' not in line or ' a=' not in line:
        continue
    d = dict(kv.split('=', 1) for kv in line.split('TLATRACE ', 1)[1].split() if '=' in kv)
    ev.append(d)
arm1 = next(e for e in ev if e['a'] == 'EndRow' and e.get('n', '(nil)') != '(nil)')
arms = [arm1['x'], arm1['n']]
thr = {}
for e in ev:
    if e['a'] == 'EndRow' and e['x'] in arms and e['x'] not in thr:
        thr[e['x']] = e['p']
last_done = {a: max(i for i, e in enumerate(ev) if e['a'] == 'EndRowDone' and e['x'] == a) for a in arms}
serial = thr[arms[0]] == thr[arms[1]]
def owner_of_block(i, e):
    if not serial:
        for k, a in enumerate(arms):
            if thr[a] == e['p']:
                return k + 1
        return None
    return 1 if i <= last_done[arms[0]] else 2
subs = {}
all_done = max(last_done.values())
for i, e in enumerate(ev):
    if e['x'] in arms or i > all_done:
        continue
    if e['a'] in ('EndRow', 'Free') and e['x'] not in subs:
        o = owner_of_block(i, e)
        if o is not None:
            subs[e['x']] = o
out = []
open_win = {}
for i, e in enumerate(ev):
    a, x, p = e['a'], e['x'], e['p']
    if x in arms:
        k = arms.index(x) + 1
        if a == 'EndRow':
            open_win[p] = k; out.append('a=RowEnd arm=%d' % k)
        elif a == 'EndRowDone':
            open_win.pop(p, None); out.append('a=RowDone arm=%d' % k)
        elif a == 'Free':
            out.append('a=FinalFree arm=%d' % k)
    elif x in subs:
        k = subs[x]
        if a == 'EndRow':
            out.append('a=SubRow arm=%d' % k)
        elif a == 'Free':
            if p in open_win:
                out.append('a=RowFree arm=%d win=%d' % (k, open_win[p]))
            elif i > all_done:
                out.append('a=FinalFree arm=%d' % k)
            else:
                out.append('a=TruncFree arm=%d' % k)
    elif a == 'Free' and i > all_done:
        out.append('a=FinalFree arm=0')
for n, o in enumerate(out):
    print('TLATRACE seq=%d %s p=e' % (n, o))
sys.stderr.write('arms=%s threads=%s serial=%s subs=%s events=%d\n' % (arms, thr, serial, subs, len(out)))
