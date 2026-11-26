# compile every entry of the changed files: optdebug -fsyntax-only, release -c -o /dev/null
import json, subprocess, sys, shlex
W = sys.argv[1]; files = sys.argv[2:]
fails = 0
for preset, extra in (("optdebug", ["-fsyntax-only", "-fmax-errors=0"]), ("release", ["-o", "/dev/null"])):
    cc = json.load(open(f"{W}/build_preset_{preset}/compile_commands.json"))
    for e in cc:
        if not any(e["file"].endswith(f) for f in files):
            continue
        args = shlex.split(e["command"]) if "command" in e else e["arguments"]
        out = []; skip = False
        for a in args:
            if skip: skip = False; continue
            if a == "-o": skip = True; continue
            out.append(a)
        r = subprocess.run(out + extra, cwd=e["directory"], capture_output=True, text=True)
        tgt = e.get("output", "")
        msgs = [l for l in r.stderr.splitlines() if "error" in l or "warning" in l]
        print(f"{preset} rc={r.returncode} {e['file'].split('/src/')[-1]} {tgt.split('/')[-3] if tgt else ''} {len(msgs)}")
        for l in msgs[:15]: print("   ", l)
        fails += r.returncode != 0
print("SYNTAX:", "OK" if fails == 0 else f"FAILED {fails}")
