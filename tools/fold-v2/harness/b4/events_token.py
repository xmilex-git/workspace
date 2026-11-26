# events_token.py <raw.log> <out.log> <dbA> <dbB> — order the TLATRACE lines of cub_broker, the two servers and the
# run script by CLOCK_MONOTONIC and rename them into TokenTable's steps (docs/tla/CBRD-27430-B4/MAP.md "Trace
# validation"). A session's token becomes the lowest model token no live session of any server has; client ports
# become the lowest free model port; a session id is 0 (a driver that is asked for none) or 1, a request's is 0 (none), 1 (the session's) or 2
# (another). Prints the constants on stderr.
import re
import sys

raw = []
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"TLATRACE (\d+) (\d+) (\w+)(.*)", line.strip())
    if m:
        f = dict(kv.split("=", 1) for kv in m.group(4).split() if "=" in kv)
        raw.append((int(m.group(1)), m.group(3), f))
raw.sort(key=lambda r: r[0])
DB = {sys.argv[3]: 1, sys.argv[4]: 2}

out = []


def ev(a, **k):
    out.append((a, k))


# the session's login line, by (db, real token), in order of appearance
logins = {}
for _, a, f in raw:
    if a == "SLogin" and f["db"] in DB:
        logins.setdefault((DB[f["db"]], int(f["tok"])), []).append((int(f["sid"]), int(f["req"])))
ends_later = [(i, DB[f["db"]], int(f["tok"])) for i, (_, a, f) in enumerate(raw) if a == "End" and f["db"] in DB]
cancels = [(i, DB[f["db"]], int(f["tok"]), int(f["hit"])) for i, (_, a, f) in enumerate(raw) if a == "SCancel" and f["db"] in DB]

up = {1: True, 2: True}
started = {1: False, 2: False}
tokmap = {}        # (db, real token) -> model token of the live incarnation
sess = {}          # (db, t) -> (model port, real sid, req)
port_of = {}       # real port -> model port, of live sessions
ch = {1: False, 2: False}
chgen = {1: 0, 2: 0}
skipdrop = {1: False, 2: False}
bstarted = False
scan = False
todo = set()
jobdb, jobport = 1, 1
maxslots = 1
cnt = dict(conn=0, cr=0, br=0, k=0, h=0, can=0)
nt, np_ = 1, 1
pending_look = None


def free_port(real):
    used = {v[0] for v in sess.values()}
    p = 1
    while p in used:
        p += 1
    return p


def end_session(d, t):
    sess.pop((d, t), None)


for i, (ns, a, f) in enumerate(raw):
    d = DB.get(f.get("db", ""), 0)
    if a == "BStart":
        maxslots = int(f["max"])
        if bstarted:
            ev("BRestart")
            cnt["br"] += 1
            ch = {1: False, 2: False}
            skipdrop = {1: False, 2: False}
            scan = False
        bstarted = True
    elif a == "SStart" and d:
        if started[d]:
            ev("SRestart", e=d)
            up[d] = True
        started[d] = True
    elif a == "XCrash" and d:
        ev("SCrash", e=d)
        cnt["cr"] += 1
        up[d] = False
        for k in [k for k in sess if k[0] == d]:
            del sess[k]
        for k in [k for k in tokmap if k[0] == d]:
            del tokmap[k]
    elif a in ("XHang", "XUnhang") and d:
        ev("Hang", e=d)
        cnt["h"] += 1
    elif a == "DStart" and d:
        jobdb, jobport = d, free_port(int(f["port"]))
        scan = f["scan"] == "1"
        todo = {1, 2} if scan else set()
        ev("DStart", d=d, port=jobport, scan=int(scan))
        cnt["conn"] += 1
        np_ = max(np_, jobport)
    elif a == "Dial" and d:
        res = f["res"]
        if scan and d in todo:
            todo.discard(d)
            ev("DScan", e=d, res=res)
        elif not scan:
            ev("DDial", res=res)
        else:
            continue
        if res == "ok":
            ch[d] = True
            chgen[d] = int(f["gen"])
            skipdrop[d] = False
    elif a == "DScanEnd":
        for e in sorted(todo):
            ev("DScan", e=e, res="none")
        todo = set()
        ev("DScanEnd")
        scan = False
    elif a == "DWait":
        ev("DWait")
    elif a == "DGiveUp":
        ev("DGiveUp")
    elif a == "DSendOk" and d:
        tok = int(f["tok"])
        lg = logins.get((d, tok), [])
        sid, req = lg.pop(0) if lg else (0, 0)
        t = 1
        while any(k[1] == t for k in sess):
            t += 1
        nt = max(nt, t)
        tokmap[(d, tok)] = t
        sess[(d, t)] = (jobport, sid, req)
        ev("DSendOk", t=t, sid=1 if req else 0)
    elif a == "DSendNo":
        ev("DSendNo")
    elif a == "DSendFail" and d:
        if ch[d]:
            if not up[d]:
                ev("DSendDead")
            else:
                ev("Kill", e=d)
                cnt["k"] += 1
                ev("DSendNo")
            ch[d] = False
            skipdrop[d] = True
        else:
            ev("DSendNo")
    elif a == "RDrop" and d:
        if f.get("pub", "1") != "1" or int(f["gen"]) != chgen[d] or not ch[d]:
            continue           # a channel that was never published, or one a failed request already took down
        ch[d] = False
        if up[d]:
            ev("Kill", e=d)
            cnt["k"] += 1
        else:
            ev("RDie", e=d)
    elif a == "End" and d:
        t = tokmap.get((d, int(f["tok"])))
        if t is not None and (d, t) in sess:
            ev("SEnd", e=d, t=t)
            end_session(d, t)
    elif a == "SFin" and d:
        tok = int(f["tok"])
        t = tokmap.get((d, tok))
        if t is None or (d, t) not in sess:
            continue
        if any(j > i and dd == d and tt == tok for j, dd, tt in ends_later):
            continue           # the broker's End stands for it
        ev("SEnd", e=d, t=t)
        end_session(d, t)
    elif a == "CnLook":
        cands = int(f["cands"])
        pending_look = None
        if cands == 0:
            continue
        tok = int(f["tok"])
        tdb = DB.get(f["db"], 0)
        keys = [k for k in tokmap if k[1] == tok and (tdb == 0 or k[0] == tdb)]
        if not keys:
            continue
        t = tokmap[keys[0]]
        q = 0
        if int(f["port"]) != 0:
            q = sess[(keys[0][0], t)][0]
        pending_look = dict(t=t, q=q, db=keys[0][0], tok=tok, cands=cands)
        cnt["can"] += 1
        if cands > 1:
            ev("CnLook", t=t, q=q, s=0, refused=1)
            pending_look = None
    elif a == "CnSend" and d and pending_look is not None:
        pl = pending_look
        pending_look = None
        port, sid, req = sess.get((pl["db"], pl["t"]), (0, 0, 0))
        has = f["has"] == "1"
        same = has and int(f["sid"]) == sid
        if req:
            s = 1 if same else (2 if has else 0)
        else:
            s = 0 if (same or not has) else 2
        hit = next((h for j, dd, tt, h in cancels if j > i and dd == d and tt == pl["tok"]), 0)
        ev("CnLook", t=pl["t"], q=pl["q"], s=s, refused=0)
        ev("CnSend", hit=hit)

with open(sys.argv[2], "w") as o:
    for n, (a, k) in enumerate(out):
        o.write("TLATRACE seq=%d a=%s p=0%s\n" % (n, a, "".join(" %s=%s" % kv for kv in k.items())))
print("ND=2 NT=%d NP=%d NSid=2 MaxSlots=%d MaxConn=%d MaxCrash=%d MaxBR=%d MaxKill=%d MaxHang=%d MaxCancel=%d"
      % (nt, max(np_, 2), maxslots, cnt["conn"], cnt["cr"], cnt["br"], cnt["k"], cnt["h"], cnt["can"]), file=sys.stderr)
