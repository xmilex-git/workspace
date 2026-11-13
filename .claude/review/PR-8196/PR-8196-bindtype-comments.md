# PR #8196 post-ready comments (바인드 타입 집중 리뷰)

## CUBRID/cubrid#8196 (engine)

- review event: COMMENT
- commit_id: ec25c8e802d719cbc1c5abbb56cde22208691ac5

### top-level

CBRD-27583 뒤로 필터·출력 프로그램을 클론당 한 번 컴파일하고 서명 재검사를 뺀 부분, 해시 조인 build 해시가 `input->converters` 를 보는 부분은 컴파일 결정을 그대로 쓰고 있습니다. 배치 층에서 바인드 값의 타입을 다시 보는 곳 몇 군데를 인라인으로 남겼습니다. NUMERIC 바인드 17가지(scale 이 다른 값, 3000000000 등)는 이 PR 과 develop optdebug 빌드의 결과가 같았습니다.

추가로 논의가 필요해 보이는 항목
- `expr_compile` 의 프로그램은 지금 서버가 클론의 첫 평가에서 regu 트리를 낮춰 만듭니다. CBRD-27583 으로 타입 결정이 XASL 생성으로 올라갔는데, 이 낮추기도 파서(XASL 생성) 쪽으로 옮길 계획이 있는지 궁금합니다.

### src/query/expr_batch.c:2434

prologue 스텝이 내는 셀은 여기서 `DB_TYPE_UNKNOWN` 스칼라가 되고, 소비 커널이 `eb_bind_operand ()` 에서 타입을 붙입니다. 그래서 집계 루트가 이런 셀이면(`:2986`), 피연산자가 `?` 그대로면(`:3030`) 소비 노드가 거절됩니다. CBRD-27583 뒤로는 `expr_prog_step_info ()` 가 hostvar 에 `info.regu->domain`, 산술에 `info.type`, CAST 에 `info.domain` 을 주니 여기서 타입을 정할 수 있지 않나요?
이 PR optdebug 빌드(20만 행, 직렬)에서 `SUM(2)`·`SUM(2+1)` 은 배치 집계(fetch 2840)인데 `SUM(?)`·`SUM(?+1)` 은 필터만 청크로 돌았습니다(fetch 11316). `TYPE_POS_VALUE` 피연산자도 `TYPE_DBVAL` 가지처럼 `operand->domain` 타입의 스칼라로 받는 것은 어떨까요?

### src/query/expr_batch.c:3743

바인드 값은 서명 타입 그대로 오고, develop 의 행 경로는 같은 조건을 optdebug assert 로만 확인합니다(`expr_k_hostvar ()`, `EXPR_ARITH_REQUIRE_TYPE`). 이 가드는 debug 빌드에서 계약이 깨져도 행 경로로 넘겨 assert 가 나지 않게 하고, release 빌드에서는 돌지 않는 코드입니다. 같은 모양이 `:3816`, `:3852`, `:3891`, `:1605`, `:4736`(행마다) 에 있습니다.
타입 비교는 `assert (DB_IS_NULL (v) || DB_VALUE_DOMAIN_TYPE (v) == type)` 로 바꾸고, 값 범위 검사(NUMERIC 워드 범위, BIGINT 창, SUBSTRING 1 이상)만 남기는 것은 어떨까요?

### src/query/query_hash_join.c:4595

`dom` 으로 읽으니 여기서 `hjoin_rtf_key ()` 가 -1 을 돌려줄 수 없는 것으로 보입니다. 그런데 돌려준다면 그 키가 집합에서 빠지고, probe 쪽 같은 키의 행이 `hjoin_rtf_pass ()` 에서 떨어집니다. assert 로 두거나, 남긴다면 키를 건너뛰는 대신 필터를 포기하는 쪽이 맞지 않나요?

### src/query/expr_compile.c:3948

정수 리프는 NULL 바인드를 받아 `k_null` 로 처리하는데(`eb_load_leaf_constants ()`), 문자열 리프와 NUMERIC 리프(`:3765`)는 값이 NULL 이면 리프가 아니라고 답합니다. 그 결과 `c = ?`, `n < ?` 에 NULL 을 바인드한 실행은 `batch: no (the data filter is interpreted)` 로 스캔 전체가 행 경로로 갑니다(`a > ?` 에 NULL 은 배치 710페이지). 리프 자격은 컬럼과 `k->domain` 으로 정하고, NULL 은 로드 때(`expr_batch.c:3811` 포함) `k_null` 로 두는 것은 어떨까요?

### src/query/query_aggregate.cpp:1207

`ER_QPROC_INVALID_XASLNODE` 를 받은 클라이언트는 xasl_id 를 버리고 다시 컴파일해 재실행합니다(`db_execute_and_keep_statement_local ()` 의 재시도, cas 의 `recompile_statement ()`). 그래서 release 빌드에서 이 불변식이 깨지면 오류 대신 조용한 재컴파일이 됩니다. `:1163`, `:1235` 도 같은 모양인데 다른 에러 코드를 쓰는 것은 어떨까요?

## TC PRs

- 이번 범위 밖. 리뷰 없음.
