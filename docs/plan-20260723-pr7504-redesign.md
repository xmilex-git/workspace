# PR #7504 재설계 실행 계획 — no-logging 병렬 인덱스 빌드

- **PR**: CUBRID/cubrid#7504 `[CBRD-27071] Support no logging-per-page parallel index build`
- **HEAD**: `3ffeab7930fec4227da9c1d820025e7c793ba0ff` (작업 브랜치 `pr-7504-redesign`, worktree `~/dev/worktrees/pr-7504-review`)
- **작성**: 2026-07-23. 리뷰 보고서(status: Blocking)의 실행 계획화.
- **목적**: 성능 개선(cold 2.48x / warm 3.48x) 유지 + 변경 최소화 + 코드 복잡성 완화 + 공용함수화/추상화로 유지보수성 강화.

## 1. 검토 결과: 타당·실행 가능

보고서의 전 좌표를 PR head 실코드에 대조 검증했다.

| 주장 | 판정 | 근거 |
|---|---|---|
| 프로토콜 OOB read | 확인 | `network_interface_sr.cpp:4719`가 `reqlen` 검사 없이 `no_logging_index` unpack. handler는 `reqlen` 수신(4605행). 같은 파일에 guard 하우스 패턴 존재(2110, 4484행) |
| barrier false positive | 확인 | barrier는 `log_append_redo_data(RVBT_BULK_BUILD_DURABLE,…)`(btree_load.c:1420) — redo-only라 savepoint rollback 시 compensation 없음. recovery(log_recovery.c:3595)는 완료 tran의 barrier를 무조건 refuse |
| 2-core gate 위반 | 확인 | `px_parallel.cpp:64` `system_core_count <= 2 → return 0`이 switch 앞이라 INDEX_BUILD도 걸림 |
| 직렬화 복제 | 확인 | `bt_load_write_record`(btree_load.c:4605)가 leaf/OID/MVCC packing 재구현, `0x8000`/`0x4000` 리터럴 재정의 |
| sorter↔loader 결합 | 확인(보고서보다 심함) | `external_sort.c`가 `btree_create_file`, `log_sysop_start/abort/attach_to_outer`, 페이지 추정 정책(`+64`, `/10`) 직접 수행. 노출 extern은 12개가 아니라 **14개** |
| LOAD_ARGS clone | 확인 | `memcpy` + 필드 리셋 ~30개 (btree_load.c:4734~) |
| `log_get_system_op_level` 제거 가능 | 확인 | 용도가 `assert(level < 0)` 4곳뿐 → `!log_check_system_op_is_started` 등가 대체 |
| `free` → `free_and_init` | 확인 | btree_load.c:4260, 4262 |

재설계 실행가능성 핵심 근거:

- `bt_load_worker_put_range`는 `btree_construct_leafs(thread_p, recdes, load_args)` 단순 위임(btree_load.c:4799) — legacy `SORT_PUT_FUNC`와 시그니처 동형. "consume을 SORT_PUT_FUNC로 접기"는 원상복귀에 가깝다.
- barrier 방식은 **commit-time postpone + media-recovery-aware redofun으로 확정**(§4 확정 2, ADR 참조). (a) undoable marker는 최후 fallback으로만 유지.
- 성능 재검증은 이 호스트(32코어/188GB/3.5TB)에서 재현 게이트 원칙(동일 장비 상대 델타)으로 수행.

## 2. Phases

### Phase 0 — 기준선 고정
1. 작업 브랜치 `pr-7504-redesign` (base `3ffeab793`), worktree 재사용.
2. **픽스처 재생성**: 20GB 원본(t20g 341M행)은 삭제·생성기 소실 → `bulkidx_bench` 스키마(`k INTEGER NOT NULL, payload VARCHAR(32)`, k=ROWNUM flat 키)를 341M행으로 스케일업한 `mkfixture-20g.sh` 작성, 인덱스는 원본 그대로 `idx_t20g_k ON t20g(k)`(pivot 하네스 잔존물). 생성은 background 1회, 사전 디스크 상한 점검.
3. 측정 하네스는 `~/dev/bkx-review-response/measure-20g-pivot.sh` 재사용(설치 루트/DB 경로만 교체; cold 교대, warmup 1 + 유효 3, conf 고정: parallelism=32, DWB off).
4. release 빌드(`just build release pr7504-base`)로 develop vs PR-head를 재측정 — 배율은 **참고 기록**(공표 3.41x와의 비교는 fixture가 다르므로 sanity 수준, 게이트 아님). **수용 기준은 오직 동일 재생성 픽스처 위 PR-head vs 재설계 상대 델타.**
5. 기능 기준선: ordered/hot/overflow/duplicate key + `checkdb` + kill sweep PASS 상태 기록.

### Phase 1 — Blocking 수정 (재설계와 분리 커밋, 선착지 가능)
1. **프로토콜**: `no_logging_index`를 `(ptr - request) + OR_INT_SIZE <= reqlen` guard 하의 선택적 tail로, 부재 시 0. 하우스 패턴(4484행식) 복제.
   - verify: 구 loaddb 클라이언트→신 서버 / 신 클라이언트→구 서버 양방향. fail-before-fix 채증.
2. **barrier = commit-time postpone + 2-rcvindex 구현 완료** (ADR: `~/dev/bulk_index_build/docs/adr/0001-bulk-build-barrier-commit-time-postpone.md` — 구현 실측 결과 포함): pending `RVBT_BULK_BUILD_DURABLE` postpone의 redofun이 실행 시점에 redo-only 마커 `RVBT_BULK_BUILD_COMMITTED`를 append, 두 redofun 모두 media recovery면 무조건 거부. media 상태는 log_recovery.c file-static + scope_exit로 함수 전 구간 한정. flush+sync는 빌드 종료 시점 유지.
   - supersede 이력: ① scan case+NULL_TRAN_INDEX 조건(crash window 2개 놓침) ② 단일 redofun(committed 재생이 logical run-postpone 래핑이라 scan에 안 보임 — R1 회귀 실측) → 2-rcvindex로 확정.
   - verify (전부 실측 완료):
     (i) abort-class: base 거부 채증(LSA 637|14528) → 수정 후 성공 [r4 프로브].
     (ii) savepoint-class: **조직적 도달 불가 판정** — loaddb는 statement 실패 시 전체 tran abort(FK 프로브 실측). 설계상 log_do_postpone의 rollback-구간 스킵이 커버, abort-class가 그 기계 검증.
     (iii) crash window: media 분석은 CWP 상태를 만들지 않으므로(log_recovery.c:1285) W0/W1/W2 전부 **clean abort(성공+인덱스 부재+행 보존+checkdb 0) 또는 거부** — 어느 쪽이든 안전. 안전성 불변식: 인덱스가 살아남는 media replay는 마커를 먼저 재생 → 반드시 거부. [w-probe 실측]
     (iv) 대조군: 정상 완료 빌드 거부 유지(R1) / restart recovery는 CWP forward-commit(인덱스 생존) / 구 클라이언트→신 서버 compat [실측].

### Phase 2 — 경계 접기 (sorter/loader)
1. consume은 기존 `SORT_PUT_FUNC` 재사용(레코드당 put; `bt_load_worker_put_range`가 이미 시그니처 동형). lifecycle은 6-op `SORT_PX_OUTPUT_OPS`로 고정 — `prepare`(파일·sysop·provider·페이지 추정), `service`(리더 페이지 공급 펌프), `end_shard`(워커 마감), `finish`(tree finalize만 — **durability는 제외**, flush/sync+barrier는 기존 outer loader 지점 유지), `abort`(멱등 전량 회수), `decode_key`(splitter 선정용 COPY 복원). 선언은 external_sort.h, 구현은 btree_load.c, 전달은 기존 put_arg/px_extra_arg.
2. **prepare는 3상태**: `NOT_APPLICABLE`(병렬 출력 비적용 → 직렬 폴백), `READY`(진행), `ERROR`(실패 전파 — OOM·파일 생성 실패·decode 오류를 조용히 serial로 강등하지 않는다. 현 PR의 오류 의미 보존).
3. sorter→loader 입력은 가공 없는 run 통계 `SORT_PX_ESTIMATE{run_total_pages, n_ovf_keys, sum_ovf_pages}` — 페이지 추정 정책(+64, /10)은 prepare 안으로.
4. 소유권 규칙(구현 확정형): (1) **prepare(ERROR)는 transactional** — 반환 전 생성 자원(파일·sysop·provider·shard) 전량 자체 rollback, sorter 회수 자원 0; (2) **prepare(NOT_APPLICABLE)는 직렬 출력 대상(미부착 sysop 안의 새 파일)을 의도적으로 열어둔 채 반환** — 직렬 put 실패 시 caller가 `abort_px`(n≤0 형태)로 회수; (3) `abort_px`는 prepare가 자원을 커밋한 뒤(READY 또는 NOT_APPLICABLE 직렬 대상)에만, 멱등; (4) **finish의 tran 소유권 전이는 마지막 한 단계에서만**; (5) finish 성공 후 sorter 접근 금지; (6) `clone_scan_args`도 transactional.
5. `btree_load.h` extern 14개·`BT_LOAD_PROVIDER`/`LOAD_ARGS` 타입 노출·`log_sysop_*` 호출 제거, `log_manager.h`의 `log_get_system_op_level` 원복(`!log_check_system_op_is_started` 대체). `demote_to_logged`/`set_px_outcome`/`parallel_enabled`는 prepare 반환값 의미론으로 흡수.
   - verify: 병렬 경로 실발동을 debug 로그/카운터로 실증(passthrough-tautology 방지). serial==parallel parity는 robust 집계.

### Phase 3 — 상태·공통코드
1. `memcpy` clone → immutable `BT_LOAD_SHARED` + per-shard `BT_LOAD_STATE` 명시적 init/clear.
2. `btree_write_record`에서 공통 packer 추출, overflow-key 저장만 callback 주입 → `bt_load_write_record` 복제 삭제, 리터럴 flag 제거.
3. `free_and_init` 통일, 정책값(`/4`, `<<16`, 16, 64, `/10`) 상수화.
4. **`BT_LOAD_PAGE_SINK` 공용화**(리뷰 보고서 원안 복원): 기존 `new_page_fn`과 `btree_log_page`를 작은 page-sink로 묶어 no-redo/logged 두 모드가 legacy leaf builder를 공유. Phase 3 착수 시 diff 크기 대비 이득을 실측해 채택/명시적 기각 중 결정 기록.
5. `px_parallel.cpp`: INDEX_BUILD를 공통 early-return 앞으로 → 2-core degree 2 허용.
   - verify: taskset 2-core 시뮬레이션에서 degree 2 발동 실증.

### Phase 4 — 최종 검증 배터리
- optdebug + release 풀빌드 green, CS 모드 optdebug 라이브(assert/tracker leak 0), orphan-zero.
- 호환 매트릭스, 2-core/degree-1 fallback/SA/online index/옵션 off → logged 경로 전수.
- ordered/hot/overflow/duplicate, DWB on/off, kill sweep, checkdb — Phase 0 기준선과 동일 PASS.
- 성능: 동일 픽스처 PR 원본 vs 재설계 상대 델타 — 수용 기준 "회귀 없음(분산 이내)". 드리프트 센티널 1회.
- **구조 게이트**: (i) `external_sort.c`의 B-tree 타입/함수 의존 0개(`bt_load_*`·`LOAD_ARGS`·`BT_LOAD_PROVIDER`·`log_sysop_*` grep 0), (ii) legacy serial kernel의 의미 있는 diff 최소화(develop 대비 diff에서 serial 경로 함수들의 변경이 어댑터 접합부로 한정). churn 감소율(30~40% 목표)은 보고 항목일 뿐 게이트 아님.

### Phase 4b — TC 번들 영향 (입력: tc-bundle **v3**(JIRA 첨부 1019935) → 산출: **v4** 재첨부)
barrier=postpone 전환으로 로그에는 빌드당 `RVBT_BULK_BUILD_DURABLE` 레코드가 2개(LOG_POSTPONE + commit 시 LOG_RUN_POSTPONE) 남는다. 영향:
- **수정**: `lib-oracle.sh barrier_count` — bare grep(빌드당 1→2로 이중 계수)을 "committed barrier"(RUN_POSTPONE 계열만) 계수로 교체. "빌드당 1건" 불변식 유지. 필요 시 `barrier_pending_count`(POSTPONE 계열) 헬퍼 추가.
- **무변경으로 생존**: tc-loaddb-basic(N1/N3 상대 비교, N4=0), tc-crash-restart(≥1), tc-splitter-balance/skew(≥1·성능 오라클), tc-replay-barrier R1~R3(메시지 grep·인덱스 생존 판정 — 계수 미사용).
- **신규 레인**:
  - tc-replay-barrier **R4 (2레인)**: (a) abort-class — barrier 후 `ROLLBACK WORK` → full replay 성공(조직적, 채증 완료 방식). (b) savepoint-class — optdebug+FI로 barrier 후 `sm_add_constraint` 실패 → savepoint rollback → 후속 commit → full replay 성공. ~~"후속 인덱스 실패"안~~ 폐기(둘째 statement의 savepoint는 첫 barrier 뒤라 첫 barrier가 rollback되지 않음 — 그 경우 거부가 정답).
  - **crash-window 레인 2종**: CWP 직후 / barrier RUN_POSTPONE 직후 kill → full replay 거부.
  - **compat 레인**: 구 설치본(develop) loaddb 클라이언트 → 신 서버, `--no-logging-index` 없는 요청 정상 + barrier 0. 두 설치 루트를 받는 번들 스크립트/수동 E2E(기존 measure-20g 패턴 재사용).
  - **2-core 레인**: `taskset -c 0,1`로 서버 기동 → 옵션 발화 시 barrier ≥1 (degree 2 허용 수정의 오라클). 번들 스크립트/수동 E2E.
- **재기준**: verification.md §1의 정확 계수 문구("barrier 3/빌드 3")를 committed-barrier 기준으로 갱신, §4 혼합버전 문단에 postpone 레코드 타입 서술 반영.

## 3. 순서 의존성·리스크
- Phase 1 ⟂ Phase 2/3 — blocking 수정만 선착지 가능하도록 커밋 분리.
- 최대 리스크: (i) barrier postpone 전환의 런타임 반증 가능성 — Phase 1 fail-before-fix TC로 조기 판정, 반증 시 (a) fallback. (ii) Phase 2 리팩터 성능 누수 — put 경로는 이미 간접호출이라 구조적 추가 비용 없음, Phase 4 상대 델타로 게이트.
- TC 저장소는 불변(확정 5) — CI의 draft TC PR 연결 검사는 현상 유지(기존에도 이 검사만 미통과였음).

## 4. 확정된 선택
1. **착지 형태 = 후속 커밋 적층** (2026-07-23 확정): #7504 브랜치에 Phase 1 blocking 수정 커밋 → Phase 2/3 리팩터 커밋 순으로 적층. 리뷰 스레드·CI·JIRA 연결 보존, squash-merge 전제.
2. **barrier = (b) commit-time postpone + media-recovery-aware redofun** (2026-07-23 확정, 동일자 개정 — ADR `~/dev/bulk_index_build/docs/adr/0001-bulk-build-barrier-commit-time-postpone.md`): 거부는 rcvindex redofun에서 무조건(media crash 시). 최초안(scan case 이동+완료 tran 조건)은 crash window 2개로 supersede. (a) undoable marker는 여전히 최후 fallback.
3. **성능 픽스처 = t20g 재구성** (2026-07-23 확정): 원본 삭제·생성기 소실 확인. bulkidx_bench 스키마 스케일업(341M행/~20GB)으로 재생성, 원본 하네스(measure-20g-pivot.sh) 재사용, sanity anchor는 develop 대비 배율(~3.4x) 재현. 재설계 수용 게이트는 동일 픽스처 위 PR-head vs 재설계 상대 델타이므로 원본과의 바이트 동일성은 불요.
4. **`SORT_PX_OUTPUT_OPS` = 6-op 계약** (2026-07-23 확정): prepare/service/end_shard/finish/abort/decode_key + `SORT_PUT_FUNC` 재사용 + 소유권 4규칙(prepare transactional, finish 전이 원자성 포함). 상세는 Phase 2.

5. **TC 반영 = JIRA 첨부만 갱신** (2026-07-23 확정): tc-bundle v4(오라클 committed-barrier 계수 수정 + R4·compat·2-core 레인) + verification.md v2(수동 E2E 절차·재기준). **TC 저장소(공개·비공개)와 draft TC PR(#3090, #3687)은 건드리지 않는다.**

계획 수준 미확정 항목 없음 — 계획 확정 (2026-07-23, 외부 리뷰 2차 조건부 승인 조건 2건 반영). 구현 중 결정 항목은 해당 Phase에 명시: Phase 3의 `BT_LOAD_PAGE_SINK` 채택/기각은 실측 후 결정·기록.
