#!/usr/bin/env python3
# usage: convert.py <log> <Name> <btid|auto> <keys> [corrupt]
#   <log>     TLATRACE lines of one csql run on the instrumented build (KeyRewind MAP.md "Trace validation")
#   <Name>    prefix of the operators written: <Name>Log, <Name>Rlo, <Name>Rhi, <Name>M, <Name>Leaf, <Name>Pg,
#             <Name>NPg, <Name>NOut, <Name>NK (printed to stdout as a TLA+ fragment)
#   <btid>    the index file id whose scan is the trace, or auto: the index with the most overflow-page events on
#             <keys>
#   <keys>    comma-separated int key values of the probe's index
#   corrupt:  stale-off   the second Start reports stale=0
#             skip-leaf   the second session's first LeafFill becomes a KeyResume at page 1 (develop's step)
#             count-off   the first PageFill reports one object more
import re, sys

def events(path):
    out = []
    for line in open(path, errors="replace"):
        i = line.find("TLATRACE")
        if i < 0:
            continue
        f = dict(t.split("=", 1) for t in line[i + 8:].split() if "=" in t)
        out.append(f)
    out.sort(key=lambda r: int(r["seq"]))
    return out

def main():
    path, name, btid, keys = sys.argv[1:5]
    corrupt = sys.argv[5] if len(sys.argv) > 5 else None
    keyset = set(int(k) for k in keys.split(","))
    ev = events(path)
    if btid == "auto":
        # the probe's index: the one whose keys fill overflow pages (catalog indexes have none)
        cand = [e["b"] for e in ev if e["a"] in ("PageFill", "Interrupt") and int(e["key"]) in keyset]
        btid = max(set(cand), key=cand.count)
    ev = [e for e in ev if e.get("b") == btid]
    # sessions: split at Rewind / Flip; the resets before the first Start belong to no session
    seq = []
    started = False
    for e in ev:
        if e["a"] == "Start":
            started = True
        if e["a"] in ("Rewind", "Flip") and not started:
            continue
        if e["a"] == "Call" and e["started"] == "0":
            continue  # the first btree_range_scan call of a session: its Start follows
        seq.append(e)
    # trailing resets after the last session (scan close) are not part of the trace
    while seq and seq[-1]["a"] in ("Rewind", "Flip"):
        seq.pop()
    sessions = [[]]
    for e in seq:
        if e["a"] in ("Rewind", "Flip"):
            sessions.append([])
        sessions[-1].append(e)
    # key order: within a session the keys are visited in model order
    vals = sorted(set(int(e["key"]) for e in seq if "key" in e))
    before = {v: set() for v in vals}
    for s in sessions:
        ks = []
        for e in s:
            if "key" in e and (not ks or ks[-1] != int(e["key"])):
                ks.append(int(e["key"]))
        for a, b in zip(ks, ks[1:]):
            before[b].add(a)
    order = []
    left = set(vals)
    while left:
        ready = sorted(v for v in left if before[v] <= set(order))
        if not ready:
            sys.exit("cyclic key order: %s" % before)
        order.append(ready[0])
        left.remove(ready[0])
    idx = {v: n + 1 for n, v in enumerate(order)}
    # key structure
    leaf, pg, npg, done = {}, {}, {}, set()
    for e in seq:
        if "key" not in e:
            continue
        k = idx[int(e["key"])]
        if e["a"] == "LeafFill":
            leaf.setdefault(k, int(e["n"]))
        elif e["a"] in ("PageFill", "Interrupt"):
            pg.setdefault((k, int(e["pg"])), int(e["n"]))
            npg[k] = max(npg.get(k, 0), int(e["pg"]))
        elif e["a"] == "KeyDone":
            done.add(k)
    nk = len(order)
    for k in range(1, nk + 1):
        leaf.setdefault(k, 0)
        npg.setdefault(k, 0)
    base, pstart = {}, {}
    acc = 0
    for k in range(1, nk + 1):
        base[k] = acc
        acc += leaf[k]
        for p in range(1, npg[k] + 1):
            pstart[(k, p)] = acc
            acc += pg.get((k, p), 0)
    # per session: range and the matched object (the buffer position a Row event names)
    rlo, rhi, m = [], [], []
    for s in sessions:
        ks = [idx[int(e["key"])] for e in s if "key" in e]
        rlo.append(min(ks))
        rhi.append(max(ks))
        bufobj, match = [], None
        for e in s:
            if e["a"] == "Call":
                bufobj = []
            elif e["a"] == "LeafFill":
                k = idx[int(e["key"])]
                bufobj += list(range(base[k] + 1, base[k] + int(e["n"]) + 1))
            elif e["a"] == "PageFill":
                k, p = idx[int(e["key"])], int(e["pg"])
                bufobj += list(range(pstart[(k, p)] + 1, pstart[(k, p)] + int(e["n"]) + 1))
            elif e["a"] == "Row" and match is None:
                match = bufobj[int(e["pos"]) - 1]
        m.append(match)
    log = [e for s in sessions for e in s]
    if corrupt == "stale-off":
        k = [j for j, e in enumerate(log) if e["a"] == "Start"][1]
        log[k] = dict(log[k], stale="0")
    elif corrupt == "skip-leaf":
        k0 = [j for j, e in enumerate(log) if e["a"] == "Start"][1]
        k = next(j for j in range(k0, len(log)) if log[j]["a"] == "LeafFill")
        log[k] = dict(a="KeyResume", key=log[k]["key"], pg="1", off="0")
    elif corrupt == "count-off":
        k = next(j for j, e in enumerate(log) if e["a"] == "PageFill")
        log[k] = dict(log[k], n=str(int(log[k]["n"]) + 1))
    def rec(e):
        f = {"a": '"%s"' % e["a"]}
        for x in ("stale", "n", "pg", "buf", "pos", "flag"):
            f[x] = e.get(x, "0")
        f["key"] = str(idx[int(e["key"])]) if "key" in e else "0"
        return "[" + ", ".join("%s |-> %s" % kv for kv in f.items()) + "]"
    print("\\* %s: traces/convert.py %s %s %s %s %s (btid %s, keys %s -> 1..%d)" % (
        name, __import__("os").environ.get("TRACE_LABEL", path.split("/")[-1]), name, sys.argv[3], keys, corrupt or "", btid,
        ",".join(str(v) for v in order), nk))
    print("%sLog == <<\n  %s\n>>" % (name, ",\n  ".join(rec(e) for e in log)))
    print("%sNK == %d" % (name, nk))
    print("%sNOut == %d" % (name, len(sessions)))
    print("%sRlo == <<%s>>" % (name, ", ".join(map(str, rlo))))
    print("%sRhi == <<%s>>" % (name, ", ".join(map(str, rhi))))
    print("%sM == <<%s>>" % (name, ", ".join("{}" if x is None else "{%d}" % x for x in m)))
    print("%sLeaf == <<%s>>" % (name, ", ".join(str(leaf[k]) for k in range(1, nk + 1))))
    print("%sNPg == <<%s>>" % (name, ", ".join(str(npg[k]) for k in range(1, nk + 1))))
    print("%sPg == <<%s>>" % (name, ", ".join("<<%s>>" % ", ".join(str(pg.get((k, p), 0)) for p in range(1, npg[k] + 1)) for k in range(1, nk + 1))))

main()
