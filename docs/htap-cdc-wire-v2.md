# HTAP CDC wire v2 — 컬럼 값 직렬화 계약 (temporal ISO 송출)

**지위: normative 기준 문서.** workspace#76 결정(D2·D3·D5)의 wire 계약을 byte 단위로 고정한다.
엔진 구현은 workspace#84, 커넥터 구현은 workspace#85가 이 문서를 선행 참조한다. 커넥터
`CubridLogValueDecoder` javadoc은 #85 구현 후 이 문서를 가리킨다. 커넥터 측 타입 매트릭스는
[debezium-connector-cubrid docs/type-support.md](https://github.com/xmilex-git/debezium-connector-cubrid/blob/main/docs/type-support.md)
(상호 링크).

- 기준 코드: 엔진 `2f24ddc0b` `src/transaction/log_manager.c` `cdc_put_value_to_loginfo()`(L14085),
  커넥터 `571713c` `log/LogItemParser.java`·`log/OrReader.java`
- **버전 협상 없음 (#76-D5).** START_SESSION에 version/capability 필드를 추가하지 않는다.
  엔진과 커넥터는 lockstep으로 페어링되는 것이 계약이며, 구엔진(v1)↔신커넥터 조합은 계약 위반이다.
  부수 안전망: v2 파서는 v1의 locale-default 텍스트(AM/PM)에서 요란하게 실패한다(silent 불가).
  protocol manifest는 다음 지도(P1-1) 범위.

## 1. 프레이밍 (v1과 동일 — informative)

값 인코딩 바깥의 항목·컬럼 리스트 구조는 v2에서 변경 없다. 구조 명세의 실체는
`LogItemParser.java`(Java port of `cubrid_log_make_log_item_list`)이며 요지만 기록한다:

- OR packing: `int`는 4바이트 big-endian, `int64`/`double`은 8바이트 정렬 후 big-endian.
  항목(item)은 8바이트(MAX_ALIGNMENT) 정렬로 시작.
- DML 항목: `dml_type(int)` `classoid(int64)` `changed 컬럼 리스트` `cond 컬럼 리스트` `lsa(int64)`.
- 컬럼 리스트: `n(int)`, `n × column_index(int)`, `n × 값`.
- 값 = `pack code(int)` + payload. pack code는 v1과 동일:

| pack code | payload | 사용 타입 |
|---|---|---|
| 0 | int 4B | INT |
| 1 | int64 8B(8-정렬) | BIGINT |
| 2 | float bit-pattern 4B | FLOAT |
| 3 | double bit-pattern 8B(8-정렬) | DOUBLE |
| 4 | short (wire에서는 4B int로 확장) | SMALLINT, ENUM(라벨 소실 시 서수) |
| 5, 8 | 문자열(§2), NULL 불가 | (DDL 경로) |
| 7 | 문자열(§2), NULL 가능 | NUMERIC·CHAR·VARCHAR·ENUM 라벨·BIT·temporal 전종·기타 문자열화 타입 |

- SQL NULL = pack code 7 + 길이 필드 `-1`(payload 없음). `''`와는 길이 필드로만 구별된다(ADR 0003).

## 2. 문자열 payload 계층 (v1과 동일 — normative 기록)

`or_pack_string`/`or_pack_string_with_length`(object_representation.c L1938/L2038) 규약:

- 레이아웃: `길이 필드(int, big-endian)` + `bytes` + `4바이트 경계 패딩`(패딩 값 미정의 — 수신측은 건너뛴다).
  길이 필드는 **패딩 포함** 바이트 수, `-1`은 NULL.
- **charset 미표기 raw bytes.** 문자열 payload는 DB codeset의 원시 바이트 그대로이며 wire에
  charset 태그가 없다. 해석 가능성은 **DB가 UTF-8일 때만** 성립하고, 이는 커넥터 기동 시
  charset guard(UTF-8 아니면 fail-fast, workspace#77 / support-scope §5-12)가 강제한다.
- **CHAR/VARCHAR pack 비대칭:**
  - `VARCHAR`: `or_pack_string(str)` — payload는 `strlen+1` 바이트로 **종단 NUL 포함**.
  - `CHAR(n)`: `or_pack_string_with_length(str, size-1)` — payload는 선언 길이까지 공백 패딩된
    내용 `size` 바이트 그대로, **종단 NUL 미포함**.
  - 수신측(`OrReader.readStringBytes`)은 길이 한도 내 **첫 NUL 이전까지**를 값으로 취하므로 두
    변형을 동일 코드로 읽는다. 따라서 **payload 내 embedded NUL(0x00)은 그 지점에서 절단**된다
    — 송신측도 `strlen` 기반이라 대칭적 한계이며, v2에서 변경하지 않는다(계약상 문자열 값에
    NUL은 표현 불가).

## 3. temporal 송출 계약 (v2 — normative)

### 3.1 렌더 기준 타임존 = UTC

CDC 데몬 전용 세션 타임존 분기(`tz_get_server_tz_region_session`, tz_support.c L4685-4688)는
v1의 `tz_Region_system`(= `server_timezone`) 대신 **UTC region을 반환**한다. 세션 타임존으로
렌더되는 타입(TIMESTAMP, TIMESTAMPLTZ, DATETIMELTZ)의 wall-clock은 따라서 항상 UTC다.
`server_timezone`은 `PRM_USER_CHANGE`가 없어 런타임 변경이 불가하므로 mid-session 변동 경로는
없다(#76-D4).

### 3.2 타입별 텍스트 포맷

전 temporal은 pack code 7 문자열이며, 엔진은 `db_to_char`에 아래 포맷을 **user format으로
유효하게**(v1의 dead 상태 해소 — §5) 적용해 송출한다. 공통 계열:
`YYYY-MM-DD HH24:MI:SS[.FF][ ±TZH:TZM]`.

| CUBRID 타입 | 포맷 문자열 | 렌더 tz | offset 토큰 | 예시(실측 `TO_CHAR`) | 수신측 해석 |
|---|---|---|---|---|---|
| DATE | `YYYY-MM-DD` | — (zone-less) | 없음 | `2026-01-02` | LocalDate |
| TIME | `HH24:MI:SS` | — (zone-less) | 없음 | `15:04:05` | LocalTime |
| TIMESTAMP | `YYYY-MM-DD HH24:MI:SS` | **UTC**(§3.1) | 없음 — **UTC임은 이 계약이 보장** | `2026-01-02 03:04:05` | UTC wall-clock → Instant 복원 → `ZonedTimestamp` |
| DATETIME | `YYYY-MM-DD HH24:MI:SS.FF` | — (zone-less) | 없음 | `2026-01-02 03:04:05.600` | LocalDateTime → offset 없는 ISO 문자열 유지 |
| TIMESTAMPTZ | `YYYY-MM-DD HH24:MI:SS TZH:TZM` | 값 자신의 zone | 있음 | `2026-01-02 03:04:05 +09:00` | OffsetDateTime → `ZonedTimestamp` |
| TIMESTAMPLTZ | `YYYY-MM-DD HH24:MI:SS TZH:TZM` | UTC(§3.1) | 있음(`+00:00`) | `2026-01-02 03:04:05 +00:00` | OffsetDateTime → `ZonedTimestamp` |
| DATETIMETZ | `YYYY-MM-DD HH24:MI:SS.FF TZH:TZM` | 값 자신의 zone | 있음 | `2026-01-02 03:04:05.670 +09:00` | OffsetDateTime → `ZonedTimestamp` |
| DATETIMELTZ | `YYYY-MM-DD HH24:MI:SS.FF TZH:TZM` | UTC(§3.1) | 있음(`+00:00`) | `2026-01-02 03:04:05.670 +00:00` | OffsetDateTime → `ZonedTimestamp` |

byte-exact 규칙 (htapdb 11.5 `TO_CHAR` 실측, 2026-08-19):

- 자리수 고정: 연 4·월 2·일 2·시 2·분 2·초 2, zero-pad. 시는 `HH24`(00–23), AM/PM 없음.
- `.FF` = **밀리초 3자리 고정** zero-pad (`.600`, `.670`, `.000`). DATETIME 계열에만 존재.
  TIMESTAMP 계열·TIME은 초 정밀도라 fraction 없음.
- offset = 리터럴 공백 1 + `±TZH:TZM`: 부호 항상 표기, 시·분 2자리 zero-pad
  (`+09:00`, `-05:00`, `+00:00`). DST 지역의 offset은 해당 instant의 실효 offset.
- 구분자: 날짜 `-`, 시각 `:`, 날짜/시각 사이 공백 1. 다른 공백·접두·접미 없음.

수신측 파서는 **strict**하게 이 문법만 수용한다 — 우회 스위치·관용 파싱 없음. v1 엔진의
locale-default 텍스트(예: `03:04:05 AM 01/02/2026`)는 파싱 실패로 즉시 fail한다(#76-D5 안전망).

### 3.3 TZ 계열 지원 시점

TZ 4종(TIMESTAMPTZ/LTZ, DATETIMETZ/LTZ)의 wire 포맷은 위와 같이 v2에서 함께 고정했고,
커넥터의 unsupported 가드는 workspace#86에서 해제됐다(2026-08-20): 디코더가 `±TZH:TZM`
접미를 파싱해 `OffsetDateTime`→`ZonedTimestamp`로 송출하고, snapshot은 SELECT가 TZ 컬럼을
`TO_CHAR(col, <§3.2 포맷>)`으로 프로젝션해 wire와 동일 문법을 공유한다. 실증:
`htap-poc/e2e/run-tz-types.sh`(snapshot/streaming byte-parity·ClickHouse epoch 일치).

## 4. 비-temporal 타입 (v2 변경 없음)

INT/BIGINT/SMALLINT/FLOAT/DOUBLE(§1 표), NUMERIC(선언 scale 유지 10진 문자열),
CHAR/VARCHAR(§2), ENUM(라벨 문자열), BIT/VARBIT(`X'..'` 리터럴 문자열 — 1.0 미지원),
컬렉션·JSON·LOB(직렬화 불가·미지원)은 v1과 동일하다. 근거·실측은 type-support.md.

## 5. v1과의 차이 요약 (informative)

v1의 `cdc_put_value_to_loginfo`는 위 ISO 포맷 문자열을 **선언만** 하고
`lang_set_flag_from_lang (NULL, false, false, &flag)`(두 번째 인자 `has_user_format=false`)로
플래그를 만들어 `db_to_char`가 포맷 인자를 무시하고 locale default(en_US AM/PM)로 렌더했다
— 리뷰 P0-2가 이 dead code를 오탐한 원인이자, P0-3 wall-clock 이동(#76)의 표면. v2는:

1. dead ISO 포맷 소생(`has_user_format=true` 상당) — DATE/TIME/TIMESTAMP/DATETIME + TZ 4종 전부.
2. LTZ 2종 포맷의 `TZR` → `TZH:TZM` 교체 (아래 D1).
3. CDC 데몬 tz `tz_Region_system` → UTC (§3.1).

## 6. 이 문서의 결정

- **D1. LTZ offset 토큰을 `TZH:TZM`(숫자 offset)으로 통일 — `TZR` 폐기.**
  v1 선언(dead)은 LTZ 2종에 `TZR`(region 이름, 예: `... Asia/Seoul`)이었다.
  이유: ① 파서 단일화 — temporal 전종이 단일 문법 계열이 되고 IANA 이름 사전이 wire 계약에
  들어오지 않는다. ② 소비 계약이 `ZonedTimestamp`(instant)라 region 정체성은 어차피 sink에
  보존되지 않는다. ③ LTZ는 §3.1에 의해 항상 UTC 렌더이므로 offset은 `+00:00` 고정 — 정보
  손실 없음. 비용: wire만 보고 원 zone 이름을 알 수 없다(TZ 2종도 offset만 실림).
  escape hatch: region 이름이 필요해지면 wire v3에서 별도 토큰으로 추가(이 문서 개정).

## 7. conformance

- 엔진(#84): `cdclogdump` 하네스로 temporal corpus 재녹취 — §3.2 예시와 byte 일치 확인.
- 커넥터(#85): wire 픽스처(`cdc-session.hexlog` 등) 전면 재녹취, strict 파서 + v1 텍스트
  거부 테스트, `SET TIME ZONE 'UTC'` 세션 자가 고정, 비UTC JVM(Asia/Seoul) matrix.
- e2e: TIMESTAMP/DATETIME 동일 표시값 차등, snapshot/streaming parity (#76-D6).
