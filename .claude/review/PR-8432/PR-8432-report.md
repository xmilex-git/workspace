# PR #8432 코드 리뷰 보고서 (2차)

**PR:** [CUBRID/cubrid#8432](https://github.com/CUBRID/cubrid/pull/8432)
**제목:** [CBRD-27973] Find the object a leaf swap left out of order in the first overflow page
**작성자:** shparkcubrid
**HEAD SHA:** `945478c64` (develop merge-base `1b2645925`). 1차 리뷰 `cca5378df` 이후 설계가 두 번 바뀜: v2(L1 유지, D를 라우팅 페이지에 삽입, jihyekim-0 이 롤백 중 할당을 지적) -> 이번 head(leaf swap 은 develop 그대로, directory 탐색 실패 시 앞 페이지 순회)
**JIRA:** CBRD-27973 (Correct Error) / 연관: CBRD-24094 (Regress), CBRD-27972 (같은 모델의 형제 이슈, PR #8431)
**TC PR:** CUBRID/cubrid-testcases-private-ex#4771 (`tc/pr-8432` `d4596a68`, jihyekim-0 Approve) / CUBRID/cubrid-testcases#4064 (빈 draft)
**리뷰 일시:** 2026-11-11
**리뷰 결정:** 엔진 Approve(1차 Request changes 해소) + 질문 인라인 1건(재시도 전 COMPACT), 1차 스레드 4510355356 답글 후 resolve, TC #4771 Approve, jihyekim-0 NIT 중복 안 함. 게시는 TLA+ 기록 실행 RESULT: OK 뒤

> **TL;DR** (작성자 확인 필요): 1차 Blocking(R1: 라우팅된 페이지의 객체를 leaf 로 올려 중단된 range scan 이 행을 놓침)은 사라졌다. 이번 head 는 쓰기 경로를 develop 그대로 두고, 제거 목적의 탐색이 directory 에서 못 찾으면 첫 페이지부터 라우팅된 페이지 앞까지 훑는다. 크래시 재현에서 재시작 뒤 vacuum 이 이 순회로 D 를 찾아 지웠고(checkdb rc 0), 스캔 누락 재현은 3/3 정상, TLA+ 는 develop·첫 페이지만 보기·1차 설계를 모두 반례로 잡는다.

## Summary

- **변경 요약**: `btree_ovf_dir_find_oid ()` 가 directory 탐색(라우팅 + step-back)에 실패하면, 객체 제거 목적(`DELETE_VACUUM_OBJECT`, `DELETE_UNDO_INSERT(_UNQ_MULTIUPD)`, `DELETE_OBJECT_PHYSICAL(_POSTPONED)`)에서만 `first_ovf_vpid` 부터 라우팅된 페이지 직전까지 페이지를 차례로 fix 해 찾음. `btree_replace_first_oid_with_ovfl_oid` 는 주석만
- **주요 이슈**: 없음
- **확인 필요 사항**: 재시도 전 COMPACT 경로를 다룰지(질문 1). jihyekim-0 의 NIT 2건 — 닿지 않는 `walk_prev_page` 분기, 유니크 전용 목적 case — 은 이미 달려 있음)

---

## Findings

### Questions for the author
1. `src/storage/btree.c:11522` (swap 주석의 "the retried delete finds it there") — 크래시 뒤 재시도 전에 `ALTER INDEX ... COMPACT` 가 D 가 남은 페이지 뒤에 다음 페이지의 앞 객체를 당겨 붙이면 페이지 안 OID 순서가 깨지고(D 뒤에 더 작은 OID), 그 객체를 페이지 안 이진 탐색과 directory 로 찾지 못하는 경로가 TLA+ 모델에 나온다(`witness-preexisting-compact`, 런타임 미재현). develop 은 D 를 영구히 남기므로 노출은 원래 있던 것이고 이 PR 은 창을 재시도까지로 줄인다. #8431 의 안정 객체 검사도 이 경우를 막지 않는다(leaf 에 L1 이 안정 객체). 여기서 다룰지 별도 이슈로 둘지 묻는다(grill: 질문으로 게시).

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: swap 1단계 직후 크래시 -> 재시작 -> vacuum 뒤 D 엔트리가 남지 않음, checkdb 정상 | 계측 head 빌드 + JIRA `h2_repro.sh`: `FindMiss`(라우팅 page 0\|4742) -> `FindWalk`(page 0\|4739, 첫 페이지) found, D 사라짐, index = heap = 1,915, `checkdb -C --check-btree-entries` rc 0 | 충족 |
| INSERT 롤백 중 크래시 -> 재시작 복구 undo 가 D 를 찾음 | 같은 순회(`DELETE_UNDO_INSERT`). 로컬 미실행, jihyekim-0 리뷰에서 복구 성공 확인(크래시 훅) | 충족(타인 증거) |
| 중단된 스캔 전제(leaf 로 오는 객체는 첫 페이지 마지막) 유지 | swap 코드 develop 과 동일. h3 재현 3/3 9,974/9,974, Swap page = 첫 페이지 | 충족 |
| 롤백 경로에 페이지 할당 없음(v2 지적) | swap 은 제자리 교체, 순회는 fix 만 함 | 충족 |
| 정상 vacuum 비용 | 순회를 제거 목적으로 한정(`DELETE_VACUUM_INSID` 제외). 작성자·jihyekim-0 측정: 건당 OVFP 읽기 3~4페이지(develop 4, 한정 전 448) | 충족(타인 측정) |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| leaf 로 오는 객체 = 첫 페이지의 마지막 객체(2페이지 체인, D 라우팅) | #4771 검사 1-3 | 통과 |
| 첫 페이지가 객체 1개 | 검사 4 | 통과 |
| 라우팅된 마지막 페이지가 객체 1개 | 검사 5-6 | 통과 |
| 단일 페이지 체인 / OID 재사용 / 다른 키 불변 / 최종 checkdb | 검사 7-10 | 통과 |
| 두 단계 사이 크래시 뒤 재시도 | TC 로 만들 수 없음(본문에 명시), 로컬 크래시 훅 재현으로 대신 | 해당 없음 |

#4771 은 develop 과 head 에서 모두 OK 인 회귀 방지 TC(1차 설계에서 검사 3·6 NOK)로, 실제 수정 경로(크래시 재시도)는 지나지 않는다고 본문이 밝힘. 셸 heredoc 머리말, 검사마다 `write_ok/nok`. gha-ci shell 통과(`tc/pr-8432` `d4596a68`). #4064 는 빈 draft.
판정: Approve.

## TLA+ Verification

TLA+ 검증: (record run 결과로 채움) — `.claude/review/PR-8432/tla/leafswap-walk`
- 속성: C1 safety(크래시 뒤 언제 오든 재시도가 D 를 찾음, 그 사이 삽입·분할·다른 swap 포함) TLC 통과 / C2 safety(재시도 대기 D 외에는 OID 순서) 통과 / C3 safety(대기 D 외 모든 객체 라우팅 가능) 통과 / C4 safety(손실·중복 없음) 통과 / C5 safety(중단 스캔이 보이는 행을 정확히 한 번) 통과 / C6 liveness(스캔 종료) 통과 / IndInv 귀납성: 추상 모델 `OvfOrder` TLC 만(Apalache 타입 불가) / TLAPS 요청 없음
- 결함: 없음
- mutant: 12개 모두 위반 검출. 핵심 셋: `mutant-merge-base`(directory 실패가 최종) -> RetryFindable, `mutant-first-page-only`(JIRA F2, 첫 페이지만) -> 재시도 전 삽입이 첫 페이지를 분할하면 D 가 새 페이지로 가 RetryFindable, `OvfScanResume.mutant-routed-swap`(1차 head) -> ExactlyOnce
- 경계: main OID 3 x 버전 2, 페이지 2; 크래시 cfg OID 6, 페이지 3(804,280 상태), scale OID 7; 스캔 OID 4, scale 3 x 2
- trace validation: 수용 1건(크래시-재시도 run, 1,916 객체 키, 마지막 키 덤프까지 일치), 거부 2건(순회가 둘째 페이지에서 찾음, 크래시 이벤트 누락)
- 반례: head 반례 없음. 작성 중 모델 오류 2건(재시도가 leaf 를 먼저 보는 코드 누락, 페이지 용량 2 의 분할 인공물), COMPACT 노출은 develop 의 기존 경로로 분류(위 참고)

## Runtime Verification

- 계측 optdebug(head `945478c64` + JIRA `tla-evidence` 패치 + FindMiss/FindWalk 로그, `~/optdebug/CUBRID-pr8432-tla`, `parallelism=1`):
  - 크래시-재시도(JIRA `h2_repro.sh` + 키 덤프): 위 JIRA 표 1행. purpose 10(`DELETE_VACUUM_OBJECT`).
  - 스캔 누락(1차 `h3_repro.sh`, 재개 8초 지연 + vacuum 게이트): 3/3 `expected=9974 returned=9974`, Swap 은 첫 페이지 `0|4751` 의 마지막 객체 이동. 1차 head 는 3/3 9,973(행 1개 누락).
- gha-ci run 42770255789(head `945478c64`, `tc/pr-8432` `d4596a68`): build·sql·medium·shell 통과, sql_by_cci fail 은 기존 CCI 실패 목록(다른 PR 과 같은 34개).
- fail-before(develop 에서 D 가 남음)는 JIRA 첨부 기록과 1차 리뷰 때 재현을 재사용.

## Existing Comments

- 1차 인라인(4510355356, R1): 작성자가 설계를 바꿔 답함(4519769311). 이번 head 에서 R1 사라짐 확인 -> 답글 후 해결 처리 대상.
- jihyekim-0 인라인 NIT 2건(14055 `walk_prev_page` 분기, 14008 유니크 전용 case): 작성자 답 없음. 중복 게시하지 않음.
