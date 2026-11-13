#!/usr/bin/env python3
# usage: post.py <raw TLATRACE log> > <normalized log>
# Normalizes a run of the instrumented build (traces/tlatrace-fields.patch) for trace2tla:
# - node pointers become the spec's node names: "o" for a serial node and a parallel scan's
#   coordinator node (the Rehome node), "w1", "w2", ... for its worker clones in order of first
#   appearance within the parallel query;
# - a Query event (mode, whether the separator is NULL) is put before every serial group's first
#   value and before every parallel scan's BORROW: the spec re-chooses the function's type there;
# - inside a parallel scan, the separator and value appends finalize_node makes on the coordinator
#   node (after a WVal of worker w) become k=msep / k=mval with w=<worker>; a worker's first value
#   becomes k=wfirst; the WVal events are dropped;
# - a NULL value's missing fields get neutral numbers; every App event carries w (its node, or the
#   merged worker).
import sys

VF = ("vt", "vp", "vsz", "vln", "vlc", "vcs", "vco", "vnul", "vcmp")
RF = ("rt", "rp", "rsz", "rln", "rlc", "rcs", "rco", "rnul", "rcmp")
DEF = {"p": "-1", "sz": "0", "ln": "0", "lc": "-1", "cs": "0", "co": "0", "cmp": "0"}

ev = []
for line in open(sys.argv[1], errors="replace"):
    i = line.find("TLATRACE")
    if i < 0:
        continue
    ev.append(dict(t.split("=", 1) for t in line[i + 8:].split()))
ev.sort(key=lambda f: int(f["seq"]))


def fill(f, pre, keys):
    for k in keys:
        if k not in f:
            f[k] = DEF[k[1:]]


# parallel query spans: from a Rehome borrow to the coordinator's Fin
out = []
px = None          # coordinator pointer while inside a parallel scan
workers = {}
merging = {}       # thread-free: the coordinator node's pending merge source, set by WVal
pending_sep_nul = None


def emit(f):
    out.append(f)


def query_event(mode, sepnul):
    emit({"a": "Query", "p": "o", "mode": mode, "sepnul": str(sepnul)})


def px_sepnul(start):
    # the separator is NULL when no App k=sep shows up before the coordinator's Fin
    coord = ev[start]["p"]
    for f in ev[start + 1:]:
        if f["a"] == "Fin" and f["p"] == coord:
            return 1
        if f["a"] == "App" and f.get("k") == "sep":
            return 0
    return 1


last_src = None
for idx, f in enumerate(ev):
    a = f["a"]
    if a == "Rehome" and f.get("dir") == "borrow":
        px = f["p"]
        workers = {}
        last_src = None
        query_event("px", px_sepnul(idx))
        emit({"a": "Rehome", "p": "o", "dir": "borrow"})
        continue
    if px is None:
        if a == "App":
            if f.get("k") == "first":
                query_event("serial", 0)
            g = {"a": "App", "p": "o", "w": "o", "k": f["k"]}
        elif a == "Fin":
            g = {"a": "Fin", "p": "o"}
        else:
            sys.exit(f"unexpected serial event {f}")
    else:
        if a == "WVal":
            last_src = f["p"]
            continue
        if a == "Rehome":
            g = {"a": "Rehome", "p": "o", "dir": f["dir"]}
        elif a == "Clone":
            w = workers.setdefault(f["src"], "w%d" % (len(workers) + 1))
            g = {"a": "Clone", "p": "o", "w": w}
        elif a == "Fin":
            g = {"a": "Fin", "p": "o"}
            if f["p"] == px:
                px_end = True
        elif a == "App":
            if f["p"] == px:
                if last_src is None:
                    sys.exit(f"merge append without a WVal: {f}")
                w = workers.setdefault(last_src, "w%d" % (len(workers) + 1))
                k = "msep" if f["k"] == "sep" else "mval"
                g = {"a": "App", "p": "o", "w": w, "k": k}
                if k == "mval":
                    last_src = None
            else:
                w = workers.setdefault(f["p"], "w%d" % (len(workers) + 1))
                k = "wfirst" if f["k"] == "first" else f["k"]
                g = {"a": "App", "p": w, "w": w, "k": k}
        else:
            sys.exit(f"unexpected parallel event {f}")
    for k in ("full", "sp", "err"):
        if k in f:
            g[k] = f[k]
    if a in ("App", "Clone"):
        fill(f, "v", ("vp", "vsz", "vln", "vlc", "vcs", "vco", "vcmp"))
        for k in VF:
            g[k] = f[k]
    if a in ("App", "Clone", "Fin") or (a == "Rehome" and f.get("dir") == "restore"):
        fill(f, "r", ("rp", "rsz", "rln", "rlc", "rcs", "rco", "rcmp"))
        for k in RF:
            g[k] = f[k]
    emit(g)
    if a == "Fin" and px is not None and f["p"] == px:
        px = None

for n, g in enumerate(out, 1):
    print("TLATRACE seq=%d " % n + " ".join("%s=%s" % kv for kv in g.items()))
