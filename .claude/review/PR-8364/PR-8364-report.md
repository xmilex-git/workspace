# PR #8364 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8364](https://github.com/CUBRID/cubrid/pull/8364)
**제목:** [CBRD-27870] A BUILDVALUE whose output reads a column of its scan keeps its rows on the serial row loop
**작성자:** soheejung-cs
**HEAD SHA:** `7d09a54cb` (develop merge-base `bbc332864`)
**JIRA:** CBRD-27870 (Correct Error, Open) / 연관: CBRD-27361 (Regress)
**TC PR:** CUBRID/cubrid-testcases#3985 (`tc/pr-8364` `694a0e04d`) / CUBRID/cubrid-testcases-private-ex#4695 (`c7ac1b4cf`)
**리뷰 일시:** 2026-11-04
**리뷰 결정:** 엔진 PR Request changes (inline 2) / TC #3985 리뷰 없음(엔진 수정 뒤 Case 8 재확인) / TC #4695 Approve

> **TL;DR** (Blocking): 집계 빠른 길을 끄는 `bfc323a9a` 가 서버 실행 중에 `agg_optimized` 를 지워서, 클라이언트가 그 집계를 빼고 쓴 operand 프로그램 이미지와 서버가 다시 컴파일한 프로그램이 달라집니다. debug 빌드에서 이 PR 의 TC Case 8(WHERE 없는 MAX 의 ODKU 소스, WHERE 없는 MIN)이 `expr_agg_prog_settle` assert 로 서버를 죽이고, gha-ci 두 번(052b84a2e, 7d09a54cb) 모두 같은 core 입니다.

## Summary

- **변경 요약**: GROUP BY 없는 집계 블록의 출력이 스캔 컬럼을 읽으면(`XASL_OUTPUT_READS_SCAN`) 페이지 배치·병렬 스캔·집계 빠른 길을 끄고, 행마다 마지막 행을 복제해 출력 직전에 돌려놓는다.
- **주요 이슈**: debug 빌드 assert (Case 8 의 3문장 중 2문장). release 빌드는 맞는 값 `'h3'`.
- **확인 필요 사항**: #8056 과 같은 XASL 플래그 비트(`0x1 << 29`)를 쓴다.

---

## Findings

### Blocking (must fix)

- `src/query/query_executor.c:14263-14275` — `XASL_OUTPUT_READS_SCAN` 블록에서 서버가 `agg_ptr->flag.agg_optimized = false` 로 바꾸고 행 루프를 돈다. 그런데 클라이언트는 직렬화 때(`xts_save_agg_prog_image ()`, `xasl_to_stream.c:3764`) `agg_optimized` 인 집계를 빼고 operand 이미지를 쓴다(`expr_compile.c:7065` `participates = !agg_p->flag.agg_optimized && ...`). 그 결과 행 루프의 첫 집계에서 debug 빌드는 `expr_agg_prog_settle ()` 의 `assert (expr_image_same_prog (prog, here))`(`expr_compile.c:9214`)로 abort 한다.
  - 재현(CI debug tarball, SA): `create index ... on t_po8 (g)` + `update statistics` 뒤 `insert into t_po9 (id) select max(s.g) + 1 from t_po8 s on duplicate key update c = s.c;` 와 `select min(s.g), (select max(s.c)) from t_po8 s;` 가 `Assertion 'expr_image_same_prog (prog, here)' failed`. 키 범위가 있는 `count(*)` 문장은 통과(COUNT(*) 는 operand 가 없어 이미지 대상이 아님).
  - develop `bbc332864` debug: 같은 세 문장이 assert 없이 끝나고 숨은 컬럼은 NULL. CONNECT BY 가 같은 런타임 분기를 써도 안전한 이유는 클라이언트가 CONNECT BY 에서 `flag_agg_optimize` 를 아예 켜지 않기 때문(`pt_to_aggregate ()` 의 `connect_by == NULL` 조건, `xasl_generation.c:4914`).
  - 고칠 곳: `pt_to_buildvalue_proc ()` 가 `XASL_OUTPUT_READS_SCAN` 을 세우는 자리(`xasl_generation.c:20847`)에서 `agg_list` 의 `agg_optimized` 를 함께 내리면 이미지와 서버가 같은 집계를 컴파일하고, 서버 쪽 분기는 필요 없어진다.

### Questions for the author

- `src/query/xasl.h:596` — `XASL_OUTPUT_READS_SCAN (0x1 << 29)` 은 열려 있는 #8056 의 `XASL_PASS_THROUGH_WRAPPER (0x1 << 29)` 와 같은 비트다. 뒤에 머지되는 쪽이 `0x1 << 30` 으로 옮겨야 하고, 그 뒤 `flag`(int)에 남는 비트는 없다.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 재현 두 개가 'g2', (1, 'g2') | PR 본문 release 확인, CI debug Case 5/7 OK | 충족 |
| 표의 형태가 #8196 이전 직렬 값과 같음 | Case 5~7 OK, Case 8(빠른 길) debug assert | 부분 (Blocking 1) |
| 병렬 대상 소스에서도 마지막 행 값 | Case 6 trace 에 parallel workers 없음, OK | 충족 |
| GROUP BY 소스는 그룹 첫 행 | Case 5 마지막 문장 OK | 충족 |
| debug 에서 `function_based_index_select_basic_subquery_001` 통과 | run 41770625665 failed.list 에 없음 | 충족 |
| CTP sql·medium·shell 통과 | sql 5 NOK(Case 8 core 1건 + 같은 shard 뒤 4건 -581), shell 1 NOK(flake) | 미충족 (Blocking 1) |
| 설계: 빠른 길을 끄는 방식 | 서버 런타임에서 끔 -> 클라이언트 이미지와 어긋남 | 부분 (Blocking 1) |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| ODKU 숨은 컬럼(필터 있음·없음, 집계 컬럼, 인덱스·힙, 조인, GROUP BY) | #3985 Case 5 | 통과 |
| 병렬 대상 소스(trace) | #3985 Case 6 | 통과 |
| SELECT 목록 상관 서브쿼리 | #3985 Case 7 | 통과 |
| 집계 빠른 길(WHERE 없는 MAX·MIN, 키 범위 COUNT(*)) | #3985 Case 8 | 실패 (debug core) |
| #8211 shell 칸 13 원래 형태 | #4695, run 41770625665 shell 에서 `cbrd_27336_forms` OK | 통과 |

- #3985 본문의 "debug 빌드에서도 같은 출력으로 통과" 는 CI debug 결과와 다르다. 머리 주석 Case 6 줄에 `;` 가 있다(`...parallel scan; the trace shows...`). 이번 답안은 영향 없음.
- #4695 는 STDDEV 우회만 되돌린 3줄 변경이고 답과 맞는다.

## Runtime Verification

- CI gha-ci run 41770625665 (head `7d09a54cb`, debug, `tc/pr-8364` `694a0e04d` / private-ex `c7ac1b4cf`): sql NOK 5 — `cbrd_27361_page_order` core `expr_agg_prog_settle`, 같은 shard 03 에서 뒤에 돈 `cbrd_27361_string_leaves`, `cbrd_27374_count`, `cbrd_27374_state`, `cbrd_27442` 는 `-581 updates are disabled`. medium OK. shell NOK 1 `cbrd_25977` 14번(병렬 워커 수 검사, 직전 run 통과) -> flake.
- CI run 41623402810 (head `052b84a2e`, debug, `tc/pr-8364` `a4ad38e17`): 같은 core. 2/2.
- 로컬 SA (CI tarball): head debug `7d09a54cb` (libcubrid sha256 `fe4a4f55…`) Case 8 의 ODKU·MIN 문장 abort, COUNT(*) 문장 `3, 'h3'`. head release: 세 문장 `'h3'`. develop debug `bbc332864` (`5a5ddd42…`): 세 문장 NULL, abort 없음.

## Existing Comments

| 코멘트 | 상태 |
|---|---|
| greptile 2건(복사 시점, `pr_clone_value` 실패) | 작성자 `756c19e28` 로 해결, greptile 확인 |
| codex 1건(빠른 길이 행 루프를 건너뜀) | 작성자 `bfc323a9a` 로 대응. 이 대응이 Blocking 1 을 만든다 |
