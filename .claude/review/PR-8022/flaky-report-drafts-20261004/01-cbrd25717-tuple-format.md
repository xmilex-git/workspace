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
