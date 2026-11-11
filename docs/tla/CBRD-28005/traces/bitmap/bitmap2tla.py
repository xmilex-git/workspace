#!/usr/bin/env python3
# usage: bitmap2tla.py <Name>=<logfile>[:drop=<a>:<k>|:dup=<a>:<k>] ... > BitmapScanTraceData.tla
#
# Turns the TLATRACE lines an instrumented build wrote during one whole-range batch into the
# universe BitmapScan is checked over (rows, pages, sectors, the entries each worker examined)
# and the sequence of events BitmapScanTrace consumes.
#   :drop=<a>:<k>  leaves out the k-th event of action <a>   (a corrupted run the spec must refuse)
#   :dup=<a>:<k>   repeats the k-th event of action <a>
# The universe is always built from the run as recorded; the corruption touches the events only.
import re
import sys

MARK = "TLATRACE"


def events(path):
    out = []
    with open(path, errors="replace") as f:
        for line in f:
            i = line.find(MARK)
            if i < 0:
                continue
            ev = dict(kv.split("=", 1) for kv in line[i + len(MARK):].split() if "=" in kv)
            out.append(ev)
    out.sort(key=lambda e: int(e["seq"]))
    return out


def oid_t(oid):           # v0p123s4 -> (0, 123, 4)
    return tuple(int(x) for x in re.fullmatch(r"v(\d+)p(\d+)s(\d+)", oid).groups())


def page_t(page):         # v0p123 -> (0, 123)
    return tuple(int(x) for x in re.fullmatch(r"v(\d+)p(\d+)", page).groups())


def sect_t(sect):         # v0s1 -> (0, 1)
    return tuple(int(x) for x in re.fullmatch(r"v(\d+)s(\d+)", sect).groups())


def tt(t):
    return "<<" + ", ".join(str(x) for x in t) + ">>"


def tset(xs):
    xs = sorted(xs)
    if xs and isinstance(xs[0], tuple):
        return "{" + ", ".join(tt(x) for x in xs) + "}"
    return "{" + ", ".join('"' + x + '"' for x in xs) + "}"


def build(name, path, corrupt):
    evs = events(path)
    opens = [e for e in evs if e["a"] == "Open"]
    if len(opens) != 1:
        sys.exit(f"{path}: {len(opens)} Open events; record one scan per log")
    lossy = opens[0]["rowbits"] == "0"
    listed_sectors, listed_pages = set(), set()
    for e in evs:
        if e["a"] == "Sector":
            vol, sect = sect_t(e["sect"])
            listed_sectors.add((vol, sect))
            bits = int(e["pages"], 16)
            for off in range(64):
                if bits >> off & 1:
                    listed_pages.add((vol, sect * 64 + off))
    workers = sorted({e["p"] for e in evs if e["a"] in ("Mark", "IdxFinish", "TakeSector", "Stop")})
    entries, kind = {}, {}        # leaf of a worker -> the OIDs it marked
    for e in evs:
        if e["a"] == "Mark":
            entries.setdefault("L" + e["p"], set()).add(oid_t(e["oid"]))
            kind[oid_t(e["oid"])] = e["kind"]
    surfaced = {oid_t(e["oid"]): e["res"] for e in evs if e["a"] == "Lookup"}
    rows = set(kind) | set(surfaced)
    # invisible: the snapshot rejects the row's version; gone: the lookup finds no version (the slot is empty,
    # or its only version is newer than the snapshot)
    vis = {r for r, res in surfaced.items() if res not in ("invisible", "gone")}
    dataok = rows - {r for r, res in surfaced.items() if res == "filtered"}
    wide = {r for r, k in kind.items() if k == "page"} if not lossy else set()

    stops = [k for k, e in enumerate(evs) if e["a"] == "Stop"]
    log = []
    for k, e in enumerate(evs):
        a = e["a"]
        if a == "Mark":
            log.append(dict(a="Mark", p=e["p"], row=oid_t(e["oid"]), kind=e["kind"]))
        elif a in ("IdxFinish", "EndSector"):
            log.append(dict(a=a, p=e["p"]))
        elif a == "TakeSector":
            log.append(dict(a=a, p=e["p"], sect=sect_t(e["sect"])))
        elif a in ("FixPage", "ReleasePage", "PageGone"):
            log.append(dict(a=a, p=e["p"], page=page_t(e["page"])))
        elif a == "Lookup":
            log.append(dict(a=a, p=e["p"], row=oid_t(e["oid"]), res=e["res"]))
        elif a == "Stop" and k == stops[-1]:
            log.append(dict(a="Abort", p=e["p"]))
        elif a == "Vacuum":          # vacuum threads log every record they remove: keep the rows of this scan
            if oid_t(e["oid"]) in rows:
                log.append(dict(a=a, p=e["p"], row=oid_t(e["oid"])))
        elif a == "FreePage":        # ... and every page deallocated: keep the pages of the sector list
            if page_t(e["page"]) in listed_pages:
                log.append(dict(a=a, p=e["p"], page=page_t(e["page"])))
    if corrupt:
        op, act, nth = corrupt
        idx = [k for k, e in enumerate(log) if e["a"] == act]
        if nth > len(idx):
            sys.exit(f"{path}: only {len(idx)} {act} events")
        k = idx[nth - 1]
        log = log[:k] + log[k + 1:] if op == "drop" else log[:k + 1] + [log[k]] + log[k + 1:]

    def rec(e):
        return ("[a |-> \"%s\", p |-> \"%s\", row |-> %s, kind |-> \"%s\", sect |-> %s, page |-> %s, res |-> \"%s\"]"
                % (e["a"], e["p"], tt(e.get("row", ())), e.get("kind", "-"), tt(e.get("sect", ())),
                   tt(e.get("page", ())), e.get("res", "-")))

    leaf_fn = " @@ ".join('"%s" :> %s' % (l, tset(v)) for l, v in sorted(entries.items())) if entries else "<<>>"
    out = [f"\\* {name}: {path.split('/')[-1]}" + (f" ({corrupt[0]} {corrupt[1]} #{corrupt[2]})" if corrupt else ""),
           f"{name}_Log == <<\n  " + ",\n  ".join(rec(e) for e in log) + "\n>>",
           f"{name}_Lossy == {'TRUE' if lossy else 'FALSE'}",
           f"{name}_Workers == {tset(workers)}",
           f"{name}_Rows == {tset(rows)}",
           f"{name}_Leaves == {tset(entries)}",
           f"{name}_ListedSectors == {tset(listed_sectors)}",
           f"{name}_ListedPages == {tset(listed_pages)}",
           f"{name}_Wide == {tset(wide)}",
           f"{name}_IdxRows == {tset(set(kind))}",
           f"{name}_Vis == {tset(vis)}",
           f"{name}_DataOk == {tset(dataok)}",
           f"{name}_EntriesFn == ({leaf_fn})",
           f"{name}_EntriesOf(l) == {name}_EntriesFn[l]"]
    counts = {}
    for e in log:
        k = e["a"] + ("/" + e["kind"] if e["a"] == "Mark" else "/" + e["res"] if e["a"] == "Lookup" else "")
        counts[k] = counts.get(k, 0) + 1
    stats = " ".join(f"{k}={v}" for k, v in sorted(counts.items())) + f" | events={len(log)} rows={len(rows)} leaves={len(entries)} sectors={len(listed_sectors)} lossy={lossy} wide={len(wide)}"
    return "\n".join(out), stats


def main():
    print("----------------------- MODULE BitmapScanTraceData -----------------------")
    print("\\* generated by traces/bitmap/bitmap2tla.py; do not edit")
    print("EXTENDS TLC, Sequences")
    for arg in sys.argv[1:]:
        name, rest = arg.split("=", 1)
        parts = rest.split(":")
        path, corrupt = parts[0], None
        if len(parts) == 3:
            op, act = parts[1].split("=")
            corrupt = (op, act, int(parts[2]))
        text, stats = build(name, path, corrupt)
        print()
        print(text)
        print(f"{name}: {stats}", file=sys.stderr)
    print("=============================================================================")


main()
