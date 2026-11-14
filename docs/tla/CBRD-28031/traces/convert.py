#!/usr/bin/env python3
# usage: convert.py serial <log> <out.tla> [corrupt]      one serial index scan (the class with the most Fill events)
#        convert.py worker <log> <Name> <k> <need> [corrupt]  the k-th smallest worker segment (one walker on one leaf, no
#                                                          overflow page) with <need>: pop | resume | err | cov | intr
# corrupt: swap-look | drop-check | flip-fired | foreign-hint | pos-off (worker) | drop-eval (worker) | skip-off (worker)
#          | intr-look (worker: the error return after a cancel taken by the look-ahead turned into a lookup)
# Writes a TLA+ data module: serial -> TraceLog, Pg (pages of each buffer); worker -> TraceLog, NOid, Base, Rej, ErrKey, Cov, Cap, Dist0.
#        convert.py covered <log> <Name> <need> [nk=<keys>] [corrupt]  one covered index scan (CoveredVisit), the one with
#                                                          the most selected objects among those with <need>:
#                                                          visit | list | verr | lerr | restart | inner<k> (k-th visited scan)
# corrupt (covered): dup-sel | list-in-visit | dlv-after-err | drop-ret | drop-dlv | foreign-in-visit
#   covered -> TraceLog, NK, PerKey, Cap, Fail (the object whose row raised the error, 0: none)
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
        if need == "intr":
            return has("WKey", ahead="1", intr="1") and has("WIntr") and has("WPop")
        if need == "cov":
            return g[0]["cov"] == "1" and has("WLook")
        return True
    good = [s for s in order if ok(s)]
    good.sort(key=lambda g: len(segs[g]))
    seg = [dict(e) for e in segs[good[k]]]
    cov = int(seg[0]["cov"])
    cap = int(seg[0].get("cap", "1000000"))
    dist0 = int(seg[0].get("dist", "0"))
    seg = seg[1:]
    if corrupt == "pos-off":
        j = [x for x, e in enumerate(seg) if e["a"] == "WWin"][0]
        seg[j]["pos"] = str(int(seg[j]["pos"]) + 1)
    elif corrupt == "drop-eval":
        j = [x for x, e in enumerate(seg) if e["a"] == "WKey" and e["ahead"] == "1" and e["res"] == "Q"][0]
        del seg[j]
    elif corrupt == "intr-look":
        j = [x for x, e in enumerate(seg) if e["a"] == "WIntr"][0]
        seg[j] = dict(seg[j], a="WLook")
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
        elif e.get("intr") == "1":
            # the key whose evaluation took the query cancel: never evaluated to its end, the leaf's last known key
            noid.append(0)
            continue
        elif res == "ERR":
            noid.append(0)
            err = len(noid)
        if e["ahead"] == "1" and res != "Q":
            pending = res
    log = []
    for e in seg:
        log.append("[a |-> \"%s\", ahead |-> %s, res |-> \"%s\", rk |-> %s, n |-> %s, pos |-> %s, sk |-> %s, intr |-> %s]"
                   % (e["a"], e.get("ahead", "0"), e.get("res", ""), e.get("rk", "0"), e.get("n", "0"),
                      e.get("pos", "0"), e.get("skipped", "0"), e.get("intr", "0")))
    return log, noid, rej, err, cov, cap, dist0, len(good)

def covered(ev, need, nk, corrupt):
    # segments: one scan (p) from its Open to its End
    # foreign: another scan (serial p, worker w) logged an event since this scan's previous event
    attached = set()
    segs, cur, last = [], {}, {}
    for n, e in enumerate(ev):
        a = e["a"]
        if a == "Attach":
            attached.add(e["p"])
            continue
        p = e.get("p", e.get("w"))
        for q in cur:
            if q != p:
                last[q] = True
        if a not in ("Open", "Fix", "Sel", "Ret", "Restart", "Dlv", "Again", "End"):
            continue
        if a == "Open":
            cur[p] = [e]
            segs.append(cur[p])
            last[p] = False
        elif p in cur:
            cur[p].append(e)
            if a == "End":
                del cur[p]
        else:
            continue
        e["foreign"] = "1" if last[p] else "0"
        last[p] = False
    def has(g, a, **kv):
        return any(e["a"] == a and all(e.get(x) == y for x, y in kv.items()) for e in g)
    def failed(g):
        return g[-1]["a"] == "End" and g[-1]["err"] == "1"
    def ok(g):
        # a scan ends at its End, or (a join's inner scan, opened again for the next outer row) at its last batch
        if g[-1]["a"] != "End" and not (g[-1]["a"] == "Again" and g[-1]["end"] == "1"):
            return False
        v = g[0]["visit"] == "1"
        if v and g[0]["p"] not in attached:
            return False
        if need == "visit" or need.startswith("inner"):
            return v and not failed(g) and has(g, "Sel")
        if need == "verr":
            return v and has(g, "Sel", err="1")
        if need == "list":
            return not v and not failed(g) and sum(1 for e in g if e["a"] == "Ret") >= 2 and not has(g, "Restart")
        if need == "lerr":
            return not v and failed(g) and has(g, "Dlv")
        if need == "restart":
            return not v and not failed(g) and has(g, "Restart")
        return False
    good = [g for g in segs if ok(g)]
    if need.startswith("inner"):
        seg = good[int(need[5:])]
    else:
        seg = max(good, key=lambda g: sum(1 for e in g if e["a"] == "Sel"))
    seg = [dict(e) for e in seg]
    # the key record of each selected object: a new (leaf, slot) starts a key
    prev, sizes = None, []
    for e in seg:
        if e["a"] != "Sel":
            continue
        key = (e["leaf"], e["slot"])
        first = key != prev
        prev = key
        if e["ks"] == "-1":
            e["ks"] = "1" if first else "0"
        else:
            assert (e["ks"] == "1") == first, e
        if first:
            sizes.append(0)
        sizes[-1] += 1
    full = sizes[:-1] if failed(seg) else sizes
    per = max(sizes)
    assert all(x == per for x in full), sorted(set(sizes))
    nsel = sum(sizes)
    fail = 0
    if failed(seg):
        if seg[0]["visit"] == "1":
            fail = [j for j, e in enumerate([x for x in seg if x["a"] == "Sel"]) if e["err"] == "1"][0] + 1
        else:
            fail = sum(1 for e in seg if e["a"] == "Dlv")
    keys = nk if nk else len(sizes)
    assert keys * per >= nsel
    caps = set(int(e["cap"]) for e in seg if e["a"] == "Ret")
    assert len(caps) == 1, caps
    cap = max(per, (caps.pop() // per) * per)
    if corrupt == "dup-sel":
        j = [x for x, e in enumerate(seg) if e["a"] == "Sel"][1]
        seg.insert(j, dict(seg[j]))
    elif corrupt == "list-in-visit":
        j = [x for x, e in enumerate(seg) if e["a"] == "Sel"][2]
        seg[j]["visit"] = "0"
    elif corrupt == "dlv-after-err":
        j = [x for x, e in enumerate(seg) if e["a"] == "Dlv"][-1]
        seg.insert(j, dict(seg[j]))
    elif corrupt == "drop-ret":
        j = [x for x, e in enumerate(seg) if e["a"] == "Ret"][0]
        del seg[j]
    elif corrupt == "drop-dlv":
        j = [x for x, e in enumerate(seg) if e["a"] == "Dlv"][3]
        del seg[j]
    elif corrupt == "foreign-in-visit":
        j = [x for x, e in enumerate(seg) if e["a"] == "Sel"][2]
        seg[j]["foreign"] = "1"
    elif corrupt:
        sys.exit("unknown corruption " + corrupt)
    keep = ("visit", "ks", "err", "end", "n", "foreign")
    log = ["[a |-> \"%s\", " % e["a"] + ", ".join("%s |-> %s" % (k, e.get(k, "0")) for k in keep) + "]" for e in seg]
    return log, keys, per, cap, fail, len(good), seg

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
elif mode == "covered":
    rest = sys.argv[5:]
    nk = 0
    if rest and rest[0].startswith("nk="):
        nk = int(rest[0][3:])
        rest = rest[1:]
    log, keys, per, cap, fail, ngood, seg = covered(ev, sys.argv[4], nk, rest[0] if rest else "")
    w("%sLog == <<\n  " % name + ",\n  ".join(log) + "\n>>\n")
    w("%sNK == %d\n%sPerKey == %d\n%sCap == %d\n%sFail == {%d}\n" % (name, keys, name, per, name, cap, name, fail))
    cnt = lambda a: sum(1 for e in seg if e["a"] == a)
    sys.stderr.write("%s events=%d visit=%s keys=%d perkey=%d cap=%d fail=%d sel=%d dlv=%d ret=%d restart=%d segments=%d\n"
                     % (name, len(log), seg[0]["visit"], keys, per, cap, fail, cnt("Sel"), cnt("Dlv"), cnt("Ret"), cnt("Restart"), ngood))
else:
    log, noid, rej, err, cov, cap, dist0, ngood = worker(ev, int(sys.argv[4]), sys.argv[6] if len(sys.argv) > 6 else "", sys.argv[5])
    w("%sLog == <<\n  " % name + ",\n  ".join(log) + "\n>>\n")
    base = [0]
    for n in noid:
        base.append(base[-1] + n)
    w("%sNOid == <<" % name + ", ".join(map(str, noid)) + ">>\n%sNK == %d\n%sMaxO == %d\n" % (name, len(noid), name, max(noid) if noid else 0))
    w("%sBase == <<" % name + ", ".join(map(str, base)) + ">>\n")
    w("%sRej == {" % name + ", ".join(map(str, rej)) + "}\n%sErrKey == %d\n%sCov == %s\n%sCap == %d\n%sDist0 == %d\n" % (name, err, name, "TRUE" if cov else "FALSE", name, cap, name, dist0))
    sys.stderr.write("%s events=%d keys=%d rejected=%d errkey=%d cov=%d maxo=%d segments=%d\n" % (name, len(log), len(noid), len(rej), err, cov, max(noid) if noid else 0, ngood))
