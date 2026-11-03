---
status: accepted
date: 2026-10-30
issue: CBRD-27819 (CBRD-27797, CBRD-27799, CBRD-27703)
supersedes: 0039
---

# 손실 키 쌍의 비교는 고치지 않고 매뉴얼에 제한으로 명시한다; 엔진은 오답은 내도 뻗지 않는다

ADR 0039 는 손실 키 쌍(GLOSSARY)의 비교에서 인덱스·다중 키·파티션 경로가 순차 스캔과 같은 답을 내도록 맞추기로 했다. 구현(map #562, #569)은 동등 항을 범위 항으로 정규화하고 경계 자리 셋과 조인 접두 한 곳을 고치는 형태가 됐고, instructions:u 측정에서 손실 쌍 문장은 +6~25%, 정수 상수·정수 바인드 같은 일반 경로도 +3~4% 가 붙었다(`.git_ignored_dir/scratch/cbrd27819/569p/perf`). 사용자는 2026-10-30 이렇게 정했다: 2^53(FLOAT 는 2^24)을 넘는 값을 부동소수점으로 비교하는 상황은 워낙 특수하므로, CUBRID 는 그 상황에서 오답(경로마다 다른 답 포함)을 낼 수 있음을 매뉴얼에 제한으로 명시하고 우회 방법을 함께 적는다. 인덱스·파티션은 develop 그대로 탄다. 엔진은 그 상황에서 segfault·assert 로 뻗지 않아야 한다. 나머지 성능 최적화(`_dtoa` 제거, 정수×NUMERIC 직접 비교, 산술, 결과 캐시 해시)는 그대로 한다.

## Considered Options

- **(가) 인덱스 탐색 범위 넓히기(ADR 0039)**: 기각. 드문 상황을 맞추려고 일반 경로까지 비용을 낸다. 기록: #569 의 커밋 4개 diff 와 측정표(`scratch/cbrd27819/569p/`).
- **(나) 정확 비교(ADR 0037)**: 기각(ADR 0039 와 같은 이유).
- **(다) PostgreSQL 처럼 손실 키 쌍 열을 키로 쓰지 않음**: 기각. develop 이 타던 인덱스를 잃는다.

## Consequences

- CBRD-27797·27799·27703 은 수정하지 않고 "문서화된 제한" 으로 닫는다(JIRA 처리는 사용자 승인 뒤). CBRD-27819 는 NUMERIC 성능 개선으로 범위를 좁히고 need-manual 로 표시한다.
- 매뉴얼(cubrid-manual, 타입 변환/비교 규칙 절, `cubrid-manual-write`)에 적는다: 어떤 타입 쌍이 어느 범위를 넘으면 서로 다른 값이 같다고 판정될 수 있고 인덱스·파티션 경로와 순차 스캔의 결과 행이 다를 수 있는지; 우회 방법 — (1) 상수·바인드 값을 열의 타입으로 CAST (`b = cast(? as bigint)`), (2) 그 부동소수점 값과 같아지는 키 구간을 질의에 직접 범위로 쓰기(`b BETWEEN 9007199254740992 AND 9007199254740993`), (3) 열 쪽을 부동소수점으로 쓰지 않기.
- "뻗지 않는다" 의 증거: TC 140줄·실측 SQL·CS 조인·파티션 DML·큰 값(2^63 근처, NUMERIC(38), inf)을 develop 과 후보의 optdebug 로 돌려 assert·core·tracker leak 0. assert 가 나오면 그 자리만 방어적으로 고치고(답은 바꾸지 않음) 개별 커밋으로 둔다. NaN 은 #576 으로 보류.
- CBRD-27583 사양 14 의 단일 열 merges 탐색은 develop 의 일부라 그대로 둔다. 비교 결과는 develop 과 같다. 이 PR 에 사양 변경은 없다.

## 개정 (2026-11-03): 매뉴얼에도 적지 않는다

사용자는 2026-11-03 매뉴얼 작업도 하지 않기로 했다. CBRD-27797·27799·27703 과 CUBRIDMAN-361 은 처리하지 않고(Won't Fix) 닫고, 매뉴얼 draft PR cubrid-manual#784 도 닫는다. CBRD-27819 는 성능 개선만 남고, DOUBLE·FLOAT → 문자열 변환(`tp_dtoa_buffer`, `tp_ftoa_buffer`)의 `_dtoa` 제거가 범위에 더해진다. 위 Consequences 의 매뉴얼 항목은 효력이 없다. 엔진이 뻗지 않아야 한다는 항목은 그대로다.

근거로 재확인한 사실(PostgreSQL 18.6, Oracle 23ai Free, CUBRID develop 582fa3941 실측, `.git_ignored_dir/scratch/cbrd27819/grill/cbrd27819-approx-compare-summary.md`): 정확형 × DOUBLE 은 세 시스템 모두 DOUBLE 로 비교해 2^53 을 넘는 서로 다른 정수가 같다고 나온다. PostgreSQL·Oracle 은 이 비교에서 인덱스 스캔·파티션 프루닝을 하지 않아(Oracle 은 index 힌트도 무시) 경로 간 답이 같다. 두 시스템은 `1e0` 같은 지수 표기 리터럴을 numeric·NUMBER 로 받지만 CUBRID 는 SQL 표준대로 DOUBLE 로 받는다; CUBRID NUMERIC 은 38자리라 같은 선택을 하면 `1e300` 이 오류, `1e-300` 이 0 이 된다.
