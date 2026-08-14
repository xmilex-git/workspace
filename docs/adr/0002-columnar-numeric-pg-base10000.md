# Columnar NUMERIC은 PG base-10000 포맷·산술·시맨틱을 통째로 채택한다

columnar 블록의 DB_VALUE-비경유 실행(#23)에서 NUMERIC의 raw 표현이 필요했다. 엔진 고유의 17B base-256 sign-magnitude(부호는 버퍼 밖 `is_value_negative`)를 그대로 쓰는 안과 int128 고정소수점 안을 기각하고, **PostgreSQL `numeric.c`의 base-10000 방식** — 디스크 포맷(sign+weight/dscale 헤더+int16 digit 배열, 가변폭)과 산술(add_var/mul_var/div_var 계열), 그리고 결과 scale·반올림 **시맨틱까지** — 을 columnar 한정으로 통째 채택한다(#23 D6/D11/D12).

## Considered Options

- **int128 고정소수점**: 기각 — `DB_MAX_NUMERIC_PRECISION=40`이라 NUMERIC(39~40)이 128비트(±38자리)를 초과한다.
- **17B two's complement 교정(최소 수정)**: 기각 — 산술 표현이 base-10000이면 read hot loop에 행×컬럼마다 binary→decimal 변환이 박힌다. 디스크=산술 표현으로 맞춰야 읽기 변환이 0이다.
- **heap 시맨틱 미러 + base-10000 substrate**: 기각(사용자 결정) — PG 코드를 정책까지 그대로 가져와 이식·유지 비용을 최소화한다.

## Consequences

- **heap과 columnar의 NUMERIC 결과가 나눗셈·AVG의 scale/반올림에서 의도적으로 갈린다**(PG `select_div_scale` ≠ CUBRID 규칙). 차등 테스트 판정은 bit-동일이 아니라 수치 동등(나눗셈 계열은 정의된 차이 허용)이다. 이 divergence를 "버그"로 오인해 되돌리지 말 것.
- 기존 columnar 저장 데이터와 비호환 — 어차피 구 포맷은 부호 유실 버그(음수 NUMERIC이 절댓값으로 저장, #23 실증)로 재적재가 불가피했고, 이 재정의가 그 버그를 흡수한다.
- NUMERIC은 고정폭 raw 직렬화에서 빠져 가변폭 스트림이 되고, 비교 커널은 digit-aware가 되며, NUMERIC min/max chunk 스킵이 가능해진다.
