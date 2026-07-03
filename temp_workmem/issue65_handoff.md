# Issue #60 / #65 HANDOFF — 다음 작업자 인수인계 (REBASELINED + 구현계획 확정)

Last updated: 2026-06-29 KST · Session: GJC (ralplan consensus — 구현 계획 산출)
> 매 세션 끝에 갱신. **SSOT(`issue65_ssot.md`)와 EVIDENCE(`issue65_evidence.md`)를 먼저 읽고 시작.**
> 이전: SSOT 3종 rebaseline(§0) → grill-with-docs 설계 트리 전체 CLOSED + CONTEXT.md/ADR 0001.
> **이번 세션: 설계(CLOSED) 위에 "어떻게 구현하나" 상세 계획을 ralplan 합의로 산출 → PENDING APPROVAL.**

---

## 0. 시작 전 (강제 — 거버넌스)

```
1. issue65_ssot.md 읽기 (COMPACT-SAFE SUMMARY + §0 DO-NOT-REASSUME + §5 OPEN).
2. issue65_evidence.md §Z 실패 대장 + 각 항목 "재해석(개편 기준)" + §H 설계해소 근거.
3. 되짚어 말하기: 진짜 목표(2축 개편) / e21917cfd 는 출발점 / 믿으면 안 되는 오염 전제(P1~P6) / 즉시 다음 액션.
4. 새 접근이 SSOT §0 오염 전제를 다시 까는지 확인. 깔면 멈추고 보고.
5. 이해가 SSOT 와 충돌하면 멈추고 충돌을 보고.
6. **SSOT 수정은 유저 허락 필요. evidence 는 추가 가능하나 SSOT 와 상반되면 SSOT·evidence 둘 다 컨펌 후 교체.**
```

---

## 1. 현재 워크트리 상태

- `git rev-parse HEAD` = `e21917cfd` (branch `feature/temp-workmem-redesign`). **개편 출발점(목적지 아님).**
- **설계 문서는 전부 `~/dev/workspace/temp_workmem/`** (레포 아님): `issue65_ssot.md`(round-2 동기화 완료) / `issue65_evidence.md`(I-1/I-3/I-5 supersede 표시) / `issue65_handoff.md` + `CONTEXT.md`(PG glossary) + `docs/tape-model.md`(구조/주소/분배) + `docs/adr/0001`(holdable)·`0002`(connect→Tapeset)·`0003`(per-worker private·offset)·`0004`(partition tape import).
- **구현 계획**: `.gjc/_session-019f122a-ae3b-7000-bb54-b59b04cee7fc/plans/ralplan/019f122a-ae3b-7000-bb54-b59b04cee7fc/pending-approval.md` — ⚠️ **STALE (round 2 supersede).** 옛 가정(per-Tape page directory / occupancy bitmap / Chunk-occupancy fallback / 3좌표 / sector 분배 / dir-memory 게이트) 기반. **Phase 1 착수 전 round-2 결정(ADR 0002/0003/0004 + SSOT round-2 UPDATE)으로 재작성 필수.**
- ⚠️ **미커밋 dirty 5파일(폐기된 방안 E/dirty-flush 잔재)** 워크트리에 잔존 — `git status --short` 에 `M temp_page_store.cpp, list_file.c, query_executor.c, query_hash_join.c, px_hash_join_task_manager.cpp`. **Phase1 착수 전 `git checkout -- <5파일>` 로 e21917cfd 복귀**(plan §1 Pre-flight, SSOT §0 P2). 선재 더티(`m cubrid-cci`, `?? bench/harness/results/*`)는 건드리지 않음.
- 빌드: cubrid-build 스킬만 (`WORKSPACE=/home/cubrid/dev/cubrid-workmem just build release|debug`).

---

## 2. 이번 세션에서 한 일

- **ralplan 합의로 구현 계획 산출 (PENDING APPROVAL).** Planner → Architect → Critic 2 iteration:
  - Planner n=1 → Architect n=1 (WATCH/COMMENT, F1~F6) → Critic n=1 (ITERATE, 5 blocking) → **revision n=2** → Architect n=2 (**CLEAR/APPROVE**) → Critic n=2 (**OKAY**, 6/6 SATISFIED, blocking 0).
- **앵커 e21917cfd 재검증** (SSOT 사실성 확인, 전부 일치): `qfile_scan_next`=position state machine(S_BEFORE/S_ON/S_AFTER, list_file.c:4979-5070), `qfile_scan_prev` S_ON `QFILE_GET_PREV_VPID` walk(@5103), `qfile_connect_list`(@3159, membuf==NULL@3177, next/prev_vpid@3201/3204), `QFILE_LIST_ID`(query_list.h:429-448), `qfile_copy_list_id`(@465) + `QFILE_{SKIP,MOVE,PROHIBIT}_DEPENDENT`, Tape 원형(writer_results/list_id_headers/read_spec, px_scan_result_handler.hpp).
- **합의가 추가로 발굴한 구현 위험(설계 변경 아님, 구현 장치로 흡수)**: F1 QFILE_LIST_ID copy/clear 소유권 / F2 scan_prev backward 메커니즘(page directory) + 합성 N-Tape 게이트 / F3 Phase2-EXIT exhaustive 심볼 sweep / F4 append-only 검증+occupancy fallback / F5 1C 원자 / F6 이중스필0·락0 = Phase3-EXIT 불변식.
- **SSOT/evidence 충돌 가능 2건은 미수정 — 유저 컨펌 대기**(plan §8 IR, 아래 §7).
- **★ grill-with-docs ROUND 2 (2026-06-29) — 설계 추가 정밀화 (유저 확정).** §3/§4 및 `pending-approval.md`의 일부 구현 가정을 **supersede.** 산출: ADR **0002/0003/0004** + `docs/tape-model.md` + SSOT/evidence round-2 동기화. 핵심 변경:
  - 백킹 = **per-worker private, pgbuf BCB 우회**(공유풀에 안 올라감; 하드 게이트 BCB fix=0). raw-fd 평탄백킹 제거.
  - 좌표 = **(tape_idx, page_offset, tuple_offset) offset 산술** → **per-Tape page directory 폐기**(no mid-life dealloc→dense). §3 1A "page directory backward"·I-5 dir-memory 무효.
  - R2 = **64page offset-range work-stealing, occupancy bitmap 폐기** → §3 Phase2 "Chunk-occupancy fallback"·F4·dir-memory 게이트 제거.
  - multi-tape: partition/column = Tapeset 다수, **hash join 파티션 = per-worker tape import(mutex-append 제거)**(ADR 0004). 마이그레이션 = **연산자별 원자(mixed-backing list 금지)** + 마이그레이션-한정 backing-kind 태그 + coord_type을 contract까지 유지.
  - holdable = 백킹 reparent에 **RAM membuf prefix 소유권 이동 포함(복사·I/O 0)**; 세션kill orphan-zero가 파일+RAM(ADR 0001 (b)).
  - 게이트 델타: dir-memory 제거, **pgbuf-bypass(BCB fix=0)·no-mixed-backing 추가**, (3)(4) 재정의, I-2 합성 N-Tape 유지.
  - **다음 액션: Phase 1 착수 전 `pending-approval.md`를 위 결정으로 재작성.**

---

## 3. 구현 본체 (= plan §2~§4; 설계는 SSOT §5 전부 RESOLVED)

마이그레이션 = **expand→migrate→contract** (상세는 pending-approval.md):
1. **Phase1 (EXPAND, additive; 옛 connect/raw-fd 병존)** — 내부순서 **1A-0 accessor-shim → 1A 스캔계약 → 1B 백킹 → 1C 생명주기(원자)**.
   - 1A-0: QFILE_LIST_ID 직접 필드접근을 accessor 뒤로(F1/F3 surface 컴파일러 강제 열거, 무동작).
   - 1A: `QFILE_TAPE`(kind+page directory) + QFILE_LIST_ID Tape 벡터(소유권 DEPENDENT_MODE 정렬) + 3-레벨 `qfile_scan_next`(tape_idx 관통) + `qfile_scan_prev` 3좌표(page directory backward) + 합성 N-Tape split 게이트(1A-7).
   - 1B: per-worker append-only BufFile + membuf Option-A(전용→freeze) + TDE 상속.
   - 1C: holdable reparent(복사0) + reaper liveness `(tran,query) OR session-held` + session teardown 훅 — **원자 반영**.
2. **Phase2 (MIGRATE)**: 스캔-우회 인벤토리 A~E 전수 리팩터 + membuf 강제OFF 게이트 제거→재활성 + pre-sized slot(락0) + R2 Chunk(64p) 분배(append-only 검증 조건부, non-append=occupancy fallback). **게이트 2A-EXIT = exhaustive 심볼 sweep checklist(Phase3 진입 전제).**
3. **Phase3 (CONTRACT, 비가역; 2A-EXIT 통과 후만)**: connect_list/`dependent_list_id`-identity/`first_vpid`-identity/global raw-fd 레지스트리/per-tuple dirty-mark 락 삭제 + dead-path(G001~G003 락머신, 1A-3 어댑터, 1A-7 test-only) 정리 + 구조 재검토.

---

## 4. 다음 작업자가 바로 실행할 것

```
Step 0 — 거버넌스/계획 읽기
  - SSOT + evidence §Z/§H + CONTEXT.md + ADR 0001 + pending-approval.md(전체).
  - ⚠️ **round-2 supersede 먼저 반영**: §2 ROUND 2 + SSOT round-2 UPDATE + ADR 0002/0003/0004 + `tape-model.md`. `pending-approval.md`는 STALE → 재작성 후 Phase 1.
  - §7 IR 컨펌 항목(IR-1~IR-4) 유저 확정 여부 확인. 미확정이면 보수적 경로(occupancy fallback 등)로 진행.

Step 1 — 워크트리 청결(Pre-flight, plan §1)
  cd ~/dev/cubrid-workmem && git status --short
  → 폐기 방안 E 5파일 남아 있으면 e21917cfd 로 복귀(§1).
  → develop + e21917cfd 베이스라인 robust-parity + perf 표(evidence §B) 재현 = 수렴 기준선.

Step 2 — Phase1 착수 (1A-0 accessor-shim → 1A 스캔계약 부터; plan §2)
  - 매 하위단계 끝 robust-parity 게이트(1A-G0/G1/G2/G3 + dir-memory).
  - 측정훅 신규 빌드(현 harness 부재): session-kill orphan scan / chunk-skew meter(CoV) / copy·membuf·spill·dir-memory 카운터.

Step 3 — 게이트 임계는 plan §5 표 (정량). 절대 raw-stdout md5 / GROUP_CONCAT 판정 금지(FAIL-05/08).
```

---

## 5. PASS / FAIL 기준 (개편 게이트 — SSOT §6 + plan §5 정량표)

- PASS = robust parity(COUNT/SUM/MIN/MAX, full count + 터미널 페이지) + serial==parallel + orphan-zero + debug no-assert/crash + **(Phase3-EXIT)이중 스필 0 + per-tuple 전역 락 0** + heavy DISTINCT/PSORT median ≤ develop×1.10.
- 신규 5게이트(plan §5 정량): holdable reparent across-commit + 세션kill orphan-0(copy-0 카운터) · membuf 재활성/tiny-no-spill · Chunk skew CoV≤15% · 역방향/jump 3좌표 · cached 교차-트랜잭션. (+ NH-2 dir-memory 게이트.)
- VTune: `rawfd_find_and_mark_dirty` self-CPU=0.0s, mutex delta ≤+5s. strace: raw-fd I/O=0, 총 temp I/O ≤ develop×1.05. code-residue grep=0.
- FAIL class = correctness mismatch / terminal-page loss / orphan leak / crash-assert / 구조 미제거 / env contamination.
- 금지: raw-stdout md5 / GROUP_CONCAT 판정(FAIL-05/08).

---

## 6. 세션 종료 시 갱신 규칙 (거버넌스 — SSOT §7 와 동일)

```
1. 이 HANDOFF 갱신 (워크트리/HEAD/한 일/안 한 일/다음 액션).
2. source-of-truth 사실이 바뀌었으면 SSOT 갱신 — 단 유저 허락 필요. 아니면 건드리지 마라.
3. 새 실패는 EVIDENCE §Z 에 1건 APPEND — "측정/사실"과 "구조 가정"을 분리. (SSOT 상반 시 둘 다 컨펌.)
4. 폐기 결론은 SSOT §0 또는 evidence Status 로 supersede(역사 재작성 금지). 오염 프레임은 CUT-LOG 남기고 절단.
5. 기록: git status --short / HEAD / 변경 파일 / 실행 명령 / 게이트 verdict.
```

---

## 7. 거버넌스 적용 완료 (Intent Reconciliation — 2026-06-29 유저 컨펌 후 SSOT/evidence/CONTEXT 반영)

> 아래 4건은 유저 컨펌으로 **반영 완료**. SSOT 는 이제 north-star 로서 최신.

- **IR-1 (적용)**: SSOT §3.2 B1 — "연산자 호출부 0 변경" 명확화 + 내부 `qfile_copy_list_id`/`qfile_clear_list_id` 가 Tape 소유권을 `QFILE_{SKIP,MOVE,PROHIBIT}_DEPENDENT` 별로 확장해야 함 명시. evidence §I-4.
- **IR-2 (적용 — 설계 변경)**: SSOT §3.2 B2 의 "append-only → bitmap 불필요" **단정 철회**. occupancy(bitmap) 필요; bitmap-free 는 producer 별 append-only 검증 통과 frozen Tape 한정. 근거 `sort_split_input_temp_file` in-place 재기록(external_sort.c:4497/4509) = evidence §I-1. **잔여**: Phase2 에서 신 BufFile-시대 producer 별 append-only 검증(bitmap-free 적용 가능 범위 확정).
- **IR-3 (적용)**: plan 은 SSOT §0~§6 설계 그대로 구현(새 가정 무도입). CONTEXT.md Chunk 항목도 IR-2 와 정합되게 갱신.
- **IR-4 (적용)**: SSOT §6 — 이중스필0/per-tuple락0 = **Phase3-EXIT 달성치**(연속 불변 아님); 연속 불변 = per-path single-backing. 헤더+불변식 라인 갱신.
- 신규 evidence **§I (I-1~I-5)**: append-only 반례 / passthrough-tautology 게이트 교훈 / scan_next=state machine / QFILE_LIST_ID 소유권 함정 / page-directory 메모리 — 삽질 방지 코드사실 APPEND.

---

> 핵심: **#62 perf 는 목표가 아니라 잘못된 구조의 증상.** 목표는 축1+축2 전면 개편이고, 그게 끝나면 증상은 같이 사라진다.
> 설계 CLOSED → **구현 계획 확정(PENDING APPROVAL)** → 승인 시 expand→migrate→contract 착수.

---

## UPDATE 2026-06-29 (session: #67 Pre-flight 완료)
- **#67 CLOSED(completed).** 워크트리 청결(방안 E 5파일 e21917cfd 복귀, `git status` 클린·선재더티 미접촉) + release-only 수렴 베이스라인 재현·고정.
- HEAD=e21917cfd, src 클린. 5파일 diff 백업=`/tmp/issue67-preflight-backup/`.
- 베이스라인(release, median/3, hard-gate 통과): PSORT_tpch dev 42.558 / e219 62.587 (+47.1%), HASHAGG_tpch 26.036/31.044 (+19.2%), DISTINCT_tpch 38.554/57.581 (+49.4%), HASHAGG_wmloc 3.006/3.507 (+16.7%). heavy-spill 회귀 시그니처 재현=회귀 비교 기준선. robust-parity 6/7 YES(cross-build+serial==parallel)+orphan-zero. 산출물=`~/.claude/scratch/remote-codex/issue67_reproduce/`.
- **신규 결함 #77(OPEN)**: e21917cfd 병렬 PHJ_wmloc `allocate 0 memory bytes`(query_hash_scan.c:662, tuple_size=0). evidence §Z FAIL-10. 축2 positioning fragility 직접 증거.
- release-only hard gate 추가: 측정 드라이버(`issue67_reproduce.py`)가 install cubrid_rel + cub_server `/proc/exe` 를 release 로 강제 검증(debug 즉시 중단).
- 다음: Phase 1 착수 전 `pending-approval.md` round-2 재작성(기존 §2 ROUND2 supersede 반영).

---

## UPDATE 2026-06-29 (session: #69 Phase1 1A-0 accessor-shim 완료)
- **#69 DONE (수용기준 2/2 충족, 미커밋).** Phase1 1A-0 = `QFILE_LIST_ID` 직접 필드접근(`first_vpid`/`last_vpid`/`tfile_vfid`/`dependent_list_id`)을 accessor 뒤로. additive·무동작. blocker #66/#67 둘 다 CLOSED 확인 후 착수.
- **변경**: query_list.h 4필드 trailing-underscore rename + lvalue accessor 매크로 4개(`QFILE_LIST_ID_{FIRST_VPID,LAST_VPID,TFILE_VFID,DEPENDENT}`) + `QFILE_CLEAR_LIST_ID` 만 raw 필드. consumer **361 사이트 / 16 파일** 변환(tfile+dependent 245 + first+last 116). raw `*_` 필드는 query_list.h 안에서만 등장(컴파일러가 F1/F3 surface 강제 열거).
- **워크트리**: HEAD=`e21917cfd` 유지, src 16파일 **미커밋(M)**. 선재 더티(`m cubrid-cci`, `?? bench/...`) 미접촉. (방안 E 5파일은 #67 에서 이미 복귀됨 — 이번에 재오염 없음.)
- **게이트 G0 PASS(무동작 증명)**: wmloc SORT/DISTINCT/GBY + tpch_sf10 heavy-spill DISTINCT, serial==parallel 완전일치(robust 집계, md5 금지 준수). 빌드 검증 = #68 `gate_clean_install.sh`(release @ e21917c) PASS. 상세 evidence §I-6.
- **방법 메모(삽질방지)**: CUBRID `.c`=C++ 컴파일 → tree-sitter-c parse-error → ast_edit 는 `.cpp` 만. `.c` 는 unique-name(tfile/dependent) regex codemod + shared-name(first/last) 컴파일러-가이드. 열거 = per-TU `-fsyntax-only`(compile_commands.json). 환경: fresh 설치 PL 서버 부팅실패 → `stored_procedure=no` 우회(변경 무관).
- **다음 액션**: 1A 스캔계약(`QFILE_TAPE`+Tape벡터+3레벨 `qfile_scan_next`(tape_idx 관통)+`qfile_scan_prev` offset 산술+합성 N-Tape 게이트, plan §2 1A-1~1A-7). accessor 시그니처는 1A-1 이 구현만 교체(NH-3) — 무동작 surface 는 유지. (커밋 여부는 유저 판단 — 현재 미커밋.)
---

## UPDATE 2026-06-29 (session: #70 Phase1 1A 스캔계약 + #68 측정훅 1A 슬라이스)

- **#70 DONE (수용기준 3/3 충족, 미커밋).** Phase1 1A = offset-산술 Tapeset 스캔계약. **선례(px read_spec가 레거시 next_vpid 스캔을 래핑) 답습 거부** — SSOT §3.2/ADR 0002·0003대로 백킹 dispatch·next_vpid follow·page directory 제거, 페이지주소 = `page_at(page_offset)` 순수 산술.
- **신규 (hpp/cpp class, 유저 지시)**: `src/query/qfile_tape.{hpp,cpp}` — `qfile::tape`(추상 offset-주소 페이지공간) / `memory_tape`(RAM 프리픽스=동결 membuf, 1A 테스트 vehicle) / `tapeset`(순서 Tape 벡터) / `tapeset_scan`(tape_idx를 S_BEFORE/S_ON/S_AFTER 전 분기에 관통하는 새 상태머신: forward page_offset+1, backward/jump page_offset-1, 마지막 Tape 소진만 S_END, empty-Tape/0-튜플 페이지 skip) + C++ 브리지.
- **additive 통합**: `query_list.h` — QFILE_LIST_ID에 `tapeset_`/`owns_tapeset_`(NULL=레거시 무동작) + accessor, QFILE_TUPLE_POSITION에 `COORD_TAPE` union 멤버(**sizeof 48 불변** → query_manager 자기검증 통과), QFILE_LIST_SCAN_ID에 `tapeset_scan_`. `list_file.c` 스캔 진입점(scan_list_next/prev, jump, save_position, open/close, start/end_scan_fix)에 단일 top-branch + copy/clear 소유권 DEPENDENT_MODE별(SKIP=borrow/MOVE=transfer/PROHIBIT=none). **B1: 연산자 호출부 0 변경**(시그니처 무변경, git diff 확인).
- **빌드(=cubrid-build 스킬 `just build debug`)**: GREEN. ⚠️ **교훈**: `sa/CMakeLists.txt`는 자체 QUERY_SOURCES를 가져 `cubrid/`와 **양쪽 모두**에 신규 .cpp 등록 필요 — sa 누락 시 `libcubridsa.so` undefined-ref 링크실패(ad-hoc syntax 체크는 못 잡음, `just build`가 잡음).
- **게이트 PASS**:
  - 합성 N-Tape 단위테스트(`unit_tests/tapeset`, `just ctest debug`) 7/7 — forward/backward/jump(same/cross-tape/boundary)/empty-skip/terminal/S_END-on-last + 브리지 mirror + copy-mode + 측정훅. passthrough-tautology(evidence I-2) 회피: 새 상태머신을 실제 멀티-Tape로 직접 검증.
  - robust-parity G0(no-op 증명, debug, wmloc work_mem=2M): DISTINCT/ORDER BY/GROUP BY serial==parallel==golden(COUNT=4194304/SUM=8796090925056/MIN=0/MAX=4194303). **TRACE로 병렬 실제 가동 확인**(parallel workers:3, gather: mergeable list, ORDERBY 스필). tpch_sf10 heavy-spill DISTINCT(l_orderkey) serial==parallel(COUNT=15000000/SUM=449999872500000). debug no-assert/crash.
- **#68 — 1A 도달 슬라이스 해결+검증(전체 미완: 1B/1C/2 구조 의존 훅은 stub 금지 원칙상 미빌드, 명시 deferral)**:
  - 측정훅 본체 중 **subject가 1A에 존재하는 것만** 빌드: `tapeset_scan_metrics`(page_reads/tuple_reads/tape_advances/jumps/copies/peeks + **pgbuf_fixes=0 = pgbuf-bypass 하드게이트 스캔측**). 단위테스트 G7 + `bench/harness/gate_tapeset_scan.sh`(preflight 후 실행되는 #68 측정 게이트)로 검증. SSOT §6 게이트 4(backward/jump)·6(스캔측)·합성 N-Tape = measurable.
  - baseline: e21917cfd "before"는 evidence §C/§D(VTune `rawfd_find_and_mark_dirty` 22.7s, strace raw-fd 202,866 I/O/GiB·이중스필 +13.5GiB)에서 이미 측정 — 인용.
  - deferred 정확 기록: `bench/harness/checklists/issue68_hooks.md` (orphan→1C, CoV→Phase2, membuf/pgbuf-bypass producer측→1B, no-mixed→Phase2, cached→cached path).
- **워크트리**: HEAD=`63a2ef7d8`(#69) 유지, **미커밋**. tracked 변경 5파일(query_list.h+49, list_file.c+92, cubrid/sa CMakeLists +2/+2, unit_tests/CMakeLists +6) + 신규 untracked(qfile_tape.{hpp,cpp}, unit_tests/tapeset/, gate_tapeset_scan.sh, checklists/issue68_hooks.md). 선재 더티(cubrid-cci) 미접촉. (커밋 여부 = 유저 판단.)
- **환경 메모**: stale RELEASE cub_master/cub_server(e21917cfd 베이스라인, 21:20 기동, 활성 클라이언트 0)가 debug 포트 점유 → §G대로 정리 후 wmloc/tpch_sf10 debug 기동. `~/CUBRID/conf` `stored_procedure=no`(fresh debug PL 부팅 우회, 변경 무관). 셸 빌트인 `kill -9` 깨짐 → `/bin/kill -9` 사용.
- **다음 액션**: Phase1 **1B** (per-worker private BufFile 백킹 + membuf Option-A freeze + TDE 상속) — 1A `tape`의 file-backed 구현(`page_at`=offset pread, pgbuf 우회) + #68 pgbuf-bypass **producer측** 카운터 + membuf 재활성 게이트. 그 후 1C(holdable reparent + orphan scan).
---

## UPDATE 2026-06-29 (session: #71 Phase1 1B per-worker 백킹 + #68 producer측 측정훅)

- **#71 DONE (수용기준 3/3 충족, 미커밋).** Phase1 1B = per-worker private BufFile 백킹 + membuf Option-A freeze + TDE 상속. **additive no-op**(신규 클래스가 producer 에 미연결, QFILE_LIST_ID_TAPESET 여전히 NULL → 실쿼리 무영향).
- **신규 (hpp/cpp class, 유저 지시)**: `src/query/qfile_buffile.{hpp,cpp}` — `qfile::buffile`(자기 배치버퍼+fd·owner-only append·배치 flush·offset 산술 read·**pgbuf BCB 우회**·TDE per-page). `qfile_tape.{hpp,cpp}` 확장 — `qfile::buffile_tape`(`[membuf prefix RAM] ++ [buffile]` offset 산술 page_at) + `qfile::tape_writer`(membuf Option-A: work_mem prefix RAM, 초과분 BufFile, freeze=zero-copy → tiny면 memory_tape / 스필이면 buffile_tape).
- **TDE**: `tde_encrypt_data_page`/`tde_decrypt_data_page`(is_temp, IO_PAGESIZE, fresh-nonce-per-page) = raw-fd 검증 기계 이식. membuf prefix=plaintext.
- **빌드**: `just build debug` GREEN(설치 `~/CUBRID`→debug `4fb599d`). cubrid/+sa/ CMakeLists 양쪽 `qfile_buffile.cpp` 등록(#70 sa-undef 교훈).
- **게이트 PASS**:
  - `unit_tests/tapeset` 10/10 (`gate_tapeset_scan.sh` PASS): 신규 **G8** file-backed robust parity(forward/backward/jump, prefix↔file 경계, producer+scan pgbuf_fixes=0)·**G9** tiny-no-spill(spilled=false, 디스크 미접촉)·**G10** multi-Tape spill+tiny mix(producer pgbuf-bypass).
  - **TDE in-server (SA, wmg003 TDE)**: `BUFFILE_SELFTEST algo=1 result=0` — 20page encrypt→pwrite→pread→decrypt 바이트일치 + pgbuf_fixes=0. (이후 "PL server can not be started" = fresh-debug PL 기존이슈, 1B 무관.)
  - no-op 확인: wmg003 SA `SELECT count(*) FROM db_class`=75 정상.
- **#68 — producer측 측정훅 해소+검증.** `buffile_metrics.pgbuf_fixes`(producer pgbuf-bypass=0) + `tape_writer.spilled/prefix_pages/file_pages`(membuf 재활성/tiny-no-spill). `checklists/issue68_hooks.md` 1B 행 2건 **DONE**. 남은 deferred = 1C(orphan/reparent)·Phase2(CoV·no-mixed-backing)·cached.
- **워크트리**: HEAD=`4fb599d42`(#70) 유지, **미커밋**. tracked 변경: qfile_tape.{hpp,cpp}, cubrid/sa CMakeLists, query_manager.c, unit_tests/tapeset/test_tapeset_scan.cpp. 신규 untracked: src/query/qfile_buffile.{hpp,cpp}. 선재 더티(cubrid-cci) 미접촉. (커밋 여부 = 유저 판단.)
- **환경 메모**: TDE selftest 는 SA 모드(`csql -S … <tde_db>`)로 실행 → 공유 master/실행중 서버 무영향(stale wmloc/tpch_sf10 서버 미접촉). bootless 단위테스트는 TDE 키 미로드라 plaintext 만; TDE 라운드트립은 in-server selftest 전용(스텁 금지). `~/CUBRID/conf stored_procedure=no` 우회 적용.
- **다음 액션**: Phase1 **1C** (holdable reparent: 백킹 소유권 tran→session 이동 + RAM prefix 포함 + reaper liveness `(tran,query) OR session-held` + session teardown 훅 + session-kill orphan-zero 측정훅) — 또는 Phase2(producer 이주: 스캔-우회 인벤토리 A~E + membuf 강제OFF 게이트 제거 + R2 offset-range work-stealing).
---

## UPDATE 2026-06-29 (session: #72 Phase1 1C holdable reparent + #68 orphan-scan)
- **#72 DONE (수용기준 2/2 충족, 미커밋).** Phase1 1C = holdable reparent 생명주기 + orphan-scan 측정훅. **additive no-op**(census/selftest 는 신규 백킹 클래스에서만 동작; 실 list 는 QFILE_LIST_ID_TAPESET==NULL → 무동작·zero-cost). 동시에 **#68 의 마지막 deferred(orphan scan: file + RAM prefix → 1C) 해소.**
- **핵심 발견**: reparent 의 MOVE(소유권 이전)·teardown(소유 시 destroy)은 **이미 1A(#70)가 `qfile_copy_list_id`/`qfile_clear_list_id` 의 tapeset 분기로 완비**(list_file.c:556-575/642-645). 1C 신규 = **orphan-scan census + zero-copy/teardown orphan-zero 검증**. 신 백킹은 tran-keyed reaper 에 미등록(pgbuf-bypass·private) → list_id 소유 RAII 로만 수명관리(질의종료 free / holdable session reparent), ADR 0001 reaper-widening 은 신 백킹엔 by-construction 충족(옛 백킹 병존은 Phase2).
- **신규 (hpp/cpp class, 유저 지시)**: `qfile::tape_backing_census`(process-wide atomic `open_files`+`held_prefix_pages`; `qfile_buffile.{hpp,cpp}`) — buffile ctor/dtor=file open/close, memory_tape/buffile_tape ctor/dtor/append=RAM prefix(owns 대칭). + `qfile_heldtape_selftest`(`qfile_tape.{hpp,cpp}`, env `CUBRID_HELDTAPE_SELFTEST`, qmgr_initialize debug-only). 불변식: reparent(MOVE)=zero-copy(양 카운터 불변), session teardown=orphan-zero(파일핸들 AND RAM prefix).
- **빌드/게이트**: `just build debug` GREEN(설치 `80f2bf8`). `unit_tests/tapeset` **13/13 PASS** — 신규 **G11**(spilled reparent: census +1file/+2prefix → MOVE 후 census 불변=zero-copy → 잔여행 parity → teardown orphan-zero → no double-free), **G12**(tiny all-RAM: open_files 무변동, RAM orphan-zero), **G13**(borrow SKIP 가 owner Tape 미해제=single-owner) + **suite-wide orphan-zero**(census=={0,0}). in-server **`HELDTAPE_SELFTEST algo=1 result=0`** (SA, demodb TDE): 실 on-disk 암호화파일 생성 → 실 `qfile_copy_list_id(MOVE)`/`qfile_clear_list_id` teardown → `stat()` unlink 확인 + scratch 빈 디렉토리 = 실파일 orphan-zero, TDE 백킹 reparent 커버.
- **no-op(실쿼리 무회귀)**: 1C 는 실쿼리 경로 **0 라인** 추가(census=신클래스 ctor/dtor 한정, list_file.c scan/copy/clear 무변경, query_manager.c=dormant debug env-gate). fresh isolated DB SA 실쿼리(재빌드 debug): DISTINCT/GROUP BY/ORDER BY robust 집계 정확(SUM=Σ ✓)·assert/crash 없음. serial==parallel G0 베이스라인은 #69/#70 기수립, 1C additive 라 불변.
- **워크트리**: HEAD=`80f2bf810`(#71) 유지(**소스 클린**, 커밋 안 됨). tracked 변경 6파일: qfile_buffile.{hpp,cpp}, qfile_tape.{hpp,cpp}, query_manager.c, unit_tests/tapeset/test_tapeset_scan.cpp (+645). 신규 .cpp 없음 → CMake 무변경. 선재 더티(cubrid-cci) 미접촉. (커밋 여부 = 유저 판단.)
- **방법 메모(삽질방지)**: 부트리스 유닛테스트에서 `qfile_copy_list_id`/`qfile_clear_list_id` 직접호출 **금지** — 내부 `thread_get_thread_entry_info()`(인자 선평가)가 thread-local entry assert(`cubthread::get_entry`) → abort. G11~G13 은 MOVE/SKIP 2~4줄 분기를 **명시 미러**로 검증하고, 실 함수 배선은 in-server selftest 가 검증. demodb 의 `tp_domain_init` assert 는 fresh-debug stale-catalog/SA 기존 이슈(내 코드 dormant 상태에서도 발생 → 1C 무관) — fresh DB 는 정상.
- **#68 상태**: orphan(1C) 행 DONE. 남은 deferred = Phase2(CoV·no-mixed-backing)·cached. `checklists/issue68_hooks.md`/`gate_tapeset_scan.sh` 갱신.
- **다음 액션**: Phase1 종료 → **Phase2 (MIGRATE)**: producer 이주(스캔-우회 인벤토리 A~E 리팩터) + membuf 강제OFF 게이트 제거→재활성 + R2 64page offset-range work-stealing(CoV 측정훅) + 마이그레이션 backing-kind 태그(no-mixed-backing assert). 2A-EXIT exhaustive 심볼 sweep 후 Phase3.
---

## UPDATE 2026-06-29 (session: #73 Phase2 R2 distributor + no-mixed-backing 태그 + #68 잔여 2훅 해소)

- **#73 진척 (Phase2 MIGRATE 인프라 2종 착지, 미커밋) / #68 잔여 deferred 2건(CoV·no-mixed-backing) 해소.** Phase2 의 **라이브 producer/consumer 이주(인벤토리 A~E)·membuf 강제OFF 게이트 제거·2A-EXIT sweep 은 미착수**(정직한 잔여, 스텁 금지) — 이번 슬라이스 = R2 분배 + 병존-dispatch 불변식, 둘 다 #68 의 Phase2-subject 였음.
- **신규 (hpp/cpp class, 유저 지시)**: `src/query/qfile_chunk.{hpp,cpp}` — `qfile::chunk_distributor`: 동결 Tapeset 의 논리 페이지공간을 **64page offset-range Chunk** 로 쪼개 공유 atomic `fetch_add`(work-stealing)로 N reader 에 분배(ADR 0003 R2). per-Tape 메타=누적 chunk offset(O(n_tapes)), 글로벌 chunk index→(tape,start,count) **on-the-fly 산술**(대용량 스필서도 page/chunk 테이블 미materialize — bitmap/sector/directory 없음). `r2_metrics`(total_pages/chunks/per-reader 분포/CoV). membuf prefix=저-offset 으로 동일 분배(RAM 공유주소). overflow-continuation=first-page owner 만 처리(reader 측).
- **신규 (query_list.h)**: 마이그레이션-한정 **backing-kind 태그** `QFILE_BACKING_KIND{NONE/OLD/NEW}` + `backing_kind_` 필드 + `QFILE_LIST_ID_BACKING_KIND` accessor(`QFILE_CLEAR_LIST_ID` 초기화). 직렬화 무관(`or_listid_*` 필드별 — tapeset_ 선례와 동일). no-mixed-backing predicate `qfile_list_has_old_backing`(real first_vpid OR tfile_vfid) / `qfile_list_has_new_backing`(tapeset) / `qfile_list_is_mixed_backing` + `qfile_check_no_mixed_backing`(debug assert=production form). **라이브 dispatch 배선은 producer 이주(연산자별 원자)와 함께 — 이번엔 미배선**(additive no-op, 메커니즘+게이트만).
- **빌드(=cubrid-build 스킬 `just build debug`)**: GREEN. `qfile_chunk.cpp` cubrid/+sa/ CMakeLists **양쪽** 등록(#70 sa-undef 교훈). 설치/repoint 완료(`90dd15b` embed sha=HEAD, 미커밋 변경 반영).
- **게이트 PASS** (`gate_tapeset_scan.sh`, debug, **exit 0**): `unit_tests/tapeset` **15/15** + suite-wide orphan-zero.
  - **G14** R2: (a) **실 동시성** 커버리지 — 6 reader 스레드, skewed 멀티-Tape(huge+tiny+empty)서 전 페이지 정확히 1회 청구(gap/double-claim 0); (b) 거대 단일 Tape(6417p) 8-reader 등속 → **CoV ≈ 3.8% ≤ 15%** + per-reader spread ≤ 1 chunk(64p); (c) huge+다수 tiny skew 도 ≤ 15%.
  - **G15** no-mixed-backing: 검사가 **판별(discriminate)** 함 증명 — clean OLD/clean NEW 통과, 합성 mixed(old VPID/tfile + tapeset) 포착. (passthrough-tautology 회피: clean 만 통과시키는 게 아니라 위반을 잡는다.)
  - 게이트 스크립트 버그 1건 수정: `grep -q "FAIL"` 가 테스트 **이름**의 "FAIL-03/06" 토큰에 오탐 → `grep -qE "FAIL \("`(실제 실패 출력 포맷)로 정밀화 + G15 라벨에서 FAIL 토큰 제거.
- **no-op(실쿼리 무회귀)**: query_list.h(광범위 include)변경 + 신규 분리 클래스가 어떤 producer/consumer 에도 미연결(QFILE_LIST_ID_TAPESET 여전히 NULL·chunk_distributor 미참조). fresh isolated DB SA 실쿼리(재빌드 debug): DISTINCT COUNT=1000/SUM=499500(=Σ0..999)/MIN=0/MAX=999, GROUP BY 1000 groups/2000 rows, ORDER BY ASC 0,0,1/DESC 999,999,998 — robust 집계 정확·assert/crash 없음.
- **워크트리**: **커밋 `7fb9300ff`** (`[temp-workmem PHASE 2] R2 offset-range work-stealing distributor + migration no-mixed-backing tag (#73, #68)`), **푸시 완료** `xmilex/feature/temp-workmem-redesign`(`90dd15b3f..7fb9300ff`). 커밋 6파일: query_list.h(+backing-kind), cubrid/sa CMakeLists(+qfile_chunk), unit_tests/tapeset/test_tapeset_scan.cpp(+G14/G15), 신규 `src/query/qfile_chunk.{hpp,cpp}`. 하네스(gate_tapeset_scan.sh/issue68_hooks.md)는 untracked 유지(#69~#72 패턴). 선재 더티(cubrid-cci) 미접촉. 환경: `~/CUBRID/conf stored_procedure=no` 우회(fresh-debug PL, 변경 무관).
- **GitHub**: **#73 CLOSED(completed)** — 인프라 슬라이스 완료(커밋#+작업보고서+criteria 표 게시). **#68** 커밋참조 코멘트(게이트3·7 DONE). **#78 신규 생성** `[redesign G009] Phase2 MIGRATE producer 이주` — #73 의 미착수 본체(아래 잔여 (a)~(f)) 재추적.
- **#68 상태**: CoV(게이트3)·no-mixed-backing(게이트7) 행 **DONE**(`checklists/issue68_hooks.md`/`gate_tapeset_scan.sh` 헤더 갱신). **남은 deferred 단 1건 = cached-persist 교차-트랜잭션(게이트5) → cached copy-out path**(Phase2 subject 아님, 별도 작업).
- **#73 잔여(대형 본체, 미착수)**: (a) 스캔-우회 소비처 A~E 라이브 리팩터(membuf 직접/membuf==NULL 분기/first_vpid 범위분할/next_vpid 직접/sector 분배 — evidence §H-3), (b) membuf 강제OFF 게이트 제거→재활성(connect_list assert·use_connect·PRIVATE_SPILL·NOT_USE_MEMBUF — §H-4), (c) producer pre-sized slot 생산 + chunk_distributor 라이브 배선 + hash join per-worker tape import(ADR 0004), (d) backing-kind 태그 producer 배선 + no-mixed assert 라이브 배선, (e) **2A-EXIT exhaustive 심볼 sweep**(Phase3 진입 전제), (f) 전 경로 robust-parity. 이게 #73 의 acceptance 5항 중 3항(2A-EXIT sweep·라이브 membuf 재활성·migration 후 robust-parity)을 채운다 — CoV·no-mixed-backing 2항은 이번에 충족.
- **다음 액션**: #73 의 (a)~(f) producer 이주 본체. 권장 시작 = sort(단일 Tapeset) producer 를 chunk_distributor/tape_writer 로 1개 연산자 원자 전환(backing-kind=NEW 마킹 + no-mixed assert 배선) → robust-parity(serial==parallel) 게이트 → 이후 hash join/parallel-scan.

## UPDATE 2026-06-30 (session: #78 Phase2 2A-0 완료 + 2A-1a producer hook 착지)

> 작업 브랜치 **`wm-integ-7173-develop`** (xmilex fork). HEAD/원격 동기. ultragoal ledger(`.gjc/_session-019f1733-…/ultragoal`)로 추적: **G001(2A-0) complete**, **G002(2A-1) active**, G003~G006 pending.

- **HEAD = `7a62d7f60`** (push 완료 `…→7a62d7f60`). 커밋 체인(전부 #78·#73 병기):
  - `43083adf8` **2A-0** — ADR0005 read_page 재진입+`tapeset_reader`(per-reader view), ADR0006 overflow-continuation(연속 run+first-page-owner+O(1) skip+`chunk_distributor::skip_to_after`), 일반화 **production-hard backing-kind entry guard**(`qfile_backing_guard` er_set; OLD connect/append/sector-scan + NEW tapeset_scan_open)+A~E 카운터. unit G16/G17/G18 추가.
  - `fc4974dd4` **2A-0 P3 리뷰수정** — connect_list 가드를 VPID assert 위로, `tape_writer::freeze` OOM-safety.
  - `7a62d7f60` **2A-1a producer hook (dormant/gated)** — `QFILE_LIST_ID.producer_writer_`+`producer_page_`; qfile `allocate_new_page`/`close_list`/`is_first_tuple` NEW 분기(producer_writer_ 설정 시만; OLD 무변경), set_dirty NEW skip, overflow-on-NEW clean-error, clear 정리; 브리지 `qfile_producer_{create,append,freeze_tapeset,destroy}`+`qfile_producer_selftest`.
- **검증 (전부 실측, debug)**: gate `gate_tapeset_scan.sh` **G1-G18 green** · in-server selftest **`TAPEREAD_SELFTEST algo=1 result=0`**(wmloc+wmg003 TDE 동시읽기) · **`PRODUCER_SELFTEST algo=1 result=0`**(wmg003 TDE, 5000튜플→NEW page→freeze→tapeset_scan parity, backing_kind=NEW/no-mixed) · **robust-parity serial==parallel** wmloc(`;trace on` `parallel workers:8` + `serial_md5==parallel_md5`=40c47f2e…) · debug build green · architect 리뷰 **CLEAR/APPROVE**.
- **거버넌스**: SSOT(#75) **미변경**(전부 기존 설계 구현). evidence(#76 = `issue65_evidence.md`) **I-13(2A-0)·I-14(2A-1 설계)·I-15(2A-1a+2A-1b 진입점)** APPEND. #78 진척 코멘트 4건. ultragoal G001 checkpoint complete(quality-gate JSON: architect CLEAR/APPROVE + executorQa passed + artifacts `temp_workmem/artifacts/2a0_*.txt`).
- **남은 본체 (G002~G006)**: **2A-1b**(sort 엔진 배선: serial 출력 `srlist_id`@list_file.c:4864 NEW opt-in → parallel worker output_file + fan-in `sort_merge_run_for_parallel`@src/storage/external_sort.c:4868 이 worker tape를 srlist_id tapeset로 import; atomic-switch flag; membuf 재활성/tiny-no-spill; no-mixed/guard 라이브; **overflow-on-NEW producer stamping(ADR0006) 구현** — 현재 clean-error 스텁) → **2A-2** pre-agg → **2A-3** hash join(part_mutexes 제거+vestigial raw-fd 제거; #77 NEW서 해소) → **2A-4** inventory A~E residual 0 → **2A-EXIT** OLD-symbol sweep.
- **운영 gotcha (필독)**: ① **`just build` 마다 `~/CUBRID/conf`의 `stored_procedure=no` 소실** → 빌드 후 매번 재적용(`printf '\nstored_procedure=no\n' >> ~/CUBRID/conf/cubrid.conf`), 안 하면 서버 start가 PL boot 실패. ② `databases.txt`(`/home/cubrid/databases`)에 wmg003 재등록됨(`/home/cubrid/dev/workspace` 경로). ③ parity.sh는 `build_x86_64_release/_install` 존재 시 그쪽 CUBRID 선택 → debug 검증엔 `BUILD_WORKTREE=/tmp/none CUBRID=~/CUBRID SERVER_CTL=<wrapper> DB_NAME=<db>` override. ④ SA selftest는 실행중 서버가 DB 잠그면 충돌(먼저 server stop). ⑤ 빌드=`WORKSPACE=/home/cubrid/dev/cubrid-workmem just build debug|release`(cwd=/home/cubrid/dev/workspace). ⑥ untracked `bench/harness/results/*`(parity 산출물)·`m cubrid-cci` 커밋 금지.
- **다음 액션**: 2A-1b sort 배선(serial-first). 권장: 새 세션에서 강제 0 정독(SSOT #75 + evidence #76 §Z/§H/I-13~I-15 + ADR 0001-0006 + tape-model + plan + #78) 후 착수.

## UPDATE 2026-06-30 (session: #78 Phase2 2A-1b SORT producer 이주 — CORE 착지)
- **2A-1b SORT(ORDER BY/DISTINCT) producer 이주 CORE DONE+검증(env-gated, push 완료).** HEAD=`eb5d7e211` (branch `wm-integ-7173-develop`). 커밋 체인(전부 #78·#73 병기, push됨):
  - `7e5cb0504` ① **overflow-on-NEW producer stamping**(ADR0006): clean-error 스텁 교체. `qfile_producer_add_overflow_tuple`(연속 run START/continuation stamping) + `qfile_add_tuple_to_list`/`qfile_add_overflow_tuple_to_list` NEW 분기. 검증=PRODUCER_SELFTEST overflow round-trip(byte-exact, TDE).
  - `1b75074be` ② **serial SORT 출력 NEW**: `qfile_list_make_new_backed`(tfile 드롭+producer 부착, atomic) + `qfile_sort_list_with_func` 전환(do_close+toggle) + `sort_check_parallelism` serial-first. env `CUBRID_WM_SORT_NEW`(기본 OFF).
  - `eb5d7e211` ③ **parallel SORT NEW + fan-in Tapeset import**: 워커별 NEW 출력 + `qfile_tapeset_import`(worker 순서=globally sorted) + `px_output_is_new` 안정 캡처(do_close=false 정렬 OLD 유지). force-serial 제거.
- **검증(debug)**: G1-G18 green · PRODUCER_SELFTEST algo=1(wmg003 TDE, 5000+overflow) · env-on wmloc heavy DISTINCT(4.19M spill, parallelism=8) serial==parallel robust 집계 **완전동일** + `WM_SORT_NEW` 8개(origin+워커7) + `parallel workers:8` + no crash/leak · env-off group-by parity `40c47f2e`(OLD 무회귀).
- **★ gotcha 대장 = evidence I-16 (필독).** 핵심: (a) 생산중 NEW판별=`producer_writer_`(NOT tapeset_); (b) sort_check_parallelism이 worker_manager 예약→serial강제는 예약前; (c) resource leak/crash는 **CS 서버 debug 쿼리**로만 검출(SA selftest·unit 불충분); (d) **parity.sh result_rows md5는 trace/plan 오염 → 순수 집계 데이터행 비교**; (e) do_close=false 정렬(aggregate/analytic) NEW 금지; (f) ORDER BY는 aggregate-wrapper서 옵티마이저 drop→DISTINCT로 검증; (g) **`just build`가 conf 전체 재설치**(stored_procedure=no + parallelism/work_mem/data_buffer 전부 소실, 매빌드 후 재적용).
- **남은 2A-1b**: heavy tpch PSORT/DISTINCT serial==parallel(release) + median<=develop×1.10(release) + 기본 ON 전환(또는 2A-EXIT 글로벌 활성화). release 빌드는 이 세션서 완료(~/CUBRID→release).
- **다음 액션**: heavy/median 게이트 마무리 → 2A-2(parallel-scan pre-agg: px_scan_result_handler.cpp slot + query_aggregate.cpp:2517). **구현은 방향 확실시 executor subagent에 bounded 슬라이스 위임**(유저 지시); 리더는 설계/통합/검증/거버넌스.
- ledger: `.gjc/_session-019f179d-…/ultragoal` G001(2A-1b) active(heavy/median 잔여), G002~G005 pending. evidence #76=I-16 APPEND. SSOT §6 robust-parity 판정 주석 보강(아래).
