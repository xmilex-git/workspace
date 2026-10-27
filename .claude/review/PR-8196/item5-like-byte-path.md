# PR 8196 항목 5 — 문자열 리프를 lockstep 방식으로 루프 안에서 바로 평가할 수 있나 (4번 세션)

대상: CUBRID/cubrid#8196 head `908bdc5af`, develop merge-base `c966fabc6`. 공유 worktree `~/dev/cubrid-worktree/pr8196-review` 는 읽기만 했습니다. 시제품은 별도 worktree `~/dev/cubrid-worktree/pr8196-item5` (head + 커밋하지 않은 diff, `.git_ignored_dir/scratch/pr8196-item5/proto.diff`)에 만들었습니다.

사용자 요청: "like 관련해서는 특정 codeset, collation 일때 byte 로 움직이는 최적화가 들어가있는데, 왜 여기선 그걸 사용하지 않았는지 리뷰." 이후 사용자가 의도를 이렇게 밝혔습니다.
- PR 의 CHAR/VARCHAR 처리 경로에 그 lockstep 을 적용해 더 빠르게 할 수 있는지.
- "경유를 하면 캐시미스가 나니까 저 for문 안에서 그냥 바로 되게끔 하면 되는거 아니냐" — LIKE 뿐 아니라 다른 연산(`=`, `<>`, IN 등)도 그렇게 평가해야 한다는 리뷰.

용어:
- **lockstep 매처**: develop 의 CBRD-27181(`5990b813b`)이 넣은 LIKE 빠른 경로입니다(`src/query/like_match_lockstep.i`). 대상 문자열과 패턴을 바이트 단위로 함께 전진하며 비교합니다. 콜레이션마다 등록 시점에 `byte_lockstep_kind`(UTF8 / SB / BINARY / NONE)가 정해지고, NONE 이 아니면 쓸 수 있습니다(`lang_set_byte_lockstep_like()`, `src/base/language_support.c:1644`).
- **리프**: 페이지 배치(GLOSSARY "페이지 배치")가 컬럼 배열 위에서 직접 판정하는 필터 항입니다.
- **행 경로**: 배치가 아닌 기존의 행 단위 평가입니다.

## TL;DR

가능하고, 실제로 빨라집니다. 다만 이득의 원인은 캐시 미스가 아니라 행마다 실행되는 명령어 수입니다. 이 PR 의 배치 경로는 이미 L1i 미스가 행당 0.1~0.9회에 그칩니다.

한 바이너리 안에서 변형만 바꿔 잰 시제품(1백만 행, `instructions:u`, 3회 반복 편차 0.25% 이하)의 결과는 다음과 같습니다.
- LIKE: lockstep 매처를 리프 만들 때 한 번 골라 루프에서 바로 부르면 -11~13%.
- `=`·`<>`·IN: 바이트 커널로 바꾸면 -5~22%.
- SUBSTRING IN: 문자 순회를 한 번으로 줄이면 합계 -26%.
- `_` 패턴과 CHAR LIKE: 리프로 받으면(지금은 행 경로) -63%.

경계값 534 질의를 develop 과 대조했습니다. 모든 변형에서 결과가 같았고, optdebug 에서 assert 도 나지 않았습니다.

## 배경: 지금 PR 의 문자열 리프가 행마다 하는 일

PR 은 lockstep 을 "안 쓴" 것이 아닙니다. 행마다 그 선택을 다시 하고 있습니다.

- **LIKE**: `eb_raw_kid_str()` 의 행 루프가 행마다 `qstr_like_match()` 를 부릅니다(`src/query/expr_batch.c:1362`). 이 함수는 `qstr_eval_like()` 의 래퍼입니다(`src/query/string_opfunc.c:5995`). `qstr_eval_like()` 는 부를 때마다 다음을 다시 합니다.
  - `lang_get_collation()`(외부 함수, `string_opfunc.c:6023`)
  - `intl_pad_char()`(외부 함수, `:6024`)
  - ESCAPE 검사
  - `byte_lockstep_kind` switch 와 codeset 교차 검사(`:6035-6066`)

  그 뒤에야 `qstr_like_match_lockstep_utf8()` 에 들어갑니다. 콜레이션·codeset·ESCAPE 는 리프를 만들 때 이미 정해져 있으므로, 이것은 불변인 분기를 루프 안에서 다시 판정하는 경우입니다(cpp-perf-rules BR-04 확장, CC-05).
- **`=`·`<>`**: `QSTR_COMPARE` 가 `lang_Collations[id]->fastcmp` 를 간접 호출합니다(`expr_batch.c:1372`). utf8_bin 이면 이것이 `lang_fastcmp_byte()` 이고(`language_support.c:5535`), 바이트마다 공백 분기 하나와 가중치 표 조회를 두 번 합니다.
- **IN**: 목록 값마다 같은 `QSTR_COMPARE` 를 부릅니다(`expr_batch.c:1300`). 작은 IN 은 옵티마이저가 OR 로 펴므로 `=` 리프 여러 개가 됩니다(trace 의 rewritten query 로 확인).
- **SUBSTRING IN**: 행마다 문자열 전체의 문자 수를 셉니다(`intl_char_count()`, `expr_batch.c:1277`). 그다음 `intl_char_size()` 를 두 번 부릅니다.

callgrind 로 잰 head release 의 행당 명령어 수입니다(SA, 1회 실행분 = (R3 - R1) / 2, 1백만 행).

| 질의 (head) | 전체 | 행마다 다시 하는 부분 |
|---|---|---|
| `vc LIKE '%ABC%'` (VARCHAR(44), utf8_bin) | 737 | `qstr_eval_like` 진입부 61 + `intl_pad_char` 10 + `qstr_like_match` 9 + `lang_get_collation` 4 = **84 (11.4%)**. lockstep 매칭 자체(memchr 포함)는 331 |
| `instr_c = 'TAKE BACK RETURN'` (CHAR(25)) | 470 | `lang_fastcmp_byte` 130 (28%) |
| `mode_v IN (5개)` (OR 로 펴짐) | 770 | `lang_fastcmp_byte` 168 + 리프 루프 196 |
| `substring(instr_v,1,4) IN (2개)` | 686 | 문자 세기 158 (`intl_char_size` 101, `intl_count_utf8_chars` 30, `intl_char_count` 27) + 비교 89 |

### "캐시 미스" 전제는 맞지 않습니다

같은 측정에서 L1i 미스(`L1-icache-load-misses`, 1백만 행 1회 실행분)는 다음과 같습니다.
- head 배치 경로: 0.1M~0.9M, 즉 행당 1회 미만입니다. 예: `like_vc` 0.25M~0.9M(측정 회차마다 다름), `ins_eq` 0.05M~0.5M.
- develop 행 경로: 0.8M~50M 입니다. 예: `vc_in5` 40.9M, `sub_in` 49.7M.

경유 단계를 없앤 시제품 모드 1 의 `like_vc` 는 L1i 미스가 0.3M → 0.1M 으로 행당 0.2회 줄었습니다. 미스 한 번을 L2 적중 10~20 사이클로 잡아도 행당 4사이클 이하입니다. 같은 변경이 줄인 명령어는 행당 84개입니다. 루프 안에서 같은 몇 KB 의 코드가 계속 돌기 때문에 경유 함수들은 L1i 에 그대로 남아 있습니다. 비용은 그 함수들이 행마다 실행하는 명령어입니다. 리뷰 코멘트는 "캐시 미스" 대신 "행마다 다시 하는 판정과 호출(명령어 수)"로 쓰는 것이 측정과 맞습니다.

## 시제품

한 바이너리 안에서 환경변수 `EB_PROTO` 비트로 변형을 고릅니다. 빌드가 다르면 코드 배치 차이가 결과에 섞이므로(MEAS-08), 그것을 피하려고 이렇게 만들었습니다. 0 은 PR 그대로입니다.

| 비트 | 변경 |
|---|---|
| 1 | LIKE 리프를 만들 때 `qstr_like_lockstep_fn()`(새로 노출, `qstr_eval_like()` 와 같은 kind·codeset 판정)으로 lockstep 인스턴스를 한 번 골라 두고, 루프에서 함수 포인터로 바로 부름. FALLBACK(패턴 깊이 > 256)이면 기존 `qstr_like_match()` |
| 2 | UTF-8 lockstep 인스턴스를 `expr_batch.c` 안에서 `like_match_lockstep.i` 로 한 번 더 생성해 루프에서 직접 호출(인라인 가능) |
| 4 | `=`·`<>`·IN: `eb_bytes_eq()` — 짧은 쪽 길이까지 memcmp. 상수에 0x00/0x20 이 있을 때만 그 둘을 같은 값으로 보며 다시 비교. 그다음 길이가 같거나, ignore_trailing_space 일 때만 긴 쪽 꼬리가 0x00/0x20 뿐이어야 같음. 자격: `fastcmp == lang_fastcmp_byte` 이고 가중치가 항등인 내장 콜레이션(utf8_bin, utf8_en_cs, iso88591_bin, iso88591_en_cs) |
| 8 | LIKE 리프가 `_`·`\` 패턴과 CHAR 컬럼을 받음 |
| 16 | SUBSTRING IN 을 `start + len - 1` 문자까지 한 번만 순회해 자름 |

## 발견 사항

### Blocking

없습니다. 아래는 모두 결과는 맞지만 더 빠르게 할 수 있는 지점입니다.

### Non-blocking

1. **LIKE 는 lockstep 인스턴스를 리프에서 한 번 고르고 루프에서 바로 부를 수 있음** (`src/query/expr_batch.c:1358-1368`, `src/query/string_opfunc.c:5995-6075`)
   - **무엇인가:** 배치 LIKE 리프는 행마다 `qstr_like_match()` → `qstr_eval_like()` 진입부를 거쳐 lockstep 에 도착합니다. 진입부의 판정은 전부 리프를 만들 때 정해지는 값입니다.
   - **측정** (시제품, 같은 바이너리, 1백만 행 1회 실행분 `instructions:u`):

     | 질의 | PR 그대로 (모드 0) | 함수 포인터 (모드 1) | 인라인 (모드 3) |
     |---|---|---|---|
     | `vc LIKE '%ABC%'` | 751.2M | 667.2M (-11.2%) | 655.8M (-12.7%) |
     | `vc NOT LIKE '%ABC%'` | 806.4M | 722.7M (-10.4%) | 710.9M (-11.8%) |
     | `vci LIKE '%ABC%'` (utf8_en_ci, 대상 아님, 대조군) | 4308.3M | 4307.5M | 4308.0M |

     모드 0 → 1 에서 준 84.0M 은 callgrind 로 잰 경유 비용(행당 84)과 같습니다. 경과 시간 중앙값은 116 → 106 → 100 ms 였지만, 부하 평균 38(64코어)에서 잰 값이라 참고만 합니다.
   - **고칠 방법:** `string_opfunc.c` 에 인스턴스를 고르는 함수를 하나 노출합니다. 시제품 `qstr_like_lockstep_fn()` 이 `qstr_eval_like()` 의 dispatch 와 같은 조건(kind 와 codeset 교차 검사, ESCAPE 없음)으로 인스턴스를 돌려줍니다. 리프는 그 포인터를 들고, 루프는 kind 별로 나눠 둡니다(BR-04: 리프마다 커널을 고르고 루프 안에서는 분기하지 않게). 인라인(모드 3)은 1.1%p 를 더 줄이지만 `.i` 인스턴스 매크로를 헤더로 옮겨야 하므로, 함수 포인터만으로도 대부분을 얻습니다.
   - **그냥 두면:** 결과는 같습니다. LIKE 필터 스캔마다 명령어가 11% 정도 더 듭니다.

2. **`=`·`<>`·IN 도 lockstep 이 가능한 콜레이션이면 바이트 커널로 루프 안에서 평가할 수 있음** (`src/query/expr_batch.c:1372-1375`, `:1298-1302`)
   - **무엇인가:** 문자열 `=` 리프는 행마다 `fastcmp` 를 간접 호출합니다. utf8_bin 의 `lang_fastcmp_byte()` 는 가중치가 항등이므로, 결과가 아래 바이트 규칙과 같습니다(`language_support.c:5535-5600`).
     - 공백(0x20)은 0으로 바꾸고 NUL 은 가중치 0 이라, 둘이 같은 값입니다.
     - 길이가 다르면 ignore_trailing_space 일 때만, 남은 꼬리가 0x00/0x20 뿐이어야 같습니다.
   - **측정** (`instructions:u`, 모드 0 → 모드 4):

     | 질의 | 모드 0 | 모드 4 |
     |---|---|---|
     | `mode_v = 'MAIL'` (VARCHAR(10), 1/7 일치) | 390.0M | 355.2M (-8.9%) |
     | `mode_v <> 'MAIL'` | 427.4M | 394.2M (-7.8%) |
     | `instr_v = 'TAKE BACK RETURN'` (25% 일치) | 455.4M | 354.4M (-22.2%) |
     | `instr_c = 'TAKE BACK RETURN'` (CHAR(25), 패딩) | 481.6M | 406.1M (-15.7%) |
     | `mode_c = 'MAIL'` (CHAR(10)) | 400.9M | 381.4M (-4.9%) |
     | `mode_c IN ('MAIL','SHIP')` | 568.5M | 529.6M (-6.8%) |
     | `mode_v IN (5개)` (OR 5개) | 803.9M | 661.8M (-17.7%) |
     | `mode_ci = 'MAIL'` (utf8_en_ci, 대상 아님, 대조군) | 390.0M | 390.4M |

     이득은 비교하는 바이트 수에 비례합니다. 일치 행이 많고 값이 길수록 크고, 첫 바이트에서 갈리는 짧은 코드값은 작습니다.
   - **자격 조건(정정 포함):** "lockstep 이 가능한 콜레이션이면 `=` 도"가 맞습니다. 처음에 utf8_ko_cs 를 예외로 보았는데 틀렸습니다.
     - utf8_ko_cs 의 `=` 는 `lang_strcmp_utf8()` 입니다. 이 함수는 `lang_strmatch_utf8()` 를 비교 모드로 부르기만 합니다(`language_support.c:2890-2894`).
     - 항등 가중치에서 그 비교는 위와 같은 규칙이 됩니다(`:2951-2985`, `:3003-3037`). 공백→0 이고, 256 이상 코드포인트는 코드포인트끼리 비교하며, 꼬리 판정은 `weights_ti` 로 합니다.
     - develop 에서 같은 데이터의 utf8_ko_cs 컬럼과 utf8_bin 컬럼에 대해 `=`·`<>`·IN 31 질의가 같은 결과였습니다(NUL·후행 공백·한글·빈 문자열 포함).
     - 바이트 비교와 결과가 다를 수 있는 것은 잘못된 UTF-8 바이트뿐입니다(`intl_utf8_to_cp()` 가 모두 0xFFFFFFFF, `intl_support.c:3872-3873`). develop 의 LIKE lockstep 이 이미 같은 전제를 받아들였습니다.
   - **주의 두 가지:**
     - LIKE lockstep 함수를 `=` 에 그대로 쓸 수는 없습니다. 꼬리 규칙이 다릅니다. LIKE 는 대상 끝의 0x20 만 무시하고 ignore_trailing_space 를 보지 않습니다(`LOCKSTEP_TAIL_IS_PAD`). 예를 들어 VARCHAR 에서 ignore_trailing_space=no 일 때 `'abc ' = 'abc'` 는 FALSE 인데 `'abc ' LIKE 'abc'` 는 TRUE 입니다. 상수 안의 `%`·`_` 도 와일드카드가 됩니다. 그래서 `=` 전용 커널(몇 줄)이 필요하고, 고르는 기준만 같은 kind 를 씁니다.
     - BINARY kind(`binary` 콜레이션)는 규칙이 다릅니다. `lang_fastcmp_binary()` 는 0x00/0x20 을 같게 보지 않고, 꼬리는 0x00 만 무시하며, ignore_trailing_space 를 보지 않습니다(`:6497-6542`). 커널이 하나 더 필요합니다.

     시제품의 자격은 `fastcmp == lang_fastcmp_byte` 로 더 좁게 잡아서 utf8_ko_cs 와 binary 는 재지 않았습니다.
   - **그냥 두면:** 결과는 같습니다. 문자열 `=`·IN 필터에서 5~22% 의 명령어가 더 듭니다.

3. **SUBSTRING IN 은 자르는 데 필요한 문자만 한 번 순회하면 됨** (`src/query/expr_batch.c:1272-1293`)
   - **무엇인가:** 행마다 문자열 전체를 세고(`intl_char_count`), 시작 위치와 길이를 `intl_char_size` 로 두 번 더 셉니다.
   - **측정:** `substring(instr_v,1,4) IN ('TAKE','NONE')` 은 모드 0 에서 699.3M 입니다. 모드 4(바이트 비교)는 656.9M(-6.1%)이고, 모드 20(바이트 비교 + 한 번 순회)은 516.7M(-26.1%)입니다.
   - **고칠 방법:** `start - 1` 문자를 건너뛰고 `len` 문자만 전진합니다. UTF-8 은 `intl_Len_utf8_char[]`, ISO-8859-1·binary 는 1바이트입니다. 문자열 끝에서 멈추는 규칙은 `qstr_substring()` 과 같게 맞춰야 합니다. 시제품은 올바른 UTF-8 만 가정했습니다(코드에 `shortcut:` 주석). 잘린 마지막 문자를 다루는 방식이 `intl_count_utf8_*` 와 같은지는 따로 확인해야 합니다.
   - **그냥 두면:** 결과는 같습니다. SUBSTRING IN 필터에서 20% 정도의 명령어가 더 듭니다.

4. **`_`·`\` 패턴과 CHAR LIKE 를 리프로 받으면 행 경로 대비 -63%** (`src/query/expr_batch.c:978-991`, `src/query/expr_compile.c:3971`)
   - **무엇인가:** `eb_like_pattern_ok()` 는 `_` 와 `\` 가 든 패턴을 거절합니다. lockstep 과 `qstr_eval_like()` 는 둘 다 `_` 를 처리합니다. ESCAPE 가 없으면(리프는 ESCAPE 를 받지 않음) `\` 는 리터럴입니다. 이 거절은 자체 매처 `eb_like_match()` 시절의 조건이 남은 것입니다(`6bc00f39f` 에서 그 매처를 지움). CHAR LIKE 제외도 같은 사정이며 항목 4 보고서 발견 2 와 같은 내용입니다.
   - **측정:** 해석기 경로 필터는 항 하나만 거절되어도 스캔 전체가 `batch: no (the data filter is interpreted)` 가 됩니다(trace 로 확인).

     | 질의 | 모드 0 (행 경로) | 모드 11 |
     |---|---|---|
     | `vc LIKE '%AB_C%'` | 1767.1M | 655.0M (-62.9%) |
     | `ch LIKE '%ABC%'` (CHAR(44)) | 1770.3M | 663.7M (-62.5%) |
   - **고칠 방법:** `eb_like_pattern_ok()` 를 지우고(ESCAPE 는 `expr_pred_term_string_info()` 가 이미 거절), `expr_compile.c:3971` 의 `|| like` 를 지웁니다. 오래된 주석(`expr_compile.c:3910-3912` "over a binary collation", `expr_batch.c:1017-1018` "where '%' matches bytes")은 항목 4 보고서에 정리되어 있습니다.
   - **그냥 두면:** 결과는 같습니다. 이런 필터는 배치 효과를 전혀 받지 못합니다.

### Questions

- Q1. LIKE 리프가 행마다 `qstr_like_match()` 를 부르게 한 것은, dispatch 규칙을 한 곳(`qstr_eval_like()`)에만 두려는 의도였나요? 그렇다면 같은 파일에서 인스턴스를 고르는 함수를 노출하면 규칙은 한 곳에 둔 채로 루프에서 바로 부를 수 있습니다(발견 1).
- Q2. lockstep 대상이 아닌 콜레이션(예: utf8_en_ci)의 LIKE 는 배치에서도 4.31G/1백만 행입니다. utf8_bin 의 lockstep 0.75G 의 5.7배입니다. 대소문자를 접는 콜레이션은 바이트 lockstep 을 쓸 수 없으니 이 PR 범위 밖으로 보는 것이 맞는지요.
- Q3. `vc LIKE 'AB%'` 는 옵티마이저가 `vc >= 'AB' AND vc < 'AC'` 로 바꾸고, 문자열 범위 비교는 리프가 아니라서 `batch: no` 입니다(trace 로 확인). 접두 LIKE 는 흔한 모양인데, 범위 비교 리프를 이 PR 범위로 볼지요. 항등 가중치에서도 `lang_fastcmp_byte()` 는 공백을 0으로 보므로, 순서 비교는 단순 memcmp 가 아닙니다.

## 리뷰 코멘트 초안 (게시하지 않음)

> 문자열 리프가 lockstep 을 행마다 다시 고르고 있습니다. `eb_raw_kid_str()` 루프가 행마다 `qstr_like_match()` → `qstr_eval_like()` 를 부릅니다. 그때마다 `lang_get_collation()`, `intl_pad_char()`, ESCAPE 검사, `byte_lockstep_kind` switch 를 거친 뒤에야 lockstep 에 들어갑니다. 콜레이션·codeset 은 리프를 만들 때 정해지니, 인스턴스를 리프에서 한 번 고르고 루프에서는 바로 부르면 됩니다. `vc LIKE '%ABC%'` 1백만 행에서 행당 84 명령어, 전체의 11% 입니다(callgrind, 시제품 A/B 로 -11.2% 확인). `=`·`<>`·IN 도 lockstep 이 가능한 콜레이션이면 `fastcmp` 간접 호출 대신 바이트 커널로 평가할 수 있습니다. 공백/NUL 을 같은 값으로 보고, ignore_trailing_space 일 때 꼬리를 보는 규칙이고, `binary` 는 꼬리 NUL 만 보는 규칙입니다. 측정 결과는 -5~22% 였습니다. 그리고 `_`·`\` 패턴과 CHAR LIKE 거절은 자체 매처 시절의 조건이라 지금은 풀 수 있습니다(행 경로 대비 -63%).

## 실행한 검증

설치(모두 이 세션 scratch `.git_ignored_dir/scratch/pr8196-item5/` 아래 자기 사본):

| 이름 | 출처 | libcubridsa sha256 앞 16자 |
|---|---|---|
| head-rel | CI tarball `builds/pr/908bdc5af…/release` | 43eceb74a10d295b |
| head-dbg | CI tarball `builds/pr/908bdc5af…/debug` (optdebug) | - |
| base-rel | CI tarball `builds/develop/c966fabc6…/release` | 63ced9d7a70bae06 |
| proto-rel | head + `proto.diff`, `just build release` (Sonnet 워커, BUILD_EXIT=0) | 062bb9db57c3d9dd |
| proto-dbg | head + `proto.diff`, `just build optdebug` (Sonnet 워커, BUILD_EXIT=0) | d4cb08f8c77e052c |

proto 설치는 RPATH 가 자기 prefix 를 가리키는 것과 `nm` 에 `qstr_like_lockstep_fn` 이 있는 것을 확인했습니다. conf 는 모든 설치에서 head-rel 것과 같습니다(data_buffer_size=512M).

데이터: 같은 SA DB `item5db`(en_US.utf8) 하나를 모든 설치가 차례로 썼습니다.
- `t`: 1백만 행. sha1 접두 10~43자를 `vc VARCHAR(44)`, `ch CHAR(44)`, `vci VARCHAR(44) utf8_en_ci` 에 넣었고, 평균 26자입니다.
- `t2`: 1백만 행. TPC-H 의 shipmode 7값과 shipinstruct 4값을 CHAR/VARCHAR/utf8_en_ci 로 넣었습니다.
- `t3`: 경계값 34개 × 50 + NULL 50, 컬럼 6개(utf8_bin VARCHAR·CHAR(8), utf8_en_cs, utf8_ko_cs, iso88591_bin, binary).

수행한 것:
1. 정적 분석(lead): 위 인용 줄.
2. lead smoke, C/S trace (head-rel, 포트 1715, `;plan detail` + `NO_PARALLEL_SCAN`):
   - batch pages 9202, row path 0: `vc LIKE`, `vci LIKE`
   - batch pages 6946, row path 0: CHAR `=`, OR 5개, SUBSTRING IN
   - `batch: no (the data filter is interpreted)`: `'%AB_C%'`, CHAR LIKE, `'AB%'`(범위식)
3. lead smoke, callgrind (head-rel, SA, R1/R3): 위 "배경" 표.
4. 정확성(워커):
   - 경계값 534 질의(`=`·`<>`·IN 3종·LIKE/NOT LIKE 27패턴·SUBSTRING IN 3종·OR, 컬럼 6개)를 develop(base-rel) 결과와 대조했습니다.
   - head-rel: 534 줄 동일(lead).
   - proto-dbg: 모드 0, 1, 2, 3, 4, 8, 16, 31 모두 diff 0줄이었고, assert·core·signal 0건이었습니다.
   - proto-rel: 모드 0, 31 diff 0줄입니다.
   - 세 경우 모두 컴파일 오류 3건(iso88591 컬럼과 한글 상수의 collation 불일치)이 같습니다.
5. 성능(워커): `probes/pmu-proto.sh`. SA(`csql -S`)를 처음부터 `perf stat` 으로 쟀고, 1회 실행분 = (R11 - R1) / 10 입니다.
   - R11 을 3번 반복했고, `instructions:u` 의 반복 편차는 0.25% 이하였습니다.
   - 대조군 `id >= 0` 은 모드에 상관없이 393.9~395.7M 이었습니다.
   - 끝날 때 부하 평균이 38(64코어)이라 cycles·경과 시간은 판정에 쓰지 않았습니다. 같은 명령어 수에서 모드 31 의 cycles 만 튀는 셀이 있었습니다(`nlike_vc` 342M vs 453M).
   - 원표: `out/pmu-proto/summary-{proto-rel,head-rel,base-rel}.txt`.
   - 참고로 develop → head 는 `like_vc` 1717.5M → 739.5M, `vc_eq` 1459.6M → 383.3M 입니다.
   - 시제품 모드 0 은 CI head 보다 1~2% 많습니다(`like_vc` 751.2M vs 739.5M). 로컬 빌드 차이와, 시제품이 루프 안에 남긴 변형 분기 때문입니다. 실제 구현은 리프별로 커널을 골라 이 분기가 없습니다.

## 확인하지 못한 것

- CTP 는 돌리지 않았습니다. 시제품은 측정용이라 PR 에 넣을 코드가 아닙니다. 실제로 반영하면 release·optdebug 빌드와 sql 스위트(특히 `_t4_14_blank_value_1` 등 LIKE 후행 공백 TC)가 필요합니다.
- 병렬(px 워커) 경로는 재지 않았습니다. SA 측정은 직렬입니다. px 워커도 같은 리프 함수를 쓰므로 비율은 비슷할 것으로 보지만 측정하지 않았습니다.
- C/S 경과 시간과 TPC-H F06/F07 재측정은 하지 않았습니다. PR 본문이 재측정을 예고한 항목입니다.
- utf8_ko_cs·binary 에 대한 바이트 `=` 커널은 시제품 범위 밖이라, 근거는 코드 읽기와 develop 결과 대조 31 질의뿐입니다. EUC-KR, LDML 로 적재한 콜레이션, 잘못된 UTF-8 데이터는 시험하지 않았습니다.
- 시제품의 한 번 순회 SUBSTRING 은 올바른 UTF-8 만 가정합니다.
