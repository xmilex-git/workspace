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
