# temp-workmem 전면 개편 SSOT (단일 진실원)

Last updated: 2026-07-03 오후 KST (SYNC — Phase3 blocker 2종 해소(#117/#118/#119, #120a/#120b) 반영. 역사·측정·정정 기록은 #76 evidence 담당.)
**이 본문이 정본**이며 로컬 미러 = `~/dev/workspace/temp_workmem/issue65_ssot.md` (수정 시 둘 다 갱신). 모든 구현 이슈는 이 본문 기준.
우선순위(충돌 시): SSOT > evidence > 그 외. 상세 버그 좌표·재현 절차는 각 구현 이슈 본문이 자족적으로 담는다.

---

## 1. 목표 (불변)

CUBRID 임시 작업메모리/스필 경로를 **PostgreSQL work_mem 철학**(BufFile / logtape / SharedFileSet)으로 전면 개편한다 (#60/#65).

- 축1 (생명주기/백킹): 처리 중 데이터는 per-worker work 버퍼(work_mem) + 오버플로는 per-worker private append-only BufFile(pgbuf BCB 우회, 전역 레지스트리·per-page 락 없음, offset 산술 주소). transient는 질의 종료 시 폐기. 질의 수명을 넘는 것은 정확히 2클래스 — holdable(세션 이관), cached-persist(결과캐시 copy-out).
- 축2 (연결구조): `qfile_connect_list`(페이지 헤더 cross-file next_vpid 재링크) 폐기 → `QFILE_LIST_ID`에 Tapeset(순서 있는 Tape 벡터). 워커가 자기 Tape을 생산·freeze(불변), 리더/세션이 논리 import. 스캔은 (tape_idx, page_offset, tuple_offset) 단일 논리 스트림. 병렬 read는 64-page Chunk atomic work-stealing.
- 용어 = PG 정준어(`CONTEXT.md`): Tape/Tapeset/BufFile/Freeze/Import/SharedFileSet/Chunk. 구조 상세 = `docs/tape-model.md`, 결정 = ADR 0001~0006. holdable은 **materialize(복사)로 통일 착지**(#94) — zero-copy reparent는 명시적 후속 최적화(그때 ADR 0001 개정).
- e21917cfd의 raw-fd 전역 페이지 레지스트리 + per-tuple dirty-mark 락 + VPID connect는 **개편 대상**이며 Phase3(#74)에서 삭제된다.

## 2. 현재 상태 (2026-07-03 오전, `wm-integ-7173-develop` @ `ceb8997e8`)

**Phase1 (#69~#72) 완료 — 코드 검증됨.** accessor-shim / Tapeset 스캔계약 유닛 게이트 / per-worker BufFile + membuf Option-A + TDE / holdable MOVE 소유권 + census. 서버 내부 소비자 기준으로 Tapeset 기계(chunk 분배, overflow first-page-owner, freeze zero-copy)는 견고하다.

**Phase2 (#73/#78) 부분 완료.** 이주 완료: SORT 출력(직렬+병렬 fan-in), 병렬 SCAN per-worker 출력, GROUP BY 출력, PHJ probe/outer/split NEW-입력(chunk_distributor), per-worker 파티션 출력, **UNION ALL C-3(출력 NEW 승격) + CTE C-6(작업리스트 OLD demote — append-소비라 OLD가 정공법, #105의 형제)**(`43048f481`). P2 출력 이주 잔여 3사이트 완료(2026-07-03): 머지조인 C-1/2(#117 `c447d929b`), analytic C-7/8(#118 `b78578bad` — 출력 OLD 유지 판정 + NEW 입력 병렬 정렬 크래시 수정), HJ ST C-15(#119 `9232882ef`, 중첩 HJ 병렬 해금·#112 동시 close), GROUP_BY/ANALYTIC 병렬 정렬 NEW 입력 chunk_distributor(#122 `61e65c18e`). 미완: membuf 강제OFF 게이트(H-4) 제거는 Phase3로 이연, no-mixed live assert는 entry-boundary 가드로 대체 구현(connect/append/sector-scan/tapeset-open, production-hard).

**게이트**: `CUBRID_WM_SCAN_NEW / SORT_NEW / HASHJOIN_NEW` — **기본 ON**(`ceb8997e8`, 사람 GO 승인 2026-07-03; env 명시 `=0`으로 게이트별 OLD 강제 가능 — 진단용 opt-out). #82 롤백 사유(R1 클라이언트 0행)는 #94+C-3/C-6+#114로 해소, 플립 검증에서 R1 클라이언트-가시 실증 포함 재확인.

**2026-07-02 종합 리뷰(7영역)가 확정한 결함 — 착지 현황:**

| 이슈 | 내용 | 상태 / 커밋 |
|---|---|---|
| #82 | 0행 검증 → 3게이트 기본 OFF 롤백 | ✅ `303fcc6bc` |
| #83 | PEEK realloc 힙오염(4사이트) + 유닛게이트 | ✅ `0d851b6c9` (parity 부채는 Batch A에서 상환 중) |
| #84 | PHJ split OLD-입력 가드 | ✅ `d4f8ac0e2` |
| #85 | NEW 좌표 VPID-punning 가드 3건 | ✅ `01b41d602` (HYBRID 재현 부채 Batch A) |
| #86 | close/freeze 실패 계약 — silent truncation 차단 + ENOSPC fault-injection | ✅ `9adb89d26` |
| #87 | per-scan 스크래치 + tape 불변화 + G22 | ✅ `81ef3ed06` |
| #88 | buffile 부트 고아 스윕 + kill-9 회귀 + /tmp fallback 제거 | ✅ `86bb5b3f8` (kill-9 고아 4→0 실증) |
| #89 | E-1 잔여 destroy-vs-scan 순서 — truncate 리셋 + open-scan assert | ✅ `76b351561` (valgrind 0건 — #87 UAF 해소 실증, #79 감사 close 근거) |
| #90 | 하드닝 7건 | ✅ `1c8a23ebb`..`274fd3c07` |
| #91 | work_mem 계정 통합 + pool 바이트 상한 + lazy memset (PHJ -21%) | ✅ `80afc2752` `46ae966dd` `a767936e4` |
| #92 | parity 하네스 + NEW-engagement 카운터(`PSTAT_QF_*`) | ✅ `9757b24f1` `25df36357` |
| #93 | pgbuf_fixes 실배선 + selftest 게이팅 | ✅ `66343e69b` `5578d498c` |
| #94 | Class-B 3싱크 tapeset materialize 통일 | ✅ `92a55adc1` |
| #95 | freeze OOM 소유권 원상복구(#86 계약 위) + OOM injection | ✅ `0f85fd6d6` |
| #96 | holdable 핸드오프 — R12 두 방향 모두 반증, 실누수 수정 | ✅ `cac62d9a4` |
| #100 | NUMERIC GROUP BY 절단 — 전컬럼 확장 | ✅ `687a694b3` |
| #103 | ANALYTIC over NEW put-side A_sort_key (#102 흡수) | ✅ `43ee3c725` |
| #104 | statdump 신규 통계 크래시 | ✅ `adcc76adb` |
| #105 | CONNECT BY NEW 차단 가드 + release store 명시 에러 | ✅ `b9081226a` |
| #106 | lib.sh 활성 설치본 우선 + cubrid_rel proof | ✅ `5235ecdd6` |
| #98 | 성능 측정 캠페인 44-leg | ✅ 판정 완료(§3 P10) |
| #99 | QUERY_CACHE + 병렬 ORDER BY 절단 — **루트코즈 정정**: px 정렬 입력 sector scan이 raw-fd 오버플로 페이지 열거 불가(membuf prefix만 정렬). raw-fd 입력 직렬 가드 + sort-then-move | ✅ `9acdc6150` |
| #107 | spill 읽기 per-row pread 제거 — D1(raw-fd spilled 입력 전컬럼 운반) | ✅ `dd556d486` — pread 4.06M→62.9k(98.5%↓), **narrow 8/8 leg ≤1.05× (#80 성능 조건 최초 충족)**, #98 잔여관찰 2건 해소(0.96×) |
| #101 | TAPE 좌표 1급화 | ✅ `475e0ad6d` (HYBRID 해제; HASH_FILE 티어는 #123 `6b3d5775a`가 spill 대체와 함께 해제) |
| #109 | PHJ per-worker slot 배열 cross-thread private-heap free(ADR0004 위반) — 리더 할당으로 수정 | ✅ `68e341295` |
| #97 | full-suite gates-ON 캠페인 (7-shard ON/OFF 집합 차분) | ✅ 실행·판정 완료 close — **게이트 무죄**(귀속 17건 전부 P2 미이주의 클린 에러, 크래시·무음오답 0). `:5636` 도달불가 record-only. merge_join 무음오답은 게이트 무관 기존 결함(별도 이슈) |

**크리티컬 패스**: ~~#107~~✅ ~~#97~~✅ ~~C-3/C-6~~✅ ~~#114~~✅ ~~#80 기본 ON~~✅(`ceb8997e8`) ~~#81 sweep~~✅(판정: 삭제 집합 CLEAR, **Phase3 진입 BLOCK**) → **#74 상신(사람 승인 대기)**. Phase3 blocker 2종 **전부 해소**(2026-07-03): ①클라이언트 전송 materialize 의존 → #120a(`c1044fd5c`) + #120b(`2fafae2be`, overflow ADR0006 run→VPID 체인 실시간 번역, 단독 리뷰 통과·close) — `qmgr_materialize_to_pgbuf`는 holdable(#111)/캐시(#121)/raw-fd 전용 폴백으로 존치(#74 sweep 전 삭제 금지), 라우팅 census 카운터 `Num_qfile_client_fetch_serve/materialize` 신설(하네스-단언용) ②P2 잔여 3사이트 → #117/#118/#119. #121 착지(`0a4ea9ca9`, 리뷰 통과·close): 캐시 copy-out Tapeset-source 전환 — 캐시가능·overflow-free NEW는 단일 복사(FILE_QUERY_AREA 직타깃, 종전 이중 복사 해소). **#110 동반 close**(게이트 ON 발동 0/OFF 2회 대조 — 가드 삭제는 #74 체크리스트 이관). #111 착지(`ab3052e2b`, 리뷰 통과·close): holdable zero-copy reparent 복원(ADR 0001 개정 `8fb828a`) — 2점 수술(sink C materialize 스킵 + facade `!is_holdable` 해제), commit 경계 관통 바이트 동일·kill-9 orphan 4→0 실증. **Class-B 싱크 정리 완료**: `qmgr_materialize_to_pgbuf`는 캐시+overflow/holdable+cacheable/raw-fd 전용 폴백. #123 착지(`6b3d5775a`, 리뷰 통과·close): hash scan accountant 편입 + HASH_FILE→PG-style 배치 spill(`hls_spill`), fhs 기계는 #74 삭제 목록 편입, #85 NEW 가드 전면 해제(HYBRID+HASH_FILE). **[정정 K-12]** hls_spill에 latent 병렬 probe race 있었음(공유 커서 — `62fc99923`이 수정, #127 후속). 발견 부산물 #126 착지(`1dfcef7a7`, 리뷰 통과·close): 병렬 outer × raw-fd spilled build 동시 스캔 오염(pre-existing) — `px_join_has_raw_fd_list_scan` 직렬 강등 가드(NEW 무접촉, debug 20/20+release 5/5 무오차), 근본 수정 금지(기판이 Phase3 삭제 대상), **가드+호출부 2곳 제거는 #74 체크리스트 이관**. **잔여 경로 완주 → #74 재상신 → 사람 승인(2026-07-03 밤) — Phase3 실행 개시**: #129 착지(`635eec6e2`, 리뷰 통과·close — fhs 기계 -2,586줄 삭제, C4 절단선: `hls_spill_hash*` 리네임·enum/spill union 존치). #128(C1, .30 sonnet)·#130(sector 삭제 C3, fable) 병행 진행 중. **C2 = (c′) 채택**(#74 처분): buffile 클래스 직접 백킹은 하드 블로커 2건(append-only·페이지캐시 부재)으로 불가 → 파일 기판 공유 + random-page 변종 + per-tfile 캐시(조건: 병존 게이트 절체 / #126 가드 후행 제거 / coherence 설계 리뷰 선행. 옵션4 축소판 = 2순위). 이후 (c′) 설계 리뷰 → 병존 구현 → 절체·raw-fd 삭제 → EXIT 재측정. #81 경량 재실행 = 조건부 CLEAR(C1~C4, #74 개정 코멘트 편입: C1 connect_list 신규 소비처 교체 선행 / C2 raw-fd OLD 티어 스필 백킹 대체 결정 / C3 OLD-입력 병렬 정렬 직렬 폴백 / C4 fhs_hash 제외. 정정: first_vpid 보존·materialize 부분 삭제·#113 폴백 존치. #110 가드 신규 등재). 62fc99923 런타임 검증 전 항목 PASS(outer_join 누적 13회 무오차, G1~G22, selftest, 회귀세트 — #127 기록 코멘트). #127 착지(`1dfcef7a7..62fc99923`, 리뷰 통과·close): upstream develop 47fcc321f 머지(M `f72ef5d35`+M2+fix, 7파일 25헝크 P1~P5 판정 기록) + **회귀 귀속 정정** — outer_join gate-ON 비결정 오답의 진범은 merge가 아니라 **#123 latent HLS_SPILL 병렬 probe 공유 커서 race**(K-12; tip도 FAIL 3/3, .33 단회 PASS는 위음성). 정공 수정 `62fc99923`(per-context HLS_SPILL_CURSOR, readkeys 5,119,999 완전 복원, release 8/8). 검증 축소(사용자 결정): debug 반복·기존 PASS 세트·G1~G22·selftest는 #81 sweep preflight로 이관. LEFT-outer 허위 안전 → 하네스 readkeys 가드 제안(#74 자료 편입). #125 착지(`fcc4aac81`, 리뷰 통과·close): BufFile fd 위생 — `ensure_buffile` EMFILE/ENFILE 매핑(legacy `is_fd_or_space_error` 패리티) + RLIMIT_NOFILE 부트 점검(`ER_BO_NOFILE_LIMIT_LOW` -1375, best-effort), fail-before-fix 채증·!NDEBUG 주입기, VFD/fd-cap 계층 신설은 과설계 기각(D4, record-only). 착지 부수: #113 무음 행유실 가드(`127abc87c` cherry-pick), #115/#116 cub_pl NPE(`a8bfe6813`/`8e70769b0`). 부수 리뷰 통과·close(2026-07-03 오후): #101 SIMPLE_POS 좌표 1급화(`475e0ad6d` — HYBRID 해제, probe pread 0.76/0.15 read/probe로 D2 same-page 캐싱 재론 불요 판정, HASH_FILE 가드는 #123 인계), #124 픽스처 정비(`712c7243c` — 함정⑩ 해제, develop 대비 관찰 = evidence K-11).

## 3. DO-NOT-REASSUME (오염 전제 — 재도입 금지)

| # | 전제 | 왜 틀렸나 |
|---|---|---|
| P1 | "정확성은 완료, perf만 남았다" | 목표는 구조 개편. 그리고 2026-07-02 리뷰로 correctness 결함 다수 확정(§2 표) — 이 프레임은 이중으로 틀렸다. |
| P2 | "dirty-flush 국소 패치가 perf 타깃" | per-tuple 락은 전역 레지스트리 구조의 증상. 레지스트리 제거(축1)가 정공법. |
| P3 | "connect는 membuf==NULL real-VPID 강제가 영속 규칙" | connect_list 자체가 폐기 대상(축2). 옛 구조의 한계 기록일 뿐. |
| P4 | "NOT_USE_MEMBUF 강제로 parity 내면 됨" | correct-but-slow(+209%)+크래시 — 막다른 길. |
| P5 | "raw-fd(e21917cfd)에서 재설계 사실상 종료" | 중간 산출물. 축1/축2가 본체. |
| P6 | "BufFile 모델은 장기/선택 과제" | 본설계이자 목적지. |
| P7 | ~~"pgbuf-bypass 하드게이트가 존재한다"~~ | **해소(#93 착지)**: `pgbuf_fixes` 실배선 + selftest 게이팅 완료 — 이제 하드 게이트로 인용 가능. 단 debug selftest 간헐 assert는 전역 카운터 타 스레드 귀속부터 의심(§5 함정 5). |
| P8 | ~~"robust-parity green = NEW 경로 검증됨"~~ | **부분 해소(#92 착지)**: 파서 수정 + NEW-engagement 카운터(`Num_qfile_new_backed_create` delta)로 engagement 실증 가능 — parity는 반드시 카운터와 함께 인용. 클라이언트 fetch/캐시/holdable 싱크는 여전히 집계 parity가 구조적으로 못 본다(§4 클라이언트-가시 게이트로 보완). |
| P9 | ~~"holdable = 복사 없는 reparent가 구현되어 있다"~~ | **해소(#111 착지 `ab3052e2b`, 2026-07-03)**: zero-copy reparent 복원 완료 + ADR 0001 개정(`8fb828a`). 이제 사실로 인용 가능 — 단 holdable+cacheable·raw-fd는 materialize 폴백. |
| P10 | ~~"develop 대비 안 빠른 이유 = pgbuf_fix 오버헤드 / SORT 이중 물질화"~~ | **#98 44-leg 실측으로 확정**: 주범은 **게이트 무관 base spill 읽기 계층의 per-row pread**(develop 7.3만 vs branch 406만, 행당 ~0.8회, 62GB 증폭; OFF/ON 동수) → #107. wide-row 확장모드 회귀는 존재하지 않음(ON/OFF 0.78~1.02) → #101 후순위. PHJ는 게이트 ON이 develop 능가(695.9 vs 876.5ms @2000k) — 게이트 설계 무죄. H2(이중 물질화)는 지배 요인 아님(직접 반증은 아니나 우선순위 하향). |
| P11 | "#62/#63류 오진 패턴" | raw-stdout md5·GROUP_CONCAT 판정 금지(FALSE-ALARM 이력), serial 강제는 `parallelism=1` AND `max_parallel_workers=1` 둘 다, 게이트 env는 서버 프로세스 기준. |
| P12 | "이론적 레이스/창(R계열) 지적은 곧 구현 과제다" | R12(#96)에서 제안된 두 수정 방향이 각각 **데드락 유발/무효**로 판명(실제 착지분은 무관한 별개 누수 수정). 이론적 창은 **구현 전 도달가능성 검증부터** — supervisor 독립 재검증 절차를 거친다. |

## 4. 불변식 (게이트)

- robust parity ONLY: COUNT/SUM(CAST NUMERIC(38,0))/MIN/MAX + 터미널 페이지 포함. raw md5 금지. 병렬은 `;trace on`의 `parallel workers: N>1`로 실증 + **NEW-engagement 카운터 delta 확인(#92 착지 — assert 가능)**.
- **클라이언트-가시 결과 실증**: 집계가 아닌 top-level SELECT(ORDER BY/DISTINCT/GROUP BY)의 실제 행 반환을 게이트에 포함한다(R1 재발 방지).
- serial == parallel; orphan-zero(정상/비정상 종료 + kill-9 부트 스윕 — #88 Batch A 진행 중); TDE 무결; deadlock-free.
- per-path single-backing(연산자별 원자 전환, entry-boundary 가드 production-hard). transient의 공용 풀 오염 0 — **#93 실배선으로 '하드 게이트' 승격 완료**(NEW 백킹 pgbuf BCB fix 0).
- close/freeze 실패는 silent truncation 불가(#86 계약): producer 실패는 리스트에 latch되고 scan-open 단일 choke point가 `ER_QPROC_OUT_OF_TEMP_SPACE` raise.
- Phase3-EXIT 달성치: 이중 스필 0 · per-tuple 전역 락 0 · heavy DISTINCT/PSORT median ≤ develop×1.10 (**달성 경로 확정: #107 — 정렬 내부 NEW화 가설은 #98로 우선순위 하향**).

## 5. 거버넌스

1. 매 세션 시작: 이 SSOT(특히 §2 현재 상태 + §3 DO-NOT-REASSUME)를 먼저 읽는다. 접근이 §3과 충돌하면 멈추고 보고.
2. **SSOT는 append하지 않는다.** 사실이 바뀌면 본문을 고치고(GitHub #75 body 편집 + 로컬 미러 동기화), 바뀐 이유·측정은 evidence(#76 코멘트 + 로컬 append)에 남긴다. 폐기된 결론은 §3에 흡수하거나 evidence에서 supersede.
3. 구현 이슈는 자족적으로(좌표+재현+기계적 수용 기준, [CONFIRMED]/[VERIFY] 구분) 작성한다 — 실행자는 SSOT 없이도 착수 가능해야 한다.
4. **런타임 검증 필수**: `git -C ~/dev/workspace pull` → 빌드(cubrid-build 스킬, `WORKSPACE=~/dev/cubrid-workmem`) → `just conf`(stored_procedure=no) → cubrid-server-control 래퍼로 기동. "환경 결함으로 검증 미완 close" 금지. fail-before-fix 필수. debug 검증은 wmloc/wmg003(tpch_sf10은 release 전용). 스크래치 /tmp 금지.
5. 커밋 태그 `[temp-workmem <slice>] ... (#이슈, #78, #73)`, 착수·커밋 전 `git fetch --all`+rebase(브랜치 명시 없는 단순 fetch가 동시 착지를 놓친 실사고 있음), 완료 시 이슈에 한글 보고 + **작업 후 트리 원상복구·데몬 정리**.
6. **착수 함정 목록(현행)**: ①stale 바이너리 — #106으로 해소(proof에 cubrid_rel 기록은 계속 요구) / ②fixture 게이트 OFF 로드 — #105로 해소 / ③fetch+rebase/HEAD re-ground(유효) / ④**게이트 기본 ON**(`ceb8997e8`, 2026-07-03) — 그 이전의 "기본 OFF/env =1로만 ON" 서술이 이제 stale. 진단용 opt-out은 env `=0` / ⑤debug selftest 간헐 assert = pgbuf 전역 카운터 타 스레드 귀속 의심(유효) / ⑥재빌드·재설치가 `just conf`를 리셋 → 매 빌드 후 재적용(PL 부팅 실패의 원인) / ⑦`cubrid server stop <db>`는 master를 안 내림 → 재빌드 바이너리 포트 바인드 실패 시 stray cub_master부터 정리 / ⑧kill-9된 서버는 master가 자동 재기동하며 **게이트 env 비상속**(#88 발견) / ⑨측정·parity 실행 중 `just build` 병행 금지 — 빌드가 `~/CUBRID` 심링크를 repoint해 공용 master와 포트 충돌(#107 인시던트) / ⑩**해소(#124 `712c7243c`, 리뷰 통과)**: 픽스처 3종 정비 완료 — outer_join/cte USE_HASH(+cte `MOD(id,25)=0` 축소), connect_by LEVEL 50k. 전 3종 ≤29s. 단 connect_by는 엔진 구조상 단일 스레드 실행이라 parity.sh 병렬-워커 가드는 수동 우회 필요(md5+카운터 delta 수동 재현). develop 대비 outer_join 2.99×/cte 1.44× 관찰은 evidence K-11(기존 tree-wide 회귀 노출 — 픽스처 무관).
7. valgrind/스트레스는 검증 쿼리 순간에만 — 적재·픽스처 준비는 일반 서버로. 10분+ 명령은 background로.

## 6. 참고 좌표 (착수 시 HEAD에서 re-ground)

- 신규 백킹: `src/query/qfile_tape.{hpp,cpp}` `qfile_buffile.{hpp,cpp}` `qfile_chunk.{hpp,cpp}`; 통합: `query_list.h` `list_file.c`; 생명주기: `query_manager.c` `session.c`; 병렬: `src/query/parallel/`; 정렬: `external_sort.c`; 레거시 raw-fd(Phase3 삭제 대상): `temp_page_store.{hpp,cpp}`.
- 게이트: `qfile_{sort,scan,hashjoin}_new_backing_enabled` (list_file.c — 착수 시 HEAD에서 라인 재확인).
- 유닛 게이트: `unit_tests/tapeset/test_tapeset_scan.cpp` (**G1~G22**). in-server selftest: `CUBRID_{BUFFILE,HELDTAPE,TAPEREAD,PRODUCER}_SELFTEST` + `CUBRID_WM_CLOSE_FAULT_SELFTEST` (debug 전용, **#93로 게이팅됨**).
- 캠페인 conf: `work_mem=1G data_buffer_size=512M parallelism=8 max_parallel_workers=8` (`just conf`). PHJ 골든: `<200000`=200360, `<2000000`=2000495; wmloc DISTINCT=4194304/8796090925056/0/4194303.
- 종합 리뷰 보고서(버그 상세 정본): `~/dev/workspace/temp_workmem/issue69-81_review_report.md` — 단 R12 문항은 #96으로 사실 변경됨(§3 P12).
- 파일 충돌 규칙: `qfile_tape.cpp`(tape_writer/freeze)는 한 번에 한 작업만. 배치 내 같은 파일은 "agent는 패치안까지, 적용은 메인이 순차".
