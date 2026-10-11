# Teams flaky TC 보고 — 게시 전 초안 4건

게시 예정: **RND → 5.Issue Task**, 각 글을 독립된 새 게시물로 등록.
현재 상태: **미게시**. Teams 작성창 입력·전송, JIRA/GitHub 이슈 생성, TC 수정/재실행은 하지 않았습니다.
각 섹션의 제목과 본문만 복사하면 됩니다. 아래 게시 준비 메모는 게시 본문에 포함하지 않습니다.

## 게시 준비 메모
- 원본: 6.35의 `/home/cubrid/dev/workspace/.claude/review/PR-8022/ci-tc-defects-20261004.md`. 원본은 수정하지 않았습니다.
- 원본 인용 A/B는 이전 조사 결과이며 이번 초안 작성 중 새로 수행한 실험이 아닙니다.
- 보관된 `hits.tsv` 120행을 프로그램으로 집계했습니다. 원본의 SQL 13 run / shell 12 run 표기는 각각 **12 / 11**로 바로잡았습니다. 실패 목록의 출현 횟수이지 전체 실행 대비 실패율은 아닙니다.
- 대표 run의 sql/shell `failed.list`를 직접 읽어 대상 9 SQL 및 shell 경로·shard를 대조했습니다. SQL LIMIT의 보관 answer/result diff, 잠금 TC의 XML, shell 두 케이스의 pinned 소스를 확인했습니다. 전체 120 run의 원격 아티팩트를 새로 재수집하지는 않았습니다.
- workflow의 `headBranch=develop` 및 `headSha`는 PR run에서 실제 테스트 엔진 SHA를 뜻하지 않습니다. PR run이 develop 엔진으로 테스트됐다고 주장하지 않도록 정리했습니다.
- 3번은 develop 재현/인과 배제가 미확정이며 4번 동기화 원인의 구체적 경합 경로도 미계측임을 본문에 명시했습니다.
- 엔진 결함 CBRD-27557은 별도이며, 1번에 포함된 shell TC 자체의 전제/재시작 보강과 구별했습니다.

---

# flaky TC 보고 — cbrd_25717 답지·데이터 크기 전제 불일치

PR #8022의 gha-ci 실패를 확인하던 중, cbrd_25717의 SQL 9건과 shell membuf_config 1번 검사에서 TC의 답지·데이터 크기 전제가 현재 엔진과 맞지 않는 것을 확인하여 보고합니다. 간헐적 flake가 아니라 엔진 변경 이후 반복되는 TC 결함입니다. 확인 및 TC 수정 부탁드립니다.

## 대상
- `sql/_36_guava/cbrd_25717/cases/`의 다음 9건:
  - `cbrd_25717_agg_inline_view_parallel.sql`
  - `cbrd_25717_empty_input.sql`
  - `cbrd_25717_multi_hashjoin.sql`
  - `cbrd_25717_nl_baseline.sql`
  - `cbrd_25717_nm_skew_join.sql`
  - `cbrd_25717_null_join_key.sql`
  - `cbrd_25717_parallel_hint.sql`
  - `cbrd_25717_sector_dependent_list.sql`
  - `cbrd_25717_trace_json.sql`
- `shell/_40_guava/cbrd_25717/cbrd_25717_membuf_config/cases/cbrd_25717_membuf_config.sh`의 1번 검사(membuf-only)

## 실패 내용 및 근거
- SQL trace의 BUILD 방식이 답지의 `hybrid`에서 `memory`로 바뀝니다. `agg_inline_view_parallel`에는 `memory+hybrid`가 나타나는 부분도 있으며, `nl_baseline`에서는 BUILD/PROBE의 `t_nla`·`t_nlb`가 바뀝니다.
- membuf-only는 결과 500은 맞지만, 기대한 병렬 해시 조인 대신 직렬 실행되어 `workers=none`입니다.
- 기존 원인 조사에서 develop OptDebug 빌드 A/B를 수행했습니다. 동일 TC revision(SQL `dbac2f953`, shell `9e9f773d1`)에서 #7866 직전 `35a7cddb6`은 SQL 14/14 통과·membuf-only `workers=2`, #7866 머지 빌드 `453da49c8`은 해당 SQL 9건 실패·membuf-only `workers=none`입니다.
- 수집한 120개 run의 실패 목록을 재집계하면 같은 SQL 9건은 12개 run, membuf_config는 11개 run에 나타납니다. 이 숫자는 조사 범위 내 실패 run 수이며, 해당 TC가 실제 실행된 전체 횟수나 실패율을 뜻하지 않습니다.
- PR 없는 develop dispatch에서도 확인됩니다: SQL run `37016878105`, SQL/shell run `37027696235`.

## 원인 및 수정 요청
#7866(CBRD-27365)의 임시 리스트 튜플 포맷 축소로 같은 데이터의 리스트 페이지 수·메모리 추정치가 줄어들어, 기존 입력이 전제한 hybrid/병렬 경계와 BUILD 쪽 선택이 달라졌습니다. 의도된 엔진 변경에 맞춰 TC를 보정할 사안입니다.

- hybrid/SPLIT 경로 자체가 검증 목적이면 데이터 폭·행 수·파라미터를 조정하여 그 경로가 실제 선택되는 것을 trace로 확인한 뒤 답지를 갱신해 주세요. 행 수 증가만으로 복원된다고 전제하지 않고, projection에 남는 컬럼 폭 등도 함께 검토가 필요합니다.
- `nl_baseline`은 BUILD 쪽 고정이 검증 목적이면 입력 크기에 충분한 차이를 두고, 부수 출력이면 현행 실측을 반영하되 결과 동등성 검증은 유지해 주세요.
- membuf-only는 20페이지 버퍼 안에 들어가면서 병렬 실행 하한을 충족하는 입력으로 보강해 주세요.
- 수정 후 동일 엔진/TC revision 반복 실행으로 의도한 경로와 결과가 안정적으로 유지되는지 확인 부탁드립니다.

참고로 membuf_config의 3~6번 검사에서 발생하는 서버 crash(CBRD-27557)는 별도 엔진 이슈이며 이 TC 결함과 분리해야 합니다. `set_membuf`의 재시작 실패를 즉시 검출하여 뒤 검사로 연쇄되는 실패를 막는 보강도 필요합니다.

## 참고 링크
- 대표 실패 run: https://github.com/CUBRID/cubrid/actions/runs/37168626427 (SQL shard 09 / shell shard 33)
- develop SQL dispatch: https://github.com/CUBRID/cubrid/actions/runs/37016878105
- develop all dispatch: https://github.com/CUBRID/cubrid/actions/runs/37027696235
- 관련 엔진 변경: https://github.com/CUBRID/cubrid/pull/7866
- SQL TC PR: https://github.com/CUBRID/cubrid-testcases/pull/3497
- shell TC PR: https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4150


---

# flaky TC 보고 — cbrd_25717_parallel_degree 병렬도 상한 기대식 오류

PR #8022의 gha-ci에서 `cbrd_25717_parallel_degree` 2번 검사가 실패하여 보고합니다. PR 없는 develop dispatch와 #7866 전후 develop 빌드에서도 같은 검사가 실패하므로, #8022 변경이나 #7866에 의해 새로 생긴 문제가 아니라 TC 기대식의 문제로 판단합니다. 확인 및 TC 수정 부탁드립니다.

## 대상
`shell/_40_guava/cbrd_25717/cbrd_25717_parallel_degree/cases/cbrd_25717_parallel_degree.sh`

2번 검사: `PARALLEL(1000)`의 실제 워커 수를 `pmax = MIN(32, nproc)`와 비교합니다.

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


---

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


---

# flaky TC 보고 — bug_bts_13242 잠금 덤프 시점 동기화 불안정

PR #8022의 gha-ci shell 테스트에서 `bug_bts_13242`가 실패하여 보고합니다. 다른 PR에서도 반복 관측되며, 잠금 개수만으로 lockdb 덤프 시점을 결정하는 TC의 동기화 문제로 판단합니다. 확인 및 안정화 부탁드립니다. 필요하면 수정 전 unstable 이관도 검토 부탁드립니다.

## 대상
`shell/_06_issues/_14_1h/bug_bts_13242/cases/bug_bts_13242.sh`

실패 검사: `bug_bts_13242-1`, `issue_13242.result_sorted`와 `issue_13242.answer_sorted` 비교

## 실패 내용 및 근거
- 대표 실패는 run `37168626427`, shell shard 16입니다.
- sorted diff에서 결과 쪽 `LOCK HOLDERS` 블록과 `dba.t1` 인스턴스 잠금이 하나 더 나타납니다. 원인 조사에서는 클래스 잠금 모드(`SCH_S_LOCK` 대비 `IX_LOCK`/`X_LOCK`)와 `IS_LOCK`의 Count(1 대비 4) 차이도 확인했습니다.
- 수집한 120개 run 중 9개 run, 서로 다른 PR 8개에서 실패했습니다.
- 관측 run: `36694232105`(#7901), `36701588264`(#7957), `36702541200`(#7977), `36703643879`(#7993), `36743148780`(#8001), `36795106556`(#7969), `36799634228`(#8059), `36986809351`(#7943), `37168626427`(#8022).

## 원인 및 수정 요청
TC의 `run_test_point`는 SQL을 백그라운드 csql에 보내고, `export_lockdb`는 1초 간격으로 lockdb를 실행해 `Current number of objects which are locked`가 기대 개수와 같아지면 덤프를 채택합니다. 같은 개수라고 같은 잠금 집합인 것은 아니므로, 잠금 획득 중간 상태나 이전 검사 정리 상태를 채택할 수 있습니다.

또한 현재 `lock_done.flag`는 덤프 후 rollback을 허용하는 신호이며, csql이 대상 SQL 실행을 완료했다는 신호는 아닙니다. `wait_pid_exit`도 60초 뒤 여전히 살아 있는 세션을 명시적으로 실패 처리하지 않습니다. 시점 동기화가 불완전하다는 판단은 이 소스와 관측 diff에 근거하며, 실패 시점의 세션 상태를 계측해 경합 경로까지 확정한 것은 아닙니다.

- 단순 개수 대신 기대하는 클래스·인스턴스·모드의 잠금 집합을 확인하거나, SQL 완료를 확인하는 세션 측 신호를 받은 뒤 트랜잭션을 유지한 상태로 덤프해 주세요. 파이프에 SQL을 썼다는 사실만으로 실행 완료를 간주하면 안 됩니다.
- 기대 상태 대기 타임아웃과 이전 세션 종료 실패를 명시적인 NOK로 처리하여 다음 검사로 잘못 진행하지 않도록 보강해 주세요.
- sleep 시간을 늘리거나 잠금 차이를 답지에서 없애기보다, 본래 잠금 검증은 유지하고 덤프 시점의 결정성을 확보하는 방향으로 수정 부탁드립니다.
- 수정 후 동일 엔진/TC revision 반복 실행으로 안정성을 확인 부탁드립니다.

## 참고 링크
- 대표 실패 run: https://github.com/CUBRID/cubrid/actions/runs/37168626427 (shell shard 16)
- 다른 PR의 실패 예: https://github.com/CUBRID/cubrid/actions/runs/36694232105
- TC 소스: https://github.com/CUBRID/cubrid-testcases-private-ex/blob/9e9f773d1/shell/_06_issues/_14_1h/bug_bts_13242/cases/bug_bts_13242.sh
