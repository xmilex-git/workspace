# PITFALLS — the measurements behind MEAS-09..16, PAR-17 and usage protocol 13

Each `P<n>` is one rule. The **Rule** line is the exact sentence the rule file carries at the ID named
in **Applies at**; keep the two byte-identical. **Case** is the measurement that paid for the rule.
**Source** is where the lesson lived before it was folded in here (auto-memory slugs are deleted once
absorbed; kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule gets a MEAS/PAR ID in the rule file and a `P<n>` here in the same commit.

### P1 — like-for-like A/B
- Rule: A comparison is made only after `env -i` isolation, a warmup and a median of N runs (for example warmup 2 + median 5), with both sides on the same conf and the same build type (confirmed in `CMakeCache.txt`) and parameter fairness confirmed with `cubrid paramdump` (for example the effective `sort_buffer_size`); a run that stopped on an error has no time to report.
- Applies at: MEASUREMENT.md MEAS-09
- Case (SSOT §2 실수 7): cold cache, a previous run's config-load error and PATH pollution together were read as a structural performance difference; a `just build` during a parity run repointed the shared install and collided with the common master's port.
- Source: CUBRID_SSOT.md §2 실수 7

### P2 — attribution needs a counter-experiment
- Rule: A perf regression is attributed by a profile (per-file breakdown: VTune, perf, strace) and a counter-experiment that turns the suspected element off; new code is judged against a control with its path disabled; a median without a CoV ≤ 15 % is not trusted; valgrind, VTune and stress tools attach only during the measured query, never during load or fixture setup.
- Applies at: MEASUREMENT.md MEAS-10
- Case (SSOT §2 실수 8): a regression cause was named from assumption; the profile and the on/off experiment pointed elsewhere.
- Source: CUBRID_SSOT.md §2 실수 8

### P3 — gate margins from measured variance
- Rule: Before a gate is fixed, a pilot run measures the per-run CoV and the paired standard deviation and the pair count needed to resolve the margin at that variance is computed; a non-inferiority pass requires the bootstrap CI's upper bound ≤ the margin; a FAIL without that power holds the merge but is no evidence that a regression exists, and no per-commit attribution is built on it.
- Applies at: MEASUREMENT.md MEAS-11
- Case (2026-07-24, PR #7504 minimal-branch gate): the gate was fixed at "median ≤ +3 % AND losses < 6/8" while the measured per-run CoV was 8.7 % and the paired sd 14.0 pp; the paired-median bootstrap 95 % CI was −1.05 %..+14.42 % (contains 0) and the loss axis alone had a 0.145 false-FAIL probability. Resolving 3 pp at that variance needed about 171 pairs.
- Source: CUBRID_SSOT.md §2 실수 9

### P4 — index-build timing is a cache regime
- Rule: For a large CREATE INDEX or loaddb index phase, wall clock is dominated by whether the sort's temp writes are absorbed by the OS page cache (temp volumes are unlinked at run end, so with cache headroom they vanish without writeback): neither cold nor warm is forced, order is balanced within a campaign (AB/BA), numbers from different regimes are never pooled, and work is compared by the page-buffer victim-flush counts ("Flush victim candidates … finished (count: N)", logged in release too) summed over the timed window rather than by wall clock.
- Applies at: MEASUREMENT.md MEAS-12
- Case (2026-07-25, 20 G / 341 M-row CREATE INDEX): prewarming the 22.9 GiB data volume turned the same workload from 110 s to 365 s and the process's real writes from ~1.2 GB to 119 GB (`sda` %util 98 %). The victim-flush count gave 0.2 % resolution between lanes at zero overhead.
- Source: CUBRID_SSOT.md §2 실수 10

### P5 — bench on the host as it is
- Rule: A benchmark runs on the shared host even under load: SMT stays on, cpusets are not touched, no step waits for a quiet host, base and fix run interleaved, and `uptime` is logged per chunk and reported with the numbers.
- Applies at: MEASUREMENT.md MEAS-13
- Case (2026-10-19, CBRD-27664): the first run turned SMT off at load 13, then the load rose to 43 on 32 CPUs; a "wait until load < 16" step would have blocked for hours (other sessions' CTP keep the host at 30–50). The user: "걍 성능 테스트 해라 그리고. 부하 높더라도 그냥 해. … 부하 높을땐 SMT 끄지 말고, 그냥 돌려서 비교해." The earlier "SMT off + release" rule holds only when the host is quiet for the whole run.
- Source: memory:bench-on-busy-host-no-wait

### P6 — this host's measurement traps
- Rule: Each of these once cost a lane rerun; check them before trusting a number:
- Applies at: MEASUREMENT.md MEAS-14
- Case (2026-09-28, #345/#372): `cp -a` install copies loaded the build prefix's current libraries (DT_RPATH), so "commit 1 has no measurable gain" compared a build with itself; `perf stat -p` on cub_server drifted short cells 0.65 → 0.18 ms; sampling at `-c 100003` lost samples non-reproducibly (client functions identical in both commits moved by −112k instructions); storage functions nobody changed ran 4–10 % more samples from a `%64` phase change.
- Case (2026-10-20, CBRD-27583 upd-31): a sampled profile put +104K instructions/exec in `intl_identifier_casecmp_w_size`; gdb showed the same 2389 calls with byte-identical arguments; callgrind R=1/R=11 matched `perf stat` (+166,908 vs +166K) and named each new function exactly.
- Case (2026-10-26, #468): `tracepoint:syscalls:*` died with "BTF is required"; kprobes on `__x64_sys_fsync` with `pid == $1` gave per-process fsync counts.
- Source: memory:bench-measurement-pitfalls

### P7 — inlining proof
- Rule: To explain why a function stopped being inlined, compile that TU alone with its SERVER_MODE line from `build_preset_release/compile_commands.json` (source and include paths swapped to the target tree, ccache dropped, `-o` to scratch) plus `-fdump-ipa-inline-details`, and read `Considering`, `Inlined … into`, `not inlinable: … <reason>` and `IPA function summary` in the `.079i.inline` dump; the host's `gcc (GCC) 8.5.0` is the CI release compiler, so sizes match to the byte.
- Applies at: MEASUREMENT.md MEAS-15
- Case (2026-10-21, PR 8196 item 3): `heap_attrvalue_read` stopped being inlined into `heap_attrinfo_read_dbvalues` (release 0x83c → 0x1f3); the dump's "--param max-inline-insns-auto limit reached" vs "big_speedup" lines explained it, and the single-TU sizes matched the CI libraries (`readelf -p .comment`).
- Source: memory:gcc-inline-decision-single-tu-dump

### P8 — JCC padding
- Rule: `-mbranches-within-32B-boundaries` (JCC erratum padding) is never proposed as a CUBRID build flag nor used for measurement pairs — MySQL, PostgreSQL, MariaDB, Fedora/RHEL and Debian release defaults do not carry it; layout noise on this host's Cascade Lake is recorded as such and judged by exact instruction counts plus the existing `-falign-functions=64` pair.
- Applies at: MEASUREMENT.md MEAS-16
- Case (2026-09-28, #372): the bench host's Xeon Silver 4216 made timing swing ±5–10 % with layout alone; the user: "다른데도 안하면 우리도 그 옵션넣어서 빌드하지말고 그냥 이런 이유다~ 만 기록하고 넘어가자". Findings: MySQL `-ffunction-sections -fdata-sections` only; PostgreSQL `-fno-strict-aliasing -fwrapv -fexcess-precision=standard`; 0 hits for the flag in the three repos; Intel advises selective use after measuring; Mozilla closed its JIT mitigation WONTFIX. Front-end counts showed equal MITE shares for dpin and develop, so the uop-cache mechanism was not supported either.
- Source: memory:jcc-mitigation-not-a-release-flag

### P9 — worker stats merge once
- Rule: Every worker type that touches statistics (px_scan, px_query, hash join, external_sort / btree_sort, histogram sampler) keeps a private array whenever stats are collected (watching, not only under `on_trace`), merges it into the parent once at the worker's end on every exit path (normal end, close, error), allocates nothing when nobody watches, and pads per-worker slices in a shared block so neighbours share no cache line.
- Applies at: PARALLEL.md PAR-17
- Case (2026-10-11, workspace#428 trace-accuracy survey): the user: "그 누락들 고치는 코드 추가할때 thread local 집계 -> 끝나고 전체 집계에 merge 패턴을 사용해. /cpp-perf-rules 를 참고해서." `pstat_Global.tran_stats[tran_index]` written by workers with a non-atomic `+=` lost counts; sort workers' `m_px_stats` were destroyed with the worker.
- Source: memory:parallel-stats-thread-local-then-merge

### P10 — a perf finding carries its number
- Rule: Before writing an efficiency finding, read the function to its end (allocation, shrink, free), take the actual size or count from a running process (gdb `p`, perf attribution) or an existing measurement, and put the number in the finding; items disproved by measurement stay listed under "측정 후 빼거나 작다고 판정한 것" so the next reader does not re-raise them.
- Applies at: SKILL.md usage protocol 13
- Case (2026-10-04, PR 8022 review, self-caught): `domain_key_pairs_make` grepped for `free|return` read as 2·n²·72 B left allocated; its last lines `realloc` the pool down — gdb showed 141 KB resident, 0.8 ms build. It would have been the report's top efficiency item.
- Case (2026-10-21, PR 8196 item 3): objdump of `eb_raw_kid` showed per-row reloads and a jump table (A59/A61 shapes); perf annotate gave 1.5–3.8 % of the function's samples on the loads and 0–1 % on the jump (< 1 % of the query), so the finding was dropped; the real cost was an out-of-line NUMERIC decode via PLT.
- Source: memory:measure-before-claiming-perf-waste
