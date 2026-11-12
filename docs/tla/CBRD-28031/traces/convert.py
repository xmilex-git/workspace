#!/usr/bin/env python3
# usage: convert.py serial <log> <out.tla> [corrupt]      one serial index scan (the class with the most Fill events)
#        convert.py worker <log> <Name> <k> <need> [corrupt]  the k-th smallest worker segment (one walker on one leaf, no
#                                                          overflow page) with <need>: pop | resume | err | cov
# corrupt: swap-look | drop-check | flip-fired | foreign-hint | pos-off (worker) | drop-eval (worker) | skip-off (worker)
# Writes a TLA+ data module: serial -> TraceLog, Pg (pages of each buffer); worker -> TraceLog, NOid, Base, Rej, ErrKey, Cov.
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

def lit(v):
    return v if re.fullmatch(r"-?[0-9]+", v) else '"%s"' % v

def rec(f, keep):
    return "[" + ", ".join("%s |-> %s" % (k, lit(f.get(k, "0"))) for k in keep) + "]"

def serial(ev, corrupt):
    fills = [e for e in ev if e["a"] == "Fill" and e.get("next") != "-1" or (e["a"] == "Fill" and int(e["n"]) > 1)]
    cls = max(set(e["cls"] for e in fills), key=lambda c: sum(1 for e in fills if e["cls"] == c))
    scans = [e["p"] for e in fills if e["cls"] == cls]
    p = max(set(scans), key=scans.count)
    seq = [e for e in ev if e.get("p") == p and e["a"] in ("Fill", "Check", "Look")]
    # the first event of the scan is its first Fill
    while seq and seq[0]["a"] != "Fill":
        seq.pop(0)
    if corrupt == "swap-look":
        k = [j for j, e in enumerate(seq) if e["a"] == "Look"][5]
        seq[k] = dict(seq[k], pg=str(int(seq[k]["pg"]) + 1))
    elif corrupt == "drop-check":
        k = [j for j, e in enumerate(seq) if e["a"] == "Check" and e.get("fired") == "1"][1]
        del seq[k]
    elif corrupt == "flip-fired":
        k = [j for j, e in enumerate(seq) if e["a"] == "Check" and e.get("fired") == "0"][0]
        seq[k] = dict(seq[k], fired="1", start=seq[k]["curr"], stop=seq[k]["curr"], skip="0", hinted="")
    elif corrupt == "foreign-hint":
        k = [j for j, e in enumerate(seq) if e["a"] == "Check" and e.get("fired") == "1" and e.get("skip") == "0"][0]
        seq[k] = dict(seq[k], hinted=(seq[k]["hinted"] + "," if seq[k]["hinted"] else "") + "999999")
    pg = []
    log = []
    for e in seq:
        if e["a"] == "Fill":
            pg.append([int(x) for x in e["pg"].split(",")])
            log.append("[a |-> \"Fill\", n |-> %s, next |-> %s, curr |-> 0, fired |-> 0, start |-> 0, stop |-> 0, skip |-> 0, hinted |-> {}, pg |-> 0]" % (e["n"], e["next"]))
        elif e["a"] == "Check":
            h = "{" + e.get("hinted", "") + "}" if e.get("hinted") else "{}"
            log.append("[a |-> \"Check\", n |-> 0, next |-> 0, curr |-> %s, fired |-> %s, start |-> %s, stop |-> %s, skip |-> %s, hinted |-> %s, pg |-> 0]" % (e["curr"], e["fired"], e.get("start", "0"), e.get("stop", "0"), e.get("skip", "0"), h))
        else:
            log.append("[a |-> \"Look\", n |-> 0, next |-> 0, curr |-> %s, fired |-> 0, start |-> 0, stop |-> 0, skip |-> 0, hinted |-> {}, pg |-> %s]" % (e["curr"], e["pg"]))
    maxn = max(len(x) for x in pg)
    maxp = max(max(x) for x in pg)
    return log, pg, maxn, maxp

def worker(ev, k, corrupt, need):
    # segments: one walker on one leaf, from WLeaf to its next WClear
    segs = {}
    order = []
    cur = {}
    for e in ev:
        if not e["a"].startswith("W"):
            continue
        w = e["w"]
        if e["a"] == "WLeaf":
            cur[w] = (w, e["seq"])
            segs[cur[w]] = [e]
            order.append(cur[w])
            continue
        if w in cur:
            segs[cur[w]].append(e)
            if e["a"] == "WClear":
                del cur[w]
    def ok(s):
        g = segs[s]
        if g[-1]["a"] != "WClear" or any(e["a"] == "WOvf" or e.get("ovfl") == "1" for e in g):
            return False
        has = lambda a, **kv: any(e["a"] == a and all(e.get(x) == y for x, y in kv.items()) for e in g)
        if need == "pop":
            return has("WPop") and g[0]["cov"] == "0"
        if need == "resume":
            return any(e["a"] == "WResume" and e["skipped"] != "0" for e in g) and has("WPop")
        if need == "err":
            return has("WKey", ahead="1", res="ERR") and has("WKey", ahead="0", res="ERR")
        if need == "cov":
            return g[0]["cov"] == "1" and has("WLook")
        return True
    good = [s for s in order if ok(s)]
    good.sort(key=lambda g: len(segs[g]))
    seg = [dict(e) for e in segs[good[k]]]
    cov = int(seg[0]["cov"])
    seg = seg[1:]
    if corrupt == "pos-off":
        j = [x for x, e in enumerate(seg) if e["a"] == "WWin"][0]
        seg[j]["pos"] = str(int(seg[j]["pos"]) + 1)
    elif corrupt == "drop-eval":
        j = [x for x, e in enumerate(seg) if e["a"] == "WKey" and e["ahead"] == "1" and e["res"] == "Q"][0]
        del seg[j]
    elif corrupt == "skip-off":
        j = [x for x, e in enumerate(seg) if e["a"] == "WResume" and e["skipped"] != "0"][0]
        seg[j]["skipped"] = str(int(seg[j]["skipped"]) - 1)
    # the leaf's keys in key order: every key a next_key call read (rk counts them), rejected ones with no OID;
    # the key an ahead call stopped at (range end, error) is read again by the next lookup call
    noid, rej, err, pending = [], [], 0, None
    for e in seg:
        if e["a"] != "WKey":
            continue
        rk, res = int(e["rk"]), e["res"]
        if e["ahead"] == "0" and pending is not None:
            assert res == pending, (res, pending)
            pending = None
            continue
        nrej = rk - 1 if res == "Q" or (e["ahead"] == "0" and res in ("ERR", "END")) else rk
        for _ in range(nrej):
            noid.append(0)
            rej.append(len(noid))
        if res == "Q":
            noid.append(int(e["n"]))
        elif res == "ERR":
            noid.append(0)
            err = len(noid)
        if e["ahead"] == "1" and res != "Q":
            pending = res
    log = []
    for e in seg:
        log.append("[a |-> \"%s\", ahead |-> %s, res |-> \"%s\", rk |-> %s, n |-> %s, pos |-> %s, sk |-> %s]"
                   % (e["a"], e.get("ahead", "0"), e.get("res", ""), e.get("rk", "0"), e.get("n", "0"),
                      e.get("pos", "0"), e.get("skipped", "0")))
    return log, noid, rej, err, cov, len(good)

# usage (operators, appended to stdout): convert.py serial <log> <Name> [corrupt] | worker <log> <Name> <k> <need> [corrupt]
mode, path, name = sys.argv[1], sys.argv[2], sys.argv[3]
ev = events(path)
w = sys.stdout.write
w("\\* %s: traces/convert.py %s %s %s\n" % (name, mode, path.rsplit("/", 1)[-1], " ".join(sys.argv[4:])))
if mode == "serial":
    log, pg, maxn, maxp = serial(ev, sys.argv[4] if len(sys.argv) > 4 else "")
    w("%sLog == <<\n  " % name + ",\n  ".join(log) + "\n>>\n")
    w("%sPg == <<\n  " % name + ",\n  ".join("<<" + ", ".join(map(str, x)) + ">>" for x in pg) + "\n>>\n")
    w("%sNB == %d\n%sMaxN == %d\n%sNP == %d\n" % (name, len(pg), name, maxn, name, maxp))
    sys.stderr.write("%s events=%d buffers=%d maxn=%d maxpage=%d\n" % (name, len(log), len(pg), maxn, maxp))
else:
    log, noid, rej, err, cov, ngood = worker(ev, int(sys.argv[4]), sys.argv[6] if len(sys.argv) > 6 else "", sys.argv[5])
    w("%sLog == <<\n  " % name + ",\n  ".join(log) + "\n>>\n")
    base = [0]
    for n in noid:
        base.append(base[-1] + n)
    w("%sNOid == <<" % name + ", ".join(map(str, noid)) + ">>\n%sNK == %d\n%sMaxO == %d\n" % (name, len(noid), name, max(noid) if noid else 0))
    w("%sBase == <<" % name + ", ".join(map(str, base)) + ">>\n")
    w("%sRej == {" % name + ", ".join(map(str, rej)) + "}\n%sErrKey == %d\n%sCov == %s\n" % (name, err, name, "TRUE" if cov else "FALSE"))
    sys.stderr.write("%s events=%d keys=%d rejected=%d errkey=%d cov=%d maxo=%d segments=%d\n" % (name, len(log), len(noid), len(rej), err, cov, max(noid) if noid else 0, ngood))
