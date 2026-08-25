---
name: cpp-perf-rules
description: Self-contained C/C++ performance rulebook for DB-engine, storage, query-processing, and systems-level code, with citable rule IDs (MEM-03, BR-04, A59, ...). Use when writing, reviewing, or optimizing performance-sensitive C/C++ code in CUBRID (hot loops, executor/scan paths, parallel workers, cache/false-sharing issues, vectorization, allocation, atomics), or when a perf regression, "more threads don't help", or a performance PR review comes up.
---

# C/C++ Performance Rulebook (Self-Contained)

Rulebook applied directly by AI agents and humans when writing or reviewing C/C++ code.
Every rule is citable by ID (e.g. "MEM-03 violation"). Target: DB engines, storage,
query processing, systems-level code.

## Usage protocol (for the agent)

1. **Demand bottleneck evidence before proposing any optimization.** No measurement data → answer "measure first". Guess-based optimization proposals are forbidden.
2. **Separate hot path from cold path first.** Do not apply this rulebook to cold paths (error handling, init, shutdown) — readability wins there.
3. **On rule conflict, priority is:** correctness > memory safety > readability > performance. Never introduce UB for performance.
4. **Give quantitative rationale.** Not "faster" — "removes N cache misses" or "eliminates M branches".
5. **Numeric thresholds are baselines.** They vary by architecture/workload; state that they must be tuned by measurement.
6. **Apply C rules to C code.** Do not propose modern C++ idioms (`shared_ptr`, RAII, templates) in a C codebase. In C, the ALIAS/CLOW sections replace the CPP section.
7. **Flag non-portable techniques.** When proposing GCC/Clang extensions (computed goto, `__builtin_*`, `__attribute__`), present a fallback path too.
8. **Never forget weak memory models.** Lock-free code that works on x86 commonly breaks on ARM64. Mention COH-10 alongside any atomics proposal.

## Recurring failure axes in this repository (CUBRID)

When writing or reviewing perf-path code, **skim [CHECKLIST.md](CHECKLIST.md) first**, and prioritize these:

| Axis | Rules | Real case |
|---|---|---|
| **Compile-time branch left in the row loop** | BR-04, A59 | `step->aux ? A : B`, `step->domain == NULL` tested per row in expr compile → removed via kernel specialization |
| **Unconditional out-of-line call per row** | CC-05, A60 | `pr_clear_value()` called per row even for fixed-width slots → replaced with inline flag set on the NULL path |
| **Multi-switch dispatch in predicate eval** | BR-06, A61 | `switch(kind)` → `switch(fast_type)` → `switch(rel_op)` triple → (type×operator) leaf function pointer fixed at compile time |
| **Invariant pointer re-published per row** | BR-04, A62 | Slot-owning step wrote the same address to the cell every row → once at program generation |
| **Serial path optimized, parallel-only loop missed** | PAR-14, A63 | px BUILDVALUE_OPT accumulation loop was outside the hook — only queries without GROUP BY were neutral |
| **Hot struct without hot/cold split** | MEM-02/05 | 96B step struct carrying fields unused during execution (regu, branch ranges) |
| **Cross-thread ownership free** | ALLOC-08, A64 | Private-heap allocation freed by another worker → mspace abort |
| **Per-row digit normalization in fixed-point** | FP-07 | NUMERIC SUM rounding/packing per row → deferred carry, finalize once |
| **False sharing on parallel worker counters** | MEM-03, GLOB-02 | px per-worker stats/partial sums |
| **Floating-point `==` in cost/selectivity** | FP-01/02 | Asymmetric plan comparator (CBRD-27139) |
| **Perf verdict from a single run** | MEAS-04 | One pass on a polluted baseline misjudged as "regression" → median-of-3 + cross-validation required |

## Priority decision procedure (when handed a perf problem)

Condensed — full text in [PRIORITY.md](PRIORITY.md). Work top-down; stop at the level that solves it. Step 3 matters most: one DRAM access ≈ 200–400 integer ops.

1. **Lower algorithmic complexity?** O(n²)→O(n log n) beats everything else combined. Remove work entirely (early exit, caching, dedup).
2. **Reduce the data touched?** Column pruning, compression, approximate structures (DS-05), read only needed fields.
3. **Improve memory access patterns?** MEM-01..07 — most real-world gains live here.
4. **Remove allocation?** ALLOC-01..05.
4.5 **Remove what blocks the compiler?** ALIAS-03/04 (aliasing), GLOB-01/10 (localize globals), BR-04-ext/CC-05 (compile-time branches & unconditional calls left in the run loop). Low risk, high gain — always try first. Multithreaded: check GLOB-02 and CPP-01 first (classic "more cores don't help" causes).
5. **Reduce branches and dependency chains?** BR-*, ILP (split partial sums).
6. **Parallelize?** PAR-*. Doing this before 3–5 just runs bad code on more cores. If threads don't scale, check in order: (1) false sharing MEM-03/GLOB-02, (2) atomic refcounting CPP-01, (3) allocator contention PAR-11, (4) contended atomics PAR-01, (5) NUMA PAR-09. Root fix is COH-12: replace sharing with partitioned ownership. Separate parallel-only loops → PAR-14.
7. **Vectorize?** CC-03/04 — needs data layout (MEM-04) fixed first.
8. **Compiler options / PGO?** CC-01/02.
9. **Hand assembly / intrinsics** — last resort, only on a measured bottleneck's tiniest part.

## Rule files (load what the task needs)

| File | Sections |
|---|---|
| [COSTS.md](COSTS.md) | §0 Cost baselines (cycles) + hardware constants — memorize the orders of magnitude |
| [MEASUREMENT.md](MEASUREMENT.md) | §1 MEAS — measurement procedure, verdict baselines, benchmark hygiene |
| [MEMORY-COHERENCY.md](MEMORY-COHERENCY.md) | §2 MEM (memory access — top category), §3 COH (cache coherency, MESI, false sharing) |
| [ALIASING.md](ALIASING.md) | §4 ALIAS — strict aliasing, restrict, the biggest C optimization lever |
| [BRANCHES-ALLOCATION.md](BRANCHES-ALLOCATION.md) | §5 BR (branches, dispatch), §6 ALLOC (allocation, arenas) |
| [FP-GLOBALS.md](FP-GLOBALS.md) | §7 FP (floating point, comparators), §8 GLOB (global/static/TLS state) |
| [PARALLEL.md](PARALLEL.md) | §9 PAR — atomics, memory order, NUMA, sync selection |
| [CPP-CLOW.md](CPP-CLOW.md) | §10 CPP (C++ feature costs), §11 CLOW (C low-level techniques) |
| [DATA-STRINGS-SERIAL.md](DATA-STRINGS-SERIAL.md) | §12 DS (data structures), §13 STR (strings), §14 SER (serialization) |
| [COMPILER-SYSTEM.md](COMPILER-SYSTEM.md) | §15 CC (compiler flags, PGO, vectorization), §16 SYS (I/O & system) |
| [ANTIPATTERNS.md](ANTIPATTERNS.md) | §17 Anti-pattern catalog A01–A66 — flag on sight with rule ID + alternative |
| [PRIORITY.md](PRIORITY.md) | §19 Priority decision procedure — full text |
| [CHECKLIST.md](CHECKLIST.md) | §18 Review checklist — run for every performance-related change |
| [APPENDIX.md](APPENDIX.md) | A: common macros/utilities, B: multithread scalability diagnosis procedure, C: external references & installed tools |
