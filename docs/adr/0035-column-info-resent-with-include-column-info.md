---
status: accepted
date: 2026-10-29
issue: CBRD-27679
supersedes: 0032 (EXECUTE 열 정보 부분)
---

# 실행한 플랜의 열 정보는 기존 include_column_info 로 다시 보낸다

ADR 0032 는 EXECUTE 응답에 "열 정보 있음/없음" 표시를 새로 두고, 드라이버와 브로커가 모두 PROTOCOL_V13 이상일 때만 쓰기로 했다. 구현을 시작하며 브로커의 EXECUTE 응답에 이미 `include_column_info` 바이트가 있음을 확인했다(PROTOCOL_V2 부터). 이 바이트가 1 이면 PREPARE 응답과 같은 형식의 열 정보가 뒤따르고, JDBC(`UStatement.readResultMeta`)와 CCI(`qe_execute` → `prepare_info_decode`)는 그 열 정보로 핸들의 열 정보를 바꾼다. 지금까지 브로커는 다중 문장일 때만 이 바이트를 1 로 보냈다.

- 브로커(CAS)는 실행한 플랜의 열 타입(CAS 타입, 정밀도, 스케일, charset)이 그 핸들에서 마지막으로 보낸 열 정보와 다르면 `include_column_info = 1` 로 열 정보를 다시 보낸다. 두 드라이버가 받은 열 정보를 핸들에 계속 두기 때문에, 비교 기준은 PREPARE 응답이 아니라 마지막으로 보낸 열 정보다.
- 열 타입은 컴파일한 열 목록(세션의 type_list)의 도메인이다. 단, 서명 플랜을 컴파일해도 `select ?` 같은 열은 그 목록에 VARIABLE 로 남으므로(실측: 이 이슈의 빌드에서 `select ?` 에 setInt 를 묶어 실행한 뒤 목록은 VARIABLE, 결과 list file 은 INTEGER), 목록의 도메인이 VARIABLE 이나 NULL 인 열은 실행한 플랜의 결과 list file 의 열 도메인을 쓴다. 나머지 열은 지금 메타데이터 그대로다.
- 드라이버 버전은 보지 않는다. V12 이하 드라이버도 11.5 서버에서는 `select ?` 같은 열의 메타데이터가 실행한 플랜의 타입으로 바뀐다.
- 그 결과 SELECT 의 NULL 타입 열에는 NULL 만 온다. 이것은 디버그 빌드의 assert 로만 확인한다(ADR 0032 의 "V13 드라이버에는 오류로 막는다"는 규칙은 둘 필요가 없어졌다).
- 응답 형식이 바뀌지 않으므로 엔진 PR 이 혼자 먼저 머지돼도 develop 의 드라이버가 그대로 동작한다. 그래서 엔진 PR 은 submodule 포인터를 올리지 않고, 드라이버 PR 이 머지된 뒤 봇이 여는 submodule sync PR 이 포인터를 올린다. 머지 순서는 엔진 → 드라이버 → sync PR 이다. 드라이버가 먼저 들어가면 develop 의 게이트웨이 CAS 가 타입 있는 길이 0 값을 값으로 읽는다.

ADR 0032 의 나머지, 즉 드라이버가 PROTOCOL_V13 이상 브로커에만 선언 타입이 있는 NULL 을 보낸다는 결정은 그대로다.

## Considered Options

- **새 "열 정보 있음/없음" 표시(ADR 0032)**: 기각. 같은 일을 하는 바이트가 이미 있고, 새 표시는 드라이버 수정과 버전 확인을 더 요구한다. 또 develop 의 V13 드라이버가 새 바이트를 읽지 못해 엔진과 드라이버를 한 PR 에서 함께 머지해야 한다.
- **PREPARE 응답과 비교**: 기각. 드라이버가 받은 열 정보를 핸들에 남기므로, INTEGER 를 보낸 뒤 PREPARE 와 같은 열 정보로 돌아온 실행에서 드라이버가 INTEGER 를 계속 쓴다.

## Consequences

- 브로커는 핸들마다 마지막으로 보낸 열 타입을 기억한다(`T_QUERY_RESULT.column_types`). SELECT 를 실행할 때마다 열마다 타입 하나를 비교한다.
- 이전 드라이버의 ResultSetMetaData 가 11.5 서버에서 바뀌는 것은 사양 변경으로 CBRD-27679 에 적는다.
