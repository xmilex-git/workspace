# CBRD-28031 — read-ahead hint for the heap lookups of an index scan: `ReadAhead` (the serial index scan's read-ahead window) and `KeyReadAhead` (the parallel index scan worker's look-ahead)

Engine: branch `CBRD-28031` `fb576da0b` (develop `45ca36562` + 1), worktree `~/dev/cubrid-worktree/CBRD-28031`; fork `xmilex-git/cubrid` branch `CBRD-28031`.
Parent survey: CBRD-28005 (`docs/tla/CBRD-28005/`, D34: the hint is `posix_fadvise (WILLNEED)`, reads stay synchronous; ADR 0055).

## Design tree (grilling ledger)

| # | Decision | Status | Where in the model |
|---|---|---|---|
| D1 | The hint has no parameter and always runs; the reads stay the synchronous buffered path. | settled 2026-11-11 (CBRD-28005 D42 (1), D34) | not modeled (no state) |
| D2 | A read-ahead window that holds one heap page is left unchecked only when it starts at the OID being looked up (that page is read at once); a one-page window that starts ahead of it is checked and hinted like any other. Code before: every one-page window returned (`count <= 1`). | settled 2026-11-11 (Q2: "보내긴해야지 그건"); TLC: `ReadAhead.mutant-one-page-skip.cfg` (the code before, `OnePage = "skip"`) violates C3, `ReadAhead.cfg` (`OnePage = "ahead"`) passes | `OnePage` |
| D3 | The parallel index scan's workers follow the same read-ahead rule as the serial scan: a window over the OIDs in the order the worker looks them up, across keys, the rest of a long key and its overflow OIDs (code before: the leaf OIDs of one key, at most 64 pages, keys with one OID never hinted). | settled 2026-11-11 (Q4: "병렬과 직렬이 동일한 기준이여야 할거같아") | `KeyReadAhead` (`WorkerLead`) |
| D6 | How a worker meets D3: it evaluates the next keys of its leaf page ahead of the lookups (key range, key filter, visibility: the work it does today, done earlier) and keeps each key's value and OIDs in a small queue; the window (256 OIDs, checked 128 ahead, D9) runs over the queued OIDs in lookup order, as the serial scan's over its OID buffer. An overflow page's OIDs get the same window when the page is drained. The window stops at the leaf page's end (the next leaf may go to another worker). Not taken: reading the next keys' OIDs without the filters (pages of rows the key filter rejects would be read for nothing). The window counts OIDs in lookup order, not page numbers: the pages of the next 32..64 OIDs, wherever they lie, are hinted. | settled 2026-11-11 (Q6; the user, after the window was explained as the next OIDs in lookup order: "그거라면 인정이야") | `KeyReadAhead` (`EvalAhead`, `Check`) |
| D5 | The buffer residency check may run without the hash bucket mutex: a racy walk of the bucket's chain whose answer may be wrong either way (a wrong "present" costs one synchronous read, a wrong "absent" one needless hint); BCBs are never freed while the server runs (`pgbuf_initialize_bcb_table`), and the walk is bounded. | settled 2026-11-11, confirmed by measurement (the user: "mutex 없게끔해야겠네"; perf-node1 run 20261111-160245-249, hot instructions:u over no hint, window 64 on the A/B build (the check runs once per OID whatever the window), 3 rounds, spread < 0.2%: Q20 +1.55% with the mutex vs +1.03% without, Q9 +0.78% vs +0.47%, Q7 +0.63% vs +0.46%, lineitem 0.1% +4.64% vs +3.07%) (proposed by the user: "해시 버킷 mutex 안잡고 힌트를 보내면 빠를거같아. 어차피 대강 맞으면 되는거니까"; Q5 "그렇게 해": C3 is stated over checked windows, not over correct answers) | `Probe = "racy"` (`ReadAhead.cfg`; `ReadAhead.option-locked.cfg` checks the mutex variant) |
| D7 | The look-ahead of D6 changes nothing a user sees in a parallel index scan: a key filter error found while evaluating ahead is cleared and stops the look-ahead, and the key is evaluated again (raising the error) when the lookups reach it; a key's trace counters (`qualified_keys`, `key_qualified_rows`, `read_rows`) are added when its OIDs are looked up, not when it is evaluated ahead. | settled 2026-11-11 (Q7: "응 추천대로. 안고치고 그대로 둬" = the behavior stays as today's parallel scan) | `ErrAt = "defer"`, `CountAt = "consume"`; mutants `error-early`, `count-at-eval` |
| D8 | Worker claims C7 (a lookup reads its own key's value), C8 (queued key values cleared once on every exit), C11 (the leaf's range end signaled only after the queue drained) adopted. | settled 2026-11-11 (Q8: "그래") | `KeyReadAhead` |
| D4 | No exponential backoff: every window is checked against the buffer, whether or not the previous windows found their pages there. The backoff (64 -> 65,536 OIDs serial, 1 -> 1,024 keys a worker) was added without measurement (session 1, 2026-11-11: no hot number without it; caps chosen without a record); PostgreSQL has none (`REL_17_0` `BitmapPrefetch` calls `PrefetchBuffer` for every block; master's read stream checks every block and only shortens its distance on hits). With it, claims C4..C6 and their mutants are dropped. | settled 2026-11-11 (the user: "이건 안할거니까 없애") | no `Cap`, no skip state |
| D9 | The read-ahead distance is 256 OIDs (`SCAN_INDEX_READ_AHEAD_DISTANCE`, serial scan and worker alike), checked half a window (128 OIDs) ahead. Measured cold (TPC-H SF10, release, interleaved; perf-node0 HDD RAID, run 20261111-160118-248, two rounds; this host's NVMe one round): Q20 none 130.3/130.0 s, 32: 53.3/54.7, 64: 52.7/54.6, 256: 49.2/49.5, 512: 48.4/48.7 (perf-node0); Q9 none 101.2/87.5, 32..512: 54..63; on NVMe 32..512 within noise. | settled 2026-11-11 (the user: "그럼 256으로 해야겟네") | `D` (the models check D = 4 and 6; the bound is not a claim) |

## Claim and sources

| # | Claim | Kind | Source |
|---|---|---|---|
| C1 | The lookups take the OIDs of every OID buffer once, in buffer order: the hint changes neither the rows nor their order. | equivalence | JIRA body, Specification Changes ("질의 결과와 행 순서도 지금과 같습니다") |
| C2 | A window lies inside the OID buffer, starts at or after the OID being looked up and holds at most 256 OIDs (`vpids[SCAN_INDEX_READ_AHEAD_DISTANCE]`). | safety | `scan_manager.c` `scan_index_read_ahead` (array bound) |
| C3 | (serial; for a worker: `WorkerLead`, the same over its OIDs in lookup order up to the leaf's end or an erroring key) Every OID from the one being looked up to 128 ahead has been in a window whose pages were checked against the buffer before its lookup (the pages the check found absent handed to the OS; the check may be wrong when another thread loads or evicts the page meanwhile) or is on the page being looked up. | safety | JIRA body (re-drafted 2026-11-11), Implementation ("조회할 OID부터 256개 ... 절반(128개)을 조회했을 때 다음 창을 알립니다"); design.md "직렬 인덱스 스캔" |
| C7 | A worker's lookup reads the key value of the OID's own key, never a key evaluated ahead (`m_slot_key`: covering reads, GROUP BY skip). | safety | D8 (Q8) |
| C8 | When a worker stops or ends (end of leaf, LIMIT, interrupt, error, reset), every key value the look-ahead copied is cleared, once. | safety | D8 (Q8); `pr_clear_value` ownership of `COPY` keys |
| C9 | A key filter error is raised only when the lookups reach its key, as without the look-ahead. | equivalence | D7 (Q7) |
| C10 | The trace counters count the keys whose OIDs were looked up, as without the look-ahead. | equivalence | D7 (Q7) |
| C11 | The leaf's range end (`signal_chain_ended`) is signaled only after the last queued key was drained. | safety | D8 (Q8) |


## Refinement map — `ReadAhead` (serial index scan)

| Model | Code (`CBRD-28031`) | One step because |
|---|---|---|
| `Fill` | `scan_manager.c:call_get_next_index_oidset` tail: `ahead_next` set after `scan_get_index_oidset` fills `oid_list` | single owner: the scan's `INDX_SCAN_ID` is private to its thread; no shared state is read |
| `Check` | `scan_manager.c:scan_next_index_scan` (`curr_oidno + SCAN_INDEX_READ_AHEAD_DISTANCE / 2 >= ahead_next`) then `scan_index_read_ahead`: window `[MAX (ahead_next, curr_oidno), MIN (oids_count, curr_oidno + 256))`, `ahead_next` moved to the window's end, `pgbuf_read_ahead` unless the window is the one page being looked up | the window is private; the only shared read is the residency check of each page, whose outcome the model draws freely (`resident` is any set under `Env`, and with `Probe = "racy"` any answer): a per-page split would reach no other combination |
| `Look` | `scan_next_index_lookup_heap` -> `heap_get_visible_version` -> `pgbuf_fix` of the OID's page; then `curr_oidno++` (non-grouped branch) or a refill | the fix loads the page (`resident`); the cursor is private |
| `Env` | other threads' `pgbuf_fix` (claim and read of a BCB) and victimization (`pgbuf_victimize_bcb`) | changes `resident` at any point between steps |
| `racyHinted` (Probe = "racy") | `page_buffer.c:pgbuf_read_ahead`: chain walk with relaxed loads, no `hash_mutex`, at most `PGBUF_READ_AHEAD_MAX_CHAIN_STEPS` BCBs | the answer may be wrong either way (D5) |
| `posix_fadvise` | `file_io.c:fileio_read_ahead_hint` | no state the scan reads afterwards: not a model variable beyond `served` |

Exit paths of the serial scan (P11): end of the OID buffer -> `Fill`; end of scan (`S_END` from `call_get_next_index_oidset`) -> `phase = "end"`; `scan_reset_scan_block`, `scan_start_scan` (`curr_oidno = -1`, position `S_BEFORE`) -> the next `Fill`, which resets `ahead_next`; grouped scans (`scan_id->grouped`), multi-range optimization, count-only and covering scans never set `ahead_next` (stays `INT_MAX`), so `Check` never fires; error or interrupt from the lookup leaves the scan with no further `Check`.

Guard whose removal violates nothing: `MAX (ahead_next, curr_oidno)` (mutant `start_at_next` not kept): `ahead_next` never falls below `curr_oidno` because `curr_oidno` moves by one per lookup (`scan_manager.c` non-grouped branch `curr_oidno++`) and every `Check` that fires moves `ahead_next` past `curr_oidno + 128` (or to `INT_MAX`); the guard is defensive.

Dead expressions: the `Mutant = "late_trigger"`, `"no_count_bound"` and `"cursor"` arms of `Check` (mutant-only).

## Refinement map — `KeyReadAhead` (parallel index scan worker, D6/D7)

| Model | Code (`CBRD-28031` `fb576da0b`) | One step because |
|---|---|---|
| `EvalAhead` | `px_scan_index_leaf_slot_walker.cpp:leaf_slot_walker::evaluate_ahead` -> `evaluate_slot (ahead = true)`: record of `m_page` at `m_ahead_slot`, `check_key_in_range`, key filter, `btree_record_process_objects` with the snapshot; the qualified key is pushed on `m_ahead` with its `read_keys` | the leaf is held (S latch, the producer keeps it through the leaf-OID drain) and the walker's state is private; the key is copied (`COPY`), the OIDs copied |
| `EvalAhead` error branch (`ErrAt = "defer"`) | `stop_at_error (ahead = true)`: `er_clear`, no `signal_chain_ended`; `evaluate_ahead` restores `m_current_range_idx` to its value before that slot, records the slot as `m_ahead_slot` and returns false; `scan_next_slot` resumes there and reads it again | private |
| `EvalStop` / range end | `evaluate_slot` returns `END` ahead without signaling; consumption reads the slot again and signals (`scan_next_slot` -> `evaluate_slot (ahead = false)`) | private; the signal is the only shared write and happens at consumption (C11) |
| `WindowDone` at the barrier (`ev` stays); `Fresh` with `ev >= ck` (no second evaluation) | `evaluate_ahead` returning false (leaf end, range end, error, or only skipped keys left) sets `m_ahead_end`, `m_ahead_slot` (the stop slot: the erroring or past-range slot, or past the leaf) and `m_ahead_skipped_keys`; `read_ahead` then returns at once; when the queue is empty `scan_next_slot` resumes at `m_ahead_slot`, adds the skipped slots' `read_keys` and clears the flag, so only the stop slot is read again (it raises the error or signals the end, C9/C11). The model's `ev` never moves back and the lookups do not evaluate a key `<= ev`; `fb576da0b` evaluated the skipped slots again once per lookup and once more in `scan_next_slot` (PR #8490 review; cubrid-tla P81) | private |
| `Check` | `leaf_slot_walker::read_ahead`, called from `process_oid`'s non-covering path: positions from the OID being looked up through the drain's buffer (`overflow_drain_fsm::buffer`, `buffer_next`) and, when `next_is_next_key`, the queued keys' OIDs, up to `SCAN_INDEX_READ_AHEAD_DISTANCE`; `m_ahead_hinted` is the frontier | private; the residency check is `ReadAhead`'s |
| `Look` | `process_oid` (non-covering): `heap_get_visible_version` | as `ReadAhead.Look` |
| `NextKey` | `scan_next_slot`: pops `m_ahead` (`m_current_slot = next_slot`), adds the key's counters (`read_keys`, `qualified_keys`, `key_qualified_rows`, `read_rows`), sets `m_slot_key`, `begin_key_record`, `begin_leaf_drain` | private |
| `Stop`, `ErrorCleanup` | `clear_ahead` (clears the queued keys' values): `cleanup_on_reset` (reset, finalize), `set_page` (asserts the queue is empty: a leaf's walk ends only after its queue drained), `overflow_drain_fsm::set_overflow_page` (helper session) | private |
| (not modeled: overflow pages) | `overflow_drain_fsm::process_one_overflow_page` calls `restart_read_ahead`: each overflow page's OIDs are a sequence of their own (a `ReadAhead` buffer) | |

Shared state the look-ahead could touch, and why it does not change a lookup's inputs: `isidp->key_attrs` (the key filter's attribute cache) is overwritten by a key evaluated ahead while the current key's rows are looked up; the non-covering lookup reads `pred_attrs` and `rest_attrs` from the heap record, not `key_attrs`, as in the serial scan, whose OID buffer is filled (key filter evaluated) before any of its lookups. Covering scans do not look ahead (`read_ahead` is called on the non-covering path only).

## Fault model

| Fault | Where it can fire | In the models |
|---|---|---|
| error return | `pgbuf_read_ahead` and `fileio_read_ahead_hint` return nothing (a failed `posix_fadvise` is ignored); the worker's key evaluation ahead (`btree_read_record`, `check_key_in_range`, key filter `V_ERROR`, `btree_record_process_objects`) | serial: not applicable (the hint has no error path); worker: `errKey` with `ErrAt` (D7: cleared ahead, raised when the lookups reach the key) |
| interrupt / query cancel, LIMIT | the worker is reset (`cleanup_on_reset`) between any two steps | `Stop` from every live phase (C8) |
| lock timeout, deadlock victim | no lock is requested by the hint or the look-ahead | not applicable |
| conditional latch failure | none: the hint fixes no page; the look-ahead reads the leaf the worker already holds | not applicable |
| OOM | `std::deque::push_back`, `std::vector` copies of a key's OIDs (`std::bad_alloc` as on the existing `leaf_oids` vector) | not modeled: the same failure class as the existing leaf-OID vector of the walker |
| crash / `kill -9` | the hint writes nothing durable | not applicable |
| spurious wakeup | no condition wait | not applicable |
| concurrent DML | pages loaded and victimized by other threads between the check and the fix | `Env` (serial, `Probe = "locked"`), the racy answer (`Probe = "racy"`, D5); results unaffected (C1) |
| vacuum | a hinted page vacuum frees: `posix_fadvise` of a freed page reads it into the OS cache only | not applicable (no state) |
| checkpoint, page flush, page replacement | as concurrent DML | `Env` |
| HA log apply | nothing replicated | not applicable |
| nested statement (SP SQL) | the look-ahead evaluates visibility with the scan's snapshot (`isidp->scan_cache.mvcc_snapshot`), as the walker does today when it reaches the key | not modeled: the same snapshot read, earlier |

Environment assumptions: none for liveness (no liveness claim); `Env` has no fairness.

## Mutants and witnesses

| Cfg | Removes | Rejected by |
|---|---|---|
| `ReadAhead.mutant-one-page-skip` | D2: every one-page window left unchecked (the code before D2) | C3 `Lead` |
| `ReadAhead.mutant-cursor` | the window loop moves the lookup cursor | C1 `LookupOrder` |
| `ReadAhead.mutant-no-count-bound` | `MIN (oids_count, ...)` | C2 `WindowBound` |
| `ReadAhead.mutant-late-trigger` | the half-window lead (`curr + 128 >= ahead_next` -> `curr >= ahead_next`) | C3 `Lead` |
| `KeyReadAhead.mutant-slot-key-latest` | `m_slot_key` set at evaluation instead of at the pop | C7 `KeyPairing` |
| `KeyReadAhead.mutant-leak-queue` | `clear_ahead` on reset | C8 `NoKeyLeak` |
| `KeyReadAhead.mutant-error-early` | D7 error deferral (`stop_at_error (ahead = true)`) | C9 `ErrorInOrder` |
| `KeyReadAhead.mutant-count-at-eval` | D7 counters at the pop | C10 `CountsConsumed` |
| `KeyReadAhead.mutant-end-at-eval` | no `signal_chain_ended` when evaluating ahead | C11 `EndAfterDrain` |
| `KeyReadAhead.mutant-late-window` | the half-window lead in `read_ahead` | C3 `WorkerLead` |
| `ReadAhead.witness-hinted` | a page is hinted | reachable |
| `KeyReadAhead.witness-queued` | a key evaluated ahead while an earlier key is looked up | reachable |
| `ReadAhead.option-locked` | (D5 not taken) the residency check under the bucket mutex | passes too: the claims do not depend on the check's answer |

Dead expressions: `KeyReadAhead.tla:169`, `KeyReadAhead.tla:170`, `KeyReadAhead.tla:172`, `KeyReadAhead.tla:173` — `EvalAhead`'s `ErrAt = "early"` branch (mutant-only: `mutant-error-early`); `ReadAhead.tla` none in the main cfg.

## Trace validation

Instrumented build: scratch worktree `CBRD-28031-instr`, base `9fa4fa661` (the tree of the gated commit before its whitespace-only reformat, now `fb576da0b`) plus uncommitted `TLATRACE` lines (159 added, none removed), optdebug install `~/optdebug/CUBRID-CBRD-28031-instr`, libcubrid sha256 `46bfffb7…`. Events: serial `Fill` (the buffer's pages), `Check` (fired, start, stop, skipped, the pages hinted, from a thread-local list in `pgbuf_read_ahead`), `Look`; worker `WLeaf`, `WEval` (ahead, OIDs, overflow), `WEvalStop`, `WPop`, `WNoWin`, `WWin` (start, position, count), `WLook`, `WNext`, `WStop`, `WClear`, `WOvf`. `traces/convert.py` turns a log (`traces/raw/*.log.xz`, `xz -dk` first) into a data module (serial: the scan with the most `Fill` events; worker: a walker's segment on one leaf that popped a queued key, the largest first).

| Trace | Query (DB `ra28031`, 400,000 rows; `index_scan_oid_buffer_size` 4K serial, 1K parallel) | Cfg | Expect |
|---|---|---|---|
| ser1 | `k between 100 and 600` on `i_ra_k` (several OIDs a key) | `ReadAheadTrace.witness-trace-ser1` | accepted (`TraceNotDone` violated) |
| ser2 | `id between 100 and 1500 and v >= 0` on `ra_n` (one OID a key, heap pages in index order) | `ReadAheadTrace.witness-trace-ser2` | accepted |
| par1s0 | `parallel(4)`, `u between 1000 and 60000` on the unique `i_ra_u` | `KeyReadAheadTrace.witness-trace-par1s0` | accepted |
| par2s0 | `parallel(4)`, `k between 100 and 20000 and s like '1%'` on `i_ra_ks` (key filter) | `KeyReadAheadTrace.witness-trace-par2s0` | accepted |
| par3s0 | `parallel(4)`, `cast(s as int) >= 0` on `i_ra_ks` (key filter error) | `KeyReadAheadTrace.witness-trace-par3s0` | accepted |
| par4s0 | `parallel(4)`, `k between 100 and 20000` on `i_ra_k` | `KeyReadAheadTrace.witness-trace-par4s0` | accepted |
| ser1, corrupted | two lookups swapped / one fired check dropped / a check's `fired` flipped / a page never in the window hinted | `ReadAheadTrace.reject-{swap-look,drop-check,flip-fired,foreign-hint}` | rejected (`TraceNotDone` holds) |
| par1s0, corrupted | a window's position off by one / one evaluation ahead dropped | `KeyReadAheadTrace.reject-{pos-off,drop-eval}` | rejected |

`Check` and `NextKey` of the worker are hidden steps of `KeyReadAheadTrace` (the slot iterator moves to the next key without an event); `WNext` is a marker that requires `phase = "fresh"`.

## Result

2026-11-11, `tools/tla/tla-check docs/tla/CBRD-28031`: **RESULT: OK** (31 cfgs, all PASS). Run dir
`.git_ignored_dir/scratch/tla/CBRD-28031-20261111-190601-2666250`, log `.git_ignored_dir/scratch/cbrd28031/tla-record.log`.
Engine: `fb576da0b` (develop `45ca36562` + 1; whitespace-only diff to the gated `42b58497f`). Trace runs on the
instrumented optdebug build above, libcubrid sha256 `46bfffb7fd18b10fbf6d5b66292f932d00ff770342683f771114398fc498c097`.

| cfg | Result | States / distinct | Depth |
|---|---|---|---|
| `ReadAhead` (window 256/128, no mutex, no backoff) | pass | 28,518,240 / 5,580,960 | 29 |
| `ReadAhead.scale-d6` | pass | 28,909,872 / 5,653,152 | 29 |
| `ReadAhead.option-locked` (D5 not taken) | pass | 28,518,240 / 5,580,960 | 31 |
| `ReadAhead.mutant-cursor` | `LookupOrder` violated (killed) | 766,120 / 351,296 | 4 |
| `ReadAhead.mutant-no-count-bound` | `WindowBound` violated (killed) | 324,580 / 128,020 | 3 |
| `ReadAhead.mutant-late-trigger` | `Lead` violated (killed) | 3,886,960 / 930,744 | 7 |
| `ReadAhead.mutant-one-page-skip` | `Lead` violated (killed) | 3,886,963 / 930,747 | 7 |
| `ReadAhead.witness-hinted` | reached | 324,640 / 128,032 | 3 |
| `ReadAhead.apalache-indinv` | IndInv inductive | — | 1 step |
| `KeyReadAhead` (worker look-ahead) | pass | 15,383 / 9,437 | 38 |
| `KeyReadAhead.scale-5keys` | pass | 67,362 / 41,206 | 47 |
| `KeyReadAhead.mutant-slot-key-latest` | `KeyPairing` violated (killed) | 4,396 / 3,137 | 6 |
| `KeyReadAhead.mutant-leak-queue` | `NoKeyLeak` violated (killed) | 3,628 / 2,494 | 5 |
| `KeyReadAhead.mutant-error-early` | `ErrorInOrder` violated (killed) | 2,739 / 2,066 | 4 |
| `KeyReadAhead.mutant-count-at-eval` | `CountsConsumed` violated (killed) | 1,227 / 1,224 | 3 |
| `KeyReadAhead.mutant-end-at-eval` | `EndAfterDrain` violated (killed) | 4,375 / 3,123 | 6 |
| `KeyReadAhead.mutant-late-window` | `WorkerLead` violated (killed) | 9,904 / 6,360 | 13 |
| `KeyReadAhead.witness-queued` | reached | 3,656 / 2,522 | 5 |
| `KeyReadAhead.apalache-indinv` | IndInv inductive | — | 1 step |
| `ReadAheadTrace.witness-trace-ser1` / `-ser2` | accepted | 4,013 / 2,806 | 4,013 / 2,806 |
| `ReadAheadTrace.reject-{swap-look,drop-check,flip-fired,foreign-hint}` | refused | 13 / 258 / 4 / 2 | — |
| `KeyReadAheadTrace.witness-trace-par1s0` … `par4s0` | accepted | 1,320 / 225 / 4,629 / 4,704 | same |
| `KeyReadAheadTrace.reject-{pos-off,drop-eval}` | refused | 31 / 30 | — |

Dead expressions: `KeyReadAhead.tla:169`, `:170`, `:172`, `:173` only, explained above. TLAPS 요청 없음.

After this run the engine moved to `998b18c63` (PR #8490 review: the worker's look-ahead re-evaluated skipped slots once per lookup). The model is unchanged (its `ev` already never moves back; the refinement rows `WindowDone` at the barrier and the `EvalAhead` error branch now name `m_ahead_end` / `m_ahead_slot` / `m_ahead_skipped_keys`). The recorded traces above are of the build before that fix; the trace spec took the repeated `WEvalStop` as a stutter (cubrid-tla P82), so they do not show the fix.

Spec sha256 (as checked; `MAP.md`'s line is the file before this section):

```
985b1cea64f739e13b21981c1692f3592e503f58121804874375138e15cd4c6f  KeyReadAhead.tla
eea609336c95171da2f817bc4f1b6b459366a104d6f8b7bdfaa449b56c80ab47  KeyReadAheadTrace.tla
7e1847bedf4ba2898907cf34ae27e0f4050176e3e1f2b69d4476e33fe58ba0b3  KeyReadAheadTraceData.tla
e6c44f6d389bc83be161b5abb667330f0dff16cd179419cf9750f925ce3283f7  ReadAhead.tla
d14cba928f786ed053ecd0954c25e1647cb00fe542e0d215e31c15917f70dd2c  ReadAheadTrace.tla
572222be557b9c8273aebcf37739a4b1669880ff21f2744a9c20095569bc660e  ReadAheadTraceData.tla
8a080e02d26c169bc568b070ae4ecb64f3e68eb4562f933b99ffc4b1f4f2e41d  MAP.md
```
