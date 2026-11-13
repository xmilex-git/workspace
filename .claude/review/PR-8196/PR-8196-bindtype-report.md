# PR #8196 코드 리뷰 보고서 (바인드 타입 활용 집중 리뷰)

**PR:** [CUBRID/cubrid#8196](https://github.com/CUBRID/cubrid/pull/8196)
**제목:** [CBRD-27361] Page batch execution: heap scans in chunks, vector filters, hash GROUP BY merge and hash join runtime filter
**작성자:** soheejung-cs
**HEAD SHA:** `ec25c8e80` (develop merge-base `0604b690b`, `52193efa9` 포함)
**범위:** `52193efa9` (CBRD-27583: `?` 까지 컴파일이 타입을 정하고 바인드 타입 서명마다 플랜 하나) 를 이 PR 이 쓰는지만 봄. JIRA·TC 판정은 10-21 리뷰(`PR-8196-report.md`) 그대로
**리뷰 일시:** 2026-10-29
**리뷰 결정:** 엔진 PR Comment (finding 1-4 인라인 + 질문 1) / TC PR 리뷰 없음 (범위 밖)

> **TL;DR** (Non-blocking): 필터·출력 프로그램을 클론당 한 번 컴파일하고 실행마다 하던 서명 재검사를 없앤 부분은 `52193efa9` 를 그대로 씁니다. 배치 층에는 그 전제를 쓰지 않은 곳이 남았습니다. 실행당 한 번 정해지는 값(`?`, `? + 1`)을 타입 없는 스칼라로 만들어 `SUM(?)` 가 `SUM(2)` 와 달리 배치 집계를 잃고, 컴파일이 이미 막은 "다른 타입의 값" 을 release fallback 7곳이 다시 검사합니다. 결과가 틀리는 경우는 찾지 못했습니다.

## Summary

- **변경 요약**: 힙 스캔을 페이지 청크 단위로 돌리는 배치 실행. #8213 위로 옮기면서 실행당 타입 확인을 뺐다고 PR 본문에 적음
- **제대로 쓴 곳**: 필터 컴파일 1회(`eval_data_filter_ensure_prog`), 해시 조인 build 해시 선계산의 `input->converters` 검사, GROUP BY 해시 병합의 `key_compares`, 집계의 `accumulator_domain`/`accumulator_takes`
- **주요 이슈**: Non-blocking 1 (실행당 상수의 타입을 버림), 2 (도달할 수 없는 타입 가드가 assert 가 아니라 fallback)
- **확인 필요 사항**: expr program 을 파서 쪽으로 옮길 계획 여부

---

## Findings

### Non-blocking (should consider)

1. **실행당 상수를 타입 없는 스칼라로 만들어 `SUM(?)`·`SUM(? + 1)` 이 배치 집계를 잃음** (`src/query/expr_batch.c:2434`, `:2456`, `:2470`, `:2986`, `:3030`)
   - `eb_program_cell_vec ()` 는 prologue 스텝이 내는 셀을 `eb_new_scalar_vec (b, EB_I64, DB_TYPE_UNKNOWN, ...)` 으로 만들고, 소비 커널이 `eb_bind_operand ()` 에서 타입을 붙입니다(주석: "a scalar whose type is only known at run time"). 집계 루트가 그런 셀이면 `"a program root without a type"`, 피연산자가 `TYPE_POS_VALUE` 그대로면 `"an operand the batch does not evaluate"` 로 소비 노드가 거절됩니다.
   - `52193efa9` 뒤로 타입은 빌드 때 이미 있습니다: `expr_prog_step_info ()` 가 hostvar 스텝에 `info.regu` (그 `domain` 이 서명 타입), 산술에 `info.type`, CAST 에 `info.domain` 을 줍니다. develop 의 `expr_k_hostvar ()` (expr_compile.c:1403-1408) 는 값 타입이 그 도메인과 같다고 assert 합니다.
   - 근거 (head optdebug, 20만 행, 직렬): `SUM(2)` / `SUM(2+1)` fetch 2840, `SUM(?)` / `SUM(?+1)` fetch 11316 (필터만 청크로 도는 모드). 리터럴과 `?` 만 다른 쌍입니다.
   - 고칠 방법: publisher 스텝의 위 필드로 스칼라 타입을 빌드 때 정하고, `TYPE_POS_VALUE` 피연산자는 `TYPE_DBVAL` 가지처럼 `operand->domain` 타입의 스칼라로 받습니다. `eb_bind_operand ()` 의 늦은 타입 붙이기는 같음 검사로 줄어듭니다.

2. **컴파일이 막은 "다른 타입 값" 을 release fallback 으로 다시 검사** (아래 7곳)
   - `expr_batch.c:3743` `"a scalar bound to another type"`, `:3816` 문자열 상수의 타입·codeset·collation, `:3852` `"a filter constant bound to another type"`, `:3891` (`expr_numeric_cmp_const_ok` 의 타입 부분), `:1605-1606` SUBSTRING 위치의 `DB_TYPE_INTEGER` 검사, `:4736` `eb_share_snapshot ()` 의 행마다 검사, `query_hash_join.c:4595` 런타임 필터 build 가 비교 못 하는 타입의 키를 건너뜀.
   - 서명이 타입·codeset·collation 을 다 담고(GLOSSARY "바인드 타입 서명"), develop 은 같은 불변식을 optdebug assert 로만 둡니다(`DOMAIN_COMPARE` 주석 "A release row ... does not check", `EXPR_ARITH_REQUIRE_TYPE`, `query_executor.c:4270`).
   - optdebug 에서 계약이 깨지면 이 가드가 행 경로로 조용히 돌리므로 CTP 가 잡지 못합니다. release 에서는 돌지 않는 코드입니다. `query_hash_join.c:4595` 는 닿으면 build 키가 빠져 probe 행이 잘못 떨어지는 방향입니다.
   - 고칠 방법: 타입 비교는 `assert (DB_IS_NULL (v) || DB_VALUE_DOMAIN_TYPE (v) == type)` 로 바꾸고 fallback 을 지웁니다. 값의 범위 검사(NUMERIC 워드 범위, BIGINT 10^15 창, SUBSTRING 1 이상)는 남깁니다.

3. **문자열·NUMERIC 리프가 바인드 값이 NULL 이면 필터 전체가 배치에서 빠짐** (`src/query/expr_compile.c:3765`, `:3948`)
   - `expr_pred_term_numeric_info ()`·`expr_pred_term_string_info ()` 는 바인드 값을 보고 `DB_IS_NULL (kv)` 이면 리프가 아니라고 답합니다. 정수 리프(`expr_pred_term_raw_info ()`)는 NULL 을 받아 `k_null` 로 처리합니다(expr_batch.c:3838-3843).
   - 근거: `a > ?` NULL 은 batch pages 710, `c = ?` NULL 과 `n < ?` NULL 은 `batch: no (the data filter is interpreted)`. 그 실행만 행 경로로 가고 답(0행)은 같습니다.
   - 서명상 비교 피연산자의 NULL 은 그 자리의 어느 플랜이든 씁니다. 리프 자격은 컬럼·`k->domain` 으로 정하고 NULL 은 로드 때 `k_null` 로 두면 됩니다.

4. **배치 집계의 "있을 수 없는" 경계가 `ER_QPROC_INVALID_XASLNODE` 를 씀** (`src/query/query_aggregate.cpp:1163`, `:1207`, `:1235`)
   - `:1207` 은 누산기가 벡터 타입으로 열리지 않은 경우(타입 불변식)입니다. 이 에러를 받은 클라이언트는 xasl_id 를 버리고 다시 컴파일해 재실행합니다(`db_vdb.c:3435`, `cas_execute.c:2434`). release 에서 불변식이 깨지면 오류 대신 조용한 재컴파일이 됩니다. 다른 에러 코드가 맞습니다.

### Questions for the author

- `expr_compile` 의 프로그램(`EXPR_PROG`)은 서버가 클론의 첫 평가에서 regu 트리를 낮춰 만든다. 이 낮추기를 파서(XASL 생성) 쪽으로 옮길 계획이 있는지.

## Out of scope (develop 동작, PR 밖)

- `SUM(b * ?)` (b BIGINT, ? INTEGER) 의 연산자 프로그램이 head 와 develop `0604b690b` 모두 `generic ... op=T_MUL dom=bigint` 행당 범용 스텝입니다. 리터럴 `SUM(b * 2)` 는 타입 검사가 `cast(2 as bigint)` 를 넣어 `mul_bigint` 가 됩니다. `?` 쪽 변환(서명 INTEGER -> 소비자 BIGINT)도 컴파일이 아는 결정이라 exec-prologue 에서 한 번 바꾸면 타입 커널을 쓸 수 있습니다. head 에서는 이 때문에 배치 집계도 거절됩니다(fetch 11316).

## Runtime Verification

| 실행 | 빌드 | 결과 |
|---|---|---|
| CS 서버, `parallelism=1`·`max_parallel_workers=1`, `;plan detail` trace | CI debug(optdebug) `ec25c8e80`, libcubrid sha256 `ef758f29` | 위 1·3 의 fetch·batch 줄. 서명이 다른 값(3000000000, 12.5)까지 배치된 스캔은 모두 `row path: 0`, 2번의 가드 사유는 한 번도 찍히지 않음 |
| 같은 질의 | CI debug `0604b690b`, sha256 `04a9ff2a` | `SUM(b * ?)` 가 develop 에서도 `generic` |
| NUMERIC 바인드 17개 결과(SA, `n < ?` 12.344/12.345/3000000000 등) | 위 두 빌드 | head 와 develop 차이 0줄 |

서버 로그에 assert·코어 없음. 증거는 `.git_ignored_dir/scratch/pr8196-types/runtime/` (`probe3cs.out`, `probe4cs.out`, `probe5b.out`, `probe6cs.out`, `parity.*`). CTP 는 돌리지 않았습니다(2번의 "도달하지 않음" 은 계약과 develop assert, 위 smoke 에 근거).
