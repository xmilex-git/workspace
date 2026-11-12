# CBRD-28031 — read-ahead hint for the heap lookups of an index scan: `ReadAhead` (the serial index scan's read-ahead window) and `KeyReadAhead` (the parallel index scan worker's look-ahead)

Engine: branch `CBRD-28031` `35a151f37` (develop `4255a337d` + 7; the model of D1..D9 was first checked on `fb576da0b`), worktree `~/dev/cubrid-worktree/CBRD-28031`; fork `xmilex-git/cubrid` branch `CBRD-28031`.
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
| D12 | The keys a worker evaluates ahead keep their OIDs where the lookups read them, in the scan's own OID buffer: every key's OIDs, read by the lookups or evaluated ahead, are appended to `isid.oid_list` (the serial scan's buffer, `index_scan_oid_buffer_size`, default 4 pages, `MAX (2 pages, the parameter)`; a covering worker gets one too); each queued key is only an end offset with its next slot and `read_keys`; the lookup position and the window's frontier are `curr_oidno` and `ahead_next`, and the window is computed by the serial scan's own function, `scan_index_read_ahead (thread_p, isidp, more)` (`more`: the leaf has keys left, so the window's end at the buffer's end is not the scan's end). The look-ahead appends while the buffer has room (`oid_cnt - curr_oidno < max_oid_cnt`): the window is cut where the buffer ends (C15). No per-key OID vector, no queue of key values (only the last queued key, the one with an overflow chain, keeps its value to publish the chain). The counters stay at the lookups (D7). Hot instructions against develop `4255a337d` (release, 400,000 rows, 3 runs, medians): `s like '1%'` -0.15%, `mod(k,10)` -0.22%, `mod(k,100)` +0.05%, no key filter -0.52%, covering -11.41% / -1.13%, join inner unique lookups +0.05%, join inner 4 OIDs a key +1.07%, parallel unique range +0.35% (+13.86% with the earlier queue of keys). | settled 2026-11-12 (the user: "oid버퍼가있는데 왜 또 배열,큐가 있어야하는지 물었다", "진행해라"; then "oid buffer size는 파라미터를 따라가지? 그리고 직렬과 엄청나게 다른방식이 아니라 공통함수 사용하지?", "응 다 멈추고 공통함수쓰게바꿔", "직렬의 oidbuffer와 그 offset을 받게해야하는거아냐?"; supersedes the leaf's own OID vector of `753e66b67`) | `Cap`, `CapWin`, `Lead`; C15 `BufferBound`; refinement of `EvalAhead`, `Fresh`, `WindowDone` |
| D13 | A scan that stops after a few rows does not pay for a full window: the read-ahead window starts small (`W0` OIDs) and doubles with every window up to 256 OIDs; the next window is told when half of the current one was looked up. C3 is lowered to that lead (half of the current window, not 128 from the buffer's first OID) and C16 bounds what a stopped scan told the OS. Found by review (PR #8490, hgryoo, comment 6814287803) and reproduced on `da50708b5` (release, SA mode, `rv_o` 400,000 rows, 400 rows a `cid` on different pages, `status` not in the index; `posix_fadvise` calls counted with `strace -c`, develop 0 in every case): NL semi join whose inner scan has a data filter (no key limit 1), 1,000 outer rows: 249,191 calls, the pages read by the scan unchanged (5,328 `read`); `... where cid = 5 and status = 'OPEN' limit 1`: 256 calls for one row; the same semi join without the data filter (key limit 1, one OID a buffer): 0. PostgreSQL does the same (`REL_17_0` `nodeBitmapHeapscan.c` `BitmapAdjustPrefetchTarget`: the target starts at -1 at every rescan, then 0, 1 and doubles to the maximum). Not taken alone: leaving out the scans of a semi/anti join's inner (`QPROC_SINGLE_INNER`) — the LIMIT case keeps its 256 calls. | settled 2026-11-12 (Q1, Q2: "응 전부 추천대로 ㄱㄱ"; `W0` = 8: Q3 "ㅇㅇ") | `W0`, `dist`; C3, C16 |
| D14 | Every OID buffer of a serial scan starts again at the first window; the distance a buffer reached is not kept for the next one. Measured (perf-node0 run `20261112-134122-248`, cold, TPC-H SF10, develop `4255a337d` and the measurement build of `da50708b5` with the first window and the two options switched by environment variables, libcubrid `edba0ba27cd3…`; seconds): first window 8 kept vs not kept: semi join with a data filter 5.5..5.7 vs 5.6, anti join (30 rows a key, read to the end) 5.08 vs 6.63, Q20 50.3 vs 49.4, Q9 52.4 vs 54.7. Keeping it lets the buffer after one read to its end tell 256 OIDs at its first lookup again, which C16 forbids (`ReadAhead.mutant-carry-distance`). | settled 2026-11-12 (Q4: "ㅇㅇ이어가지마") | `Carry = "reset"`; mutant `carry-distance` |
| D15 | The inner scan of a NL semi/anti join (`QPROC_SINGLE_INNER`) keeps its read-ahead: with the first window of 8 OIDs a semi join that stops at the first match costs what develop costs (cold, same run: develop 4.9..5.5 s, fixed 256 window 11.4 s, first window 8: 5.6 s; left out as well: 5.1..5.3 s), and leaving the scan out takes the gain away where the inner scan reads every row of the key (anti join with no match: develop 33.6 s, first window 8: 6.63 s, left out: 31.7 s). | settled 2026-11-12 (Q5: "ㅇㅇㅇ 리뷰답에도달ㅇ아") | not modeled (the scan is a `ReadAhead` scan like any other) |
| D16 | A parallel index scan worker keeps its distance from leaf to leaf and from key to key; it starts at the first window when the worker's scan is opened (a reset opens it again). A window cut short (the leaf's end, the OID buffer's bound) does not make the next one larger. A worker's scan stops once (LIMIT, interrupt), so C16 counts the lookups of the whole worker scan. | settled 2026-11-12 (Q6: "ㅇㅇ") | `KeyReadAhead`: `dist`, `look0`; C16 `StopWaste` |
| D17 | The inner scan of a NL semi/anti join (`QPROC_SINGLE_INNER`) looks its first OID up without a window and starts its windows at the second lookup, with 2 OIDs (then 4, 8, ... 256): C16's bound for it is 3k + 1. With the first window of 8 the scan that stops at its first match told the OS about 7 pages it never read, for every outer row and again at every execution, because those pages never enter the buffer: the semi join of D15 run again right after its cold run took 0.36..0.37 s against develop's 0.17..0.18 s (fixed 256 window 0.93 s; first window 1: 0.18 s; perf-node0 run `20261112-134122-248`). Measured on `35a151f37` (release, libcubrid `5df76ab07268…`, perf-node0 run `20261112-155325-248`, cold / run again, seconds): semi join with a data filter 5.88 / 0.18 (develop 4.90..5.50 / 0.17..0.18), anti join reading 30 rows a key 9.47 (develop 33.5, first window 8: 6.63..6.76), Q20 49.5 (develop 118.2, 119.2), Q9 54.9 (develop 82.3), lineitem range 1.64 (develop 7.27). `posix_fadvise` calls of the development host's cases (develop 0): semi join matching at the first row 16 (fixed window 25,413; first window 8: 613), matching at the 7th row on average 2,307 (249,191; 6,339), `limit 1` with a data filter 20 (256). Replaces D15's "like any other scan" for the first window only. | settled 2026-11-12 (Q7: "그렇게 하자.") | `Single`, `First`; mutant `single-as-other`; trace ser3 |
| D9 | The read-ahead distance is 256 OIDs (`SCAN_INDEX_READ_AHEAD_DISTANCE`, serial scan and worker alike), checked half a window (128 OIDs) ahead. Measured cold (TPC-H SF10, release, interleaved; perf-node0 HDD RAID, run 20261111-160118-248, two rounds; this host's NVMe one round): Q20 none 130.3/130.0 s, 32: 53.3/54.7, 64: 52.7/54.6, 256: 49.2/49.5, 512: 48.4/48.7 (perf-node0); Q9 none 101.2/87.5, 32..512: 54..63; on NVMe 32..512 within noise. | settled 2026-11-11 (the user: "그럼 256으로 해야겟네") | `D` (the models check D = 4 and 6; the bound is not a claim) |

## Claim and sources

| # | Claim | Kind | Source |
|---|---|---|---|
| C1 | The lookups take the OIDs of every OID buffer once, in buffer order (all of them unless the scan stops: `StopEarly`): the hint changes neither the rows nor their order. | equivalence | JIRA body, Specification Changes ("질의 결과와 행 순서도 지금과 같습니다") |
| C2 | A window lies inside the OID buffer, starts at or after the OID being looked up and holds at most 256 OIDs (`vpids[SCAN_INDEX_READ_AHEAD_DISTANCE]`; `SCAN_INDEX_READ_AHEAD_NEXT` never exceeds it). | safety | `scan_manager.c` `scan_index_read_ahead` (array bound) |
| C3 | (serial; for a worker: `WorkerLead`, the same over its OIDs in lookup order up to the leaf's end or an erroring key, and up to `max_oid_cnt - 1` ahead when its OID buffer holds fewer than 129 OIDs, C15) Every OID from the one being looked up to half of the current window ahead (the window: 8 OIDs at first, twice the one before at every whole window, up to 256, so 128 ahead once it is 256; D13) has been in a window whose pages were checked against the buffer before its lookup (the pages the check found absent handed to the OS; the check may be wrong when another thread loads or evicts the page meanwhile) or is on the page being looked up. | safety | JIRA body (re-drafted 2026-11-11), Implementation ("조회할 OID부터 256개 ... 절반(128개)을 조회했을 때 다음 창을 알립니다"); design.md "직렬 인덱스 스캔" |
| C7 | A worker's lookup reads the key value of the OID's own key, never a key evaluated ahead (`m_slot_key`: covering reads, GROUP BY skip). | safety | D8 (Q8) |
| C8 | When a worker stops or ends (end of leaf, LIMIT, interrupt, error, reset), every key value the look-ahead copied is cleared, once. | safety | D8 (Q8); `pr_clear_value` ownership of `COPY` keys |
| C9 | A key filter error is raised only when the lookups reach its key, as without the look-ahead. | equivalence | D7 (Q7) |
| C10 | The trace counters count the keys whose OIDs were looked up (`qualified_keys`), and every key read once (`read_keys`), as without the look-ahead. | equivalence | D7 (Q7); `read_keys` once: PR #8490 review (Greptile), D10 |
| C11 | The leaf's range end (`signal_chain_ended`) is signaled only after the last queued key was drained. | safety | D8 (Q8) |
| C12 | A worker evaluates every key of its leaf (read, key range, key filter) once, as without the look-ahead; only the key the look-ahead stopped at (an error; the key past the range's end takes the same path) is evaluated once more, by the lookups. | safety (cost) | PR #8490 review (Greptile P2), D10 |
| C13 | A key the key range or the key filter rejects takes no queue entry: its copied value is cleared when it is read. | safety | D10 |
| C14 | A worker whose scan has no heap lookup (covering index) never evaluates a key ahead and never checks a window. | safety | D11 |
| C15 | The OIDs a worker evaluates ahead of its lookups fit the scan's OID buffer (`index_scan_oid_buffer_size`): the look-ahead stops when the buffer is full from the OID being looked up, the key that crosses the bound included (its OIDs fit: the buffer holds at least two pages, a leaf record's OIDs). | safety | D12 |
| C16 | A scan that stops after looking up k OIDs of an OID buffer has told the OS about at most 3k + 8 OIDs of it (`W0`; 3k + 1 for the inner scan of a NL semi/anti join, D17; a worker: over the lookups of its whole scan, D16). The fixed window told 256 for k = 1. | safety (cost) | PR #8490 review (hgryoo), D13 (Q1, Q3), D17 (Q7) |


## Refinement map — `ReadAhead` (serial index scan)

| Model | Code (`CBRD-28031`) | One step because |
|---|---|---|
| `Fill` | `scan_manager.c:call_get_next_index_oidset` tail: `ahead_next` set and `ahead_distance = 0` (`Carry = "reset"`, D14) after `scan_get_index_oidset` fills `oid_list`; a `QPROC_SINGLE_INNER` scan (`Single`) gets `ahead_next = 1`, `ahead_distance = 1` (D17: its first OID is looked up at once) | single owner: the scan's `INDX_SCAN_ID` is private to its thread; no shared state is read |
| `Check` | `scan_manager.c:scan_next_index_scan` (`curr_oidno + ahead_distance / 2 >= ahead_next`) then `scan_index_read_ahead`: `distance = SCAN_INDEX_READ_AHEAD_NEXT (ahead_distance)` (`NextDist`: 8, then twice the last whole window, up to 256), window `[MAX (ahead_next, curr_oidno), MIN (oids_count, curr_oidno + distance))`, `ahead_distance = distance` when the window was not cut by the buffer's end (`dist`), `ahead_next` moved to the window's end (`INT_MAX` when it reaches the buffer's end and `more` is false: the serial scan passes false, its next buffer starts a new sequence at `Fill`), `pgbuf_read_ahead` unless the window is the one page being looked up | the window is private; the only shared read is the residency check of each page, whose outcome the model draws freely (`resident` is any set under `Env`, and with `Probe = "racy"` any answer): a per-page split would reach no other combination |
| `Look` | `scan_next_index_lookup_heap` -> `heap_get_visible_version` -> `pgbuf_fix` of the OID's page; then `curr_oidno++` (non-grouped branch) or a refill | the fix loads the page (`resident`); the cursor is private |
| `StopEarly` | the scan is not asked for its buffer's next OID: `scan_handle_single_scan` (`single_fetched`: the first match of a semi/anti join's inner scan), LIMIT in `qexec_intprt_fnc`, an error or interrupt from the lookup; the next `call_get_next_index_oidset` (a rescan for the next outer row, `scan_start_scan`) is the next `Fill` | private: no shared state |
| `Env` | other threads' `pgbuf_fix` (claim and read of a BCB) and victimization (`pgbuf_victimize_bcb`) | changes `resident` at any point between steps |
| `racyHinted` (Probe = "racy") | `page_buffer.c:pgbuf_read_ahead`: chain walk with relaxed loads, no `hash_mutex`, at most `PGBUF_READ_AHEAD_MAX_CHAIN_STEPS` BCBs | the answer may be wrong either way (D5) |
| `posix_fadvise` | `file_io.c:fileio_read_ahead_hint` | no state the scan reads afterwards: not a model variable beyond `served` |

Exit paths of the serial scan (P11): end of the OID buffer -> `Fill`; end of scan (`S_END` from `call_get_next_index_oidset`) -> `phase = "end"`; `scan_reset_scan_block`, `scan_start_scan` (`curr_oidno = -1`, position `S_BEFORE`) -> the next `Fill`, which resets `ahead_next`; grouped scans (`scan_id->grouped`), multi-range optimization, count-only and covering scans never set `ahead_next` (stays `INT_MAX`), so `Check` never fires; a scan that stops before its buffer's end (the first match of a semi/anti join's inner scan, LIMIT, an error or interrupt from the lookup) -> `StopEarly`, then the next rescan's `Fill` or the end; `ReadAheadTrace` takes `StopEarly` as its one hidden step (the next event is the next buffer's `Fill`).

Guard whose removal violates nothing: `MAX (ahead_next, curr_oidno)` (mutant `start_at_next` not kept): `ahead_next` never falls below `curr_oidno` because `curr_oidno` moves by one per lookup (`scan_manager.c` non-grouped branch `curr_oidno++`) and every `Check` that fires moves `ahead_next` past `curr_oidno + 128` (or to `INT_MAX`); the guard is defensive.

Dead expressions: the `Mutant = "late_trigger"`, `"no_count_bound"` and `"cursor"` arms of `Check` (mutant-only). `ReadAhead.tla:73` — `NextDist`'s `"fixed"` and `"no_distance_cap"` arms (mutant-only). `ReadAhead.tla:119`, `ReadAhead.tla:120`, `ReadAhead.tla:121`, `ReadAhead.tla:122` — `Fill`'s `Single` arm (the inner scan of a NL semi/anti join, `QPROC_SINGLE_INNER`: `ahead_next = 1`, `ahead_distance = 1`); dead in every cfg with `Single = FALSE`, evaluated in `ReadAhead.single` (`Single = TRUE`); removing the arm is the mutant `ReadAhead.mutant-single-as-other`.

## Refinement map — `KeyReadAhead` (parallel index scan worker, D6/D7/D10/D11/D12)

| Model | Code (`CBRD-28031` `35a151f37`) | One step because |
|---|---|---|
| `rej`, `FirstKept` | `px_scan_index_leaf_slot_walker.cpp:leaf_slot_walker::next_key`: the loop over the slots of `m_page` from `*slot`; a key outside the range (not past it), a NULL first index term, or a key filter `V_FALSE`/`V_UNKNOWN` is cleared (`pr_clear_value`) and the loop goes on (`continue`); fence and unreadable slots are not keys (not counted in `read_keys`) | the leaf is held (S latch) and the walker's state is private |
| `EvalAhead`, a key qualifies | `leaf_slot_walker::evaluate_ahead` -> `next_key (ahead = true)`: the rejected keys, then the qualifying key; its visible OIDs (`btree_record_process_objects` with the snapshot, `leaf_collect_helper`) are appended to the scan's OID buffer (`isid.oid_list`, `oid_cnt`) and `{end offset, next slot, read_keys}` is pushed on `m_ahead`; its value is cleared, or kept in `m_ahead_last` when it has an overflow chain (the walk goes no further); `m_ahead_slot` after it | private; the key is copied (`COPY`) and freed, as before the look-ahead |
| `EvalAhead`, stop (`n = NK + 1` or `n = errKey`; `aend`, `errAhead`) | `next_key` returns `LEAF_END`, or `END`/`ERROR` through its `stop` lambda (ahead: `*slot`, `*read_keys`, `m_current_range_idx` back to the stop key; `stop_at_error (ahead = true)` clears the error, no `signal_chain_ended`; OIDs appended by a failing key are cut off: `oid_cnt` back to its value before the key); `evaluate_ahead` sets `m_ahead_slot`, `m_ahead_skipped_keys`, `m_ahead_end` | private; the signal is the only shared write and happens at consumption (C11) |
| `WindowDone` (`Win` = min (`ND`, `Cap`) OIDs, or `aend`) | `read_ahead`: `curr_oidno` = the OID being looked up (`buffer_next () - 1`); returns when `curr_oidno + ahead_distance / 2 < ahead_next`; else evaluates keys ahead while `oid_cnt < curr_oidno + SCAN_INDEX_READ_AHEAD_NEXT (ahead_distance)` (`ND`) and `oid_cnt - curr_oidno < max_oid_cnt` (only after a key with no overflow chain), sets `oids_count = oid_cnt` and calls `scan_index_read_ahead (thread_p, isidp, more)`, the serial scan's function: window `[MAX (ahead_next, curr_oidno), MIN (oids_count, curr_oidno + distance))`, `ahead_next` to its end, `ahead_distance = distance` when the window is whole (`dist`), `pgbuf_read_ahead` of its pages | private; the residency check is `ReadAhead`'s |
| `Check` | `process_oid`: covering path (`cov`) returns before `read_ahead`; `read_ahead` returns at once when `curr_oidno + ahead_distance / 2 < ahead_next`, else fires; after the stop (`aend`) the last window ended at the buffer's end with `more` false, so `ahead_next` is `INT_MAX` until the lookups resume past the stop (`ahead_next = 0`) | private |
| `Look` | `process_oid`: covering path (key values from `m_slot_key`), non-covering `heap_get_visible_version` | as `ReadAhead.Look` |
| `Fresh`, `n <= ev` | `scan_next_slot`: `m_ahead[m_ahead_head++]`; the drain takes `oid_list->oidp[buffer_end (), end)` (`begin_leaf_drain`), `m_current_slot = next_slot`, the key's counters (`read_keys`, `qualified_keys`, `key_qualified_rows`, `read_rows` = end - begin), `m_slot_key` (null, or `m_ahead_last` for the last key), `begin_key_record`; the queue's array is emptied (capacity kept) once drained | private |
| `Fresh`, `n > ev` | `scan_next_slot`, queue empty: when `m_ahead_end`, `m_current_slot = m_ahead_slot` and `read_keys += m_ahead_skipped_keys` (the keys `ck..ev` the look-ahead passed); the buffer is emptied (`oid_cnt = 0`) and `next_key (ahead = false)` appends the next qualifying key's OIDs (`ahead_next = 0`: a new sequence), or raises the error (`stop_at_error`, `signal_chain_ended`), the range's end (`signal_chain_ended`, `S_END`) or the leaf's end (`S_END`) | private |
| `NextKey` | `scan_next_slot`'s loop after `drain_next_oid` returned `S_END` for the key | private |
| `dist`, `look0` | `isid.ahead_distance` of the worker's scan: 0 at `scan_open_index_scan` (the worker's task opens its scan once; a reset opens it again), kept by `set_page`, `clear_ahead` and the key-to-key restarts (`ahead_next = 0`), D16; `look0`: the lookups of the leaves before this one (not a code variable) | private |
| `Cap` | `isid.oid_list->max_oid_cnt` (`ISCAN_OID_BUFFER_COUNT`, from `index_scan_oid_buffer_size`): `scan_index_alloc_oid_buffer` at the worker's `scan_open_index_scan` (`px_scan_task.cpp`); the collect helpers check the capacity (`assert_release` and `ER_GENERIC_ERROR`, unreachable while C15 holds) | constant per scan |
| `Stop` | `clear_ahead` (empties `m_ahead`, clears `m_ahead_last`'s value, `m_ahead_end`) and `overflow_drain_fsm::cleanup_on_reset` (`oid_cnt = 0`): `slot_iterator_index::finalize` and `set_page` (reset, LIMIT, next leaf; `set_page` asserts the queue is empty), `overflow_drain_fsm::set_overflow_page` (helper session) | private |
| (not modeled: overflow pages) | `overflow_drain_fsm::process_one_overflow_page` replaces the buffer's contents with the page's OIDs (`oid_cnt = 0`, then `ovf_collect_helper` appends) (it asserts no key is queued: none is evaluated past a key with an overflow chain) and calls `restart_read_ahead`: each overflow page's OIDs are a sequence of their own (a `ReadAhead` buffer) | |

The model's keys are the keys `next_key` reads; a rejected key has no OID (`KeysWf`), and the range's end is the leaf's end of the model (`n = NK + 1`): the key past it is read twice like an erroring key, by the same `stop` lambda, but is not a model key. `ev` (the last key evaluated) never moves back (cubrid-tla P81): in the code it is `m_ahead_slot`, kept on every return of `evaluate_ahead`.

Shared state the look-ahead could touch, and why it does not change a lookup's inputs: `isidp->key_attrs` (the key filter's attribute cache) is overwritten by a key evaluated ahead while the current key's rows are looked up; the non-covering lookup reads `pred_attrs` and `rest_attrs` from the heap record, not `key_attrs`, as in the serial scan, whose OID buffer is filled (key filter evaluated) before any of its lookups. Covering scans do not look ahead (`read_ahead` is called on the non-covering path only).

## Fault model

| Fault | Where it can fire | In the models |
|---|---|---|
| error return | `pgbuf_read_ahead` and `fileio_read_ahead_hint` return nothing (a failed `posix_fadvise` is ignored); the worker's key evaluation ahead (`btree_read_record`, `check_key_in_range`, key filter `V_ERROR`, `btree_record_process_objects`) | serial: not applicable (the hint has no error path); worker: `errKey` with `ErrAt` (D7: cleared ahead, raised when the lookups reach the key) |
| interrupt / query cancel, LIMIT | the worker is reset (`cleanup_on_reset`) between any two steps | `Stop` from every live phase (C8) |
| lock timeout, deadlock victim | no lock is requested by the hint or the look-ahead | not applicable |
| conditional latch failure | none: the hint fixes no page; the look-ahead reads the leaf the worker already holds | not applicable |
| OOM | `scan_index_alloc_oid_buffer` (the OID buffer, once per worker scan, from the pool `scan_Iscan_oid_buf_list`); `std::vector::push_back` of `m_ahead` (end offsets, capacity kept across leaves) | not modeled: the buffer's failure fails the worker's scan open with an error, as the serial scan's; `m_ahead`'s `std::bad_alloc` is the class of the walker's other containers |
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
| `ReadAhead.mutant-no-distance-cap` | `SCAN_INDEX_READ_AHEAD_NEXT`'s `MIN (distance * 2, SCAN_INDEX_READ_AHEAD_DISTANCE)`: the window keeps doubling (`D = 2`, where the bound is reached inside a 6-OID buffer; with `D = 4` or `6` the buffer's end cuts the window first, so `ReadAhead.cap-d2` is the passing cfg in which the bound limits a window) | C2 `WindowBound` |
| `ReadAhead.mutant-late-trigger` | the half-window lead (`curr + ahead_distance / 2 >= ahead_next` -> `curr >= ahead_next`) | C3 `Lead` |
| `ReadAhead.mutant-fixed-window` | D13: every window holds 256 OIDs from the buffer's first lookup (the code of `da50708b5`) | C16 `StopWaste` |
| `ReadAhead.mutant-single-as-other` | D17: the inner scan of a semi/anti join starts with a window at its first lookup like any other scan (the code of `cdc38c0db`; `W0` = 2) | C16 `StopWaste` |
| `ReadAhead.mutant-carry-distance` | D14 not taken: an OID buffer starts from the distance the buffer before it reached | C16 `StopWaste` |
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
| `KeyReadAhead.mutant-fixed-window` | D13: a worker's every window holds 256 OIDs | C16 `StopWaste` |
| `KeyReadAhead.mutant-no-cap` | D12: the look-ahead's `oid_cnt - curr_oidno < max_oid_cnt` bound (`Cap = 2`) | C15 `BufferBound` |
| `ReadAhead.witness-hinted` | a page is hinted | reachable |
| `ReadAhead.witness-over-2k` | the windows run more than 2k + `W0` OIDs ahead of k lookups (C16's bound is 3k + `W0`: the next window is told when half of the current one is left) | reachable |
| `KeyReadAhead.witness-queued` | a key evaluated ahead while an earlier key is looked up | reachable |
| `KeyReadAhead.witness-skipped-stop` | the look-ahead passed a rejected key and stopped at the leaf's end before the lookups reached it | reachable |
| `KeyReadAhead.witness-error-twice` | the key the look-ahead stopped at on an error is raised by the lookups | reachable |
| `KeyReadAhead.witness-covered-done` | a covering scan drains a leaf with OIDs | reachable |
| `ReadAhead.option-locked` | (D5 not taken) the residency check under the bucket mutex | passes too: the claims do not depend on the check's answer |

Dead expressions: `KeyReadAhead.tla:254`, `KeyReadAhead.tla:255`, `KeyReadAhead.tla:257`, `KeyReadAhead.tla:258`, `KeyReadAhead.tla:259` — `EvalAhead`'s `ErrAt = "early"` branch (mutant-only: `mutant-error-early`); `KeyReadAhead.tla:275` — the `no_stop_mark` arm of the stop (mutant-only: `mutant-no-stop-mark`); `ReadAhead.tla` none in the main cfg.

## Trace validation

Serial (`ReadAhead`): the instrumented build below (the serial call site of `scan_index_read_ahead` logs too); events `Fill` (the buffer's pages), `Check` (fired, start, stop, skipped, the pages hinted, from a thread-local list in `pgbuf_read_ahead`), `Look`.

Worker (`KeyReadAhead`): instrumented build of 2026-11-12, scratch worktree `CBRD-28031-instr` = the tree of `35a151f37` plus `TLATRACE` lines only (`next_key`'s result kept in a variable to log it), optdebug install `~/optdebug/CUBRID-CBRD-28031-instr`, libcubrid sha256 `bec36f124b31a836…`; recorded with `index_scan_oid_buffer_size=1K` (`max_oid_cnt` 143, logged in `WLeaf` as `cap`: the trace's `Cap`; `WLeaf` also logs `ahead_distance`, the trace's `Dist0`: 128 for n1, 64 for n2, 0 for n3, n4, n5). Events: `WLeaf` (cov), `WKey` (every `next_key` call: ahead or not, result `Q`/`LEAF`/`END`/`ERR`, the keys it read, the OIDs), `WPop` (the key's `read_keys`), `WResume` (`m_ahead_skipped_keys`), `WWin` (the window's end relative to the OID being looked up), `WEnded` (`read_ahead` returning at once after the stop), `WNoWin`, `WLook` (covering and non-covering), `WNext`, `WClear`, `WOvf`. `traces/convert.py worker <log> <Name> <k> <need>` cuts one walker's segment on one leaf (from `WLeaf` to its next `WClear`, no overflow page), the k-th smallest that has `<need>` (`pop`, `resume`: a resume past rejected keys, `err`: an error found ahead and raised by the lookups, `cov`), and rebuilds the leaf's keys from the `WKey` lines (rejected keys, OID counts, the erroring key). Logs `traces/raw/n*.log.xz` (`xz -dk` first).

| Trace | Query (DB `ra28031`, 400,000 rows; `index_scan_oid_buffer_size` 1K, `parallel(4)`) | Segment | Cfg | Expect |
|---|---|---|---|---|
| ser1 | `k between 100 and 600` on `i_ra_k` (serial, buffer 4K) | — | `ReadAheadTrace.witness-trace-ser1` | accepted (`TraceNotDone` violated) |
| ser2 | `id between 100 and 1500 and v >= 0` on `ra_n` (serial) | — | `ReadAheadTrace.witness-trace-ser2` | accepted |
| n1 | `u between 1000 and 60000` on the unique `i_ra_u` | 170 keys, 683 events | `KeyReadAheadTrace.witness-trace-n1` | accepted |
| n2 | `k between 100 and 20000 and s like '1%'` on `i_ra_ks` (key filter) | 271 keys, 243 rejected, 115 events | `KeyReadAheadTrace.witness-trace-n2` | accepted |
| n3 | `k between 0 and 100003 and cast(s as int) >= 0` on `i_ra_ks` (key filter error) | 127 keys, the last erroring, 507 events | `KeyReadAheadTrace.witness-trace-n3` | accepted |
| n4 | `k between 100 and 20000` on `i_ra_k` | 286 keys of 4 OIDs, 2,863 events | `KeyReadAheadTrace.witness-trace-n4` | accepted |
| n5 | `count(*), sum(k)` with `s like '1%'` on `i_ra_ks` (covering) | 271 keys, 243 rejected, 58 events | `KeyReadAheadTrace.witness-trace-n5` | accepted |
| ser3 | `... from rv_c c where c.id < 6 and exists (select 1 from rv_o o where o.cid = c.id and o.status = 'OPEN')` (serial, the inner scan of a NL semi join: 6 buffers of 400 OIDs, each left at its first match) | 60 events | `ReadAheadTrace.witness-trace-ser3` (`Single = TRUE`) | accepted |
| ser1, corrupted | two lookups swapped / one fired check dropped / a check's `fired` flipped / a page never in the window hinted | — | `ReadAheadTrace.reject-{swap-look,drop-check,flip-fired,foreign-hint}` | rejected (`TraceNotDone` holds) |
| n1, n2 corrupted | a window's position off by one (n1) / one key evaluated ahead dropped (n1) / the resume's skipped keys one short (n2) | — | `KeyReadAheadTrace.reject-{pos-off,drop-eval,skip-off}` | rejected |

`Check` and `NextKey` are hidden steps of `KeyReadAheadTrace`; `WResume`, `WEnded`, `WNoWin`, `WNext` are markers that check the state they find (`WResume`: the keys `ck..ev` the look-ahead passed equal `m_ahead_skipped_keys`). In the whole n2 log (all workers, all leaves), 8,837 lookups saw 141 windows, 224 returns before the next window (`WNoWin`) and 8,472 returns after the stop (`WEnded`), and the keys the `WKey` lines read add up to the counted `read_keys` (79,605 = 2,649 read by the lookups' `WKey` + 76,956 read ahead, counted by `WPop` 74,271 + `WResume` 2,685): no key was evaluated twice except the one key past the range's end the look-ahead stopped at (its ahead read is rewound out of `read_keys`). Before `67a924189` the same query re-evaluated the passed keys once per lookup (8,837 `WEvalStop`).

## Result

2026-11-12, engine `35a151f37` (develop `4255a337d` + 7): all 52 cfgs PASS, 0 FAIL — in one whole-directory run that was
stopped by hand plus `--only` reruns of the serial model. No single run printed `RESULT: OK`; each rerun printed
`RESULT: PARTIAL (...; 0 failed)`.

- Whole-directory run `.git_ignored_dir/scratch/tla/CBRD-28031-20261112-155856-2490832` (log
  `.git_ignored_dir/scratch/cbrd28031/tla-record4.log`), stopped after 37 cfgs: the 27 TLC cfgs of `KeyReadAhead` and
  `KeyReadAheadTrace` PASS there and were not run again (their `.tla`, data module and cfgs are unchanged since 15:30,
  before the run). It reported `ReadAhead`, `ReadAhead.option-locked` and `ReadAhead.scale-d6` as FAIL with `got=[pass]`:
  the dead expressions `ReadAhead.tla:119`..`122` had no line in this file.
- After that line and `NextDist`'s `no_distance_cap` arm (`ReadAhead.tla:73`, cfgs `ReadAhead.cap-d2` and
  `ReadAhead.mutant-no-distance-cap`) were added, every `ReadAhead` and `ReadAheadTrace` cfg and both Apalache cfgs ran by
  `--only`: run dirs `CBRD-28031-20261112-190630-2938275` (`ReadAhead`), `-192421-2944996` (`ReadAhead.*`),
  `-190631-2938694` (ser1), `-194434-2950549` (ser2), `-210716-2972618` (`KeyReadAhead.apalache-indinv`),
  `-210733-2973126` (reject traces), `-210810-2974030` (ser3); logs `.git_ignored_dir/scratch/cbrd28031/tla-part7a.log`,
  `tla-part7b.log`. The `.tla` and `.cfg` sha256 in each of those runs' `summary.txt` equal the files as they are now.

Engine gate of `35a151f37`: optdebug `c0447b8c30833f29…` / release `5df76ab072686028…`; smoke equal to develop (0
differing lines) on optdebug, release and the memory check. Local CTP sql was not completed on this head: one run ended
on a core of CBRD-28058 (checkpoint, a develop defect), one on the hang watchdog in `_36_guava/cbrd_27802` Case 12 while
the host's load average was 119–188, the third was stopped at the user's request. Upstream CI `gha-ci` run 43171338682 on
`35a151f37`: sql, medium and shell 0 failed; sql_by_cci 36 failed, the same list as run 43039550926 (the list five other
PRs showed on 2026-11-12). YCSB on perf-node0 (run `20261112-193954-248`, the team's four workloads, 5,000,000 records,
64 threads, 300 s, once each; develop `4255a337d` / this head, ops/s): workloada 26,734 / 26,542, workloadb 29,281 /
29,786, update 25,997 / 25,865, mix 17,276 / 17,957.

| cfg | Result | States / distinct | Depth |
|---|---|---|---|
| `ReadAhead` (`W0 = 1`, `D = 4`, no mutex, no backoff) | pass | 131,685,264 / 31,609,296 | 29 |
| `ReadAhead.cap-d2` (`D = 2`: the distance bound limits a window) | pass | 127,275,664 / 30,598,736 | 29 |
| `ReadAhead.scale-d6` | pass | 131,685,264 / 31,609,296 | 29 |
| `ReadAhead.scale-w2` (`W0 = 2`, `D = 6`) | pass | 149,754,640 / 35,774,048 | 29 |
| `ReadAhead.single` (`Single = TRUE`, D17) | pass | 131,685,264 / 31,609,296 | 29 |
| `ReadAhead.option-locked` (D5 not taken) | pass | 131,685,264 / 31,609,296 | 31 |
| `ReadAhead.mutant-cursor` | `LookupOrder` violated (killed) | 2,140,152 / 626,261 | 6 |
| `ReadAhead.mutant-no-count-bound` | `WindowBound` violated (killed) | 1,343,700 / 352,308 | 5 |
| `ReadAhead.mutant-no-distance-cap` | `WindowBound` violated (killed) | 3,993,777 / 1,132,528 | 7 |
| `ReadAhead.mutant-late-trigger` | `Lead` violated (killed) | 3,426,124 / 952,173 | 7 |
| `ReadAhead.mutant-one-page-skip` | `Lead` violated (killed) | 3,426,146 / 952,176 | 7 |
| `ReadAhead.mutant-fixed-window` | `StopWaste` violated (killed) | 325,588 / 129,028 | 3 |
| `ReadAhead.mutant-carry-distance` | `StopWaste` violated (killed) | 3,302,669 / 913,975 | 7 |
| `ReadAhead.mutant-single-as-other` | `StopWaste` violated (killed) | 325,588 / 129,028 | 3 |
| `ReadAhead.witness-hinted` / `-over-2k` | reached | 1,368,000 / 359,398; 3,993,771 / 1,132,527 | 5 / 7 |
| `ReadAhead.apalache-indinv` | IndInv inductive | — | 1 step |
| `KeyReadAhead` (worker look-ahead, `W0 = 1`, `D = 4`, `Cap = 4`) | pass | 1,764,560 / 1,091,989 | 39 |
| `KeyReadAhead.cap-2` (`Cap = 2`: the OID buffer's bound limits the look-ahead) | pass | 1,744,961 / 1,079,246 | 42 |
| `KeyReadAhead.scale-5keys` | pass | 9,771,055 / 6,060,833 | 48 |
| `KeyReadAhead.mutant-slot-key-latest` | `KeyPairing` violated (killed) | 636,502 / 453,799 | 6 |
| `KeyReadAhead.mutant-leak-queue` | `NoKeyLeak` violated (killed) | 534,738 / 359,688 | 5 |
| `KeyReadAhead.mutant-error-early` | `ErrorInOrder` violated (killed) | 383,283 / 306,818 | 4 |
| `KeyReadAhead.mutant-count-at-eval` | `CountsConsumed` violated (killed) | 190,534 / 190,472 | 3 |
| `KeyReadAhead.mutant-skip-count-lost` | `CountsConsumed` violated (killed) | 985,486 / 652,981 | 9 |
| `KeyReadAhead.mutant-end-at-eval` | `EndAfterDrain` violated (killed) | 68,328 / 68,328 | 2 |
| `KeyReadAhead.mutant-late-window` | `WorkerLead` violated (killed) | 777,684 / 522,912 | 7 |
| `KeyReadAhead.mutant-no-stop-mark` | `EvalOnce` violated (killed) | 535,526 / 360,364 | 5 |
| `KeyReadAhead.mutant-queue-rejected` | `NoRejectedEntry` violated (killed) | 401,548 / 312,243 | 4 |
| `KeyReadAhead.mutant-covering-window` | `NoWindowWithoutLookup` violated (killed) | 376,114 / 304,701 | 4 |
| `KeyReadAhead.mutant-fixed-window` | `StopWaste` violated (killed) | 542,586 / 367,282 | 5 |
| `KeyReadAhead.mutant-no-cap` | `BufferBound` violated (killed) | 398,474 / 311,321 | 4 |
| `KeyReadAhead.witness-{queued,skipped-stop,error-twice,covered-done}` | reached | 360,428 / 307,160 / 652,715 / 518,195 distinct | 5 / 4 / 9 / 7 |
| `KeyReadAhead.apalache-indinv` | IndInv inductive | — | 1 step |
| `ReadAheadTrace.witness-trace-ser1` / `-ser2` / `-ser3` | accepted | 6,017 / 4,207 / 93 | 4,013 / 2,806 / 66 |
| `ReadAheadTrace.reject-{swap-look,drop-check,flip-fired,foreign-hint}` | refused | 19 / 15 / 6 / 3 | — |
| `KeyReadAheadTrace.witness-trace-n1` … `n5` | accepted | 1,196 / 202 / 886 / 4,582 / 144 | 1,194 / 200 / 886 / 4,580 / 143 |
| `KeyReadAheadTrace.reject-{pos-off,drop-eval,skip-off}` | refused | 145 / 144 / 198 | — |

`ReadAhead.scale-d6` and `ReadAhead.single` reach the state count of `ReadAhead` (`ReadAhead.option-locked` did in every
earlier record too): since D13 a
6-OID buffer ends the third window (1, 2, 4 OIDs) before a distance bound of 4 or 6 limits it, so `D = 6` scales nothing
(`ReadAhead.cap-d2` and its mutant are the cfgs in which the bound acts, `ReadAhead.scale-w2` the one that grows the
state space); `Single = TRUE` enters after `Fill` the state `W0 = 1` enters after its first window (`ahead_next = 1`,
`ahead_distance = 1`, the first OID counted as told), and differs from it under `W0 = 2`, which
`ReadAhead.mutant-single-as-other` uses.

Dead expressions reported: `ReadAhead.tla:119`, `:120`, `:121`, `:122` (pass cfgs with `Single = FALSE`; none in
`ReadAhead.single`) and `KeyReadAhead.tla:254`, `:255`, `:257`, `:258`, `:259`, `:275`, each explained above. TLAPS 요청 없음.

Spec sha256 (as checked; `MAP.md` as the last run read it, before this section was rewritten: `7449607a497293fe9d8f9279e43f0872dc5712f22701c3030c19fe4b0aa3fcd6`):

```
3ed8ad353b822cbf56bfc2930e75392534f5c55204725f9062b1b66b476e5b6a  KeyReadAhead.tla
b406097bffc47229807c5684eca9f4d41bee9c9ace715c2301942c281d380b44  KeyReadAheadTrace.tla
1d85063d335d3236fdd4c6632a6ea3c577ef18a0f4d7c35debb1b1d038028fc1  KeyReadAheadTraceData.tla
516372a98937f71b5c9437b02af53d2a2d89844620718ec6e12234375fbfb734  ReadAhead.tla
c4a06de577022460166a952354ef8e03e537fa87d09a48905b5749de33b4ed4f  ReadAheadTrace.tla
e1a5c2b70b5449dfaeb7f9a438d7ff46113df6d7432757ec14f82f87ebfd690a  ReadAheadTraceData.tla
```
