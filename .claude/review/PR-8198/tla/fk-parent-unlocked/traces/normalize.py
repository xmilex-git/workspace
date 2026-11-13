#!/usr/bin/env python3
"""normalize.py <raw.log> <out.log>: rename tran indexes, OIDs and MVCCIDs of a raw TLATRACE log of the
instrumented fbaae2592 build to the model's names (d, w1, w2; slots 1..; masks), and print NS."""
import re, sys
raw = []
for line in open(sys.argv[1]):
    i = line.find("TLATRACE")
    if i < 0:
        continue
    f = dict(t.split("=", 1) for t in line[i + 8:].split())
    raw.append(f)
raw.sort(key=lambda f: int(f["seq"]))
# child rows: OIDs that got an FK entry for the key, or that the parent's phases name
oids = set()
for f in raw:
    if f["a"] in ("WInsEntry", "DP2", "DP3", "DP3Read"):
        oids.add(f["s"])
    if f["a"] == "DCollect" and f["coll"] != "-":
        oids.update(x.split("#")[0] for x in f["coll"].split(","))
key = lambda o: tuple(int(x) for x in o.split("|"))
slot = {o: n + 1 for n, o in enumerate(sorted(oids, key=key))}
# a child UPDATE stamps a row that is a child: keep WUpdStamp/WInsHeap only on those OIDs
keep = []
for f in raw:
    if f["a"] in ("WInsHeap", "WUpdStamp", "WChkPass", "WChkFail") and f["s"] not in slot:
        continue
    keep.append(f)
dtran = next(f["p"] for f in keep if f["a"] == "DMark")
names, mv = {dtran: "d"}, {}
for f in keep:
    if f["a"] in ("Commit", "Abort"):
        continue
    if f["p"] not in names:
        names[f["p"]] = "w%d" % (len(names))
    if "mv" in f:
        mv[f["mv"]] = names[f["p"]]
out, ended, seen = [], set(), set()
for f in keep:
    p = f["p"]
    if f["a"] in ("Commit", "Abort"):
        if p not in names or p not in seen or p in ended:
            continue
        a = ("DCommit" if f["a"] == "Commit" else "DFail") if p == dtran else ("W" + f["a"])
        ended.add(p)
        out.append({"a": a, "p": names[p]})
        continue
    if p in ended:
        continue
    seen.add(p)
    e = {"a": f["a"], "p": names[p]}
    if f["a"] == "DFail":
        ended.add(p)
    if "s" in f and f["a"] != "DFail":
        e["s"] = slot[f["s"]]
    if f["a"] == "DCollect":
        m = ins = 0
        if f["coll"] != "-":
            for x in f["coll"].split(","):
                o, w = x.split("#")
                m |= 1 << (slot[o] - 1)
                if w != "0":
                    ins |= 1 << (slot[o] - 1)
        e.update(coll=m, insr=ins, cc=int(f["cc"]))
    if f["a"] in ("DP2", "DRCheck"):
        e["w"] = "none" if f["w"] == "0" else mv[f["w"]]
    if f["a"] == "DP2":
        e["o"] = 1 if f["skip"] == "other" else 0
    if f["a"] == "DRCheck":
        e["found"] = "none" if f["found"].split("|")[1] == "-1" else "child"
    if f["a"] == "DP3":
        e["skip"] = int(f["skip"])
    if f["a"] == "DP3Read":
        e["kept"] = int(f["kept"])
    out.append(e)
with open(sys.argv[2], "w") as o:
    for n, e in enumerate(out):
        o.write("TLATRACE seq=%d " % n + " ".join("%s=%s" % kv for kv in e.items()) + "\n")
print("NS=%d writers=%s" % (len(slot), sorted(v for v in names.values() if v != "d")))
