# cas-merge YCSB PoC baseline (2026-09-10) — workspace#244

Fixed reference for every PoC ticket under [#207](https://github.com/xmilex-git/workspace/issues/207) item 7.
All later candidates are A/B'd against **this sha, this install layout, this DB copy, this conf, these scripts**.
Raw data: tooling repo `.git_ignored_dir/scratch/wf-poc/` (not committed; per-leg `run.log`, `*.hdr`, `perf.data`, smaps).

## Fixed baseline

| item | value |
|---|---|
| engine sha | `d533969e4db6ef94d512d91f463790bab559790a` (= `xmilex/cas-merge` tip at ticket start, 2026-09-10 13:32 +0900; PR [CUBRID/cubrid#7837](https://github.com/CUBRID/cubrid/pull/7837) head lineage) |
| why not `ed284a2e3` | ticket body quoted the stale local branch (2026-08-31); it said "re-verify at start"; tip had moved 125 commits (wf222–wf227 shell/CI fixes). Decision D1 in runbook |
| build | fresh `release` preset = RelWithDebInfo, `CUBRID 11.5.0 (11.5.0.2835-d533969)`, built 2026-09-10 15:27 |
| install | `/home/cubrid/release/CUBRID-wf-poc-base` (`WF_POC_BUILD_INFO.txt` inside) |
| `libcubrid.so.11.5` sha256 | `94a4dd34b27d8c6db9e14cf7f93a987ac36586866d267ed2baee1f44ea764803` |
| `cub_server` sha256 | `e4e859ad67295b88d8508ba486cf2a0b79bb98647bc98a4eb2a4834cf0688583` |
| JDBC | `cubrid-jdbc-11.4.0.0076.jar` sha256 `3e876fb189ea55fe7f6d2481b6f79e02c8c8c222c38543f10c2f73c693e5f564` (from `CUBRID-wf222-final/jdbc`) |
| DB | golden `ycsb_g` `/home/cubrid/wf125-ycsb-db` (10M rows, immutable) → `copydb` → `/home/cubrid/wf-poc-db/ycsb`, fresh copy before every leg |
| harness | `cubrid-perftools-internal/ycsb/ycsb/cubrid/run.sh` @ `99e0703`, YCSB 0.4.0, threads=100, zipfian, recordcount=10M, hdrhistogram file output on (p50 computed from `.hdr`) |
| host | podman container on a shared 2-socket Xeon 4216 (32 CPU visible, no SMT); `/proc/loadavg` is host-wide |
| perf | `kernel.perf_event_paranoid=-1` (opened by the user) |

### conf (verbatim, `conf/cubrid.conf.100`)
```
[service]
service=server,broker,manager
server=ycsb
[common]
data_buffer_size=4G
log_buffer_size=2G
vacuum_worker_count=50
max_clients=200
data_buffer_neighbor_flush_pages=0
cubrid_port_id=1523
checkpoint_every_size=256G
checkpoint_interval=120min
```
Broker `%BROKER1`: `APPL_SERVER=CAS, BROKER_PORT=33000, MIN_NUM_APPL_SERVER=120, MAX_NUM_APPL_SERVER=120, DIRECT_HANDOFF=ON, SQL_LOG=OFF, APPL_SERVER_SHM_ID=33000`; `%query_editor SERVICE=OFF`; `MASTER_SHM_ID=30001`.
1,000-connection variant (`*.1000`): only `max_clients=1100`, `MIN/MAX_NUM_APPL_SERVER=1100` differ.
Leg validity = 0 lines matching `checkpoint` in server `.err` logs written during the leg, and 0 non-zero YCSB return codes.

## Runbook
`.git_ignored_dir/scratch/wf-poc/runbook.md` + `scripts/` (`00_build_install.sh`, `10_copydb.sh`, `20_apply_conf.sh`,
`stack.sh`, `30_ycsb_leg.sh`, `40_perf_leg.sh`, `50_smaps_leg.sh`, `60_churn_leg.sh`, `run_detached.sh`/`wait_leg.sh`,
`parse_ycsb.sh`, `stats.py`, `idle_gate.sh`, `ConnHold.java`, `HdrP50.java`) and `patches/ycsb-cachestatements.patch`.
Later tickets call only these. Selection protocol (item 7): per candidate `CUBRID-wf-poc-<cand>`, same DB copy, **C×1 (20M)**,
recorded next to the baseline median+MAD; in the stack unless throughput < median−3·MAD or crash; p99 > +10 % → G2 hold note.

## G1 — throughput baseline (C×3 · A×3, 20M ops each)
| leg | ops/s | READ p50 µs | READ p95 | READ p99 | UPD p50 | UPD p95 | UPD p99 | ckpt | err | loadavg1 before→after |
|---|---|---|---|---|---|---|---|---|---|---|
| c1 | 115,550 | 766 | 1,763 | 2,433 | – | – | – | 0 | 0 | 4.97→57.09 |
| c2 | 118,374 | 750 | 1,689 | 2,299 | – | – | – | 0 | 0 | 4.67→59.82 |
| c3 | 119,919 | 742 | 1,672 | 2,293 | – | – | – | 0 | 0 | 5.05→57.83 |
| a1 | 31,423 | 372 | 3,817 | 6,107 | 4,559 | 17,279 | 22,927 | 0 | 0 | 4.64→19.36 |
| a2 | 31,447 | 351 | 2,823 | 5,507 | 4,687 | 18,351 | 22,735 | 0 | 0 | 6.61→16.55 |
| a3 | 26,944 | 328 | 1,475 | 5,291 | 5,679 | 21,311 | 26,383 | 0 | 0 | 6.70→17.96 |

`stats.py` (median + MAD; floor = median − 3·MAD; hold = p99 median +10 %):
```
legs=3: c1, c2, c3
throughput  n=3 median=118374.0 MAD=1545.2 min=115550.2 max=119919.2  floor(median-3MAD)=113738.5
read_p50    n=3 median=750.0 MAD=8.0 min=742.0 max=766.0  hold(+10%)=825
read_p99    n=3 median=2299.0 MAD=6.0 min=2293.0 max=2433.0  hold(+10%)=2529
legs=3: a1, a2, a3
throughput  n=3 median=31423.4 MAD=24.1 min=26944.3 max=31447.5  floor(median-3MAD)=31351.2
read_p50    n=3 median=351.0 MAD=21.0 min=328.0 max=372.0  hold(+10%)=386
read_p99    n=3 median=5507.0 MAD=216.0 min=5291.0 max=6107.0  hold(+10%)=6058
upd_p50     n=3 median=4687.0 MAD=128.0 min=4559.0 max=5679.0  hold(+10%)=5156
upd_p99     n=3 median=22927.0 MAD=192.0 min=22735.0 max=26383.0  hold(+10%)=25220
```
**Gate reference (for the stack ticket):** C median **118,374 ops/s** (MAD 1,545 → floor 113,739); A median **31,423 ops/s**
(MAD 24 → raw floor 31,351). a3 (26,944) is a single low outlier under the same conf; with n=3 the A MAD is degenerate
(24 = 0.08 %). **D4:** when MAD < 1 % of the median, use 1 % of the median as the MAD for the floor/hold (A floor → 30,481);
the raw formula stays on record. C legs ran 5.0→57 loadavg (our own 100 client threads + server), A legs 4.6–6.7→16–19.


## Hot-symbol baseline (perf, 5M ops, `cycles:u --call-graph dwarf -F 499`, 30 s from t=20 s)
Event actually used: **`cycles` (kernel-inclusive)** — `perf_event_paranoid=-1` was open, so the script upgraded from the
ticket's `cycles:u`; `[k]` rows are kernel. Both records reported lost chunks (C 216, A 82) like the #218 probe — self-% ratios
are approximate in the tail. Runs: perfC 106,934 ops/s (5M, perf attached), perfA 31,129 ops/s. Checkpoints 0.

**C — top-15 self**
```
     2.89%  [.] __memmove_evex_unaligned_erms
     2.53%  [.] malloc
     2.42%  [.] __pthread_mutex_lock
     2.11%  [.] malloc_consolidate
     1.72%  [.] lock_internal_perform_lock_object
     1.59%  [k] rep_movs_alternative
     1.54%  [.] lock_internal_perform_unlock_object
     1.44%  [.] _int_malloc
     1.24%  [.] pgbuf_fix_release
     1.16%  [.] __tls_get_addr
     1.03%  [.] _int_free
     0.98%  [k] _raw_spin_lock
     0.92%  [k] __raw_spin_lock_irqsave
     0.84%  [k] perf_adjust_freq_unthr_context
     0.84%  [k] native_queued_spin_lock_slowpath
```
**A — top-15 self**
```
     9.71%  [.] pgbuf_get_victim_from_lru_list
     2.34%  [.] __pthread_mutex_lock
     2.16%  [.] __memmove_evex_unaligned_erms
     1.85%  [k] update_sg_lb_stats
     1.65%  [k] rep_movs_alternative
     1.65%  [k] native_queued_spin_lock_slowpath
     1.46%  [.] malloc
     1.35%  [.] pgbuf_fix_release
     1.08%  [.] lock_internal_perform_lock_object
     1.01%  [.] _int_malloc
     0.95%  [.] malloc_consolidate
     0.93%  [k] _raw_spin_lock
     0.90%  [.] lock_internal_perform_unlock_object
     0.84%  [.] __tls_get_addr
     0.82%  [.] __memset_evex_unaligned_erms
```
**Candidate target symbols (self %)**

| symbol | C | 
|---|---|
| `__tls_get_addr` | 1.16% |
| `cursor_copy_list_id` | 0.02% |
| `lock_internal_perform_lock_object` | 1.72% |
| `lock_unlock_all` | 0.06% |
| `mht_clear` | 0.77% |
| `heap_classrepr_get` | 0.09% |
| `heap_classrepr_free` | 0.03% |
| `db_value_clone` | 0.03% |
| `malloc` | 2.53% |
| `__memmove_evex_unaligned_erms` | 2.89% |
| `__pthread_mutex_lock` | 2.42% |
| `csc_current` | 0.24% |
| `db_ws_alloc` | 0.03% |
| `db_ws_free` | 0.03% |

| symbol | A |
|---|---|
| `__tls_get_addr` | 0.84% |
| `cursor_copy_list_id` | 0.01% |
| `lock_internal_perform_lock_object` | 1.08% |
| `lock_unlock_all` | 0.03% |
| `mht_clear` | 0.53% |
| `heap_classrepr_get` | 0.12% |
| `heap_classrepr_free` | 0.04% |
| `db_value_clone` | 0.02% |
| `malloc` | 1.46% |
| `__memmove_evex_unaligned_erms` | 2.16% |
| `__pthread_mutex_lock` | 2.34% |
| `csc_current` | 0.15% |
| `db_ws_alloc` | 0.03% |
| `db_ws_free` | 0.02% |

Not found above 0.1 % in either: `qmgr_attach_first_page_copy`, `lock_find_my_holder_entry`, `free` (appears as `cfree` 0.45 % C).
Observations: profile is flat (C top symbol 2.9 %); **malloc family C ≈ 7.1 %** (malloc 2.53 + consolidate 2.11 + _int_malloc 1.44
+ _int_free 1.03) → R-class memory quick-wins have visible weight; A is dominated by **`pgbuf_get_victim_from_lru_list` 9.7 %**
(10 GB DB vs 4 GB buffer under write load); `__tls_get_addr` 1.16 % / 0.84 % matches #177/#218 (G3 quick-win); `mht_clear`
0.77 % / 0.53 %; `csc_current` 0.24 % / 0.15 %. Caller decompositions: `results/base/perf{C,A}/{malloc,tls,mutex}_callers.txt`.


## G5 — memory baseline (L5 5-stage smaps_rollup, ×3 per stage)
| n | S1 boot | S2 idle conns | S3 prepared (READ+UPDATE held) | S5 closed | idle kB/conn | prepared kB/conn | retained after close | threads S1→S2 |
|---|---|---|---|---|---|---|---|---|
| 100 | 3,747,160 | 3,789,296 | 3,836,836 | 3,806,296 | **421** | **897** | 59,136 kB | 228→329 |
| 1,000 | 3,803,116 | 4,204,176 | 4,632,228 | 4,317,288 | **401** | **829** | 514,172 kB | 228→1,229 |

(Rss kB, median of 3 `smaps_rollup` samples 10 s apart; conf 1000 = `max_clients=1100`.) Slope is linear 100→1,000
(~400 kB idle, ~850 kB with one live READ+UPDATE prepared pair per connection — matches #218's 315–512 kB idle).
Retained after close ≈ 0.5 GB at 1,000 (page-buffer growth + per-session arenas not returned; not separable by RSS alone).
S3's UPDATE dirties one golden-copy row; the next leg re-copies. Tool: `scripts/ConnHold.java` (YCSB SQL shapes).


## L6 — prepare-churn baseline (C 1M ×1, `jdbc.cachestatements=false`)
`jdbc.cachestatements=false` (7-line harness patch, restored afterwards; `git status` clean on `jdbc/src`):
**12,285 ops/s**, READ p50 7,195 µs, p99 12,231 µs, 0 errors, 0 checkpoints — vs cached C median 118,374 → **prepare-per-op costs ≈9.6×**
throughput. This is the P6 (native XASL / shared prepared) measurement lever.


## Caveats
- **Shared host**: this environment is a podman container; `/proc/loadavg` is host-wide and other tenants pushed it to 300–1,200
  during the session. Idle gate (<4) took 15 / 50 / 10 / 10 / 5 min to clear; legs ran only when it was < 4. Absolute numbers
  still carry tenant noise (a3 −14 % outlier; perfA started at loadavg 21).
- **C baseline is ~20 % below the #177 gate figure** (147,013 on `7117c8a66`, 2026-09-01) but matches the #218 probe on the
  wf226 lineage (110–125 k, 2026-09-09). Either host state or a regression in wf222–wf227 — **not diagnosed here; logged as fog**.
  A is *higher* than #177 (31.4 k vs 29.1 k).
- perf used kernel-inclusive `cycles`; lost chunks as noted. p50 comes from hdr logs (YCSB 0.4.0 prints only avg/95/99).
- `run.sh` rebuilds the harness jars every leg (cwd-relative `lib` test) — before the client starts, so measurement-neutral.
- Broker CAS error logs show one benign `dynamic_load.c:1735 ER -380 "Dynamic loader already initialized"` per CAS at start.

