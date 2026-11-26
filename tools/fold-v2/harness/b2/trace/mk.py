# mk.py — from the raw runs in this directory, write docs/tla/CBRD-27430-B2/traces/*.log, the <Module>TraceData.tla
# modules and the witness-trace / reject cfgs.  A reject log is an accepted log with one event corrupted.
import os
import re
import subprocess
import sys

WS = "/home/cubrid/dev/workspace"
T = WS + "/.git_ignored_dir/scratch/fold-v2/b2/trace"
D = WS + "/docs/tla/CBRD-27430-B2"
os.makedirs(D + "/traces", exist_ok=True)

# module -> [(operator, cfg name, raw run, extra events.py args)]
RUNS = {
    "ConfigPush": [("Config", "config", "config", []), ("Restart", "restart", "restart", [])],
    "AclTable": [("Acl", "acl", "acl", [])],
    "LogLease": [("Lease", "lease", "lease", [])],
    "StatsKill": [("Stats", "stats", "stats", [])],
    "SslAck": [("Tls", "tls", "ssl", ["1"]), ("Cleartext", "cleartext", "stats", ["1"])],
}


def renumber(lines):
    return [re.sub(r"seq=\d+", "seq=%d" % n, l) for n, l in enumerate(lines, 1)]


def first(lines, pat):
    for i, l in enumerate(lines):
        if re.search(pat, l):
            return i
    raise SystemExit("no line matches " + pat)


def write_skipped(lines):      # a conf the handler wrote, logged as skipped: the flag that follows has no write
    i = first(lines, r"a=SWrite .*take=1")
    lines[i] = lines[i].replace("take=1", "take=0")
    return lines


def stale_check(lines):        # a check after a reload, logged with the table of the load before
    i = max(i for i, l in enumerate(lines) if re.search(r"a=CCheck .*failed=0 n=[2-9]", l))
    n = int(re.search(r" n=(\d+)", lines[i]).group(1))
    lines[i] = re.sub(r" n=\d+", " n=%d" % (n - 1), lines[i])
    return lines


def index_twice(lines):        # an index another session holds, logged as taken
    i = first(lines, r"a=STry .*got=0")
    lines[i] = lines[i].replace("got=0", "got=1")
    return lines


def torn_row(lines):           # a row whose first counter is of a later request than its second
    i = first(lines, r"a=RRow ")
    ga = int(re.search(r" ga=(-?\d+)", lines[i]).group(1))
    lines[i] = re.sub(r" ga=-?\d+", " ga=%d" % (ga + 1), lines[i])
    return lines


def ack_first(lines):          # the ack logged before the server handled the HANDOFF
    i, j = first(lines, r"a=SHandle "), first(lines, r"a=BAck")
    lines[i], lines[j] = lines[j], lines[i]
    return renumber(lines)


REJECTS = {
    "ConfigPush": ("WriteSkipped", "write-skipped", "Config", write_skipped,
                   "a conf the handler wrote, logged as skipped: the model has no flag without a write"),
    "AclTable": ("StaleCheck", "stale-check", "Acl", stale_check,
                 "a check after a reload logged with the table of the load before it"),
    "LogLease": ("IndexTwice", "index-twice", "Lease", index_twice,
                 "an index another session holds, logged as taken"),
    "StatsKill": ("TornRow", "torn-row", "Stats", torn_row,
                  "a row whose two counters are of different requests"),
    "SslAck": ("AckFirst", "ack-first", "Tls", ack_first,
               "the ack of an SSL client logged before the server handled the HANDOFF"),
}

summary = []
for module, runs in RUNS.items():
    ops, consts = [], {}
    for op, name, raw, extra in runs:
        log = "%s/traces/%s-%s.log" % (D, module.lower(), name)
        r = subprocess.run([sys.executable, T + "/../events.py", module, "%s/%s.raw" % (T, raw), log] + extra,
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit("%s %s: %s" % (module, name, r.stderr[-600:]))
        line = r.stderr.strip().splitlines()[-1]
        consts[op] = dict(kv.split("=") for kv in line[2:].split() if "=" in kv)
        ops.append((op, log))
        events = consts[op].pop("events")
        summary.append("%s %s events=%s %s" % (module, name, events, consts[op]))
        cfg = "%s/%sTrace.witness-trace-%s.cfg" % (D, module, name)
        cs = "  ".join("%s = %s" % kv for kv in consts[op].items())
        open(cfg, "w").write("\\* expect: violation TraceNotDone\n"
                             "\\* deadlock-off: an interleaving the run contradicts stops before the run is consumed\n"
                             "\\* tlc: -difftrace\n\\* timeout: 1800\nSPECIFICATION TSpec\n"
                             "CONSTANTS %s  Mutant = \"none\"\nCONSTANT TraceLog <- %s\n"
                             "INVARIANT TraceNotDone\nCHECK_DEADLOCK FALSE\n" % (cs, op))
    rop, rname, src, mutate, why = REJECTS[module]
    srclog = dict(ops)[src]
    lines = mutate(open(srclog).read().splitlines())
    rlog = "%s/traces/%s-%s.log" % (D, module.lower(), rname)
    open(rlog, "w").write("\n".join(lines) + "\n")
    ops.append((rop, rlog))
    cs = "  ".join("%s = %s" % kv for kv in consts[src].items())
    open("%s/%sTrace.reject-%s.cfg" % (D, module, rname), "w").write(
        "\\* expect: pass\n\\* deadlock-off: %s\n\\* tlc: -difftrace\n\\* timeout: 1800\nSPECIFICATION TSpec\n"
        "CONSTANTS %s  Mutant = \"none\"\nCONSTANT TraceLog <- %s\nINVARIANT TraceNotDone\nCHECK_DEADLOCK FALSE\n"
        % (why, cs, rop))
    data = subprocess.run([WS + "/tools/tla/trace2tla", module + "TraceData"] + ["%s=%s" % o for o in ops],
                          capture_output=True, text=True)
    if data.returncode != 0:
        raise SystemExit("trace2tla %s: %s" % (module, data.stderr[-400:]))
    open("%s/%sTraceData.tla" % (D, module), "w").write(data.stdout)
print("\n".join(summary))
