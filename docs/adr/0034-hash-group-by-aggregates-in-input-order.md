---
status: accepted
date: 2026-10-28
issue: CBRD-27802
---

# 첫 행 사본이 없는 해시 GROUP BY 는 행이 들어온 순서대로 누산한다

develop 의 해시 GROUP BY 는 그룹마다 첫 행 사본을 두고 둘째 행부터 누산기에 쌓은 뒤, 출력할 때 첫 행을 마지막으로 누산했다. CBRD-27802 는 출력이 그룹 키와 집계만 읽으면 사본을 두지 않고 첫 행부터 누산한다. 그래서 입력 순서에 따라 결과가 달라지는 집계는 develop 해시 결과와 달라진다. 표가 작아 그룹이 해시 표를 떠나지 않아도 마찬가지다. 아래 표의 작은 표에서는 `NO_HASH_AGGREGATE`(정렬 GROUP BY)와 같은 값이 나오지만, 정렬 GROUP BY 는 그룹 안의 행을 정렬 뒤 순서로 누산하므로 입력이 다른 순서로 들어오면 서로 다를 수 있다(CTP `json_host_variables`: `JSON_OBJECTAGG(i,j) from (select * from t order by 1 desc, 2 desc) group by i+1` 에서 해시는 입력 순서의 첫 값, 정렬은 다른 값). 실측(develop 2d925cb86 대 1a00ba4d2 optdebug, g=1 에 a=1,2,3 순서로 넣은 행):

| 질의 | develop 해시 | 수정 해시 | develop NO_HASH_AGGREGATE |
|---|---|---|---|
| `json_arrayagg(a)` | `[2,3,1]` | `[1,2,3]` | `[1,2,3]` |
| `json_objectagg('k', j)` (중복 키) | `{"k":"y"}` | `{"k":"x"}` | `{"k":"x"}` |
| `max(s)`, `min(s)` (utf8_en_ci, 'a'/'A') | `'A'` | `'a'` | `'a'` |
| `max(tz)` (같은 시각, 다른 시간대) | `+00:00` | `+09:00` | `+09:00` |
| `sum(sm)` (SMALLINT 30000, 10000, -10000) | 30000 | overflow 오류 | overflow 오류 |
| `sum(d) - 1e16` (DOUBLE 1e16, 1, 1) | 2 | 0 | 0 |

2026-10-28 사용자가 이 변화를 사양 변경으로 받아들였다(질문 때는 'NO_HASH 와 같아진다' 로 설명했고, 게이트에서 위 반례가 나와 '입력 순서대로' 로 정정해 알렸다). 첫 행 사본을 유지하는 GROUP BY(그룹 키가 아닌 열·서브쿼리·분석 함수·CONNECT BY·ROWNUM 계열·다중 테이블 UPDATE/DELETE·WITH ROLLUP)는 develop 순서 그대로다. 같은 날 GROUPBY_NUM()과 그것으로 바뀌는 `GROUP BY ... LIMIT n`(ORDER BY 없음)도 사본 없이 처리하기로 해, 이 순서 변화가 LIMIT 질의에도 적용된다.

## Considered Options

- **순서 민감 집계가 있으면 첫 행 사본 유지**: 기각. develop 해시 결과는 "첫 행을 마지막에" 라는 구현의 부산물이다. 이를 보존하려면 JSON_ARRAYAGG·JSON_OBJECTAGG, DOUBLE/FLOAT 합·평균·분산, 작은 정수 SUM, 콜레이션·시간대 MIN/MAX 가 있는 질의를 최적화에서 빼야 한다.

## Consequences

- 그룹이 hash 표를 여러 번 나가 partial 여럿으로 나뉘면 partial 끼리 합치는 순서가 정렬 GROUP BY 와 다르다. 그래서 DOUBLE 합·분산은 그런 그룹에서 develop 처럼 NO_HASH_AGGREGATE 와 마지막 자릿수가 다를 수 있다(smoke: 30만 행 STDDEV/VARIANCE/SUM(DOUBLE), develop 과 같은 차이).
- SUM(SMALLINT) 처럼 누산 중 범위를 넘는 질의는 develop 해시에서 값을 냈어도 수정 뒤에는 정렬 GROUP BY 처럼 오류를 낼 수 있다.
- TC 는 `cbrd_27802_spec_change.sql` 이 위 표를 고정한다(직전 빌드 NOK 가 정상). develop 해시 순서를 답으로 가진 기존 TC 다섯 개(`json_aggregate`, `json_aggregate_2`, `json_host_variables`, `_02_select_groupby_dttz`, `_02_select_groupby_tstz`)의 답을 새 순서로 바꾼다.
- 같다고 비교되지만 표기가 다른 그룹 키(JSON `true` 와 `"true"`, 같은 시각의 다른 시간대)는 develop 해시와 같은 값을 보인다: 한 엔트리 안에서는 첫 행의 키, partial 여럿이 합쳐질 때는 정렬 순서상 마지막 엔트리의 키.
