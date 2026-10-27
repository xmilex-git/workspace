# PR #3861 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3861](https://github.com/CUBRID/cubrid-testcases/pull/3861)
**제목:** [CBRD-27510] Revise testcase for modify cci answers and add cci answers for domain collation pin change
**작성자:** kiho-um
**HEAD SHA:** `ccfd034c4` (develop merge-base `6a52e963e`)
**JIRA:** CBRD-27510 (엔진 PR CUBRID/cubrid#8022, TC PR #3588 모두 develop 머지) / 연관: 없음
**TC PR:** 이 PR 자체가 TC 전용 후속 PR이다. 엔진 PR과 `tc/pr-<N>` 짝은 없다.
**리뷰 일시:** 2026-10-26
**리뷰 결정:** Comment (review 5647943072, 2026-10-26), 스레드 답글 6건

> **TL;DR** (작성자 확인 필요): 바뀐 CCI 답지 28개는 값이 모두 맞다. 바뀐 줄은 표시만 바뀌었거나 JDBC 답지와 같은 값이다. 그런데 PR 본문의 "배경"이 바뀐 규칙을 틀리게 적었고, 이 본문은 머지 커밋 메시지가 된다.

## Summary

- **변경 요약**: PR #8022 머지 뒤 `sql_by_cci`에서 NOK가 나던 12개 `.answer_cci`를 고치고, `cbrd_27510`의 16개 케이스에 `.answer_cci`를 새로 만든다.
- **주요 이슈**: 본문이 "일부는 축약형에서 전체 자릿수로 바뀌었다"고 쓰지만, 그런 줄은 없다. AVG 값 변경도 표시 변경으로 묶여 있다.
- **확인 필요 사항**: kwonhoil의 질문 6건은 개발 쪽 답이 필요하다(아래 Existing Comments).

---

## Findings

### Questions for the author

1. **PR 본문 "배경"** — "일부는 반대로 축약형에서 전체 자릿수 표기로 바뀌었습니다"에 해당하는 줄이 diff에 없다. 기존 답지에서 바뀐 273줄은 모두 긴 표기에서 짧은 표기로 갔다. 짧은 표기에서 긴 표기로 간 줄은 0이다. 새 `cbrd_27510` 답지의 긴 표기는 무엇이 바뀐 것이 아니다. CCI 답지가 처음 생기면서 JDBC 답지와의 표시 차이가 드러난 것이다.
2. **PR 본문 "배경"** — 표시가 갈리는 규칙이 빠져 있다. CTP의 CCI 드라이버(`CTP/sql_by_cci/execute.c`)는 prepare가 알려 준 열 타입으로 값을 찍는다.
   ```
   열 타입 DOUBLE   : sprintf("%.9f") 후 trimdouble   -> 123.0, 19자를 넘으면 "%le" -> 1.797693e+308
   그 밖의 타입     : cci_get_data(CCI_A_TYPE_STR)    -> CCI ut_double_to_str "%.16f" -> 123.0000000000000000
   ```
   PR #8022 이전에는 문자열 인자 MEDIAN/PERCENTILE의 타입을 실행 중 첫 값으로 정했다. 그래서 prepare는 DOUBLE을 알려 주지 못했고, 드라이버는 그 값을 문자열로 받아 긴 표기로 찍었다. CBRD-27510 스펙 1번("인자가 문자열 컬럼이나 문자열 식이면 결과 타입은 DOUBLE")부터는 prepare가 DOUBLE을 알려 주므로 짧은 표기로 찍는다. 값은 같다. 바뀐 273줄 모두 옛 값에 위 DOUBLE 규칙을 적용하면 새 값이 나온다.
3. **PR 본문 "배경"** — `_14_avg` 3개 파일의 54줄은 표시가 아니라 값이 바뀌었다. 예를 들어 `111.209500504`가 `111.209500122`로 바뀌었다. 이는 PR #8022의 스펙 2b다. develop은 분석 AVG의 FLOAT 인자에서 첫 덧셈 한 번을 float로 반올림했는데, 이제 첫 값부터 DOUBLE로 더한다. 54줄 모두 #3588이 갱신한 JDBC 답지 값(`111.20950012207031`)에 `%.9f`를 적용한 것과 같다.

## JIRA -> Engine PR

엔진 PR #8022는 이미 머지됐고 이 PR의 범위가 아니라 생략한다. 다만 스펙 2b(분석 AVG의 FLOAT 합산)는 CBRD-27510 본문의 스펙 변경 목록에 없다. 이 내용은 저장소의 `docs/research/domain-pin-spec-changes.md` 2b에만 있다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 문자열 인자 MEDIAN/PERCENTILE의 CCI 표시(9개 파일, 273줄) | 옛 값에 드라이버 DOUBLE 규칙 적용 = 새 값, 273/273 | 통과 |
| 분석 AVG FLOAT 값(`_14_avg` 3개 파일, 54줄) | develop JDBC 답지(#3588) 값과 일치, 54/54 | 통과 |
| `cbrd_27510` 새 `.answer_cci` 16개 | JDBC 답지와 다른 214줄이 모두 같은 값의 표시 차이 | 통과 |
| 답지 없는 케이스 | 케이스 파일 변경 없음, 답지만 바뀜 | 해당 없음 |

케이스 파일을 바꾸지 않으므로 헤더 `;` 검사는 해당 없다. #3588이 바꾼 JDBC 답지 중 CCI 답지가 있는 `_18_host_vars`는 이 PR에 없다. 이 파일은 DOUBLE을 `%.9f`로 찍어 `5.700000000000002`와 `5.7`이 모두 `5.7`로 나오므로 고칠 필요가 없다. 판정: 답지 내용은 통과, 본문 정정 필요.

## Runtime Verification

- `just ctp sql_by_cci` (2026-10-26 추가, workspace `44b749b`), install `~/optdebug/CUBRID-cbrd27674-dev` = develop `2ef77b8f0` optdebug(#8022 포함), 8개 디렉토리 350 케이스, 코어 0.
- TC `ccfd034c4`(PR 헤드): Fail 9 / Success 341. 실행 디렉토리 `sql_by_cci-20261026T055222Z-3796483`.
- TC `6a52e963e`(merge-base): Fail 37 / Success 313. 실행 디렉토리 `sql_by_cci-20261026T055224Z-3796551`. 37 = 이 PR이 고친 28 + 남은 9.
- 남은 9개(percentile_cont `_02_analytic_function` 3, percentile_disc `_01` 3, `_02` 3)는 이 PR이 손대지 않은 `.answer_cci`다. diff는 같은 값의 표시 차이이고, percentile_disc `_00_from_dev` 4곳만 `-181` -> `-1118`(스펙, JDBC 답지는 #3588에서 갱신됨).

## Existing Comments

| 코멘트 | 위치 | 요지 |
|---|---|---|
| 6408436449 | 대화 탭 | 본문 "배경"의 규칙을 확인해 확인된 내용으로 바꿔 달라 |
| 4373976002 | bug_bts_13653 L29 | CCI 답지와 JDBC 답지를 맞추는 것이 스펙인지, 스펙이면 CBRD-27510에 적어 달라 |
| 4374036965 | avg_constraints L151 | average 값이 바뀐 이유 |
| 4374087151 | 11087 L182 | 문자열 컬럼 MEDIAN이 DOUBLE이 된 스펙 때문인지, 변경 전에는 어떻게 처리했는지 |
| 4374114723 / 4374119492 / 4374125094 | 11087 L229, 11087_3 L147, L621 | 같은 사항인지, 테스트 데이터가 달라졌는지 |
| 4374135034 | 01_fetch_gate_probes L1 | GHA에서 CCI를 돌릴 수 있는지 (작성자 대상, 개발 답 불필요) |

## 2차 (2026-10-27)

head `ccfd034c4` 그대로. 본문 "일부는 반대로" 문장 삭제 확인. 사용자 "전부다 approve해" -> APPROVE review 5661357779 (본문: percentile CCI 답지 9개 NOK 갱신 요청). AVG 스레드 정정 답글과 CBRD-27510 스펙 2b 추가는 하지 않음.
