#!/usr/bin/env python3
"""Equivalence of two counter runs (fast-counters.sh or the sequential harness): every (cell, rule, variant, rep) row
in both, and every column except the elapsed time `ms` equal. usage: compare-counter-runs.py <run dir A> <run dir B>"""
import csv, sys


def load(path):
    with open(path) as f:
        return {(r["cell"], r["rule"], r["variant"], r["rep"]): r for r in csv.DictReader(f, delimiter='\t')}


a, b = sys.argv[1], sys.argv[2]
failed = False
for mode in ("p0", "p24"):
    ra, rb = load(f"{a}/output/counters-{mode}.tsv"), load(f"{b}/output/counters-{mode}.tsv")
    only_a, only_b = sorted(set(ra) - set(rb)), sorted(set(rb) - set(ra))
    diffs = []
    for k in sorted(set(ra) & set(rb)):
        for col in ra[k]:
            if col != "ms" and ra[k][col] != rb[k].get(col):
                diffs.append((k, col, ra[k][col], rb[k].get(col)))
    print(f"=== {mode}: A rows={len(ra)} B rows={len(rb)} only-A={len(only_a)} only-B={len(only_b)} differing values={len(diffs)}")
    for k in only_a[:20]:
        print("  ONLY-A", k)
    for k in only_b[:20]:
        print("  ONLY-B", k)
    for d in diffs[:50]:
        print("  DIFF", *d)
    failed |= bool(only_a or only_b or diffs)
print("EQUIVALENT" if not failed else "NOT EQUIVALENT")
sys.exit(1 if failed else 0)
