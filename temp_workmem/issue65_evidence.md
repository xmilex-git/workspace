# Issue #60 / #65 EVIDENCE — temp-workmem 개편 근거 창고 (REFINED)

> SSOT(`issue65_ssot.md`)가 "결론/방향", 이 파일은 "근거 창고". 항상 다 읽을 필요 없음.
> **정제(2026-06-29):** 측정/사실(유지) ↔ 옛 구조 결론(재해석) ↔ 오염 프레임(절단) 분리. **+ grill-with-docs 설계해소(2026-06-29): 설계 트리 닫은 코드 근거 = §H.**
> 원본 백업: `/tmp/issue65-pre-rebaseline-backup/issue65_evidence.md`.
> 모든 raw 산출물: `~/.claude/scratch/remote-codex/` (perftable_profile/, fix62_gate/, robust_parity/, reground62/ …).

---

## CUT-LOG — 이번 rebaseline 에서 잘라낸 오염 프레임 (역사 보존용 요약)

다음 서술은 "e21917cfd 구조를 유지하고 국소 패치한다"는 오염 전제의 산물이라 **잘라냈다.** (배경은 SSOT §0.)
- ❌ "정확성은 끝났고 #62 perf 회귀가 유일한 open blocker" — 목표를 구조 개편에서 perf 패치로 바꿔치기.
- ❌ "Current fix (uncommitted): dirty-flush opt = SEQUENTIAL_ONCE+DONT_FREE 락 스킵 + mark-dirty-at-alloc (방안 E)" — 증상 패치. 개편 결정으로 폐기(미커밋 5파일 수정은 SSOT §0 P2 참조).
- ❌ "Next action: robust gate 완료 → 5파일 최소 커밋 → push → #62 close" — 폐기된 다음액션.
- ❌ "방안 A(BufFile)는 장기/선택 과제" — 사실은 본 개편의 본설계(SSOT §0 P6).
아래 §A 의 해당 라운드 서술도 같은 기준으로 재해석/표시했다.

---

## Z. 실패 가설 대장 / FAILED-ATTEMPTS LEDGER  (DO NOT REPEAT — 단, 개편 기준 재해석 포함)

> **새 시도 전에 반드시 이 표를 먼저 읽는다.** append-only — 삭제 금지, status 로 supersede.
> 스키마: Assumption → Action → Result → Class → Guardrail → **재해석(개편 기준)** → Evidence → Status.
> Class: `WRONG-RESULT` / `PERF` / `CRASH` / `NON-VIABLE` / `FALSE-ALARM`(되돌린 게 잘못이었던 것).

### FAIL-01 — work_mem RAM tier 확대 (16MB tier)  [NON-VIABLE + CRASH]
- Assumption: RAM tier(work_mem)를 키우면 스필이 줄어 heavy-spill perf 가 해결된다.
- Action: `temp_file_memory_size_in_pages` cap(20p) 너머로 per-worker tier 확대.
- Result: px_scan 가 `list_id_headers` 를 parallelism 크기로 가정 → CRASH; tier 키워도 working set ≫ tier 라 어차피 스필 → 무이득.
- Guardrail: **DO NOT** heavy-spill perf 를 RAM tier 확대로 풀려 하지 마라.
- 재해석(개편 기준): 여전히 유효한 **측정 사실**. 단 "px_scan 가 list_id_headers 를 parallelism 크기로 가정"하는 것은 축2(연결구조)가 고쳐야 할 **구조적 결함**이다 — 새 연결구조는 tier 와 무관해야 한다.
- Evidence: `46d69a7bf`→`1f2d01744`(CRASH)→`4e950d6a6`(REVERT).
- Status: REVERTED (사실 유효).

### FAIL-02 — Phase B raw-fd write-buffer / pwrite coalescing  [PERF]
- Assumption: pwrite 를 coalescing(버퍼링)하면 I/O 비용이 준다.
- Action: raw-fd write 경로에 write-buffer + pwrite 병합.
- Result: pwrite 는 data-volume-bound 라 병합해도 바이트가 안 줄어 무이득 + **mutex 26→67s 회귀**.
- Guardrail(옛): raw-fd 에 write-buffer/pwrite-coalescing 재시도 금지.
- 재해석(개편 기준): ⚠️ **이 가드는 옛 구조(전역 레지스트리 위 raw-fd)에 한정.** 개편의 per-worker BufFile 은 **버퍼 단위 배치 쓰기가 본설계**다. 실패 원인은 "버퍼링" 자체가 아니라 "전역 레지스트리/락 위에 버퍼링을 얹어서 mutex 가 늘어난 것". 새 구조엔 그 락이 없으므로 이 가드를 새 구조에 적용하지 마라.
- Evidence: Phase B (reverted, 커밋 없이 폐기).
- Status: REVERTED — **구조 한정**.

### FAIL-03 — raw-fd 입력에 connect_list 머지  [WRONG-RESULT]  ★개편 핵심 동기
- Assumption: 워커 출력 머지를 `connect_list`/`use_connect` 로 하면 된다(모든 입력).
- Action: raw-fd-backed 리스트에 connect 머지 적용.
- Result: 출력 garbled.
- Guardrail(옛): 입력이 raw-fd-backed(`membuf != NULL`)일 때 connect 금지. connect 는 양 입력 `membuf==NULL` real-VPID + no-raw-fd 일 때만.
- 재해석(개편 기준): ⚠️ **이게 축2 개편의 핵심 동기다.** garbled 의 근본원인은 `qfile_connect_list` 가 **VPID 물리식별자로 cross-file 재링크**를 하기 때문 → mixed-backing 을 못 잇는다. 옛 가드("real-VPID 일 때만 connect")는 이 한계를 영속 규칙으로 굳혔고, 그래서 다들 connect 를 쓰려고 vpid 백킹을 재사용하게 됐다(=오염의 진원). **개편은 connect_list 자체를 폐기**하므로 이 가드는 "왜 새 연결구조가 필요한가"의 증거이지 새 구조의 제약이 아니다.
- Evidence: #62 attempt 1.
- Status: SUPERSEDED-by 축2 개편 (connect_list 폐기 예정).

### FAIL-04 — result-file / FILE_QUERY_AREA=1 백킹  [PERF]
- Assumption: 워커 출력을 query-area result file 로 backing 하면 머지가 단순해진다.
- Action: 스필 출력을 FILE_QUERY_AREA result-file 로.
- Result: **1571s** catastrophic.
- Guardrail: **DO NOT** 스필 출력을 FILE_QUERY_AREA result-file 로 backing 하지 마라.
- 재해석(개편 기준): 유효. 단 "처리 중 결과를 query-area 로 흘리는 것"이 나쁘다는 것 = 축1 의 "transient 는 처리 중 공용/캐시 file 에 안 쓴다"와 일치하는 증거.
- Evidence: #62 attempt 2.
- Status: REVERTED (사실 유효).

### FAIL-05 — real-VPID backing 이 "truncation"을 고친다는 추적  [FALSE-ALARM]
- Assumption: 병렬 SORT/DISTINCT 40% truncation 은 mixed-backing read 때문 → real-VPID backing 으로 고친다.
- Action: 워커/origin 을 real-VPID backing 으로 전환.
- Result: 그 "truncation" 자체가 **측정 아티팩트**(raw-stdout-md5 / GROUP_CONCAT)였음(#63). 고치려던 버그가 없었다.
- Guardrail: **DO NOT** raw-stdout `|md5sum` / `MD5(GROUP_CONCAT())` 차이를 corruption 증거로 삼지 마라. robust 집계(COUNT/SUM/MIN/MAX)로만 판정.
- 재해석(개편 기준): 100% 유효 — 개편 게이트도 robust 집계로만 판정(SSOT §6).
- Evidence: #62 attempts 3/4; #63(CLOSED).
- Status: SUPERSEDED-by FAIL-08.

### FAIL-06 — NOT_USE_MEMBUF 0x1000 (force membuf==NULL real-VPID + connect)  [PERF + CRASH]
- Assumption: 워커+origin 을 `membuf==NULL` real-VPID 로 강제 + connect 하면 raw-fd 오버헤드 없이 parity.
- Action: `NOT_USE_MEMBUF=0x1000` 플래그로 강제 백킹 + connect 머지.
- Result: robust **PARITY PASS** 였으나 **PERF +209%** + **debug crash + core + orphan leak**.
- Guardrail: **DO NOT** NOT_USE_MEMBUF 0x1000 / force-membuf==NULL backing 재도입 금지. (stale `fix62_gate` FAIL 의 출처 — 현 워크트리 상태 아님.)
- 재해석(개편 기준): ⚠️ 이건 "옛 구조 안에서 connect 를 살리려는" 막다른 길의 결정적 증거. 개편(connect 폐기 + per-worker 백킹)은 이 길로 안 간다. correct-but-slow 가 났다는 것 자체가 "옛 백킹 모델이 비용 구조상 틀렸다"는 증거.
- Evidence: #62 attempt 5; `fix62_gate/report.md`(FAIL). clean at `e21917cfd`.
- Status: REVERTED.

### FAIL-07 — #62 근본원인 red herrings (TDE / merge-copy / mixed-backing)  [근본원인 오추적]
- Assumption: heavy-spill 회귀 원인이 TDE 암호화 / 워커-출력 merge-copy / mixed-backing read 중 하나.
- Action: 각각을 원인으로 가정하고 수정 시도.
- Result: VTune 에서 셋 다 0.0s 급 → 전부 기각. 실제 원인은 per-tuple dirty-mark 락(+37.6s).
- Guardrail: **DO NOT** #62 perf 원인으로 TDE/merge-copy/backing 재의심 금지.
- 재해석(개편 기준): 유효. "락이 지배"라는 것 = 전역 레지스트리 제거(축1)가 정공법이라는 직접 증거.
- Evidence: `perftable_profile/why_slow.md` §VTune.
- Status: SUPERSEDED-by 프로파일링.

### FAIL-08 — #63 병렬 SORT/DISTINCT 오답 보고 = FALSE ALARM  [FALSE-ALARM]
- Assumption: 병렬 SORT/DISTINCT 가 행을 ~40% truncate 한다.
- Action: 병렬 경로를 의심하여 여러 차례 코드 revert/serial-force.
- Result: robust 재검(COUNT/SUM/MIN/MAX)으로 serial==parallel 증명. truncation 은 raw-stdout-md5 포맷 아티팩트. **revert 들이 오히려 잘못**.
- Guardrail: **DO NOT** 나쁜 QA(MD5/GROUP_CONCAT)로 정상 병렬 코드 revert 금지.
- 재해석(개편 기준): 100% 유효. 가장 비싼 교훈(~10시간 + 다수 wrongful revert). 개편 중에도 robust 집계로만 판정.
- Evidence: #63(CLOSED).
- Status: CLOSED(false alarm).

### FAIL-09 — raw-fd temp 를 data-buffer LRU 로 라우팅 (R6 env-A)  [PERF]
- Assumption: raw-fd temp 쓰기를 일반 data buffer 를 통해 처리해도 된다.
- Action: raw-fd writes 를 data-buffer 경유.
- Result: env-A I/O-bound **~10x** 회귀 = data-buffer LRU 오염.
- Guardrail: **DO NOT** temp 를 일반 data-buffer LRU 로 라우팅하지 마라. temp-page 는 LRU-ignore-unfix(`pgbuf_unlatch_void_zone_bcb`) 필요.
- 재해석(개편 기준): 100% 유효 — 축1 의 "transient 가 공용 풀 LRU 를 오염시키지 않는다" 불변식의 직접 근거. persist copy-out 경로도 LRU 오염 주의.
- Evidence: `f21d2a624`(REJECTION)→`8a8cebde4`(LRU-ignore-unfix 포팅).
- Status: REJECTED / mitigated (사실 유효).

---

## A. ROUND-BY-ROUND 진행 이력 (개편 기준 재해석 포함)

전체 목표(재기준): CUBRID temp 스필을 PostgreSQL식 work_mem + per-worker BufFile/logtape/SharedFileSet 모델로 **전면 개편**.
(아래는 e21917cfd 까지의 경로. raw-fd "single overflow" 시제는 **중간 산출물**이지 목적지가 아님.)

- **락 재설계 (G001~G003)** (`97043c9d8`/`ccc4d034f`/`ab6ea6452`): 전역 mutex 1개 → registry/fixed_pages/read_cache 3분할 + O(1) 보조인덱스 + 64-shard. mutex self-CPU **356→26.4s**. 아키텍트 CLEAR.
  - 재해석: 유효한 개선이나 **전역 레지스트리를 전제로 한 완화책**. 개편(레지스트리 제거)이 되면 이 machinery 상당부는 dead-path 가 된다.
- **Phase C C-2 hash-agg native merge** (`4f9f4ca7f`): `qmgr_materialize_list_to_single_owner` pgbuf-copy 3사이트 제거. 아키텍트 CLEAR.
- **Phase D work_mem GUC** (`dcb7bacda`): `PRM_ID_WORK_MEM`(4MB) 추가, 레거시 4파라미터(sort_buffer_size/sort_buffer_pages/max_hash_list_scan_size/temp_file_memory_size_in_pages) 하드제거. → 개편의 유효 토대.
- **#64 병렬 PHJ on raw-fd FIXED** (`e21917cfd`): 병렬 PHJ 입력 page-distribution 이 raw-fd-blind 였던 것 수정(`query_hash_join.c`/`px_hash_join_task_manager.cpp`/`px_hash_join.cpp`). robust gate PASS(병렬==직렬, 병렬이 더 빠름). 아키텍트 CLEAR.
  - 재해석: 옛 구조 위의 정확성 수정. 축2 개편 시 이 경로도 새 연결구조로 흡수된다.
- **#63 = FALSE ALARM → CLOSED** (FAIL-08): 과거 다수 wrongful revert 무효화.
- **#62 fix 시도 1~5 = 전부 FAIL/REVERT** (FAIL-03/04/05/06): connect garbled / FILE_QUERY_AREA 1571s / real-VPID truncation(아티팩트) / NOT_USE_MEMBUF +209%+crash. → 전부 "옛 구조 봉합" 시도였고 막다른 길.
- **#62 근본원인 PINNED** (FAIL-07): per-tuple raw-fd dirty-mark 락(+37.6s) 이 syscall(+7.4s) 지배.
- ~~dirty-flush 타깃 수정(방안 E) + robust gate~~ → **CUT-LOG 참조. 증상 패치라 개편 결정으로 폐기.**

---

## B. Representative perf table (develop vs e21917cfd) — 현 구조 비용 = 개편 동기

출처: `perftable_profile/perf_table.tsv`. conf: 양쪽 `data_buffer_size=512M`, `parallelism=8`, `max_parallel_workers=8`; develop `sort_buffer_size=8M`, e21917cfd `work_mem=8M`. robust parity 전부 일치.

| query | develop median s | e21917cfd median s | delta | parity |
|---|---:|---:|---:|---|
| PHJ_wmloc | 2.505 | 4.007 | +60.0% | YES |
| PSORT_wmloc | 0.502 | 0.503 | +0.0% | YES |
| PSCAN_wmloc | 0.502 | 0.502 | -0.0% | YES |
| HASHAGG_wmloc | 3.006 | 3.507 | +16.7% | YES |
| PSORT_tpch | 39.058 | 67.093 | **+71.8%** | YES |
| HASHAGG_tpch | 25.041 | 29.543 | +18.0% | YES |
| DISTINCT_tpch | 41.565 | 52.573 | **+26.5%** | YES |

해석: 경량(PSORT/PSCAN wmloc)은 develop 동등. 회귀는 **heavy-spill 경로에 집중** = 개편으로 제거할 비용.

---

## C. VTune self-CPU 귀속 (sw sampling, attach cub_server) — 개편 동기

| category | develop DISTINCT | e219 DISTINCT | e219 PSORT |
|---|---:|---:|---:|
| pthread mutex lock/unlock | 15.260 | **52.889** | **80.442** |
| pread/pwrite syscall self-CPU | 27.630 | 35.009 | 34.785 |
| memcpy/memmove | 23.181 | 19.293 | 17.205 |
| sort core | 18.052 | 17.765 | 18.047 |
| pgbuf path | 47.404 | 32.223 | 23.047 |
| worker-output merge copy | 0.000 | 0.000 | 0.000 |
| AES/TDE | 0.000 | 0.000 | 0.000 |

→ 단일 지배 신호: **mutex lock/unlock delta +37.6s** (DISTINCT 52.889 vs 15.260). syscall delta +7.4s 는 부차.

락 스택(결정적 증거) — e21917cfd DISTINCT:
```
__GI___pthread_mutex_lock                       32.670s
 std::lock_guard<std::mutex>::lock_guard         23.026s
  rawfd_find_and_mark_dirty                      22.717s   <- 전역 레지스트리 shard mutex + map.find
   temp_page_store::rawfd_flush_page             22.717s
    qmgr_set_dirty_page                          22.717s
     qfile_set_dirty_page                        22.717s
      qfile_generate_tuple_into_list             22.687s   <- 튜플마다
```
develop 은 동일 스택에 raw-fd dirty 경로 자체가 없음(0.000s).
→ **이 비용 전체가 "전역 페이지 레지스트리를 워커가 공유"하는 구조의 직접 산물.** 축1(레지스트리 제거)로 사라진다.
원본 스택: `perftable_profile/vtune_e21917cfd_{DISTINCT,PSORT}_tpch_stacks.txt`.

---

## D. strace raw-fd vs pgbuf (16KB 페이지) — 이중 스필 증거

### DISTINCT_tpch
| op | develop calls/GiB | e21917cfd calls/GiB | delta |
|---|---|---|---|
| pread64 pgbuf_temp | 1,473,581 / 22.485 | 1,924,674 / 29.368 | +451,093 / +6.883 |
| pread64 rawfd_temp | 0 / 0 | 202,866 / 3.088 | +202,866 / +3.088 |
| pwrite64 pgbuf_temp | 1,410,130 / 21.517 | 1,438,685 / 21.953 | +28,555 / +0.436 |
| pwrite64 rawfd_temp | 0 / 0 | 202,866 / 3.088 | +202,866 / +3.088 |

→ DISTINCT 추가 temp logical I/O = **+13.495 GiB**(raw-fd 6.176 + pgbuf net 7.319). raw-fd 가 **추가**되고 pgbuf read 가 증가. PSORT raw-fd add = **15.95 GiB**.
→ 축1(단일 백킹 + transient 폐기 + 종료 후 copy)이 이 이중 스필을 제거한다.

---

## E. PostgreSQL 비교 — ★개편 청사진 (가장 중요)

> CUBRID 재설계는 "워커들이 공유하는 서버 전역 페이지 레지스트리"에 락을 걸지만, PostgreSQL 은 temp 스필에 공유 상태를 두지 않는다.

| 축 | develop CUBRID | e21917cfd (raw-fd) | **PostgreSQL (목표 모델)** |
|---|---|---|---|
| temp 거점 | 공유 pgbuf 풀(temp BCB) | 서버 전역 raw-fd 레지스트리(64-shard) | **공유 풀 없음 — 워커별 `BufFile`** |
| dirty 추적 | per-BCB 미세 래치 | **페이지마다 shard mutex + map.find** | **`BufFile` 당 dirty bool 1개**, 버퍼 찰 때만 dump |
| I/O 단위 | — | **페이지 단위 16KB**(DISTINCT 405K syscalls) | 버퍼 전체 1회 dump + `logtape` prefetch |
| 동시성 | 낮음 | **가변 레지스트리 공유 → 락 필수** | **워커가 자기 BufFile 소유; 리더가 frozen tape 읽기전용 import(SharedFileSet)** |
| 정렬 스필 | membuf | membuf/PRIVATE_SPILL/raw-fd **백킹 분기** | **`logtape.c`: 단일 temp 파일에 논리 테이프 다중화 + prefetch** |
| 이중 스필 | 없음 | **있음(raw-fd + pgbuf)** | **없음(한 번만)** |
| 정리 | boot-sweep + (owner_tran,query_id) | 전역 레지스트리 + boot-sweep | **ResourceOwner — close 시 unlink 자동** |

왜 PG 가 빠른가(3줄):
1. dirty/flush 가 버퍼(또는 logtape 의 큰 런) 단위로 상각 → 페이지마다가 아니라 버퍼가 찰 때 한 번. 자기 소유라 락 불필요.
2. temp 에 전역 레지스트리/공유 풀이 없음 → hot path 워커 간 락 0.
3. I/O 모아서 크게 + prefetch → syscall 수십 배 적음.

→ **이게 축1+축2 개편의 설계 지침이다.** 참고 파일: `~/dev/postgres/src/backend/storage/file/buffile.c`, `src/backend/utils/sort/logtape.c`, `tuplesort.c`.

---

## F. I/O 프로파일 요약 (참조)
- e21917cfd DISTINCT: raw-fd 405,732 pread+pwrite(per-page) + raw-fd 6.176 GiB + pgbuf ~29 GiB read / ~22 GiB write. syscall self-CPU +7.4s.
- VTune: `/opt/intel/oneapi/vtune/latest/bin64/vtune` (sw sampling, `-target-pid` cub_server). 고정-duration attach(DISTINCT 75s/PSORT 95s/develop 65s).

---

## G. 인프라/주의 (운영 — 유지)
- 빌드: cubrid-build 스킬만 (`WORKSPACE=/home/cubrid/dev/cubrid-workmem just build release|debug`, `just` 는 `/home/cubrid/dev/workspace`). raw cmake 금지(설치/symlink 안 됨).
- 서버: cubrid-server-control 래퍼만. 바이너리 전환 시 stale `cub_master` kill. `CUBRID_SERVER_CTL_TIMEOUT=420`.
- DB: `tpch_sf10`(lineitem 60M), `wmg003`(TDE), `wmloc`(t 4.19M single int).
- 바이너리: develop `/home/cubrid/release/CUBRID-develop-69e73b47`; 재설계 tip `/home/cubrid/release/CUBRID-11.5.develop`(e21917cfd).
- 아키텍트 stale-clone 회피: `git show <sha> -- <files> > scratch/...diff` 후 diff 파일 READ.
- GitHub(xmilex-git/cubrid): #60 parent; #62 OPEN(perf 증상); #63 CLOSED(false alarm); #64 CLOSED(fixed); #65 status.

---

## H. 설계 해소 근거 — grill-with-docs 세션 (2026-06-29, 측정/사실)

> SSOT §2~§5 결정의 코드 근거. 전부 e21917cfd / develop(`~/dev/cubrid`) / PG(`~/dev/postgres`) 의 측정·사실(구조 가정 아님). 결론은 SSOT, 용어는 CONTEXT.md.

### H-1. holdable = reparent (복사 불필요) — develop 이 이미 그렇게 함 → ADR 0001
- develop 커밋 경로(`~/dev/cubrid/.../query_manager.c:2345-2348`): `xsession_store_query_entry_info` → `qentry_to_sentry`(`session.c:2417-2422`)가 list_id/temp_file **포인터 이동(복사 0)** + `session_preserve_temporary_files`(`session.c:2466`)가 `file_temp_preserve`+`preserved=true` **플래그**. = tran→session reparent.
- e21917cfd 회귀: `qmgr_materialize_to_pgbuf`(`query_manager.c:3640-3694`)가 커밋마다 전 튜플 scan+re-add = **전체 결과셋 복사**. 강제 이유 = raw-fd가 file-manager 밖이라 `file_temp_preserve` 불가 + reaper가 `(tran,query)` 죽으면 unlink(`temp_page_store.cpp:1864`).
- 세션 teardown 훅 존재: `session_state_free`→`session_free_sentry_data`(`session.c:2566`)가 `qfile_close_list`+`qmgr_free_temp_file_list` → reparent 백킹 orphan-zero 가능.

### H-2. persist = 정확히 2클래스 (OPEN#1 CLOSED)
- `file_temp_preserve` 호출자 **딱 둘**: result cache(`query_manager.c:3140`) + holdable(`session.c:2466`). `FILE_QUERY_AREA`("permanent query result file")도 result-cache 전용 → 트랜잭션 너머 생존 **제3 메커니즘 없음**.
- SP/method 결과 = holdable(`method_query_handler.cpp:848 db_session_set_holdable(true)`) → 별도 클래스 아님. cursor 재오픈 = `session_load_query_entry_info`(holdable). 나머지(external sort 중간산출 등) = transient(`query_executor.c:1408 if(!is_result_cached) qfile_destroy_list`).

### H-3. 스캔 = 2레벨→3레벨 + 스캔-우회 소비처 인벤토리(전부 리팩터 대상)
- `qfile_scan_next`(`list_file.c:4979-5070`): inner(tuple @5013-5018) / outer(page = 헤더 next_vpid follow @5026). 신규 = +Tape 최외곽 루프(3레벨).
- A `membuf[pageid]` 직접: `list_file.c:1405`, `query_manager.c:2872/2939`, `temp_page_store.cpp:1393`. B `membuf==NULL`/`membuf_last` 분기: `query_hash_join.c:1905`, `scan_manager.c:4963/6630`. C `first_vpid`/`last_vpid` 범위 분할: `external_sort.c:4486/4555-4557`. D `last_pgptr` next_vpid 직접 NULL: `query_executor.c:10045-10051/16781-16784`. E sector 분배: `px_scan_input_handler_list.cpp:105`, `px_hash_join_task_manager.cpp`.
- "Tape 컬렉션" 원형 이미 존재: `mergeable_list_variables.writer_results`(`vector<QFILE_LIST_ID*>`), `xasl_snapshot_variables.list_id_headers` + `read_spec{ list_id_header*, QFILE_LIST_SCAN_ID }`(px_scan_result_handler.hpp).

### H-4. membuf 강제 OFF 사이트 (재활성 surface)
- `connect_list` assert `membuf==NULL`(`list_file.c:3177`), `use_connect` 게이트 양측 `membuf==NULL`(`query_hash_join.c:1905-06`), `PRIVATE_SPILL_FALLBACK`→`membuf=NULL`(`query_manager.c:3902`), NOT_USE_MEMBUF/0x0800. connect 폐기 시 전부 제거 가능 → per-Tape membuf 재활성.

### H-5. TDE 정책 (그대로 상속)
- `includes_tde_class`(=`XASL_INCLUDES_TDE_CLASS`, `query_manager.c:1444`)일 때 temp `tde_encrypted=true` + `file_apply_tde_algorithm`. raw-fd 경로는 `tde_encrypt_data_page`(fresh-nonce-per-physical-page). VTune AES/TDE=0.0s(FAIL-07) → 비용 무시. membuf(RAM)은 plaintext.

### H-6. PG 청사진 용어 (`~/dev/postgres`)
- `LogicalTape`/`LogicalTapeSet`/`LogicalTapeFreeze`/`LogicalTapeImport`/`TapeShare`(logtape.c); `BufFile`(buffile.c — 주의: PG "segment"=BufFile 1GB 물리조각); `SharedFileSet`(cross-worker), `FileSet`(트랜잭션 넘겨 생존=holdable, buffile.c:39-42); parallel read **"chunk"**(tableam.c:571, atomic `phs_nallocated`); `SharedTuplestore` "participant"/"chunk". → CONTEXT.md 가 정준 매핑.

---

## I. ralplan 구현-사실 (2026-06-29, 측정/코드사실 — 개편 후에도 유효)

> 구현 계획(ralplan 합의 → `pending-approval.md`) 중 e21917cfd 에서 검증한 코드사실. "측정/사실"이지 "구조 가정" 아님. I-1 은 SSOT §3.2 B2 / §6 정정과 연동(유저 컨펌 후 교체 완료 2026-06-29).

### I-1. append-only 는 보편 사실이 아니다 (★SSOT §3.2 B2 정정 근거 — bitmap 필요)
- 검증: `sort_split_input_temp_file`(external_sort.c:4460)가 parallel-sort 입력 temp 파일을 N 분할하며 **이미 쓴 page 헤더를 in-place 재기록**: `QFILE_PUT_PREV_VPID_NULL(page_p)`@4497, `QFILE_PUT_NEXT_VPID_NULL(page_p)`@4509 + `qmgr_set_dirty_page(DONT_FREE)`. = append-only 아님.
- 결론: 옛 SSOT B2 "spill=append-only → bitmap 불필요" **단정 철회.** Chunk 분배 = occupancy(bitmap) 추적 필요; bitmap-free 는 producer 별 append-only 검증 통과 frozen Tape 한정. (신 BufFile-시대 producer 는 분할을 논리 range 로 재구성하면 append-only 가능 → Phase2 producer 별 검증.)
- 삽질 방지: SSOT 가 "append-only" 를 닫힌 사실로 두면 다음 작업자가 bitmap-free 를 깔았다가 **silent wrong result**.
- **UPDATE (grill round 2 — 결론 supersede):** "bitmap 필요" **철회.** sort_split 의 in-place 재기록은 **입력 분배**(워커에게 나눠주기)이지 동결 출력의 속성이 아님. 새 백킹=per-worker private flat + **mid-life dealloc 없음**(`qfile_truncate_list`=전체 리셋) → R2 = **64page offset-range work-stealing, bitmap 없음**. 측정사실(헤더 in-place 재기록)은 보존, 결론만 supersede. (ADR 0003, SSOT §3.2/§5.2 UPDATE)

### I-2. 방법 교훈 — "passthrough-tautology 게이트" 안티패턴 [METHOD]
- 레거시 1-Tape 어댑터만 통과시키는 게이트(예 "1-Tape robust-parity == e21917cfd")는 신 multi-Tape 3좌표/scan_prev/경계 로직을 **전혀 검증 못 함**(어댑터가 옛 raw-fd/next_vpid 로 위임). 가장 위험한 정확성 코드(역방향/jump)를 작성만 하고 한 phase 내내 미검증으로 둠.
- 교훈: 신 구조를 **합성 N-Tape split**(test-only)로 강제 생성해 producer 이주 전에 같은 게이트로 forward/reverse/jump/empty-skip/terminal/S_END-on-last 검증.
- **UPDATE (grill round 2):** 교훈(합성 N-Tape gate 로 producer 이주 전 검증)은 **그대로 유효.** 단 "3좌표/scan_prev"는 이제 **offset 산술 `(tape_idx, page_offset, tuple_offset)`**, page directory 없음(ADR 0002/0003). gate 항목(forward/reverse/jump/empty-skip/terminal/S_END-on-last) 불변.

### I-3. `qfile_scan_next` 는 position state machine [CODE-FACT]
- list_file.c:4979-5070 = S_BEFORE/S_ON/S_AFTER 분기(nested 2중 루프 아님). raw-fd 분기 2곳(@4988/5020), tuple@5013-5018, next_vpid follow@5026, S_END@5058. "3-레벨 스캔"=`tape_idx` 차원을 **모든 position 분기에 관통**(외곽 루프 1개 추가가 아니라 더 침습적).
- `qfile_scan_prev`(@5081): S_ON 에서 page-header `prev_vpid` walk(@5100-5102). → backward 가 prev_vpid 의존 → connect 폐기 시 per-Tape page directory 필수(SSOT §3.2 정정 연동).
- **UPDATE (grill round 2):** state machine 코드사실 유효. 단 "per-Tape page directory 필수" **철회** — per-worker private flat 백킹 + dealloc 없음 → backward/jump = **`page_offset±1` 산술**, directory 불필요(ADR 0003).

### I-4. QFILE_LIST_ID 소유권 함정 [CODE-FACT]
- `qfile_copy_list_id`(list_file.c:465)가 struct memcpy 복사(~12 사이트) + dependent 보정. 모드 `QFILE_{SKIP,MOVE,PROHIBIT}_DEPENDENT`: scan-open@5444=SKIP(얕은참조), result-cache@6631=PROHIBIT(copy-out), holdable=MOVE(handle move). `qfile_clear_list_id`@585 가 `dependent_list_id` 재귀 free@607.
- 함의: 추가하는 Tape 벡터는 copy/clear/모드별 소유권을 **반드시** 확장. 누락 시 cached(copy)/holdable(move) 경로서 leak(orphan 위반) 또는 double-free(no-crash 위반). (SSOT B1 정정 연동.)

### I-5. page-directory 메모리 [CODE-FACT]
- 옛 backward = page-header `prev_vpid`(추가 메모리 0). 신 per-Tape page directory = O(pages) → 멀티-GiB 스필(수백만 16KB 페이지)×다수 Tape 서 메모리 폭주 위험. → PG `logtape` **indirect-block 스타일** 표현(dense whole-tapeset 배열 금지) + 메모리 카운터 게이트.
- **UPDATE (grill round 2 — supersede):** **page directory 자체 폐기 → 이 메모리 위험은 무효(moot).** 주소 = offset 산술, per-Tape 메타 = 스칼라 2개(`prefix_page_count`, `total_page_count`). (ADR 0003)

---

## Z-APPEND (2026-06-29, #67 baseline reproduction) — measured fact

### FAIL-10 — e21917cfd 병렬 PHJ_wmloc `allocate 0 memory bytes`  [CRASH/WRONG → ERROR]
- Assumption(없음): #67 release-only 베이스라인 재현 중 관측된 신규 사실.
- Action: e21917cfd release(11.5.0.2297-e21917c), wmloc, work_mem=8M, parallelism=8/max_parallel_workers=8 에서 `SELECT /*+ USE_HASH(a,b) PARALLEL(8) */ ...` (perf+parity 둘 다).
- Result: 결정적(3/3) `ERROR: Out of virtual memory: unable to allocate 0 memory bytes` @ `query_hash_scan.c:662` (8 workers, EID 3~10). serial(max_parallel_workers=1) OK, develop OK. 가용 124GiB(188 total) → 실제 OOM 아님.
- Root: `qdata_alloc_hscan_value()` `tuple_size=QFILE_GET_TUPLE_LENGTH(tpl)=0` → `db_private_alloc(0)`=NULL → spurious OOM. 0-length 튜플 = 병렬 hash-scan 워커 read-positioning 결함.
- 재해석(개편 기준): SSOT §3 축2(worker 출력 연결/positioning fragility)의 **직접 증거**. raw-fd/connect 백킹 위 병렬 워커 포지셔닝이 길이0 튜플 생성. 개편(논리 Tape import + offset 산술)으로 제거 대상.
- 주의: reference(#76 §B, 동일 바이너리, ~9h 전)에선 PHJ_wmloc parity=YES → 데이터 레이아웃/워커 분배 민감 latent. perf 표의 PHJ_wmloc e219 "2.005s" 는 에러-중단 시간(무효치).
- Evidence: server err `CUBRID-11.5.develop/log/server/wmloc_20260629_2037.err`; repro `~/.claude/scratch/remote-codex/issue67_reproduce/`.
- GitHub: **#77** (OPEN). Status: TRACKED(#77).

---

## I-6. Phase1 1A-0 accessor-shim 착지 (2026-06-29, #69) — 구현/측정 사실

> SSOT #75 / Evidence #76 기준. "측정/코드사실"이지 "구조 가정" 아님 — accessor-shim 은 SSOT 불변식을 **강화**하는 무동작 구현장치(plan §2 1A-0, Option D fold). 설계 무변경(SSOT 미수정).

- **무엇을 했나**: `QFILE_LIST_ID` 의 connection-identity(`first_vpid`/`last_vpid`) + backing(`tfile_vfid`) + dependency(`dependent_list_id`) 4필드를 trailing-underscore(`*_`)로 rename + lvalue accessor 매크로 4개(`QFILE_LIST_ID_{FIRST_VPID,LAST_VPID,TFILE_VFID,DEPENDENT}`, query_list.h) 도입. `QFILE_CLEAR_LIST_ID`(canonical init)만 renamed raw 필드 직접접근. → raw `*_` 필드는 **query_list.h 안에서만** 등장(grep 확인) = F1(copy/clear 소유권)·F3(Phase3 심볼 sweep) surface 를 컴파일러가 강제 열거(신규 직접접근 = 컴파일 에러).
- **규모**: consumer 361 사이트 / 16 파일 (tfile_vfid+dependent_list_id 245 + first_vpid+last_vpid 116). diff additive(+359/−339). HEAD `e21917cfd` 유지, 미커밋(working tree).
- **코드사실 — CUBRID `.c` 는 C++ 로 컴파일**: `c++`(g++) + `const_cast`(list_file.c:533) 등 → tree-sitter-c 가 `.c` 를 parse-error. 결과: `ast_edit` 는 `.cpp` 만 적용 가능, `.c` 는 미적용. 우회 = unique-name 필드(`tfile_vfid`/`dependent_list_id`)는 bounded-receiver regex codemod, **shared-name 필드(`first_vpid`/`last_vpid`)는 codemod 금지**(heap_file.c `estimates.last_vpid`, page_buffer/external_sort/file_manager 로컬 등 同名 타구조 오염 위험) → 컴파일러(type-aware) 가 권위.
- **방법 — per-TU `-fsyntax-only` 열거**: `build_preset_release/compile_commands.json` 의 컴파일 커맨드에 `-fsyntax-only -fmax-errors=0` 부착해 TU별 type-aware 에러 열거(초 단위) → 전 필드접근 사이트를 풀빌드 없이 정밀 식별. 변환 후 16 TU 전부 syntax-clean(rc=0) 확인 후 풀빌드.
- **게이트 G0 (robust-parity, 무동작 증명) PASS**:
  - wmloc(work_mem=2M, 4.19M `t.a`): SORT/DISTINCT/GBY × serial(mpw=1)==parallel(mpw=8) **완전일치** — COUNT=4194304, SUM(CAST a NUMERIC(38,0))=8796090925056(=Σ0..4194303), MIN=0, MAX=4194303.
  - tpch_sf10 heavy-spill DISTINCT(`/*+ PARALLEL(8) */ DISTINCT l_orderkey,l_partkey,l_suppkey`): serial==parallel **완전일치** — COUNT=59986042, SUM(l_orderkey)=1799464978671107 등 全컬럼 일치.
- **빌드 검증 — #68 preflight 게이트 사용**: `gate_clean_install.sh`(SKIP_BUILD=1, MODE=release) PASS — release @ `e21917c`(install sha==HEAD sha), `~/CUBRID` repoint, 산출물/로케일 확인. (#68 measurement-hook 본체는 미빌드(#68 종료시 미충족) + 1A-0 무관 → 미사용.)
- **환경 사실(변경과 무관)**: fresh `just build release` 설치에서 PL(Java stored-procedure) 서버가 `pl_sr.cpp:546`("Failed to initialize the PL server")로 부팅 실패 → 서버 기동 위해 `stored_procedure=no` conf 우회(쿼리 테스트엔 무영향). G004 소스변경(query/list_id accessor)과 인과 없음.
- Status: 1A-0 DONE(미커밋). 다음 sub-step = 1A 스캔계약(`QFILE_TAPE`+Tape벡터+3레벨 scan, plan §2 1A-1~). accessor 시그니처는 1A-1 이 구현만 교체(NH-3).

---

## I-7. Phase1 1B per-worker 백킹 착지 (2026-06-29, #71 / #68 producer-side) — 구현/측정 사실

> SSOT #75 §2.2 + ADR 0003 + §H-1/§H-5 구현. "측정/코드사실"이지 "구조 가정" 아님. 설계 무변경(SSOT 미수정) — 1B 는 기존 설계를 구현. 1B 는 **additive no-op**: 신규 클래스가 어떤 producer 에도 연결되지 않음(QFILE_LIST_ID_TAPESET 는 모든 실 list 에서 여전히 NULL). producer 연결 = Phase2, lifecycle/reparent = 1C.

- **무엇을 했나 (hpp/cpp class, 유저 지시)**:
  - `src/query/qfile_buffile.{hpp,cpp}` — `qfile::buffile`: per-worker private append-only 파일. 자기 배치버퍼(8page)+fd, owner-only `append_page`, 배치 `flush`(1 pwrite), `read_page`=offset 산술 pread. **pgbuf BCB 우회**(pread/pwrite만, `pgbuf_fix` 미호출 → `buffile_metrics.pgbuf_fixes` 구조적 0). 전역 레지스트리/per-page 락 없음(e21917cfd raw-fd 와의 의도적 결별). 비-TDE=DB_PAGESIZE, TDE=IO_PAGESIZE stride.
  - `src/query/qfile_tape.{hpp,cpp}` 확장 — `qfile::buffile_tape`(tape = `[membuf prefix RAM] ++ [buffile]`, `page_at`=offset 산술: `<prefix`→RAM, else `read_page(off-prefix)`; 단일-reader 스크래치 1page) + `qfile::tape_writer`(membuf Option-A: 첫 budget page 는 work_mem RAM prefix, 초과분만 BufFile lazy-create append; `freeze`=zero-copy 소유권 이전 → 미스필이면 `memory_tape`(tiny), 스필이면 `buffile_tape`).
  - TDE 상속: `tde_encrypt_data_page`/`tde_decrypt_data_page`(is_temp=true, IO_PAGESIZE, FILEIO_PAGE wrap, fresh-nonce-per-page) — raw-fd `rawfd_write_page`/`rawfd_pos_read`(temp_page_store.cpp:1872/1988)의 검증된 기계 그대로 이식. membuf prefix(RAM)=plaintext.
  - `qfile_buffile_selftest`(query_manager.c env gate `CUBRID_BUFFILE_SELFTEST`, debug, rawfd selftest 옆) — bootless 단위테스트가 못 하는 TDE 라운드트립을 in-server 로 검증.
- **검증 (측정, debug `4fb599d` + 미커밋)**:
  - `unit_tests/tapeset` 10/10 PASS (`gate_tapeset_scan.sh` PASS). 신규: **G8** spilled file-backed Tape robust parity(forward==expected / backward==reversed / jump 4-probe prefix↔file 경계; budget=2→file_pages=4; producer pgbuf_fixes=0 + scan pgbuf_fixes=0), **G9** tiny-no-spill(budget=10→`spilled()`=false, file_pages=0, 디스크 미접촉), **G10** multi-Tape spill+tiny mix(producer pgbuf-bypass 각 tape=0). passthrough-tautology 회피(I-2): 실제 디스크 스필 후 read-back 으로 검증.
  - **TDE in-server (SA, db `wmg003` TDE)**: `BUFFILE_SELFTEST algo=1 result=0 (0=PASS)` — 20page(배치경계 통과) encrypt→pwrite→pread→decrypt 바이트-일치 + pgbuf_fixes=0. (셀프테스트 이후 단계의 "PL server can not be started" 는 fresh-debug PL 기존 이슈(I-6), 1B 무관 — selftest-없는 boot 도 동일.) rawfd selftest(`CUBRID_RAWFD_SELFTEST`)는 SA 에서 error_context assert(기존 rawfd-selftest 거동, 내 변경 무관).
  - **no-op 확인**: wmg003 SA 실쿼리 `SELECT count(*) FROM db_class`=75 정상(재링크된 debug 바이너리에서 정상 쿼리 무회귀). 1B 는 신규 파일 + additive 클래스 + CMake 등록 + env-gated debug-only hook 뿐, 기존 실행경로 무변경.
- **#68 producer-side 해소**: `buffile_metrics.pgbuf_fixes`(producer pgbuf-bypass) + `tape_writer.spilled()/prefix_pages()/file_pages()`(membuf 재활성/tiny-no-spill) = 측정 가능. `checklists/issue68_hooks.md` 1B 행 2건 DONE. 남은 deferred = 1C(orphan/reparent) / Phase2(CoV·no-mixed-backing) / cached.
- **방법 메모**: (a) `cubrid/`+`sa/` CMakeLists **양쪽**에 `qfile_buffile.cpp` 등록(#70 sa-undefined-ref 교훈 준수). (b) `DB_PAGESIZE`=`db_User_page_size` 컴파일타임 기본(IO_DEFAULT-RESERVED) → bootless 단위테스트서 buffile 유효. (c) TDE 키는 bootless 미로드 → TDE 라운드트립은 in-server selftest 전용(스텁 금지).
- Status: 1B DONE (미커밋). HEAD=`4fb599d42` 유지. 다음 = 1C(holdable reparent + orphan scan) 또는 Phase2(producer 이주).

## I-8. Phase1 1C holdable reparent + orphan-scan 착지 (2026-06-29, #72 / #68 orphan-side) — 구현/측정 사실

> SSOT #75 §2.2/§5.1/§5.5 (1)/§6 (1) + ADR 0001 + §H-1/§H-2 구현. "측정/코드사실"이지 "구조 가정" 아님. 설계 무변경(SSOT 미수정) — 1C 는 기존 설계를 구현. 1C 는 **additive no-op**: 신규 census/selftest 는 신규 백킹 클래스(tapeset/tape/buffile)에서만 동작, 실 list 는 여전히 QFILE_LIST_ID_TAPESET==NULL → census 무동작(zero-cost). producer 연결 = Phase2.

- **핵심 발견 (1A 재검증)**: holdable reparent 의 **MOVE(소유권 이전)와 teardown(소유 시 destroy)은 이미 1A(#70)에서 `qfile_copy_list_id`/`qfile_clear_list_id`의 tapeset 분기로 완비**됨(list_file.c:556-575 MOVE/SKIP/PROHIBIT, :642-645 owned-destroy). 1C 가 추가한 것 = **orphan-scan 측정훅(#68 1C 슬라이스) + zero-copy/teardown orphan-zero 검증**(silently-fake 없이 측정으로). reaper-liveness 확장은 신 백킹엔 N/A: 신 백킹은 tran-keyed reaper 에 등록되지 않고(pgbuf-bypass·private) list_id 소유 RAII 로만 수명관리 → list_id clear(질의종료) 또는 session teardown(holdable) 때 free. ADR 0001 의 reaper-widening 은 옛 백킹 병존(Phase2)·또는 신 백킹엔 by-construction 충족.
- **신규 (hpp/cpp class, 유저 지시)**: `qfile::tape_backing_census`(process-wide atomic `open_files` + `held_prefix_pages`; `qfile_buffile.{hpp,cpp}`). 계측: buffile ctor/dtor=file open/close(생성실패 delete 포함 대칭), memory_tape append/dtor + buffile_tape ctor/dtor=RAM prefix(owns 플래그 대칭). 두 불변식: **(a) reparent(MOVE)=zero-copy → 양 카운터 불변**(no copy/no flush), **(b) session teardown → 양 카운터 baseline 복귀**(orphan-zero = 파일핸들 AND RAM prefix). + `qfile_heldtape_selftest`(`qfile_tape.{hpp,cpp}`, env `CUBRID_HELDTAPE_SELFTEST`, qmgr_initialize debug-only).
- **검증 (측정, debug `80f2bf8` 재빌드 + 미커밋)**:
  - `unit_tests/tapeset` **13/13 PASS** (`./build_preset_debug/bin/test_tapeset_scan`, `ALL TESTS PASSED`). 신규: **G11** spilled 홀더블 reparent — budget2(prefix2+file4) → produce 시 census `+1 file/+2 prefix`, 절반 스캔 후 MOVE → **census 불변**(zero-copy)+src 소유 해제·dest 소유, 잔여행 스캔 == expected(parity), session teardown → census baseline 복귀(orphan-zero), producer 재-clear no double-free. **G12** tiny all-RAM(budget10/3page, file=0) reparent — open_files 무변동, RAM prefix MOVE→teardown orphan-zero. **G13** borrow(SKIP) — owns=false 사본 clear 가 producer Tape 미해제(single-owner), 이후 producer scan parity, owner teardown 만 orphan-zero. + **suite-wide orphan-zero** assert(전 게이트 종료 후 census=={0,0}).
  - **in-server `qfile_heldtape_selftest` (SA, demodb TDE)**: `HELDTAPE_SELFTEST algo=1 result=0 (0=PASS)` — 8page(budget2→6 spill) 실 on-disk(**TDE 암호화**) 파일 생성 → MOVE reparent(census 불변=zero-copy, producer 소유해제) → 잔여행 parity → **실 `qfile_copy_list_id(MOVE)`/`qfile_clear_list_id` teardown**(유효 thread-entry 하) → `stat()` 으로 파일 unlink 확인 + census baseline. scratch `cubrid_buffile/` 디렉토리 **빈 상태 확인**(실파일 orphan-zero). algo=1 → TDE-암호화 백킹 reparent+teardown 경로까지 커버.
  - **no-op 확인(실쿼리 무회귀)**: 1C 코드는 실쿼리 경로에 **0 라인** 추가(census=신클래스 ctor/dtor 한정, list_file.c scan/copy/clear 무변경, query_manager.c=dormant debug env-gate). 재빌드 debug 바이너리로 fresh isolated DB SA 실쿼리: DISTINCT(1000 distinct, SUM=499500=Σ0..999 ✓, MIN=0/MAX=999), GROUP BY(1000 groups, 62625 rows ✓), ORDER BY DESC(999/998/997 ✓) — robust 집계 정확·assert/crash 없음. demodb 의 `tp_domain_init` assert 는 fresh-debug stale-catalog/SA 기존 이슈(env-gate OFF, 내 코드 dormant 상태에서도 발생 → 1C 무관). serial==parallel G0 베이스라인은 #69/#70 에서 기수립, 1C additive 라 불변.
- **#68 orphan-side 해소**: `tape_backing_census`(file + RAM prefix) = SSOT §6 게이트 (1) orphan-zero 측정 가능. `checklists/issue68_hooks.md` orphan 행 **DONE**. 남은 deferred = Phase2(CoV·no-mixed-backing)·cached.
- **방법 메모**: (a) **부트리스 유닛테스트는 `qfile_copy_list_id`/`qfile_clear_list_id` 직접호출 금지** — 내부 `thread_get_thread_entry_info()`(qlist 카운터용, type_cnt==0서 no-op 이나 인자 평가가 선행)가 thread-local entry assert(`cubthread::get_entry`) → bootless abort. G11~G13 은 MOVE/SKIP 2~4줄 분기 + owned-destroy 를 **명시 미러**(주석)로 검증하고, 실 함수 배선은 in-server selftest 가 검증. (b) census 는 frozen-tape/held 자원만 셈(writer 의 일시 prefix 미계수) → orphan surface 와 정합·전 경로 대칭.
- Status: 1C DONE (미커밋). HEAD=`80f2bf810` 유지(소스 클린). 변경 6파일(qfile_buffile.{hpp,cpp}, qfile_tape.{hpp,cpp}, query_manager.c, unit_tests/tapeset/test_tapeset_scan.cpp, +645). 다음 = Phase2(producer 이주: 스캔-우회 인벤토리 A~E + membuf 강제OFF 게이트 제거→재활성 + R2 offset-range work-stealing + no-mixed-backing/CoV 측정훅).

## I-9. Phase2 R2 distributor + no-mixed-backing 태그 착지 (2026-06-29, #73 / #68 CoV·no-mixed) — 구현/측정 사실

> SSOT #75 §3.2 B2 / §5 (R2) / §6 (3)(7) + ADR 0003 + tape-model "Parallel read". "측정/코드사실"이지 "구조 가정" 아님. 설계 무변경(SSOT 미수정) — 기존 설계 구현. **additive no-op**: chunk_distributor 는 어떤 라이브 reader 에도 미배선, backing-kind 태그/predicate 는 라이브 dispatch 에 미배선(실 list 여전히 OLD·tapeset NULL → 무동작).

- **R2 distributor 코드사실 (`qfile::chunk_distributor`, qfile_chunk.{hpp,cpp})**: 동결 Tapeset 의 논리 페이지공간([membuf prefix RAM]++[private file])을 **64page offset-range Chunk** 로 분할, 공유 `std::atomic<long> m_next` 의 `fetch_add` 로 N reader 가 work-stealing 청구. per-Tape 메타 = 누적 chunk-offset 배열(크기 n_tapes+1, = parallel degree); 글로벌 chunk index g → `upper_bound` 로 owning Tape → `(tape_idx, local*64, min(64, pages-local*64))` **순수 산술**. **page/chunk 테이블 미materialize** → 수백만 페이지 스필서도 O(n_tapes) 메모리(ADR 0003 "per-Tape 스칼라 2개" 정합, bitmap/sector/directory 없음). per-reader 페이지누계는 reader-private 슬롯(락 0, atomic 은 m_next 단 하나). CoV = stddev/mean.
- **측정 (debug `90dd15b` 재빌드 + 미커밋, `gate_tapeset_scan.sh` exit 0, 15/15)**:
  - **G14(a) 실 동시성 커버리지**: skewed 멀티-Tape `{200,0,5,64,1,130,0,33}`(empty Tape 포함), 6 reader **std::thread** 각자 `next_chunk` drain → 각 reader 가 모은 range 합산 시 전 페이지(Σ=433) **정확히 1회** 청구(out-of-range/double-claim/gap = 0). fetch_add 가 각 chunk 를 정확히 1 reader 에 — 스케줄 무관 정확성.
  - **G14(b) balance(거대 단일 Tape)**: 6417p(=64×100+17 → 101 chunk, 1 partial), 8 reader 등속(round-robin = work-stealing 정상상태). 실측 per-reader = {832×4, 785, 768×3}, mean 802.125, **CoV ≈ 3.78% ≤ 15%**, max−min = 64 = chunk 1개(= work-stealing spread 상한). 거대 단일 Tape 가 chunk 로 쪼개져 N reader 균형 — SSOT §6 (3) 충족.
  - **G14(c)**: huge(12800p) + tiny×20(3p) skew 도 CoV ≤ 15%.
  - 방법: balance 단언은 **결정적 round-robin**(등속 reader 모델 — 스케줄 비결정성 회피, non-flaky), 커버리지는 **실 스레드**(스케줄 무관 정확성). 둘 분리 = 비-flaky + 강한 검증.
- **no-mixed-backing 코드사실 (query_list.h)**: `QFILE_BACKING_KIND{NONE/OLD/NEW}` 태그 + `qfile_list_has_old_backing`(real first_vpid OR tfile_vfid) / `has_new_backing`(tapeset) / `is_mixed_backing`(둘 다) + `qfile_check_no_mixed_backing`(debug assert). 직렬화 무관(`or_listid_length`/pack 은 필드별, tapeset_ 선례 동일). 
  - **G15 판별 검증**(passthrough-tautology I-2 회피): clean OLD(first_vpid 만)·clean NEW(tapeset 만) 통과 + 합성 mixed(VPID+tapeset, tfile+tapeset) 2종 **포착**. clean 만 통과시키는 게 아니라 **위반을 잡는다**(FAIL-03/06 mixed-backing 영구회피의 런타임 가드).
- **no-op 무회귀**: fresh isolated DB SA(재빌드 debug): DISTINCT COUNT=1000/SUM=499500/MIN=0/MAX=999, GROUP BY 1000그룹/2000행, ORDER BY ASC 0,0,1 / DESC 999,999,998 — robust 집계 정확, assert/crash 없음. query_list.h(광범위 include) 변경이 실쿼리 무영향(태그 필드 init-만, predicate/distributor 미배선).
- **#68 해소**: 게이트(3) CoV·(7) no-mixed-backing 행 DONE. 남은 deferred = (5) cached-persist 교차-트랜잭션(cached copy-out path, Phase2 subject 아님).
- **방법 메모**: `gate_tapeset_scan.sh` 의 `grep -q "FAIL"` 가 G15 테스트 **이름**의 "FAIL-03/06"에 오탐 → `grep -qE "FAIL \("`(실패 출력 실 포맷 `<name> FAIL (<n>)`)로 정밀화. 게이트 grep 은 테스트 출력 토큰에만 매칭해야 함(이름에 게이트 키워드 금지).
- Status: #73 인프라 2종 DONE(미커밋, HEAD=`90dd15b`). #73 라이브 producer 이주(인벤토리 A~E·membuf 재활성·2A-EXIT sweep·robust-parity)는 미착수 잔여.

## H-7. PG 동시읽기 청사진 — frozen tape N-reader (2026-06-30, grill round 3) — 측정/코드사실

> SSOT §3.2 B2 / §5.5 (3) "freeze 후 N reader 동시 read, 락 0" 의 코드근거. `~/dev/postgres` 측정/사실. 결론·결정 = ADR 0005.

- **PG `BufFile` 도 단일 커서**(buffile.c:71-105): 자기 `buffer`(PGAlignedBlock @104) + `curOffset`/`pos`/`nbytes`; `BufFileReadCommon`(@594)이 그 상태를 변경 → **한 BufFile 객체는 동시 read 불가**(우리 `buffile_tape` 단일 `m_readbuf` 와 동형).
- **그래서 PG 는 공유 안 하고 reader 마다 새로 연다**(sharedtuplestore.c, 병렬 hash join 배치): reader=`SharedTuplestoreAccessor`(백엔드-로컬, 참가자별), **자기 `read_buffer`**(@84) + **자기 `read_file`**; 청크 잡을 때 `BufFileOpenFileSet(&fileset->fs, name, O_RDONLY, false)`(@538-540)로 파일을 직접 open. 공유 mutable 상태 = **온디스크 파일(쓰기 후 불변) + 청크 커서 `p->read_page`(LWLock 하 `+= STS_CHUNK_PAGES`, @510-523)** 뿐.
- **왜 reader-별 open 인가**: PG 워커=별도 **프로세스**(주소공간 분리 → BufFile struct 공유 불가) + `BufFileOpenFileSet`이 **vfd 풀** 위라 많이 열어도 OS fd 안 마름.
- **overflow 재조립 청사진**: `sts_parallel_scan_next`(@556-560)가 overflow 청크 착지 시 `chunk_header.overflow * STS_CHUNK_PAGES` 만큼 **skip** → 경계 넘는 튜플은 *그 튜플을 시작한 청크*가 처리 = 우리 "first-page owner 만 재조립, 나머지 skip" 의 원형.
- **재해석(개편 기준)**: CUBRID 는 **스레드** 모델 + `qfile::buffile` 은 **raw `m_fd`**(vfd 풀 없음). PG 가 의존하는 *불변식*("freeze=불변, reader 마다 자기 버퍼, 공유는 청크커서뿐")은 **공유 fd + `pread`(offset-stateless) + per-reader 스크래치**(ADR 0005 ①)로 충족하면서 fd 1개만 씀. PG 의 reader-별 open(②)은 멀티프로세스 강제+vfd 흡수의 산물 → CUBRID raw-fd 에 그대로 옮기면 (reader×tape×Tapeset)만큼 fd 폭증. → **① 확정(유저 2026-06-30, ADR 0005).** 포팅 대상은 PG accessor 의 **per-reader `read_buffer` 원칙**이지 멀티프로세스 open 이 아님.

## I-10. PR #7173 가 #78 producer 이주 베이스라인을 재편 (2026-06-30, grill round 3) — 코드사실

> SSOT §5.4 UPDATE(2026-06-30)와 연동. `gh pr diff 7173`(CUBRID/cubrid, `[CBRD-26795] Parallel Sort Extension`, OPEN·5인 Approved 포함 xmilex-git·`mergeable:CONFLICTING`, +1361/−614) 측정/코드사실.

- **#7173 이 `sort_split_input_temp_file` 를 삭제**(diff: external_sort.c 본문 `-`, external_sort.h 선언 `-`, in-place `QFILE_PUT_NEXT/PREV_VPID_NULL` 재기록 `-`). 입력분배를 **정적 슬라이싱 → 공유 sector work-stealing**(`QFILE_LIST_SECTOR_SCAN_INFO` `px_sector_scan`, `qfile_open_list_sector_scan(input_file)`, `sector_page_iterator`)으로 교체. → **I-1 의 "sort_split = in-place 재기록(append-only 아님)" 코드사실은 #7173 이후 무효(함수 자체가 사라짐)**; plan IR-6("SORT split=OLD 잔존 / inventory-C residual for Phase3") **전제 소멸** — Phase3 이월할 split 잔존 없음.
- **`sector_page_iterator` 가 `query_list.h` 로 공통화**(우리 fork 현 위치=`px_hash_join_task_manager.cpp:252`; #7173 이 −126/−33 후 헤더로 이동, sort+hashjoin+pscan 공통). → OLD 병렬 입력분배의 단일 메커니즘. NEW = `chunk_distributor`(ADR 0003) 가 대응. **둘 다 Phase3(contract)서 OLD 만 은퇴.**
- **새 병렬 sort 타입 3종**(SORT_GROUP_BY / SORT_ANALYTIC / SORT_ORDER_WITH_LIMIT) + async 2-way queue merge(level-based 제거). 전부 단일 final-output 모델 → #78 마이그레이션 표면에 편입(simplest-first 별도 게이트).
- **결정(유저 2026-06-30)**: #78 producer 이주는 #7173 을 우리 fork 에 먼저 적용 + 최신 develop 머지 + 전 좌표 re-ground 후 착수. plan 좌표(2A-1/2A-3 external_sort.c·px_hash_join·sector)는 re-ground 전까지 provisional. R7(line drift) 은 이 경우 Low 아님 = 선행 통합으로 1회 흡수.
- 재해석(개편 기준): #7173 의 "atomic" = `next_sector_index.fetch_add()` **섹터 work-stealing(런타임 동시성)** 으로, 우리 "원자 전환"(per-list backing OLD→NEW indivisible, `qfile_check_no_mixed_backing` per-list 강제)과 **무관**. 동명이의.

## I-11. robust-parity는 병렬 engage를 trace로 실증해야 한다 + #7173+develop fold 통합검증 (2026-06-30, grill step1) — 측정/방법

> SSOT §6 robust-parity 보강 근거. extends I-2(passthrough-tautology). 통합 브랜치 `wm-integ-7173-develop`(681ebc58d) release 바이너리 측정.

- **방법 결함 발견 (★I-2 확장):** robust-parity "serial==parallel"이 **둘 다 사실상 serial이면 무의미**(trivially equal = passthrough-tautology). 두 함정: (a) `parallelism=1`만 내려도 **#7173 병렬 sort 는 `max_parallel_workers` 로 degree 를 잡아** 여전히 8워커로 병렬 — **serial 강제엔 `parallelism=1` AND `max_parallel_workers=1` 둘 다 필요**(parity.sh 는 둘 다 1/8 로 옳게 설정). (b) `COUNT(*) FROM (SELECT DISTINCT ...)` 식 **aggregate-wrapper 가 내부 연산자를 조용히 serial 화**(옵티마이저). → **robust-parity 는 `;trace on` 의 `parallel workers: N(>1)` 로 병렬 실제 engage 를 *실증*해야 한다** (plan(`;plan detail`)엔 병렬이 안 나옴 — trace 에만 나옴). 미실증 robust-parity = passthrough-tautology.
- **병렬 검증 수단 = SQL trace (코드사실):** `;trace on` → `Trace Statistics` 의 `SCAN ... (parallel workers: 8, ...readrows: 7.46M..7.50M.., gather: ...)`. degree cap = `plan_generation.c:3001-3008`(`cap=PRM_ID_PARALLELISM`, `cap<=1`→`NO_PARALLEL_SCAN`); 단 sort 병렬(#7173)은 `max_parallel_workers` 의존. **test_mode 무관**(parallelism 기본 4, test_mode 게이팅 아님 — system_parameter.c).
- **통합검증 결과 (release, 진짜 serial vs 진짜 parallel):** `bench/harness/queries` 의 확립된 병렬 연산자 쿼리로 측정 —
  - **B_parallel_sort**(parallel sort+groupby, #7173 SORT 경로): parallel=`parallel workers: 8`(gather: mergeable list) / serial(둘 다 1)=workers 0 → **5행 완전 동일**.
  - **A_parallel_hj**(parallel hash join): parallel=`parallel workers: 2/7` / serial=workers 0 → **3행 완전 동일** (#77 크래시 없음 — bounded RAM-resident PHJ).
  - 별도 parallel SCAN+agg(lineitem 60M): `parallel workers: 8`(각 ~7.5M행) COUNT=59986052 SUM=1799465265420123.
  - → #7173+최신 develop fold + connect-free reconcile 가 **병렬 질의 정확성 무회귀**(serial==parallel, 병렬 trace-실증). + unit gate G1–G15 PASS(debug) + compile/link/install(debug+release) green.
- **하니스 보강(권장):** parity.sh 는 둘-다-1/8 은 옳으나 **parallel 런에 `;trace on` + `parallel workers` 단언이 없어** 비병렬 쿼리도 통과 → trace-engagement 가드 추가 필요(I-2 가드의 robust-parity 판).
- 운영 메모: fresh 빌드 PL(Java SP) boot 실패(I-6) → conf `stored_procedure=no` 우회. 서버 lifecycle 은 `/skill:cubrid-server-control` wrapper 필수(raw `cubrid server start` 는 pipe-capture 시 hang).

## I-12. re-ground 코드사실 — 통합 트리 `wm-integ-7173-develop` 681ebc5 (2026-06-30, grill step2) — 코드사실

> #78 plan "Re-ground coordinate map" 의 근거. fork+최신 develop+#7173 통합 트리 측정. 좌표 전체는 plan 참조; 여기엔 구조 사실만.

- **드리프트 패턴:** list_file.c +~307(#7173 sector_page_iterator+307) → `qfile_generate_tuple_into_list(T_SORTKEY)` :3952→**:4259**, append :3013→:3016, connect :3195→:3198. **query_hash_join.c 는 안정**(#7173 미변경) → 2A-3 좌표(use_connect:1898, part_mutexes~:2340, append:1709/1764) 거의 불변. external_sort.c 는 #7173 전면재작성.
- **`sector_page_iterator` 가 query_list.h:860 으로 공통화**(#7173) — sort(external_sort.c:5376/5531 `qfile_open_list_sector_scan`)/hashjoin/pscan 의 **OLD 병렬 입력 단일 메커니즘** = backing-kind entry 가드(SSOT (d))의 OLD-입력 site.
- **결정 A(raw-fd-overflow 분배 드롭) 부분실현 — vestigial 잔재:** `sector_page_iterator` 클래스(구 px_hash_join L238-391)는 @theirs 제거됐으나, raw-fd-overflow 헬퍼(`get_raw_fd_overflow_page`/`get_sector_scan_list_id`/`has_raw_fd_overflow_pages` + `sector_scan_list_ids` 맵, task_manager.cpp:46-120)는 auto-merge 잔존. **읽기경로(`get_raw_fd_overflow_page`) 호출0 = 死** → raw-fd-overflow 분배 미동작(결정 A 기능 실현). 단 `register/unregister_sector_scan_list_id`(px_hash_join.cpp:87/121/146/527/605)가 **unread map** 채움 = vestigial. 무해(정확성 무관), OLD raw-fd 잔재라 2A-3/2A-EXIT sweep 제거.
- **검증:** 위 통합 트리 = build(debug+release)+G1-G15+robust-parity(serial==parallel, 병렬 trace-실증) 통과(I-11). 좌표는 실행 직전 재-grep 권장(R7).

## I-13. Phase2 2A-0 HARD prereq 착지 (2026-06-30, #78) — 구현/측정 사실

> SSOT #75 round-3 (a)–(f) + ADR 0005/0006 + plan 2A-0 구현. "측정/코드사실"이지 "구조 가정" 아님 — 기존 설계 구현(SSOT 미수정). **additive no-op**: 라이브 producer/reader 미배선(실 list 여전히 OLD·tapeset NULL), 가드는 OLD list 에 NO_ERROR → 라이브 쿼리 무영향. 커밋 `43083adf8` (branch `wm-integ-7173-develop`, 미푸시), 10파일 +1334/−79.

- **ADR 0005 (read_page 재진입 + per-reader view) — 코드사실**: `qfile::buffile::read_page` 시그니처 `(thread_p, page_offset, dest, tde_read_scratch*)` + **const**. 멤버 TDE 스크래치 `m_stored`/`m_plain`이 read 경로에서 **제거**(쓰기 staging용 `m_plain`만 잔존), 읽기는 caller `tde_read_scratch`(cipher+plain) → 공유 fd + `pread`(offset-stateless) → N reader 재진입. `pages_read` 비-atomic 증가 제거 → `mutable std::atomic<long> m_reads`. 신규 `tape::read_page_into(thread_p, page_offset, page_dest, tde*)`(memory_tape=RAM 직반환 / buffile_tape=caller dest) + `qfile::tapeset_reader`(per-participant: 자기 page 스크래치 + 자기 `tde_read_scratch`; 공유 mutable = `chunk_distributor` atomic 커서 단 하나). buffile_tape R1 단일reader는 멤버 `m_read_scratch` 보유(degenerate 1-reader).
- **ADR 0006 (overflow-continuation) — 코드사실**: overflow 튜플 = **연속 페이지 run**. start page = count `QFILE_OVERFLOW_TUPLE_COUNT_FLAG(-2)` + `OVERFLOW_PAGE_ID` 필드에 **자기 logical offset**(=start 판별); continuation page = 같은 -2 + `OVERFLOW_PAGE_ID`=first-page offset(< self) + `LAST_TUPLE_OFFSET` 필드(continuation서 free)=run-end. 헬퍼 `qfile_overflow_{set_start,set_continuation,is_overflow_page,first_page,run_end,run_pages}`. R1 `tapeset_scan` overflow 경로 구현(옛 `assert(false)` 스텁 교체): forward(START서 run 재조립+O(1) skip to run_end+1), backward(run_end서 landing→start로 reposition+재조립), jump(saved=start→재조립). R2 `tapeset_reader`: first-page owner가 chunk 경계 넘어 forward 재조립 + `chunk_distributor::skip_to_after(tape_idx, run_end)`(forward-only CAS, 완전포함 continuation chunk만 skip, post-run 페이지 가진 경계 chunk는 claimable 유지) → 거대 run 1회 read.
- **일반화 backing-kind ENTRY 가드 (SSOT (d)/(e)) — 코드사실**: pure `qfile_backing_mechanism_violation(list, mechanism)`(er_set-free, 부트리스 검증용) + production-hard `qfile_backing_guard(...)`(list_file.c, `er_set`+`ER_QPROC_INVALID_XASLNODE`, release 포함) + 매크로 `QFILE_GUARD_{OLD,NEW}_MECHANISM`. 배선: OLD 진입 `qfile_append_list`(:3057 entry)·`qfile_connect_list`(membuf assert 前)·`qfile_open_list_sector_scan`(collect 前) → NEW list 거부; NEW 진입 `qfile_tapeset_scan_open` → OLD list 거부. `combine_two_list` exempt(IR-8). **A~E 카운터** `qfile_ae_{record,old_touch_count,reset}_old_touch`(list_file.c static atomic): OLD 메커니즘이 NEW list 닿으면 +1 → SSOT §6 "A~E NEW-touched-by-OLD == 0".
- **검증 (측정, debug `43083adf8` 재빌드)**:
  - `unit_tests/tapeset` **G1–G18 PASS** (`gate_tapeset_scan.sh` exit 0). 신규: **G16** 가드 판별(clean OLD/NEW 통과 + NEW→OLD & OLD→NEW 위반 포착 + A~E 카운터 0→2→0), **G17** overflow run 재조립 chunk 경계 횡단(R1 forward/backward/jump == {0,1,99,2,3}/역순 + 전바이트 검증; R2 chunk_pages=2, 4 reader: 전 튜플 정확히 1회 + overflow first-page-owner 1회만 재조립), **G18** N=8 reader 동시 file-backed read(전 1000튜플 정확히 1회·무race·scan pgbuf_fixes=0). passthrough-tautology(I-2) 회피: 실제 멀티-Tape/실스레드/실스필 검증.
  - **in-server TDE 동시읽기 (`CUBRID_TAPEREAD_SELFTEST`, SA)**: `TAPEREAD_SELFTEST algo=1 result=0` on **wmloc + wmg003**(둘 다 cipher 로드 → TDE 암호화 백킹) — 40page spill·6 reader 동시 decrypt(per-reader scratch)·240튜플 byte-정확 coverage + pgbuf_fixes=0. 부트리스가 못 하는 TDE 라운드트립 동시성을 in-server 로 실증.
  - **robust-parity serial==parallel (wmloc, debug, parity.sh)**: parallel `;trace on` = **`parallel workers: 8`**(병렬 실증, passthrough-tautology 아님) + `serial_md5==parallel_md5`(=40c47f2e…, group-by COUNT/SUM(CAST NUMERIC38)/MIN/MAX over 997 groups). serial 강제 = parallelism=1 AND max_parallel_workers=1. → 2A-0 additive 변경 라이브 무회귀.
  - 라이브 쿼리 무회귀: wmg003 SA `SELECT count(*) FROM db_class` 정상(debug, assert/crash 없음).
- **방법 메모**: (a) read_page 2-arg 호출자 2곳(buffile_tape::page_at, buffile selftest)만 → 4-arg 전환. (b) 부트리스 COPY 모드는 `tr.tpl` 사전할당(큰 버퍼)으로 `db_private_realloc(NULL,…)` thread-entry abort 회피(run_copy 패턴). (c) backward overflow 테스트는 S_AFTER까지 forward 후 backward(fresh S_BEFORE는 즉시 S_END). (d) 운영: fresh debug PL boot 실패 → `~/CUBRID/conf stored_procedure=no`; wmg003 미등록 → `databases.txt`에 `/home/cubrid/dev/workspace` 경로로 재등록(복원). (e) parity.sh는 `build_x86_64_release/_install` 존재 시 그쪽 CUBRID 선택 → `BUILD_WORKTREE` 더미+`CUBRID=~/CUBRID`+`SERVER_CTL`=래퍼 override로 debug 강제.
- Status: **2A-0 DONE**(커밋 `43083adf8`, 미푸시). 라이브 `chunk_distributor` 배선 전 하드 prereq 충족 → **2A-1 SORT** 진입 가능. 다음 = T_SORTKEY@list_file.c:4259 → tape_writer/freeze, fan-in(external_sort.c:4868 + sort_run_final_single) → tapeset import, 연산자별 원자 전환 + robust-parity(trace-실증) 게이트.

## I-14. Phase2 2A-1 SORT — 데이터플로우 re-ground + 구현 설계 (2026-06-30, #78) — 코드사실/설계

> 2A-0 완료(I-13) 후 2A-1(첫 라이브 producer 이주) 착수 전 grounding. "측정/코드사실"(통합 트리 HEAD)이지 "구조 가정" 아님. SSOT 미변경. 구현은 다음 실행턴(델리킷한 core sort 변경이라 fresh-context로 신중 진행).

- **SORT 데이터플로우 (코드사실, R7 재확인)**:
  - 정렬요청 `qfile_sort_list`→`qfile_sort_list_with_func`(list_file.c:4771): `srlist_id`(출력 list) 생성, `info.output_file=srlist_id`(:4808), `sort_listfile`(:4857) 호출.
  - put-func(정렬튜플 emit, list_file.c ~4276-4348): worker가 `qfile_generate_tuple_into_list(thread_p, sort_info->output_file, T_SORTKEY)`(**:4327**) / `qfile_add_tuple_to_list`(:4277/:4345)로 자기 output_file에 생산.
  - 병렬 fan-in `sort_merge_run_for_parallel`(src/storage/external_sort.c:4868): worker별 output_file을 `qmgr_append_list_to_single_owner`(:4937, connect-free)로 origin(worker0 output_file=:4944 `origin_sort_info_p->output_file`)에 머지.
  - 최종 `srlist_id` 반환 → 호출자(ORDER BY/DISTINCT 등)가 scan(`qfile_open_list_scan`→`qfile_scan_*`); **scan 진입은 1A에서 tapeset_ != NULL 시 tapeset_scan으로 자동 dispatch** → 소비자 무변경.
- **producer page 관리 (코드사실, list_file.c)**: `qfile_generate_tuple_into_list`(:1895)→`qfile_allocate_new_page_if_need`(:1608)→full이면 `qfile_allocate_new_page`(:1512, OLD: `qmgr_get_new_page`+next_vpid+`qfile_set_dirty_page`)→`qfile_save_*`→`qfile_add_tuple_to_list_id`(:1639, tuple_cnt/lasttpl_len/last_offset 갱신). page-full 판정 `qfile_is_last_page_full`(:1483, last_offset 기반). first-tuple 판정 `qfile_is_first_tuple`(:1477, **`VPID_ISNULL(first_vpid)`**). `qfile_close_list`(:1389): 마지막 page next_vpid NULL + `qmgr_free_old_page`. overflow 튜플은 `qfile_add_tuple_to_list`(:1657)서 `qfile_allocate_new_ovf_page`(OLD VPID chain).
- **구현 설계 (NEW-backing producer hook, 연산자별 원자·gated)**:
  1. `QFILE_LIST_ID`에 `producer_writer_`(opaque `qfile::tape_writer*`, NULL=OLD 무변경) + 단일 재사용 scratch page(`producer_page_`). accessor 추가.
  2. **first-tuple 판정 NEW-aware**: `producer_writer_!=NULL`이면 `qfile_is_first_tuple`=`(last_pgptr==NULL)` (first_vpid 건드리지 않음 — 건드리면 `has_old_backing`→mixed). page-full 판정 무변경.
  3. `qfile_allocate_new_page`(NEW branch): 현재 full page(page_p) `tape_writer.append_page` → scratch page memset+헤더init(count=0, last_offset=HEADER_SIZE, overflow null) → `last_pgptr=scratch`, `last_offset=HEADER_SIZE`, page_cnt++. **first_vpid/last_vpid 미설정(NULL 유지)**. qmgr/next_vpid/dirty 미사용.
  4. **overflow NEW branch**: `qfile_add_tuple_to_list` 오버플로 루프가 ADR0006 표현(`qfile_overflow_set_start/continuation` + 연속 append to tape_writer)으로. (overflow 미발생 SORT 키튜플은 단순; 일반튜플 큰 값만 해당.)
  5. `qfile_close_list`(NEW branch): 마지막 `last_pgptr` append → `freeze()` → tape → `srlist_id`의 `tapeset_`에 append + `backing_kind=NEW`(또는 worker별 close 후 fan-in이 import). scratch free, last_pgptr clear.
  6. **fan-in**: `sort_merge_run_for_parallel`서 worker별 frozen tape를 최종 srlist_id의 tapeset에 import(현 `qmgr_append_list_to_single_owner` 머지 대체). serial sort(`sort_run_final_single`)는 단일 tape tapeset.
  7. **atomic-switch 게이트**: SORT 출력만 NEW로 opt-in(flag/조건) — 다른 list 생산 OLD 유지. `qfile_check_no_mixed_backing` + entry guard 라이브 호출.
- **검증 계획**: producer hook은 부트리스 단위테스트 곤란(`qfile_generate`가 thread+tuple_descr 필요) → **in-server selftest**(NEW list_id에 tape_writer 부착→`qfile_generate_tuple_into_list`→close→`tapeset_scan` parity) + 실 SORT robust-parity(serial==parallel, trace `parallel workers:N`, wmloc 경량 + tpch PSORT heavy) + pgbuf_fixes=0 + CoV<=15% + PSORT median<=develop×1.10 + orphan-zero + TDE wmg003.
- **위험/주의**: (a) qfile core(전 list 생산 공유) 수정이라 OLD path 절대 무변경(NEW branch는 `producer_writer_!=NULL`서만) — blast radius 격리. (b) first_vpid 합성 금지(mixed 위반). (c) overflow run NEW 표현은 ADR0006 producer 측 stamping. (d) 병렬 worker output_file 생명주기 + fan-in import 소유권(copy/clear DEPENDENT_MODE) 정확.
- Status: 2A-1 **설계 grounded**(구현 미착수). 다음 = producer hook 구현(gated/additive) → in-server selftest → sort 배선 → activation → heavy robust-parity 게이트 → commit/push/#78/checkpoint G002.

## I-15. Phase2 2A-1a producer hook 착지 + 2A-1b 진입점 (2026-06-30, #78) — 구현/측정 사실

> 2A-1a(producer hook) 착지. SSOT 미변경. 커밋 `7a62d7f60`(push `fc4974dd4..7a62d7f60`, branch wm-integ-7173-develop). 2A-0=`43083adf8`+`fc4974dd4`.

- **2A-1a 착지 (additive/gated, dormant)**: `QFILE_LIST_ID.producer_writer_`(qfile::tape_writer*)+`producer_page_`(scratch) NULL=OLD 무변경. qfile producer hook(`producer_writer_` 설정 시만): `qfile_allocate_new_page`(완성 page→tape_writer append + scratch 재사용, qmgr/VPID 없음), `qfile_close_list`(마지막 append+freeze→single-Tape tapeset+backing_kind=NEW), `qfile_is_first_tuple` NEW-aware(`last_pgptr==NULL`; first_vpid NULL 유지→mixed 아님), `set_dirty` NEW skip, overflow-on-NEW clean-error(ADR0006 producer stamping 후속), `qfile_clear_list_id` aborted producer 정리. 브리지 `qfile_producer_{create,append,freeze_tapeset,destroy}` + `qfile_producer_selftest`(`CUBRID_PRODUCER_SELFTEST`).
- **검증(debug `7a62d7f60`)**: `PRODUCER_SELFTEST algo=1 result=0` on wmg003(TDE, 5000튜플 `qfile_add_tuple_to_list`→NEW page→tape_writer→freeze→tapeset_scan, ids 0..4999, backing_kind=NEW, no-mixed). gate G1-G18 green. robust-parity serial==parallel wmloc(`parallel workers:8`, serial_md5==parallel_md5=40c47f2e…)=OLD 라이브 무회귀. debug build green.
- **운영 gotcha (중요)**: `just build debug`(또는 release)는 `~/CUBRID` 재설치 → **conf의 `stored_procedure=no`가 매 빌드마다 사라짐**. 서버 start(SA selftest 이후 단계 포함 multi-process boot)는 PL boot 실패로 실패. **매 빌드 후 `printf '\nstored_procedure=no\n' >> ~/CUBRID/conf/cubrid.conf` 재적용 필수**(parity.sh/서버 기동 전).
- **2A-1b 진입점 (sort 배선, 코드사실)**: serial 출력 `srlist_id = qfile_open_list(...)`(list_file.c:4864, tfile_vfid 있음=OLD) — NEW로: producer_writer_+scratch 부착 + tfile_vfid 미생성/무해화(NEW면 has_old_backing 금지). put-func가 srlist_id에 생산 → close→freeze→tapeset. **parallel**: worker별 output_file(SORT_PARAM put_arg=sort_info->output_file, external_sort.c 병렬 setup)도 NEW; fan-in `sort_merge_run_for_parallel`(external_sort.c:4868)이 `qmgr_append_list_to_single_owner`(:4937) 대신 worker frozen tape를 srlist_id tapeset로 import. atomic-switch=SORT 출력만 opt-in(flag). 권장 순서: serial-first(단일 output, fan-in 없음) 검증 → parallel(per-worker+fan-in import) → membuf 재활성/tiny-no-spill + no-mixed/guard 라이브 + heavy robust-parity(wmloc+tpch PSORT, trace 실증)+pgbuf_fixes=0+CoV+median+orphan+TDE 게이트 → commit/push/#78/checkpoint G002.
- Status: 2A-1a DONE(`7a62d7f60` pushed). 다음 = 2A-1b sort 배선(serial-first).

## I-16. Phase2 2A-1b SORT 이주 착지 (2026-06-30, #78) — 구현/측정 사실 + ★temp-file 작업 gotcha 대장

> 2A-1b = SORT 연산자(ORDER BY/DISTINCT = `qfile_sort_list_with_func`) producer 이주. 3 커밋 push(branch `wm-integ-7173-develop`): `7e5cb0504`(① overflow stamping) → `1b75074be`(② serial NEW) → `eb5d7e211`(③ parallel NEW fan-in). **env-gated `CUBRID_WM_SORT_NEW`**(기본 OFF=OLD 무변경). SSOT 설계 미변경(기존 설계 구현). "측정/코드사실"이지 "구조 가정" 아님.

- **착지 설계 (코드사실)**:
  - serial: `srlist_id`(qfile_open_list) → `qfile_list_make_new_backed`(빈 tfile_vfid 드롭 `qmgr_free_list_temp_file`+`VFID_SET_NULL(temp_vfid)` → `producer_writer_`+scratch 부착). **atomic 순서**: producer 먼저 생성 성공 후에만 tfile 드롭 → OOM 시 list는 완전 OLD 유지(half-converted 없음). gated `do_close && qfile_sort_new_backing_enabled()`. tde_encrypted는 드롭 前 캡처해 sort_listfile에 전달.
  - parallel: 각 worker가 in-order 구간을 자기 NEW list(tape_writer)에 쓰고 `qfile_close_list`(freeze) → fan-in `sort_merge_run_for_parallel`가 worker frozen Tape를 origin Tapeset로 **worker 순서 import**(`qfile_tapeset_import`, 소유권 이전+count 누적) = `sort_split_last_run`이 merged run을 순서 분할하므로 Tapeset 순차연결 = globally sorted. `qmgr_append_list_to_single_owner` 대체, frozen NEW origin은 `qfile_reopen_list_as_append_mode` skip.
  - 워커/origin 일치: `SORT_PARAM.px_output_is_new`(워커 실행 前 sort_listfile서 origin의 `producer_writer_`로 **안정 캡처**) → 워커 전환을 origin과 일치. `sort_check_parallelism`서 2A-1b serial-first 강제 제거(NEW 병렬 허용).

- **★삽질 방지 코드사실 (future temp-file 작업자 필독)**:
  - **(a) 생산중 NEW 판별 = `producer_writer_ != NULL`, NOT `tapeset_`/`qfile_list_has_new_backing`.** `tapeset_`는 freeze(close) 後에만 set → 생산중 NEW list는 `producer_writer_`만 set. dispatch/force-serial을 `tapeset_`로 판별하면 미발동 → 병렬 fan-in이 NEW origin을 OLD로 오인해 `qmgr_append_list_to_single_owner` 크래시(실측 core: sort_merge_run_for_parallel).
  - **(b) `sort_check_parallelism`이 worker_manager를 예약(db_private_alloc @px_worker_manager.cpp:62, degree>1).** serial 강제는 **예약 前**(sort_check_parallelism 내부 return 1)에 해야 함. 예약 後(sort_listfile)서 px_parallel_num=1로 강제하면 serial 분기가 그 worker_manager를 미해제 → **alloc resource_tracker leak assert**(request teardown). 실측 core: `resource_tracker<void const*>::pop_track`(thread_entry.cpp:422 m_alloc_tracker).
  - **(c) resource_tracker(alloc/pgbuf) 누수/혼합/크래시는 CS(server) 모드 per-request에서만 검출**(`net_server_request`→`pop_resource_tracks`). **SA(`csql -S`) selftest·bootless unit test는 per-request tracking 미실행 → 누수 못 잡음.** ⇒ producer/scan 라이브 검증은 반드시 **CS 모드 서버 debug 쿼리**로(selftest+unit만으론 불충분; `PRODUCER_SELFTEST` PASS인데 라이브 DISTINCT가 alloc leak으로 서버 크래시한 사례 — (b)).
  - **(d) parity.sh `result_rows` md5 오염**: awk가 subquery-aggregate 쿼리에서 `;trace on`/`;plan detail` 라인을 결과행으로 포착 → serial/parallel md5가 **timing/`parallel workers:` 차이로 불일치**(데이터행은 동일). **robust-parity 판정은 순수 집계 데이터행(COUNT/SUM/MIN/MAX) 비교**로(trace/plan 제외; `grep -E '^[[:space:]]+[0-9]+([[:space:]]+[0-9]+){2,}'`). group-by 쿼리(다수 결과행, trace가 "N rows selected" 뒤)는 우연 회피. **2A-2/2A-3 operator 게이트도 동일 주의 — raw result md5 신뢰 금지(SSOT §6 "md5 금지"의 실무판).**
  - **(e) do_close=false 정렬은 NEW 전환 금지.** `qfile_sort_list(...,false)` 호출자 = `query_aggregate.cpp:1378`, `query_analytic.cpp:797`(aggregate/analytic 내부 정렬). open producer를 MOVE하면 leak/lost(`qfile_copy_list_id`가 producer_writer_/producer_page 미처리 → 닫지 않은 producer는 MOVE 금지). origin OLD 유지 + 워커도 OLD(px_output_is_new로 일치). 이들은 2A-1b 이주 대상 아님(별도/후속).
  - **(f) ORDER BY optimizer-drop**: `count(*) FROM (SELECT a FROM t ORDER BY a)`는 옵티마이저가 inner ORDER BY 제거(aggregate 순서무관) → 정렬 미발생(`WM_SORT_NEW` 로그 0). SORT operator 검증/게이트엔 **DISTINCT**(dedup 제거불가) 또는 순서-민감 consumer(ROWNUM/LAG) 사용.
  - **(g) `just build`가 conf 전체 재설치** → `stored_procedure=no` 뿐 아니라 `parallelism`/`max_parallel_workers`/`work_mem`/`data_buffer_size`도 소실. 빌드 후 매번 전부 재적용(I-15 (g)는 stored_procedure만 언급했음 — 보강).
  - **(h) `qfile_list_make_new_backed`의 unique BufFile seq**: `qfile_producer_create_for_list`가 process-global `std::atomic` seq(base `0x100000000`, selftest 고정 seq 90000번대와 분리)로 부여 — O_EXCL 충돌 회피. 동시 정렬/워커 다수 안전.

- **검증(debug, HEAD eb5d7e211)**: gate **G1-G18 green** · `PRODUCER_SELFTEST algo=1`(wmg003 TDE: 5000튜플 + 60튜플 small/3-page-overflow 혼합 **byte-exact** 재조립) · env-on wmloc heavy DISTINCT(4.19M, **spill**, parallelism=8): serial vs parallel robust 집계 **완전동일**(4194304/8796090925056/0/4194303) + `WM_SORT_NEW` 로그 **8개**(origin+워커7=병렬 NEW 실증) + `parallel workers:8` + no assert/crash + resource tracker clean · env-off group-by parity serial==parallel `40c47f2e`(OLD 병렬 무회귀).

- **heavy tpch (release, env-on) 검증 추가**: tpch_sf10 `count/sum/min/max FROM (SELECT /*+ PARALLEL(8) */ DISTINCT o_orderkey FROM orders)`(15M distinct, heavy spill) — serial(28.7s) vs parallel(14.2s, **2× speedup**) robust 집계 **완전동일**(15000000/449999872500000/1/60000000), no crash/leak, 서버 env에 `CUBRID_WM_SORT_NEW=1` 전파 확인(do_close+toggle→NEW 전환은 결정적). 주의: **release 빌드는 `er_log_debug`(WM_SORT_NEW)가 no-op** → release 로그로 NEW 실증 불가(NEW 판별은 debug 빌드 WM_SORT_NEW 로그 또는 env+gate 결정성으로).
- **남은 2A-1b 게이트(미완)**: **precise median <= develop×1.10** = develop 바이너리 + 동일 baseline 쿼리 3-run 측정(별도 perf 작업; NEW는 #62 오버헤드 제거로 develop 이하 기대, release parallel 14.2s indicative). + **기본 ON 전환**(2A-EXIT 글로벌 활성화 권장). pgbuf_fixes=0·membuf/tiny·orphan·TDE·CoV(N/A)는 by-construction/selftest 커버.
- Status: 2A-1b CORE(overflow+serial+parallel SORT NEW) **DONE+검증(env-gated)**; heavy tpch correctness PASS(release 15M). HEAD=`eb5d7e211`. 잔여=precise median(perf) → 기본 ON → 2A-2(parallel-scan pre-agg). **차후 구현은 executor subagent에 bounded 위임(유저 지시); 리더=설계/통합/검증/거버넌스.**

---

## I-17 — 2A-1b PERF median 게이트 + **회귀 출처 진단 (2026-06-30, release)**

**측정(공정성 확인)**: DB=tpch_sf10, 쿼리=`SELECT count(*),sum(cast(o_orderkey as numeric(38,0))),min,max FROM (SELECT /*+ PARALLEL(n) */ DISTINCT o_orderkey FROM orders) z;`(15M distinct, heavy spill). 결과행 모든 빌드 **완전동일** `15000000/449999872500000/1/60000000`.
- config 동일: data_buffer_size=512M, parallelism=8, max_parallel_workers=8, stored_procedure=no.
- **sort 메모리 공정성**: develop `sort_buffer_size=8M` vs redesign `work_mem=8M` (재설계가 `sort_buffer_size` 키워드 제거→`work_mem` rename; sort_buffer_size 입력시 "Unrecognized keyword"). paramdump effective 8.0M 양쪽 확인. conf 중복 work_mem=2M/8M는 8M로 정리 후 측정.

| build / path | serial(PARALLEL 1) | parallel(PARALLEL 8) median |
|---|---|---|
| **develop** (CUBRID-develop-69e73b47) | 9.93s | **4.30s** (4.197/4.305/4.602) |
| redesign **OLD** (eb5d7e211 env-OFF) | 16.91s | **15.91s** (15.107/15.913/16.626) |
| redesign **NEW** (eb5d7e211 env-ON=2A-1b) | 16.9–19.4s | **~14.07s** (16.334/14.072/13.390) |

### 진단 (이전 결론 **정정**)
1. **회귀는 2A-1b(NEW 백킹)가 원인이 아니다.** redesign 트리는 NEW를 **꺼도(env-off)** develop 대비 parallel ~3.7×(15.91 vs 4.30) 느림 → 회귀는 **redesign 트리 전반(tree-wide)**.
2. **2A-1b NEW는 오히려 redesign-OLD보다 ~11% 빠름**(14.07 vs 15.91). 2A-1b는 회귀 무추가 + 미세 개선.
3. **이전 세션 "heavy gate PASS"(I-16/#78)는 serial==parallel parity(정합성)만 확인** — develop 대비 perf 비교 아님. perf 게이트는 통과한 적 없고, 진짜 ~3.7× 회귀는 2A-1b 이전부터 redesign 트리에 존재.

### 미해결 confound (차기 세션 우선 검증)
- **빌드 타입**: redesign `release` preset = **RelWithDebInfo**. develop-69e73b47 최적화 수준 미확인(libcubrid.so 심볼릭링크라 file 비교 불발). develop이 full Release(-O3/no-assert)면 3.7× 중 일부는 빌드 플래그 차이일 수 있음 → **동일 preset로 양쪽 재빌드 후 재측정**. (단 env-off≈env-on은 동일 빌드라 build-type 독립 → "2A-1b가 원인 아님"은 확정.)
- **가설(user)**: 정합성 완벽 + 느림 = redesign 경로에 **불필요한 오버헤드/과정**(§0 P-history의 per-tuple lock / double-spill / membuf-connect 잔재 의심). VTune hotspot으로 특정.

---

## I-18 — 2A-2 scan-producer NEW 이주 + VTune root-cause 확정 + 잔여 병렬성 갭 (2026-06-30)

### (a) confound 제거 [확정] — I-17 미해결 confound 해소
develop-69e73b47과 redesign install **둘 다 `build_preset_release` = RelWithDebInfo (`-O2 -g -DNDEBUG`)**, 동일 ccache GCC 8.5.0, 동일 WITH_*/ENABLE_*, NDEBUG(assert off). CMakeCache 직접 대조 + DWARF producer 확인. → **3.7× 회귀는 빌드 플래그 아님, 구조적/알고리즘적.**

### (b) VTune root-cause [확정] — 커널+유저 EBS + threading (driverless perf, kptr_restrict=0)
- 회귀 = **병렬성 붕괴**: develop 평균 4.16코어(4.3s) vs redesign 0.87코어(15.9s). CPU 작업량은 비슷, 코어 활용 1/5 = off-CPU wait.
- 병목 wait 스택(redesign-OLD/NEW 공통, 117s/3.4M회): `rawfd_find_and_mark_dirty(per-page mutex) ← rawfd_flush_page ← qmgr_set_dirty_page ← qfile_set_dirty_page ← qfile_generate_tuple_into_list ← parallel_scan::result_handler::write`. = §0 P2 "전역 레지스트리 per-page dirty-mark 락"의 라이브 실증.
- 근본원인: raw-fd 페이지 버퍼=naked `malloc`(identity 없음) → PAGE_PTR로 flush/release하려고 **서버 전역 `unordered_map<PAGE_PTR,…>`** lookup(mutex). 호출자는 tfile을 이미 넘기는데 `rawfd_flush_page`가 `(void)tfile_p`로 버리고 전역맵 재조회. 즉 락=opaque-PAGE_PTR 호환계층의 산물(per-worker 단일쓰기엔 불필요).

### (c) 2A-2 구현/검증/측정 [DONE, commit `3fd601626` push@xmilex]
- 병렬 SCAN MERGEABLE_LIST per-worker 출력을 NEW per-worker Tapeset로 이주(게이트 `CUBRID_WM_SCAN_NEW`, 기본 OFF). merge=zero-copy `qfile_tapeset_import`로 NEW dest. 병렬 SORT 입력 reader=sector→`chunk_distributor`+`tapeset_reader`(executor 위임 구현). gate qfile_scan_new_backing_enabled.
- correctness: release tpch_sf10 15M DISTINCT, SCAN_NEW=1 (±SORT_NEW): 병렬(8) robust 집계 == serial (15000000/449999872500000/1/60000000), no crash/leak.
- perf(병렬 median): redesign-OLD 15.9s → **2A-2 ~10.6s (~1.5×)**. 락이 hotspot/threading에서 **소멸**(top self-CPU=정상 sort/scan 작업, threading 잔여 wait=전부 idle infra).

### (d) ★삽질 방지 (gotcha): sort 입력 reader는 COPY(peek=0) 필수
`tapeset_reader::next(...,PEEK)`는 `tuple_record.tpl`을 **borrowed page 포인터**(reader의 m_page)로 세팅(qfile_tape.cpp emit_in_page:819, 무할당). sort worker cleanup(external_sort.c:1739)이 `db_private_free(state->tplrec.tpl)` → **borrowed 포인터 free → heap corruption → 서버 크래시**. COPY(peek=0)일 때만 emit_in_page/reassemble가 `db_private_realloc`로 소유(826/845) → free 유효 + overflow 재조립 처리. (release는 NDEBUG라 silent SIGSEGV·0-byte coredump → gdb attach batch로 스택 확보가 정석.)

### (e) 잔여 병렬성 갭 [미해소, 별도 조사] — 2A-2 범위 밖
2A-2 후에도 병렬 DISTINCT가 **여전히 ~0.95코어(single-threaded)**로 돈다(develop 4.16). threading=쿼리경로 contention 0(전부 idle infra wait). 즉 락 제거로 **단일스레드 작업량은 줄었지만(→10.6s) 병렬성은 회복 안 됨** = redesign 트리가 이 쿼리를 본질적으로 single-thread로 실행하는 **tree-wide 병렬성 갭**(sort/dedup/aggregate 단계 or merge 경로). 락은 그 single-thread 비용의 일부였을 뿐. 차기: 병렬 SORT/aggregate 단계가 왜 다워커로 안 펴지는지(trace `parallel workers`) 조사.

### (f) ★정정 (I-18 (c)/(e) supersede) — 깨끗한 warm 측정: 회귀 사실상 해소
I-18 (c)의 10.6s와 (e)의 "tree-wide single-thread 갭" 결론은 **confounded 측정**(cold-cache + 직전 비교 run의 config-load 오류 + PATH 오염으로 develop csql이 redesign conf 로드)에 기반한 오판이었음. **동일 clean protocol(env -i 격리, warmup 2 + median 5, 동일 config)** 재측정:
| build | 병렬(8) wall warm | vs develop |
|---|---|---|
| develop-69e73b47 | **3.72s** | 1.0× |
| redesign-OLD (env-OFF) | **9.2s** | 2.47× |
| **redesign-2A-2 (SCAN+SORT NEW)** | **4.42s** | **1.19×** |
모두 정합성 15000000 무결. → **2A-2가 perf 회귀를 2.5×(warm)→1.19×로 해소**(거의 develop 수준). VTune 0.95코어는 I/O-bound(workers가 디스크 wait, low CPU util)+프로파일 윈도의 idle 포함 산물이지 single-thread 아님 — 트레이스가 scan·ORDERBY **각각 parallel workers:8** 실증.
**잔여 ~19% 정체(trace로 특정)**: 바깥 `count(*)` 집계의 temp 스캔이 **develop=parallel 5워커(buildvalue, 133ms)** vs **redesign=serial(1060ms)**. 원인: 그 outer 집계 스캔(BUILDVALUE_OPT)이 NEW inner-result(Tapeset)를 sector-scan으로 못 읽어 serial fallback — 2A-2가 scope-out한 동일 sector→chunk 커플링. 후속(outer aggregate 스캔도 chunk 전환)으로 대부분 닫힐 전망(develop 패리티). gate 기본 ON은 2A-EXIT 전역 결정.

### (g) 잔여 ~19% 정체 확정: 바깥 집계 serial은 **redesign-wide·NEW와 무관** — 2A-2b revert
trace로 단계별 분해(동일 config):
| phase | redesign-OLD(env-OFF) | redesign-2A-2(NEW) | develop |
|---|---|---|---|
| inner heap SCAN | 4114ms (락-contended, worker 708..3352 편차) | **726ms** (락-free, 692..726 균일) | ~1100ms |
| outer count(*) | **serial 925ms** | **serial 1029ms** | **parallel-5(buildvalue) 133ms** |
- **2A-2가 고친 것 = inner 스캔 락**(4114→726ms, worker 시간 균일화 = 레지스트리 락 contention 소멸 실증). 이게 회귀의 본체(2.5×→1.19×).
- **잔여 갭 = 바깥 `count(*)`(uncorrelated subquery)가 redesign에서 serial**(~925-1029ms) vs develop parallel-5(133ms). **env-OFF(순수 OLD)에서도 serial** → NEW backing/temp-workmem 생산자 이주와 **무관한 pre-existing redesign-wide 차이**(병렬 BUILDVALUE_OPT 집계가 redesign 트리에서 안 켜짐; #7173/optimizer 계열 의심). #78 producer 이주로는 안 고쳐짐.
- ⇒ **2A-2b(px_scan LIST 입력 chunk 전환)는 잘못된 타깃**(바깥 serial은 NEW-입력 커플링이 아니라 집계 병렬화 미발동)이라 **revert**(uncommitted, 트리는 2A-2 `3fd601626` 유지). 잔여 갭은 별도 이슈(redesign 병렬 외부집계)로 분리 조사 대상.

### (h) ★잔여 ~19% root cause 정밀 확정: px_scan.cpp:868 BUILDVALUE_OPT 병렬 list-scan scope-limit
플랜은 develop·redesign **동일**(`sscan class:z` outer). 차이는 실행: inner heap scan은 양쪽 parallel-8(MERGEABLE_LIST), **outer `count(*)` list scan만 redesign에서 serial**. 게이트 코드:
```
// src/query/parallel/px_scan/px_scan.cpp:868 (scan_open_parallel_list_scan)
if (temp_page_store::raw_fd_master_enabled () && !ACCESS_SPEC_IS_FLAGED (spec, ACCESS_SPEC_FLAG_MERGEABLE_LIST))
  return NO_ERROR;   // serial fallback
```
- raw-fd master(=redesign 백킹) ON + spec가 **MERGEABLE_LIST 아님**이면 병렬 list scan 차단. outer count는 **BUILDVALUE_OPT**(MERGEABLE_LIST 아님) → serial. inner heap은 MERGEABLE_LIST → 통과(parallel-8).
- 출처: commit **`9f8c78a3c` [temp-workmem P5-hashagg]** ("remove parallel-hash-GBY scope-limit; guard FALSE") — 병렬 hash-GBY는 열되 **BUILDVALUE_OPT/XASL_SNAPSHOT 병렬 list scan은 raw-fd에서 scope-limit(serial)**로 남김. develop엔 이 게이트 없음 → outer parallel-5.
- ⇒ 잔여 갭 = 이 scope-limit. **닫으려면 BUILDVALUE_OPT(외부 집계) 병렬 list scan을 redesign 백킹 위에서 재활성**: (1) 게이트 완화(BUILDVALUE_OPT 허용) + (2) 그 입력 list scan이 raw-fd OLD(sector; inner heap과 동일 경로라 동작 가능성 높음) **및** NEW(SORT_NEW일 때 inner 결과가 NEW Tapeset → chunk 입력 필요, 앞서 revert한 2A-2b류)를 모두 처리 + 정합성 검증. **별도 슬라이스**(temp-workmem producer 이주 #78 범위 밖, P5-hashagg scope-limit 해제 성격).

### (i) 2A-2c: BUILDVALUE_OPT 병렬 list scan 재활성 → develop 패리티 달성 (commit `c94ae5081`)
(h)의 게이트(px_scan.cpp:868)를 완화: `raw_fd_master_enabled()`가 **MERGEABLE_LIST도 BUILDVALUE_OPT도 아닌** spec만 차단. BUILDVALUE_OPT는 MERGEABLE_LIST와 동일한 OLD sector 입력경로(input_handler_list/sector_page_iterator)로 병렬 진입. NEW(Tapeset) 입력은 `qfile_list_has_new_backing` 가드로 serial 유지(NEW 병렬 list 입력=후속). XASL_SNAPSHOT 무변경.
- 검증(release, tpch_sf10): env-OFF 기본 + SCAN_NEW=1(inner-OLD) 모두 외부 count temp SCAN **parallel workers:5** + 15000000 ×4 정확 + no crash. 
- **승리 config = SCAN_NEW=1 + SORT_NEW=0 + 2A-2c**: inner scan 락-free(NEW 워커) + inner 결과 OLD → 외부 count parallel-5. **~3.99s vs develop ~3.72s = ~1.07× → develop×1.10 게이트 통과.**
- perf 진행: redesign-OLD 9.2s(2.47×) → 2A-2(SCAN+SORT NEW) 4.42s(1.19×) → **2A-2c(SCAN_NEW + gate relax, SORT_NEW=0) 3.99s(1.07×)**. heavy-spill 회귀 **이 워크로드에서 develop 패리티로 해소**.
- ⚠️ SORT_NEW=1은 이 쿼리를 오히려 느리게(inner 결과 NEW → 외부 count serial guard → 4.7s). 즉 SORT_NEW=1 + 외부집계 병렬을 동시에 얻으려면 **NEW 입력 병렬 list scan(chunk_distributor/tapeset_reader)** 이 필요 = 후속(이전 revert한 2A-2b를 제대로). 그 전엔 이 워크로드 최적은 SCAN_NEW=1·SORT_NEW=0.
- ⚠️ 2A-2c는 **기본(env-OFF) 동작 변경**(외부 스칼라집계가 raw-fd에서 병렬화) — full-suite 검증 권장(P5-hashagg scope-limit가 BUILDVALUE_OPT를 막아둔 다른 이유가 없는지). count 외 sum/min/max 등 BUILDVALUE_OPT 광범위 테스트 필요.

### (j) 2A-2d: NEW Tapeset 입력 병렬 list scan(overflow-safe) → 완전 develop 패리티 (commit `15fe7c549`)
2A-2c의 NEW-serial 가드를 제거하고 NEW 입력 병렬 list scan 구현 → SORT_NEW=1(락-free 정렬, inner 결과 NEW)에서도 외부집계 병렬.
- input_handler_list NEW 분기: 공유 chunk_distributor(input Tapeset) + per-worker reader/스크래치 + `tape::read_page_into`. out_tfile=NULL(pgbuf/qmgr 비경유), slot_iterator release는 tfile NULL이면 qmgr_free skip(borrowed/스크래치).
- **overflow 안전**: NEW overflow 튜플(ADR0006 cross-page run)은 한 self-contained 페이지로 못 담음 → **`QFILE_LIST_ID_NEW_CONTAINS_OVERFLOW` 플래그 false일 때만 병렬**. 플래그는 `qfile_producer_add_overflow_tuple`이 set, `qfile_tapeset_import`가 fan-in dest로 전파. overflow 포함 NEW list는 serial 유지 + NEW page reader가 overflow page 만나면 **방어적 에러**(silent wrong-result 금지).
- 검증(release tpch_sf10): **SCAN_NEW=1+SORT_NEW=1 → 외부 count temp SCAN parallel workers:5, 15000000 정확, ~3.65s vs develop ~3.72s = ~0.98× (패리티/약간 우위)**. SORT_NEW=0 경로 무회귀(parallel-5 정확). debug `test_tapeset_scan` PASS.
- **perf 진행 최종: 9.2s(2.47×) → 4.42s(1.19×, 2A-2) → 3.99s(1.07×, 2A-2c) → 3.65s(0.98×, 2A-2d).** heavy-spill 회귀 **develop 패리티로 완전 해소**(SCAN_NEW=1+SORT_NEW=1 = 락-free scan+sort + 외부집계 병렬).
- 미완(차후): overflow 포함 NEW list의 병렬 입력(현재 serial fallback) = tuple-level reassembly 어댑터 필요. 2A-2c/2A-2d는 기본 동작 변경 포함 → **full-suite(ctest/CTP) 검증 권장**(BUILDVALUE_OPT 광범위 + overflow 라이브). gate 기본 ON은 2A-EXIT.

### (k) 2A-2e: NEW 입력 overflow도 병렬 (first-page-owner, tuple-level reader) — serial fallback 제거 (commit `7559d1445`)
유저 원칙("overflow head를 가져간 worker가 run 처리, continuation skip" = ADR0006 first-page-owner). 2A-2d의 page-level read_page_into + overflow serial fallback을 **tuple-level `qfile::tapeset_reader`**로 교체: NEW 입력 워커가 공유 chunk_distributor에서 reader로 `next(...,COPY)` 튜플을 받음. reader가 이미 first-page-owner overflow(reassemble + skip_to_after) 구현 → overflow 포함 NEW list도 병렬. slot_iterator_list에 NEW tuple-source 분기(pred/fetch/trace/tplrecp 로직 보존, m_tplrec db_private 소유). OLD page-walk(+qfile_assemble_overflow_tuple) 무변경.
- 검증(release): SCAN_NEW=1+SORT_NEW=1 tpch 15M count-distinct → 외부 parallel workers:5, 15000000, ~3.60s(~0.97×); SORT_NEW=0 무회귀(parallel-5); **wmloc 4.19M both-NEW golden-exact**(4194304/8796090925056/0/4194303). [정정: debug 셀프테스트 정확한 이름/결과 및 라이브 overflow 병렬 gdb 확인은 아래 (k') 참조 — 이전의 "test_tapeset_scan G1-G18/G17/G18" 표기는 부정확했음.]
- **2A-2 시리즈 완결**: 9.2s(2.47×)→4.42s(1.19× 2A-2)→3.99s(1.07× 2A-2c)→3.65s(0.98× 2A-2d)→3.60s(~0.97× 2A-2e, overflow 포함 병렬). heavy-spill 회귀 develop 패리티 해소 + 외부집계/overflow 병렬까지.
- 차후(미완): full-suite(ctest/CTP) 검증(2A-2c/d/e 기본동작 변경 + BUILDVALUE_OPT 광범위 + overflow 라이브) → gate 기본 ON(2A-EXIT). 커밋 5개(3fd601626/c94ae5081/15fe7c549/7559d1445 + 2A-1b들) push@xmilex.

### (k') 2A-2e 검증 정정·보강 — 실제 셀프테스트 + 라이브 overflow 병렬 (gdb 확인)
**정정**: (k) 및 commit `7559d1445`/이전 #78 코멘트의 "test_tapeset_scan G1-G18 / G17" 라벨은 코드에 존재하지 않는 부정확한 표기였음. 실제 디버그 셀프테스트는 아래 둘.
- **`TAPEREAD_SELFTEST`** (`qfile_taperead_selftest`, qfile_tape.cpp:1371): 40p spilled Tape, **N=6 동시 스레드**가 각자 `tapeset_reader`로 공유 `chunk_distributor` 위 읽기 → merged ids == 0..239(중복/유실 0) + `pgbuf_fixes==0`. = 2A-2e reader+동시성+chunk분배 경로.
- **`PRODUCER_SELFTEST`** (`qfile_producer_selftest`, qfile_tape.cpp:1735): 5000튜플 roundtrip + `qfile_producer_overflow_roundtrip`(60튜플, 매 7번째 3페이지 BIG=2*MAX+100) cross-page 재조립 byte 검증.
- fresh 2A-2e **debug** 빌드(/home/cubrid/debug/CUBRID-11.5.develop)서 둘 다 `result=0(PASS)`, **algo=1(TDE 암호화)**. (HELDTAPE/BUFFILE도 0.)
- 실행: `env -i ... CUBRID_PRODUCER_SELFTEST=1 CUBRID_TAPEREAD_SELFTEST=1 csql -S -u dba demodb -c "SELECT 1;"` → stderr `*_SELFTEST result=0`.

**보강(핵심)**: 기존 tpch/wmloc 측정은 small 고정폭 컬럼이라 overflow 튜플이 0개 → 2A-2e가 실제 enable한 "NEW 입력 overflow 병렬"이 한 번도 안 탔음. 그래서 wide-tuple 라이브 검증 추가:
- tpch_sf10에 임시 `wt_ovf(g BIGINT, payload VARCHAR(40000))`, 10000 **유일** payload × 17012B(=QFILE_MAX_TUPLE_SIZE_IN_PAGE 초과 → 2페이지 overflow run), ~170MB. (검증 후 DROP, 측정용 thresholds 원복 2048.)
- `parallel_scan_page_threshold=8`로 외부 스캔 강제 병렬 → trace **외부 temp SCAN parallel workers:5**(gather buildvalue), ORDERBY parallel 8.
- `SELECT count(*),SUM(SUBSTR..),SUM(CHAR_LENGTH) FROM (SELECT /*+PARALLEL(8)*/ DISTINCT payload ...)` SCAN_NEW=1+SORT_NEW=1 → **10000 / 199915000 / 170120000**(=10000×17012, overflow 튜플 full-length 무손실), serial 기준 동일, ×3 안정.
- **gdb 결정적**(debug, Rel 아님): `px_scan_slot_iterator_list.cpp:146`(=`if(m_new_tuple_source)` NEW reader 분기 내부) bp가 위 쿼리 중 **HIT** → 2A-2e NEW `tapeset_reader` 경로 실제 실행 입증(OLD raw-fd 2A-2c 경로가 아님 확정). 분기 선택=`input_handler_list::init_on_main`의 `qfile_list_has_new_backing(list_id)`(px_scan_input_handler_list.cpp:63), worker별 reader=`initialize`(:117-124), tuple drain=`slot_iterator_list::next_qualified_slot_with_peek`(:144-165, COPY=peek0).

### (l) full-suite (a) 검증 — 회귀 2건 + 2A-2f 정합성 수정 + 0.97× 패리티 재평가
유저 지시 full-suite. ctest는 build_preset에 `tapeset_scan` 1개뿐(PASS). 실질 커버리지 = serial==parallel robust-parity 스윕(HASHJOIN/GROUPBY/DISTINCT/ORDERAGG × count/sum/min/max, tpch_sf10, mpw 8 vs 1, env-OFF). → **정합성 버그 2건 발견.**

**버그1 (2A-2c 회귀, commit `c94ae5081`) → 2A-2f로 수정 (commit `3711786dd`)**: `count(*) FROM (SELECT l_orderkey,count(*) FROM lineitem GROUP BY l_orderkey)` → develop 병렬 15000000(정답)·redesign serial 15000000·**redesign mpw=8+2A-2c = 349006(틀림, 안정)**. trace: GROUPBY 15M 생산, 외부 parallel BUILDVALUE temp SCAN 349006만 읽음. 근본: OLD `sector_page_iterator` 병렬 리더가 MERGEABLE_LIST엔 정확하나 임의 파생테이블 리스트 행유실; 2A-2c가 모든 외부집계에 default로 노출(2A-2c는 DISTINCT로만 검증). 수정=병렬 BUILDVALUE를 NEW 입력 한정(px_scan.cpp:868~ `!(is_buildvalue_opt && is_new_backing)`); OLD/raw-fd→serial. GROUPBY 15000000 안정 x3.

**0.97× 패리티 재평가(중요)**: DISTINCT/sort/groupby **출력은 아직 OLD-backed**(출력 이주 미완). 앞서(k/k') 보고한 SCAN_NEW=1+SORT_NEW=1 DISTINCT ~3.60s(0.97×)는 **2A-2c의 buggy OLD-sector 병렬경로가 외부 count를 병렬화**해서 나온 수치였음. 2A-2f로 그 경로를 serial화하니 같은 쿼리 **~10.6s(≈2.9×)**. ⇒ 그 0.97× 패리티는 정합성 깨진 토대 위였음. 복구엔 (B-i) OLD sector 리더 행유실 근본수정 OR (B-ii) 집계/정렬 출력 NEW 이주 필요. (NEW overflow 라이브(k')는 여전히 유효—그건 NEW reader 경로 자체 검증.)

**버그2 (pre-existing, 내 변경 아님)**: 병렬 HASH JOIN 비결정성 — `count(*) FROM orders o,lineitem l WHERE o.o_orderkey=l.l_orderkey AND o.o_orderkey<200000` → develop 200360 안정, **redesign 병렬 149510/200360 깜빡임**(레이스), serial 정상. query_hash_join.c/px_hash_join 실행부 2A-2 미변경 = 미이주 PHJ(#77) = **2A-3 해소 대상**. PM-2(R2 concurrent reader race) 부류.

**조치**: 2A-2f push(`3711786dd`). 정합성: GROUPBY 수정 / parallel PHJ는 2A-3 대기. perf 복구 방안(B-i vs B-ii) + 2A-3 착수 순서 = 유저 결정 대기.

### (m) B-ii grounding — parallel-sort 출력 NEW화는 부분배선됨; DISTINCT가 serial인 진짜 원인 = 2 가설 (다음 세션 gdb 1회로 확정)
perf 복구(B-ii) 코드 추적 완료. 핵심: **parallel ORDER_BY 출력 NEW화는 이미 배선되어 있음** — 따라서 B-ii는 "새로 짜기"가 아니라 "왜 DISTINCT가 안 닿나" 1버그.
- DISTINCT 경로: `qexec_orderby_distinct`→`qexec_orderby_distinct_by_sorting`(query_executor.c:4094)→`qfile_sort_list_with_func`(query_executor.c:4280, **do_close=true**, parallelism 전달).
- 출력 NEW화 게이트: `qfile_sort_list_with_func` list_file.c:**5204** `if (do_close && qfile_sort_new_backing_enabled() && qfile_list_make_new_backed(...))` → srlist_id를 NEW로.
- `px_output_is_new`: external_sort.c:**1498-1500** = (parallel_type ORDER_BY/ORDER_WITH_LIMIT) && output_file에 PRODUCER_WRITER 존재.
- worker 출력 NEW화: external_sort.c:**5338-5341** (`qfile_list_make_new_backed`). 병렬 fan-in NEW import: external_sort.c:**4934-4958** (`qfile_tapeset_import`, **이미 배선됨**).
- **모순/미해결**: do_close=true인데도 SCAN_NEW=1+SORT_NEW=1 DISTINCT(15M)의 외부 buildvalue SCAN이 2A-2f 후 **serial(10.6s)**. 2가설:
  - **H1**: 파생테이블 DISTINCT 출력이 실제로 NEW가 안 됨(make_new_backed 스킵/parallel_type 불일치) → is_new_backing=false → 2A-2f가 serial화.
  - **H2(유력)**: 출력은 NEW지만 **NEW tapeset의 page_cnt 과소보고** → `compute_parallel_degree(SCAN, list_id->page_cnt)` < 2048(default `parallel_scan_page_threshold`) → serial. 근거: (k') wide-overflow NEW list(170MB)가 threshold=2048선 serial, **threshold=8로 낮춰야 병렬**이었음 = NEW page_cnt가 실데이터보다 훨씬 작게 잡힘.
- **다음 세션 첫 스텝**: debug 서버 + gdb로 SCAN_NEW=1+SORT_NEW=1 DISTINCT 외부 스캔서 `qfile_list_has_new_backing(list_id)` 와 `list_id->page_cnt` 확인 → H1이면 출력 NEW화 경로 수정, H2면 NEW tapeset page_cnt 정확히 누적(또는 임계 NEW-aware) 수정. 어느 쪽이든 SORT_NEW 게이트라 default 무회귀. 그 후 2A-3.

### (m-CORRECTION) 측정 아티팩트 정정 — 0.97× 유지, 2A-2f는 깨끗한 수정
(l)/(m)의 "2A-2f로 DISTINCT 10.6s(2.9×) 후퇴 / 0.97×는 buggy 토대" 는 **측정 오류였음.** `qfile_sort_new_backing_enabled`/`qfile_scan_new_backing_enabled` = **서버측 getenv**. 재측정 때 서버를 게이트 없이 띄우고 csql 클라이언트에만 env 줘서 NEW 경로가 꺼져 있었음. (H1/H2 가설, B-ii의 "DISTINCT가 왜 OLD" 도 이 confound 산물 — 무효.)
- **서버를 게이트와 함께 기동** 후 정확 측정: DISTINCT 15M 외부 temp SCAN **parallel workers:5 (gather buildvalue)**, **3.68/3.82/3.89s ≈ 0.97×**, 15000000 정확. ⇒ **0.97× 유지, 올바른 NEW tapeset_reader 경유**(buggy OLD-sector 아님).
- ⇒ **2A-2f = 깨끗한 win**: env-OFF GROUP BY 349006→15000000 수정 + NEW 경로 0.97× 보존. env-OFF buildvalue-over-OLD만 serial 복귀(미이주 baseline이라 무방).
- **B-ii 재정의(진짜 잔여 갭)**: NEW 경로서도 **GROUP BY 외부집계 스캔 serial**(scan-based groupby 출력 list가 NEW-backed 아님; trace GROUPBY hash:false sort:false, 외부 temp SCAN parallel 없음, 15000000 정확). DISTINCT/ORDER_BY는 이미 NEW(0.97×). ⇒ B-ii = **group-by/집계 출력 producer의 NEW 이주**(2A-2 scope 중 query_executor.c group-by 미완분). → 그 후 2A-3(PHJ race).
- 측정 교훈(재확인): WM 게이트는 **서버 프로세스 env**에 줘야 함. `cubrid server start` 시 `CUBRID_WM_SCAN_NEW=1 CUBRID_WM_SORT_NEW=1` 필수. 클라이언트 env는 무효.

### (n) B-ii 완료 — GROUP BY 출력 NEW Tapeset 이주 (commit `cf936e0c2`)
DISTINCT/ORDER_BY 출력은 이미 NEW(0.97×). GROUP BY 출력만 OLD라 외부집계 스캔 serial이던 갭 해소.
- 설계 핵심: group-by 출력 = **단일 main-thread drain**(qexec_gby_put_next via qfile_generate_tuple_into_list+qfile_add_tuple_to_list). 병렬 sort여도 worker는 중간 OLD temp run만 생산, 최종 put_fn drain은 single-thread → 출력 list NEW화 = 단일 쓰기를 producer hook→tape_writer로 라우팅(동시 producer 0 = PM-2 레이스 없음).
- 변경(query_executor.c only, 게이트 `qfile_sort_new_backing_enabled()`): (1) qexec_groupby/qexec_groupby_index의 갓-열린-빈 output_list_id를 SORT_NEW일 때 `qfile_list_make_new_backed`로 NEW화(list_file.c:5204 DISTINCT 패턴 미러; 실패시 close_list+FREE_AND_INIT+GOTO_EXIT). (2) 5개 핸드오프 `qfile_copy_list_id(list_id,gbstate.output_file,true,…)`: `qfile_list_has_new_backing()?MOVE:PROHIBIT`. PROHIBIT는 dest tapeset=NULL(list_file.c:576)로 떨궈서 NEW엔 silent-wrong → MOVE(569-572 tapeset 이전+src clear, clear_groupby_state 더블프리 방지) 필수.
- 빌드 1차 실패: `qfile_close_and_free_list_file`은 list_file.c static(미export) → `qfile_close_list`+`QFILE_FREE_AND_INIT_LIST_ID`로 인라인 교체(동일 동작, list_file.c:3684).
- 검증(release tpch_sf10 mpw=8): **서버측** SCAN_NEW=1+SORT_NEW=1 → GROUP BY 외부 temp SCAN **parallel workers:5**, robust 15000000/59986052/1/7=ref; HAVING 8569672/47128037/7=ref; DISTINCT …449999872500000…=ref; DISTINCT 무회귀. **env-OFF: 15000000/59986052/1/7 정확 + 외부 serial(무변경)=default 무회귀.** TDE는 producer infra(PRODUCER_SELFTEST algo=1)로 커버, out_tde 전달; wmg003 라이브 group-by는 미실시(차후).
- 측정 교훈 재확인: 게이트는 **서버 프로세스 env**. 빌드는 conf wipe → 재적용 필수(이번에도 1회 누락 후 복구).

### (o) 2A-3 grounding (hash join) — 다음 집중세션용 정밀 좌표 + 안전 1차 슬라이스
**bug2 = 미이주 병렬 PHJ 레이스(silent wrong, 간헐 149510 vs 정답 200360, develop 정상). 2A-3가 구조 해소 대상. 내 변경 아님(query_hash_join.c/px_hash_join 2A-2 미변경).**
파티션 흐름(query_hash_join.c):
- `hjoin_build_partitions`(:1507) → `hjoin_split_qlist`(:1602, outer/inner ×2): 입력 list 스캔, 튜플 해시→파티션, `temp_part_list_id[pid]`(membuf)에 `qfile_add_tuple_to_list`(:1739); membuf 풀→`part_list_id[pid]`에 `qfile_append_list`(:1709/:1764) spill.
- part 슬롯 alloc: `hjoin_init_split_info` outer/inner->part_list_id db_private_alloc(:2221/2228). 컨텍스트 분배 :1398-1420(part별 outer/inner list_id open).
- 병렬 join: `parallel_query::hash_join::execute_partitions`(qexec_hash_join :220) + `part_mutexes`(:2342 alloc / :2415 free) — px_hash_join.cpp/task_manager.
- 파티션결과 머지 `use_connect` per-PAIR(:1898): `qfile_connect_list`(:1909, membuf==NULL+raw-fd-free일때) vs `qfile_append_list`(:1913). single-owner append :1884.
2A-3 이주(ADR 0004): (worker,partition)별 NEW per-worker tape → partition = 그 tape들 import한 tapeset; `part_mutexes`+`qfile_append_list` copy 제거(NEW 경로 한정); `use_connect`는 NEW 입력엔 drop(OLD 유지 until contract); PRIVATE_SPILL membuf-OFF 제거 NEW scope(query_manager.c:3371/3920); 병렬 partition reader = chunk_distributor; backing-kind entry guard. 게이트(예: CUBRID_WM_HASHJOIN_NEW, default OFF).
**안전 1차 슬라이스(de-risk, behavior 무변경)**: vestigial raw-fd-overflow 잔재 제거 — `get_raw_fd_overflow_page`/`get_sector_scan_list_id` 死(호출0), `register/unregister_sector_scan_list_id`가 unread map 채움(무해) → task_manager.cpp:46-120 + px_hash_join.cpp(:87/121/146/527/605) + .hpp 정리. 그 후 본 이주.
EXIT GATE(plan): PHJ wmloc+tpch serial==parallel robust; **#77 NEW경로 해소**; part_mutexes 0(이주경로); merge guard 0; CoV≤15%; pgbuf_fixes=0; no-mixed=0; PHJ median≤develop×1.10; deadlock-free. = HARD-GATE 서브페이즈 → 졸속 금지(2A-2c 교훈).

### (p) 2A-3 slice-1 착지 — vestigial raw-fd sector-scan 레지스트리 死코드 제거 (2026-07-01, #78) — 구현/측정 사실
> 2A-3 hash-join 이주의 안전 1차 슬라이스. behavior 무변경(死코드). commit `017afa968` (branch `wm-integ-7173-develop`, push@xmilex). SSOT/ADR 미변경.
- **제거 대상 (px_hash_join, +0/−87)**: `px_hash_join_task_manager.cpp` 서버-전역 `sector_scan_list_ids`(`unordered_map<QFILE_LIST_SECTOR_SCAN_INFO*,QFILE_LIST_ID*>`) + `sector_scan_list_id_mutex` + `has_raw_fd_overflow_pages` + `get_sector_scan_list_id` + `get_raw_fd_overflow_page` + `register/unregister_sector_scan_list_id` + 미사용 `#include <unordered_map>`; `px_hash_join.cpp` forward decl 2개 + 호출부 5곳(register outer:87/inner:121/probe:527, unregister build-cleanup:146/probe-cleanup:605).
- **死코드 근거(트리 전수 검색)**: map은 register/unregister가 write만, read는 `get_sector_scan_list_id`/`get_raw_fd_overflow_page` 둘뿐 → **호출자 0**. `has_raw_fd_overflow_pages`는 `get_raw_fd_overflow_page`만 사용. ⇒ 클러스터 전체 死. LIVE OLD sector 기계(`qfile_open/close_list_sector_scan`/`QFILE_LIST_SECTOR_SCAN_INFO`/`shared_info.sector_scan`/`qmgr_list_has_raw_fd_segments`) 무변경.
- **검증**: release(RelWithDebInfo, cf936e0→2390) build+install+link green + campaign conf 재적용. tpch_sf10 무회귀 — serial `USE_HASH(o,l)` count=200360(golden), parallel `PARALLEL(8)`×5 전부 200360 PHJ 정상. (bug2 레이스는 간헐적이라 5run에 미발현; 死코드 제거와 무관.)
- **재-ground 좌표(HEAD cf936e0c2, slice-1 前)**: `hjoin_build_partitions` list_file기준 query_hash_join.c:1507 / `hjoin_split_qlist`:1602(write `qfile_add_tuple_to_list`:1739, spill `qfile_append_list`:1709/:1764) / `hjoin_init_split_info` part_list_id alloc:2221·2228 / `hjoin_merge_qlist` use_connect per-PAIR:1898(connect:1909/append:1913, single-owner:1884) / `part_mutexes` alloc:2342·free:2415 / 병렬 split `split_task::execute`(task_manager.cpp:257) shared part_list_id under `part_mutexes[part_id]`(:429 overflow, :457 membuf-full flush) / 병렬 exec `execute_partitions`(px_hash_join.cpp:161) join_task per-partition(get_next_context:649). 좌표는 slice-1 삭제로 task_manager.cpp만 −76행 드리프트.
- **bug2 재현성 노트**: parallel PHJ 레이스는 간헐적(evidence l 버그2 = 149510 vs 200360 깜빡). 5-run 클린이 레이스 부재를 입증하지 못함 → 이주 후 검증은 (i) 구조적 논거(shared list+mutex 제거) + (ii) 다회+고경합 재현 병행.

### (q) ★2A-3 정정 — bug2 = 병렬 PHJ 입력 sector-read 행유실 (파티션 write race 아님) (2026-07-01, #78) — 측정/코드사실
> evidence(o)/plan의 "2A-3 per-worker tape(part_mutexes 제거)가 bug2 해소" 전제를 **반증**. slice-1(`017afa968`) 후 본 이주 구현→검증 중 발견. 버그 이주는 revert(HEAD=slice-1, src clean). SSOT/ADR 문서는 미변경(설계 재검토 필요 항목).
- **PHJ 두 병렬 경로 구분**: (1) 파티션 `HASHJOIN_STATUS_PARALLEL` = `build_partitions`+`execute_partitions`(work_mem 초과 시). (2) `HASHJOIN_STATUS_PARALLEL_PROBE` = 단일 해시테이블 + 병렬 프로브(`probe_execute`, work_mem 적합 시). **bug2 쿼리(o_orderkey<200000)는 (2)** — gdb로 `build_partitions` 미히트 확인(파티션 안 함).
- **행유실 위치 = 입력 읽기**: 병렬 프로브가 프로브 입력을 `qfile_open_list_sector_scan`(px_hash_join.cpp:611)/`sector_page_iterator`로 읽음 → **임의 파생리스트 행유실**(buggy1/2A-2c 동일 결함, #7173 sector 기계). 파티션 split 입력도 동일 리더. serial=정답, 병렬=유실.
- **측정**(tpch_sf10 release): serial `USE_HASH(o,l) PARALLEL(1)` <200000=**200360**, <2000000=**2000495**(정답). 병렬(8): <200000=**149510**, <2000000=**149574**(env-OFF·게이트-ON 동일 = pre-existing, 내 코드 무관).
- **write측 무관**: `part_mutexes[part_id]` 하에 `qfile_append_list`는 직렬화 → 유실 아님. ⇒ per-worker output tape(내가 구현한 것)는 bug2와 **직교**. 게다가 내 이주는 <2M서 자체 레이스로 varying 오답(209198/837199) → 폐기.
- **NEW 입력 미지원**: `CUBRID_WM_SCAN_NEW=1 CUBRID_WM_SORT_NEW=1` + 병렬 PHJ → **서버 crash + `ERROR: Invalid XASL tree node content`**. PHJ가 NEW-backed 입력을 처리 못함 → 안전 병렬(chunk_distributor) 경로 부재.
- **정정된 수정 지점**: 병렬 PHJ 입력 읽기 sector→chunk_distributor(NEW 입력) 이주(프로브+split) + `Invalid XASL tree` 원인 규명(PHJ NEW-input 인지). per-worker output tape(ADR0004)는 그 위 별도 perf 슬라이스. bug2 EXIT(200360 결정성 + median≤develop×1.10) = 입력 NEW-병렬 완성이 전제. correctness>perf 상 필요 시 OLD입력 serial 강제가 즉효 correctness fix(단 perf 게이트 미충족).
- **gotcha(측정 방법)**: PHJ 병렬 유실은 세션-상태 의존적 재현(cold separate run은 200360, batched -i 세션서 149510 결정적). 다회 + batched 병행 필요.
### (r) 2A-3 REAL — 병렬 PHJ 입력-리더 NEW 이주 (프로브 경로) 착지 (2026-07-01, #78) — 구현/측정 사실
> (q)의 정정 스코프를 실행. commit `d517fc60c` (branch `wm-integ-7173-develop`, push@xmilex). SSOT/ADR 미변경(round-3 (a)/(d) 그대로 구현). 게이트 `CUBRID_WM_HASHJOIN_NEW`(기본 OFF).
- **원인 gdb 확정**: `Invalid XASL tree node content` = **2A-0 backing guard 정상 발화**(오류 아님). 스택: `qfile_backing_guard(mechanism=QFILE_BACKING_OLD, list_file.c:8446)` ← `qfile_open_list_sector_scan` ← `parallel_query::hash_join::probe_execute`(px_hash_join.cpp:514) ← `hjoin_probe`(query_hash_join.c:3339). 프로브 list_id 덤프: `backing_kind_=QFILE_BACKING_NEW`, `tapeset_` set, `first_vpid_={-1,-1}`, `tfile_vfid_=0x0`, `tuple_cnt=59986052`. ⇒ SCAN_NEW서 PHJ 프로브 입력은 **실제 NEW-backed**, OLD sector 리더가 못 읽어 guard가 막음(pre-existing, NEW-입력 경로 부재).
- **수정 (6파일, +270/−96)**: (1) `qfile_hashjoin_new_backing_enabled()`(list_file.c, getenv 캐시). (2) `hjoin_try_parallel_probe`: NEW 프로브 입력 + (게이트 OFF ∨ outer join) → serial 강제(`HASHJOIN_STATUS_SINGLE`). (3) `hjoin_try_parallel`: NEW 입력(outer/inner) → serial PARTITION 강제(split 미이주 크래시 회피). (4) `probe_execute`: NEW → 공유 `qfile::chunk_distributor(tapeset, task_cnt)` 생성(cleanup서 `delete`), sector-scan 대체; `HASHJOIN_SHARED_PROBE_INFO`에 `new_tapeset`/`new_dist` 필드. (5) `probe_task::execute_inner`: per-tuple 처리부(fetch_key→hash→probe_key→merge)를 공유 람다 `process_probe_tuple`로 추출; NEW 경로는 per-worker `qfile::tapeset_reader(new_tapeset, new_dist, m_index)`로 튜플 소싱(COPY peek=0), OLD 페이지-워크는 람다 호출로 동일 로직 유지. (6) `execute_outer`/`split_task`는 OLD 유지(NEW 입력 serial 강제).
- **측정 (release RelWithDebInfo + debug, 서버측 게이트, env -i 격리, tpch_sf10)**:
  - 게이트 ON(SCAN_NEW+SORT_NEW+HASHJOIN_NEW): `<200000`=**200360**, `<2000000`=**2000495**; `;trace on`서 PHJ 프로브 **`parallel workers: 8`**(6천만 입력을 7.2~7.6M씩 8 reader 분담) = chunk_distributor 병렬 실증(passthrough-tautology 아님). batched 결정성 **×4(debug)+×3(release)**.
  - 게이트 OFF + NEW 입력(SCAN_NEW only): `<200000`=200360, `<2000000`=2000495 (force-serial, 정답, 무크래시).
  - serial(PARALLEL(1))+SCAN_NEW: `<200000`=200360 (통합 list scan이 NEW를 정확히 읽음; debug 132s).
  - **env-OFF 무회귀(byte-identical OLD 경로)**: 가드가 NEW-backing에만 발화 → OLD 경로 무변경. pre-existing OLD-sector 유실 재현: `<2000000` PARALLEL(8) = **209198 then 837199**(오답·비결정, (q)의 값과 일치) → 우리 회귀 아님, legacy-until-contract.
  - LEFT OUTER JOIN(게이트 ON) = 200360 (outer serial 강제, 무크래시) — execute_outer 미이주 검증.
  - debug **PRODUCER_SELFTEST + TAPEREAD_SELFTEST algo=1(TDE, wmg003) result=0** — producer/reader 인프라 무회귀.
  - **perf median**(bug2 `<200000`, warm): redesign 게이트-ON **5.34s** vs develop **7.83s = 0.68× (≤develop×1.10 통과)**. bimodal ~27s outlier(60M lineitem BUILD file-hash + NEW materialize I/O 지배; 프로브는 663ms) → 정상상태/CoV 별도 측정 후속.
  - build debug+release green.
- **release-only 빌드 함정(gotcha)**: `HASHJOIN_SHARED_PROBE_INFO` ctor init-list 순서 ≠ 멤버 선언순서 → `-Werror=reorder`(release 프리셋만; debug 통과)로 FAIL. 초기화 리스트를 선언순서로 정렬해 해소. **union 빌드는 release도 반드시 돌려야 함**(debug-only 통과로 착지 금지).
- **남은 것(후속 슬라이스)**: (a) `execute_outer` NEW 병렬(현재 outer+NEW=serial), (b) split/파티션 경로 NEW 병렬(현재 NEW 입력 시 serial PARTITION 강제로 무크래시), (c) perf outlier 정상상태 규명, (d) #77 wmloc PHJ 0-length은 NEW-입력 경로 메커니즘상 해소되나 wmloc-특정 재검증 미실시.
### (s) 2A-3 session-fix — 세션 상태 오염 root-cause 해소 (2026-07-02, commit `d9ad680ad`, #78) — 구현/측정 사실
> SSOT (t)/(u). 세션 프롬프트 과제 A 해소.
- **root-cause**: XASL re-execution에서 `qexec_execute_mainblock_internal`의 subquery parallel executor(`px_executor`)가 aptr 실행 전 worker 1개를 선점 → inner (lineitem) `scan_open_parallel_heap_scan`에서 `try_reserve_workers(8)` = NULL → serial fallback → probe input이 NEW backing 유실(tapeset=nil, backing_kind=0, OLD) → `hjoin_try_parallel_probe`가 OLD `sector_page_iterator`(#7173 sector 기계, known row-loss) 병렬 경로를 탐 → 행유실(200360→407). 첫 실행에서는 subquery executor 미생성(px_executor=nullptr) → worker pool 전체 확보 → inner scan parallel → NEW backing → chunk_distributor → 정답.
- **진단 방법**: (1) `qfile_list_make_new_backed` 호출 로그 — inner list_id에 대한 호출 0회(q2). (2) `scan_open_parallel_heap_scan`에 serial fallback 지점별 로그 → `SERIAL-WORKERS: try_reserve(8) returned NULL` 확정. (3) `hjoin_init_manager`에서 inner_xasl·aptr_list·list_id 주소 대조 — pointer identity 정상이나 list_id 내용(backing_kind)이 OLD.
- **수정 (2파일, +30/−11)**:
  - `query_hash_join.c` `hjoin_try_parallel_probe`: 기존 `NEW && !gate → serial` → **`!NEW || !gate → serial`** (OLD input serial 강제, buggy sector reader 차단).
  - `query_executor.c` `qexec_execute_mainblock_internal`: subquery parallel executor 생성(line 15801) 및 사용(line 15844)에 `&& merge_infop == NULL` 조건 추가 — hash/merge join aptr는 sequential 실행 → 각 scan이 full worker pool 확보.
- **검증 (release RelWithDebInfo + debug, tpch_sf10, work_mem=1G)**:
  - cold csql -c ×5: **전부 200360** (이전: 200360/407/407/407/407).
  - batched csql -i 3쿼리: **200360 / 200360 / 2000495** (이전: 200360/407/407).
  - env-OFF serial: 200360. env-OFF parallel(8): 200360 (OLD → serial 강제).
  - **perf 7회**: 4.401/4.261/5.107/4.798/4.141/4.192/4.244s. **median=4.261s (0.201×develop), CoV=8.2%≤15%**. bimodal 해소.
  - develop median=21.206s → **median≤develop×1.10 충족**.
  - debug+release build green. PRODUCER_SELFTEST algo=1 PASS. TAPEREAD_SELFTEST algo=1 PASS.
- **부수 효과**: (r)의 "cold 별도 csql 세션 필수" 검증 프로토콜 제약 해소 — batched도 정답.

### (t) 과제B 잔여 EXIT 게이트 + 메모리 풀 수정 (2026-07-02, commit `fb4e20af6`, #78)
> SSOT 해당 없음 (검증 결과만). 세션 프롬프트 과제 B 해소.
- **#77 wmloc PHJ 재검증 (release, gates ON)**: `SELECT DISTINCT a FROM t` → `4194304/8796090925056/0/4194303` = golden-exact. serial == parallel 패리티 ✅. 크래시 없음 (#77 NEW 경로 해소).
- **debug selftest**: `PRODUCER_SELFTEST algo=1 result=0`, `TAPEREAD_SELFTEST algo=1 result=0` (TDE, wmg003) ✅.
- **하드 카운터 (CS debug wmloc, gates ON)**: `Num_data_page_fixed=1` (NEW scan pgbuf 미사용), `rawfd_pgbuf_spill_overflow=0`, 에러 로그 backing guard 위반 0건, assert/crash 0.
- **메모리 풀 수정 (commit `fb4e20af6`)**: `qmgr_initialize_temp_file_list`가 부트 시 `QMGR_TEMP_FILE_FREE_LIST_SIZE(100) × work_mem(1G) = 100GB`를 미리 할당. 수정: pre-allocation 루프 제거, lazy pool. debug wmloc RSS: 100.6GB → 504MB(시작), 1.0GB(쿼리 후).

### (u) per-worker OUTPUT tape + 인벤토리 sweep (2026-07-02, commits `544512265`+`1fe2b07d8`, #78)
> SSOT UPDATE (v): per-worker OUTPUT tape 구현 + 인벤토리 A~E sweep 완료.

**과제A — per-worker OUTPUT tape (ADR0004, part_mutexes 제거):**
- **root-cause 분석**: 이전 시도의 "자체 레이스"(209198/837199) = pre-existing `sector_page_iterator` 행유실 값과 동일(evidence (r) env-OFF <2M). 당시 입력 리더가 OLD sector 기반 → 입력 버그가 결과 오염. `d517fc60c`~`d9ad680ad` 입력 이주 후 root-cause 제거.
- **구현 (commit `544512265`)**: NEW split 경로에서 각 워커가 자기 전용 파티션 리스트에 쓰고(`worker_part_lists[worker][partition]`), 리더가 `task_manager.join()` 후 순차 병합. `part_mutexes` 락 제거(NEW 한정).
- **검증**: INNER <200000=200360, <2000000=2000495, env-OFF=200360, wmloc DISTINCT=golden, selftest PASS(TDE), debug+release green, perf ~4.7s(0.22×develop).

**과제B — 인벤토리 A~E sweep:**
- **A-1** (P1, 해소): `use_connect` 가드에 `!qfile_list_has_new_backing()` 추가 (commit `1fe2b07d8`). latent hazard 제거.
- **A-2** (P2): `membuf_last` 역참조 — legacy-until-contract (split 파티션 항상 OLD).
- **E-1** (P1): `qexec_clear_xasl_head` tapeset destroy 시 활성 reader 가능성 — needs-investigation (에러 경로 scan closure 순서 감사 필요).
- **E-2** (P3): index covering scratch — legacy-until-contract.

**과제C — 잔여 operator 출력 점검 (18 사이트 분류):**
- **이미 게이트됨**: SORT/GROUP BY/ROLLUP(SORT_NEW), parallel SCAN(SCAN_NEW), PHJ probe(HASHJOIN_NEW).
- **NEW-convertible (P2)**: analytic intermediate/output(C-7/C-8), merge join(C-1/C-2), UNION/CTE(C-3/C-6), hash join ST output(C-15).
- **legacy-until-contract (P3)**: CONNECT BY(in-place page 수정), BUILDVALUE(1튜플), BUILD_SCHEMA, aggregate per-function, hash split 내부 파티션, analytic distinct/group/value scratch, agg hash partial.
- **전환 로드맵**: analytic → merge join → UNION/CTE → hash join ST output (별도 슬라이스).


---

## J. 종합 정적 리뷰 결과 (2026-07-02, HEAD `25ba22327` — 7영역 병렬 코드리뷰 + 하네스 유효성 평가)

> 출처: `~/dev/workspace/temp_workmem/issue69-81_review_report.md` (전체 좌표/시나리오는 보고서가 정본).
> 전부 **정적 분석 사실**(코드 인용 기반) — DB 실행/VTune 미수행. [V] 표시는 런타임 확인 필요 항목.

### J-1. 확정 버그 (측정/사실)
- **R1 (CRITICAL)** NEW-backed 최상위 결과 클라이언트 전송 불가: frozen NEW = `first_vpid NULL` → `cursor.c:1494` 즉시 END(release 0행), `xqfile_get_list_file_page` VPID 전용(debug assert :2626). Class-B 3싱크(query_manager.c:1501/1863/2637)의 materialize가 `qmgr_list_has_raw_fd_segments`(RAW_FD_OVERFLOW 전용) 게이트 → tapeset-blind no-op. 리스트캐시는 PROHIBIT 복사로 tapeset NULL → 백킹 없는 영구 빈 엔트리. [V: `csql -c "SELECT * FROM t ORDER BY 1"` 1분 검증]
- **R2 (CRITICAL)** PEEK-borrowed 포인터에 `db_private_realloc`(qfile_tape.cpp:466/517/826/845) — 레거시 `size==0→alloc` 가드 누락. PEEK 후 overflow 튜플 = 힙 오염. (동계열 정렬 리더 수정 이력: list_file.c:4316-4318 주석.)
- **R3 (HIGH)** `qfile_close_list` NEW 분기 `(void) producer_append` + freeze NULL 무보고(void API) → ENOSPC 시 silent truncation/empty (list_file.c:1403-1421).
- **R4 (HIGH)** SERVER_MODE `operator new` = noexcept NULL(memory_wrapper.hpp:55-88) — freeze OOM-safety(fc4974dd4)는 throwing 전제라 무효: `new buffile_tape` NULL이어도 `m_buffile=NULL; m_prefix.clear()` → fd+파일+prefix(≤work_mem) 전량 누수; tiny 경로 `new memory_tape` NULL-deref (qfile_tape.cpp:305-328).
- **R5 (HIGH)** R1 스캔 파일페이지 스크래치 `m_readbuf`가 per-scan 아닌 per-tape(qfile_tape.hpp:174) — 같은 스필 리스트 위 2스캔 인터리브(NEW CTE self-join, 단일 스레드로 충분) = 무음 오염. R2 reader는 per-reader 스크래치라 안전.
- **R6 (HIGH)** PHJ **split** `hjoin_try_parallel`(query_hash_join.c:1970-2059)에 OLD-입력 가드 부재(probe 가드 :2128-2134만 존재) → 중첩 HJ 결과/워커풀 고갈 fallback 입력이 행유실 `sector_page_iterator`를 기본 설정에서 병렬 실행. 부속: `CUBRID_WM_HASHJOIN_NEW=0`이 split엔 무효(px_hash_join.cpp:86/204 gate 미참조).
- **R7 (HIGH)** NEW 좌표 VPID-punning: (a) hash list scan HYBRID/HASH_FILE — build가 synthetic mirror vpid(tape_idx 소실, qfile_tape.cpp:1040-1054)를 저장, probe가 tape 좌표로 재해석(UNKNOWN_CRSPOS/오답), cleanup이 malloc 페이지를 pgbuf unfix(scan_manager.c:9095/9134); `check_hash_list_scan`(:9175) backing 체크 없음. (b) ORDER BY/DISTINCT partial-key: `qfile_initialize_sort_key_info`(list_file.c:4939)에 NEW 가드 없음(GROUP BY :5682/ANALYTIC :21612엔 있음). work_mem=1G 캠페인에선 HYBRID 창이 안 열려 미노출.
- **R8 (HIGH)** `cubrid_buffile/buffile_*.tmp`(qfile_buffile.cpp:296-329)는 dtor unlink 뿐 — 부트 스윕(temp_page_store.cpp:455-489)은 raw-fd 네임스페이스만. 크래시 = 영구 고아(orphan-zero 위반). scratch fallback 최후가 `/tmp`(:287-292).
- **R9 (HIGH)** E-1 잔여: (a) `qexec_clear_xasl`가 aptr 자식 tapeset 파괴 후 scan_ptr 체인 close(:2394-2428) — close가 죽은 tapeset 참조(release_page→get_tape). (b) per-row `qexec_clear_head_lists`(bptr/fptr :8641/:8714) 스캔 close 없이 destroy; `qfile_truncate_list`(list_file.c:3560-3601)는 tapeset 미리셋.
- **R10 (MED)** `qfile_tapeset_import`(qfile_tape.cpp:1541-1567) append 루프 후 소유권 flip — 중간 bad_alloc = 이중해제; src에 dangling unowned 포인터 잔존.
- **R11 (MED)** NEW prefix = producer당 `work_mem/DB_PAGESIZE` plain malloc, accountant 미연동(qfile_tape.cpp:1527-1531) → degree×work_mem 무계정 RSS. lazy pool free-list 100개 유지 = 버스트 후 ≤100×work_mem 상주(query_manager.c:73,4543). NEW 리스트마다 membuf 생성→즉시 반환 낭비(query_manager.c:3735→list_file.c:5173).
- **R12 (MED)** holdable: ADR0001 "reparent 복사 없음" vs 코드 = materialize 시도(그마저 R1 blind) → NEW holdable 커서 0행. tran→session 핸드오프가 mutex 밖(query_manager.c:2616→2643) = 무소속 창 [V: ASAN].
- **R13 (LOW 묶음)** 병합 실패 슬롯 미-NULL(px_hash_join.cpp:170-181/281-292); `buffile_metrics.pages_read` 죽은 카운터; `page_at` er_set 없는 실패; NEW producer 루프 interrupt 체크 누락; `qfile_copy_list_id`의 producer 필드 무단 복사(규율로만 안전); DISTINCT가 env-OFF에도 result-file 라우팅(list_file.c:1280-1283); `hjoin_init_manager`의 NOT_USE_MEMBUF 드랍(미문서 결정, query_hash_join.c:806-807).

### J-2. 하네스 유효성 (측정/사실)
- **버그-하네스 매트릭스: 확정 8건 중 0건 검출 가능** — 전부 에러 경로/실물 싱크/인터리브에 존재, 하네스는 happy-path/프록시/집계 한정.
- `pgbuf_fixes`(buffile_metrics·tapeset_scan_metrics) **증가 사이트 0** (grep 확정) → "pgbuf-bypass 하드게이트" = `assert(0==0)` 동어반복. `pages_read`도 미증가(별도 `m_reads` atomic만).
- `parity.sh:41-51` `result_rows()`가 복수형 `rows selected`만 매칭 → 단일행(`1 row selected.`)에서 trace 유입 = **정본 단일행 집계에서 위양성 FAIL 실재**(results/parity.wmloc_distinct_parity.sql.proof.txt — md5 불일치가 전부 trace timing 라인). 병렬 실증은 예약 시점 수치(query_executor.c:15878)라 이후 per-operator serial fallback 미검출; serial 레그 워커=0 미검증(`set_server_conf_param`이 conf 미기록 시 무음 no-op, lib.sh:81); **NEW-engagement 무검증**(게이트 거부→OLD 폴백이어도 PASS).
- in-server selftest 4종: 실물 API를 몰지만 `qmgr_initialize`가 **리턴코드 폐기**(query_manager.c:1178-1189 — FAIL이어도 부트 green), debug 전용, 비게이팅. #72 "세션 kill orphan-zero"는 `qfile_clear_list_id` 직접호출 프록시(실물 세션/커서 레이어 미경유).
- census: writer-held prefix(freeze 전) 미계상 → 누수된 writer는 orphan-zero 통과. in-process라 크래시 고아 표현 불가.
- unit G1~G6/G8~G13/G15~G18(coverage)은 진짜 판별력 있음(우수). G14(b)(c) CoV는 단일스레드 round-robin의 산술 필연. 유닛 스크래치 `/tmp`(test_tapeset_scan.cpp:159) 하우스룰 위반. `gate_tapeset_scan.sh`/`lib_build.sh`/`preflight.sh`/`checklists/issue68_hooks.md`/wmloc parity `.sql` 전부 **untracked**.

### J-3. perf 구조 분석 (사실 + 구조 결론 구분)
- [사실] pgbuf fix/unfix RAM 히트 = 페이지당 ~0.2-0.4µs(develop page_buffer.c 경로), 튜플당 상각 3-7ns. NEW BufFile: 쓰기 memcpy+128KB 배치 pwrite(8페이지당 1), 읽기 **페이지당 pread 1**(배치/readahead 없음), TDE 읽기에 불필요 16K memcpy 1(qfile_buffile.cpp:541). overflow run 첫 페이지 2회 읽음(감지+재조립).
- [사실] SORT 중간 런/머지 = 여전히 OLD pgbuf(`sort_write_area`/`sort_read_area`/`file_create_temp_numerable`, external_sort.c:5993/6041/4383 미게이트), 최종 머지 파일 pgbuf 재독 후 튜플 단위 NEW 재기록(:3327/:3363) = 이중 물질화. PHJ 리더 병합 = `qfile_append_list` 튜플 전량 재복사(2× 증폭, 직렬) — ADR0004 "import" 미완. build 단계 완전 직렬.
- [사실] 잔존 raw-fd(미이주 연산자 스필): per-tuple shard mutex(`rawfd_find_and_mark_dirty` ← query_manager.c:3066) + 16KB 단건 pwrite — `LEADER_VERIFIED_ENABLE_RAW_FD_WRITES=true`(temp_page_store.cpp:91)로 기본 live.
- [구조 결론] develop VTune의 pgbuf_fix 1위 = 폭(전 서브시스템 경유)+병렬 경합의 산물이지 단일 스트림 히트 비용 아님 → pgbuf 제거 자체는 CPU-bound 질의에서 수 % 미만. heavy-spill에서 develop에 지는 주인 = 이중 물질화 > work_mem 상한 prefix(vs 512M 공짜 캐시) > raw-fd 잔존 > 읽기 배치 부재. **`median≤develop×1.10`(#74 EXIT)은 정렬 내부(런/머지) NEW화 없이 달성 불가.** PHJ 5×(0.20×) = 병렬화 해금이지 I/O 승리 아님(develop은 동 경로 serial).
- 측정 계획 9종(귀속 검증/strace 시그니처/work_mem 절벽/이중스필 정량/readahead/raw-fd 경합/가드 오버헤드/LRU 상호작용/statdump 노출 선행)은 보고서 §6.

### J-4. 기존 서술 정정 (supersede — 역사 재작성 아님)
- SSOT §5.5(6)·§6 "pgbuf-bypass 하드 게이트" → **실배선 전까지 하드 게이트로 간주 금지**(J-2). #71 acceptance의 해당 체크는 "구조적 보장" 표현으로 읽을 것.
- #72 acceptance "세션 kill→orphan-zero(파일+RAM)" → **프록시 검증**이었음. 실물 WITH HOLD 경로는 R1/R12로 현재 깨져 있음.
- #80 완료 코멘트의 "검증 통과(6군 parity)" → 필수조건 5개 중 (1) full-suite 미실행, (2) 10군+ 확대 parity 미충족 상태의 부분 통과로 정정.
- evidence (v)/(u)의 "인벤토리 18 사이트" → 분류 합계 21(5+7+9) — "18"은 오기.
- (t)의 "세션 상태 오염 root-cause 해소" 자체는 유효하나, 동일 수정이 커버하지 않는 **split 경로**(R6)가 같은 기제로 잔존 — "(t)로 sector 행유실 노출이 닫혔다"고 일반화하지 말 것.
- ADR 0001 "holdable = reparent, 복사 없음" ↔ 코드(query_manager.c:2637 materialize 시도) 불일치 — 설계 의도 유지 시 코드가, 코드 유지 시 ADR이 고쳐져야 함(현재는 양쪽 다 아닌 상태 = R1).
- ADR 0004 "per-worker tape import" ↔ 코드(리더 병합 = 튜플 재복사) — import 미구현으로 정정.

---

## K. 2026-07-02 사실 변경/갱신 로그 (§J 이후 — GitHub #76 코멘트 미러)

> §J(HEAD 25ba22327) 게시 이후 GitHub #76 코멘트로만 적립된 사실 변경·해소 항목을 로컬로 동기화한다(코멘트 충실 미러, 요약 변형 최소화). 각 항목은 §J의 R-번호 결함 또는 진행 이슈(#78 배치)에 대응. 시간순.

### K-1. §J-4/R1 후속 — Class-B 싱크 tapeset 물질화 (#94, 커밋 `92a55adc1`, 05:19)
§J(및 리뷰 보고서 R1)의 사실 중 다음이 커밋 `92a55adc1`로 **변경**됨:
- ~~"3개 Class-B 싱크의 `qmgr_materialize_to_pgbuf`는 raw-fd 전용 술어라 Tapeset에 no-op"~~ → **수정됨**: 진입 술어가 `qmgr_list_needs_pgbuf_materialize`(raw-fd OR NEW(Tapeset), dependent 체인 순회)로 확장. 게이트 ON에서 frozen NEW top-level 리스트가 3싱크 전부에서 실-VPID pgbuf 리스트로 물질화되어 서빙됨 — e2e: 4.19M행 클라이언트 fetch 전량 도달, 캐시 히트==미스, CCI holdable commit 경계 통과, TDE(wmg003 AES) 유지, iowrites 델타 0, 스필 잔존 0. 상세는 #94 완료 코멘트.
- materialize 루프 본체는 무변경으로 충분했음: `qfile_open_list_scan_raw_fd_segments` == `qfile_open_list_scan`(동일 internal, Tapeset 스캔 분기 내장) — R1 서술 중 "tapeset 분기 추가 필요"는 정확히는 "진입 술어만 tapeset-blind"였다.
- 게이트 기본값은 여전히 **OFF**(#82 롤백 유지). 기본 재-ON은 별도 검증 이슈 몫.
- 신규 발견(게이트 무관/게이트 ON 기존 결함 2건 — QUERY_CACHE 힌트 절단, NUMERIC 집계 GBY parity 실패)은 별도 이슈로 분리 예정.
- Refs #94 #78 #75

### K-2. 환경 사실 — libasan 64bit 런타임 부재 (#83 작업 중, 05:46)
이 호스트(및 아마도 동일 이미지의 다른 워커)에는 어떤 툴체인(시스템 gcc 8, gcc-toolset-13/15)에도 **64bit libasan 런타임이 설치돼 있지 않다** — `/usr/lib/gcc/x86_64-redhat-linux/8/libasan.so`는 존재하지만 링커 스크립트가 가리키는 `/usr/lib64/libasan.so.5.0.0` 자체가 없고, gcc-toolset-13/15는 `.../32/libasan.so`(32bit)만 보유. `-fsanitize=address`로 링크 시 `cannot find /usr/lib64/libasan.so.5.0.0`로 실패. "ASAN 빌드에서 clean" 게이트가 필요한 이슈는 **valgrind memcheck**(`--leak-check=full --track-origins=yes`)로 대체 — 무효 포인터 realloc/free·힙오염·누수 클래스는 동일하게 잡힘. 패키지 설치(sudo dnf install libasan) 여부는 확인/시도하지 않음(공유 호스트 시스템 변경이라 별도 승인 필요 판단).
PL 서버 기동 실패는 이미 기록된 사실과 일치(`fresh debug PL boot 실패 → java_stored_procedure=no` 우회) — #83에서도 동일 재현, #85(`01b41d602`)에서도 독립 재현.

### K-3. tape 계약 변경 + 실물 오답 증적 (#87, 커밋 `81ef3ed06`, 07:42)
- **tape 계약 변경(#87, 커밋 `81ef3ed06`)**: frozen tape에서 `page_at`/`release_page` 제거, `read_page_into(const, caller-scratch)` 단일화. R1 스캔 스크래치는 tapeset_scan 소유(lazy, 스캔당 DB_PAGESIZE+TDE scratch — #91 계정 대상). `tapeset_scan::close`는 tapeset 생존 비의존(#89 답변 확정), jump 경로 포함 caller-scratch 계약(#101 전제 충족).
- **실물 오답 증적**: pre-fix + `CUBRID_WM_SORT_NEW=1`, wmloc CTE self-join COUNT=704,316 (정답 2,477,800) — 무음 오염 실재 확인. 수정 후 ON==OFF parity, engagement delta(new_backed_create=1/old_touch=0) 실증.
- **신규 사실**: `CUBRID_WM_SORT_NEW=1` × **CONNECT BY**(INSERT ... CONNECT BY) 조합에서 cub_server abort — `qexec_recalc_tuples_parent_pos_in_list` → `qfile_tuple_position_store_to_db`의 #85 assert(TAPE-coord는 POSITION_DB 저장 불가) 발화. pre-existing 한계(#101 좌표 1급화 영역), coredump `cub_server_20260702162018.509`. 게이트 ON 캠페인 시 CONNECT BY 쿼리 주의.

### K-4. §R11 반영 — NEW prefix 계정/풀 상한/memset 제거 (#91 close, `d45fdb15b..a767936e4`, 08:31)
사실 변경 3건 — 기존 evidence(§R11 계열)의 관련 서술은 이 시점 이후 stale:
1. **NEW prefix 무계정 → 계정됨**: tape_writer prefix가 accountant에 64페이지 배치 reserve_held로 계상, cap 도달 시 조기 스필 degrade(관측: work_mem=1G/cap=64M에서 쿼리당 degrades +18, reserved_bytes 피크 83.4M→종료 후 0). charge는 frozen Tape로 이전되어 holdable 상주분도 계정 유지.
2. **lazy pool 100엔트리 무제한 → 바이트 상한**: free list put 시 count<100 AND bytes ≤ max(cap/4, 64M). 동시 128 정렬 버스트 후 release cub_server VmRSS 625MB(구조상 100×work_mem 상주 불가능해짐).
3. **temp file 생성 시 work_mem 전체 memset 제거**(헤더만 zero) → NEW 전환 낭비 사이클의 RSS commit 소멸. PHJ golden 224ms→176ms(-21%), env B k64/k128 band 내 개선측.
검증 상세: #91 close 보고 참조 (parity DISTINCT/SORT green, TDE 셀프테스트 PASS, debug+release green).

### K-5. R12 정정 — 제안 수정 방향 부적합, 실버그 1건 수정 (#96, 커밋 `cac62d9a4`, 08:44·08:55)
> gh #76에 같은 사실이 두 코멘트로 적립됨(간이판·상세판). 둘 다 미러.
- **(간이판)** R12(#96)의 두 제안 수정 방향(2단계 게시 재정렬 / 핸드오프 전체를 tran 락으로 감싸기)이 모두 부적합함을 확인 — 락 확장은 `qmgr_create_new_temp_file()`이 동일 non-recursive `tran_entry_p->mutex`를 재획득해 데드락, 리스트 재정렬은 실제 보호 대상(file manager의 tran-scoped temp file 등록)과 무관해 무효. tran측/세션측 양쪽 다 UAF 도달 경로 없음(세션측은 `SESSION_STATE.ref_count>0` 가드로 안전) 확인. 대신 조사 중 발견한 실제 리소스 누수(`session_store_query_entry_info()`가 실패를 알리지 못해 OOM 등에서 결정론적으로 발생)를 반환값 수정으로 해결. 상세: #96 완료 보고. 커밋 `cac62d9a4`.
- **(상세판)** 리뷰 보고서 R12의 두 수정 방향은 모두 부적합 판명: ① 핸드오프 전체 락 확장 = `qmgr_materialize_to_pgbuf` → `qmgr_create_new_temp_file`의 동일 non-recursive `tran_entry_p->mutex` 재획득으로 **데드락**, ② publish-then-unlink 재정렬 = qmgr 리스트 소속과 `file_Tempcache.tran_files` 등록이 **독립 부기라 무효**. '무소속 창'은 구조상 실재하나 tran측(sweep은 `qmgr_clear_trans_wakeup` 리턴 후 동일 스레드에서만)·세션측(`ref_count` 가드, session.c:822-828) 모두 **도달 불가** 확인. 대신 실버그 1건 수정: `session_store_query_entry_info`의 void 반환 + 호출부 무조건 NULL-out으로 인한 OOM/무세션 시 결정론적 고아 누수 (commit `cac62d9a4`). 상세: #96 완료 보고.

### K-6. R3 해소 — qfile_close_list silent truncation (#86 완료·close, 커밋 `9adb89d26`, 10:10)
- 커밋 `9adb89d26` (wm-integ-7173-develop). close/freeze 실패 계약으로 교체: tape_writer sticky-error latch(`m_failed`/`failed()`), `freeze()`는 실패 시 소유권 이전 전 NULL, `QFILE_LIST_ID_PRODUCER_FAILED` 마크 → `qfile_open_list_scan`이 `ER_QPROC_OUT_OF_TEMP_SPACE` raise. silent 0행/truncation 차단.
- 기계 검증: `CUBRID_WM_CLOSE_FAULT_SELFTEST` (ENOSPC fault-injection, `CUBRID_WM_FAULT_FLUSH_AT`). fail-before-fix result=-1 → after-fix result=0, census baseline 복귀. debug/release green, wmloc DISTINCT PARALLEL(8) 무회귀(2000/1999000/0/1999, workers=8).
- **#95(freeze OOM 소유권 원상복구)**: 위 'freeze는 실패 시 소유권 이전 전 NULL' 불변식 + `failed()` latch가 기반. OOM 경로(noexcept-NULL/throw)도 같은 지점에서 latch+NULL로 통일하면 소유권 원상복구 자동 성립.

### K-7. SYNC 기록 — SSOT(#75) 본문 갱신 (supervisor, 10:19)
sonnet 준비 세션의 SYNC 초안(미게시, supervisor 검수 통과)을 반영해 #75 본문을 편집하고 로컬 미러(`issue65_ssot.md`)를 동기화. 반영 골자:
- **§2**: HEAD 좌표 `25ba22327`→`9adb89d26`, 게이트 서술 "기본 ON, 롤백 예정"→**기본 OFF 완료**(`303fcc6bc`), 결함 표→착지 현황 표(20건 close + 진행 중 5건), 실행순서→크리티컬 패스(#107→#97→#80→#81→#74).
- **§3**: P7 해소(#93), P8 부분 해소(#92), P9에 #94 착지 반영, P10 실측 확정(#98: 주범=base per-row pread→#107, wide-row 무회귀→#101 후순위), **P12 신설**(R12류 이론적 창은 구현 전 도달가능성 검증 — supervisor 판단으로 일반화 채택).
- **§4**: NEW-engagement 카운터 assert 가능(#92), #93 하드 게이트 승격, #86 close/freeze 계약 불변식 편입.
- **§5**: 런타임 검증 규칙 정식 편입, `git fetch --all` 실사고 반영, 함정 목록 7종으로 현행화(신규 ⑥재빌드가 conf 리셋, ⑦stop이 master 미종료 — #86 세션 발견).
- **§6**: G1~G18→G1~G22, selftest 게이팅됨(#93), R12 사실 변경 각주, qfile_tape.cpp 충돌 규칙 편입.
supervisor 판단 3건(초안 §E): ①P12 일반화 **채택** ②#99는 **트랙 내 유지**(검증 무결성 영향 + Batch A가 Option B 구현 중 + #107 Phase 2 선행) ③본문 편집은 supervisor가 직접 수행(이 기록).

### K-8. R4 해소 — freeze OOM 누수/크래시 (#95 완료·close, 커밋 `0f85fd6d6`, 10:50)
- 커밋 `0f85fd6d6` (wm-integ-7173-develop, `9acdc6150` 위 rebase). SERVER_MODE noexcept-new(NULL) 대응: `tape_writer::freeze`의 memory_tape/buffile_tape 할당을 소유권 이전 전 NULL 체크 → `ER_OUT_OF_VIRTUAL_MEMORY` + `m_failed` latch + NULL 반환, caller `delete w`가 prefix/스필파일 회수. #86의 'freeze 실패 시 소유권 이전 전 NULL' 불변식을 OOM까지 확장(전파는 #86 재사용, 미재구현).
- 기계 검증: `CUBRID_WM_FREEZE_OOM_SELFTEST`(OOM injection `CUBRID_WM_FAULT_ALLOC_AT`). fail-before-fix=부트 크래시(recovery 제거 빌드, env로만 재현), after-fix result=0(P1 spill: census open_files baseline 복귀=fd+파일 회수; P2 tiny: NULL-deref 없음, prefix 유지). debug/release green, NDEBUG 컴파일아웃 확인. wmloc DISTINCT PARALLEL(8) 무회귀(2000/1999000/0/1999).
- R3(#86)·R4(#95) 두 계약이 이제 tape_writer 실패 경로(append 손실·flush ENOSPC·freeze OOM)를 일관 처리 — freeze는 어떤 실패든 소유권 이전 전 NULL, close는 failed 마크, scan-open은 raise.

### K-9. #88/#89/#99 착지 + #83/#85/#77 검증부채/재트리아지 (배치, 10:51)
**착지 커밋** (`xmilex/wm-integ-7173-develop`, 베이스 `9adb89d26`): `86bb5b3f8`(#88) · `76b351561`(#89) · `9acdc6150`(#99)
1. **#99 루트코즈 정정 (§ 병렬 SORT 절단 계열)**: 절단 원인은 "캐시 publish"도 "FILE_QUERY_AREA **출력** 직접 쓰기"도 아니라, **px 정렬 입력 sector scan이 raw-fd overflow 페이지(`RAW_FD_OVERFLOW`, temp_vfid=NULL)를 열거하지 못해** 워커들이 membuf 프리픽스만 정렬하는 것 (계측: 워커 산출 합 1,128,632/5,120,000, 손실 집합은 정렬 키 무관 = 입력 페이지 결정). 수정: raw-fd 입력 시 serial 가드 + sort-then-move + 출력 query-area 안전망 (`9acdc6150`). 후속 과제: sector scan에 raw-fd chunking (NEW의 chunk_distributor 상당).
2. **게이트 기본값**: `CUBRID_WM_SCAN/SORT/HASHJOIN_NEW`는 HEAD 코드상 **기본 OFF** (일부 이슈 본문의 "기본 ON" 기재는 stale). buffile 스필 경로도 게이트 필요(무조건 활성 아님 — #88 검증에서 확인).
3. **#85 store_to_db assert 실전 발화**: CONNECT BY parent-pos punning(query_executor.c:19098)을 게이트 ON에서 검출(core 채증) — #105(`b9081226a`)가 근본 수정, 수정 후 정상 재확인 완료.
4. **#77 stale close**: e21917cfd의 0-byte alloc PHJ 결함은 현 HEAD 미재현(3/3 정상). 단 **신규 #109**: `CUBRID_WM_HASHJOIN_NEW=1` + work_mem=8M PHJ가 결정적 힙손상 SIGABRT (px_hash_join.cpp:196 build_partitions, 빌드 2종 3/3).
5. **orphan-zero(§6)**: cubrid_buffile 부트 스윕 착지(#88) — `<base>/cubrid_buffile/<db>/<sid>` 서브트리 + kill-9 회귀 테스트 PASS. 구 레이아웃(디렉토리 직하) 잔재는 새 스윕 대상 아님(1회 수동 정리함, 신규 발생 없음).
**검증 기록**: debug+release 풀빌드 green(베이스 `9adb89d26`) · tapeset ctest PASS · wmloc DISTINCT/ORDER BY robust-parity PASS(NEW 발동 실증, 최종 베이스 재확인) · #99 진단 매트릭스 debug/release 전 항목 5,120,000 · #89 에러경로 valgrind invalid r/w/free 0.

---

## K-10. 2026-07-02 밤 — #109 PHJ 결정적 힙손상 해소 (Batch B 슬롯1, `68e341295`)

**루트코즈 [CONFIRMED]**: ADR0004 per-worker OUTPUT tape의 slot 배열(`worker_part_lists[wi]`)을 **워커**가 `db_private_alloc`(스레드별 lea mspace, `memory_alloc.c`)으로 할당하고 **리더**가 `px_hash_join.cpp:196`에서 `db_private_free` — 외부 mspace 청크 free → `mspace_free` `ok_address` 실패 → `USAGE_ERROR_ACTION`=ABORT(`malloc_2_8_3.c:5052`). release 백트레이스와 정확 일치. debug에선 동일 결함이 워커 alloc-tracker 잔존 항목으로 task 종료 시 `resource_tracker.hpp:455` assert로 더 일찍 발현. `work_mem=1G`에선 partition 경로(`hjoin_try_partition`→`build_partitions`) 미발동이라 잠복 — #98 캠페인이 못 본 이유. px_scan은 동일 상황을 `db_change_private_heap(thread_p,0)`로 이미 회피, PHJ per-worker output만 누락이었음. error path `hjoin_clear_shared_split_info`(`query_hash_join.c:2482`)에도 동일 잠재 결함 존재(동시 해소).

**수정**: slot 배열 할당을 리더(`build_partitions` outer/inner)로 이동, 워커는 채우기만 (`68e341295`).

**검증** (debug `11.5.0.2437-0f85fd6 Jul 2 2026 20:07:02` / release `... 20:22:16`):
- fail-before-fix: 현 HEAD(0f85fd6d6) debug 3/3 SIGABRT — core.parallel-query.3311439/3314095/3314946 신규 채증(전건 동일 시그니처)
- 수정 후 debug 게이트 3종 ON+8M: 3/3 `4194304/8796090925056`(골든), `Num_qfile_new_backed_create` delta=16/run, trace `parallel workers: 8`
- 게이트 OFF 동일 결과(매트릭스 동치), ctest tapeset PASS
- valgrind memcheck(게이트 ON+8M, 재현 쿼리): **Invalid read/write/free 0**, 결과 골든 일치. Mismatched new/free 105건은 pre-existing 클래스(부팅만으로 32건, 셧다운 경로 프레임 대부분 — memory_wrapper 유래, 수정 파일 무관)
- release 게이트 ON+8M: 3/3 골든, delta=48/3run, 서버 생존
- release tpch_sf10(campaign conf 1G): PHJ 골든 `<200000`=200360 / `<2000000`=2000495, TPC-H Q2(4667/20678731.70)·Q4(5그룹) — **ON==OFF 완전 일치**
- ASAN 대체: 이 호스트 64bit libasan 부재(기왕 기록) → valgrind memcheck 사용

## K-10. #120a 보고의 "top-level NEW+overflow SQL 생산 불가" — 오판 정정 (2026-07-03, #120b 착지분)

- **정정**: #120a 착지 보고 4번의 "현 엔진에서 top-level NEW+overflow 결과는 SQL로 생산 불가"는 **틀렸다**. `enable_string_compression=no` big-tuple 형상(ORDER BY/GROUP BY/plain-select)은 NEW+overflow top-level 결과를 실제로 생산하며, #120a의 materialize 폴백이 설계대로 작동하고 있었다.
- **원인**: 계측 오류 — #120a 자체 편집이 `qmgr_materialize_to_pgbuf`를 ~55줄 밀어 stale line-bp가 죽은 줄을 짚음(materialize측 카운트만 무효). serve측 함수-bp와 클라이언트-가시 검증은 전부 유효.
- **구조적 방지**: `2fafae2be`가 라우팅 census 카운터 `Num_qfile_client_fetch_serve` / `Num_qfile_client_fetch_materialize`(statdump) 신설 — "materialize 발동 0" acceptance가 디버거 없이 하네스-단언 가능(§4 카운터 독트린 확장).
- **파급**: #120b 재스코핑 논의(축소/종결 옵션)는 무효 — 번역 구현(원계획 (a))으로 착지 완료. 교훈 "오진도 확정 기록을 이긴다"(#99)의 재확인 사례.
- Evidence: #120 코멘트(착지 보고+리뷰), 커밋 `2fafae2be` 메시지 "Correction" 절.

## K-11. parity 픽스처 outer_join/cte의 develop 대비 gate-ON 회귀 관찰 (2026-07-03, #124)

- **실측** (release, 콜드세션 3회 중앙값, develop `47fcc321f`=11.5.0.2295 vs redesign 게이트 ON, 동일 wmloc DB): outer_join **2.99×**(8.91→26.69s) / cte **1.44×**(17.84→25.62s) / connect_by **0.92×**(회귀 없음). 결과행 수 양측 동일 — correctness 무관, 순수 perf 델타.
- **판단**: #124 픽스처 정비가 만든 회귀 아님 — 기존 기록된 tree-wide 회귀(#65 w5: SORT 이중 물질화·work_mem 상한 prefix vs develop 512MB 캐시·미이주 연산자 raw-fd mutex)의 노출. narrow 8/8 ≤1.05×(#107 충족)와는 별개 형상(hash join + NULL 확장 / CTE self-join).
- **처분**: record — perf 회수 트랙(#111 holdable zero-copy, #123 accountant+배치 spill, Phase3 이중기계 삭제) 진행 후 동일 3픽스처 재측정 가치. **#74 상신 자료에 포함**(Phase3-EXIT 기준 자체는 heavy DISTINCT/PSORT ≤1.10×로 별개임을 명시).
- Evidence: #124 완료 보고(측정 표), 커밋 `712c7243c`.

## K-12. #123 HLS_SPILL 병렬 probe 공유 커서 race — 판별표 정정 + LEFT-outer 허위 안전 (2026-07-03, #127 후속)

- **정정**: #127 원보고의 "회귀 = 47fcc321f 머지 유입" 귀속은 위음성 기반 오판. fable 재판별에서 remote tip `1dfcef7a7` **FAIL 3/3**, pre-merge `6b3d5775a` FAIL, merge 창 9파일 bisect 전부 FAIL → merge 무혐의. 진범 = **#123(`6b3d5775a`) 자신이 도입한 HLS_SPILL의 probe 커서/페이지버퍼/scratch 객체 내장** → 병렬 probe 8워커가 포인터 공유 race → 해시 match ~95% miss(readkeys serial 5,119,999 vs parallel ~30만) → unmatched 대량 방출(총행수 보존 = NULL-extended 재배치).
- **LEFT-outer 허위 안전**: 1:1 조인 + a측-전용 집계에서는 match miss가 md5에 불가시(LEFT도 readkeys ~29만으로 동일 붕괴). → parity 판정에 **readkeys(match율) 동반 확인** 필요 — 하네스 가드 추가 제안(#74 상신 자료 하네스 항목).
- **수정**: `62fc99923` per-context `HLS_SPILL_CURSOR` 분리(5파일 +160/−52), readkeys 완전 복원 + release outer_join 8/8 무오차. 잔여 검증(debug 반복·기존 PASS 세트·G1~G22·selftest)은 사용자 결정으로 축소 → #81 sweep preflight 이관.
- **교훈**: (i) 비결정 race 판별은 단회 PASS를 믿지 말 것(반복 N회 필수 — .33 단회 PASS가 오귀속의 뿌리). (ii) 오진도 확정 기록을 이긴다(K-10 재확인). (iii) 착지 검증이 race를 발현 못 시키면 latent로 통과한다 — 병렬 소비 신설 시 공유 mutable 상태 감사 필요.
- Evidence: #127 후속 작업 보고(판별표·bisect 표·정량), 커밋 `62fc99923`, 증적 `~/dev/cubrid-workmem/.claude/scratch/wm127f/`.

## K-13. order_wide 1.17×/write 1.94×의 귀속 — 스필 기계 무결, #65 w5 구조 확정 + cap 64MiB 고정 발견 (2026-07-05, #140)

- **분해**(strace 파일별, 로컬 재구성 wmwide): 신판 2,686MiB = pgbuf temp 1,500 + 입력 tape 619 + 출력 tape 567 (+page_spill **0**). 물질화 횟수는 develop과 동일 구조(입력1·런1·머지2·출력1) — 신판 고유 추가 기록 0, tape 이중쓰기 0, fetch 재물질화 0.
- **반증 실험 2종**: pgbuf first-unfix 훅 off → 완전 동일(기각). cap 1GiB 상향 → write -21%(출력 tape 전량 membuf 흡수)에 **시간 불변** — 시간 회귀는 write가 아니라 **CPU 1.63×**(입력 tape read-back 경로).
- **발견**: `init_accountant()`가 PRM_ID_WORK_MEM을 미참조 — cap = clamp(data_buffer/8, 64MiB, 4GiB), 캠페인 conf에서 **64MiB 고정**. degrades 전수 백트레이스: 리스트 open마다 degrade(13/13) + tape prefix 배치 예약 실패(12).
- **귀속**: (b) #65 w5 구조(develop 512M pgbuf 흡수 vs 신판 write-through tape + 거대런 thrash)의 실측 확정판. 스필 기계((a)/(c)) 무결.
- **처분**: order_wide 시간·I/O는 #65 w5 perf 트랙 이관(수정 방향 3건 기록: cap의 work_mem 존중 / tot_buffers pgbuf 협조 / read-back CPU 절감). cap 정책은 #91 재론 사안 — EXIT 전 수정 금지.
- Evidence: #140 보고(분해표·백트레이스·실험), 증적 `~/dev/cubrid-workmem/.claude/scratch/wm140/`.
