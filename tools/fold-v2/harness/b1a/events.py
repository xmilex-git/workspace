# events.py <raw.log> [<out.log>] — merge the broker's and the server's TLATRACE lines by CLOCK_MONOTONIC and
# rename their identities into the model's: channel generations / server channel ids -> conn (dial order = accept
# order), tokens -> the job whose HANDOFF the server read (FIFO per conn), transaction indices -> 1..NT.
# Writes "TLATRACE seq=<n> a=<Action> p=0 k=v..." lines for tools/tla/trace2tla and prints the constants.
import re
import sys

raw = []
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"TLATRACE (\d+) (\d+) (\w+)(.*)", line.strip())
    if m:
        f = dict(kv.split("=", 1) for kv in m.group(4).split())
        raw.append((int(m.group(1)), int(m.group(2)), m.group(3), f))
raw.sort(key=lambda r: r[0])

brk_inc = 1
gen2c = {}            # (broker inc, gen) -> conn
dials = 0
srv2c = {}            # server channel id -> conn
accepts = 0
jobs = 0
cur_job = 0
send_q = {}           # conn -> [job] HANDOFFs sent, FIFO
recv_job = {}         # conn -> job of the HANDOFF the server is handling
tok2s = {}
trans = {}
last_cancel_c = 0
out = []
stats = {"restart": 0, "timeout": 0, "cancel": 0, "stop": False}


def conn_of_gen(g):
    return gen2c[(brk_inc, int(g))]


def ev(a, **k):
    out.append((a, k))


for ns, pid, a, f in raw:
    if a == "DStart":
        jobs += 1
        cur_job = jobs
        ev("DStart", j=jobs)
    elif a == "DGetCh":
        if "pub" in f:
            ev("DGetCh", kind="pub", c=conn_of_gen(f["pub"]))
        elif "dial" in f:
            dials += 1
            gen2c[(brk_inc, int(f["dial"]))] = dials
            ev("DGetCh", kind="dial", c=dials)
        else:
            ev("DGetCh", kind="nosrv", c=0)
    elif a in ("DHello", "DResync"):
        ev(a, c=conn_of_gen(f["gen"]))
    elif a == "DDialFail":
        stats["timeout"] += int(f["to"])
        ev(a, to=int(f["to"]))
    elif a == "DAdmit":
        ev(a, ok=int(f["ok"]))
    elif a == "DSend":
        c = conn_of_gen(f["gen"])
        if int(f["ok"]):
            send_q.setdefault(c, []).append(cur_job)
        ev(a, ok=int(f["ok"]))
    elif a == "DWait":
        if f["op"] == "timeout":
            stats["timeout"] += 1
        ev(a, op=f["op"])
    elif a == "RRecv":
        c = conn_of_gen(f["gen"])
        k = {"c": c, "op": f["op"], "tok": int(f["tok"])}
        ev(a, **k)
    elif a in ("RDie", "RDrop"):
        ev(a, c=conn_of_gen(f["gen"]))
    elif a == "CnLook":
        stats["cancel"] += 1
        ev(a, c=conn_of_gen(f["gen"]), tok=int(f["tok"]))
    elif a == "CnSend":
        ev(a, c=conn_of_gen(f["gen"]) if f["gen"] != "0" else 0)
    elif a == "BRestart":
        brk_inc += 1
        stats["restart"] += 1
        ev(a)
    elif a == "SAccept":
        accepts += 1
        srv2c[int(f["ch"])] = accepts
        ev(a, c=accepts)
    elif a == "SRecv":
        c = srv2c[int(f["ch"])]
        if f["op"] == "HANDOFF":
            recv_job[c] = send_q[c].pop(0)
        if f["op"] == "CANCEL":
            last_cancel_c = c
        ev(a, c=c, op=f["op"])
    elif a == "SHCheck":
        ev(a, c=srv2c[int(f["ch"])], ok=int(f["ok"]))
    elif a == "SHReg":
        c = srv2c[int(f["ch"])]
        if "tok" in f:
            tok2s[int(f["tok"])] = recv_job[c]
            ev(a, c=c, refused=0, tok=int(f["tok"]))
        else:
            ev(a, c=c, refused=1, tok=0)
    elif a in ("SHAck", "SHSpawn"):
        k = {"c": srv2c[int(f["ch"])], "s": tok2s[int(f["tok"])]}
        if a == "SHAck":
            k["ok"] = int(f["ok"])
        ev(a, **k)
    elif a == "CLook":
        ev("SCancelLook", c=last_cancel_c, found=int(f["found"]), tran=int(f["tran"]))
    elif a == "CInt":
        ev("SCancelInt", c=last_cancel_c)
    elif a == "SResync":
        ev(a, c=srv2c[int(f["ch"])], n=int(f["n"]))
    elif a == "SEof":
        ev(a, c=srv2c[int(f["ch"])])
    elif a == "SLogin":
        t = int(f["tran"])
        trans.setdefault(t, len(trans) + 1)
        ev(a, s=tok2s[int(f["tok"])], x=trans[t])
    elif a in ("SEnd", "SClean", "SErase", "SSendEnd", "SClose"):
        ev(a, s=tok2s[int(f["tok"])])
    elif a == "SPick":
        ch = int(f["ch"])
        ev(a, s=tok2s[int(f["tok"])], c=srv2c.get(ch, 0) if ch else 0)
    elif a.startswith("Stop"):
        stats["stop"] = True
        ev(a)
    else:
        raise SystemExit("unknown event " + a)

dst = open(sys.argv[2], "w") if len(sys.argv) > 2 else sys.stdout
for n, (a, k) in enumerate(out, 1):
    dst.write("TLATRACE seq=%d a=%s p=0 %s\n" % (n, a, " ".join("%s=%s" % kv for kv in k.items())))
print("# J=%d MaxConn=%d NT=%d MaxRestart=%d MaxTimeout=%d MaxCancel=%d HasStop=%s events=%d" % (
    max(jobs, 1), max(dials, 1), max(len(trans), 1), stats["restart"], stats["timeout"], stats["cancel"],
    "TRUE" if stats["stop"] else "FALSE", len(out)), file=sys.stderr)
