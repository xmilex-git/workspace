# flaky TC 보고 — _01_no_data_filter.sql의 ORDER BY 없는 LIMIT 결과 비교

PR #8022의 gha-ci SQL 테스트에서 아래 TC가 1회 실패하여 보고합니다. 실패 질의의 내부 LIMIT에 ORDER BY가 없어, 고정 답지와 비교하는 행 집합이 스캔 순서에 의존하는 TC로 판단합니다. 확인 및 TC 안정화 검토 부탁드립니다.

## 대상
`sql/_18_index_enhancement_qa/_02_full_test/_06_optimizing_limit/cases/_01_no_data_filter.sql`

## 실패 내용 및 근거
- run `37168626427`, SQL shard 05에서 실패했습니다. 수집한 120개 run 중 이 케이스가 실패 목록에 나타난 것은 이 run 1개입니다.
- `select * from (select /*+ recompile */ * from t where ... limit 2,8) t order by ...` 형태의 두 질의에서 답지와 행 집합이 달라졌습니다.
- 첫 번째 diff: 답지의 `(2,1,21)`이 빠지고 `(2,4,24)`가 나타납니다.
- 두 번째 diff: 답지의 `(2,1,21)`이 빠지고 `(4,2,42)`가 나타납니다.
- 원인 조사에서 실패 질의는 `sscan + inst_num`으로 LIMIT을 처리하며, 같은 파일의 iscan 질의는 답지와 일치하는 것으로 확인했습니다.

## 원인 및 수정 요청
내부 서브쿼리에 ORDER BY가 없기 때문에 LIMIT으로 선택되는 8행은 힙 스캔 순서에 따라 달라질 수 있습니다. 바깥의 ORDER BY는 이미 선택된 행을 정렬할 뿐, LIMIT 대상 행 집합을 고정하지 않습니다. 관측된 diff는 이 순서 의존성과 부합합니다.

- 특정 행 집합을 검증하려면 내부 서브쿼리에도 ORDER BY를 넣어 LIMIT 대상을 결정해 주세요.
- 다만 이 TC는 keylimit 재작성 여부도 검증하므로, ORDER BY 추가로 검증하려는 플랜이 바뀌지 않는지 확인이 필요합니다. 행 집합 자체가 검증 목적이 아니라면 결과 개수/적합성 및 본래 플랜 검증을 분리하는 방식도 검토해 주세요.
- 고정 답지를 이번 실패 결과로 단순 교체하기보다는, LIMIT 대상의 결정성 또는 비교 방식부터 보강하는 것이 맞겠습니다.

## 확인 범위
develop 빌드에서 이 실패를 재현한 기록은 없으며, 기존 조사에서 재실행으로도 재현되지 않았습니다. 동일 엔진/TC revision 반복 재현으로 #8022와의 무관성을 확정한 상태는 아닙니다. 현재 판단은 SQL의 비결정적 행 선택, 관측 플랜, 실제 answer/result diff에 근거합니다.

## 참고 링크
- 실패 run: https://github.com/CUBRID/cubrid/actions/runs/37168626427 (SQL shard 05)
- 관련 PR: https://github.com/CUBRID/cubrid/pull/8022
