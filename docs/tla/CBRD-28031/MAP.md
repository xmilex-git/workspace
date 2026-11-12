# CBRD-28031 — read-ahead hint for the heap lookups of an index scan: `ReadAhead` (the serial index scan's read-ahead window) and `KeyReadAhead` (the parallel index scan worker's look-ahead)

Engine: branch `CBRD-28031` `134354740` (develop `4255a337d` + 3; the model of D1..D9 was first checked on `fb576da0b`), worktree `~/dev/cubrid-worktree/CBRD-28031`; fork `xmilex-git/cubrid` branch `CBRD-28031`.
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
| D10 | A key the key range or the key filter rejects takes no queue entry: the worker's key evaluation (`next_key`) passes the rejected keys inside one loop and returns only a key that qualifies (or the leaf's end, the range's end, an error), for the look-ahead and the lookups alike; the look-ahead never evaluates a key twice: when it finds no more key to queue it records where it stopped and the lookups resume there (the stop key, an error or the range's end, is the only key read twice). Measured on hot instructions (release, `parallel(4)`, 400,000 rows, against develop `4255a337d`): `s like '1%'` key filter +3.6% (`67a924189`) -> +1.8%, `mod(k,100)` +4.3% -> +0.4%. | settled 2026-11-12 (the user: "필터에서 떨어지는 키는 큐 항목을 만들지 않게") | `rej`, `EvalAhead` and `Fresh` over `FirstKept`; C12, C13 |
| D11 | A worker whose scan has no heap lookup (covering index) keeps no queue, computes no window and checks no page against the buffer: `process_oid`'s covering path returns before `read_ahead`, the only caller of `evaluate_ahead` and `pgbuf_read_ahead`. The key loop is inlined into its callers so a covering scan runs the same loop as before (hot instructions against develop: covering `k` +1.2% with the loop alone, +0.3% inlined; covering with a key filter -0.1%). | settled 2026-11-12 (the user: "covering index scan처럼 lookup을 안해도 되면 큐가 있어야해? 창계산 및 버퍼 적중 확인도 안해도 되자나?") | `cov`; C14 |
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
| C10 | The trace counters count the keys whose OIDs were looked up (`qualified_keys`), and every key read once (`read_keys`), as without the look-ahead. | equivalence | D7 (Q7); `read_keys` once: PR #8490 review (Greptile), D10 |
| C11 | The leaf's range end (`signal_chain_ended`) is signaled only after the last queued key was drained. | safety | D8 (Q8) |
| C12 | A worker evaluates every key of its leaf (read, key range, key filter) once, as without the look-ahead; only the key the look-ahead stopped at (an error; the key past the range's end takes the same path) is evaluated once more, by the lookups. | safety (cost) | PR #8490 review (Greptile P2), D10 |
| C13 | A key the key range or the key filter rejects takes no queue entry: its copied value is cleared when it is read. | safety | D10 |
| C14 | A worker whose scan has no heap lookup (covering index) never evaluates a key ahead and never checks a window. | safety | D11 |


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

## Refinement map — `KeyReadAhead` (parallel index scan worker, D6/D7/D10/D11)

| Model | Code (`CBRD-28031` `134354740`) | One step because |
|---|---|---|
| `rej`, `FirstKept` | `px_scan_index_leaf_slot_walker.cpp:leaf_slot_walker::next_key`: the loop over the slots of `m_page` from `*slot`; a key outside the range (not past it), a NULL first index term, or a key filter `V_FALSE`/`V_UNKNOWN` is cleared (`pr_clear_value`) and the loop goes on (`continue`); fence and unreadable slots are not keys (not counted in `read_keys`) | the leaf is held (S latch) and the walker's state is private |
| `EvalAhead`, a key qualifies | `leaf_slot_walker::evaluate_ahead` -> `next_key (ahead = true)`: the rejected keys, then the qualifying key with its visible OIDs (`btree_record_process_objects` with the snapshot), pushed on `m_ahead` with its `read_keys` (the rejected keys before it, itself included); `m_ahead_slot` after it | private; the key is copied (`COPY`), the OIDs copied |
| `EvalAhead`, stop (`n = NK + 1` or `n = errKey`; `aend`, `errAhead`) | `next_key` returns `LEAF_END`, or `END`/`ERROR` through its `stop` lambda (ahead: `*slot`, `*read_keys`, `m_current_range_idx` back to the stop key; `stop_at_error (ahead = true)` clears the error, no `signal_chain_ended`); `evaluate_ahead` sets `m_ahead_slot`, `m_ahead_skipped_keys`, `m_ahead_end` | private; the signal is the only shared write and happens at consumption (C11) |
| `WindowDone` (D OIDs, or `aend`) | `read_ahead` after its loop: `m_ahead_hinted = pos - 1`, `pgbuf_read_ahead` of the window's pages | private; the residency check is `ReadAhead`'s |
| `Check` | `process_oid`: covering path (`cov`) returns before `read_ahead`; `read_ahead` returns at once when `m_ahead_end` (`aend`), decrements `m_ahead_hinted` when more than 128 ahead are hinted, else fires (positions from the OID being looked up through the drain's buffer and, when `next_is_next_key`, the queued keys' OIDs) | private |
| `Look` | `process_oid`: covering path (key values from `m_slot_key`), non-covering `heap_get_visible_version` | as `ReadAhead.Look` |
| `Fresh`, `n <= ev` | `scan_next_slot`: `m_ahead.pop_front`, `m_current_slot = next_slot`, the key's counters (`read_keys`, `qualified_keys`, `key_qualified_rows`, `read_rows`), `m_slot_key`, `begin_key_record`, `begin_leaf_drain` | private |
| `Fresh`, `n > ev` | `scan_next_slot`, queue empty: when `m_ahead_end`, `m_current_slot = m_ahead_slot` and `read_keys += m_ahead_skipped_keys` (the keys `ck..ev` the look-ahead passed), then `next_key (ahead = false)`: the rejected keys, then a qualifying key (`m_ahead_hinted = 0`), the error (`stop_at_error` raises it, `signal_chain_ended`), the range's end (`signal_chain_ended`, `S_END`) or the leaf's end (`S_END`) | private |
| `NextKey` | `scan_next_slot`'s loop after `drain_next_oid` returned `S_END` for the key | private |
| `Stop` | `clear_ahead` (clears the queued keys' values, `m_ahead_end`): `cleanup_on_reset` (reset, finalize), `set_page` (asserts the queue is empty), `overflow_drain_fsm::set_overflow_page` (helper session) | private |
| (not modeled: overflow pages) | `overflow_drain_fsm::process_one_overflow_page` calls `restart_read_ahead`: each overflow page's OIDs are a sequence of their own (a `ReadAhead` buffer) | |

The model's keys are the keys `next_key` reads; a rejected key has no OID (`KeysWf`), and the range's end is the leaf's end of the model (`n = NK + 1`): the key past it is read twice like an erroring key, by the same `stop` lambda, but is not a model key. `ev` (the last key evaluated) never moves back (cubrid-tla P81): in the code it is `m_ahead_slot`, kept on every return of `evaluate_ahead`.

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
| `KeyReadAhead.mutant-no-stop-mark` | the stop mark (`m_ahead_end`, `m_ahead_slot` at the stop): the look-ahead and the lookups read the passed keys again (the code of `2ecbf72b2`, PR #8490 review) | C12 `EvalOnce` |
| `KeyReadAhead.mutant-skip-count-lost` | `read_keys += m_ahead_skipped_keys` at the resume | C10 `CountsConsumed` |
| `KeyReadAhead.mutant-queue-rejected` | D10: a rejected key kept as a queue entry (its value copied and held) | C13 `NoRejectedEntry` |
| `KeyReadAhead.mutant-covering-window` | D11: the covering path calls `read_ahead` | C14 `NoWindowWithoutLookup` |
| `ReadAhead.witness-hinted` | a page is hinted | reachable |
| `KeyReadAhead.witness-queued` | a key evaluated ahead while an earlier key is looked up | reachable |
| `KeyReadAhead.witness-skipped-stop` | the look-ahead passed a rejected key and stopped at the leaf's end before the lookups reached it | reachable |
| `KeyReadAhead.witness-error-twice` | the key the look-ahead stopped at on an error is raised by the lookups | reachable |
| `KeyReadAhead.witness-covered-done` | a covering scan drains a leaf with OIDs | reachable |
| `ReadAhead.option-locked` | (D5 not taken) the residency check under the bucket mutex | passes too: the claims do not depend on the check's answer |

Dead expressions: `KeyReadAhead.tla:229`, `KeyReadAhead.tla:230`, `KeyReadAhead.tla:232`, `KeyReadAhead.tla:233`, `KeyReadAhead.tla:234` — `EvalAhead`'s `ErrAt = "early"` branch (mutant-only: `mutant-error-early`); `KeyReadAhead.tla:250` — the `no_stop_mark` arm of the stop (mutant-only: `mutant-no-stop-mark`); `ReadAhead.tla` none in the main cfg.

## Trace validation

Serial (`ReadAhead`): instrumented build of 2026-11-11 (scratch worktree on `9fa4fa661`, the tree of the gated commit before its whitespace-only reformat `fb576da0b`, plus 159 `TLATRACE` lines; optdebug, libcubrid sha256 `46bfffb7…`). The serial code (`scan_manager.c`, `page_buffer.c`, `file_io.c`) has not changed since; events `Fill` (the buffer's pages), `Check` (fired, start, stop, skipped, the pages hinted, from a thread-local list in `pgbuf_read_ahead`), `Look`.

Worker (`KeyReadAhead`): instrumented build of 2026-11-12, scratch worktree `CBRD-28031-instr` = the tree of `134354740` plus `TLATRACE` lines only (the serial ones above, and in the walker: one line removed, `next_key`'s result kept in a variable to log it), optdebug install `~/optdebug/CUBRID-CBRD-28031-instr`, libcubrid sha256 `0a54381cc423eda8…`. Events: `WLeaf` (cov), `WKey` (every `next_key` call: ahead or not, result `Q`/`LEAF`/`END`/`ERR`, the keys it read, the OIDs), `WPop` (the key's `read_keys`), `WResume` (`m_ahead_skipped_keys`), `WWin` (start, position, count), `WEnded` (`read_ahead` returning at once after the stop), `WNoWin`, `WLook` (covering and non-covering), `WNext`, `WClear`, `WOvf`. `traces/convert.py worker <log> <Name> <k> <need>` cuts one walker's segment on one leaf (from `WLeaf` to its next `WClear`, no overflow page), the k-th smallest that has `<need>` (`pop`, `resume`: a resume past rejected keys, `err`: an error found ahead and raised by the lookups, `cov`), and rebuilds the leaf's keys from the `WKey` lines (rejected keys, OID counts, the erroring key). Logs `traces/raw/n*.log.xz` (`xz -dk` first).

| Trace | Query (DB `ra28031`, 400,000 rows; `index_scan_oid_buffer_size` 1K, `parallel(4)`) | Segment | Cfg | Expect |
|---|---|---|---|---|
| ser1 | `k between 100 and 600` on `i_ra_k` (serial, buffer 4K) | — | `ReadAheadTrace.witness-trace-ser1` | accepted (`TraceNotDone` violated) |
| ser2 | `id between 100 and 1500 and v >= 0` on `ra_n` (serial) | — | `ReadAheadTrace.witness-trace-ser2` | accepted |
| n1 | `u between 1000 and 60000` on the unique `i_ra_u` | 170 keys, 683 events | `KeyReadAheadTrace.witness-trace-n1` | accepted |
| n2 | `k between 100 and 20000 and s like '1%'` on `i_ra_ks` (key filter) | 271 keys, 243 rejected, 115 events | `KeyReadAheadTrace.witness-trace-n2` | accepted |
| n3 | `k between 0 and 100003 and cast(s as int) >= 0` on `i_ra_ks` (key filter error) | 127 keys, the last erroring, 507 events | `KeyReadAheadTrace.witness-trace-n3` | accepted |
| n4 | `k between 100 and 20000` on `i_ra_k` | 286 keys of 4 OIDs, 2,863 events | `KeyReadAheadTrace.witness-trace-n4` | accepted |
| n5 | `count(*), sum(k)` with `s like '1%'` on `i_ra_ks` (covering) | 271 keys, 243 rejected, 58 events | `KeyReadAheadTrace.witness-trace-n5` | accepted |
| ser1, corrupted | two lookups swapped / one fired check dropped / a check's `fired` flipped / a page never in the window hinted | — | `ReadAheadTrace.reject-{swap-look,drop-check,flip-fired,foreign-hint}` | rejected (`TraceNotDone` holds) |
| n1, n2 corrupted | a window's position off by one (n1) / one key evaluated ahead dropped (n1) / the resume's skipped keys one short (n2) | — | `KeyReadAheadTrace.reject-{pos-off,drop-eval,skip-off}` | rejected |

`Check` and `NextKey` are hidden steps of `KeyReadAheadTrace`; `WResume`, `WEnded`, `WNoWin`, `WNext` are markers that check the state they find (`WResume`: the keys `ck..ev` the look-ahead passed equal `m_ahead_skipped_keys`). In the whole n2 log (all workers, all leaves), 8,837 lookups saw 125 windows and 8,712 `WEnded` returns, and the keys the `WKey` lines read add up to the counted `read_keys` (79,606 = the lookups' `WKey` + `WPop` + `WResume`): no key was evaluated twice except the one key past the range's end the look-ahead stopped at (its ahead read is rewound out of `read_keys`). Before `67a924189` the same query re-evaluated the passed keys once per lookup (8,837 `WEvalStop`).

## Result

2026-11-12, `tools/tla/tla-check docs/tla/CBRD-28031`: **RESULT: OK** (40 cfgs, all PASS). Run dir
`.git_ignored_dir/scratch/tla/CBRD-28031-20261112-084519-461989`, log `.git_ignored_dir/scratch/cbrd28031/tla-record2.log`.
Engine: `134354740` (develop `4255a337d` + 3). Worker traces on the instrumented optdebug build of that tree (libcubrid
sha256 `0a54381cc423eda8…`); serial traces on the build of 2026-11-11 (`46bfffb7…`; serial code unchanged since).
Gate of `134354740`: optdebug `aa9dc3789e99e966…` / release `fe77d86e72157530…`; CTP sql 17,781 OK / 0 NOK and medium
975 OK (`sql-20261111T232328Z-142034`); smoke equal to develop on optdebug, release and the memory check.

| cfg | Result | States / distinct | Depth |
|---|---|---|---|
| `ReadAhead` (window 256/128, no mutex, no backoff) | pass | 28,518,240 / 5,580,960 | 29 |
| `ReadAhead.scale-d6` | pass | 28,909,872 / 5,653,152 | 29 |
| `ReadAhead.option-locked` (D5 not taken) | pass | 28,518,240 / 5,580,960 | 31 |
| `ReadAhead.mutant-cursor` | `LookupOrder` violated (killed) | 766,124 / 351,296 | 4 |
| `ReadAhead.mutant-no-count-bound` | `WindowBound` violated (killed) | 324,580 / 128,020 | 3 |
| `ReadAhead.mutant-late-trigger` | `Lead` violated (killed) | 3,886,956 / 930,744 | 7 |
| `ReadAhead.mutant-one-page-skip` | `Lead` violated (killed) | 3,886,952 / 930,744 | 7 |
| `ReadAhead.witness-hinted` | reached | 324,640 / 128,032 | 3 |
| `ReadAhead.apalache-indinv` | IndInv inductive | — | 1 step |
| `KeyReadAhead` (worker look-ahead, D10/D11) | pass | 61,232 / 37,938 | 38 |
| `KeyReadAhead.scale-5keys` | pass | 346,052 / 214,960 | 47 |
| `KeyReadAhead.mutant-slot-key-latest` | `KeyPairing` violated (killed) | 21,871 / 15,413 | 6 |
| `KeyReadAhead.mutant-leak-queue` | `NoKeyLeak` violated (killed) | 17,430 / 11,776 | 5 |
| `KeyReadAhead.mutant-error-early` | `ErrorInOrder` violated (killed) | 12,649 / 9,983 | 4 |
| `KeyReadAhead.mutant-count-at-eval` | `CountsConsumed` violated (killed) | 6,157 / 6,153 | 3 |
| `KeyReadAhead.mutant-end-at-eval` | `EndAfterDrain` violated (killed) | 2,314 / 2,312 | 2 |
| `KeyReadAhead.mutant-late-window` | `WorkerLead` violated (killed) | 45,875 / 29,594 | 13 |
| `KeyReadAhead.mutant-no-stop-mark` | `EvalOnce` violated (killed) | 17,635 / 11,968 | 5 |
| `KeyReadAhead.mutant-skip-count-lost` | `CountsConsumed` violated (killed) | 38,744 / 25,456 | 11 |
| `KeyReadAhead.mutant-queue-rejected` | `NoRejectedEntry` violated (killed) | 13,595 / 10,266 | 4 |
| `KeyReadAhead.mutant-covering-window` | `NoWindowWithoutLookup` violated (killed) | 12,362 / 9,898 | 4 |
| `KeyReadAhead.witness-{queued,skipped-stop,error-twice,covered-done}` | reached | 17,612 / 13,631 / 32,544 / 26,253 | 5 / 4 / 9 / 7 |
| `KeyReadAhead.apalache-indinv` | IndInv inductive | — | 1 step |
| `ReadAheadTrace.witness-trace-ser1` / `-ser2` | accepted | 4,013 / 2,806 | 4,013 / 2,806 |
| `ReadAheadTrace.reject-{swap-look,drop-check,flip-fired,foreign-hint}` | refused | 13 / 258 / 4 / 2 | — |
| `KeyReadAheadTrace.witness-trace-n1` … `n5` | accepted | 1,196 / 202 / 886 / 4,582 / 144 | 1,194 / 200 / 886 / 4,580 / 143 |
| `KeyReadAheadTrace.reject-{pos-off,drop-eval,skip-off}` | refused | 174 / 173 / 198 | — |

Dead expressions: `KeyReadAhead.tla:229`, `:230`, `:232`, `:233`, `:234`, `:250` only, explained above. TLAPS 요청 없음.

Spec sha256 (as checked; `MAP.md`'s line is the file before this section):

```
57052a71728eaa7189a7cdbeb972d704717d9da8e927283a1d60225a35a75dd1  KeyReadAhead.tla
16a0f522caf44dc16a5c0de843e51273f4e437edaece72c8f58cea1bf59ef4da  KeyReadAheadTrace.tla
add4b84d70b32c23897ecba1f823c7008033c2a0fce2910ce2bce9a533da036c  KeyReadAheadTraceData.tla
e6c44f6d389bc83be161b5abb667330f0dff16cd179419cf9750f925ce3283f7  ReadAhead.tla
d14cba928f786ed053ecd0954c25e1647cb00fe542e0d215e31c15917f70dd2c  ReadAheadTrace.tla
572222be557b9c8273aebcf37739a4b1669880ff21f2744a9c20095569bc660e  ReadAheadTraceData.tla
d3ea67294dd77fdb4e627385dd5a05535d9a01b9f7a742da00c705aa281421f6  MAP.md
```
