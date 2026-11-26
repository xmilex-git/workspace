# mk.py — from the converted runs (<name>.log + the constants events.py printed into <name>.consts) build the
# trace data module, the witness-trace cfgs and the reject cfgs under docs/tla/CBRD-27430-B1b.
import re, subprocess, sys, os
WS = "/home/cubrid/dev/workspace"; D = WS + "/docs/tla/CBRD-27430-B1b"; T = os.path.dirname(os.path.abspath(__file__))
runs = sys.argv[1:]            # names
os.makedirs(D + "/traces", exist_ok=True)
ops = []
consts = {}
def cname(n): return "".join(p.capitalize() for p in re.split(r"[-_]", n))
def read_consts(n):
    m = dict(re.findall(r"(\w+)=(\d+)", open(f"{T}/{n}.consts").read()))
    return m
for n in runs:
    subprocess.check_call(["cp", f"{T}/{n}.log", f"{D}/traces/{n}.log"])
    ops.append(f"{cname(n)}=docs/tla/CBRD-27430-B1b/traces/{n}.log")
    consts[n] = read_consts(n)
# corrupted runs
def corrupt(src, dst, fn):
    lines = open(f"{D}/traces/{src}.log").read().splitlines()
    out = fn(lines)
    assert out != lines, dst
    open(f"{D}/traces/{dst}.log", "w").write("\n".join(out) + "\n")
    ops.append(f"{cname(dst)}=docs/tla/CBRD-27430-B1b/traces/{dst}.log")
    consts[dst] = consts[src]
def flip_first(pat, a, b):
    def f(lines):
        out = list(lines); done = False
        for i, l in enumerate(out):
            if not done and re.search(pat, l) and a in l:
                out[i] = l.replace(a, b); done = True
        return out
    return f
rej = []
if "probe" in runs:
    corrupt("probe", "auth-flipped", flip_first(r"a=Auth ", "ok=0", "ok=1")); rej.append(("auth-flipped", "a failed login logged as a success: the model has no step from a bad credential to the request loop"))
if "resume" in runs:
    corrupt("resume", "yield-flipped", flip_first(r"a=Finish ", "yld=1", "yld=0")); rej.append(("yield-flipped", "a yielded connection logged as an ordinary end: registry_auto_finish answers by the binding's state"))
    def drop_claim(lines):
        out = list(lines)
        for i, l in enumerate(out):
            if " a=CTCas " in l and "ok=1" in l:
                del out[i]; break
        return out
    corrupt("resume", "wake-without-cas", drop_claim); rej.append(("wake-without-cas", "the compare-and-swap of a YIELD_TRY dropped: its wake has no yielded binding"))
subprocess.check_call(f"cd {WS} && tools/tla/trace2tla AutoSessionTraceData {' '.join(ops)} > {D}/AutoSessionTraceData.tla", shell=True)
def cfg(name, expect, n, note):
    c = consts[n]
    open(f"{D}/AutoSessionTrace.{name}.cfg", "w").write(
        f"\\* expect: {expect}\n\\* deadlock-off: {note}\n\\* tlc: -difftrace\n\\* timeout: 3600\nSPECIFICATION TSpec\n"
        f"CONSTANTS NT = {c['NT']}  NS = {c['NS']}  ND = 1  MaxSlots = 1  MaxReq = {c['MaxReq']}  MaxPass = {c['MaxPass']}  MaxResets = {c['MaxResets']}  QMax = 3  Mutant = \"none\"\n"
        f"CONSTANT TraceLog <- {cname(n)}\nINVARIANT TraceNotDone\nCHECK_DEADLOCK FALSE\n")
for n in runs:
    cfg(f"witness-trace-{n}", "violation TraceNotDone", n, "an interleaving the run contradicts stops before the run is consumed")
for n, note in rej:
    cfg(f"reject-{n}", "pass", n, note)
print("ok", ops)
