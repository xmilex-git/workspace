# temp-workmem 재설계 (#69~#81) 종합 리뷰 보고서

작성: 2026-07-02, 리뷰 기준: `~/dev/cubrid-workmem` @ `25ba22327` (`wm-integ-7173-develop`), base `a25a6b6d4` (develop)
리뷰 방식: 7개 병렬 영역 리뷰(백킹 코어 / 스캔계약 / PHJ / 정렬·생명주기 / 성능 구조분석 / 이슈-코드 대사 / 하네스 유효성), 전부 정적 분석 — DB 실행·VTune 미수행(측정 계획은 §6).

---

## 0. TL;DR

1. **Phase1(#69~72)은 코드로 검증된 진짜 완료.** 서버 내부 소비자(스캔/병렬 리더/fan-in) 기준으로 Tapeset 기계는 견고하다 (chunk 분배·overflow first-page-owner·freeze zero-copy 모두 검증 통과).
2. **그러나 게이트 기본 ON(#80)은 치명 결함 위에서 켜졌다.** 최상위(클라이언트 가시) ORDER BY/DISTINCT/GROUP BY 결과가 NEW-backed가 되는 순간 **클라이언트로 전송할 방법이 없다** — release는 조용히 0행, debug는 assert (R1). 기존 검증이 전부 "집계 1행(OLD 유지)" 형태라 못 잡았다. **csql 한 줄로 1분 안에 확인 가능.**
3. 그 외 확정 버그: PEEK-overflow 힙오염(R2), close 무음 실패=silent truncation(R3), freeze OOM 누수(R4), 공유 readbuf 스캔 오염(R5), PHJ split OLD 병렬 행유실(R6), NEW 좌표 VPID-punning 2계열(R7), buffile 크래시 고아 영구 누수(R8), E-1 잔여 UAF(R9) 등.
4. **하네스는 확정 버그 8건 중 0건을 잡을 수 있는 상태.** "pgbuf-bypass 하드게이트"는 증가 코드가 없는 카운터의 `assert(0==0)`, parity.sh는 단수 `1 row selected.` 미파싱으로 정본 쿼리에서 항상 위양성 FAIL, 에러 경로 주입 테스트 0개.
5. **"develop(pgbuf_fix 지배)보다 왜 안 빠른가"의 답**: pgbuf fix/unfix는 페이지당 ~0.5µs = 튜플당 3~7ns에 불과(VTune 1위는 '폭'과 '경합'의 산물). 진짜 병목은 (a) SORT의 **이중 물질화**(중간 런은 여전히 OLD pgbuf, 최종 출력만 NEW 재기록), (b) develop의 512MB 공짜 RAM temp 캐시 vs NEW의 work_mem 상한 prefix, (c) 미이주 연산자의 raw-fd per-tuple mutex 잔존, (d) 리더 병합의 튜플 단위 전량 재복사. PHJ 5×는 I/O 승리가 아니라 **병렬화 해금**.
6. SSOT는 방향 유지 장치로서는 우수하나 **이중 소스(GitHub #75 vs 로컬 파일) 드리프트**, 코드와의 모순(게이트 기본값, E-1 상태), acceptance 과장(#72 세션kill, #71 하드게이트), ADR0001("reparent 복사 없음") vs 코드(materialize 시도, 그마저 tapeset-blind) 괴리가 누적됐다.

---

## 1. 진행상황 리뷰 (이슈 ↔ 코드 대사)

| # | 상태 | 판정 | 비고 |
|---|---|---|---|
| 69 accessor-shim | CLOSED | **완료-검증** | 직접 필드 접근 잔존 0 (grep 검증) |
| 70 스캔계약 | CLOSED | **완료-검증** | G1~G6 합성 게이트 실재·판별력 있음 |
| 71 BufFile+Option-A+TDE | CLOSED | **완료-검증(주석付)** | pgbuf-bypass "하드게이트"는 동어반복(§4) |
| 72 holdable reparent | CLOSED | **완료-주장(프록시 검증)** | 실제 WITH HOLD 커서/세션 kill이 아닌 synthetic 직접호출 검증 — 실물 경로는 R1/R12에서 깨짐 |
| 73 Phase2 인프라 | CLOSED | **재범위화로 정당** | 본체는 #78로 이관(본문 체크리스트만 보면 오독 위험) |
| 74 Phase3 CONTRACT | OPEN | **미착수(정당)** | 진입 차단 갭 §1.1 |
| 78 producer 이주 | OPEN | **부분** | (a)(b)(g) 부분, (e) no-mixed live assert 미배선, (f) 미착수 |
| 79 E-1 감사 | OPEN | **부분-완료** | 수정 실재하나 scan_ptr 체인·per-row clear 미커버(R9), 회귀 테스트 없음 |
| 80 게이트 기본 ON | OPEN | **조건 미충족 선행** | 5조건 중 full-suite 미실행, gates-ON parity 10군 중 6군만 |
| 81 2A-EXIT sweep | OPEN | **미착수** | 스팟체크에서 실위험 확인(§1.1-2) |
| 75/76 SSOT/Evidence | OPEN | **드리프트** | §7 |

### 1.1 Phase3 진입 차단 갭 (우선순위순)

1. **R1 클라이언트 싱크 부재** — 사실상 게이트 ON 자체의 성립 조건. 최우선.
2. `external_sort.c:5606` — **병렬 GROUP_BY/ANALYTIC 정렬 입력에 NEW 분기 없음**(무조건 OLD sector scan; NEW 입력이면 가드 에러, OLD 입력이면 행유실 리더 도달).
3. full-suite(CTP SQL+shell) 게이트 ON 미실행; gates-ON parity 잔여군(UNION/OUTER JOIN/MERGE JOIN/CTE/CONNECT BY).
4. P2 출력 이주 7사이트(머지조인 C-1/2, UNION C-3, CTE C-6, analytic C-7/8, HJ ST C-15) — 이들이 OLD 리더에 계속 공급.
5. #77 판정(이주로 해소/재현/Phase3 삭제) 미확정 — `query_hash_scan.c:658-663`의 `tuple_size>0` 가드는 여전히 없음.
6. no-mixed live assert(또는 acceptance를 entry-guard 하이브리드로 공식 개정).
7. SSOT/evidence 동기화(§7), 하네스 untracked 파일 커밋.
8. raw-fd 레지스트리/per-tuple dirty-mark는 미이주 연산자 스필에서 **여전히 live** (`LEADER_VERIFIED_ENABLE_RAW_FD_WRITES=true`, temp_page_store.cpp:91).

---

## 2. 확정 버그 (심각도순, 전부 file:line 검증됨)

> 표기: [C]=CONFIRMED(코드로 확정), [V]=VERIFY(런타임 확인 필요). 좌표는 HEAD `25ba22327` 기준.

### R1 [C] CRITICAL — NEW-backed 최상위 결과는 클라이언트로 전송 불가 (0행/assert) + 결과캐시 오염
- 경로: `qfile_sort_list_with_func`(list_file.c:5232, `do_close && gate`)·GROUP BY 출력(query_executor.c:5481/21005)이 **최상위 리스트도 무조건 NEW 전환** → frozen NEW 리스트는 `first_vpid=NULL` → 클라이언트 fetch `xqfile_get_list_file_page`(list_file.c:2574-2700)는 VPID 전용(debug assert @2626), 클라이언트 커서 `cursor.c:1494`는 `VPID_ISNULL`→즉시 `DB_CURSOR_END`.
- 3개 Class-B 싱크의 `qmgr_materialize_to_pgbuf`(query_manager.c:3659)는 `qmgr_list_has_raw_fd_segments`(:3209, RAW_FD_OVERFLOW 전용)만 보고 **tapeset-blind → no-op**: 클라이언트 fetch(:1501), 리스트캐시 publish(:1863, 이후 :1869의 tfile-NULL로 duplicate도 skip → **백킹 없는 캐시 엔트리** = 캐시 히트마다 영구 빈 결과), holdable 커밋(:2637).
- 못 잡은 이유: 검증 쿼리가 전부 집계(최상위=1행 BUILDVALUE, OLD 유지). parity는 양쪽이 똑같이 비면 통과.
- [V] 1분 검증: 게이트 기본 상태로 `csql -u dba <db> -c "SELECT * FROM some_table ORDER BY 1"` (다행 테이블) → 0행이면 확정.
- 수정 방향(택1+보완): (i) 단기 — 최상위/`QFILE_FLAG_RESULT_FILE`/holdable/cache 후보 리스트는 `make_new_backed` 제외(클라이언트-가시성 항을 게이트 술어에 추가), (ii) 본설계 — tapeset→VPID materialize-at-sink 구현(`qmgr_materialize_to_pgbuf`에 tapeset 분기) 또는 wire 프로토콜에 tapeset 서빙 추가. 캐시(:1863)와 holdable(:2637)도 동일 분기 필요.

### R2 [C] CRITICAL — PEEK로 빌린 포인터에 `db_private_realloc` → 힙 오염
- `qfile_tape.cpp:466`(retrieve overflow 재조립), `:517`(copy), `:826/:845`(reader emit/reassemble): 레거시 `qfile_reallocate_tuple`의 "size==0이면 fresh alloc" 가드 누락. PEEK 후(`tpl`=페이지 내부 포인터, `size`=0) overflow 튜플을 만나면 빌린 포인터를 realloc.
- 팀이 동일 계열을 정렬 리더에서 이미 수정(list_file.c:4316-4318 주석)했으나 스캔 4사이트는 방치. 추가로 PEEK-overflow가 caller record에 할당(레거시는 scan 소유 `tplrec`) → 계약 위반 + 누수.
- 수정: 4사이트에 `size==0 → alloc` 패턴 복원 + overflow-PEEK을 scan 소유 버퍼로.

### R3 [C] HIGH — `qfile_close_list`가 NEW 경로 실패를 삼킴 → silent truncation/empty
- list_file.c:1403-1421: 마지막 페이지 `(void) qfile_producer_append(...)`, freeze NULL 리턴 미보고(void 함수). writer에 실패 플래그도 없어 **append 실패 후 freeze는 성공** → `tuple_cnt`는 그대로인데 행이 모자란 결과, 에러 0.
- ENOSPC 시나리오: 대형 ORDER BY 꼬리 스필 실패 → 조용히 잘린 결과. OLD close는 실패 불가였으므로 NEW 전용 회귀.
- 수정: writer에 sticky error + `qfile_close_list`에 에러 리턴(또는 list에 failed 마크 → 스캔 open 시 er_set).

### R4 [C] HIGH — freeze OOM 경로: SERVER_MODE `new`는 noexcept(NULL) — 수정이 무효
- `memory_wrapper.hpp:55-58,88`의 `operator new`는 NULL 반환. `qfile_tape.cpp:322-328`: `new buffile_tape` NULL이어도 `m_buffile=NULL; m_prefix.clear()` 무조건 실행 → **fd+스필파일+prefix(최대 work_mem) 전량 누수**. tiny 경로 `:308` `new memory_tape` NULL 체크 없음 → NULL-deref. `qfile_producer_freeze_tapeset`(:1594)·`tapeset_scan`(:1074)도 동일. (`buffile::create`는 체크함 — 코드베이스가 이 계약을 알고 있음.)
- 수정: NULL 체크 + 실패 시 소유권 원상복구(writer가 계속 소유 → dtor가 정리).

### R5 [C] HIGH — tape 소유 공유 `m_readbuf`: 같은 리스트 위 2개 스캔 인터리브 시 무음 오염
- `qfile_tape.hpp:174-175`, `qfile_tape.cpp:157-177`: R1 스캔의 파일 페이지 스크래치가 per-scan이 아닌 per-tape. 같은 스필된 NEW 리스트에 스캔 2개(단일 스레드 인터리브로 충분 — NEW-backed 파생테이블/CTE self-join)면 서로 페이지 덮어씀. (R2 reader는 per-reader 스크래치라 안전.)
- 수정: 스크래치를 `tapeset_scan`으로 이동, `page_at`을 caller-scratch 재진입형으로(ADR0005를 R1에도 적용). 부수효과: tape 완전 불변 → frozen=shareable 모델 정합.

### R6 [C] HIGH — PHJ **split** 경로에 OLD-입력 가드 부재 → 행유실 sector reader 병렬 실행
- probe에는 가드 존재(query_hash_join.c:2128-2134, d9ad680ad), split `hjoin_try_parallel`(:1970-2059)에는 없음. OLD-backed 입력(중첩 해시조인 결과 — NEW producer가 아님; 워커풀 고갈 fallback; mixed outer/inner)이 `px_hash_join.cpp:110-118/:227-235` → `sector_page_iterator`(list_file.c:4080) 병렬 워크 → **기본 설정에서 silent wrong result**.
- 수정: probe 가드 미러링(OLD 입력 → serial split) 또는 per-relation serial fallback. 부속: `CUBRID_WM_HASHJOIN_NEW=0`이 split엔 무효인 게이트 계약 위반(px_hash_join.cpp:86/204가 gate 미참조)도 함께.

### R7 [C] HIGH — NEW 좌표의 VPID-punning 2계열 (tape_idx 유실)
- (a) hash list scan HYBRID/HASH_FILE: build 시 `qdata_alloc_hscan_value_OID`(query_hash_scan.c:700-712)가 tapeset 스캔의 synthetic mirror `curr_vpid`(volid=NULL_VOLID, pageid=tape 상대 offset — `qfile_tape.cpp:1040-1054`, **tape_idx 소실**)를 VPID로 저장 → probe `qfile_jump_scan_tuple_position`(list_file.c:6125)이 union을 tape 좌표로 재해석 → `ER_QPROC_UNKNOWN_CRSPOS` 또는 **엉뚱한 tape**. cleanup(scan_manager.c:9095/9134)은 malloc'd tape 페이지를 pgbuf unfix. `check_hash_list_scan`(scan_manager.c:9175)에 backing 체크 없음 — 엔트리 가드 사각.
- (b) ORDER BY/DISTINCT partial-key(`use_original=1`): `qfile_initialize_sort_key_info`(list_file.c:4939)에 NEW-입력 가드 없음(GROUP BY :5682·ANALYTIC :21612에는 있음) → Tapeset 입력에 VPID 역참조 방출.
- 발견 못한 이유: work_mem=1G 테스트에선 HYBRID 창(`page_cnt*16K > work_mem && entry ≤ work_mem`)이 안 열림.
- 수정: (a) NEW-backed build 리스트는 IN_MEM/파티션 강제 또는 `QFILE_TUPLE_SIMPLE_POS`에 TAPE 좌표 확장(save_position 사용), (b) :4939에 `qfile_list_has_new_backing → use_original=0` 가드(기존 2사이트와 동일 패턴). 공통: `qfile_tuple_position_store_to_db`(query_list.h:792-815)에 TAPE→VPID 저장 assert 추가.

### R8 [C] HIGH — buffile 크래시 고아 파일 영구 누수 (orphan-zero 불변식 위반)
- 생성: `<scratch>/cubrid_buffile/buffile_<seq>_w<wid>_p<pid>.tmp`(qfile_buffile.cpp:296-329), unlink는 dtor뿐(:250-263). 부트 스윕(`initialize_raw_fd_boot_sweep` → temp_page_store.cpp:455-489)은 raw-fd 네임스페이스만. `cubrid_buffile` 참조는 생성부·유닛테스트뿐(grep 확정) → kill-9/크래시 시 스필 파일 영구 잔존, 반복 크래시로 디스크 고갈.
- 부속: `default_scratch_dir`(:266-294)의 최후 fallback이 `/tmp` — tmpfs 호스트에서 스필=RAM 소모(이 저장소 하우스룰과도 충돌).
- 수정: raw-fd와 동형의 부트 스윕 추가(+ 서버 인스턴스 식별자 포함 네이밍), fallback 순서 재고.

### R9 [C] HIGH — E-1 수정 잔여: destroy-while-reader-live 2계열
- (a) `qexec_clear_xasl`(query_executor.c:2394-2428): E-1은 자기 노드 `curr_spec`/`merge_spec`만 선-close 후 aptr 자식(과 그 tapeset)을 파괴하고 **그 다음** scan_ptr 체인 재귀 — scan_ptr 스캔이 aptr의 NEW 리스트를 보던 중 에러/인터럽트면 close가 죽은 tapeset을 참조(UAF; `tapeset_scan::close`→`release_page`가 `m_tapeset->get_tape()` 접근, qfile_tape.cpp:401-413). `qexec_clear_xasl_for_parallel_aptr`(:2942-2953)도 동일 구조.
- (b) 행 단위 클리어: `qexec_clear_head_lists`(bptr/fptr, :8641/:8714)는 스캔 close 없이 destroy; dptr `qfile_truncate_list`(list_file.c:3560-3601)는 **tapeset을 아예 안 건드림**(UAF는 아니나 tapeset-backed dptr 재사용 정합성 구멍).
- 수정: (a) 전체 spec 트리 close를 destroy보다 선행(또는 tapeset 참조 카운트), (b) truncate에 tapeset 리셋 추가 + bptr/fptr 클리어 전 소비 스캔 종료 보장 감사. E-1 회귀 테스트 부재도 해소.

### R10 [C] MED — `qfile_tapeset_import` 이중해제(OOM)와 dangling src
- qfile_tape.cpp:1541-1567: append 루프 후에야 `set_owns_tapes(false)` — 루프 중 `push_back` bad_alloc 시 0..i-1 tape 양측 소유 → 이중해제(또는 C 프레임 관통 예외→terminate). import 후 src 벡터에 unowned dangling 포인터 잔존, self-import 가드 없음.
- 수정: tape 단위 소유권 이전(move-and-null) 또는 사전 reserve + 예외 경계.

### R11 [C] MED — NEW 경로가 work_mem 거버너를 완전 우회
- `qfile_producer_create_for_list`(qfile_tape.cpp:1527-1531): producer마다 `work_mem/DB_PAGESIZE` prefix를 **계정 없이 plain malloc** — 레거시 membuf는 accountant(cap=min(max(buf/8,64M),4G)) 예약·degrade. 병렬 질의 1개가 degree×work_mem + dest work_mem 무계정 RSS; work_mem=1G 캠페인 conf에서 OOM-by-design. PHJ도 컨텍스트마다 full work_mem 예산(query_hash_join.c:2695) — degree× 증폭.
- 부속: lazy pool free-list 100개 유지(query_manager.c:73,4543) → 버스트 후 최대 100×work_mem 상주; NEW 리스트마다 "1G membuf 생성→즉시 pool 반환" 낭비 사이클(query_manager.c:3735-3741 → list_file.c:5173-5178).
- 수정: prefix 예산을 accountant에 연동(soft 예약+degrade), pool 상한을 바이트 기준으로, make_new_backed 예정 리스트는 membuf 생성 skip.

### R12 [C] MED — holdable: 설계-코드 괴리 + 무잠금 핸드오프 창
- ADR0001 "reparent, 복사 없음" vs 코드: 커밋 시 `qmgr_materialize_to_pgbuf` **복사 시도**(query_manager.c:2637) — 그마저 tapeset-blind no-op(R1) → NEW holdable은 포인터 이동으로 세션 생존은 하나 **커서는 0행**(R1과 동일 원인). 세션 만료 정리는 정상(session.c:2565-2585).
- tran→session 핸드오프가 `tran_entry_p->mutex` 밖(query_manager.c:2616→2643 사이): 엔트리가 어느 스코프에도 없는 창 — `file_temp_preserve` 전 동시 정리와 경합 가능 [V: ASAN + holdable commit×세션kill 루프].
- 수정: R1 싱크 수정에 편승 + 핸드오프를 잠금 하 또는 2단계 게시(publish-then-unlink)로.

### R13 LOW 묶음
- `px_hash_join.cpp:170-181/:281-292` 병합 실패 시 destroy된 워커 리스트 슬롯 미-NULL → 잠재 이중 destroy. OLD split overflow 에러 삼킴(px_hash_join_task_manager.cpp:512-521).
- `buffile_metrics.pages_read` 죽은 카운터(qfile_buffile.cpp:509,542는 `m_reads`만 증가); scan `pgbuf_fixes` 증가 사이트 0(동어반복 게이트).
- `page_at` 실패 시 er_set 없음(qfile_tape.cpp:168-171) → "unknown error"; `ensure_buffile`이 EMFILE/ENOSPC 구분 소실(:257-264).
- NEW producer 페이지 루프에 interrupt 체크 누락(list_file.c:1551-1590) — 대형 스필 취소 지연 [V].
- `qfile_copy_list_id`가 `producer_writer_`를 그대로 복사(SKIP/PROHIBIT에서 미-NULL) — 현재는 규율로만 안전(list_file.c:471, :654-658).
- DISTINCT가 게이트 OFF에서도 result-file로 라우팅(list_file.c:1280-1283) — "env=0이면 OLD 복원" 계약 위반 [V].
- `hjoin_init_manager`가 `QFILE_NOT_USE_MEMBUF` 드랍(query_hash_join.c:806-807) → env-OFF에서도 connect 병합 사실상 사멸 — 미문서 결정.

---

## 3. 검증 필요 항목 [V] (수행 레시피 — 실행은 하지 않았음)

| 항목 | 실행 | 관찰/판정 |
|---|---|---|
| R1 확정 | 게이트 기본 상태에서 `csql -c "SELECT * FROM t ORDER BY 1"` (다행) | 0행 → 확정. debug 빌드면 list_file.c:2626 assert |
| R6 재현 | work_mem 축소(64M)+`(t1 JOIN t2) JOIN t3` 파티션 유발, serial 대조 | count 불일치 → split 행유실 확정 |
| R7(a) 재현 | HYBRID 창: NEW-backed 파생리스트(정렬/DISTINCT) build + `page_cnt*16K>work_mem` | UNKNOWN_CRSPOS 에러 또는 오답 |
| R5 재현 | `CUBRID_WM_SORT_NEW=1`, 소 work_mem, NEW CTE self-join, `=0` 대조 | 결과 diff → 확정 |
| R12 창 | ASAN, holdable commit × 동시 세션 kill 루프 | UAF 리포트 |
| worker 에러 정리 | 병렬 정렬 중 워커 fault-inject | `tape_backing_census` baseline 복귀 여부 |
| P3 sentinel | reader `read_page_into` fault-inject | 태스크 spin 여부(px_scan_input_handler_list.cpp:152-163) |

---

## 4. 하네스 유효성 평가 (요약 — 상세는 리뷰 원본)

| 레이어 | 판정 | 핵심 근거 |
|---|---|---|
| robust-parity(parity.sh) | **부분유효+파서 결함** | `result_rows()`가 복수형 `rows selected`만 매칭 → 단일행 집계(정본 형태)에서 trace가 md5에 유입, **기록된 위양성 FAIL 실재**(results/parity.wmloc_distinct…proof.txt). 병렬 실증은 예약 시점 수치라 이후 per-operator serial fallback 못 잡음; serial 레그의 워커=0 미검증; **NEW 경로가 실제 돌았는지 아무것도 증명 안 함**(게이트 거부→OLD 폴백이어도 PASS) |
| 집계 방법론 | 부분유효 | 행유실/중복은 잡음(bug2 실적). **정렬 순서는 구조적으로 검증 불가**(sort 후 md5), VARCHAR 단byte 오염·NULL flip 미커버 |
| unit G1~G18 | **부분유효** | 스캔 기계·소유권 census는 진짜 판별력(G15/16의 anti-tautology 패턴 우수). 단 pgbuf_fixes==0은 전 사이트 동어반복, G14(b)(c) CoV는 산술 필연, **에러 경로 주입 0**, PEEK×overflow 조합 미실행, 인터리브 이중 스캔 미실행. 유닛 스크래치가 `/tmp`(하우스룰 위반) |
| in-server selftest | 부분유효·비게이팅 | 실물 API를 몰긴 하나 `qmgr_initialize`가 **리턴코드 폐기**(query_manager.c:1178-1189, FAIL이어도 부트 green), debug 전용, 실행법은 untracked 문서에만. #72의 "세션 kill"은 직접 teardown 호출(프록시) |
| metrics/census | pgbuf_fixes 동어반복 / census 유효-협소 | census는 writer-held prefix 미계상 + in-process(크래시 고아 표현 불가). statdump 미노출 → e2e 게이트 불가 |
| **버그 매트릭스** | **0/8** | 확정 버그 전부가 "에러 경로/실물 싱크/인터리브"에 있고 하네스는 전부 happy-path/프록시/집계 |

**개선 우선순위(요약)**: ① parity 파서 수정+양방향 검증+NEW-engagement 카운터 게이트(A~E old_touch statdump 노출) ② pgbuf_fixes 실배선(pgbuf_fix에 TLS 카운터) or 삭제 ③ ENOSPC/OOM fault-injection 훅+테스트(R3/R4 커버) ④ 인터리브 이중스캔·PEEK-overflow 유닛 게이트(R5/R2 커버) ⑤ 실물 e2e: WITH HOLD·query cache ON·대형 클라이언트 fetch·상관 서브쿼리(R1/R9 커버) ⑥ kill-9 부트스윕 테스트(R8) ⑦ work_mem 상한 게이트(R11) ⑧ untracked 하네스 커밋+CI 배선 ⑨ ORDER BY용 순서보존 비교 모드+NULL/VARCHAR 픽스처.

---

## 5. 성능 분석 — "develop(모든 페이지 상주, pgbuf_fix/unfix 최고 부하)보다 왜 빠르지 않은가"

### 5.1 비용 모델 (16KB 페이지 기준, 정적 분석)

| 경로 | 페이지당 비용 | 튜플당 상각(~150tuple/page) |
|---|---|---|
| OLD pgbuf RAM 히트 (fix+unfix, 해시체인+래치) | ~0.2–0.4µs, syscall 0 | **3–7ns** |
| NEW prefix(RAM) 쓰기 | malloc+16K memcpy ~0.4–1.5µs | ~5–10ns |
| NEW prefix 읽기 | 포인터 반환 ~0 | ~0 |
| NEW BufFile 쓰기 | memcpy+1/8 pwrite(128K 배치) ~1–2.5µs | ~10–15ns |
| NEW BufFile 읽기 | **페이지당 pread 1회**(배치/readahead 없음), 캐시히트 ~1–2.5µs | ~15ns |
| 잔존 raw-fd 쓰기 | shard mutex 2–3회+16K 단건 pwrite ~3–6µs + **per-tuple dirty mutex** | 튜플당 50–100ns+경합 |
| TDE(fd 경로) | +페이지 전체 AES 5–15µs (+read 시 불필요 memcpy 1회, qfile_buffile.cpp:541) | +30–100ns |

**핵심**: pgbuf fix/unfix는 *페이지당* 비용이라 튜플당 3~7ns — 튜플당 공통 작업(비교/해시/qdata 평가 100~500ns)의 오차 범위. **VTune에서 pgbuf_fix가 1위인 것은 (i) 모든 서브시스템이 지나가는 '폭', (ii) 병렬 경합 — 단일 스트림 히트 비용이 아니다.** 따라서 pgbuf를 완벽히 제거해도 CPU-bound 질의에서 수 % 이상 못 번다. NEW의 구조적 승리는 **경합 제거**(private fd + 64페이지당 atomic 1회)이고, 그게 병렬에서만 돈이 된다 — PHJ 5×(4.26s vs 21.2s)가 정확히 그것(develop은 해당 경로 serial + OLD sector reader 회피 목적의 강제 직렬화; I/O 승리 아님).

### 5.2 지는 지점 (기여 순)

1. **이중 물질화 [최대]**: SORT의 초기 런·머지 패스는 여전히 OLD pgbuf 스크래치(`sort_write_area`/`sort_read_area`/`file_create_temp_numerable` — external_sort.c:5993/6041/4383, 미게이트), 최종 머지 파일을 pgbuf로 재독 후 `sort_put_result_from_tmpfile`(:3327/:3363)이 **튜플 단위로 NEW tape에 재기록** → 스필-바운드 정렬 출력을 2회 쓰고 1회 더 읽음 = **+50~100%** (역대 +70% 회귀와 동일 규모). PHJ도 리더 병합이 tape import가 아닌 `qfile_append_list` 전량 재복사(2× 증폭+직렬; ADR0004 미완).
2. **RAM 계층 비대칭**: develop은 512MB 데이터버퍼 전체가 temp 캐시(상주 시 syscall 0). NEW는 producer당 work_mem까지만 prefix — 그 사이 페이지 전부가 0-syscall 히트→2~5µs syscall+복사(OS 페이지캐시 히트여도)로 강등. working set이 (work_mem, 512M] 구간일 때 선형으로 손해.
3. **잔존 raw-fd**: 미이주 연산자(P2 7사이트+P3 9사이트)의 qmgr temp가 membuf 초과 시 per-tuple shard mutex + 페이지 단건 pwrite — e21917cfd 회귀 기제가 그대로 (#62의 원인이 부분 잔존).
4. **읽기 배치/readahead 부재**: 페이지당 pread 1:1(PG는 머지 레이어에서 tape당 256KB preread + 연속 사전할당). 순차 단독 스캔은 커널 readahead가 구제하나, 멀티-tape 머지 인터리브·R2 64페이지 스트라이드 공유 fd에서 약화. 캐시 콜드 시 장치 순차/랜덤 격차만큼 손해.
5. 부차: 재스캔(NL-join 내부) 시 pgbuf 캐시 없이 매 패스 pread+decrypt; branch의 pgbuf temp victimization 변경(page_buffer.c:6787-6812)이 gates-OFF에서도 OLD 스크래치를 develop보다 evict되기 쉽게 함; overflow run 첫 페이지 2회 읽기(감지+재조립).

### 5.3 결론
- 예측: 현 NEW 경로는 raw-fd보다는 낫지만, **spill ≫ work_mem이면서 ≲512M인 구간에서는 develop에 계속 진다**(요인 1+2). working set이 512M도 초과하면(양쪽 다 스필) 수렴~역전 가능(NEW는 배치 쓰기+풀 오염 없음).
- heavy-spill 목표(`median ≤ develop×1.10`, #74 EXIT)는 **요인 1(이중 물질화) 제거 없이는 달성 불가** — 정렬 중간 런/머지의 NEW화(logtape 모델의 본체)가 Phase3 아닌 성능 필수 경로임을 SSOT에 명시할 것.

---

## 6. 측정 계획 (실행은 추후 — 목적/명령/기대 시그니처/대처)

공통: 동일 데이터, 3구성 — develop / branch 게이트 ON / branch 게이트 OFF, `work_mem ∈ {64M,256M,1G}`, `data_buffer_size=512M` 고정, 각 쿼리 전후 `cubrid statdump` 델타. 게이트 env는 **서버 프로세스**에 주입(server-control 래퍼 env), PHJ는 cold 세션 프로토콜 불요((t) 수정 후) 단 재확인 1회.

1. **귀속 검증(왜 안 빠른가의 0번)**: VTune hotspots(user+kernel), all-RAM 워크로드, develop vs branch. 기대: develop의 pgbuf_fix+unfix 중 `qfile_*`/`qmgr_*` 호출 스택 기여는 수 % — branch에서 그 시간이 memcpy/`tape_writer::append_page`로 이동, 순변화 ≈ 0. **만약 gates-ON이 serial all-RAM에서 크게 이기면 모델 기각** → pgbuf 경합 재조사.
2. **syscall 세금**: `strace -f -c -e trace=pread64,pwrite64 -yy` — NEW 시그니처 = `buffile_*.tmp`에 128KB pwrite(스필페이지/8) + 16KB pread 1:1; raw-fd 잔존 시그니처 = 16KB pwrite 1:1. raw-fd 카운트 > 0이면 §5.2-3 해당 연산자 이주 우선순위 상향.
3. **work_mem 절벽**: 런타임 vs work_mem 플롯. develop=512M까지 평평, branch=working set≈work_mem에서 무릎. 무릎 좌측 격차가 크면 요인 2 확정 → prefix 예산/공유 캐시 재설계 검토.
4. **이중 스필 정량화**: `/proc/<pid>/io` write_bytes + `Num_sort_io_pages`(OLD 스크래치) vs buffile pwrite bytes. heavy DISTINCT에서 branch ≈ 2×(정렬 데이터), develop ≈ 1×(또는 0)이면 요인 1 확정 → 정렬 런/머지 NEW화 착수.
5. **readahead**: 캐시 콜드(`drop_caches`) vs 웜, `iostat -x 1` — avgrq-sz 소형+r/s 고 → 단페이지 읽기 확정 → chunk 클레임 시 `posix_fadvise(WILLNEED)` 추가.
6. **raw-fd 경합**: VTune threading, membuf 초과 파티션 유발 — `rawfd_find_and_mark_dirty` 대기시간, lock count ≈ tuple count면 per-tuple mutex 확정.
7. **가드 오버헤드**: gates ON vs OFF, 비스필 워크로드 — 격차 <2% 기대, 초과 시 per-tuple 경로 프로파일.
8. **LRU 상호작용**: branch gates-OFF vs develop 동일 OLD 경로 — 격차는 page_buffer.c:6787-6812 귀속, `Num_data_page_ioreads` 관찰.
9. **선행 작업**: buffile/tapeset 메트릭·census의 statdump 노출(현재 release에서 읽을 수 없음 — 위 실험 다수의 전제).

VTune: `/opt/intel/oneapi/vtune/latest/bin64/vtune -collect hotspots|threading -target-pid <cub_server>` 고정-duration attach(기존 evidence §F 관행 유지).

---

## 7. SSOT/거버넌스 적절성 평가

**잘 작동한 것**: §0 DO-NOT-REASSUME(오염 전제 배격)은 실제로 방향 회귀를 막았고, COMPACT-SAFE SUMMARY는 컨텍스트 절단에서 생존. PG 용어 정합(CONTEXT.md)·ADR 분리도 유효. 자기 정정 문화((k)~(v)의 오진 정정)는 모범적.

**문제**:
1. **이중 소스 드리프트**: GitHub #75 본문(정본으로 지정, #79~81이 "정독" 지시)이 UPDATE (o)~(v) 부재 — 실체 SSOT는 로컬 파일로 이동했는데 하위 이슈는 GitHub를 가리킴. evidence도 GitHub가 ~6엔트리 뒤짐.
2. **코드와 모순**: (j) "기본 OFF"(현재 ON), (v) "E-1 needs-investigation"(수정 landed), "18사이트=5+7+9"(합 21).
3. **acceptance 과장**: #71 "하드게이트"(동어반복), #72 "세션 kill orphan-zero"(직접호출 프록시), #80 완료 코멘트가 5조건→6군 parity로 조용히 축소.
4. **설계-코드 괴리 미기록**: ADR0001 zero-copy reparent vs 코드의 materialize(그마저 blind); ADR0004 per-worker tape "병합"이 실제로는 전량 재복사; "aggregate/analytic OLD 유지" vs GROUP BY 출력 NEW(무 do_close 조건).
5. **하네스 신뢰 근거의 순환**: "robust-parity green"이 게이트 문서 도처의 근거인데 parity 자체가 NEW-engagement를 증명 못 함(§4) — SSOT §6 불변식에 "NEW 경로 실증(카운터)" 항 추가 필요.

**권고**: SSOT는 "GitHub 이슈 = 정본, 로컬 = 미러(수정 시 즉시 코멘트 동기화)"로 단일화하고, 매 라운드 종료 체크리스트에 "게이트 술어/기본값 grep 대사"를 추가. acceptance는 "프록시 검증"과 "실물 경로 검증"을 구분 표기.

---

## 8. 구조 개선 제안 (버그픽스 이후)

1. **클라이언트/persist 싱크 설계(R1의 본질 수정)**: 게이트 술어에 "server-side-only" 항 도입 + Class-B 싱크에 tapeset materialize 분기. 장기적으로 wire에 tapeset 서빙(페이지 스트리밍) 검토.
2. **close/freeze 실패 계약**: `qfile_close_list`에 상태 리턴 또는 list failed 마크 — "close는 실패 불가" 시대의 void API를 NEW 계약에 맞게.
3. **R1 스캔 재진입화**: per-scan 스크래치(ADR0005 일반화) → tape 완전 불변.
4. **정렬 내부 NEW화**: 초기 런/머지를 BufFile/logtape로 — heavy-spill 목표의 필수 경로(§5.3).
5. **리더 병합 = tape import**: PHJ per-worker 출력·probe 결과를 재복사 대신 import(ADR0004 완성) — 2× 증폭 제거.
6. **메모리 계정 통합**: prefix 예산·PHJ 컨텍스트 예산을 accountant로, degree-aware 분할(PG처럼 operator가 예산 소유).
7. **관측성**: buffile/tapeset 메트릭+census statdump 노출, pgbuf_fixes 실배선, backing-kind 카운터 — parity의 NEW-engagement 게이트 전제.
8. **readahead**: chunk 클레임 시 fadvise, 머지 tape당 preread.
9. 잔존 정리: `qmgr_list_has_raw_fd_segments` 명칭(실의미: Class-B 물질화 필요 술어), dispatch 레벨 통일(tapeset은 wrapper, raw-fd는 내부 — 3백킹 2레벨), 중복 람다/리더 루프 3벌 통합(Phase3).

## 9. 후속 이슈화 예정 목록 (별도 진행)

P0: R1(클라이언트 싱크)+R2+R6+R7 / P1: R3~R5, R8, R9, full-suite+잔여 parity, external_sort.c:5606 / P2: R10~R13, 하네스 개선 ①~⑨, 측정 캠페인(§6), 정렬 내부 NEW화·리더 import(§8) — 각 이슈는 [CONFIRMED]/[VERIFY] 구분·자족적 재현/판정 절차 포함으로 작성.
