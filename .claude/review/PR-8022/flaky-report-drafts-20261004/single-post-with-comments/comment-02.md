# 댓글 2 — cbrd_25717_parallel_degree 병렬도 상한 기대식 오류

## 실패 내용 및 근거
- CI: `cores=192 pmax=32`인데 `actual='8' expected='32'`로 실패합니다.
- 기존 원인 조사의 develop A/B: `35a7cddb6`, `453da49c8` 모두 `actual='25' expected='32'`입니다.
- 같은 실행의 1·3·4·5번 검사는 통과했습니다(`PARALLEL(4)` → 4, 0/음수 → 직렬, 5번은 `requested=32 workers=7 partitions=7`).
- 수집한 120개 run 중 이 케이스가 실패 목록에 나타난 run은 11개입니다. develop all dispatch `37027696235`에서도 실패합니다.

## 원인 및 수정 요청
실제 워커 수는 힌트 상한과 CPU 수만으로 정해지지 않고 입력 페이지 수·파티션 수·가용 워커에도 제한됩니다. TC는 5번 검사에서 파티션 상한을 반영하면서 2번 검사에서는 이를 빠뜨리고 있습니다.

- develop A/B의 25는 원인 조사에서 확인한 파티션 수 제한과 일치합니다.
- CI의 8은 엔진의 affinity/cgroup 기반 CPU 인식과 `nproc`의 차이 가능성이 있으나, 이 조사에서 CI CPU quota를 직접 측정해 확정한 것은 아닙니다.
- 2번 검사는 `PARALLEL(1000)`과 `PARALLEL(32)`가 동일한 유효 병렬도로 제한되는지를 비교하는 방식 등을 검토해 주세요. 비교 시 두 실행 모두 실제 병렬 경로에 진입했는지와 결과 값도 확인하여, 둘 다 직렬인 경우를 통과로 처리하지 않아야 합니다.
- 정확히 32 워커를 검증하려면 파티션·페이지·엔진 인식 CPU·가용 워커 조건을 먼저 충족해야 합니다. 이 전제 없이 CI에서 32를 기대하는 방식은 피하는 것이 맞겠습니다.
- 동일 엔진/TC revision 반복 실행으로 환경별 안정성과 기존 하한·파티션 제한 검증이 유지되는지 확인 부탁드립니다.

## 참고 링크
- 대표 실패 run: https://github.com/CUBRID/cubrid/actions/runs/37168626427 (shell shard 49)
- develop all dispatch: https://github.com/CUBRID/cubrid/actions/runs/37027696235 (shell shard 23)
- TC 소스: https://github.com/CUBRID/cubrid-testcases-private-ex/blob/9e9f773d1/shell/_40_guava/cbrd_25717/cbrd_25717_parallel_degree/cases/cbrd_25717_parallel_degree.sh
- TC PR: https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4150
