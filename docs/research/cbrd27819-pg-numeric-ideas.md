# PostgreSQL numeric.c 의 알고리즘 아이디어 중 이진 NUMERIC 위에서 쓸 수 있는 것

CBRD-27819 지도 workspace#562 / 연구 workspace#564. 작성 2026-10-30. 후속 구현 티켓은 #570 이다.

## 0. 규약과 읽은 소스

- **고정한 소스.** PostgreSQL master `b0392c26bd3cfb61ee24b7577967cc806d01da36`(2026-10-30), 파일은 `src/backend/utils/adt/numeric.c`(12230줄) 하나. CUBRID 는 develop `a199916d400c22b5cfcfd5b899796dc70f9b974d`(2026-10-30).
- **develop 워크트리가 뒤처져 있다.** `~/dev/cubrid-worktree/develop` 는 `5b1867174`(2026-10-15)에 멈춰 있어 CBRD-27215(`b8199438e`, 식을 단계 프로그램으로 컴파일)와 CBRD-27381(`5cd1de888`)이 빠져 있다. `float_numeric_db_value_mul_fixed64` 도 그 색인에는 없다(code-index `definition` 이 "no definition" 으로 답했다). 그래서 이 문서의 CUBRID `file:line` 은 전부 `a199916d4` 를 `git archive` 로 scratch 에 풀어(읽기 전용) 읽은 줄 번호다. code-index 는 워크트리 색인이라 callers 교차 확인에만 썼다(`numeric_db_value_compare` 호출처는 `mr_data_cmpdisk_numeric`, `mr_cmpval_numeric` 두 곳이 핫 경로).
- **표기.** 아래 표와 본문의 CUBRID 줄 번호는 `a199916d4`, PG 줄 번호는 `b0392c26bd3` 기준이다. 해시를 줄마다 반복하지 않는다.
- **ADR 0036.** PG 는 읽고 이해만 했다. 이 문서에 든 PG 코드는 두 줄 이하 인용뿐이고 줄 번호를 붙였다. 실행·측정용 대조 기준으로 쓰는 것은 허용되지만 이 티켓에서는 실행하지 않았다.
- **범위 밖.** 10000진 저장 표현 교체는 제안하지 않는다(#562 Out of scope).
- **측정 없음.** 이 문서의 모든 속도 수치에는 **(추정)** 을 붙였다. 명령 수 계산과 코드 읽기로 낸 값이고 측정이 아니다. 유일하게 실행한 것은 gcc 8.5 `-O2` 코드젠 확인 한 건이다(부록 B). 엔진 빌드, CTP, 서버, 단위 테스트는 하지 않았다.
- **용어.** PG 의 `weight`·`dscale`·`NBASE` 와 CUBRID 의 `precision`·`scale`·계수(coefficient) 는 같지 않다. 대응표는 1.2 에 있다.

## 1. 결론 (먼저)

1. **CUBRID 의 질의 경로 산술은 PG 의 핵심 가속 세 가지를 이미 이진 표현 위에서 구현했다.**
   - 지연 반올림·지연 자릿수 계산 누산기(`SUM_ACC`, CBRD-27178 `7749f4ff8`, `numeric_opfunc.c:4297-4429`, `4706-4746`). PG 의 `NumericSumAccum`(carry 지연, `numeric.c:11947-12054`)과 같은 노림이다.
   - 64/128비트 고속 경로(`float_numeric_*_fast`, `mul_fixed64`, 나눗셈 `div_fast`; scale 조정의 128비트 나눗셈 축소와 출력 고속 경로는 CBRD-27150 `c1332583d`).
   - {+,-,*} 식 트리를 DB_VALUE 없이 `uint128` 계수로 평가(`numeric_agg_expr_*`, `4503-4691`).
   - PG 의 NUMERIC 산술은 digit 배열 위에서 돈다. 이진 정수 경로는 정수 입력 집계의 `Int128AggState`(`numeric.c:5506-5513`)와 `div_var_int64` 의 128비트 carry(`9702-9709`), 자릿수 6개 이하 곱 `mul_var_short`(`8682-8947`) 정도뿐이다.
2. **PG 의 속도는 대부분 10000진 표현에서 나온다.** 자릿수 그룹이 위치(weight)에 박혀 있어 scale 정렬은 인덱스 어긋남이고, 값이 앞뒤 0 없이 정규화돼 있어 비교는 weight 먼저, 반올림은 자리 절단이다. 이진 표현에서는 이 셋이 오히려 10^k 곱셈·나눗셈이 되므로 **옮겨지지 않는다.** 옮겨지지 않는 것: NBASE² 쌍 곱셈, 양/음 분리 누산기, 부동소수 역수 몫 추정(64비트 digit 에는 53비트 double 이 모자란다), approximate 나눗셈의 guard digit.
3. **옮길 가치가 남은 것은 아래 다섯이다(상세는 3장, 순위는 6장).**
   - (A) NUMERIC 비교 단축 — scale 이 같으면 precision 을 무시하고 계수를 바로 비교, scale 이 다르면 `u64×10^k→u128`. 같은 아이디어를 정렬·B-tree 키 비교(`mr_data_cmpdisk_numeric`)에 DB_VALUE 없이 적용. PG 의 `cmp_var_common`(weight 먼저)과 `numeric_fast_cmp`(포장된 값에서 바로 비교)에 해당한다.
   - (B) 자릿수(precision) 계산 단축과 add/sub 의 64비트 특수화(`mul_fixed64` 와 같은 모양). 값은 그대로 두고 계산만 싸게 한다.
   - (C) ROUND/TRUNC/FLOOR/CEIL 의 NUMERIC 가지가 십진 문자열을 거치는 것을 이진 10^k 나눗셈으로 교체, 문자열 출력의 256자 패딩 제거. PG 의 `round_var`/`get_str_from_var` 가 "필요한 자리만" 만지는 것에 대응한다.
   - (D) 나눗셈: 선행 0 워드 몫 생략과 128/64 나눗셈의 libgcc 호출 제거.
   - (E) 곱셈 고속 경로 조건을 선언 precision 이 아니라 실제 계수 크기로(결과 동일).
4. **TPC-H SF10 에는 거의 효과가 없다.** 이유는 산술이 이미 word 도메인이고 22개 질의에서 NUMERIC 비교·문자열·반올림·나눗셈을 행 단위로 많이 치는 질의가 없기 때문이다. 질의별 추정은 4장: Q1 은 0~1%(상한 3%), Q6 은 1% 이하, Q18 이 1~3% 정도로 가장 크다. 어떤 질의도 느려지지 않는다.
5. **#570 에 대한 함의.** (A)와 (B)가 ≥1.3× 기준을 넘길 가능성이 높고, 이 둘은 NUMERIC×DOUBLE 비교(#563, #567)와 같은 "지수 먼저" 도우미를 공유할 수 있다. (C)(D)(E)는 1.3× 를 넘겠지만 TPC-H 와 무관해 이 PR 의 표면을 넓힌다. 6장과 7장에서 리드가 정할 것을 묻는다.

### 1.1 산술이 이미 어디까지 와 있는가 (요지)

| 항목 | 현행 상태 | 출처 |
|---|---|---|
| 질의 경로 산술 | `float_numeric_db_value_*` (워드 기반, 정밀도는 실제 자릿수로 다시 계산) | `numeric_opfunc.c:2544`, `2820`, `3045`, `3430`; 호출처 `query_opfunc.c:4555-4595`, `type_checking.c:14439,15115,15518,15635`, `expr_compile.c:577-578,585,612` |
| 구형 고정 NUMERIC 산술 | `numeric_db_value_*` (17바이트 바이트 단위 루프, 나눗셈은 비트 단위 시프트-뺄셈 `1300-1310`). 호출처는 serial·DDL·log applier 뿐이다. | `numeric_opfunc.c:2423`, `2976`, `3269`, `1267`; `serial.c:1389-1472`, `execute_statement.c:379-402`, `log_applier_sql_log.c:413` |
| SUM/AVG | 계수 3워드 `SUM_ACC`, 반올림은 그룹당 1회 | `query_sum_accumulator.h:60-80`, `numeric_opfunc.c:4297-4429` |
| SUM/AVG 안의 {+,-,*} 식 | `uint128` 계수로 평가해 DB_VALUE 없이 누산 | `query_aggregate.cpp:153-219`, `1425-1440`, `numeric_opfunc.c:4503-4691` |
| 비교 | scale·precision 이 모두 같을 때만 17바이트 memcmp, 아니면 워드 정렬 후 비교 | `numeric_opfunc.c:3651-3714`, `1994-2040` |

### 1.2 용어 대응 (PG 와 CUBRID)

| PG | CUBRID | 의미 차이 |
|---|---|---|
| `NumericVar.digits[]`: 십진 네 자리씩 담은 int16 배열, NBASE=10000 (`numeric.c:97-100`, `314-322`) | 17바이트 빅엔디언 이진 계수(`DB_VALUE` 의 `data.num.d.buf`)와 부호(`is_value_negative`). 이진 정수의 부호-크기 표현 | CUBRID 는 계수 하나가 이진 정수다 |
| `weight`: 자릿수 그룹 단위 지수 | 없음. 지수는 `자릿수 - scale` 로 유도한다(`float_numeric_normalize_for_sort` 의 반환값, `numeric_opfunc.c:4231`) | 비교가 weight 로 먼저 갈리지 않는다 |
| `dscale`: 표시용 소수 자릿수. 계수와 독립 | `scale`: 계수 안의 소수점 위치(−214..252, `DB_MIN/MAX_NUMERIC_SCALE`) | 계수가 scale 에 묶여 있어 덧셈·비교에 정렬(10^k 곱)이 필요하다 |
| 없음(ndigits 가 값에서 정해진다) | `precision`. fixed NUMERIC(p,s) 는 선언 값, 산술 결과인 floating NUMERIC(40) 은 DB_VALUE 헤더에 **실제 자릿수**(`dbtype_function.i:1641-1657`, 최대 `DB_MAX_NUMERIC_PRECISION`=40) | precision 이 관찰된다(해시·디스크 크기 등급, 표 13행) |
| `strip_var`: 앞뒤 0 digit 제거로 값이 정규형(`11890-11916`) | 없음. 0 꼬리를 지우지 않는다(해시 때만 정규화, 표 14행) | 같은 값이 여러 표현을 갖는다 |

## 2. 연산별 표

표의 "이전" 칸은 이 질문에 대한 답이다: **PG 의 아이디어가 이진 표현 위에서 성립하는가** (yes / partly / no). "기대" 칸의 수치는 모두 추정이고 하네스(5장)가 확인할 항목이다. CUBRID 칸은 `a199916d4`, PG 칸은 `b0392c26bd3`.

| # | 연산 | CUBRID 현행 | PG 방식 | 이전 | 기대 효과와 근거 | TPC-H 에서 치는 질의 |
|---|---|---|---|---|---|---|
| 1 | 덧셈·뺄셈 (계수 < 2^64) | `float_numeric_db_value_add/sub` `2544-2679`, `2820-2955`. 순서: 인자 검사 → `calc_words` 결정(`2589-2591`, 표 `154-181`) → VLA 3개 memset(`2594-2599`) → `bytes_to_words` 2회(`6458`) → scale 정렬 `mul_normalize`(`6008`) → 상위 2워드가 0 이면 고속(`2614-2627`, `add_fast` `974-1000`: `_addcarry_u64` 1회) → `words_to_bytes` → 자릿수 계산(`609-656`) → `db_make_numeric`. 식 커널은 reference 를 그대로 부른다(`expr_compile.c:577-578`). agg-expr 는 이 경로를 안 탄다(`4617-4669`). | `numeric_add_safe` `2886-2935` → `init_var_from_num`(복사 없음) → `add_var` `8153` → `add_abs` `11555-11627`(자리 루프, `digitbuf_alloc` `11589`) → `make_result`(palloc). 부호가 다르면 `cmp_abs` + `sub_abs`. | partly | 현행 ≈100~140 cycles(추정). PG 가 주는 것(복사 없이 직접 읽기, 부호·크기 선결정)은 이미 있다. 남은 낭비는 CUBRID 고유: VLA memset, 2회 변환, 자릿수 재계산. `mul_fixed64`(`3191-3248`)와 같은 모양의 add/sub 64비트 특수화 + u64/u128 전용 자릿수 계산이면 ≈55~75 cycles → **1.5~2×(추정)**. 결과 동일 조건은 "precision = 정확한 자릿수". | Q1·Q6 은 SUM 이라 이 경로를 안 탄다. CASE 안의 산술(Q8, Q12, Q14: 대상 행이 적다)과 상수 접기뿐이라 ≈0 |
| 2 | scale 정렬 (10^k 곱) | per-row 경로: `float_numeric_mul_normalize` `6008-6026`, 19자리씩 `pow10` u64 표(`184-189`)를 3워드 루프로 곱함(`5965-5982`). agg-expr: `uint128` 표 한 칸 곱(`4633-4636`, 표 `127-131`, `544-555`). 구형 고정 NUMERIC: 17바이트 ×10 을 scale 차이만큼 반복(`2051-2077`, `2113-2132`). | 정렬 자체가 없다. weight 로 자릿수 그룹 위치가 정해져 `add_abs` 가 인덱스만 어긋나게 읽는다(`11593-11602`). dscale 은 표시용이고 `max` 만 취한다(`11578`). | no(표현 의존). 단 "정렬 = 곱셈 1회" 는 agg-expr 가 이미 구현. per-row 경로는 partly. | 계수가 u64 이고 차이가 19 이하이면 `(u128)c*pow10[k]` 1회로 가능: 3워드 루프 18~25 → 4~6 cycles. 연산 전체의 10~15% 라 **단독 1.1× 대 → 후보 아님**, (1)·(8)에 묶는다. | Q1 의 `1 - l_discount`(scale 0→2)는 agg-expr 에서 이미 u128. ≈0 |
| 3 | 곱셈 | `float_numeric_db_value_mul` `3045-3173`: 고속(`3117-3127`, `mul_fast` `1226-1250` = u64×u64→u128 1회). 식 커널은 `mul_fixed64`(`3191-3248`: 두 계수가 단일 워드이고 `prec1+prec2 ≤ 55` 일 때만, 조건은 `3235-3238`). 일반 경로는 3워드 학교식(`float_numeric_mul` `1167-1209`). agg-expr: `numeric_agg_expr_mul` `4581-4605`(`__builtin_mul_overflow` u128). | `mul_var` `8391-8671`: NBASE² 쌍, 64비트 누산기, carry 지연, 짧은 쪽을 바깥 루프. 정확한 결과를 요청하고 짧은 쪽이 6자리 이하면 `mul_var_short` `8682-8947`(분기 `8453`). | partly (대부분 이미 구현) | `mul_var_short` 의 "작은 피연산자는 단일 패스 직접 곱" 은 이진에서 `mul` 1회라 이미 더 낫다. NBASE² 쌍·carry 지연은 3워드 이하에서 불필요. **개선 여지는 `3235` 의 선언 precision 조건**: 두 계수가 2^64 미만이면 128비트 곱이 정확하고 자릿수가 40 을 넘지 않으므로(< 2^128 ≈ 3.4e38) 선언 precision 과 무관하게 고속 경로로 충분하다. 현재는 `NUMERIC(38,s)` 열 둘의 곱이 값이 작아도 5워드 학교식 + 자릿수 > 40 이면 `round_and_pack`(`6231-6276`)으로 간다. 그 절벽은 **5× 이상(추정)**. | TPC-H 열은 전부 NUMERIC(15,2) 라 0 |
| 4 | 곱셈 결과 scale·반올림 | scale = s1+s2, 252 초과 시에만 `div_normalize` + 반올림(`1235-1245`, `3136-3145`). 정밀도 40 초과 시 scale 을 낮추고 `round_and_pack`(`6192-6276`). | rscale = dscale1+dscale2 를 정확히 요청(`3123`), `NUMERIC_DSCALE_MAX` 초과 시에만 `round_var`(`3125-3126`). | no (같은 의미) | 두 쪽 모두 정상 범위에서 곱셈 뒤에 나눗셈·반올림 단계가 없다. 차이는 CUBRID 의 40자리 한계뿐이라 결과가 41자리 이상일 때만 10^k 나눗셈이 생긴다. | TPC-H 에서 발생하지 않음 |
| 5 | 나눗셈, 두 계수 자릿수 ≤19 | `3430-3513`: 자릿수 계산(`3491-3492`) → `div_fast` `1417-1504`: 피제수를 10^exponent10 으로 확대해 4워드(`1466-1468`), **4워드 모두** uint128/uint64 짧은 나눗셈(`1477-1482`), 반올림(`1485-1488`). 몫은 40유효숫자를 목표(`1456`, `3523`). gcc 8.5 `-O2` 는 이 128/64 를 인라인 `divq` 가 아니라 `__udivmodti4` 호출로 낸다(부록 B). | `div_var` `8969`: 제수 ≤2자리(≤8 십진)는 `div_var_int` `9510`, ≤4자리(≤16 십진)는 `div_var_int64` `9626`(`9012`, `9031` 분기). 몫 자리 수는 weight 차 + rscale/4 + 1 만큼만 루프(`9548`, `9664`). 유효숫자 ≥16 (`select_div_scale` `9738-9798`). | partly | (i) "몫 자리 수를 먼저 정하고 그만큼만 루프" 는 이진에서도 성립한다. 현행은 4워드 중 선행 두 워드의 몫이 0 인데도 4회 호출한다. (ii) `div_var_int64` 의 "carry 가 64비트에 들어가면 128비트 생략" 은 밑이 2^64 인 이진에는 해당 없음(항상 128/64). (i)+(인라인 divq 또는 역수곱)으로 **2~3×(추정; Cascade Lake 의 `div r64` 35~90 cycles 가정)**. CUBRID 몫은 40유효숫자, PG 는 ≥16 유효숫자라 같은 알고리즘이어도 CUBRID 가 몫 자리를 2.5배 만든다. 그건 사양이므로 건드리지 않는다. | Q1 의 avg(그룹 4개), Q14·Q17·Q8 의 최종 나눗셈 1회. ≈0 |
| 6 | 나눗셈, 한쪽 ≥20자리 | 비교(`3519`) + 큰 확대 + Knuth 64비트 digit(`1825-1919`): 몫 digit 추정이 `uint128/uint64`(`1676-`)라 digit 마다 libgcc 호출. | `div_var` 의 NBASE² 쌍 + 부동소수 역수 몫 추정(`9182-9185`, `9215-9221`) + carry 지연 + 나머지 보정(`9344-9451`). | partly / no | 부동소수 추정은 double 53비트라 64비트 digit 에 안 맞는다. 32비트 digit 으로 바꿔야 한다(`knuth_digit_t` 는 현재 `uint64_t` 로 고정, `numeric_opfunc.h:85-89`. 코드 주석 `1579`, `1599` 는 32/64비트를 모두 상정한다). 이 경로 자체가 드물다. **≤1.5×(추정), 우선순위 낮음.** | 0 |
| 7 | 반올림·절단 (10^k) | 내부 helper: `float_numeric_div_normalize` `6078-6104`, 19자리씩 `uint128/variable uint64`, 워드마다 `__udivti3` 호출(부록 B). `numeric_coerce_num_to_num` `5830-5933`. **SQL 함수 ROUND/TRUNC/FLOOR/CEIL 의 NUMERIC 가지는 십진 문자열을 거친다**: `arithmetic.c:96`(floor), `265`(ceil), `2350`(round), `3362`(trunc); 512바이트 버퍼 memset + `numeric_coerce_num_to_dec_str`(256자 0채움) + 문자 조작 + `numeric_coerce_dec_str_to_num`(`159`, `327`, `2520`, `3559`). | `round_var` `11722-11818`: 남길 자리 수 `di` 계산(`11732`) → ndigits 를 줄이고 마지막 자릿수 그룹 하나에서만 나머지 연산(`11776`). `trunc_var` `11828-11882`. 자릿수 수에 무관(O(1)). | partly | "자리 절단이 O(1)" 은 표현 의존이라 no. 이진에서의 대응은 (i) SQL 함수가 문자열 대신 이미 있는 이진 10^k 나눗셈 helper 를 쓰게 하는 것, (ii) 10^k(k≤19) 나눗셈을 정수 역수곱으로 바꾸는 것(Möller·Granlund 2011, "Improved division by invariant integers" — 문헌, PG 아님). (i) **5~20×(추정)**, (ii) div_pow10 단독 3~6×(추정). | 22개 질의에 ROUND/TRUNC 없음: 0 |
| 8 | 비교 (NUMERIC×NUMERIC, DB_VALUE) | `numeric_db_value_compare` `3651-3714`: 부호가 다르면 즉시(`3683-3686`), prec 와 scale 이 **모두** 같으면 17바이트 memcmp(`3687-3696`, `6136`), 아니면 `float_numeric_compare` `1994-2040`(common scale/prec 계산 → VLA 2개 memset → `bytes_to_words` 2회 → `mul_normalize` → 워드 비교). **scale 이 같고 precision 만 다른 경우도 느린 경로**를 탄다. 결과는 `db_make_int(answer)` 로 DB_VALUE 에 썼다가 호출자(`mr_cmpval_numeric` `8885-8913`)가 다시 읽는다. | `cmp_var_common` `8110-8143`: 0 먼저, 부호, 그다음 `cmp_abs_common` `11491-11545`: **weight 가 다르면 자릿수를 안 보고 결정**, 같을 때만 자릿수 비교. 포장된 값에서 바로 비교(`cmp_numerics` `2525-2576`). 스케일 정렬·복사 없음. | yes (partly) | 같은 부호·같은 scale 이면 precision 과 무관하게 계수 대소 = 값 대소. scale 이 다르면 계수가 모두 u64 이고 차이 ≤19 일 때 `u128` 정렬 곱 1회, 그 밖에는 비트 길이로 선판정(`bits(c1)-1 + k·log2(10) ≥ bits(c2)` 이면 곱 없이 결정). 비교 본체 55~80 → 8~15 cycles. 진입·반환 포함 **2~3×(추정)**, answer 를 DB_VALUE 로 거치지 않으면 더 크다. | Q6(`l_discount between .06 - 0.01 and .06 + 0.01`: 상수 접힘이 floating NUMERIC prec 1 을 만들어 열 prec 15 와 다를 가능성, scale 은 같음 → **V7 로 확인**), Q18 `having sum(...) > 300`, Q22 `c_acctbal > 0.00`, Q2·Q15 의 동등 비교. 행당 횟수가 선행 술어로 줄어 효과 ≤1% |
| 9 | 비교 (정렬·B-tree 키, 디스크 바이트) | `mr_data_cmpdisk_numeric` `8849-8882`: 두 값을 `mr_data_readval_numeric`(`8763-8824`: 헤더 3바이트 파싱·경계 검사 → `db_make_numeric` = `db_value_domain_init` + 크기별 switch + memset + memcpy)로 DB_VALUE 2개 만든 뒤 `numeric_db_value_compare` + `db_make_int`. 호출처: 정렬 키 `list_file.c:4306,4364,4419,4465`, B-tree `index_cmpdisk`. | 포장된 datum 에서 바로 비교(`numeric_fast_cmp` `2286`), 정렬 지원에서 64비트 abbreviated key 로 대부분을 정수 비교 한 번에 끝냄(`numeric_abbrev_convert_var` `2367-2411`). | yes (partly) | DB_VALUE 없이 헤더(부호, precision, scale)와 가변 길이 계수를 직접 읽어 `u128`+상위 1바이트로 비교. 현행 ≈120~165 cycles, 직접 ≈30~40 → **3.5~5×(추정)**. 인덱스 빌드용 정규화 키는 이미 있다(`float_numeric_normalize_for_sort` `4208`, `btree_sort_radix.cpp:995`). **함정:** 디스크 크기 등급은 fixed NUMERIC 은 값에서, float NUMERIC 은 precision 에서 정해지므로(`object_primitive.c:130-139`, `8394-8398`) 크기만으로 대소를 정할 수 없다. float 쪽은 상위 바이트 0 검사가 필요하다. | ORDER BY 에 NUMERIC 이 든 Q2, Q3, Q10, Q11, Q15, Q18. 모두 LIMIT 이거나 결과가 작아 ≤1~2% |
| 10 | 문자열 출력 (NUMERIC→text) | `numeric_db_value_print` `7120-7223` → `numeric_coerce_num_to_dec_str` `4009-4099`(256자 `'0'` 채움 `4027-4028`, 64비트면 `4047-4066`, 아니면 16자리 청크 3회, `numeric_pack_digits4_ascii` `6369-6393` 의 4자리 LUT `125`) 다음 **출력 루프가 256자(+부호) 전부를 훑는다**(`7146-7195`). CAS 는 `db_value_coerce` NUMERIC→VARCHAR 경유 + `db_private_alloc` 1회(`object_domain_convert.cpp:3130-3160`, `cas_execute.c:4840`). csql 은 `csql_result_format.c:930`. | `get_str_from_var` `7317-`: 출력 길이를 weight/dscale 에서 계산해 `palloc` 1회(`7345`), 자릿수 그룹마다 상수 나눗셈 3회로 4문자를 만들고 선행 0 억제. | partly | 4자리 단위 생성은 CUBRID 의 LUT 가 PG 보다 낫다. 바꿀 것은 **패딩**: precision/scale 에서 길이를 알고 오른쪽부터 필요한 자리만 쓰면 256회 반복(≈700~1000 cycles 추정)이 사라진다. **3~8×(추정).** | 결과 행이 작아 0 (대량 NUMERIC 전송에는 큼, TPC-H 밖) |
| 11 | 문자열 입력 (text→NUMERIC) | `numeric_coerce_string_to_num_status` `5757-5814`: `analyze_numeric_string` `5237-5450`(문자를 정수/소수 배열 2개로) → `determine_prec_scale` `5468`(`num_string` 복사) → `numeric_coerce_dec_str_to_num` `3914-3988`(`strlen` + 18자리 이하 곱-더하기, 아니면 16자리 청크). loaddb 는 `3914` 를 직접(`load_db_value_converter.cpp:342,934`, `load_sa_loader.cpp:2461,2541`). | `set_var_from_str` `6835-7031`: 한 번 훑어 digit 배열(palloc) + weight/dscale 확정, 4자리씩 묶기(`6999-7000`), 지수 처리. | partly | PG 도 문자당 곱-더하기 사슬이라 더 빠르지 않다. 3패스·배열 2개·복사를 단일 패스 누산(≤19자리는 u64 하나)으로 줄이는 것은 이진의 자연스러운 대응이지만 PG 고유 아이디어는 아니다. **1.5~2.5×(추정).** | 적재(loaddb)뿐, 재적재 없음: 0 |
| 12 | SUM/AVG 누산 | `SUM_ACC`(`query_sum_accumulator.h:60-80`): 부호-크기 3워드, 반올림·자릿수·오버플로 검사를 finalize 로 미룸(`numeric_opfunc.c:4297-4320`, `4373-4429`, `4706-4746`). 식 트리는 u128 로 평가해 DB_VALUE 없이 누산(`query_aggregate.cpp:153-219`, `1425-1440`). 행당 DB_VALUE 출력 없음. | `NumericSumAccum`: 양수 합과 음수 합을 따로, 자릿수별 int32 슬롯, NBASE-1 번 더한 뒤 carry 일괄 전파(`11947-12054`, `11960`). `do_numeric_accum` `4828-4880`. 정수는 `Int128AggState`(`5506-5513`). | 이미 구현 (지연 반올림 = 지연 carry 의 이진판) | 추가 이득 ≈0. 양/음 분리는 192비트 `adc` 한 번보다 느리다. 행당 남은 비용은 leaf 의 DB_VALUE 디코드와 트리 순회로 PG 와 무관하다. | Q1(행당 누산 7개), Q6, Q18 |
| 13 | 자릿수(precision) 계산 | `float_numeric_get_decimal_digit` `609-656`: 선행 0 워드 탐색 + clz 추정 + `powers_of_10` 표(27워드 행)와의 3워드 비교 반복. 연산마다 호출(`999`, `1249`, `3579`, `4720`). agg-expr 는 `numeric_digits_u128` `4470-4482` 를 finalize 에서만. | 없음. ndigits/weight 가 값과 함께 저장되고 dscale 은 별도(`NumericVar` `314-322`). | partly | **계산을 없앨 수는 없다.** precision 이 관찰된다: `memory_hash.c:606-633`(float NUMERIC 해시 정규화 분기), 디스크 크기 등급 `object_primitive.c:130-134`, `numeric_coerce_num_to_num` 의 조기 오버플로 판정 `5866-5879`. 값은 같게 두고 계산만 싸게(u64/u128 전용: 비트 길이 → LUT → 비교 1회). 연산당 15~25 cycles 절감(추정) → 단독 1.15~1.25× 로 **기준 미달**, 1번에 묶는다. | Q18 그룹 15M 개의 finalize(`snapshot` `4706`)에서 1~3% |
| 14 | 해시 정규화 (float NUMERIC 0 꼬리) | `float_numeric_normalize_for_hash` `4117-4193`: 10^19/10^8/10^4/10^2/10 단계 나눗셈 시도(워드마다 `uint128` 나눗셈). 호출처 `memory_hash.c:628,2443`, `btree.c:7536`. | `hash_numeric` `2717-2796`: 자릿수 배열이 이미 앞뒤 0 제거 형태라 정규화 불필요(`strip_var` `11890-11916`). | partly | 나눗셈 없이 "10^t 로 나눠떨어지는가"를 판정(2^t 는 ctz, 5^t 는 곱셈 역원 판정 — Granlund·Montgomery 1994 "Division by invariant integers using multiplication", 문헌). 단독 ≥1.3× 가능성은 있으나 TPC-H 에 NUMERIC 해시 키가 없다. 우선순위 낮음. | 0 |
| 15 | 할당 | 산술 경로 힙 할당 없음(VLA ≤27워드, DB_VALUE 안의 17바이트 인라인 버퍼). 할당은 NUMERIC→문자열 변환(`object_domain_convert.cpp:3144`)과 ROUND 계열의 512바이트 스택 memset 정도. | 연산마다 digit 버퍼 palloc(`478-481`; `add_abs` `11589`, `mul_var` `8552`, `div_var` `9145`) + `make_result` palloc → 연산당 2회 이상. | no (PG 쪽이 불리) | 옮길 것 없음. | - |

## 3. 티켓이 지정한 후보 (a)~(g) 에 대한 직접 답

### (a) 나눗셈 — PG 학교식(10000진)과 현행, uint128 경로의 범위

- **현행.** 두 계수가 모두 ≤19자리면 `div_fast`(`1417-1504`): 피제수를 10^exponent10 으로 확대해 4워드로 만들고 uint128/uint64 로 워드마다 나눈다. 그 밖에는 Knuth 64비트 digit(`1825-1919`). 결과는 항상 40유효숫자를 목표로 한다(`1456`, `3523`).
- **PG.** 제수 자릿수 ≤2 면 32비트 짧은 나눗셈, ≤4 면 64비트 짧은 나눗셈, 그 이상은 NBASE² 쌍 학교식(몫 digit 은 부동소수 역수 추정 후 보정). 몫 자리는 필요한 수만(`9548`, `9664`).
- **옮겨지는 것.** 몫 길이를 지수에서 먼저 정하고 그 길이만 루프(현행은 4워드 고정). 128/64 나눗셈 한 번에서 몫과 나머지를 같이 얻기(GCC 8.5 는 `/` 와 `%` 를 `__udivmodti4` 한 번으로 합치지만 호출이다).
- **옮겨지지 않는 것.** 부동소수 역수 추정(밑 2^64 에서는 53비트로 부족), pair 학교식.
- **uint128 경로가 NUMERIC(15,2)×NUMERIC(15,2) 를 덮는가.** 덮는다. 계수 < 10^15 < 2^50 이라 `mul_fixed64`(`3191-3248`), `mul` 고속(`3117`), agg-expr(`4581`) 모두 곱이 10^30 미만(< 2^100)에서 끝난다. 이탈 경계는 아래 표:

| 경로 | 고속 조건 | 이탈 경계 |
|---|---|---|
| `mul_fixed64` (식 커널) `3191-3248` | 두 계수 < 2^64(19자리는 보장, 20자리는 1.8e19 이하만) **그리고** `prec1+prec2 ≤ 55`(`3235`: `lookup[prec]+1 ≤ 24`, 표 `154-181`) | 계수 ≥ 2^64, 또는 `prec1+prec2 ≥ 56`(예: NUMERIC(28,·)×NUMERIC(28,·), NUMERIC(38,·)×NUMERIC(38,·)=76). precision 은 열 값이면 **선언값**, 연산 결과면 실제 자릿수 |
| `mul` 고속 `3117-3127` | `calc_words == 3`(위와 같은 `prec1+prec2 ≤ 55`) 그리고 두 계수 < 2^64 | 같음. 이후 3~5워드 학교식(`1167-1209`)과, 자릿수 > 40 이면 `round_and_pack` |
| agg-expr `4581`, `4617` | 피연산자 계수 < 2^128(상위 바이트 0, `4515`), 곱·합이 u128 안(`__builtin_mul_overflow`), scale ≤ 252 | 곱 ≥ 3.4e38(39자리 이상)이면 그 행만 legacy DB_VALUE 경로(행마다 다시 시도할 수 있다, `query_aggregate.cpp:1425-1440`). 이탈은 **실제 값** 기준이라 NUMERIC(15,2) 세 개 곱의 선언 상한 45자리는 TPC-H 값(< 2^64)에서는 닿지 않는다 |
| add/sub 고속 `2614`, `2891` | `calc_words == 3`(`result_prec ≤ 55`) 그리고 scale 정렬 뒤 두 값 < 2^64 | 정렬 곱셈 뒤 ≥ 2^64(19자리 값을 10^k 확대 등) 또는 `result_prec ≥ 56` |
| `div_fast` `3503` | 두 계수의 **실제 자릿수** ≤ 19 | 한쪽이 ≥ 20자리 → Knuth. 예: Q1 `sum_charge`(scale 6)의 계수는 SF10 에서 약 1e17~1e18(18~19자리 이하)이고 스케일 팩터가 100 안팎부터 20자리에 닿는다(추정) |

### (b) 곱셈 결과 scale 처리 — 나눗셈·반올림 단계를 강제하는가

강제하지 않는다. scale = s1+s2 이고 252 를 넘을 때만 `div_normalize` + 반올림이다(`1235-1245`). PG 도 정확한 결과를 요청한다(`3123`). 현행에만 있는 추가 단계는 (i) 매번의 자릿수 계산(표 13행), (ii) 결과가 40자리를 넘는 경우의 `round_and_pack`(표 4행)이다. (ii)는 TPC-H 에서 발생하지 않는다.

### (c) 10^k 반올림·절단 — 표 7행

PG 의 O(1) 은 옮겨지지 않는다. 대응은 (i) 문자열 경유 제거, (ii) 10^k 나눗셈의 역수곱이다. SQL 함수 ROUND/TRUNC/FLOOR/CEIL 이 NUMERIC 에서 문자열을 거친다는 점이 가장 큰 발견이다. (i)은 비슷한 이진 helper(`numeric_coerce_num_to_num` `5830-5933`, `float_numeric_div_normalize` `6078-6104`)가 이미 있어 새 알고리즘은 필요 없다. 결과 동일성(특히 ROUND 의 음수 자릿수 인자와 precision 규칙)은 V6 이 확인한다.

### (d) 십진 문자열 입출력 — 표 10·11행

- **PG.** 입력은 한 패스로 digit 배열과 weight 를 정하고 4자리씩 묶는다. 출력은 길이를 먼저 계산해 palloc 한 번.
- **현행의 비싼 곳.** 출력은 256자 패딩과 256자 순회, 입력은 3패스와 중간 배열 2개다. 4자리 LUT 생성(`6369-6393`)은 PG 보다 낫다.
- **TPC-H 경로에서의 위치.** 질의 실행에는 거의 없다(결과 행이 작다). 있는 곳은 loaddb(`load_db_value_converter.cpp:342,934` 등), csql 출력(`csql_result_format.c:930`), CAS 가 NUMERIC 을 문자열로 보내는 경로(`cas_execute.c:4840` → `object_domain_convert.cpp:3130-3160`), SQL 함수 ROUND 계열(`arithmetic.c`), 정수 변환 strict 의 `numeric_is_fraction_part_zero`(`4809-4830`)다.

### (e) 비교 단축 — 표 8·9행

PG 의 weight 먼저 비교는 이진에서는 "scale 같으면 precision 무시"와 "비트 길이 선판정"으로 바뀐다. 부호 선판정은 이미 있다(`3683`). 가장 효과가 큰 것은 scale 이 같고 precision 만 다른 경우를 빠른 경로로 보내는 것이다. 예: 열(15,2)과 상수 접힘 결과(prec 1, scale 2). 이 경우의 실제 발생 여부는 V7 로 확인한다.

### (f) SUM/AVG 누산 — 표 12행

PG 는 NumericSumAccum 으로 carry 를 늦춘다. CUBRID 는 같은 목적을 더 싼 이진 방식으로 이미 달성했다(반올림·자릿수 지연, 식 트리 u128). **행당 누산 비용(Q1 기준).**

- 입력: leaf 는 이미 디코드된 DB_VALUE(`numeric_agg_expr_from_dbv` `4504` 가 `bytes_to_words` 로 변환). 출력: DB_VALUE 없음. `numeric_sum_acc_add_core`(`4373-4429`)는 scale 이 같으면 3워드 `adc` 1회, 41자리 경계 비교(첫 워드에서 끝남), `memcpy` 24바이트.
- 도메인 검사는 `qdata_sum_acc_add_dbv`(`query_opfunc.c:2454`)의 타입 비교 한 번.
- 추정: 누산 하나당 35~60 cycles. 이 구간에 PG 아이디어를 더할 곳이 없다.

### (g) 연산당 할당 — 표 15행

CUBRID 산술은 힙 할당이 없고, PG 는 연산당 palloc 2회 이상이다. 옮길 것이 없다. CUBRID 의 할당은 문자열 변환(`object_domain_convert.cpp:3144`)에서만 생긴다.

## 4. TPC-H SF10 질의별 추정

lineitem 59,986,052행, orders 15,000,000행, partsupp 8,000,000행, customer 1,500,000행(`~/databases/tpch/README.md`). 질의 SQL 은 `/home/cubrid/dev/workspace/tpch-sspq/queries/q*-cubrid.sql`. lineitem 의 `l_quantity`, `l_extendedprice`, `l_discount`, `l_tax` 는 전부 `numeric(15,2)`(`~/databases/tpch/load/schema_nopk:51-54`).

행 비율은 TPC-H 명세의 균등 분포에서 낸 값이며 측정이 아니다. 표의 수치는 전부 (추정)이다.

| 질의 | NUMERIC 이 닿는 곳 | 해당 연산 | 기대 효과(추정) |
|---|---|---|---|
| Q1 | 98% 안팎 행(~59M)에 행당 누산 7개: `sum(l_quantity)`, `sum(l_extendedprice)`, `sum(ext*(1-d))`, `sum(ext*(1-d)*(1+t))`, `avg` 3개 + count. 마지막에 4그룹의 finalize 와 그룹당 avg 나눗셈 3회 | 식은 agg-expr(u128), 나머지는 `SUM_ACC` — **둘 다 이미 word 도메인.** 비교·문자열·반올림 없음, 자릿수 계산은 finalize 뿐 | **0~1%, 상한 3%.** 행당 numeric 구간이 Q1 시간의 10~15%(추정)이고 남은 개선 여지는 PG 가 가르쳐 주는 쪽이 아니라 leaf 변환 공유(같은 열을 10회 가량 `bytes_to_words`)뿐이다 |
| Q6 | 약 1/7(8.5M 행)이 날짜를 통과한 뒤 `l_discount between 0.05 and 0.07`(비교 2), `l_quantity < 24`(비교 1), `sum(ext*d)`(agg-expr) | 비교 단축 (A) | ≤1%. 술어 순서는 미확인 |
| Q14 | 1개월분(약 0.7M 행)의 CASE 안 `ext*(1-d)`(커널 add/sub/mul_fixed64), 최종 곱·나눗셈 1회 | (B) | ≈0 |
| Q17 | 상관 서브쿼리 부품 약 2000개, `0.2*avg` 곱·나눗셈 수천 회, 후보 lineitem 약 6만 행의 비교 | - | ≈0 |
| Q11 | 약 32만 행 `sum(ps_supplycost*ps_availqty)`(정수는 cast wrap), HAVING 약 3만 그룹 비교(scale 2 대 10 혼합) | (A) | ≈0 |
| Q18 | 60M 행 `sum(l_quantity)` + **그룹 15M 개 finalize**(`snapshot` `4706`) + **HAVING 비교 15M 회**(scale 2 대 정수 상수) | (A) + (B) | **1~3%** — 가장 큼 |
| Q22 | 150만 행 `c_acctbal > 0.00` 비교와 `avg` | (A) | ≈0 |
| Q2, Q3, Q10, Q15 | ORDER BY 의 NUMERIC 정렬 비교(`cmpdisk`), LIMIT 이면 상위 N | (A) cmpdisk | 각 ≤1~2% |
| 그 밖 | NUMERIC 비교·정렬이 적다 | - | ≈0 |

종합: **PG 아이디어 트랙은 TPC-H 레버가 아니다.** 어떤 질의도 develop 보다 느려지지 않는다(추가되는 분기 비용은 ≤1 cycle 이고, 모든 개선은 결과를 바꾸지 않는 같은 연산의 단축이다). 이 트랙의 가치는 NUMERIC 비교·정렬·출력·반올림이 많은 비-TPC-H 작업에 있다.

## 5. 연산 단위 하네스 설계

목적은 "이진 현행 대 이진+아이디어"를 연산별로 비교해 **1.3배 이상 이기는 연산만** 후보로 남기는 것이다. 이 티켓에서는 만들지 않는다(구현은 #570).

### 5.1 구조와 링크

- **프로그램.** 독립 C++ 한 개(`.git_ignored_dir/scratch/cbrd27819/harness/numeric_ops/` 아래, 엔진에 넣지 않음). 구성은 survey 하네스(`exact_check.cpp` + `exact_fn.inc`)와 같다: 아이디어 쪽은 별도 `.inc` 에 새로 작성(ADR 0036: PG 소스 불가), 엔진 쪽은 아래 방식.
- **"현행" 쪽은 엔진 소스를 그대로 쓴다.**
  1. survey 의 `exact_check.cpp` 는 엔진 라이브러리에 링크하지 않는다. 자체 typedef 와 매크로(`NUMERIC_CLZ64`, `pow10` 표, `numeric_get_uint64_from_be`)를 선언하고 `exact_fn.inc` 에 베낀 함수 본문을 `#include` 해 `stub/memory_wrapper.hpp` 스텁으로 독립 빌드한다. 이 방식은 드리프트가 생기고 `static` helper(`float_numeric_compare`, `mul_normalize`, `get_decimal_digit`)를 부를 수 없다.
  2. 그래서 하네스 번역 단위에서 `#include "<develop>/src/query/numeric_opfunc.c"` 를 하고, 컴파일 옵션은 develop **release** 프리셋의 `build_preset_release/compile_commands.json` 에서 `query/numeric_opfunc.c` 의 **sa** 변형 항목을 그대로 가져온다(`syntax.py` 가 같은 방식. 항목은 server/sa/cs 3개). 헤더 경로와 `-D` 를 손으로 적지 않는다.
  3. 그 파일이 내부에서 부르는 엔진 함수(`er_set`, `db_value_domain_init`, `tp_domain_resolve_default`, `prm_get_bool_value` 등)는 같은 release install 의 `libcubridsa.so` 에 링크한다(`-L$INST/lib -lcubridsa -Wl,-rpath,$INST/lib`). 실행 파일 쪽 정의가 공유 라이브러리보다 우선하므로 `numeric_opfunc.c` 가 이중 정의로 충돌하지 않고, `__attribute__((constructor))` 표 초기화(`458`, `518`, `544`)도 하네스 시작 때 돈다. 오류 경로(오버플로) 입력은 정확성 단계에서만 쓰며 `er_set` 은 실행 파일에서 스텁으로 덮는다.
  4. `arithmetic.c` 의 ROUND 계열은 의존이 많으므로 `libcubridsa.so` 의 export(`db_round_dbval` 등)를 그대로 호출한다.
- **어느 install.** develop `a199916d4` 를 worker 가 `just build release`(`INSTALL_PREFIX=~/release/CUBRID-cbrd27819-base`, `WORKSPACE=<a199916d4 워크트리>`)로 새로 만든 것. 기존 `~/release/CUBRID-cbrd27819-s0`, `-s1c` 는 survey 변경이 섞여 있어 기준으로 쓰지 않는다. 지문은 `sha256sum lib/libcubridsa.so` 를 결과 파일에 적는다(`cubrid-build` 규칙).
- **API 층.** 엔진이 부르는 층(DB_VALUE 입출력)에서 잰다. `db_make_numeric`(`dbtype_function.i:1632`)와 `db_value_domain_init`(`db_macro.c:163`) 비용이 연산 비용의 바닥(연산당 ≈20~30 cycles)이라 이 층을 빼면 개선율이 부풀려진다.

### 5.2 하네스가 다루는 연산(요약)

| ID | 연산 | 현행 | 아이디어 쪽 |
|---|---|---|---|
| H1 | add/sub/mul | `float_numeric_db_value_add/sub/mul/mul_fixed64` | 64비트 특수화 + u64/u128 자릿수(표 1, 3, 13) |
| H2 | 비교 | `numeric_db_value_compare` | scale 같으면 계수, 다르면 u128/비트 길이(표 8) |
| H2b | 디스크 비교 | `mr_data_cmpdisk_numeric` | DB_VALUE 없는 직접 비교(표 9) |
| H3 | 자릿수 | `float_numeric_get_decimal_digit` | u64/u128 전용(표 13) |
| H4 | 나눗셈 | `float_numeric_db_value_div` (≤19자리, 20~40자리) | 몫 길이 제한 + 인라인 divq 또는 역수곱(표 5, 6) |
| H5 | 문자열 | `numeric_db_value_print`, `numeric_coerce_string_to_num_status` | 패딩 제거, 단일 패스(표 10, 11) |
| H6 | 반올림 | `db_round_dbval` 등 NUMERIC 가지, `float_numeric_div_normalize` | 이진 helper, 역수곱(표 7) |
| H8 | 기준선 | `numeric_sum_acc_add_dbv`, `numeric_agg_expr_*`, `float_numeric_normalize_for_hash` | (비교 기준만, "이득 없음" 확인용) |

### 5.3 입력 분포

- **C0 — TPC-H 실데이터.** lineitem 의 `l_quantity`, `l_extendedprice`, `l_discount`, `l_tax`, partsupp 의 `ps_supplycost`, customer 의 `c_acctbal`, orders 의 `o_totalprice`. 행 상관을 유지한 튜플 단위로 100만 개.
- **C1 — 집계 결과형.** 17~19자리, scale 2/4/6(Q1 의 sum 값).
- **C2 — 리터럴.** precision 1~5, scale 0/1/2/10(`1`, `300`, `24`, `0.2`, `7.0`, `100.00`, `0.0000100000`).
- **C3 — scale 혼합 쌍.** (0,2), (2,4), (4,6), (2,10) 등.
- **C4 — 경계.**
  - 10^k±1 (k = 18, 19, 20, 37, 38, 39, 40).
  - 2^63, 2^64, 2^127, 2^128 ±1 (고속 경로 이탈선).
  - 선언 NUMERIC(15,2), (38,10), (38,0), floating(40) 각각.
- **C5 — 부호·0.** 음수, 0, 같은 값의 다른 scale(`0`, `0.00`), 음의 scale(−2, −214), 양의 scale 252.
- **C6 — 오류 입력.** 정확성 단계 전용.
- **TPC-H 값의 성격.** 가격 계수는 대략 1.1e7 이하, 수량 100~5000, 할인 0~10, 세금 0~8(스펙 기준, 첫 행으로 확인: `33078.94`, `0.04`, `0.02`). 모두 u64 안이라 TPC-H 값은 느린 경로를 건드리지 않는다.

### 5.4 TPC-H 샘플을 **서버 없이, DB 를 열지 않고** 뽑는 법

- **권장: 적재 원본에서.** `/home/cubrid/dev/TPC-H/scale10/load_data/*.load` 는 `tpch_sf10` 에 적재된 바로 그 데이터다(md5 가 `~/databases/tpch/README.md` 에 기록됨). DB 를 열지 않으므로 공유 DB 에 닿지 않는다.
- **방법.**
  - 8.7GB 를 순차로 읽지 말고 무작위 바이트 오프셋으로 `pread` 해 다음 개행부터 한 줄씩 읽는다. 시드는 고정(예: 27819).
  - lineitem 은 앞 8필드(`... quantity extendedprice discount tax ...`)에 따옴표 문자열이 없어 공백 분리가 된다. customer·partsupp·orders 는 필드 앞쪽에 따옴표 문자열이 있어 따옴표 인식 분리기를 쓴다(`python3 -I`).
  - 각 값을 (부호, 계수, scale)로 변환해 이진 파일로 저장하고, 문자열 입력 벤치(H5)용으로 원문 텍스트도 같이 둔다.
- **`csql -S` 는 권하지 않는다.** `csql -S -r`(`CSQL_SA_MODE_S='S'`, `CSQL_READ_ONLY_S='r'`, `utility.h:1499-1520`)은 SA 로 DB 를 부팅하므로 서버가 올라 있으면 열 수 없고, README 에 따르면 SA 로 한 번만 열어도 볼륨 헤더가 다시 쓰인다(mtime 변경). **지금 실행하지 말 것**(요청대로). 꼭 필요하면 registry 에 claim 하고 서버가 없는 시점에 쓴다.
- **술어 타입 확인(V7)은 다른 DB 에서.** tpch_sf10 이 아니라 TPC-H 스키마만 가진 소형 scratch DB(`cubrid createdb`)를 따로 만들어 `;plan`/XASL 덤프로 확인한다.

### 5.5 측정 방법

- **고정.** 코어 하나에 `taskset -c <N>`. 같은 코어의 SMT 형제가 놀고 있는지 확인(`mpstat -P ALL 1 3`, 이 호스트는 다른 세션의 CTP·서버가 돈다). 측정 전후 `/proc/cpuinfo` MHz 를 기록(CPU: Xeon Silver 4216, 2.1GHz 기본·3.2GHz 최대).
- **샘플.** 한 샘플은 입력 배열(L1~L2 에 들어가는 8K~16K 쌍)을 2^20 연산이 되도록 반복 처리하고 합계로 결과를 소비해 dead-code 제거를 막는다. 시계는 `clock_gettime(CLOCK_MONOTONIC_RAW)`. 메모리 상주형(64MB 이상) 변형을 하나 더해 캐시 영향을 본다.
- **교차.** 현행 A 와 아이디어 B 를 A B A B 순으로 번갈아 N=15 회 재고 **각각의 최솟값**의 비를 보고한다. 프로세스를 3번 따로 띄워 최솟값의 변동계수가 3% 이하인지 확인한다.
- **정확성 먼저.** 시간을 재기 전에 현행과 아이디어의 결과(값, precision, scale, 부호, 반환 코드)가 **전수 동일**한지 확인하고 하나라도 다르면 중단한다. 입력은 무작위 ≥10^8 + C4/C5 경계 전부 + C6.

### 5.6 판정 규칙

한 아이디어는 다음을 모두 만족할 때만 후보다.

1. **속도.** 그 연산에서 최솟값의 비(현행/아이디어)가 ≥1.3 이다. 기준 입력은 C0∪C3(TPC-H 에서 실제로 닿는 분포)의 가중 평균이다.
2. **무회귀.** 어떤 입력 부류에서도 3% 넘게 느려지지 않는다.
3. **결과 불변.** #570 의 완료 조건과 같다: 값, precision(정확한 자릿수 유지), scale, 반올림(half-up), 오버플로 오류, 0 의 부호(−0 없음).

묶음 규칙: 단독 1.3× 에 못 미치지만 같은 경로의 군더더기를 함께 줄이는 것(표 1·2·13)은 한 아이디어로 묶어 판정한다.

### 5.7 하네스가 답해야 할 항목

- V1: add/sub 특수화 + 자릿수 단축의 실제 배율(표 1, 13)
- V2: 비교 단축의 배율. 같은 scale 다른 precision, scale 혼합 각각
- V3: `cmpdisk` 직접 비교의 배율
- V4: 나눗셈의 배율. 몫 길이 제한만, 거기에 인라인 divq, 또는 역수곱
- V5: 문자열 출력·입력의 배율
- V6: ROUND/TRUNC/FLOOR/CEIL 이진화의 배율과 결과 동일성
- V7: 술어 상수의 타입(서버 필요, scratch DB). 아래 7장 참조

## 6. 순위 단축 목록

| 순위 | 아이디어 | 근거 | 기대 배율(추정) | TPC-H | 위험 |
|---|---|---|---|---|---|
| 1 | (A) 비교 단축 + `cmpdisk` 직접 비교 (표 8, 9) | PG `cmp_var_common`(weight 먼저), `numeric_fast_cmp`(포장 값에서 비교) | 비교 2~3×, cmpdisk 3.5~5× | Q18 1~3%, Q6·정렬 ≤1~2% | 낮음(순수 수학, 결과 동일). #563·#567 의 NUMERIC×DOUBLE 비교와 같은 "지수 먼저" 도우미(`float_numeric_normalize_for_sort` `4208` 가 이미 `digits - scale` 계산)를 공유할 수 있다 |
| 2 | (B) 자릿수 단축 + add/sub 특수화 (표 1, 2, 13) | `mul_fixed64` 선례(`3191`, 절약 항목은 주석 `3187-3189`) | 1.5~2×(묶음) | Q18 finalize 1~3% | 중간: precision 이 정확한 자릿수여야 함(해시·디스크 등급이 의존). 10^k 경계 전수 테스트 필수 |
| 3 | (C) ROUND/TRUNC/FLOOR/CEIL 이진화 + 문자열 출력 패딩 제거 (표 7, 10) | PG `round_var`/`get_str_from_var` 는 필요한 자리만 만진다 | 5~20× / 3~8× | 0 | 중간: 부호, 음의 scale, `oracle_compat_number`(`7130`) 출력 동일성 |
| 4 | (D) 나눗셈 몫 길이 제한 + 128/64 호출 제거 (표 5) | PG `div_var_int64` 의 몫 자리 수 상한 | 2~3× | 0 | 낮음 |
| 5 | (E) 곱셈 고속 조건을 실제 계수 크기로 (표 3) | 결과 동일(정확한 128비트 곱) | NUMERIC(38,·) 열에서 5×+ | 0 | 낮음. 단 "reference 와 비트 동일"이라는 주석 설명(`3176-3185`, `3234`)을 고쳐야 한다 |
| 6 | 문자열 입력 단일 패스 (표 11) | 일반 기법 | 1.5~2.5× | 0 | 중간(오류 입력 처리 보존) |

**버릴 것.** NBASE² 쌍 곱셈, 양/음 분리 누산기, 부동소수 역수 몫 추정(64비트 digit), approximate 나눗셈의 guard digit(PG 는 초월함수용), abbreviated key(이미 `float_numeric_normalize_for_sort` 가 비슷한 일을 인덱스 빌드에서 한다), 해시 정규화(TPC-H 무관).

**TPC-H Q1 의 기대 효과(추론만).** 위 순위 어느 항목도 Q1 의 행당 경로(leaf 변환, u128 식, `add_core`)를 건드리지 않는다. 자릿수 계산·비교·문자열·나눗셈이 행당 경로에 없다. 따라서 Q1 은 **0~1%**. 상한 3% 는 leaf 변환 공유 같은 PG 와 무관한 구조 개선을 더했을 때의 값이다.

## 7. 리드에게 질문

1. **TPC-H 효과가 없는 항목을 이 PR 에 넣을지.** (C)(D)(E)는 ≥1.3× 가 될 가능성이 높지만 TPC-H·비교 변경과 무관하다. 권고: 이 PR 은 (A)(B)로 한정하고 나머지는 별도 CBRD 이슈로 분리. #570 의 종료 규칙("아무 연산도 기준을 못 넘으면 코드 0줄로 닫는다")과 충돌하지 않는지 확인 부탁.
2. **precision 불변.** floating NUMERIC 의 precision = 정확한 자릿수를 사양 불변으로 못 박아도 되는가. 의존처를 셋 찾았다: `memory_hash.c:606-633`, `object_primitive.c:130-134`, `numeric_coerce_num_to_num` `5866-5879`. 못 박으면 "자릿수 계산 생략" 계열은 후보에서 빠진다.
3. **V7 의 술어 타입 확인.** Q6 의 `.06 - 0.01` 은 상수 접기에서 floating NUMERIC(`type_checking.c:15115-15125`)이 되는데, 열과 비교할 때 열 도메인으로 coerce 되는지가 비교 단축의 TPC-H 효과를 가른다. 서버가 필요하다. TPC-H 스키마만 가진 소형 scratch DB 를 worker 가 만들어 `;plan`/XASL 덤프를 해도 되는가. (tpch_sf10 은 열지 않는다.)
4. **비교 도우미 공유.** #563/#567 의 NUMERIC×DOUBLE "두 단계 비교"와 이 문서의 (A)가 같은 `digits - scale` 도우미를 쓴다. 한 곳에서 구현하고 한 곳에서 판정할지 정해 달라. 중복 구현을 피하려는 질문이다.
5. **곱셈 고속 조건 완화(E)의 범위.** `3235` 의 조건이 "reference 와 비트 동일"을 위해 보수적으로 잡은 것이라면(주석 `3176-3185`, `3234`), 실제 계수 크기 기준으로 넓히는 것을 이 지도 범위로 볼지.
6. **하네스 코어.** 고정할 코어 번호와, 측정 중 다른 세션의 CTP·서버가 그 코어와 SMT 형제를 쓰지 않도록 하는 방법(예약 또는 시간대).
7. **범위 밖 관찰 하나(미검증).** `memory_hash.c:628` 의 `mht_valhash` NUMERIC 가지는 `mht_1str_pseudo_key(db_get_numeric(val), -1)` 을 부른다. 길이 -1 이면 첫 NUL 바이트에서 멈추는데(`memory_hash.c:136-169`), 17바이트 빅엔디언 계수의 첫 바이트는 2^128 미만에서 항상 0 이므로 모든 NUMERIC 이 같은 해시를 받을 것으로 읽힌다. 코드 읽기뿐이고 develop 빌드에서 확인하지 않았다. 이 지도에 넣을지, 별도 `[VERIFY]` 이슈로 올릴지 정해 달라.

## 8. 검증되지 않은 것

- **모든 속도·cycle 수치.** 명령 수 계산이다. 공유 가정(`div r64` 35~90 cycles, `mul` 3 cycles, 호출 15~25 cycles)은 Agner Fog 의 Skylake 계열 명령표와 libgcc 동작에 대한 기억에서 가져온 것이고 이 세션에서 다시 열어 확인하지 않았다. 이 호스트 CPU 는 Xeon Silver 4216(Cascade Lake)이다(`lscpu`).
- **libgcc `__udivmodti4` 가 상위 < 제수일 때 단일 `divq` 로 처리한다는 점.** 기억에 의존한다. gcc 가 호출을 낸다는 사실(부록 B)만 확인했다. 엔진 release 의 최적화 옵션(RelWithDebInfo, `-O2` 가정)도 `compile_commands.json` 으로 확인하지 않았다.
- **Q6·Q18·Q22 술어의 상수 타입과 평가 순서, 행 통과 비율.** V7 과 하네스 단계가 필요하다. 행 비율은 TPC-H 명세의 균등 분포 가정이다.
- **Q1 에서 numeric 구간이 차지하는 비중(10~15%).** 추정이다. 같은 열의 leaf 변환이 공유되지 않는다는 것도 코드 읽기에서 그렇게 보일 뿐 프로파일로 확인하지 않았다.
- **loaddb 가 `numeric_coerce_dec_str_to_num` 에 이미 잘라 놓은 문자열을 넘기는지.** 호출 줄만 확인했다.
- **`mht_valhash` NUMERIC 해시 충돌**(7장 7번). 읽기 전용 관찰.
- **문헌.** Möller·Granlund 2011, Granlund·Montgomery 1994, Knuth TAOCP vol.2 4.3.1 은 제목·연도를 기억으로 적었다. 원문을 열지 않았다(Knuth 4.3.1 연습 16 은 PG 소스 주석 `numeric.c:9560-9565` 에 인용되어 있어 그 부분은 확인했다).
- **PG 성능 주장.** PG 의 연산당 palloc 은 소스(`478-481`, `11589`, `8552`, `9145`)에서 읽은 사실이고, PG 가 CUBRID 보다 느리다는 정량 주장은 하지 않았다.
- **`csql -S` 의 헤더 재작성.** `~/databases/tpch/README.md` 의 기록을 인용했고 다시 시험하지 않았다.
- **develop 워크트리 `5b1867174` 와 `a199916d4` 의 차이.** `numeric_opfunc.c` 에 영향을 준 커밋만 확인했다(`b8199438e`, `5cd1de888`). 다른 파일의 차이는 보지 않았다.

## 부록 A. PG 인용 (두 줄 이하, 출처 표시)

| 위치 | 인용 | 용도 |
|---|---|---|
| `numeric.c:8453` (PG) | `if (var1ndigits <= 6 && rscale == var1->dscale + var2->dscale)` | 작은 피연산자 직접 곱 위임 |
| `numeric.c:9182-9185` (PG) | `fdivisor = (double) divisor[0] * NBASE_SQR;` / `fdivisorinverse = 1.0 / fdivisor;` | 몫 digit 부동소수 추정 |
| `numeric.c:11499` (PG) | `while (var1weight > var2weight && i1 < var1ndigits)` | weight 먼저 비교 |
| `numeric.c:11776` (PG) | `extra = digits[--ndigits] % pow10;` | 반올림은 마지막 그룹에서만 나머지 연산 |
| `numeric.c:11960` (PG) | `if (accum->num_uncarried == NBASE - 1)` | carry 지연 누산기 |
| `numeric.c:4294-4295` (PG) | `Convert val1/(10**log10val2) to numeric. This is much faster than normal numeric division.` | 10^k 나눗셈 = 메타 이동(`int64_div_fast_to_numeric` `4298`). CUBRID 에서는 계수는 그대로 두고 scale 만 올리는 연산에 해당하며 TPC-H 에 없다 |

## 부록 B. gcc 코드젠 확인

`(GCC) 8.5.0 20210514`, `-O2 -S` 로 `float_numeric_div_fast` 단계 4(`numeric_opfunc.c:1477-1482`)와 `float_numeric_div_pow10`(`6037-6053`)의 모양을 그대로 옮긴 함수 둘을 컴파일했다. 파일은 `.git_ignored_dir/scratch/cbrd27819/research/probe/divprobe.c`, `divprobe.s`(scratch, 커밋하지 않음).

- `div_fast` 모양은 워드마다 `call __udivmodti4` 한 번(`/` 와 `%` 가 합쳐짐). 인라인 `div` 는 없다.
- `div_pow10` 모양은 워드마다 `call __udivti3` 한 번. 나머지는 곱셈으로 계산(`6049`).

따라서 128/64 나눗셈은 모두 libgcc 호출이다. `div_fast` 는 4회, `div_pow10` 은 `calc_words` 회(보통 3).
