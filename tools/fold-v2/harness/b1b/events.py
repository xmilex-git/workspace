# events.py <raw.log> <out.log> — merge the broker's and the server's TLATRACE lines by CLOCK_MONOTONIC and rename
# their identities into the model's: jobs in dispatch order -> threads 1..NT, tokens -> the admitted jobs in order,
# session ids -> 1..NS in creation order. Synthesizes the steps the build takes inside one logged evaluation
# (see docs/tla/CBRD-27430-B1b/MAP.md "Trace validation"). Prints the constants on stderr.
import re
import sys

raw = []
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"TLATRACE (\d+) (\d+) (\w+)(.*)", line.strip())
    if m:
        f = dict(kv.split("=", 1) for kv in m.group(4).split())
        raw.append((int(m.group(1)), m.group(3), f))
raw.sort(key=lambda r: r[0])

out = []                 # [action, fields]
jobs = 0
cur_job = 0
admitted = []            # jobs in admission order
tok2t = {}
sid2s = {}
info = {}                # t -> dict(sid=presented, res=, auth=)
start_ev = {}            # t -> index of its BStart in out
pend_wx = {}
pend_exec = {}
after_close = {}
woke = {}
rejected = {}
pend_try = None
pass_scans = 0
reqs = {}
stats = {"resets": 0, "passes": 0}


def ev(a, **k):
    out.append([a, k])


def T(f):
    tok = int(f["tok"])
    if tok not in tok2t:
        tok2t[tok] = admitted[len(tok2t)]
    return tok2t[tok]


def flush_wx(t):
    if pend_wx.get(t):
        pend_wx[t] = False
        ev("Wx", t=t)


def flush_try():
    global pend_try
    if pend_try is not None:
        ev("CTCas", t=pend_try, ok=0)
        pend_try = None


for idx, (ns, a, f) in enumerate(raw):
    if a == "BStart":
        jobs += 1
        cur_job = jobs
        info[cur_job] = {"sid": 0, "res": "none", "auth": 1}
        start_ev[cur_job] = len(out)
        ev("BStart", t=cur_job)
    elif a == "BTop":
        ev("BTop", full=int(f["full"]))
        if f["full"] == "0":
            admitted.append(cur_job)
    elif a == "BSlot":
        ev("BSlot")
        admitted.append(cur_job)
    elif a in ("BTry", "BWatch", "BHint", "BTimeout"):
        ev(a)
    elif a == "BTryRep":
        ev(a, rep=int(f["rep"]))
    elif a == "CStart":
        if f["op"] == "reset":
            stats["resets"] += 1
            ev("EReset")
        ev("CStart", op=f["op"])
    elif a == "TCasTry":
        flush_try()
        pend_try = T(f)
    elif a == "TCasOk":
        pend_try = None
        ev("CTCas", t=T(f), ok=1)
    elif a == "TEnd":
        flush_try()
    elif a == "TWake":
        ev("CTWake")
    elif a in ("CW1", "CWX"):
        ev(a)
    elif a == "CWScan":
        ev(a, idle=int(f["idle"]))
    elif a == "RMark":
        ev("CRMark", t=T(f))
    elif a == "RCas":
        ev("CRCas", t=T(f))
    elif a == "XScan":
        if pass_scans == 0:
            for ns2, a2, f2 in raw[idx:]:
                if a2 == "XEnd":
                    break
                if a2 == "XScan":
                    ev("Timeout", s=sid2s[int(f2["sid"])])
        pass_scans += 1
        ev("XScan", s=sid2s[int(f["sid"])])
    elif a == "XRecheck":
        ev("XRecheck", s=sid2s[int(f["sid"])], exp=int(f["exp"]))
    elif a == "XTear":
        ev("XTear", s=sid2s[int(f["sid"])])
    elif a == "XEnd":
        if pass_scans:
            stats["passes"] += 1
            ev("XEndPass")
        pass_scans = 0
    else:
        t = T(f)
        if a not in ("Wx", "Wch"):
            flush_wx(t)
        if a == "Create":
            if f["ok"] != "1":
                raise SystemExit("a new session's boot failed: not a modelled run")
            sid2s[int(f["sid"])] = len(sid2s) + 1
            ev("Create", t=t, s=sid2s[int(f["sid"])])
        elif a == "Claim":
            info[t]["sid"] = sid2s.get(int(f["sid"]), 0)
            info[t]["res"] = f["res"]
            if f["res"] == "ok":
                ev("Claim", t=t, ok=1)
            elif f["res"] in ("secret", "busy"):
                rejected[t] = True
                ev("Claim", t=t, ok=0)
        elif a == "Swap":
            ev("Swap", t=t)
        elif a == "Auth":
            info[t]["auth"] = int(f["ok"])
            if f["ok"] != "1":
                rejected[t] = "auth"
            ev("Auth", t=t, ok=int(f["ok"]))
        elif a == "Top":
            ev("Top", t=t, clean=int(f["clean"]))
        elif a == "Rst":
            ev("Rst", t=t, rreq=int(f["rreq"]))
        elif a == "Wch":
            ev("Wch", t=t, go=int(f["go"]))
            pend_wx[t] = f["go"] == "1"
        elif a == "Wx":
            pend_wx[t] = False
            ev("Wx", t=t)
        elif a == "WakeSeen":
            woke[t] = True
            ev("WakeSeen", t=t)
        elif a == "Rd":
            if woke.get(t):
                pass
            elif f["ret"] == "0":
                ev("Request", t=t, ok=int(f["ok"]))
                pend_exec[t] = f["ok"] == "1"
                if f["ok"] == "1":
                    reqs[t] = reqs.get(t, 0) + 1
            else:
                ev("ClientClose", t=t)
        elif a == "Ret":
            if pend_exec.get(t):
                pend_exec[t] = False
                ev("Exec", t=t)
                after_close[t] = f["keep"] == "0"
        elif a == "Finish":
            if not rejected.get(t):
                if after_close.get(t):
                    ev("Top", t=t, clean=0)
                    ev("ClientClose", t=t)
                ev("Finish", t=t, yld=int(f["yld"]))
        elif a == "End":
            ev("EndSession", t=t)
        elif a == "Free":
            if rejected.get(t) is not True:
                ev("FreeConn", t=t)
        elif a == "Deact":
            if rejected.get(t) is not True:
                ev("Deact", t=t)
        elif a == "Send":
            ev("Send", t=t)
        else:
            raise SystemExit("unknown event " + a)

for t, i in start_ev.items():
    d = info[t]
    cred = "badsecret" if d["res"] == "secret" else "badauth" if d["auth"] == 0 else "good"
    out[i][1].update(s=d["sid"], c=cred)

dst = open(sys.argv[2], "w")
for n, (a, k) in enumerate(out, 1):
    dst.write("TLATRACE seq=%d a=%s p=0 %s\n" % (n, a, " ".join("%s=%s" % kv for kv in k.items())))
print("# NT=%d NS=%d MaxReq=%d MaxPass=%d MaxResets=%d events=%d" % (
    max(jobs, 1), max(len(sid2s), 1), max(list(reqs.values()) + [1]), stats["passes"], stats["resets"], len(out)),
    file=sys.stderr)
