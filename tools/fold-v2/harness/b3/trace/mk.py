# mk.py <run>... — from the converted runs (<name>.log + the constants events.py printed into <name>.consts) build
# the trace data module, the witness-trace cfgs and the reject cfgs under docs/tla/CBRD-27430-B3.
import re, subprocess, sys, os
WS = "/home/cubrid/dev/workspace"; D = WS + "/docs/tla/CBRD-27430-B3"; T = os.path.dirname(os.path.abspath(__file__))
S = WS + "/.git_ignored_dir/scratch/fold-v2/b3"
runs = sys.argv[1:]
os.makedirs(D + "/traces", exist_ok=True)
ops, consts = [], {}
def cname(n): return "".join(p.capitalize() for p in re.split(r"[-_]", n))
for n in runs:
    subprocess.check_call(["python3", "-I", S + "/events.py", f"{T}/{n}.raw", f"{D}/traces/{n}.log"], stderr=open(f"{T}/{n}.consts", "w"))
    ops.append(f"{cname(n)}=docs/tla/CBRD-27430-B3/traces/{n}.log")
    consts[n] = dict(re.findall(r"(\w+)=(\d+)", open(f"{T}/{n}.consts").read()))
def corrupt(src, dst, fn):
    lines = open(f"{D}/traces/{src}.log").read().splitlines()
    out = fn(lines)
    assert out != lines, dst
    open(f"{D}/traces/{dst}.log", "w").write("\n".join(out) + "\n")
    ops.append(f"{cname(dst)}=docs/tla/CBRD-27430-B3/traces/{dst}.log")
    consts[dst] = consts[src]
def flip_first(pat, a, b):
    def f(lines):
        out = list(lines); done = False
        for i, l in enumerate(out):
            if not done and re.search(pat, l) and a in l:
                out[i] = l.replace(a, b); done = True
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
rej = []
if "gates" in runs:
    corrupt("gates", "ro-write-applied", flip_first(r"a=Write .* c=cl ", "out=cl", "out=ok")); rej.append(("ro-write-applied", "gates", "a write of a read-only broker's session logged as applied: its counter refuses it at the entry point"))
if "readonly" in runs:
    corrupt("readonly", "gated-write-applied", flip_first(r"a=Write .* c=bnd ", "out=sv", "out=ok")); rej.append(("gated-write-applied", "readonly", "a savepoint on a read_only server logged as applied: the fold boundary asks the transaction's gate"))
if "demote" in runs:
    corrupt("demote", "reset-missed", flip_first(r"a=End2 .* h=tbs ", "r=1", "r=0")); rej.append(("reset-missed", "demote", "the commit of a transaction that wrote on a to-be-standby server logged without a reset"))
    corrupt("demote", "standby-admitted", flip_first(r"a=Admit .* h=standby ", "rej=1", "rej=0")); rej.append(("standby-admitted", "demote", "a read-write broker's session logged as admitted on a standby"))
    corrupt("demote", "gate-not-set", drop_first(r"a=GateDis ")); rej.append(("gate-not-set", "demote", "logtb_disable_update dropped: the standby's next registration seeds a gate that is set"))
subprocess.check_call(f"cd {WS} && tools/tla/trace2tla HaGateTraceData {' '.join(ops)} > {D}/HaGateTraceData.tla", shell=True)
def cfg(name, expect, n, src, note):
    c = consts[n]
    ro = "TRUE" if src == "readonly" else "FALSE"
    open(f"{D}/HaGateTrace.{name}.cfg", "w").write(
        f"\\* expect: {expect}\n\\* deadlock-off: {note}\n\\* tlc: -difftrace\n\\* timeout: 3600\nSPECIFICATION TSpec\n"
        f"CONSTANTS NS = {c['NS']}  TypesC = {{\"RW\", \"RO\", \"SO\", \"RWR\"}}  KindsC = {{\"dml\", \"ddl\", \"wire\", \"srv\"}}  IsReplica = FALSE  ROMode = {ro}  HaInit = \"active\"  GInit = {c['GInit']}  HaMoves = TRUE  Wit = FALSE  Mutant = \"none\"\n"
        f"CONSTANT TraceLog <- {cname(n)}\nINVARIANT TraceNotDone\nCHECK_DEADLOCK FALSE\n")
for n in runs:
    cfg(f"witness-trace-{n}", "violation TraceNotDone", n, n, "an interleaving the run contradicts stops before the run is consumed")
for n, src, note in rej:
    cfg(f"reject-{n}", "pass", n, src, note)
print("ok", len(ops))
