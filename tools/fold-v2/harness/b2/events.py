# events.py <model> <raw.log> <out.log> [cp-index] — turn the TLATRACE lines of an instrumented run into the events of
# one model of docs/tla/CBRD-27430-B2 (MAP.md "Trace validation").  Lines of all processes are ordered by
# CLOCK_MONOTONIC; identities are renamed into the model's (client port -> session, binding pointer -> session,
# server pid -> server, descriptor number -> 1..NF, loader thread -> 1..NL).  Prints the constants on stderr.
import re
import sys

model, raw_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
raw = []
for line in open(raw_path, errors="replace"):
    m = re.match(r"TLATRACE (\d+) (\d+) (\d+) (\w+)(.*)", line.strip())
    if m:
        f = dict(kv.split("=", 1) for kv in m.group(5).split())
        raw.append((int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4), f))
raw.sort(key=lambda r: r[0])
out = []


def ev(a, **k):
    out.append((a, k))


def finish(consts):
    with open(out_path, "w") as dst:
        for n, (a, k) in enumerate(out, 1):
            dst.write("TLATRACE seq=%d a=%s p=0 %s\n" % (n, a, " ".join("%s=%s" % kv for kv in k.items())))
    print("# %s events=%d" % (consts, len(out)), file=sys.stderr)


# what every model needs: binding pointer and session thread -> the connection's client port
b2cp = {}      # (pid, binding) -> cp, as of the latest SHandoff
t2cp = {}      # (pid, tid) -> cp, as of the latest SThread


def note(pid, tid, a, f):
    if a == "SHandoff":
        b2cp[(pid, f["b"])] = int(f["cp"])
    elif a == "SThread":
        t2cp[(pid, tid)] = int(f["cp"])


if model == "ConfigPush":
    cp2s, qmap, vmap = {}, {}, {}
    role = {}                    # broker thread -> "D" | "C" | None: whose snapshot comes next
    restarts = changes = owed_change = 0
    broker_pid = None
    brokers = {pid for ns, pid, tid, a, f in raw if a in ("DStart", "CStart")}
    jobs = 0

    def Q(x):
        return qmap[int(x)]

    def V(x):
        x = int(x)
        if x not in vmap:
            vmap[x] = len(vmap)
        return vmap[x]

    for ns, pid, tid, a, f in raw:
        note(pid, tid, a, f)
        if a == "BInit" and pid in brokers:      # the modeled broker's process (another broker of the run logs BInit too)
            if broker_pid is not None:
                restarts += 1
                ev("BRestart")
            broker_pid = pid
        elif a == "AChange":
            if owed_change > 0:
                owed_change -= 1         # already placed before the snapshot that showed it
            else:
                changes += 1
                ev("AChange")
        elif a == "DStart":
            jobs += 1
            cp2s[int(f["cp"])] = jobs
            role[tid] = "D"
            ev("DStart", s=jobs, d=1)
        elif a == "CStart":
            ev("CStart")
        elif a == "CDial":
            role[tid] = "C"
            ev("CDial")
        elif a == "Snap":
            r = role.pop(tid, None)
            if r is None:
                continue                 # the snapshot of a RESET: sent to nobody
            qmap[int(f["seq"])] = len(qmap) + 1
            v = V(f["v"])
            while v > changes:           # the shared memory was written; broker_changer logs after its write
                changes += 1
                owed_change += 1
                ev("AChange")
            ev("DSnap" if r == "D" else "CSnap", q=Q(f["seq"]), v=v)
        elif a == "DSend":
            ev("DSend")
        elif a == "DReply":
            ev("DReply")
        elif a == "DTimeout":
            ev("DTimeout")
        elif a == "CSend":
            ev("CSend", d=1)
        elif a == "CReply":
            ev("CReply", d=1)
        elif a == "CTimeout":
            ev("CTimeout", d=1)
        elif a == "CDone":
            ev("CDone", ok=int(f["ok"]))
        elif a == "SHandoff":
            ev("SHandoff", s=cp2s[int(f["cp"])], q=Q(f["seq"]), v=V(f["v"]))
        elif a == "SRefuse":
            ev("SRefuse", s=cp2s[int(f["cp"])])
        elif a == "SCfgBegin":
            ev("SConfigBegin", d=1, q=Q(f["seq"]))
        elif a == "SWrite":
            ev("SWrite", s=cp2s[b2cp[(pid, f["b"])]], take=int(f["take"]))
        elif a == "SFlag":
            ev("SFlag", s=cp2s[b2cp[(pid, f["b"])]])
        elif a == "SCfgEnd":
            ev("SConfigEnd", d=1)
        elif a == "TClear":
            ev("TClear", s=cp2s[b2cp[(pid, f["b"])]])
        elif a == "TRead":
            ev("TRead", s=cp2s[b2cp[(pid, f["b"])]], q=Q(f["seq"]))
        elif a == "SErase":
            ev("TFinish", s=cp2s[b2cp[(pid, f["b"])]])
    finish("NS=%d ND=1 MaxV=%d MaxRestart=%d" % (max(jobs, 1), max(changes, 1), restarts))

elif model == "AclTable":
    slot = {}                     # loader thread -> l
    edits = 0
    for ns, pid, tid, a, f in raw:
        if a == "FEdit":
            edits += 1
            ev("FEdit", bad=int(f["bad"]))
        elif a == "LStart":
            l = min(set(range(1, 9)) - set(slot.values()))
            slot[(pid, tid)] = l
            ev("LStart", l=l)
        elif a == "LParse":
            ev("LParse", l=slot[(pid, tid)], ok=int(f["ok"]), n=int(f["n"]))
        elif a == "LSwap":
            ev("LSwap", l=slot.pop((pid, tid)))
        elif a == "CCheck":
            ev("CCheck", c=1, failed=int(f["failed"]), n=int(f["n"]))
            ev("CAgain", c=1)
    finish("NL=2 NC=1 MaxF=%d" % max(edits, 1))

elif model == "LogLease":
    procs, sess, used = {}, {}, {}
    NP = len({pid for ns, pid, tid, a, f in raw if a == "LBegin"})
    opened = set()
    maxidx = 1
    for ns, pid, tid, a, f in raw:
        if a == "LBegin":
            p = procs.setdefault(pid, len(procs) + 1)
            k = used.get(p, 0)
            used[p] = k + 1
            s = k * NP + p                       # Proc(s) = ((s - 1) % NP) + 1
            sess[(pid, tid)] = s
            ev("SBegin", s=s)
        elif a == "LTry":
            maxidx = max(maxidx, int(f["idx"]))
            ev("STry", s=sess[(pid, tid)], idx=int(f["idx"]), got=int(f["got"]))
        elif a == "LOpen":
            opened.add(sess[(pid, tid)])
            ev("SOpen", s=sess[(pid, tid)])
        elif a == "LClose":
            if sess.get((pid, tid)) in opened:
                opened.discard(sess[(pid, tid)])
                ev("SClose", s=sess[(pid, tid)])
        elif a == "LRelease":
            ev("SRelease", s=sess[(pid, tid)])
        elif a == "LDone":
            if (pid, tid) in sess:
                ev("SDone", s=sess.pop((pid, tid)))
        elif a == "Crash":
            ev("Crash", p=procs[int(f["pid"])])
    finish("NS=%d NP=%d NI=%d" % (max(used.values()) * NP, NP, maxidx))

elif model == "StatsKill":
    cp2s, fdmap = {}, {}
    reqs = {}                    # s -> [started, finished]
    pubs = {}                    # s -> {(req, q): (started, finished)} of its publications, the latest last
    maxreq = 1

    def F(x):
        return fdmap.setdefault(int(x), len(fdmap) + 1)

    def S(pid, b):
        return cp2s[b2cp[(pid, b)]]

    for ns, pid, tid, a, f in raw:
        note(pid, tid, a, f)
        if a == "SHandoff":
            s = cp2s[int(f["cp"])] = len(cp2s) + 1
            reqs[s], pubs[s] = [0, 0], {}
            ev("SNew", s=s, f=F(f["fd"]))
        elif a == "SPublish":
            s = S(pid, f["b"])
            pubs[s][(f["req"], f["q"])] = tuple(reqs[s])
            ev("SPublish", s=s)
        elif a in ("SReqA", "SReqB"):
            if (pid, tid) not in t2cp:
                continue
            s = cp2s[t2cp[(pid, tid)]]
            reqs[s][0 if a == "SReqA" else 1] += 1
            maxreq = max(maxreq, reqs[s][0])
            ev(a, s=s)
        elif a in ("SCleanup", "SDrain", "SErase"):
            ev(a, s=S(pid, f["b"]))
        elif a == "SClose":
            ev("SClose", s=cp2s[t2cp[(pid, tid)]])
        elif a in ("RBegin", "REnd", "KBegin", "KShut", "KEnd"):
            ev(a)
        elif a == "RRow":
            s = S(pid, f["b"])
            ga, gb = pubs[s].get((f["req"], f["q"]), (-1, -1))
            ev("RRow", s=s, ga=ga, gb=gb)
        elif a == "KPin":
            ev("KPin", s=S(pid, f["b"]))
    finish("NS=%d MaxReq=%d NF=%d" % (len(cp2s), maxreq, max(len(fdmap), 1)))

elif model == "SslAck":
    # one connection: the cp-index'th parked client of the run
    parks = [int(f["cp"]) for ns, pid, tid, a, f in raw if a == "BPark"]
    cp = parks[int(sys.argv[4]) - 1 if len(sys.argv) > 4 else 0]
    ssl = 0
    requested = False
    for ns, pid, tid, a, f in raw:
        if "cp" not in f or int(f["cp"]) != cp:
            continue
        if a == "BPark":
            ssl = int(f["ssl"])
            ev("BPark")
        elif a == "BPeeked":
            if not ssl:
                ev("BPeeked")
        elif a == "BPeekTimeout":
            ev("BPeekTimeout")
        elif a == "BDequeue":
            ev("BDequeue")
        elif a == "BDial":
            ev("BDial", up=int(f["up"]))
        elif a == "BSlot":
            ev("BSlot", got=int(f["got"]))
        elif a in ("SHandoff", "SRefuse"):
            if not requested:
                requested = True
                ev("BRequest", sent=1)
            ev("SHandle", ok=1 if a == "SHandoff" else 0)
        elif a == "DReply":
            ev("BAck" if int(f["ack"]) else "BReject")
        elif a == "DTimeout":
            if int(f["sent"]) and not requested:
                ev("BRequest", sent=1)
            ev("BReplyTimeout" if int(f["sent"]) else "BRequest", **({} if int(f["sent"]) else {"sent": 0}))
    finish("Ssl=%s" % ("TRUE" if ssl else "FALSE"))
else:
    raise SystemExit("unknown model " + model)
