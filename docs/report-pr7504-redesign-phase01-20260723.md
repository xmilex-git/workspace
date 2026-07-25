# PR #7504 재설계 — Phase 0·1 완료 보고 (2026-07-23)

- 브랜치: `pr-7504-redesign` (base `3ffeab793`), **Phase 1 커밋 `1583d80d5`** (push 안 함)
- 계획: `docs/plan-20260723-pr7504-redesign.md` / ADR: `~/dev/bulk_index_build/docs/adr/0001-bulk-build-barrier-commit-time-postpone.md`
- 증거: `~/dev/bkx-redesign/evidence/` (하네스: `~/dev/bkx-redesign/harness/`, TC v4 작업본: `~/dev/bkx-redesign/tc-v4-work/`)

## Phase 0 — 기준선·픽스처 (완료)

- **t20g 20GB 픽스처 재생성 완료 (양 레인)**: dev(2320-dfeffb3)·tip(PR-head 2412-3ffeab7) 각각 341,000,000행/min 1/max 341M 정합, 레인당 ~19-22GB. 생성기 `mkfixture-20g.sh`(t_budget 규율), 측정 하네스 `measure-20g.sh`(pivot 계승, 레인별 loaddb 옵션 지원) 준비 완료. dev vs PR-head 배율 측정은 Phase 4 성능 캠페인에서 일괄 실행 예정(참고 기록용).
- 설치본: `CUBRID-pr7504-base`(PR head), `CUBRID-pr7504-p1v3`(Phase 1), 모두 release, `~/CUBRID` symlink 불변(INSTALL_PREFIX 격리).

## Phase 1 — Blocking 수정 (완료, 커밋 1583d80d5: 7 files, +144/-27)

### 1. 프로토콜 하위 호환 (network_interface_sr.cpp)
- `no_logging_index` tail을 정렬 경계 검사(`PTR_ALIGN + OR_INT_SIZE <= request+reqlen`) 하의 optional 필드로 — 부재 시 0(no-redo 비활성).
- **검증**: 구(11.5.0.2320) loaddb 클라이언트 → 신(p1v3) 서버: 빌드 정상, committed barrier 불변(3), copypage 증가 = logged 경로 [실측 PASS].

### 2. Barrier 재설계 (btree_load.c, log_recovery.c, recovery.{c,h}, log_manager.{c,h})
최종 형태 = **commit-time postpone + 2-rcvindex + media-aware redofun** (설계는 외부 리뷰 2회 반영으로 2회 진화, ADR에 supersede 이력 기록):
- barrier(`RVBT_BULK_BUILD_DURABLE`)를 `log_append_postpone`으로 기록 — rollback/abort된 빌드는 commit 시 postpone이 스킵되어 흔적이 남지 않음.
- postpone이 실제 실행될 때 redofun이 redo-only 마커 `RVBT_BULK_BUILD_COMMITTED`(신규 rcvindex 132)를 append. 두 redofun 모두 media recovery면 무조건 거부(완료 tran 조건 제거).
- **핵심 안전성 논증(전 절단점)**: media 분석은 CWP 상태를 만들지 않으므로(log_recovery.c:1285 실코드) 인덱스가 살아남으려면 LOG_COMMIT 재생 필수 → COMMIT은 마커 뒤 → 마커 재생 = 무조건 거부. ∴ **no-redo 인덱스가 살아남는 media replay는 반드시 먼저 거부**, 나머지 절단점은 전부 clean abort(성공+부재+데이터 보존+checkdb 0).

### 검증 배터리 (전부 실측 PASS)
| 레인 | 결과 |
|---|---|
| fail-before-fix (abort-class) | base: barrier 1건+인덱스 0개인데 restore **거부**(false positive 채증, LSA 637\|14528) → p1v3: restore **성공** |
| tc-replay-barrier R1/R2/R3 | R1 거부 유지·R2 시점복원·R3 이후백업 PASS |
| tc-loaddb-basic 옵션 매트릭스 | 발화 barrier=3(빌드당 1)·N1 csql·N3 무옵션·N4 SA 전부 logged 경로 PASS |
| tc-crash-restart (v4 kill-sweep) | C1 mid-build 포착(d=0.05, idx=0, 잔존 tran 0)·C2 재기동 생존 PASS |
| crash-window W0/W1/W2 (신규 w-probe) | mid-build/CWP직후/마커직후 → 전부 clean abort(부재+행 보존+checkdb 0) 또는 거부 PASS |
| restart recovery | CWP tran forward-commit, 인덱스 생존+마커 append [실측] |
| compat 구→신 | logged 경로 정상 [실측] |

### 실행 중 확정된 추가 사실
1. **loaddb는 statement 실패 시 전체 tran abort** → 리뷰의 savepoint-후-commit 시나리오는 현 제품 표면에서 조직적 도달 불가(FK 프로브 실측). 설계상 log_do_postpone의 rollback-구간 스킵이 커버, abort-class 실측이 그 기계를 검증.
2. crash 직후 media 분석은 torn tail을 절단(resetlog)할 수 있음 — W2에서 마커 소실 시 clean abort로 수렴(안전 방향).
3. `ALTER ADD FK`의 인덱스 빌드는 no-redo 미발화(pending=0) — no-redo 표면은 CREATE INDEX 적재 한정.
4. TC 번들 v4 갱신분: `barrier_count`=COMMITTED 계수(빌드당 1 불변식 복원), `barrier_pending_count` 신설, C1 kill-sweep(빠른 호스트 타이밍 플레이크 수정), kill 스코프를 자기 DB로 한정(**타 캠페인 서버 오살 사고 2건 재발 방지** — 본 세션에서 실제 발생·복구).

### 운영 사고·복구 (투명 보고)
- tc-run 트랩의 `pkill cub_master` / 번들 TC의 `pgrep -x cub_server` kill-all이 픽스처 생성 서버를 두 번 죽임 → 두 지점 모두 스코프 수정, 픽스처는 재개 스크립트로 무손실 복구(341M 정합 확인).

## 다음: Phase 2 (경계 접기)
6-op `SORT_PX_OUTPUT_OPS`(3상태 prepare, transactional prepare, finish 전이 원자성) + `SORT_PUT_FUNC` 재사용 + btree_load.h extern 14개 제거. executor 투입 예정.
