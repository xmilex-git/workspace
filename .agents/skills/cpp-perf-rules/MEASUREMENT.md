# §1 Measurement (MEAS)

## MEAS-01 — Never propose optimization without measurement
80% of bottlenecks are where you did not predict. "This looks slow" from reading code is not accepted as evidence.

## MEAS-02 — Follow the 3-stage measurement procedure

```
Stage 1: Characterize — what is the bottleneck (memory? branches? compute?)
  perf stat -r 10 -e cycles,instructions,cache-misses,cache-references,\
    branch-misses,branch-instructions,stalled-cycles-frontend,\
    stalled-cycles-backend ./target

Stage 2: Locate — which function
  perf record -g --call-graph dwarf ./target
  perf report --sort=overhead,symbol

Stage 3: Explain — which instruction in that function
  perf annotate -s target_function
```

## MEAS-03 — Verdict baselines

| Metric | Formula | Normal | If bad, cause |
|---|---|---|---|
| IPC | instructions / cycles | > 1.5 | < 1.0 → memory stalls or dependency chains |
| Cache miss rate | cache-misses / cache-references | < 3% | > 5% → data layout |
| Branch miss rate | branch-misses / branch-instructions | < 1% | > 2% → unpredictable branches |
| Frontend stall | stalled-cycles-frontend / cycles | < 10% | > 20% → I-cache pressure, over-inlining |
| Backend stall | stalled-cycles-backend / cycles | < 20% | > 40% → memory stalls |

## MEAS-04 — Benchmark hygiene
- Compare the **median** of repeated runs; the mean is polluted by outliers. `perf stat -r 10`.
- Consume the result so the measured code isn't dead-code-eliminated (`DoNotOptimize` pattern).
- Pin CPU frequency scaling/turbo, or run long enough to average it out.
- Measure after warm-up; the first run is polluted by cache and page faults.
- **Measure with production-like data sizes.** Small data fits entirely in L1 and hides cache problems.

## MEAS-05 — Verify correctness after the improvement
Performance changes must pass functional regression tests. FP reordering, parallelization, and SIMD substitution can change results — verify explicitly.

## MEAS-06 — Never judge from a single metric (usage protocol for the MEAS-03 table)

The MEAS-03 thresholds are **suspicion signals, not verdicts**. Read one metric alone and you will read it backwards. Two measured cases (low-latency paper note §2.1, §3.5):

| Case | Miss rate | Instructions | Wall time |
|---|---|---|---|
| Cache cold → warm | 73.96% → 71.56% (≈ unchanged) | 4.93B → 12.01B (**up**) | 267.7ms → **25.6ms** |
| Combined optimizations | 16.0% → 33.9% (**2× worse**) | 6.01B → **3.27B** | **fastest** |

- The first case got faster because the **number of cache references** dropped, not the miss *rate*. Rate alone reads as "no improvement".
- The second has double the miss rate and is the fastest — total instruction count halved.
- So **record rate and absolute count together**: both `cache-misses` and `cache-references` from `perf stat`, plus `instructions`.
- The final verdict is always the **wall-clock median**. Hardware counters explain *why*; they never decide.

> Same failure shape outside the engine: a histogram was judged "full-scan statistics" from `buckets:300` alone when it was actually sampled (2026-08-28). **A secondary indicator looking normal is not evidence that the primary thing is normal.**

## MEAS-07 — Variance (the tail) is a metric, not just the mean

What a DB user feels is not the mean but the **slow tail**. Same mean with high variance means timeouts and SLA violations.

- When reporting an optimization, **write the dispersion (MAD or stddev) next to the median.**
  Measured: pair-trading stddev 4,233ns → 400ns — not just faster but **predictable** (paper note §3.4).
- Pre-allocation and fixed-size buffers contribute more to **reducing variance** than to the mean. Runtime allocation is not slow; it is **occasionally very slow** (same reason as ALLOC-01).
- If the mean improved while variance stayed high, do not call it an improvement.

## MEAS-08 — Exclude the code-layout confound before attributing a delta to source semantics

Any A/B on hot-loop code that lands in the same DSO compares **two different binaries**, not two versions of
one function (CC-08). Before saying "change X made the executor N % slower/faster", run the ELF gate:

```
1. Hot-symbol phase diff (Appendix E):  nm -n -S on A and B for the workload's top perf symbols
     → addr, size, addr % 32, addr % 64, raw-byte hash for each; count of symbols shifted
   No shift and identical bytes  → layout excluded, attribute to semantics.
   Shift (typically a uniform ±16 / ±32 across a long run of symbols) → continue.
2. Locate the first divergence: walk the sorted symbol list, find the first symbol whose size differs
   (in CBRD-26382 a 7-byte cold fragment 3 MB upstream of the executor).
3. Padding control: rebuild B with N non-executable bytes appended to that object's section so that the
   hot addresses return to A's phase, keeping B's logic. Same toolchain, same day, same flags.
   If timing follows the phase, the delta is layout, not the source change — say so in the PR/report.
4. Extend to phases 0/8/16/24/32 with independent rebuilds if the finding will drive a product decision
   (removes periodicity and build-date confounds).
```

Reporting rules:
- Give **paired** B/A ratios with a bootstrap CI from ≥ 20 runs per variant; publish the direction *and*
  whether the magnitude reproduced (stable host +1.46 % vs QA +10.56 % is a real, CPU-dependent spread).
- Read the **full Top-down L1/L2** for both variants. "DSB miss +52 %" alone is not a cause; in the
  measured case front-end bound went *down* while core bound went up. Say which slot moved.
- Restart protocol matters for reproduction (server/master restart per sample vs fresh `createdb`); state it.
  Confirm `read_bytes`/major-faults are 0 before ruling out I/O — don't argue disk from hardware specs.
- A control that changes hot bytes for a *different* reason (e.g. forced `noexcept`) is a **separate**
  variant, not evidence about layout: compare its hot-symbol hashes to B before interpreting its timing.

## MEAS-09 — An A/B is valid only under isolated, like-for-like conditions

A comparison is made only after `env -i` isolation, a warmup and a median of N runs (for example warmup 2 + median 5), with both sides on the same conf and the same build type (confirmed in `CMakeCache.txt`) and parameter fairness confirmed with `cubrid paramdump` (for example the effective `sort_buffer_size`); a run that stopped on an error has no time to report. (P1)

- Cold cache, a config-load error from the previous run and a polluted `PATH` each look like a structural difference.
- A `just build` never runs beside a measurement or parity run on the same install (cubrid-build P4/P6).

## MEAS-10 — Attribute a regression by profile and counter-experiment, never by assumption

A perf regression is attributed by a profile (per-file breakdown: VTune, perf, strace) and a counter-experiment that turns the suspected element off; new code is judged against a control with its path disabled; a median without a CoV ≤ 15 % is not trusted; valgrind, VTune and stress tools attach only during the measured query, never during load or fixture setup. (P2)

## MEAS-11 — A gate margin comes from the measured variance

Before a gate is fixed, a pilot run measures the per-run CoV and the paired standard deviation and the pair count needed to resolve the margin at that variance is computed; a non-inferiority pass requires the bootstrap CI's upper bound ≤ the margin; a FAIL without that power holds the merge but is no evidence that a regression exists, and no per-commit attribution is built on it. (P3)

- A loss-count axis is a sign test: it detects a small positive effect regardless of the margin — say so.

## MEAS-12 — Large index-build timing is a page-cache regime, not a code delta

For a large CREATE INDEX or loaddb index phase, wall clock is dominated by whether the sort's temp writes are absorbed by the OS page cache (temp volumes are unlinked at run end, so with cache headroom they vanish without writeback): neither cold nor warm is forced, order is balanced within a campaign (AB/BA), numbers from different regimes are never pooled, and work is compared by the page-buffer victim-flush counts ("Flush victim candidates … finished (count: N)", logged in release too) summed over the timed window rather than by wall clock. (P4)

- `cubrid statdump` `Num_*` accumulate only while a perfmon watcher is attached (`perfmon_is_perf_tracking`); all-zero counters mean collection was off, not that no work was done.

## MEAS-13 — Benchmarks run on the host as it is

A benchmark runs on the shared host even under load: SMT stays on, cpusets are not touched, no step waits for a quiet host, base and fix run interleaved, and `uptime` is logged per chunk and reported with the numbers. (P5)

## MEAS-14 — Host measurement traps (this host)

Each of these once cost a lane rerun; check them before trusting a number: (P6)

- An install copy runs the original prefix's libraries (`DT_RPATH`) — cubrid-build P4; two builds whose per-row code differs but give equal exact counts (±0.05 %) are the same binary.
- `perf stat -p` is never attached to `cub_server` inside a timing run: the attach walks hundreds of threads, overlaps the first measured executions of short cells (0.65 → 0.18 ms drift) and misses threads created afterwards. Count PMU in `csql -S` under `perf stat` from process start: run the variant 1× and N×, one execution = (N − 1) delta; with six events and the NMI watchdog on, multiplexing is about 66 %, so the values are estimates.
- Instruction sampling is throttled (`kernel.perf_event_max_sample_rate` 25000): `-c 100003` on a busy thread drops samples non-reproducibly; use `-c 1000003`, compare builds only inside one run, take absolute counts from `perf stat`.
- Exact per-function cost per execution comes from callgrind (`valgrind --vgdb=no --tool=callgrind`, R=1 and R=N, `callgrind_annotate --auto=no`, ((bN − b1) − (dN − d1)) / (N − 1)); at `-c 2000000` a ±20-sample difference is noise.
- JDBC `SHOW TRACE` returns NULL for a statement prepared before `SET TRACE ON` (`query_trace` is read at prepare); check the trace text, not a "0 plan differences" count; compare the "Trace Statistics" tree with digits removed.
- `addr2line -f` names an inlined instruction by the inlined function (`RESOLVED_CELL`, `__bswap_32` show up as "functions"); that is the inlined code's cost, not a missed inline.
- A gdb breakpoint on a libcubridsa function stops first on its `@plt` stub (no arguments); a breakpoint with `<MULTIPLE>` locations counts every location — read `info breakpoints` before comparing hit counts.
- Profile A/B only between installs whose `lib/libcubrid_all_locales.so` sha256 is equal (an optdebug archive has none, a `just build` install has it; en_US.utf8 identifier compares then execute different instruction counts).
- `bpftrace` tracepoints fail here (no kernel BTF); use `kprobe:__x64_sys_fsync` / `__x64_sys_fdatasync` with `pid == $1`.
- Storage functions nobody changed can run 4–10 % more samples from a `%64` phase change alone — MEAS-08 before blaming source.

## MEAS-15 — Inlining decisions are proven with a single-TU IPA dump

To explain why a function stopped being inlined, compile that TU alone with its SERVER_MODE line from `build_preset_release/compile_commands.json` (source and include paths swapped to the target tree, ccache dropped, `-o` to scratch) plus `-fdump-ipa-inline-details`, and read `Considering`, `Inlined … into`, `not inlinable: … <reason>` and `IPA function summary` in the `.079i.inline` dump; the host's `gcc (GCC) 8.5.0` is the CI release compiler, so sizes match to the byte. (P7)

- GCC 8 splits `-fopt-info-inline-all=<file>` on `-`, so a dash in the path fails; `-fopt-info` printed nothing useful anyway.
- Count real calls per execution with a uprobe (`sudo -n perf probe -x <lib> --add 'name=func'`, `perf stat -e probe_<lib>:name`, then `perf probe -d`).

## MEAS-16 — JCC-erratum padding is not a CUBRID build flag

`-mbranches-within-32B-boundaries` (JCC erratum padding) is never proposed as a CUBRID build flag nor used for measurement pairs — MySQL, PostgreSQL, MariaDB, Fedora/RHEL and Debian release defaults do not carry it; layout noise on this host's Cascade Lake is recorded as such and judged by exact instruction counts plus the existing `-falign-functions=64` pair. (P8)
