# events.py <raw.log> <out.log> — order the server's TLATRACE lines by CLOCK_MONOTONIC and rename them into the
# model's: a session thread (one per driver connection) takes the lowest free session slot, or the slot whose
# kept client context it resumes; client types and HA states get the model's names. Events of threads that are no
# folded session (CS clients, the changemode request's worker apart from its HA steps) are dropped. Steps the
# build takes inside one logged evaluation are synthesized (docs/tla/CBRD-27430-B3/MAP.md "Trace validation").
# Prints the constants on stderr.
import re
import sys

TY = {4: "RW", 5: "RO", 6: "SO", 11: "RWR"}
HA = {0: "idle", 1: "active", 2: "tba", 3: "standby", 4: "tbs", 5: "maint"}
CLS = {"network_interface_cl.c": "bnd", "query_executor.c": "exe", "serial.c": "ser"}

raw = []
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"TLATRACE (\d+) (\d+) (\w+)(.*)", line.strip())
    if m:
        f = dict(kv.split("=", 1) for kv in m.group(4).split())
        raw.append((int(m.group(1)), m.group(3), f))
raw.sort(key=lambda r: r[0])

sess_tids = {int(f["tid"]) for _, a, f in raw if a == "AdmitIn"}
# does a thread's registration resume a kept context, and does its unregistration take the server to standby
reg = {int(f["tid"]): f for _, a, f in raw if a == "Register"}
leave_y = {int(f["tid"]): int(f["y"]) for _, a, f in raw if a == "Leave"}

out = []
slot = {}          # tid -> s
free = []          # freed slots
kept = {}          # session id -> the slot holding its kept context
sid = {}           # tid -> session id
nslot = 0
st = {}            # tid -> "adm" | "boot" | "idle" | "tran" | "end0" | "gone"
transit = set()    # session tids whose Leave was written at their LeaveTransit
ginit = 0
seen_session = False
hb_seen = False
types, kinds = set(), set()


def ev(a, **k):
    out.append([a, k])


def begin(tid):
    if st[tid] == "idle":
        ev("Begin", s=slot[tid])
        st[tid] = "tran"


for ns, a, f in raw:
    tid = int(f["tid"])
    if tid not in sess_tids:
        if not seen_session and not hb_seen and a in ("GateDis", "GateEn", "Promote1", "Promote2"):
            if a in ("GateDis", "GateEn"):
                ginit = 1 if a == "GateDis" else 0  # the boot (idle -> active, read_only): the model's Init
        elif a == "Demote1":
            ev("Demote1")
        elif a == "Demote2":
            ev("Demote2", moved=1 if int(f["st"]) == 3 else 0)
        elif a in ("Promote1", "Promote2", "Maint", "GateDis", "GateEn"):
            ev(a)
        if a in ("Demote1", "Maint"):
            hb_seen = True
        continue
    seen_session = True
    if a == "AdmitIn":
        r = reg.get(tid)
        if r is not None and int(r["resumed"]) == 1:
            s = kept.pop(int(r["sid"]))             # the slot of the session whose kept context it resumes
        elif free:
            s = free.pop(0)
        else:
            nslot += 1
            s = nslot
        slot[tid] = s
        st[tid] = "adm"
        t = TY[int(f["type"])]
        types.add(t)
        ev("Connect", s=s, t=t)
        ev("Admit", s=s, h=HA[int(f["ha"])], d=int(f["d"]), rej=0)
        continue
    s = slot[tid]
    if a == "Admit":
        assert out[-1][0] == "Admit" and out[-1][1]["s"] == s, "an event between AdmitIn and Admit"
        out[-1][1]["rej"] = int(f["rej"])
        st[tid] = "off" if int(f["rej"]) else "boot"
        if int(f["rej"]):
            free.append(s)
    elif st[tid] == "boot":
        if a == "Register":
            ok = int(f["ok"])
            ev("Register", s=s, ok=ok, retry=int(f["retry"]), resumed=int(f["resumed"]), cnt=int(f["cnt"]), base=int(f["base"]))
            st[tid] = "idle" if ok else "off"
            sid[tid] = int(f["sid"])
            if not ok:
                free.append(s)
        # else: the boot's own raise, checks and commits, inside the Register step
    elif st[tid] == "end" and a in ("End0", "End1", "End2", "SrvChk"):
        pass                                        # the rollback of a connection that is closing, inside Leave
    elif a == "MBegin":
        begin(tid)
        ev("MBegin", s=s, cnt=int(f["cnt"]))
    elif a == "MEnd":
        ev("MEnd", s=s, cnt=int(f["cnt"]))
    elif a == "ClRef":
        begin(tid)
        kinds.add("cl")
        ev("Write", s=s, c="cl", out="cl")
    elif a == "SrvChk":
        if st[tid] == "end0":
            continue                                # the commit's own check of a transaction that wrote
        begin(tid)
        c = CLS[f["f"]]
        kinds.add(c)
        ev("Write", s=s, c=c, out="sv" if int(f["ref"]) else "ok")
    elif a == "End0":
        begin(tid)
        st[tid] = "end0"
    elif a == "End1":
        begin(tid)
        ev("End1", s=s, hu=int(f["hu"]), base=int(f["base"]))
        st[tid] = "c2"
    elif a == "End2":
        ev("End2", s=s, h=HA[int(f["ha"])], d=int(f["d"]), r=int(f["r"]), roc=int(f["roc"]))
        st[tid] = "end" if int(f["r"]) else "idle"
    elif a == "LeaveTransit":
        y = leave_y[tid]
        ev("Leave", s=s, y=y, tr=1)
        transit.add(tid)
        if y:
            kept[sid[tid]] = s
        else:
            free.append(s)
        st[tid] = "gone"
    elif a == "GateDis":
        ev("GateDis")                               # the unregistering session's logtb_disable_update
    elif a == "Leave":
        if tid not in transit:
            y = int(f["y"])
            ev("Leave", s=s, y=y, tr=0)
            if y:
                kept[sid[tid]] = s
            else:
                free.append(s)
            st[tid] = "gone"
    else:
        raise SystemExit("unknown event " + a)

with open(sys.argv[2], "w") as o:
    for n, (a, k) in enumerate(out):
        o.write("TLATRACE seq=%d a=%s p=0 %s\n" % (n, a, " ".join("%s=%s" % kv for kv in k.items())))
sys.stderr.write("NS=%d GInit=%d events=%d types=%s sites=%s\n" % (max(nslot, 1), ginit, len(out), ",".join(sorted(types)), ",".join(sorted(kinds))))
