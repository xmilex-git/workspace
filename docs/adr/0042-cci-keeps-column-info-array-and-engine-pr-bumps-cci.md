---
status: accepted
date: 2026-11-03
issue: CBRD-27679 / APIS-1130
supersedes: 0035 (submodule 포인터와 머지 순서 부분)
---

# CCI 는 다시 받은 열 정보를 같은 배열에 덮어쓰고, 엔진 PR 이 cubrid-cci 포인터를 올린다

ADR 0041 로 브로커는 PREPARE 응답이 타입을 정하지 못한 열이 있는 SELECT 를 실행할 때마다 V13 드라이버에 `include_column_info = 1` 로 열 정보를 보낸다. CCI 는 이것을 `qe_execute` → `prepare_info_decode` 로 받아, 핸들의 열 정보 배열을 풀고(`req_handle_col_info_free`) 새 배열로 바꿔 왔다. `cci_get_result_info` 가 돌려주는 것은 이 배열 자체라, PREPARE 뒤에 받아 둔 포인터를 EXECUTE 뒤에도 쓰는 응용은 풀린 메모리를 읽는다. develop 에서는 다중 문장일 때만 이 경로를 탔다.

엔진 PR(cubrid#8317)의 CI(gha 41553251846, 엔진 b22224b92 + develop CCI a6a16d5)가 이것을 드러냈다:
- shell `bug_bts_9756`: CCI 프로그램이 PREPARE 뒤 받은 포인터로 EXECUTE 뒤 열 이름을 읽다가 SEGV. valgrind: `cci.c:229` 의 읽기가 `cci_execute` → `prepare_info_decode` → `req_handle_col_info_free` 가 푼 블록.
- shell `cbrd_24501_cubrid`: DBLink 도 PREPARE 뒤 포인터를 둔다(`dblink_scan.c` "metadata is fixed at prepare time"). 풀린 배열에서 타입을 읽어 `dblink - Type conversion error`, `not supported type set`.
develop 309265e6d 에서는 같은 스모크(`cbrd27679-impl/smoke/colinfo.sh`)가 모두 통과한다.

- CCI(APIS-1130): `prepare_info_decode` 가 받은 열 수가 핸들의 열 수와 같으면 배열을 풀지 않고 각 열을 그 자리에 덮어쓴다. 문자열(열 이름, 속성 이름, 클래스 이름, 기본값)은 이전 것과 같으면 이전 것을 두고 새 것을 푼다. 열 수가 다르면 지금처럼 바꾼다(다중 문장의 다음 결과).
- 엔진 PR 이 cubrid-cci submodule 포인터를 APIS-1130 의 커밋으로 올린다. 엔진만 먼저 들어가면 develop 의 CCI 응용과 DBLink 가 위처럼 깨지고, 드라이버만 먼저 들어가면 develop 의 게이트웨이 CAS 가 타입 있는 길이 0 값을 값으로 읽는다(ADR 0035). 머지는 cubrid-cci#118 → 엔진 PR 의 포인터를 머지된 커밋으로 다시 맞춤 → 엔진 PR 순서다. #118 머지와 엔진 머지 사이에는 develop 의 cubrid-cci 브랜치만 앞서 있다. 엔진의 포인터는 아직 옛 커밋이라 develop 빌드에는 영향이 없고, cubrid-cci 를 따로 빌드해 develop 게이트웨이 CAS 에 붙이는 경우만 위 문제를 겪으므로 이 간격은 짧게 둔다. cubrid-jdbc 포인터는 올리지 않는다(2026-11-03 사용자 결정).

## Considered Options

- **CAS 가 클라이언트 요청이 있을 때만 다시 보낸다**: 기각. CCI 가 실행한 플랜의 열 타입을 받지 못해 APIS-1130 의 "column info follows the executed plan" 을 버리게 되고, CCI 가 요청하는 순간 같은 해제가 돌아온다.
- **머지 순서 엔진 → 드라이버 → sync PR 유지(ADR 0035)**: 기각. 그 사이 develop 의 CCI 응용과 DBLink 가 죽는다.
- **엔진 PR 이 cubrid-jdbc 포인터도 올린다**: 기각(2026-11-03 사용자 결정). 이 문제와 무관하다.

## Consequences

- `cci_get_result_info` 가 돌려준 포인터는 같은 결과 형태의 EXECUTE 뒤에도 유효하고, 그 포인터로 읽는 타입은 실행한 플랜의 타입이다.
- 엔진 PR 의 CI 가 새 CCI 와 새 CAS 의 조합을 검증한다.
