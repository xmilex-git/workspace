# events_domain.py <raw.log> <out.log> — order a server's TLATRACE lines by CLOCK_MONOTONIC and rename them into
# DomainCache's steps (docs/tla/CBRD-27430-B4/MAP.md "Trace validation"). A client context (csc) from its login
# to the release of its lists holds the lowest free slot; a class is numbered by its OID in order of appearance;
# a MOP's address is the lowest model address no live MOP and no other node holds. The lines of contexts that
# never logged in, and FindOid of classes no session resolved with a MOP, are dropped.
# Prints the constants on stderr, and walked_dead: the FindOid walks that read more MOP nodes than the live
# workspaces put into the process lists (a node of an ended workspace was read).
import re
import sys

raw = []
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"TLATRACE (\d+) (\d+) (\w+)(.*)", line.strip())
    if m:
        f = dict(kv.split("=", 1) for kv in m.group(4).split() if "=" in kv)
        raw.append((int(m.group(1)), m.group(3), f))
raw.sort(key=lambda r: r[0])

out = []


def ev(a, **k):
    out.append((a, k))


resolved = {f["oid"] for _, a, f in raw if a.startswith("Resolve")}
slot = {}          # csc -> s
st = {}            # s -> "run" | "kept" | "end1" | "end2"
inc = {}           # s -> sessions the slot ran
cls = {}           # oid -> c
maddr = {}         # (s, c) -> (model address, real pointer)
node_addr = {}     # real pointer of a process-list node -> model address
dead_ptrs = set()  # MOP pointers of ended workspaces
owner = {}         # real MOP pointer -> s, of live workspaces
ns_max, na_max, walked_dead = 0, 1, 0
proc_nodes = []    # the slot of each MOP node put into the process lists, None once its workspace ended


def c_of(oid):
    if oid not in cls:
        cls[oid] = len(cls) + 1
    return cls[oid]


def mop(s, c, ptr):
    global na_max
    if (s, c) in maddr:
        return
    live = {a for a, _ in maddr.values()}
    if ptr in node_addr and node_addr[ptr] not in live:
        a = node_addr[ptr]
    else:
        a = 1
        while a in live or a in node_addr.values():
            a += 1
    maddr[(s, c)] = (a, ptr)
    owner[ptr] = s
    dead_ptrs.discard(ptr)
    na_max = max(na_max, a)
    ev("Mop", s=s, c=c, addr=a)


# a context's workspace is made by its login (db_restart_ex), whose resolves are logged before the login's own
# line: the context begins at its first line when a login line of it follows before its lists are released
def logs_in(i, csc):
    for _, a2, f2 in raw[i + 1:]:
        if f2.get("csc") == csc and a2 in ("Begin", "FreeLists"):
            return a2 == "Begin"
    return False


for i, (ns, a, f) in enumerate(raw):
    csc = f.get("csc", "(nil)")
    if a == "Begin" and csc in slot:
        continue
    if a == "Begin" or (a.startswith("Resolve") and csc not in slot and csc != "(nil)" and logs_in(i, csc)):
        s = 1
        while s in st:
            s += 1
        slot[csc] = s
        st[s] = "run"
        inc[s] = inc.get(s, 0) + 1
        ns_max = max(ns_max, s)
        ev("Begin", s=s)
        if a == "Begin":
            continue
    if a == "FindOid":
        if f["oid"] not in resolved and f["mops"] == "0":
            continue
        s = slot.get(csc, 0)
        t = s if s and st.get(s) == "run" else 0
        if int(f["mops"]) > sum(1 for o in proc_nodes if o is not None):
            walked_dead += 1
        ev("FindOid", t=t, c=c_of(f["oid"]), mops=int(f["mops"]))
        continue
    if csc not in slot:
        continue
    s = slot[csc]
    if a == "Resume":
        st[s] = "run"
        ev("Resume", s=s)
    elif a == "Yield":
        st[s] = "kept"
        ev("Yield", s=s)
    elif a == "EndRollback":
        if f["xa"] == "1":
            ev("Tran", s=s, x="xa")
        st[s] = "end1"
        ev("EndRollback", s=s)
    elif a == "Retire":
        if st[s] == "kept":
            st[s] = "end1"
            ev("Expire", s=s)
    elif a == "WsFinal":
        if st[s] != "end1":
            continue
        st[s] = "end2"
        proc_nodes = [None if o == s else o for o in proc_nodes]
        for (ss, c), (addr, ptr) in list(maddr.items()):
            if ss == s:
                del maddr[(ss, c)]
                owner.pop(ptr, None)
                dead_ptrs.add(ptr)
        ev("WsFinal", s=s)
    elif a == "FreeLists":
        if st[s] != "end2":
            continue
        del st[s]
        del slot[csc]
        ev("FreeLists", s=s)
    elif a == "ResolveSess":
        if st[s] != "run":
            continue
        c = c_of(f["oid"])
        mop(s, c, f["mop"])
        ev("ResolveSess", s=s, c=c, ins=int(f["ins"]))
    elif a in ("ResolveProc", "ResolveProcHit"):
        if st[s] != "run":
            continue
        c = c_of(f["oid"])
        mop(s, c, f["mop"])
        if a == "ResolveProc":
            node_addr[f["mop"]] = maddr[(s, c)][0]
            proc_nodes.append(s)
        ev("ResolveProc", s=s, c=c, ins=1 if a == "ResolveProc" else 0)

with open(sys.argv[2], "w") as o:
    for n, (a, k) in enumerate(out):
        o.write("TLATRACE seq=%d a=%s p=0%s\n" % (n, a, "".join(" %s=%s" % kv for kv in k.items())))
print("NS=%d NC=%d NA=%d MaxInc=%d walked_dead=%d" % (max(ns_max, 1), max(len(cls), 1), na_max, max(inc.values() or [1]), walked_dead),
      file=sys.stderr)
