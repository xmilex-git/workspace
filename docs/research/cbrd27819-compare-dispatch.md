# 비교 디스패치 설계 — 비교값을 어디서, 어떤 형태로 적용하는가 (workspace #567, 지도 #562)

2026-10-30. 질문: ADR 0037(경계 사양 포함)의 비교값 v(d) 를 BIGINT/NUMERIC × DOUBLE/FLOAT 의 모든 판정 자리에 어떤 코드 형태로 적용하는가. 전제: census `research/cbrd27819-compare-sites`(#565), 경계 사양(ADR 0037), 자체 최단 십진수(#563, 구현은 #568), PG 아이디어 (A)(#564, 구현은 #570).

- 기준 코드: develop `7b7e84d25`(census worktree `~/dev/cubrid-worktree/CBRD-27819-census`)와 엔진 브랜치 `CBRD-27819`(`bb4aac404` = survey S0·S1-3 rebase, #568 진행 중 미커밋 변경 포함, 읽기만 함). 줄 번호는 별도 표시가 없으면 develop 기준.
- 리드 smoke: survey install `~/optdebug/CUBRID-cbrd27819-s1c`, SA(`tools/fast-gate/fast-sa.sh`), `.git_ignored_dir/scratch/cbrd27819/567/smoke/` (`keep.sql`·`negscale.sql`, `out/`=정확 비교 env 켬, `out3/`=끔, `out4/`).
- 표시: [CONFIRMED] 코드·실측으로 확인, [VERIFY] #569 구현 중 확인할 것.

## 1. 결론

1. **(ii) 타입 유지 + 전용 cmpval.** BIGINT/NUMERIC × DOUBLE/FLOAT 비교는 어느 쪽도 변환하지 않고(`conv[0] = conv[1] = NULL`, method DIRECT), cmp 는 그 타입 쌍 전용 `PR_TYPE`(cmpval 만 바꾼 복사본)이다. 브랜치 `CBRD-27819` 의 S1-3 이 정수 × NUMERIC 에 이미 쓰는 `domain_compare_cmp (source0, source1, compared)`(`domain_rules.c`, 브랜치 1170) 를 이 쌍으로 넓힌다. K1(`domain_compute_comparison`)·거울(`domain_compare_mirror`)·풀기(`stx_unpack_decided_compare`)가 이미 이 함수로 cmp 를 정하므로 결정 지점이 하나다. K2(`tp_value_compare_with_error`)는 `tp_value_compare_common_domain` 앞에서 같은 쌍을 가로채 같은 비교 함수를 부른다.
2. **(i) 공통 타입 변경은 기각.** `tp_more_general_type`/`pt_common_type` 이 NUMERIC 을 답하게 하면 결과 타입·해시 키 도메인까지 바뀌어(census 결론 1) "산술·집계·함수 결과 타입 불변"(지도 확정)과 충돌한다. 또 비교값은 NUMERIC 도메인 밖일 수 있어(1e-300, 2^1000, inf, NaN) "DOUBLE 쪽을 NUMERIC 으로 변환"하는 conv 로 표현할 수 없다.
3. **행 비교는 두 단계.** BIGINT × DOUBLE 은 하드웨어 int64→double 이 정확 반올림이라 최단 십진수 없이 정확하다(3.1). NUMERIC × DOUBLE 은 기존 근사 변환으로 먼저 판정하고, 보호 띠(비트 패턴 거리 16) 안일 때만 비교값으로 정확 판정한다(3.2). 그래서 행 비용은 develop 의 "변환 + DOUBLE 비교"와 같은 수준이다.
4. **공용 도우미 `numeric_compare_magnitude`**(4장): 십진 지수가 붙은 두 계수의 크기 비교. 자리 위치를 먼저 보고 u128, 필요하면 워드로 정렬한다. 정수 × NUMERIC(S1-3), 비교값 정확 경로, NUMERIC × NUMERIC 의 scale 이 다른 비교(#570 (A))가 함께 쓴다.
5. **인덱스 키 범위는 KEEP 경계 + 정확 비교**(5장, 2026-10-30 1번 세션 확정): 경계를 DOUBLE 로 둔 채 B-tree 키 비교가 새 cmpval 을 쓴다. 엄격 단조 비교라 범위 탐색이 그대로 맞고, 키 원소 규칙에 새 코드가 없다. smoke 11질의에서 인덱스 = NONE 이었다.
6. **해시 키는 "정확한 쪽 도메인 + 정확한 상"**(6장): 키 도메인을 BIGINT/NUMERIC 쪽 도메인으로 두고, DOUBLE/FLOAT 쪽은 비교값이 그 도메인에 정확히 있을 때만 그 값으로 바꾼다. 없으면 NULL 키처럼 건너뛴다. 키 도메인 안의 동등이 새 동등과 같아지므로 재검사도 그대로 정확하다.
7. **따로 바꿀 자리**(7장): NULLIF, `qo_reduce_equality_terms`, DOUBLE 열 × 정확 상수의 리터럴 고정, 사양 14 범위 확장의 죽는 분기, `domain_resolve_compare`, SHORT/INTEGER × FLOAT.
8. **env 게이트 없이 기본 동작**(ADR 0038). 판정이 타입 쌍만으로 정해지고 클라이언트(XASL 생성)와 서버(풀기)가 같은 답을 내야 하는데, 프로세스별 환경 변수는 둘을 갈라놓을 수 있다.

## 2. 타입 쌍과 비교 방식

| 쌍 (순서 무관) | 비교 | 표현 | develop 대비 |
|---|---|---|---|
| BIGINT × DOUBLE | v(d) 규칙, 3.1 | DIRECT, conv 없음, 전용 cmpval | 답 바뀜 (ADR 0037) |
| BIGINT × FLOAT | BIGINT × DOUBLE((double) f) (ADR 0037 결정 5) | 같음 | 답 바뀜 |
| NUMERIC × DOUBLE | v(d) 규칙, 3.2 | 같음 | 답 바뀜 |
| NUMERIC × FLOAT | v32(f) 규칙(|f| ≥ 2^24 는 정확 정수, 확정), 3.3 | 같음 | 답 바뀜 |
| SHORT/INTEGER × NUMERIC, BIGINT × NUMERIC | 정확 (S1-3, 브랜치 커밋) | DIRECT + 전용 cmpval | 답 같음 |
| SHORT/INTEGER × FLOAT | DOUBLE 비교 (양쪽 무손실 변환) | CONVERT, conv 양쪽 → DOUBLE | 답 바뀜(|i| > 2^24) |
| SHORT/INTEGER × DOUBLE, FLOAT × DOUBLE | 현행 DOUBLE 비교 | 현행 | 같음 |

- BIGINT × FLOAT 을 (double) f 로 넓힐 때와 NUMERIC × FLOAT 이 v32(f) 를 쓸 때의 정수 쪽 답은 같다. 정수가 아닌 float 의 반올림 구간에는 정수가 없다(ulp ≤ 1 인 구간에서 float 는 ulp 의 배수, 정수와의 거리 ≥ ulp > 구간 반폭). 그래서 정수 b 의 순서는 v32(f) 기준이든 v((double) f) 기준이든 같다. 정수인 float 는 ≥2^24 정확 정수 규칙에서 두 경우 모두 그 정수다.
- SHORT/INTEGER × FLOAT 는 새 cmpval 이 아니라 기존 CONVERT(양쪽 DOUBLE) 로 둔다. 그래서 develop 의 DOUBLE 비교 의미(NaN 이 모든 수와 같음, #576)를 SHORT/INTEGER × DOUBLE 과 똑같이 유지한다. BIGINT × FLOAT 은 BIGINT × DOUBLE 처럼 전순서 NaN 을 따른다. 결과적으로 `int열 = cast('nan' as float)` 는 참, `bigint열 = …` 은 거짓이다(ADR 0037 결정 2 의 경계 그대로).
- 전순서: -inf < 수 < +inf < NaN, NaN = NaN 만, v(-0) = 0. 이 쌍의 cmpval 은 `total_order` 인자와 상관없이 이 순서를 쓴다(NULL 은 cmpval 밖에서 처리됨, `query_evaluator.c` 602–609).

## 3. 행 비교 알고리즘

모든 함수는 `numeric_opfunc.c` 에 둔다. #568 의 정적 `numeric_shortest_decimal_of_double/float`(유효숫자 u64, 십진 지수)를 같은 번역 단위에서 직접 부르기 위해서다. 공개 시그니처는 DB_VALUE 두 개 → `DB_VALUE_COMPARE_RESULT`(S1-3 의 `numeric_compare_bigint_num_exact` 와 같은 꼴)이다.

### 3.1 BIGINT × DOUBLE — 최단 십진수 없음

```
d NaN                 → b < d
x = (double) b        (하드웨어 변환, 정확 반올림)
x < d → LT, x > d → GT          (nearest(b) < d ⇒ b < v(d), ADR 0037 증명)
x == d:
  |d| < 2^53 → EQ               (이때 |b| < 2^53 이라 b 가 정확히 d, 정수 d 의 v(d) = d)
  d == 2^63  → LT               (b ≤ 2^63 - 1)
  d == -2^63 → b == INT64_MIN ? EQ : GT
  그 밖     → b 와 (int64) d 를 정수로 비교   (|d| ≥ 2^53 의 v(d) 는 정확 정수)
```
±inf 는 첫 비교에서 끝난다. 비용은 develop 의 BIGINT→DOUBLE 변환 + 비교에 분기 하나가 더해지는 정도다.

### 3.2 NUMERIC × DOUBLE — 근사 + 보호 띠 + 정확 경로

1. 특수값: d 가 NaN → n < d, ±inf → 부호대로 결정. n = 0 이고 d = ±0 → EQ.
2. 근사: x̂ = `numeric_coerce_num_to_double (n)`(브랜치 4898, develop 의 비교가 행마다 하던 바로 그 변환).
3. 띠: `ord(z)` 를 double 비트 패턴의 순서 정수(부호-크기 → 2의 보수)로 둔다. |ord(x̂) − ord(d)| > 16 이면 x̂ 와 d 의 순서가 답이다.
4. 정확 경로(띠 안): |d| < 2^53 이면 (m, e) = 최단 십진수(d)로 두고, n 의 (계수, −scale) 과 `numeric_compare_magnitude` 로 비교한다. |d| ≥ 2^53 이면 d = c·2^q 를 워드 정수로 두고 지수 0 으로 같은 도우미에 넣는다. 부호는 앞에서 정한다.

**띠의 근거.** 변환은 x̂ = fl(fl(C) / fl(10^s)) 다. fl(C) 는 정확 반올림(round-to-odd 접기, 브랜치 4880–4896 주석)이라 |δ1| ≤ u (u = 2^-53) 이다. 10^s 는 s ≤ 22 이면 정확하고, 그 밖은 표 상수 ≤ u 또는 `pow` ≤ 2u(glibc 는 1 ulp 미만)다. 나눗셈은 ≤ u 다. 따라서 상대 오차 ≤ 4u + O(u²) 이다. |x| u < ulp(x) 이므로 |x̂ − x| < 4.01 ulp(x) 이고, nearest(x) 는 x 에서 0.5 ulp 안에 있으므로 |x̂ − nearest(x)| < 4.51 ulp(x) 다. binade 아래로 넘어가면 ulp 가 반이 되어 패턴 거리로는 < 9.02 다. 그래서 띠 16 이면 "x̂ 와 d 의 순서 = nearest(n) 과 d 의 순서"가 성립하고, 두 단계 조건으로 n 과 v(d) 의 순서와 같다. 결과는 아래 넘침이 없다(|n| ≥ 1e-252). #563 실측 최대 오차는 2 ulp(1억 쌍)로, 이 상한 안이다.
**optdebug**: 띠 밖 판정 때마다 정확 경로를 함께 돌려 답이 같은지 assert 한다(4장의 도우미가 있으므로 코드 몇 줄). CTP 전체가 이 상한을 실측하는 셈이다.

### 3.3 NUMERIC × FLOAT

비교값은 v32(f) 다. |f| < 2^24 이면 float32 최단 십진수, 이상이면 정확 정수다(ADR 0037 결정 5). 근사 판정은 x̂(double)가 f 의 float 반올림 구간 [lo, hi](이웃 float 와의 중점, double 로 정확)를 띠 16 double-ulp 만큼 넓힌 범위 밖에 있을 때만 한다. 안이면 정확 경로로 간다(`numeric_shortest_decimal_of_float` + 도우미). 빈도가 낮은 쌍이라 단순한 구현도 괜찮다. 예: 항상 정확 경로로 시작하고, #572 측정에서 필요할 때만 띠를 넣는다.

### 3.4 K2 와 그 소비자

`tp_value_compare_with_error`(develop `object_domain.c:6536`)는 coercion 판정(`:6644`) 앞에서 `(BIGINT|NUMERIC) × (DOUBLE|FLOAT)` 쌍과 SHORT/INTEGER × FLOAT 쌍을 가로챈다. 앞의 쌍은 3.1–3.3 함수를, 뒤의 쌍은 양쪽 DOUBLE 변환을 쓴다. 다중 열 키 원소(`pr_midxkey_compare_element`), 컬렉션, JSON, 옵티마이저 상수 비교, 클라이언트 상수 접기, `mht_compare_dbvalues_are_equal` 이 이것으로 따라온다(census 3.2).

## 4. 공용 도우미 — `numeric_compare_magnitude` (#570 (A) 와 공유)

```c
/* the order of the magnitudes a * 10^a_exp and b * 10^b_exp; a and b are words, low word first */
static DB_VALUE_COMPARE_RESULT
numeric_compare_magnitude (const uint64_t * a, int na, int a_exp, const uint64_t * b, int nb, int b_exp);
```
- NUMERIC 은 (계수 워드, −scale)로 넣는다. scale 범위 −214..252 와 floating NUMERIC 40자리 계수(136비트)를 그대로 받는다. 최단 십진수는 (m, e), |d| ≥ 2^53 정수는 (c << q 의 워드, 0) 으로 넣는다.
- 순서: (1) 0 처리 (2) 지수가 같으면 워드 비교 (3) **자리 위치 먼저**: 비트 길이로 구한 floor(log10) 의 하한·상한(±1)이 겹치지 않으면 결정 (4) 겹치면 지수가 큰 쪽에 10^(차) 를 곱해 정렬해 비교한다. 위치가 같으므로 차 ≤ 41 이고 결과는 다른 쪽 크기(≤ 1024비트) 안에 든다. 양쪽이 128비트 안이면 u128, 아니면 S1-3 의 워드 연산(`numeric_words_mul_pow10`, `numeric_words_compare`, 워드 수 `NUMERIC_EXACT_WORDS` — |d| ≥ 2^53 의 정수를 위해 17로 늘림 [VERIFY]).
- S1-3 의 `numeric_compare_u64_magnitude (value, buf, scale)` 를 이 도우미 호출로 바꾼다(u128 빠른 경로는 도우미의 (4) 로 옮김). 중복이 남지 않게 한다.
- #570 (A): NUMERIC × NUMERIC 은 scale 이 같으면 부호 다음 계수를 바로 비교한다(도우미 불필요). scale 이 다르면 이 도우미를 쓴다. `cmpdisk` 직접 비교도 포장 바이트를 워드로 읽어 같은 도우미를 쓴다.
- 누가 쓰나: #569 와 #570 가운데 먼저 커밋하는 쪽이 이 시그니처로 만들고, 다른 쪽이 그대로 쓴다.

## 5. 인덱스 키 범위 — KEEP 경계 + 정확 비교 (2026-10-30 확정)

- 지금 `domain_key_rule`(`domain_rules.c:2195`)은 BIGINT/NUMERIC 열 × DOUBLE 경계에 KEEP 을 답한다(`domain_key_converts_losslessly` 거짓). `pt_decide_key_element`(`xasl_generation.c:14179`)의 KEEP 가지는 "비교가 경계를 변환하면 한 번 변환해 둔다"인데, 새 비교는 conv 가 없어 이 가지가 아무것도 하지 않는다. 그래서 경계는 DOUBLE 값으로 남고, `DOMAIN_KEY_BOUND.compares`(K1)와 `pr_midxkey_compare_element`(K2)가 새 cmpval 로 키와 비교한다.
- 새 비교는 전순서이고 v 는 엄격 단조다. 그래서 "경계보다 크거나 같은 첫 키"를 찾는 B-tree 탐색과 범위 끝 검사가 순차 스캔의 술어 평가와 같은 집합을 낸다. 다중 열 인덱스에서 develop 이 어긋난 것(27799)은 DOUBLE 동등이 키 순서와 맞지 않는 동치(2^53 ≡ 2^53+1)였기 때문이고, 정확 비교에는 그런 동치가 없다.
- **실측 [CONFIRMED, 메커니즘]**: survey install 에서 env `CUBRID_NUMERIC_EXACT_COMPARE` 를 켜면 S1-2(이진 정확값 비교, conv 없음, KEEP) 가 된다. 이때 `keep.sql` 11질의 — 단일 열 `b = 2^53e0`, 범위 `b > 2^53e0 and b < …1000`, 다중 열 (b,id), IN·OR 다중 키(27797), NUMERIC(20,0)·NUMERIC(10,2) 인덱스, `m < 1e20`(오류 없음) — 의 인덱스 경로 답이 `USING INDEX NONE` 과 모두 같았다. env 를 끄면 q1·q3·q6 이 develop 처럼 어긋났다. 비교값 규칙(최단 십진수)은 S1-2 와 값이 다르지만 메커니즘(KEEP + conv 없는 전순서 비교)은 같다.
- 다중 키 정렬·중복 제거·병합(`scan_manager.c` `scan_key_compare` 등)은 DOMAIN_KEY_RANGES 의 셀 비교(K1)를 따른다. 위 smoke 의 q4·q5 가 그 경로다.
- 범위 확장 `merges`(CBRD-27583 사양 14): 새 비교는 `conv[1] == NULL` 이라 `domain_key_compare_merges` 가 거짓(`:2226`)이 되고 확장이 꺼진다. 7.4 에서 정리한다.
- 비용: B-tree 하강과 범위 끝 검사에서 키 비교마다 혼합 cmpval 이 한 번 돈다. develop 도 키마다 BIGINT/NUMERIC→DOUBLE 변환을 하므로 같은 수준이다(3.1·3.2).
- 기각안 (b) 올림·내림: 키 비교가 같은 타입이라 빠르지만 연산자 엄격성 전환(`>` → `>=`), 정확/부정확 표지, 도메인 밖의 빈/전체 범위 같은 새 코드가 생기고 답은 (a) 와 같다. 키 범위가 성능 병목으로 측정되면(#572) 그때 다시 본다.
- ADR 0037 결정 3 의 "비교값을 키 도메인으로 올림·내림해 범위를 만든다"는 답(빈 범위·전체 범위·NONE 과 같음)을 기술하는 문장으로 고쳤다. 구현은 이 절을 따른다.

**자리별: 키 범위·다중 키 판정이 같은 cmpval 로만 정해짐** [CONFIRMED 코드, develop]

| 판정 | 자리 | 비교가 닿는 곳 |
|---|---|---|
| 단일 열 경계 vs 키 | `btree.c:23627` 부근 `btree_compare_bound_key` | DIRECT 이면 `compares->cmp->cmpval`, 아니면 `domain_compare_decided` → 같은 cmpval |
| 다중 열 경계 vs 키, 뒤 열 범위 (27799) | 같은 함수의 MIDXKEY 가지 → `pr_midxkey_compare_resolved (…, domain_key_bound_element_compare, compares)` | 열마다 `domain_compare_decided (&compares[column])` (`domain_rules.c:3052-3059`) → cmpval. 앞 열이 정확 × 근사여도 그 열의 동등은 cmpval 의 EQ 하나뿐이라 뒤 열 범위는 그 안에서만 열린다 |
| 거울(키가 왼쪽) | `DOMAIN_KEY_BOUND.reversed`, `domain_compare_mirror` | 같은 쌍의 전용 cmpval(뒤집힌 방향) |
| 다중 키 정렬·중복 제거·병합 (27797) | `scan_manager.c:1107` `scan_key_compare`, `:1248` `eliminate_duplicated_keys`, `:1284` `merge_key_ranges`, `:1410` `check_key_vals` | `domain_key_ranges_element_compare` (`domain_rules.c:3062`) → DOMAIN_KEY_RANGES 셀의 `domain_compare_decided` → cmpval. 셀은 K1 로 만들어지므로(`domain_key_pairs_make` `:2565`) 같은 전용 cmpval |
| 범위 확장 | `merges` | 새 쌍에서 거짓(7.4), 범위를 넓히지 않음 |
| 행 시점 K2 다중 열 비교 | `pr_midxkey_compare_element` (`object_primitive.c:7718`) | 3.4 의 K2 가로채기 |

#569 의 optdebug assert 3 이 이 셀들의 cmp 가 전용 PR_TYPE 임을 확인한다. smoke `keep.sql` 의 q3·q3b(뒤 열 범위)와 q4·q5(다중 키)가 이 경로를 지난다.

**비용 확인(1번 세션 조건)**: BIGINT 인덱스 × DOUBLE 경계의 범위 스캔(예: 200만 행 `b > ? and b < ?`, DOUBLE 바인드, 대부분의 행이 범위 안)이 develop 과 같은 수준인지 #569 smoke 항목으로 확인한다.

## 6. 해시 키 — 정확한 쪽 도메인 + 정확한 상

**규칙.** 정확 × 근사 쌍(BIGINT/NUMERIC × DOUBLE/FLOAT)의 해시 키 도메인은 정확한 쪽의 도메인이다. 근사 쪽 값 d 는 **비교값의 정확한 상**으로 바꾼다. 상은 그 도메인의 값 가운데 v(d) 와 같은 값이고, 없으면 "상 없음"이다.
- BIGINT: d 가 정수이고 [−2^63, 2^63) 안이면 (int64) d, 아니면 상 없음. 최단 십진수가 필요 없다(정수가 아닌 d 의 v(d) 는 정수가 아님, census 결론 4 / #566).
- NUMERIC(p, s)(음수 s 포함): v(d) 가 scale s 에서 정확하고 p 자리 안이면 그 값, 아니면 상 없음. floating NUMERIC 쪽이면 v(d) 의 정규형(뒤 0 을 음수 scale 로)을 쓰고, `mht_get_hash_number` 의 floating 정규화(`memory_hash.c:606-633`)와 맞는지 [VERIFY].
- 상 없음 → 그 행은 NULL 키와 같은 길로 간다(anti join 에서는 그 행이 남는 것이 맞다 — 짝이 없으므로): `hjoin_fetch_key` 의 `skip_next`(`query_hash_join.c:2861`). 이 길은 내부 조인에서 짝이 없고 outer 조인에서는 짝 없는 행으로 남는다. null-aware anti join 은 해시 조인에 없다(rg `null_aware` 0) [CONFIRMED]. outer·semi·anti 의 행 보존은 smoke 로 [VERIFY].

**왜 이것이 맞나.** n = v(d) ⇔ 상(d) 가 존재하고 n = 상(d) 이다(상의 정의). 따라서 키 도메인 안의 동등(해시 동일 + `hjoin_compare_key` 재검사, `:2849`)이 새 동등과 정확히 같다. census 가 지적한 "변환된 값끼리 재검사"는 키 도메인이 정확해지면 문제가 아니게 된다.

**적용 자리.**
- 해시 조인: `domain_resolve_hash_key`(브랜치 `domain_rules.c` 2896)가 conv 없음일 때 `tp_more_general_type` 으로 DOUBLE 을 고르는 가지를 바꿔, 이 쌍이면 정확한 쪽 도메인을 고르게 한다. 키 변환은 `hjoin_fetch_key` 의 `tp_value_convert`(`:2808`) 자리에서, 소스가 DOUBLE/FLOAT 이고 키 도메인이 BIGINT/NUMERIC 인 키에 상 변환을 쓴다. 상이 없으면 `skip_next`, 오류는 내지 않는다. 병렬 해시 조인도 같은 `hjoin_fetch_key` 를 쓴다(`px_hash_join_task_manager.cpp`).
- 해시 리스트 스캔: `pt_hash_key_domain`(`xasl_generation.c:7170`)이 같은 규칙으로 키 도메인을 고르고, build·probe 의 키 fetch(`scan_manager.c:3493`, `8105`)가 상 변환과 상 없음 = NULL 키 처리를 따른다. 재검사는 원 술어 그대로다(`:8138`).
- 상 변환 선택은 XASL 에 실린 두 도메인(소스 도메인, 키 도메인)만으로 정해지는 순수 함수다. 서버가 새로 결정하지 않고, XASL 필드도 더하지 않는다.
- 해시 GROUP BY·memoize·서브쿼리 캐시·결과 캐시는 한 도메인 키라 해당 없다(census 3.4). HASH 파티션 가지치기는 바꾸지 않는다(census 3.3; IN 리스트 가지치기는 `pt_comparison_keeps_key` 가 conv 없음으로 참이 되어 따라온다).
- 비용: BIGINT 쪽은 develop 의 BIGINT→DOUBLE 변환 대신 DOUBLE→BIGINT 정수 판정이다(같은 수준). NUMERIC 쪽은 DOUBLE 행마다 최단 십진수(#563 측정 41.8 ns)와 NUMERIC 조립이 든다. develop 은 NUMERIC 행마다 NUMERIC→DOUBLE 변환을 했다. #572 에서 잰다.

## 7. 커널을 거치지 않는 자리

### 7.1 NULLIF (census 3.3)
`pt_is_op_with_forced_common_type`(`type_checking.c:21083`)가 NULLIF 피연산자에 공통 타입 CAST 를 씌운다. 그래서 서버가 DOUBLE × DOUBLE 로 비교한다. 정확 × 근사 쌍이면 **비교는 원 피연산자로**, **결과만 공통 타입(DOUBLE)으로** 하도록 바꾼다. 클라이언트는 이 쌍에 CAST 를 씌우지 않고 반환 타입만 DOUBLE 로 둔다(`pt_expr_get_return_type` `:6472` 는 그대로). 서버 NULLIF(`fetch.c:1044`, 결정 비교 `stream_to_xasl.c:7528-7565`)는 원 값으로 비교한 뒤, 같지 않으면 첫 피연산자를 결과 도메인으로 변환해 돌려준다. 상수 접기(`type_checking.c:17486`)도 같은 순서를 따른다. 기대: `nullif(b, 2^53e0)` 에서 b = 2^53+1 이면 9.007199254740992e15, b = 2^53 이면 NULL. LEAST/GREATEST 는 바꾸지 않는다(census: 답 불변).

### 7.2 `qo_reduce_equality_terms` (`query_rewrite_term.c:973-1000`, 강제 변환 `:994`)
NUMERIC(매개변수 타입) 열 × DOUBLE/FLOAT 상수이면 `tp_value_cast_force` 대신 6장의 **정확한 상**을 쓴다. 상이 있으면 그 값을 복사하고(T01 `n = 12345678901234568e0 and m = n` → 1행), 없으면 이 항을 축약하지 않고 그대로 둔다. 그러면 커널이 거짓을 답한다(`n NUMERIC(10,2) = 1e20` → 오류 없이 0행). BIGINT 열은 지금처럼 상수를 그대로 복사한다(census T04: 일관). 문자열·BIT 등 다른 매개변수 타입은 그대로 둔다.

### 7.3 리터럴 고정 (`expr_compile.c:2765-2782`)
새 비교는 conv 가 없어 "오른쪽 리터럴을 왼쪽 타입으로 한 번 바꿔 고정"이 꺼진다. develop 에서 고정되던 **DOUBLE 열 × NUMERIC/BIGINT 리터럴**(예: `d < 10.5`)이 행마다 혼합 비교가 되어 develop 보다 느려진다. 그래서 이 쌍에 고정을 둔다.
- 리터럴 c 에 대해 c = v(d0) 인 DOUBLE d0 가 있으면(대부분의 짧은 리터럴), c 를 d0 로 고정한다. 그러면 모든 d 에 대해 c ⋈ v(d) ⇔ d0 ⋈ d 다(v 의 엄격 단조).
- 고정된 잎(leaf)은 DOUBLE 로 비교하되 NaN 을 가장 큰 값으로 둔다(`d != d` 검사 하나, 또는 NaN 행만 일반 경로). develop 의 빠른 DOUBLE 잎을 그대로 쓰면 NaN 에서 전순서와 어긋난다.
- c = v(d0) 인 d0 가 없으면(17자리 이상 리터럴, 범위 밖) 고정하지 않는다.
- optdebug: 고정된 잎의 답을 해석 경로(혼합 cmpval)와 대조한다(`eval_assert_operator_function` 과 같은 방식).
- BIGINT/NUMERIC 열 × DOUBLE 리터럴(`n < 0.05e0`)은 develop 도 열 쪽을 행마다 변환했으므로 고정하지 않는다(3.2 비용 = develop). FLOAT 열은 빠른 잎 타입이 없어 고정하지 않는다.

### 7.4 CBRD-27583 사양 14 정리 (제거 범위)
- `domain_key_compare_merges`(`domain_rules.c:2212-2236`)의 `type == DB_TYPE_NUMERIC && target == DB_TYPE_DOUBLE` 분기(`:2229-2233`)를 지운다. NUMERIC 인덱스 키를 DOUBLE 로 바꾸는 비교가 더는 없다.
- `DOMAIN_KEY_BOUND.merges` 주석(`domain_rules.h:586`)의 예 "(BIGINT into DOUBLE)" 을 남는 경우로 바꾼다. 남는 경우는 인덱스 쪽 변환이 같은 키를 만드는 것, 곧 문자열 키를 TO_DOUBLE 로 바꾸거나 다른 collation 으로 비교하는 것이다.
- 범위 확장 기계(`btree.c:5439`, `:5768`, `:5845`, `:5860`, `:20408`)와 `merges` 직렬화는 문자열·collation 경우에 계속 쓰이므로 남긴다.
- optdebug assert: 정확 × 근사 쌍의 비교에서 `merges` 가 참이면 assert 한다(`xasl_generation.c:14628` 결정 지점).

### 7.5 `domain_resolve_compare`
develop 에서 호출 경로가 없다(census 2장; 브랜치는 S1-2/S1-3 이 손댐). 브랜치 HEAD 에서 code-index `callers` 로 0 을 다시 확인한 뒤 지운다 [VERIFY].

### 7.6 SHORT/INTEGER × FLOAT
`domain_compute_comparison` 의 `SECOND_TO_FIRST/FIRST_TO_SECOND`(정수 → FLOAT) 대신 TO_DOUBLE 과 같은 모양(양쪽 conv → DOUBLE, `cmp = tp_Double`)으로 한다. 두 변환 모두 무손실이라 `merges` 거짓, 바인드 rule cast 는 DOUBLE, 해시 키 DOUBLE 이 모두 맞다. K2 도 같은 쌍을 양쪽 DOUBLE 로 바꾼다.

## 8. CS 모드에서 결정 공유

- 비교: XASL 에는 method(DIRECT), 두 source 타입, collation 이 이미 실린다(`xts_pack_decided_compare`). 서버는 풀 때 `domain_compare_cmp (source0, source1, …)` 로 같은 cmp 를 얻는다. 직렬화 형식은 바뀌지 않는다. 바뀌는 것은 같은 바이너리 안의 순수 함수 하나뿐이다.
- 키 범위: KEEP 결정과 경계 도메인은 지금처럼 XASL 에 실린다.
- 해시 키: 키 도메인은 XASL 에 실리고, 상 변환 여부는 (소스, 키) 도메인의 순수 함수다(6장).
- 그래서 env 게이트를 두면 안 된다. 클라이언트(CAS/csql 의 XASL 생성)와 서버가 같은 타입 쌍에 다른 cmp 를 고를 수 있다. 예를 들어 클라이언트는 KEEP + conv 없음으로 XASL 을 만들었는데 서버는 tp_Double cmpval 로 풀면 BIGINT 값을 DOUBLE 로 읽게 된다. ADR 0038.

## 9. #568 과의 인터페이스

- 시그니처 변경 요구 없음. 비교 함수(3장)는 `numeric_opfunc.c` 안에서 정적 `numeric_shortest_decimal_of_double/float` 를 직접 부른다.
- `numeric_double_to_compare_num`/`numeric_float_to_compare_num` 의 `NUMERIC_COMPARE_VALUE_OUT_OF_RANGE` 는 "어떤 NUMERIC 도 그 값과 같지 않다"는 뜻이 아니다. [CONFIRMED] `numeric(10,-2)` 열이 만들어지고, floating NUMERIC `3022314549036572936765440000000000000000000000`(= 2^100·5^22, 정확한 double)이 develop 계열 빌드에서 그 DOUBLE 과 같다고 답한다(`smoke/out4/neg.negscale.out`). 해시 키 상 변환(6장)이 이 함수를 쓰면 음수 scale 상을 만들어야 한다.
- FLOAT |f| ≥ 2^24 정확 정수 규칙은 #568 이 이미 구현했고 1번 세션이 확정했다(ADR 0037 결정 5). OUT_OF_RANGE 의미는 1번 세션이 4번 세션에 전달한다.

## 10. #569 구현 지시 (요약 — 본문은 #569 이슈)

자리별 변경은 2·3·5·6·7장, assert·smoke 는 아래와 같다.

**optdebug assert**
1. 3.2·3.3: 띠 밖 판정과 정확 경로의 답이 같다. **CTP 전체에서 0회 발화가 게이트 조건이다.**
2. 7.3: 고정된 잎의 답과 해석 경로(혼합 cmpval)의 답이 같다.
3. `stx_unpack_decided_compare`·`domain_compare_mirror`·`domain_compute_comparison` 뒤: 정확 × 근사 쌍이면 cmp 가 전용 PR_TYPE 이고 conv 가 둘 다 NULL 이다.
4. 7.4: 정확 × 근사 쌍의 `merges` 는 거짓이다.
5. 해시 키 결정(`domain_resolve_hash_key`, `pt_hash_key_domain`): 정확 × 근사 쌍의 키 도메인은 DOUBLE/FLOAT 가 아니다.
6. 옛 경로 hit 수: 이 쌍이 `tp_value_compare_common_domain` 의 DOUBLE/FLOAT 변환 가지에 닿는 횟수가 gdb 로 0 이다(smoke 전체).

**smoke (SA·CS optdebug, 리드)**
- census 프로브 `scratch/cbrd27819/565/smoke/p1–p4.sql`, #566 프로브 `566/probe1–7.sql`, 이 문서의 `567/smoke/keep.sql`, CBRD-27797/27799/27703 Repro. 기대값은 ADR 0037 두 표.
- 인덱스 = NONE 짝: 단일·다중 열, IN/OR, NUMERIC(p,s)·음수 scale, NaN·inf·-0, 1e20, 1e-300.
- 해시 조인(`USE_HASH`) inner / left outer / semi(IN 서브쿼리) / anti(NOT EXISTS): 상 없는 DOUBLE(0.5e0, 1e300, NaN)의 outer 행 보존, BIGINT·NUMERIC(10,2)·floating NUMERIC 키; 해시 리스트 스캔.
- 해시 상 없음의 결과: inner 0행, left outer 는 그 행 + NULL, semi(IN) 0행, anti(NOT EXISTS/NOT IN) 는 그 행이 남는다.
- BIGINT 인덱스 × DOUBLE 경계 범위 스캔 비용이 develop 과 같은 수준(같은 데이터·질의를 번갈아 측정, 5장 조건).
- `d < 10.5` 리터럴 고정: DOUBLE 열 인덱스 경로와 `USING INDEX NONE` 순차 경로가 같은 답인지 TC 짝으로 확인(NaN·inf 행 포함).
- NULLIF 상수·열, `qo_reduce_equality_terms` T01·`n = 1e20`, RANGE/LIST/HASH 파티션 SELECT·DELETE, JSON S06, 16777217 × FLOAT(INT·BIGINT), 1073741824 × FLOAT(BIGINT·NUMERIC).
- CS 전용: 병렬 해시 조인·병렬 merge join·px_scan 이 같은 답(병렬 힌트).

**게이트(워커)**: release·optdebug 빌드, CTP sql·medium 전체 + shell 의 파티션·인덱스·numeric 디렉터리(`just ctp`, `PR=`/`TC_REF=` 명시), core·assert·leak 0. 답이 바뀐 CTP 케이스는 목록으로 남긴다.

## 11. 검증하지 않은 것

- KEEP 메커니즘 smoke 는 S1-2(이진 정확값) 빌드에서 했고 비교값(최단 십진수) 빌드에서는 하지 않았다. 메커니즘은 같지만 #569 에서 다시 잰다.
- 3.2 의 오차 상한은 코드에서 도출한 것이다. glibc `pow` 의 1 ulp 는 문서상 값이다. optdebug assert 1 이 CTP 규모로 확인한다.
- 해시 조인 상 변환·NULLIF·리터럴 고정의 비용은 재지 않았다(#572).
- CS 병렬 경로는 코드로 같은 함수를 쓰는지만 확인했다(census 그대로).
