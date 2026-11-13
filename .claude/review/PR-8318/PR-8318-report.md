# PR #8318 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8318](https://github.com/CUBRID/cubrid/pull/8318)
**제목:** [CBRD-27794] Do not eliminate an outer join when the ON condition converts the unique column so that distinct values become equal
**작성자:** shparkcubrid
**HEAD SHA:** `c75b1c11a` (develop merge-base `d93145bdb`, 이후 develop 의 `src/optimizer/rewriter`, `src/parser` 변경 없음)
**JIRA:** CBRD-27794 (Correct Error, Develop) / 연관: CBRD-24182, CBRD-26415
**TC PR:** CUBRID/cubrid-testcases#3930 (`tc/pr-8318` `0a598b27a`) / CUBRID/cubrid-testcases-private-ex#4621 (빈 draft, init 커밋만)
**리뷰 일시:** 2026-10-30
**리뷰 결정:** 엔진 #8318 Approve at `72ad4e886` (rebase, patch 동일; inline 2: Finding 2 제안, Finding 3 NIT; review 5707280420) / TC #3930 Approve at `a5fc0dd91` (Finding 1 은 작성자가 먼저 삭제; review 5707296423) / private-ex #4621 리뷰 없음 / 호스트 변수 TC 부재·첨부 부재는 미게시

> **TL;DR** (Non-blocking): 엔진 변경은 JIRA 재현 1~5 를 모두 고치고, 직접 돌린 probe 에서도 틀린 결과가 나오는 조인 제거는 찾지 못했다. 다만 TC PR #3930 에 작업 도구의 에러 로그 파일(`.omc/state/last-tool-error.json`, 내부 IP와 경로 포함)이 들어가 있어 TC PR 은 머지 전에 이 파일을 지워야 한다.

## Summary

- **변경 요약**: LEFT OUTER JOIN 제거(`qo_reduce_outer_joined_tbls`) 판단에서, ON 절 `=` 의 유니크 컬럼 쪽 식 트리와 `=` 의 비교 형을 검사해 서로 다른 값이 같아질 수 있으면 조인을 유지한다.
- **주요 이슈**: TC PR #3930 의 `sql/_36_guava/cbrd_27794/cases/.omc/state/last-tool-error.json` 잘못 커밋된 파일.
- **확인 필요 사항**: PR 본문의 "새로 막히는 경우는 `u.d || ''` 하나" 는 코드보다 좁다. DATE = DATETIME, FLOAT = DOUBLE 도 새로 조인을 유지한다(정답은 같음).

---

## Findings

### Blocking (must fix)

1. (TC PR #3930) `sql/_36_guava/cbrd_27794/cases/.omc/state/last-tool-error.json` -> 작업 도구가 남긴 에러 로그가 testcase 디렉터리에 커밋됨. 내용에 내부 host IP(`192.168.6.16`)와 개인 scratch 경로가 들어 있고, 공개 저장소 develop 에 그대로 머지된다.

### Non-blocking (should consider)

2. `src/parser/parse_tree_cl.c:19441` -> `pt_keeps_distinct_values()` 는 표에 없는 형 변환을 모두 `from_type == to_type` 으로 막는다. 그래서 값이 그대로 보존되는 DATE -> DATETIME(자동 `cast(u.dte as datetime)`), FLOAT -> DOUBLE 비교도 조인을 유지한다. develop 은 두 경우 모두 조인을 제거하고 정답(2행)을 냈다. PR 본문 "정답이 맞으면서 새로 막히는 경우는 `u.d || ''` 하나" 와 다르므로, 두 변환을 허용 목록에 넣거나 본문을 고치면 된다.
   ```
   head : 'P2 date = datetime'  plan= Nested-loop join([dba.o].kdt= cast([dba.u].dte as datetime)): left outer
   base : 'P2 date = datetime'  plan= Sequential scan(dba.o dba.o)
   ```
3. `src/optimizer/rewriter/query_rewrite_select.c:34-36` -> 새 static 프로토타입 3개(`qo_check_keeps_distinct`, `qo_get_host_var_bound_type`, `qo_eq_keeps_distinct`)가 `qo_collect_name_with_eq_const` 프로토타입 뒤에 있지만, 정의는 그 함수 앞(1979, 1998, 2030 행)에 있다. 프로토타입 블록은 정의 순서를 따르는 것이 이 파일의 관례다.

## JIRA -> Engine PR

JIRA 에 `design.md` / `test.md` / `test_result.md` 첨부가 없다. Expected Result 와 Root cause 기준으로 판정한다.

| 항목 | PR 상태 | 판정 |
|--|--|--|
| 질의 1 (`u.code + 0 = o.k`) COUNT 3 | PR 표 3, TC Case 1, CI sql `cbrd_27794` ok | 충족 |
| 질의 2 (`u.code = o.k`, 암시적 CAST) COUNT 3 | PR 표 3, TC Case 2 | 충족 |
| 질의 3, 4 (조인 제거 없는 비교 질의) COUNT 3 | 조인 제거 대상 아님, 변화 없음 | 충족 |
| 질의 5 (CBRD-26415 `MOD`) COUNT 8 | TC Case 14, 8 | 충족 |
| Root cause: 유지 연산(PLUS/MINUS/CONCAT/CAST)의 형 미확인 | `pt_expr_keeps_distinct_values()` 로 식마다 결과 형 검사 | 충족 |
| Root cause: `=` 자체의 비교 형 미확인 | `qo_eq_keeps_distinct()` 로 양쪽 형 검사, 호스트 변수는 바인드 형(CBRD-27583 형별 플랜) | 충족 |

연관 이슈: CBRD-26415 는 같은 결함의 함수 식 부분이고 develop 에 이미 반영되어 있다. CBRD-24182 는 조인 제거 도입 이슈다. 11.4 백포트는 PR 본문이 별도 판단으로 남겼다.

판정: 충족.

## TC PRs

| 시나리오 | 근거 | 판정 |
|--|--|--|
| VARCHAR 유니크 `+ 0` / 암시적 CAST / 상수 비교 | #3930 Case 1~3 | 통과 |
| BIGINT = DOUBLE, DOUBLE `+ 1` | #3930 Case 4, 5 | 통과 |
| 콜레이션 불일치(utf8_bin, 기본 = utf8_en_ci, `||` 포함) | #3930 Case 6~8 | 통과 |
| 제거 허용 경우(INT `+ 1`, VARCHAR `||`, NUMERIC `+ 0`, INT = VARCHAR, BIGINT = BIGINT) | #3930 Case 9~13 (COUNT 비교만, 플랜 미출력) | 통과 |
| CBRD-26415 `MOD` | #3930 Case 14 | 통과 |
| `NUMERIC(38,38)` + 38자리 상수 반올림 | #3930 Case 15 | 통과 |
| 기존 `cbrd_26415` Case 19, 20, 26 재기준 | #3930 answer 변경, CI ok | 통과 |
| 호스트 변수 바인드 형별(JDBC `setDouble`/`setString`/`setLong`) | PR 본문 JDBC 실측만, TC 없음 | 미포함 |

TC 파일: 새 case 와 answer 가 짝을 이루고, 헤더 주석에 `;` 가 없다. 본문의 "develop 빌드에서 Case 1~8 NOK" 는 잘못 커밋된 json 파일 안의 diff(8곳 `2` vs `3/4`)와도 맞는다. 잘못 커밋된 파일이 Finding 1 이다. private-ex #4621 은 변경이 없는 빈 draft 라 리뷰 대상이 아니다(TC Merge Gate 안내대로 닫으면 된다).

판정: 승인. Finding 1 은 `a5fc0dd91` 에서 해소(json 삭제, `cbrd_27794.queryPlan` 으로 플랜 출력 추가 -> Case 9~13 조인 제거도 answer 로 고정).

## Runtime Verification

- CI 재사용: gha-ci run 40841881357 (engine `c75b1c11a` debug, `tc/pr-8318` `0a598b27a`). sql 에서 `cbrd_27794`, `cbrd_26415` ok. sql NOK 12건 중 `cbrd_27379/02_hash_join_mode` 는 rerun 40862631761 에서 통과(PR 8198 run 40899260493 에서도 실패한 flake), 남은 `cbrd_27381` 11건은 다른 PR run(40974047234)에서도 같은 11건이 실패한다. medium, shell 통과.
- 직접 실행(SA `csql -S`, `tools/fast-gate/fast-sa.sh`, 새 DB): CI tarball optdebug head `c75b1c11a` (libcubrid sha256 `9b95d73a...`) 와 merge-base `d93145bdb` (`3f886294...`).
  - BIGINT 유니크 = NUMERIC(20,0) 에 2^53, 2^53+1: 두 빌드 모두 조인 제거, COUNT 2 (정답 2). 정확한 수 비교 분기가 맞다.
  - INT 유니크 = FLOAT 에 16777216, 16777217: develop 1 (틀림), head 2 (정답 2, 조인 유지). PR 표에 없는 경우도 고친다.
  - DATE = DATETIME, TIMESTAMP = DATETIME, FLOAT = DOUBLE: develop 은 제거, head 는 유지, 두 빌드 COUNT 같음(Finding 2).
  - INT = BIGINT, NUMERIC(10,2) = INT / NUMERIC(10,1), CHAR = VARCHAR, utf8_en_ci 유니크 = 리터럴, ENUM = 리터럴, CHAR = 리터럴, DATE = 리터럴: 두 빌드 모두 제거, COUNT 같음.
- `just ctp sql _36_guava/cbrd_27794` (PR=8318, tc `a5fc0dd91`, head optdebug `c75b1c11a` = `72ad4e886` 와 patch 동일): PASSED 1/1, result vs answer 차이 0줄, core 0.
- 호스트 변수 경로는 CS/JDBC 실행을 하지 않았다. PR 본문의 JDBC 실측과 develop 에 들어 있는 CBRD-27583(`52193efa9`, 바인드 형별 XASL)에 기댄다.

## Existing Comments

| 코멘트 | 상태 |
|--|--|
| greptile P1 (parse_tree_cl.c, NUMERIC 덧셈 반올림 시 조인 제거) | `ed25c892e` 에서 `pt_get_exact_number_digits()` 와 TC Case 15 로 반영됨, 답글 없음 |
