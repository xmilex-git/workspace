# PR #7658 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#7658](https://github.com/CUBRID/cubrid/pull/7658)
**제목:** [CBRD-27215] Compile expression evaluation into step programs for aggregates and projections
**작성자:** soheejung-cs
**HEAD SHA:** `c0a9d2ff3` (develop merge-base `5b1867174`, 2026-10-15 develop head)
**JIRA:** CBRD-27215 (Improve Function/Performance, Develop) / 연관: CBRD-27408 (Relates, 이 PR에 포트됨)
**TC PR:** CUBRID/cubrid-testcases#3239 (`tc/pr-7658` `59c86e3ad`, develop 대비 파일 변경 없음) / cubrid-testcases-private-ex#3869 (`tc/pr-7658` `f28b95387`, shell `cbrd_27215_expr_program` 추가 + `_01_show_table.answer` 수정)
**리뷰 일시:** 2026-10-15
**리뷰 결정:** 엔진 PR REQUEST_CHANGES / private-ex #3869 COMMENT / cubrid-testcases #3239 리뷰 없음 (2026-10-15 grill)

> **TL;DR** (Blocking): 실행당 1회 계산하는 상수 값을 셀 포인터로 넘기는 경로가 두 곳에서 틀린 값을 냅니다. (1) 호스트 변수 준비문을 다시 실행하면 exec-prologue 스텝이 이전 실행의 해제된 값 배열을 읽어 CS에서 NULL이나 이전 실행 값이 나옵니다(`(? + 1) * n`). (2) 필터 값 공유가 리터럴 CAST 상수의 빈 슬롯을 넘겨 투영과 SUM이 NULL이 됩니다. 공유 동일성 판정이 ENUM, charset, collation을 보지 않아 오답과 optdebug 서버 abort도 납니다.

## Summary

- **변경 요약**: 투영, SUM/AVG 피연산자, 스캔 데이터 필터의 식을 실행당 1회 스텝 프로그램으로 컴파일하고, 10-13부터는 모든 연산자를 generic step으로 프로그램에 넣음
- **주요 이슈**: 준비문 재실행 오답(Blocking 1), 필터 값 공유 오답 2종(Blocking 2, 3)
- **확인 필요 사항**: CBRD-27408 포트 후 병렬 NUMERIC SUM이 직렬과 다른 값, 튜플 재생성(RETRY) 경로의 1회 평가가 의도인지

---

## Findings

### Blocking (must fix)

1. `src/query/expr_compile.c:1497` (`expr_k_resolved_value`) - 게이트 값이 있으면 노드의 셀을 그 실행의 값 배열(`ctx->vd->dbval_ptr + ref`)로 돌려 둠 -> `expr_prog_enter_execution`(5700)은 다음 실행에서 셀을 슬롯으로 되돌리지 않음 -> exec-prologue(실행당 1회 스텝)로 올라간 소비자(`? + 1`의 NUMERIC coerce)가 행 루프의 체크보다 먼저 돌며 이전 실행의 해제된 배열을 읽음(Blocking 2와 같은 10-13 `69de4b886`의 resolved_value 스텝). `prepare st from 'select id, (? + 1) * n from t0'`를 1, 10, 100, 1000으로 실행하면 2번째부터 직전 실행의 값(3.00, 4.50 / 16.50, 24.75 / 151.50, 227.25), 사이에 다른 문장을 끼우면 NULL. `sum((? + 1) * n)`, `(? + 1) + n`, `? * 2 * n`도 같음. csql -C와 CTP shell(csql)에서 매번 재현, csql -S와 CTP sql(브로커 경유)에서는 맞게 나옴(해제된 배열 자리를 다시 받으면 우연히 맞음). 준비문 재사용 형태.
2. `src/query/expr_compile.c:3188` (`expr_scan_pred_share_build`) - 게이트(`resolve_domains`: 실행 전에 상수식을 1회 계산하는 단계)가 계산한 상수 노드의 슬롯을 공유 목록에 올림 -> 필터 프로그램은 `expr_k_resolved_value`(4355-4378, 10-13 `69de4b886`)가 그 노드의 cast 스텝을 건너뛰어 슬롯이 비어 있음 -> 그 슬롯을 받은 투영/집계가 NULL을 읽음. `select id, i - cast(1 as int) from t where i > cast(1 as int)`이 develop은 1, 4 / PR은 NULL, NULL. NVL 첫 인자가 이런 상수면 두 번째 인자를 고름(`sum(nvl(cast(1 as int), i))` develop 5 / PR 4). 실사용 형태 `select id, p - cast(10 as numeric(10,2)) from t where p > cast(10 as numeric(10,2))`도 develop 90.00, 40.50 / PR NULL, NULL, 같은 식의 SUM은 130.50 / NULL. `to_date('...')`, 날짜 리터럴, `sysdate`, 호스트 변수 형태는 차이 없음. trace: 필터 `[0] resolved_value ... else -> [2]`, `[1] cast`, 출력 리스트 `shared from data filter: 1`.
3. `src/query/expr_compile.c:1722-1726` (`expr_share_same`) - 동일성 판정이 도메인의 타입, 정밀도, 스케일만 비교하고 연산자의 상태를 보지 않음 -> 결과가 다른 식을 같은 값으로 공유. 실행으로 확인한 네 가지:
   - ENUM 원소 순서만 다른 CAST: `cast(s as enum('b','a'))+0 ... where cast(s as enum('a','b'))+0 > 0` develop 2, 1 / PR 1, 2
   - charset만 다른 CAST: `hex(cast(s as varchar(20) charset iso88591)) ... where cast(s as varchar(20) charset euckr) = e` develop `'3F3F'` / PR `'B0A1B3AA'`
   - collation만 다른 CAST: `strcmp(cast(s as varchar(20) collate utf8_bin), 'ABC') ... where cast(s as varchar(20) collate utf8_en_ci) = c` -> PR optdebug에서 `db_string_compare` assert(`string_opfunc.c:530`, collation 불일치)로 서버 abort
   - 시드 RAND: `select id, rand(1) - 1 from t where rand(1) - 1 > a` -> RAND 노드마다 따로 진행하는 시드 수열 대신 필터의 값이 출력됨

### Non-blocking (should consider)

4. `src/query/query_aggregate.cpp:1263` (`qdata_evaluate_aggregate_list`) - 컴파일된 집계 피연산자를 행마다 집계 루프보다 먼저 한꺼번에 평가 -> 프로그램에 들어가지 않는 집계(GROUP_CONCAT, STDDEV 등)와 부수효과 순서가 develop(집계 리스트 = SELECT 목록 역순)과 다름. 시리얼 `max(s.next_value * 1), group_concat(s.next_value)` develop 6, '1,3,5' / PR 5, '2,4,6'. `SELECT MAX(@a := @a * 2), GROUP_CONCAT(@a := @a + 1)`이 develop은 14, @a=14 / PR은 6, @a=7. 투영 리스트에는 bug_bts_9234 때 부수효과 규칙(`expr_arith_side_effect`)이 들어갔지만 집계 리스트는 루트만 봄. SELECT 목록 평가 순서는 SQL 미정의라 Non-blocking(grill), 규칙 적용 또는 JIRA spec 명시를 제안.
5. `src/query/expr_compile.c:4160-4172` (`'^'` 규칙) - WIDTH_BUCKET의 bucket 수(third)를 경계보다 먼저 계산 -> develop(왼쪽, 경계, bucket 수 순서)과 오류 우선순위와 시리얼 소비 순서가 다름. `width_bucket(a, lo / z, 100, cast(n as int))`이 develop -539 / PR -181, `width_bucket(60, s.next_value, s.next_value + 100, mod(s.next_value, 7) + 1)`이 develop 3 / PR 2. 투영과 필터 모두 해당.
6. `src/query/query_aggregate.cpp:1126-1143` - SUM/AVG에서 develop의 fused 경로로 남기는 피연산자가 NUMERIC 트리와 CAST_WRAP뿐 -> develop이 `REGU_VARIABLE_AGG_OPERAND`로 표시한 DOUBLE 나눗셈이 generic step(`qdata_is_divided_zero`, `|x| <= DBL_EPSILON`이면 0)으로 감. `sum(d / x)`(x = 1e-20)가 develop -9.97e+19 / PR "Attempt to divide by zero"(직렬, GROUP BY, parallel(4) 모두).

### Questions for the author

7. `src/query/numeric_opfunc.c:4372` (`numeric_sum_acc_add_core`, CBRD-27408 포트) - 41자리에 이른 합을 `+`와 같이 행마다 반올림하므로 결과가 더하는 순서에 따라 달라짐 -> 병렬 스캔은 워커별 부분합을 `numeric_sum_acc_merge`로 합치므로 직렬과 다른 값. NUMERIC(38,30) +/-99999999.999...9 각 6만 행의 SUM이 PR 직렬 1.00E-28 / PR parallel(2,4,8) 0E-27 / develop 모두 0E-30. 직렬의 잔차(1e-30, NUMERIC(38,2) 0.00 -> 0.01)는 CBRD-27408(Resolved, PR #7915 닫힘)의 의도로 보이지만, 병렬에서 "40자리 초과 SUM = + 체인"이 성립하지 않는 점과 병렬 여부로 스케일까지 바뀌는 점은 확인 필요.
8. `src/query/query_opfunc.c:440` (`eval_prog_row_ready`) - 튜플 재생성(RETRY: SET 컬럼, 페이지 초과 행) 때 develop은 리스트를 두 번 평가해 시리얼을 두 번 뽑고(2,4,6) PL 함수의 DML도 두 번 실행하는데, PR은 한 번(1,2,3)입니다. develop 쪽이 결함에 가까우나 결과가 달라지므로 의도라면 본문 명시가 필요.

## JIRA -> Engine PR

JIRA에는 design.md / test.md 첨부가 없고, 기준은 본문의 "기존 해석 경로와 동일한 시맨틱 유지"와 결과 byte 동일입니다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 결과/에러가 develop과 동일 (본문 "22종 결과 byte 동일", "같은 결과/에러 위치") | 준비문 재실행, 필터 값 공유, 집계 순서, WIDTH_BUCKET, DOUBLE 나눗셈에서 차이 | 미충족 (Blocking 1-3, Non-blocking 4-6) |
| 스텝 프로그램 컴파일러, CSE, 커널, 점프 스텝, 호이스팅 | 구현, 무작위 식 약 1.3만 문장 차등 실행에서 차이 없음 | 충족 |
| 필터 -> 출력/집계 공유 | 구현, 오답 2종 | 부분 (Blocking 2, 3) |
| 호스트 변수 식 실행당 1회 계산 | 구현, 재실행 시 이전 실행 값 | 미충족 (Blocking 1) |
| 재귀 깊이 한계 적용 | 본문대로 해석기 거절의 하한(함수 리프, CSE에서 1단계 늦음은 이 범위) | 충족 |
| CBRD-27408 포트 (40자리 초과 SUM = + 체인) | 직렬은 구현, 병렬은 직렬과 다른 값 | 확인 필요 (Question 7) |
| 남은 일: q7 1.10 회귀 원인 조사 | PR 본문에 "조사 중" | 미해결 (본문 명시) |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 깊은 식의 재귀 한계 (투영, 필터, 집계, CASE) | private-ex #3869 `depth_guard.sql` | 통과 (CI) |
| 상관 서브쿼리 되감기 | #3869 `corr_subq.sql` | 통과 (CI) |
| trace 게이트 (`;plan detail`에서만 EXPR_COMPILE) | #3869 `trace_gate.sql` | 통과 (CI) |
| 회귀 문장 모음 (hoist, hostvar, share 등 29절) | #3869 `expr_compile.sql` + `coverage.answer` | 통과 (CI) |
| 플랜 캐시 on/off/clone off | #3869 shell 본문 | 통과 (CI) |

- TC 파일: #3239는 develop 대비 바뀐 파일이 없어 검토할 내용이 없습니다. #3869의 `_01_show_table.answer`는 현재 head의 `;plan detail` 출력(10-13 이후 generic step `op=T_COALESCE`, `op=T_ADD dom=set` 줄)과 맞지 않아 gha-ci shell에서 NOK입니다(run 38680302759 shard 38).
- 위 Blocking/Non-blocking/Question 7 형태는 어느 TC에도 없습니다. 리뷰용 TC를 sql 6개, shell 1개 만들어 두었습니다(아래 Runtime Verification, 코멘트에는 SQL만 넣고 tc/pr-7658 반영은 제안만).
- 판정: TC 보완 필요 (`_01_show_table.answer` 재생성, 위 형태의 케이스 추가).

## Runtime Verification

- 빌드: gha-ci optdebug tarball 두 개. develop `5b1867174` (libcubrid.so sha256 `eb676664...`), PR `c0a9d2ff3` (`bbf1d9e4...`). 같은 빌드 종류로 A/B.
- 차등 실행 (csql -S와 csql -C, 같은 SQL을 두 빌드에 돌려 문장 단위 byte 비교):
  - 무작위 타입 식 트리 1,750개를 투영, 필터, 필터+투영, CASE 분기, SUM/AVG, GROUP BY, 다중 루트, 준비문(바인드 타입 회전) 문맥에 배치 (모드별 약 12,500 문장 출력): PR 고유 차이 2건(Blocking 2와 같은 형태)
  - 수작업 위험 형태 (비결정 함수, 시리얼, 세션 변수, CONNECT BY, LOB, 상관 서브쿼리, DML, 넓은 튜플, 세션 파라미터, generic step 지연 피연산자, 병렬 30만 행): 차이 없음, 병렬 결과도 develop과 같음
  - 코드 리딩으로 뽑은 후보 SQL 약 1,300 문장: 위 Findings 1-8 확인
  - csql -C 병렬 프로브(12만 행 NUMERIC): Question 7의 직렬/병렬 차이, trace에서 `parallel workers: 4, gather: buildvalue` 확인
- CTP shell (`just ctp shell`, private-ex develop 트리 + `_06_issues/_26_2h/cbrd_27215_hostvar_reexecute`): develop 2회 OK 5/5, PR 2회 NOK(검사 2-4, CTP 재실행 포함 4번 모두 같은 값). 같은 형태의 sql 케이스는 CTP sql에서 PR도 OK라 제외.
- CTP (`just ctp sql`, 컨테이너 1 shard, `--testcases-as-is`, 답안은 develop 결과): `sql/_36_guava/cbrd_27215/` 7개 케이스 `filter_share_const`, `filter_share_identity`, `width_bucket_order`, `depth_limit`, `agg_side_effect`, `agg_double_divide`, `numeric_sum_parallel` (`depth_limit`은 grill 후 리뷰에서 제외). develop 3회 모두 7/7 OK(결과 byte 동일). PR 7/7 NOK, core 1개(`filter_share_identity` Case 4, `string_opfunc.c:530` collation assert; 스택 `fetch_op_strcmp` <- `expr_k_generic` <- `qdata_valptr_prog_ensure`). `width_bucket_order`는 core 없는 단독 실행에서도 NOK. 근거: scratch `ctp`, `ctp2`, `ctp3`, `ctp4`, `ctp6`.
- 코멘트의 SQL은 그대로 csql -S와 csql -C에서 다시 돌려 develop / PR 값을 확인(run11, collation abort는 별도 파일).
- CI 재사용: gha-ci run 38680302759 (head `c0a9d2ff3`, debug, tc/pr-7658) sql NOK 2건 `cbrd_27596`, `cbrd_27624`는 develop #8145의 답안 차이(이 PR 무관), shell NOK `_01_show_table`는 위 TC PR 항목, medium 통과.
- 덧붙임 (이 PR 무관, develop에서도 재현): `conv('', 16, 10)`의 `intl_prev_char` assert -> workspace #439, `adddate(date, -2147483648)`의 SIGSEGV(`abs (INT_MIN)`) -> workspace #440.
- 게시: 엔진 PR review 5529764805 (CHANGES_REQUESTED, 인라인 8), private-ex #3869 review 5529766405 (COMMENTED), 2026-10-15.
