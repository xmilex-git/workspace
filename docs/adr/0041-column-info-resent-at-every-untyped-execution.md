---
status: accepted
date: 2026-11-02
issue: CBRD-27679
supersedes: 0035 (열 정보를 다시 보내는 조건)
---

# 타입이 정해지지 않은 열이 있으면 실행마다 열 정보를 다시 보낸다

ADR 0035 는 CAS 가 핸들마다 마지막으로 보낸 열 타입(`T_QUERY_RESULT.column_types`)을 기억하고, 실행한 플랜의 열 타입이 그것과 다를 때만 `include_column_info = 1` 로 열 정보를 다시 보내기로 했다. 그 전제는 CAS 문장 핸들 하나를 클라이언트 한 연결만 쓴다는 것이다. SHARD 브로커는 이 전제를 깬다. SHARD 프록시는 같은 SQL 을 쓰는 여러 연결이 CAS 문장 핸들 하나를 함께 쓰게 하고, 두 번째 연결의 PREPARE 에는 캐시해 둔 응답을 돌려준다(`shard_proxy_function.c` 의 `shard_stmt_find_by_sql`, 같은 프로토콜 버전끼리만 공유). 그래서 CAS 가 기억한 열 타입은 요청한 연결이 가진 열 정보와 어긋난다. 리뷰(cubrid#8317, 2026-11-02)의 재현: `select /*+ shard_id(0) */ ? from db_root` 를 두 연결이 바인드 값만 바꿔 번갈아 실행하면, PREPARE 응답의 NULL 타입 열 정보를 가진 연결이 열 정보도 타입 바이트도 없는 INT 값을 받아 JDBC `null`, CCI -20008 이 되고, CHAR 열 정보를 가진 연결이 INT 값을 받아 NUL 3자를 읽는다. 타입 있는 NULL 없이도 틀린다.

- PROTOCOL_V13 이상 드라이버의 SELECT 실행에서, PREPARE 응답이 타입을 정하지 못한(NULL 타입) 열이 하나라도 있으면 실행마다 `include_column_info = 1` 로 열 정보를 보낸다. 그런 열이 없으면 ADR 0035 이전과 같이 보내지 않는다.
- 기준은 PREPARE 응답이다. 클라이언트가 실행 전에 가진 열 정보가 PREPARE 응답이고, SHARD 에서도 핸들을 함께 쓰는 연결은 모두 캐시된 같은 PREPARE 응답을 받는다. CAS 는 PREPARE 때 어느 열이 NULL 타입이었는지만 핸들에 둔다(`T_QUERY_RESULT.untyped_column`). 연결마다 다른 "마지막으로 보낸 열 타입"은 두지 않는다.
- 그런 열의 타입은 실행한 플랜의 결과 list file 도메인이다. 실행 때 컴파일한 열 목록의 도메인으로 고르지 않는다. SQL 의 `EXECUTE st USING ...` 은 값을 넣어 열 목록을 다시 컴파일하므로, PREPARE 응답은 NULL 타입이어도 실행 때 목록은 다른 타입일 수 있다(실측: `prepare st from 'select s1 + ? from t1'` 을 `execute st using 0.123123e1` 로 실행하면 PREPARE 응답은 NULL 타입, 실행 때 목록은 STRING, 결과 list file 은 DOUBLE).
- V13 한정과 값마다 타입 태그를 붙이는 경로는 ADR 0035 그대로다.

## Considered Options

- **SHARD 일 때만 실행마다 보낸다**(`cas_shard_flag`): 기각. 일반 브로커에 ADR 0035 의 비교 경로와 핸들 상태를 남기고 두 경로를 유지해야 한다. 아끼는 것은 타입이 정해지지 않은 열이 있는 문장의 실행당 열 정보 바이트뿐이다.
- **PREPARE 응답과 비교**: ADR 0035 에서 기각한 그대로다. 드라이버가 받은 열 정보를 핸들에 남긴다.
- **실행한 플랜의 열 타입이 PREPARE 응답과 같아도 생략하지 않고, 다를 때만 보낸다**: 위와 같은 이유로 기각. 다른 실행이 보낸 열 정보를 드라이버가 갖고 있을 수 있다.
- **실행 때 컴파일한 열 목록이 VARIABLE/NULL 인 열로 판단한다**: 기각(이 ADR 의 첫 구현). `EXECUTE` 문은 실행 때 목록이 타입을 갖게 되어 열 정보를 보내지 않았고, 클라이언트는 PREPARE 의 NULL 타입 열 정보로 값을 읽었다. sql_by_cci 의 `number_string`, `late_binding` 4 케이스가 develop 표기로 돌아가 드러났다.

## Consequences

- `select ?, a, b from t` 처럼 PREPARE 가 타입을 정하지 못한 열이 있는 SELECT 는 V13 드라이버에 실행마다 열 정보(열 이름, 클래스, 속성 이름 포함)를 더 보낸다. develop 은 그런 열의 값마다 타입 바이트를 붙여 왔다. 그런 열이 없는 SELECT 의 응답은 develop 과 바이트 단위로 같다.
- 실행 응답마다 `prepare_column_list_info_set` 이 다시 돌므로, 앞선 실행이 만든 `col_update_info` 를 먼저 푼다(`hm_col_update_info_free`).
