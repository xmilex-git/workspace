# bulkidx 세션 요약 (2026-07-15) — 작업/검증/커밋/현안

대상 브랜치: `bulkidx/noredo-parallel-r304-wip` (worktree `/home/cubrid/dev/worktrees/r304-bulkidx`), 원격 검증: `.32:/home/cubrid/dev/bulkidx-r304/v2` (SSH 전용). push 0회. gdb/core 분석 0회. 20MB 초과 신규 텍스트 0개.

## 1. 이 세션에서 한 일 (시간순)

| # | 작업 | 결과 |
|---|---|---|
| 1 | G012(OV-04/05 결함) 마무리 — 죽은 리뷰(429) 재파견 → architect 1차 WATCH/REQUEST CHANGES(F1~F5) | fix6 커밋 + 2차 CLEAR/APPROVE → **G012 완결** |
| 2 | F1~F5 해소: `3f8cd6ff4` 커밋 + oracle/스펙 개정(grilled §0/§8.2/D9, ralplan §F-2/R7/§1.4/§3.2 — COPYPAGE=0 → "정확히 1건 & VPID==sticky root") | .32 재검증 4케이스 전부 green |
| 3 | G004 FL+TX 캠페인(.32) 실행 → architect BLOCK → blocker 해소(51 사용자 지시로 강제종료 → 52 승계) → 3차 CLEAR/APPROVE | **G004 완결** |
| 4 | G005 MR+BK 캠페인(.32) 실행 | MR/BK 대부분 PASS, **신규 제품결함 2건 발견** → G005 review_blocked, G013 등록 |
| 5 | G013 결함수정: BK-03 원인확정·수정(`9b1b4adf7`)·재검증 green / OV3 원인 미확정(추측수정 거부) | BK-03 **완결**, OV3 **미해결 blocker** — 현재 N=5 재현율 측정 진행 중 |
| 6 | 스토리지 정리 판정(별도 요청): CI/EX raw dump 37개=406.8GiB 삭제 1순위 식별, 20MB artifact cap 전 agent 강제 | 텔레그램 기송부, 삭제는 미실행(보스 승인 대기) |

## 2. 검증 완료 내역 (무엇을 어떻게)

**G012 재검증** (.32 release 3f8cd6ff4, fresh restore, 증거 `v209fix6-final.tar.gz`):
- OV-04(t_ovfm 40KB×5,000) / OV-05(t_ovfn 2,100B×100,000) / ZEROFIX(t_oc 병렬 zero-ovf) — CREATE + checkdb -I/-C rc=0 + DROP 정상.
- ZEROFIX-CRASH — commit 직후 kill -9 → 재기동 recovery → header/checkdb 무결.
- 개정 oracle 실측: 3케이스 모두 RVBT_COPYPAGE 정확히 1건, 대상 VPID=(0,123777)==sticky root, marker 1.

**G004 FL+TX** (.32, 증거 `fl-tx-final.tar.gz` + `fl-tx-fix-final.tar.gz`):
- FL-06: unique 위반 → 정확히 99,000행 삭제(잔여 1,000 singleton) → 재시도 O-COMMON green.
- TX-01/02/05/06: catalog/DML/marker/COPYPAGE/checkdb + 4질의 scan-eq + RECOMPILE plan 증명 전부 green.
- TX-04: 독립 fresh copy N=5 kill/재기동 — 매회 index 0·marker 0·file SHA baseline 동일·checkdb 0·retry 성공.
- TX-03: raw marker=0 oracle이 물리적으로 잘못임을 recovery 소스로 입증(**ORACLE BUG** 판정) → transaction-aware effective marker predicate로 ralplan 개정 후 PASS 재검증(marker Trid=11 → 후행 LOG_ABORT, COMMIT/2PC 0).
- T-FULL/FL-01/02/03/10: 제품이 데이터볼륨 최소 4096페이지(16K 페이지≈64.02MB)를 강제(소스 확정 util_sa.c:456-471→disk_manager.c:6841/259)하는데 .32 /dev/shm 총량 62.5MiB보다 커서 **16K 전제 환경한계** — 정적 대체 처리. `--db-page-size=4K` 편차 대안은 보스 판단 대기.
- 부수 사고 처리: .32 install 동시 재빌드로 인한 conf 거부/csql rc=139 → orphan cub_master 2개 정리 + canonical conf 채택으로 해소(사실만 기록).

**G005 MR+BK** (.32, 증거 `mr-bk-final.tar.gz`):
- MR-02(pre-commit stop-at): cleanup 0줄·index 부재·checkdb 0 (Case A). MR-03(post-commit): cleanup 정확히 1줄(v2 4필드)·index destroy·데이터 무결 (Case B). 결정성: 동일 restore 2회 diff=0.
  - ※ ralplan §2.7의 MR-02/03 기대치가 실제 Case A/B와 **뒤집혀 기재** — 계획 문서 결함으로 문서화(supersede 각주), 교정 predicate로 판정.
- MR-04: cleanup 중단 5회(0.3~5.0s, restoredb 자식 프로세스 kill) → 전부 동일 종착 상태 수렴(멱등).
- MR-05: restore leg PASS / O-CHECKDB leg FAIL → **DEFECT-OV3**. MR-06: v1 marker artifact 부재로 정직 한계. MR-01·2PC: EXIT2 기재만.
- BK-01/02: r304 스택엔 backup×build mutex 게이트가 실존(§2.8 amend는 r305 전제 — 부적용 문서화) → 구 직렬화 predicate로 PASS.
- BK-03(overflow): restoredb 자체 FATAL → **DEFECT-BK-03**. BK-03(non-ovf)/BK-04: partial image 0 증명 PASS.

**G013 재검증** (.32 release 9b1b4adf7, 증거 `defect-ov3-bk03-final.tar.gz`):
- BK-03 fix 후: t_up backup→restore **rc=0**(수정 전 FATAL rc=1)→cleanup 1줄 정상→300,000행 무결→checkdb 0.
- 회귀 4종: OV-04/OV-05/zero-ovf(t_oc) 3/3 green + MR-05 leg는 OV3 미수정이라 FAIL 사실대로 기록.

## 3. 코드 커밋 (검증 실패 → 수정)

이 세션에서 만든 제품 커밋 2건 (전부 로컬 debug+release 빌드 게이트 green, push 안 함):

**`3f8cd6ff4` [bulkidx] V2-09fix6: unify zero-ovf-key root publish, harden pool asserts** — src/storage/btree_load.c
- 계기: architect 리뷰 F2 — zero-ovf-key 병렬 경로가 root를 WAL 게시(2245) '후' ovfid NULL로 no-redo 재발행 → '마지막 mutation' 불변 위반 + COPYPAGE redo 이미지에 stale ovfid(media-restore 시 dangling VFID 위험).
- 내용: ① zero-ovf 판정+file_postpone_destroy+VFID_SET_NULL을 phase III root 조립 이전(2137-2148)으로 이동, post-hoc 재latch/재발행 블록 제거 → root page mutation은 단일 RVBT_COPYPAGE WAL 게시 1건뿐. ② ledger assert를 volid+pageid 검사로 강화(F3). ③ sticky-root-in-pool 조용한 흡수를 assert(false)+ER_FAILED로 소음화(F4).
- 검증: §2 G012 재검증 4케이스 + crash 테스트 green.

**`9b1b4adf7` [bulkidx] V2-10fix1: tolerate deallocated file header during bulk skip-redo check** — src/storage/file_manager.c (+17/−1)
- 계기: DEFECT-BK-03 — overflow-key no-redo 인덱스 백업 restoredb가 FATAL(`log_recovery_bulk_should_skip_redo → file_recovery_check_vpid → pgbuf 'fetching deallocated pageid 123840'`).
- 원인: skip-redo 판정이 파일 header page를 `OLD_PAGE`(dealloc 비허용 모드)로 fix하는데, zero-ovf 파일이 로그 타임라인 후반에 postpone destroy되면 이미 dealloc된 header를 fix → fatal.
- 내용: fetch mode를 `OLD_PAGE_MAYBE_DEALLOCATED`로 변경, ER_PB_BAD_PAGEID면 'NOT_MEMBER'(=redo 스킵 안 함, 보수적 안전값) 반환. 비-media-crash 경로 영향 0.
- 검증: §2 G013 재검증 — fail-before-fix 체인 완결(수정 전 FATAL 봉인 → 수정 후 rc=0).

부수(제품 아님): ralplan.md/grilled_plan_v2.md oracle 개정, REPORT-{CI-EX 승계,FL-TX,MR-BK}.md, DEFECT-OV3-BK03-analysis.md, 각 증거 tar.

## 4. 현안: DEFECT-OV3 (미해결, 판단 요청)

**증상**: zero-overflow 테이블 `t_ovf_m1`(100k행) 평범한 `CREATE INDEX`에서 두 가지 발현 — ① CREATE 중 라이브 crash, ② 빌드 성공 후 SA-mode checkdb rc=1 (CS-mode는 rc=0). 시그니처 `slot 0 ... is not allocated` (slotted_page.c assert).

**정확한 위치** (err 로그 내장 스택, gdb 미사용):
```
spage_get_record ← btree_get_node_header
← btree_build_nleafs        btree_load.c:1726 (Phase-I leaf-chain walk 1802-1831)
← bt_load_px_join_finalize  btree_load.c:4870
← sort_px_construct_index_leaf  external_sort.c:5219
```
leaf `next_vpid` 체인에 **끼워져 있지만 실제로는 한 번도 채워지지 않은 페이지**(run마다 VPID 다름: 252738/124035)를 걷다가 사망 → **비결정적(레이스)** 확정.

**배제된 가설(소스 인용, 6건)**: BK-03과 동일 원인 아님(media-crash 전용 경로), sticky-root WAL 게시 갭 아님, fileio_synchronize_all 순서 아님, worker leaf-close flush 누락 아님, btree_proceed_leaf 핸드오프 아님, reconcile tail-dealloc 아님.

**유력 가설(미확정)**: lock-free `BT_LOAD_PROVIDER` 페이지풀 할당자(span claim / cursor·n_published 원자 핸드오프 / span->used 계정)의 page-identity 레이스.

**진행 중**: N=5 fresh copydb + `log_btree_operations=yes` 재현율 측정(라이브 crash vs SA-checkdb crash vs 무증상 분류 + DEBUG_BTREE 발췌) — 결과 나오는 대로 보고.

**추천 해결 경로(리더 의견)**: N=5 결과로 발현율 고정 → install-debug(debug 빌드)로 재현해 provider ledger assert가 더 이른 지점에서 발화하는지 확인 → 원인 확정 후 최소 수정. 추측성 동시성 수정은 계속 금지 유지.

**보스 결정 필요(애매한 것들)**:
1. **OV3 수정 우선순위**: 병렬 빌드 전체의 정합성 결함이라 SEAL 전 필수로 볼지(리더 추천: 필수), G006(HA)·G007(종합리포트)을 OV3 수정 전에 계속 돌릴지.
2. **T-FULL 4K 페이지 변형**: `--db-page-size=4K`로 FL-01/02/03/10 동적 재현 시도할지(계획 16K 보정과 편차), 정적 대체로 종결할지.
3. **CI/EX raw dump 37개(406.8GiB) 삭제** 승인 여부 (기송부한 정리 판정문 참조).
4. **MR-06(v1 marker replay)**: 구 SHA 재빌드 금지 유지로 영구 한계 처리할지, 1dbb844 계열 재빌드 1회 허용할지.
5. **SHA 이질성**: G002/G003 증거는 1dbb844, G004~는 3f8cd6f/9b1b4ad 기반 — 최종 SEAL 전 구 그룹(CI/EX, OV/PX) 재실행 여부.
