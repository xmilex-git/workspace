# mk.py — from the recorded runs (trace/<name>.raw) build the converted logs, the trace data modules, the
# witness-trace cfgs and the reject cfgs under docs/tla/CBRD-27430-B4.
#   token runs:  multi restart faults  (correct build)   noscan nosid (knobs: accepted only as the mutant)
#   domain runs: sessions kept-expire     (correct build)   olddomain    (knob)
import re, subprocess, sys, os
WS = "/home/cubrid/dev/workspace"; D = WS + "/docs/tla/CBRD-27430-B4"; T = os.path.dirname(os.path.abspath(__file__))
S = WS + "/.git_ignored_dir/scratch/fold-v2/b4"
A, B = "foldv2s0", "foldv2b"
TOK = [n for n in ("multi", "restart", "faults", "noscan", "nosid") if os.path.exists(f"{T}/{n}.raw")]
DOM = [n for n in ("sessions", "kept-expire", "olddomain") if os.path.exists(f"{T}/{n}.raw")]
os.makedirs(D + "/traces", exist_ok=True)
consts = {}
def cname(n): return "".join(p.capitalize() for p in re.split(r"[-_]", n))
def conv(n, kind):
    args = ["python3", "-I", f"{S}/events_{kind}.py", f"{T}/{n}.raw", f"{D}/traces/{kind}-{n}.log"] + ([A, B] if kind == "token" else [])
    subprocess.check_call(args, stderr=open(f"{T}/{n}.consts", "w"))
    consts[n] = dict(re.findall(r"(\w+)=(\d+)", open(f"{T}/{n}.consts").read()))
    print(n, open(f"{T}/{n}.consts").read().strip(), "events", sum(1 for _ in open(f"{D}/traces/{kind}-{n}.log")))
def corrupt(kind, src, dst, fn):
    lines = open(f"{D}/traces/{kind}-{src}.log").read().splitlines()
    out = fn(lines)
    assert out != lines, dst
    out = [re.sub(r"seq=\d+", "seq=%d" % i, l) for i, l in enumerate(out)]
    open(f"{D}/traces/{kind}-{dst}.log", "w").write("\n".join(out) + "\n")
    consts[dst] = consts[src]
def flip_first(pat, a, b):
    def f(lines):
        out = list(lines)
        for i, l in enumerate(out):
            if re.search(pat, l) and a in l:
                out[i] = l.replace(a, b); break
        return out
    return f
def swap_first(pa, pb):
    def f(lines):
        out = list(lines)
        for i, l in enumerate(out):
            if re.search(pa, l):
                for j in range(i + 1, len(out)):
                    if re.search(pb, out[j]):
                        out[i], out[j] = out[j], out[i]
                        return out
        return out
    return f
def drop_first(pat):
    def f(lines):
        out = list(lines)
        for i, l in enumerate(out):
            if re.search(pat, l):
                del out[i]; break
        return out
    return f

for n in TOK: conv(n, "token")
for n in DOM: conv(n, "domain")
trej, drej = [], []
if "restart" in TOK:
    corrupt("token", "restart", "survivor-uncounted", drop_first(r"a=DScan .*res=ok"))
    trej.append(("survivor-uncounted", "the scan's dial of the survivor's database dropped: the model's scan asks every database"))
if "multi" in TOK:
    corrupt("token", "multi", "end-other-db", flip_first(r"a=SEnd ", "e=1", "e=2"))
    trej.append(("end-other-db", "a SESSION_END of one database logged as the other's"))
    corrupt("token", "multi", "wrong-sid-hit", flip_first(r"a=CnSend .*hit=0", "hit=0", "hit=1"))
    trej.append(("wrong-sid-hit", "a cancel with another session id logged as an interrupt"))
if "sessions" in DOM:
    corrupt("domain", "sessions", "lists-before-ws", swap_first(r"a=WsFinal ", r"a=FreeLists "))
    drej.append(("lists-before-ws", "the lists freed before the workspace"))
    corrupt("domain", "sessions", "second-node", flip_first(r"a=ResolveSess .*ins=0", "ins=0", "ins=1"))
    drej.append(("second-node", "a resolve of a cached domain logged as an insert"))
def data(mod, kind, names):
    ops = " ".join(f"{cname(n)}=docs/tla/CBRD-27430-B4/traces/{kind}-{n}.log" for n in names)
    subprocess.check_call(f"cd {WS} && tools/tla/trace2tla {mod} {ops} > {D}/{mod}.tla", shell=True)
data("TokenTableTraceData", "token", TOK + [r[0] for r in trej])
data("DomainCacheTraceData", "domain", DOM + [r[0] for r in drej])
def tcfg(name, expect, n, note, mutant="none", inv="TraceNotDone"):
    c = consts[n]
    open(f"{D}/TokenTableTrace.{name}.cfg", "w").write(
        f"\\* expect: {expect}\n\\* deadlock-off: {note}\n\\* tlc: -difftrace\n\\* timeout: 1800\nSPECIFICATION TSpec\n"
        f"CONSTANTS ND = 2  NT = {c['NT']}  NP = {c['NP']}  NSid = 2  MaxSlots = {c['MaxSlots']}  MaxConn = {c['MaxConn']}  MaxCrash = {c['MaxCrash']}  MaxBR = {c['MaxBR']}  MaxKill = {c['MaxKill']}  MaxHang = {c['MaxHang']}  MaxCancel = {c['MaxCancel']}  Mutant = \"{mutant}\"\n"
        f"CONSTANT TraceLog <- {cname(n)}\nINVARIANT {inv}\nCHECK_DEADLOCK FALSE\n")
def dcfg(name, expect, n, note, mutant="none", inv="TraceNotDone"):
    c = consts[n]
    open(f"{D}/DomainCacheTrace.{name}.cfg", "w").write(
        f"\\* expect: {expect}\n\\* deadlock-off: {note}\n\\* tlc: -difftrace\n\\* timeout: 1800\nSPECIFICATION TSpec\n"
        f"CONSTANTS NS = {c['NS']}  NC = {c['NC']}  NA = {c['NA']}  MaxInc = {c['MaxInc']}  Mutant = \"{mutant}\"\n"
        f"CONSTANT TraceLog <- {cname(n)}\nINVARIANT {inv}\nCHECK_DEADLOCK FALSE\n")
W = "an interleaving the run contradicts stops before the run is consumed"
for n in TOK:
    if n == "noscan":
        tcfg("witness-trace-noscan-mutant", "violation TraceNotOverCap", n, W, "no_scan", "TraceNotOverCap")
        tcfg("reject-noscan-as-correct", "pass", n, "the run of the old dispatcher is not a run of the model")
    elif n == "nosid":
        tcfg("witness-trace-nosid-mutant", "violation TraceNotWrongCancel", n, W, "no_sid_check", "TraceNotWrongCancel")
        tcfg("reject-nosid-as-correct", "pass", n, "the run of the server without the session id check is not a run of the model")
    else:
        tcfg(f"witness-trace-{n}", "violation TraceNotDone", n, W)
for n, note in trej: tcfg(f"reject-{n}", "pass", n, note)
for n in DOM:
    if n == "olddomain":
        dcfg("witness-trace-olddomain-mutant", "violation TraceNotUaf", n, W, "process_list", "TraceNotUaf")
        dcfg("reject-olddomain-as-correct", "pass", n, "the run of the old routing is not a run of the model")
    else:
        dcfg(f"witness-trace-{n}", "violation TraceNotDone", n, W)
for n, note in drej: dcfg(f"reject-{n}", "pass", n, note)
print("ok")
