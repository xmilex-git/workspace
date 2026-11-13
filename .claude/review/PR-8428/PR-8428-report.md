# PR #8428 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8428](https://github.com/CUBRID/cubrid/pull/8428)
**제목:** [CBRD-27961] Keep the statement text when a set operation folds to one of its arms
**작성자:** soheejung-cs
**HEAD SHA:** `3599b53b4` (develop merge-base `38c931e7d`)
**JIRA:** CBRD-27961 (Correct Error, Confirmed) / 연관: CBRD-27583(회귀 원인, Regress), CBRD-28019(실행 때 두 갈래가 모두 거짓으로 접히는 다른 결함, 이 PR과 무관), CBRD-27932
**TC PR:** cubrid-testcases#4059 (`tc/pr-8428` `117fc72c`) / cubrid-testcases-private-ex#4766 (빈 draft)
**리뷰 일시:** 2026-11-11
**리뷰 결정:** 엔진 Approve, TC #4059 Approve, 코멘트 없음, #4766 리뷰 없음

> **TL;DR** (Non-blocking): 수정이 맞습니다. 집합 연산이 한 갈래로 접힐 때 남는 노드가 문장 텍스트(`sql_user_text`, 길이)를 받고, `db_compile_statement_local` 이 컴파일 전 텍스트를 되돌려, 드라이버 재컴파일(`db_recompile_for_bind_signature`)이 -452 없이 같은 문장을 다시 컴파일합니다. develop release 에서 Case 1·2·4 가 -452 인 TC 가 head debug·release 에서 통과하고, TLA+ 와 trace 검증도 통과입니다.

## Summary

- **변경 요약**: `pt_fold_union ()` 이 접은 결과 노드에 집합 연산의 텍스트·길이를 옮기고, `db_compile_statement_local ()` 이 `stmt_start_line` 처럼 텍스트·길이를 저장했다가 되돌림
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

## JIRA -> Engine PR

JIRA 첨부(`design.md`, `test.md`) 없음. Expected Result 와 본문의 수정 방향 후보로 판정.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: JDBC 준비문(바인드 1)이 1행 반환, -452 없음 | TC Case 1(JIRA 재현과 같은 꼴). 로컬 JDBC: 8개 준비문 모두 OK, 재컴파일 8회 ok=1 | 충족 |
| 바인드가 접히는 갈래 / 남는 갈래 모두 | TC Case 1·2, Case 4(VARCHAR 재컴파일) | 충족 |
| 수정 방향 후보: 접은 뒤 노드에 텍스트를 이어 줌 | `pt_fold_union` 복사 + `db_compile_statement_local` 복원 | 충족 |
| 두 갈래 모두 거짓(NULL 값으로 접힘) | 범위 밖으로 명시(CBRD-27932 [3]); 실행 시점 변형은 CBRD-28019 | 해당 없음 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 바인드가 접히는 갈래에 | #4059 Case 1 | 통과 |
| 바인드가 남는 갈래에 | #4059 Case 2 | 통과 |
| 갈래와 UNION ALL 양쪽 ORDER BY·LIMIT(파생 테이블로 접힘) | #4059 Case 3 | 통과 |
| VARCHAR 바인드(다른 타입 서명으로 재컴파일) | #4059 Case 4 | 통과 |
| 접히지 않는 대조 | #4059 Case 5 | 통과 |

#4059: 케이스 1개와 답 1개, 머리말에 `;` 없음, 본문 판정(develop release Case 1·2·4 -452, head OK)은 로컬 실행과 일치. #4766 은 변경 없는 빈 draft.
판정: Approve.

## TLA+ Verification

TLA+ 검증: 통과 — `.claude/review/PR-8428/tla/fold-text`
- 속성: C1 safety(드라이버 재컴파일이 -452 없이 자기 문장 텍스트를 컴파일) TLC 통과, IndInv 귀납성 Apalache (JIRA Expected) / C2 equivalence(부질의 안 집합 연산을 접어도 텍스트 그대로) 통과 (PR Implementation) / C3 safety(컴파일 뒤 문장 노드가 자기 텍스트·길이를 가짐, 둘째 문장·새 노드 포함) 통과 (PR Remarks, fdd1e3c8b) / TLAPS 요청 없음
- 결함: 없음
- mutant: 3개 모두 위반 검출 (`merge-base` -> OwnText, `no-restore` -> OwnText(두 문장 텍스트에서 번역이 새 노드를 돌려줄 때), `no-fold-copy` -> SubUnchanged)
- 비교 cfg `restore-only`: 컴파일 경로만 보면 복원만으로 C1·C3 가 성립하고, 런타임으로도 `pt_fold_union` hunk 를 뺀 release 빌드가 TC dir 103/103 통과. 다만 실행 시점에 바인드 값을 넣은 복사본을 다시 의미 검사하는 경로(`db_execute_and_keep_statement_local` -> `pt_semantic_type`)는 저장·복원 밖이라 `pt_fold_union` 복사만 텍스트를 지킴: 두 변경 모두 필요
- 경계: 텍스트당 문장 1~2개, 접기 2회, 번역의 세 갈래(같은 노드 / 새 노드 / 뷰 텍스트); scale 문장 3개; Apalache 문장 3개
- trace validation: 수용 3건(JDBC 16회 컴파일·8회 재컴파일, csql 두 문장 텍스트, 가상 클래스 계층), 거부 2건(복원이 다른 텍스트를 만남, 재컴파일 실패). 계측 빌드 3599b53b4 optdebug, CS, 브로커 경유 JDBC
- 반례: 없음. 참고: 모든 run 에서 복원 전에 이미 텍스트가 맞았음(pre=1). PR 본문이 말한 "가상 클래스 계층에서 번역이 뷰 텍스트를 가진 새 노드를 돌려주는" 경우는 재현하지 못함(새 노드 4건 모두 올바른 텍스트)
- `RESULT: OK` (18 cfg, run `fold-text-20261111-151656-1724560`)

## Runtime Verification

- CI 빌드 tarball, testcase `tc/pr-8428` `117fc72c`, `just ctp sql _13_issues/_26_2h`(103 케이스):
  - develop `38c931e7d` release: fail 1 = `cbrd_27961` (Case 1·2·4 `Error:-452`, diff 3곳) — fail-before
  - head `3599b53b4` debug: 103/103 / release: 103/103 — pass-after
  - head에서 `pt_fold_union` hunk 만 뺀 로컬 release 빌드: 103/103
- gha-ci run 42949801387(11-11): build, sql, medium, shell 통과; sql_by_cci fail 은 `cbrd_27337`, `cbrd_25984` 등 다른 PR run 에도 있는 기존 실패(최근 40개 run 중 16개 이상)뿐.
