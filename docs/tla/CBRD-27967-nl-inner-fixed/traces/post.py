#!/usr/bin/env python3
# usage: post.py <raw log> <statement number, 1-based>  > <model events>
#
# Turns the instrumented build's scan events (scan_manager.c / heap_file.c TLATRACE lines: Next, Reset,
# Early, Fix, Copy, CopyHit, End; p= the scan id, or the scan cache at scan id + 0x70 for the heap events)
# into NlInnerFixed's R actions for one execution of a statement: an index scan (k=O) outermost, a cached
# heap scan (k=M) in the middle, a fixed heap scan (k=I) innermost. A statement's window runs from the
# first event of a new outer scan to its S_END. Pages are named by their order within the window: a level's
# first fixed page is its header page (M1, B1), any other its next page (M2, B2).
import re
import sys

raw, want = sys.argv[1], int(sys.argv[2])
ev = []
for line in open(raw):
    m = line.find("TLATRACE")
    if m >= 0:
        ev.append(dict(t.split("=", 1) for t in line[m + 8:].split()))
ev.sort(key=lambda e: int(e["seq"]))

# statement windows
wins, cur, outer = [], None, None
for e in ev:
    if e["k"] == "O" and e["a"] == "Next" and outer is None:
        outer, cur = e["p"], []
    if cur is not None:
        cur.append(e)
        if e["k"] == "O" and e["p"] == outer and e["a"] == "Next" and e["res"] == "0":
            wins.append(cur)
            cur, outer = None, None
win = wins[want - 1]

out = []
first = {}          # level -> header page id
mfix = None         # middle page fixed since the last middle row
def page(k, pg):
    first.setdefault(k, pg)
    return ("M1" if k == "M" else "B1") if pg == first[k] else ("M2" if k == "M" else "B2")
def emit(a, **kw):
    out.append("a=%s p=R%s" % (a, "".join(" %s=%s" % kv for kv in kw.items())))

for i, e in enumerate(win):
    a, k = e["a"], e["k"]
    if k == "O":
        if e["p"] != win[0]["p"]:
            sys.exit("seq %s: a second index scan in the window" % e["seq"])
        emit("OuterRow" if e["res"] == "1" else "OuterEnd")
    elif k == "M":
        if a == "Reset":
            emit("MStart")
        elif a == "Fix":
            pg = page("M", e["pg"])
            if pg == "M1":
                mfix = pg
            else:
                nxt = win[i + 1] if i + 1 < len(win) else {}
                emit("MNextPage", copy=1 if nxt.get("a") == "Copy" else 0)
        elif a == "Next" and e["res"] == "1":
            pg = page("M", e["pg"])
            emit("MRow", pg=pg, fix=1 if mfix == pg else 0)
            mfix = None
        elif a == "End":
            emit("MEnd")
        # Copy (read with its Fix), CopyHit (a row or slot search on the copy), Next res=0 (after End): no step
    elif k == "I":
        if a == "Reset":
            emit("IReset", held=e["held"])
        elif a == "Fix":
            emit("IStart" if page("I", e["pg"]) == "B1" else "INextPage")
        elif a == "Next":
            emit("IRow" if e["res"] == "1" else "IBack", held=e["held"])
        elif a == "Early":
            emit("IEarly")
        elif a == "End":
            emit("IEnd")
    else:
        sys.exit("seq %s: scan kind %s in the window" % (e["seq"], k))

for n, o in enumerate(out, 1):
    print("TLATRACE seq=%d %s" % (n, o))
