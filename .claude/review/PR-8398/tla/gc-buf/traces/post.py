#!/usr/bin/env python3
# usage: post.py <raw TLATRACE log> > <normalized log>
# Normalizes a run of the instrumented build for trace2tla: node pointers become the spec's
# node names ("o", "w1", "w2", ... in the order the workers first appear), buffer addresses
# become 1, 2, ... in first-seen order ((nil) -> 0), _role lines are dropped, and "Clear"
# becomes WClear (a worker clone), ExtFree (a GROUP BY output node) or OEnd k=clear (the
# coordinator's node at the end of a BUILDVALUE query). An OInit of a worker clone is dropped:
# qdata_initialize_aggregate_list's capacity reset on a clone is a step the spec does not have,
# and it can only forget a capacity.
import re, sys
ev = []
for line in open(sys.argv[1], errors="replace"):
    i = line.find("TLATRACE")
    if i < 0:
        continue
    f = dict(t.split("=", 1) for t in line[i + 8:].split())
    ev.append(f)
ev.sort(key=lambda f: int(f["seq"]))
role = {}
for f in ev:
    if f["a"] == "_role":
        role.setdefault(f["p"], f["role"])
    elif f["a"] in ("WMerge", "WRun"):
        role.setdefault(f["p"], "w")    # finalize_node's cur_agg_p is a worker's clone
workers = []
addr = {}
def A(v):
    if v in ("(nil)", "0", "0x0"):
        return "0"
    if v not in addr:
        addr[v] = str(len(addr) + 1)
    return addr[v]
def N(p):
    if role.get(p) == "w":
        if p not in workers:
            workers.append(p)
        return "w%d" % (workers.index(p) + 1)
    return "o"
out = []
for f in ev:
    a = f["a"]
    if a == "_role":
        continue
    r = role.get(f["p"])
    if a == "OInit" and r == "w":
        continue
    if a == "Clear":
        if r == "w":
            a = "WClear"
        elif r == "gout":
            out.append("TLATRACE seq=%s a=ExtFree p=ext addr=%s" % (f["seq"], A(f["addr"])))
            continue
        else:
            out.append("TLATRACE seq=%s a=OEnd p=o k=clear addr=%s" % (f["seq"], A(f["addr"])))
            continue
    g = ["seq=" + f["seq"], "a=" + a, "p=" + (N(f["p"]) if r != "gout" else "ext")]
    for k, v in f.items():
        if k in ("seq", "a", "p"):
            continue
        g.append("%s=%s" % (k, A(v) if k == "addr" else v))
    out.append("TLATRACE " + " ".join(g))
print("\n".join(out))
sys.stderr.write("workers=%d addresses=%d events=%d\n" % (len(workers), len(addr), len(out)))
