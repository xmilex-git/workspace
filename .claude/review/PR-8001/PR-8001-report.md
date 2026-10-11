# PR #8001 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8001](https://github.com/CUBRID/cubrid/pull/8001)
**제목:** [CBRD-27379] Support hash join for SEMI JOIN and ANTI JOIN
**작성자:** youngjinj
**HEAD SHA:** `718f3699e` (develop merge-base `a59140bdd`)
**JIRA:** CBRD-27379 (Sub-task, Develop) / 연관: CBRD-23836 (부모, Support HASH JOIN), CBRD-27376 (Relates, 조인이 있는 서브쿼리 언네스팅). 같은 결함을 다루는 이슈 없음
**TC PR:** CUBRID/cubrid-testcases#3565 (`tc/pr-8001` `c27353c95`) / CUBRID/cubrid-testcases-private-ex#4232 (빈 draft, 파일 변경 없음)
**리뷰 일시:** 2026-10-08
**리뷰 결정:** 엔진 PR #8001 Comment / TC PR #3565 Request changes / #4232 리뷰 없음 (엔진 PR 코멘트로 close 요청)
**후속 (2026-10-10):** head 변경 없음. 작성자 답글(주석 제거, `qfile_slot_reset` 검토, 시나리오 TC 추가, #4232 는 머지 직전 close) 확인 후 엔진 PR #8001 Approve(review 5479197673). R8 은 사용자 결정으로 무대응. TC PR #3565 도 사용자 지시로 Approve(review 5479200252)

> **TL;DR** (Non-blocking): 엔진 변경에서 결과가 틀어지는 결함은 찾지 못했고 NIT 두 건만 남는다. 다만 JIRA DoD 가 요구하는 시나리오 TC 가 TC PR #3565 에 없어서 TC 판정은 미충족이다.

## Summary

- **변경 요약**: 해시 조인 실행기(직렬, 병렬)에 SEMI/ANTI 출력 규칙을 추가하고, 플래너가 SEMI/ANTI 를 해시 조인 후보로 평가하게 한다. SEMI/ANTI 결과 행 수 추정을 바꾸고, ANTI ON 절 조건 분류와 SEMI/ANTI 조인 순서 결함을 고친다
- **주요 이슈**: DoD 시나리오 TC 누락. 엔진 코드는 주석 정확성 NIT 1건, 튜플 레코드 API 일관성 NIT 1건
- **확인 필요 사항**: NL ANTI JOIN 이 마지막 조인일 때 after-join 조건이 일치 판정 안에서 평가되는 결함(develop 부터 있음, 이 PR 범위 밖)을 작성자에게 알리고 별도 처리 여부를 묻는다

---

## Findings

### Non-blocking (should consider)

- `src/query/query_executor.c:16534`: 새 aptr(조인 입력을 미리 만드는 하위 XASL) 생략 주석 표의 RIGHT 행에 붙은 "(merge join only)" 는 틀린 설명이다. 이 분기는 `HASHJOIN_PROC` 에서도 `merge_infop` 를 잡는다. 해시 조인도 `JOIN_RIGHT` 를 그대로 받는다(`hjoin_check_empty_inputs ()` 의 `JOIN_RIGHT` case). 그래서 해시 조인 RIGHT 에도 같은 생략이 적용되고, 그 동작이 맞다. 주석만 보면 해시 조인에서는 생략하지 않는 것처럼 읽힌다.
  ```c
   *   RIGHT       no (inner rows go out NULL-filled)   yes (merge join only)
  ```
- `src/query/query_hash_join.c:3626`, `:3935`, `src/query/parallel/px_hash_join/px_hash_join_task_manager.cpp:1157`, `:1513`: SEMI/ANTI 의 첫 일치 종료가 `build->tuple_record.tpl = NULL` 만 대입한다. 같은 루프의 자연 종료(`hjoin_probe_key ()` 의 not found)는 `qfile_slot_reset ()` 를 쓴다. 이 함수는 튜플 레코드의 `tpl`, `size`, 열 위치 캐시를 함께 초기화하는 API 다. PEEK 레코드(페이지를 복사하지 않고 가리키는 레코드)라 `size` 는 0 이고 다음 fetch 가 캐시를 다시 초기화하므로, 현재 결과에는 영향이 없다. 같은 API 를 쓰는 편이 낫다.

## JIRA -> Engine PR

기준: JIRA Expected Result 가 재현 조건에서 성립하고, design 변경이 모두 구현되고, 미정 항목이 해소되거나 남기는 이유가 명시되어야 한다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC-1 해시 조인 결과 (중복 키, NULL 키, 빈 입력, ON 추가 조건, SINGLE/PARTITION/PARALLEL) | 작성자 시나리오 1, 2 "통과" (빌드 미기재) + 리뷰 실행 R1, R2, B1-B4 | 충족 |
| AC-2 해시 조인 후보 평가, `USE_HASH`/`NO_USE_HASH` | 작성자 시나리오 3 + 리뷰 실행 계획 (SEMI/ANTI 에 `USE_HASH` 적용) | 충족 |
| AC-3 결과 행 수 추정 | 작성자 시나리오 4 "통과" (리뷰에서 재측정하지 않음) | 충족 |
| AC-4 ON 절 조건 분류, 조인 순서, 경로 표현식 언네스팅 제외 | 작성자 시나리오 5 + R3, R4, B3 (develop 오답 -> head 정답), R6 | 충족 |
| design 1-4 (실행기, 후보 평가, 추정, ON 절 분류) | 모두 구현 | 충족 |
| 미정 항목 | 없음. 선형 근사 한계는 후속 검토로 명시 | 충족 |
| DoD: 기존 QA 통과 | CI run 36973349027 sql/medium/shell 통과 (`tc/pr-8001`) | 충족 |
| DoD: 시나리오를 TC 로 추가 | TC PR 에 없음 | 미충족 |

판정: **부분**. DoD 의 TC 추가만 미충족이다. 연관 이슈 CBRD-23836, CBRD-27376 은 같은 결함이 아니다. R8(아래)은 AC-4.2 가 해시 조인 한정이라 판정에 넣지 않았다.

## TC PRs

기준: 시나리오가 JIRA 시나리오 파일에 있거나 TC PR 이 다루면 통과다. 변경된 케이스는 답안이 맞고, 헤더 주석에 `;` 가 없어야 한다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| TC-1-01 ~ TC-1-04 (AC-1.1~1.8, AC-4.1) | JIRA 시나리오 1 "통과". TC PR 에 없음 | 시나리오 있음, TC 없음 |
| TC-1-05 ~ TC-1-07 (AC-1.9~1.11, 실행 모드) | JIRA 시나리오 2 "통과". TC PR 에 없음 | 시나리오 있음, TC 없음 |
| TC-2-01 (AC-2 힌트) | JIRA 시나리오 3 "통과". TC PR 에 없음 | 시나리오 있음, TC 없음 |
| TC-3-01 ~ TC-3-06 (AC-3 추정) | JIRA 시나리오 4 "통과". CTP 가 계획의 card 를 마스킹(`card ?`)해서 답안으로 고정하기 어려움 | 시나리오 있음, TC 대상 아님 |
| TC-4-01 ~ TC-4-04 (AC-4) | JIRA 시나리오 5 "통과". TC PR 에 없음 | 시나리오 있음, TC 없음 |

- #3565 는 `cbrd_27465`(Case 1, 2, 5, 6, 9, 12, 13)와 `cbrd_27485`(Case 1-6)에 `USE_NL` 을 넣어 기존 NL 계획을 고정한다(Case 9 는 `USE_NL USE_HASH(b)`). 답안은 rewritten query 의 힌트 문자열만 바뀌었다. CI sql 이 `c27353c95` 로 통과했다. 바뀐 줄에 헤더 주석은 없다.
- #4232 는 develop merge 커밋만 있고 파일 변경이 없다.
- 결과적으로 SEMI/ANTI 해시 조인 계획을 답안에 고정한 TC 가 없다. 실행기나 ANTI ON 절 분류가 다시 깨져도 CI 가 잡지 못한다.

판정: **미충족**. DoD 의 시나리오 TC 가 없다. AC-1, AC-2, AC-4 를 `sql/_36_guava/cbrd_27379/` 에 넣도록 요청한다. AC-1.9 실행 모드는 trace 의 `SPLIT`/`PARALLEL` 줄로 답안에 남는다.

## Runtime Verification

- CI: run 36973349027 (head `718f3699e`). build debug(optdebug)/release 통과. sql 17472건, medium 975건(둘 다 `tc/pr-8001` `c27353c95`), shell 3282건(private-ex `tc/pr-8001` `5cf62fa17`) 모두 통과.
- 리뷰 실행: CI optdebug tarball 로 head `718f3699e` (libcubrid.so sha256 `48c7c15e...`)와 merge-base `a59140bdd` (`dea5915a...`)를 비교했다. 테스트케이스는 develop `9985a0a9e` 에 리뷰 전용 케이스 하나를 더했다(`just ctp sql _99_review_adhoc/pr8001_review`). 두 빌드 모두 core 와 hang 이 없었다. 정답 기준은 `NO_UNNEST`(서브쿼리 그대로 실행) 결과다.

| 사례 | develop | head |
|---|---|---|
| R1/R2 언네스팅 EXISTS / NOT EXISTS (중복 키, NULL 키) | NL, 정답 | 해시 = NL = 정답 |
| R3 ANTI ON 에 바깥쪽 전용 조건 `ra.cc is not null` (정답 3 4 7) | 4 (오답) | 해시 = NL = 3 4 7 |
| R4 ANTI ON 에 두 바깥쪽 테이블 조건 `ra.x = rc.x` (정답 2 3 4 5 7) | 3 4 (오답) | 해시 = NL = 2 3 4 5 7 |
| R6 SEMI ON 에 세 테이블 조건 | NL, 정답 | 해시 = NL |
| R7 비등가 상관만 있는 SEMI/ANTI + `USE_HASH` | 정답 | 힌트 무시 경고 후 NL, 정답 (오류 없음) |
| B1/B2 SEMI/ANTI 20만 행, PARTITION / PARALLEL(4) | NL, 정답 | 100000 / 100100, 모드별 동일 |
| B3 ANTI ON 에 바깥쪽 전용 조건 (정답 166767) | 33434 (오답) | 해시 2모드 = NL = 166767 |
| R8 LEFT JOIN + NOT EXISTS + `where rc.x is null`, ANTI 가 마지막 NL 조인 (정답 5 7) | 1 3 4 5 6 7 | `ORDERED USE_NL` 1 3 4 5 6 7, 해시 5 7 |

- R8 은 develop 부터 있던 결함이다. NL ANTI 가 마지막 조인이면 after-join 조건(외부 조인의 NULL 채움 쪽을 거르는 WHERE 조건)이 일치 판정 안에서 평가되어 거꾸로 작용한다. 이 PR 은 해시 경로만 맞게 했다. Findings 에 넣지 않고 엔진 PR 상위 코멘트로 알린다.
- 증거: `.git_ignored_dir/scratch/pr8001/evidence/{head,base}/pr8001_review.result`, 케이스 SQL `.git_ignored_dir/scratch/pr8001/adhoc/pr8001_review.sql`
