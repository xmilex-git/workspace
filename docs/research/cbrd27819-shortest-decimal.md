# 가장 짧은 왕복 십진수의 자체 구현 — 알고리즘·표·비교 경로 (workspace #563, 지도 #562)

2026-10-30. 질문: DOUBLE/FLOAT 의 가장 짧은 왕복 십진수(GLOSSARY "NUMERIC 표현")를 외부 소스 없이(ADR 0036) 구현할 때 무엇이 필요하고, 비교값(ADR 0037)·CAST 경로에 맞춘 최적화는 무엇인가. Sonnet 워커가 논문만 읽고 프로토타입을 만들어 엔진 `_dtoa` 와 대조한 결과를 리드가 1시간 시점에 중단해 정리했다(워커는 문서를 쓰기 전이었다). 금지 파일(PG `d2s.c` 계열, survey 이식본, `dtoa_vs_ryu.cpp`, ulfjack/ryu)은 열지 않았다(워커 기록 `prohibited_files_touched`: 해당 없음 — 중단 전이라 구조화 보고는 없고 툴 호출 기록으로 확인).

산출물(모두 `.git_ignored_dir/scratch/cbrd27819/research/`): 프로토타입 `proto/sf.h`(+`g_tab.h`, `gen_tables.py`, `tabgen.cpp`), 대조 하네스 `proto/harness_double.cpp`·`harness_float.cpp`·`oracle_check.py`·`oracle_f32.cpp`, 검산 `proto/intcheck.cpp`·`matula.cpp`·`numconv.cpp`·`numconv2.cpp`·`twostep_check.py`, 결과 `work/*.out`. 논문 메모 `papers/`, `work/{schubfach,dragonbox,grisu,errol,gay}.txt`.

## 1. 결론

1. **Schubfach(Giulietti, "The Schubfach way to render doubles", 3·5–9절, optimal variant M=1)** 를 논문 정의에서 128비트 정수 연산으로 새로 쓴 프로토타입(`sf.h`, 약 120줄)이 엔진 `_dtoa` mode 0 과 **31,945,790 double 에서 불일치 0**(`work/double_full.out`), 정확 유리수 oracle(Python `fractions`) 과도 모든 부류에서 0. float32 는 **2^31 전수(지수 0~254, 2,139,095,039 패턴)에서 정확 oracle 과 불일치 0**(`work/float_exact_exhaustive.out`, 197 s).
2. 속도: 프로토타입 **41.8 ns/호출**, 엔진 `_dtoa` mode 0 **3,609 ns/호출**(같은 입력, 같은 호스트; 부류별 32~77 ns 대 540~4,907 ns). 행마다 부르는 경로에서 JIRA 프로파일의 dtoa 큰 수 연산·할당이 사라진다.
3. 표: `g(k) = floor(10^-k / 2^r) + 1`(r = floor(log2 10^-k) − 125), k = −324..292 의 **617 항목 × 128비트 = 9.9 KB**. 저장하지 않고 **시작 시 생성도 가능**: 평범한 C 24-limb 정수로 28 ms, Python 생성본과 617/617 동일(`work/tabgen.out`). float32 는 같은 표를 상위 64비트로 줄여 쓴다(`sf_float`).
4. 곱셈: double 1회 변환에 64×64→128 곱 **6회**(`sf_vbar64` 3회 × 2), float 3회. 분기는 짧은 경로(s ≥ 10 일 때 10의 배수 후보) 둘과 u/w 포함 판정.
5. **CAST 경로(16자리 절단, FLOAT 7자리 절단)** 는 같은 함수의 결과(유효숫자 m, 지수 e)를 자른 뒤 NUMERIC 으로 조립하면 되고, 결과는 `_dtoa` mode 0 절단과 같다(자릿수가 같으므로). FLOAT CAST 는 develop 이 **DOUBLE 로 넓힌 값**의 mode 0 을 7자리에서 자르므로(`numeric_opfunc.c:4975`, `TP_FLOAT_MANTISA_DECIMAL_PRECISION`), 결과 불변을 지키려면 FLOAT CAST 는 `sf_double((double) f)` 를 써야 한다. float32 자체의 가장 짧은 십진수(`sf_float`)는 **비교값에만** 쓴다(지도 결정 Q13). 둘은 2^24 이상 정수·큰 홀수 가수에서 다르다(`work/oracle_float.out`: 정수 2^24..2^50 의 88%, 큰 홀수 가수의 50%).

## 2. 알고리즘 후보 비교 (논문 설명에서; 코드는 어느 것도 보지 않음)

| 후보 | 표 | 곱 | 정확성 근거 | 짝수 가수 경계(=`_dtoa` mode 0) | float32 | 비고 |
|---|---|---|---|---|---|---|
| **Schubfach** (Giulietti 2020/21) | 617 × 128비트, 생성 가능 | 6 | 논문 5–9절의 정수 증명(ε 경계) | 논문 정의 그대로(`outb = c & 1`) | 같은 표 축소 | 분기 적고 루프 없음 — **채택 후보** |
| Ryu (Adams, PLDI 2018) | 5^k 역/정 표 2개(≈10 KB), 생성 가능 | 3×(2~3) + 자릿수 루프(최대 17회 나눗셈 10) | 논문 정리 | 상수로 선택 | 별도 표 | 루프가 길고 표 둘; 코드 구조를 Ryu 소스와 다르게 짜도 "Ryu" 라는 설명은 남는다 |
| Dragonbox (Jeon) | Schubfach 와 같은 표 | Schubfach 와 비슷 | 저자 증명(비공식 발표) | 지원 | 지원 | Schubfach 의 변형, 추가 이득은 짧은 가수 특수화 |
| Grisu3 (Loitsch 2010) | 87 × 64비트 | 2~3 | 0.5% 입력에서 실패 → fallback 필요 | 가능 | 가능 | fallback(`_dtoa`) 이 남아 제외 |
| Errol / Dragon4 | 큰 정수 | 많음 | 정확 | 가능 | 가능 | 느림(현행과 같은 부류) |

선택 근거: CUBRID 제약(cs/sa 에서 `cc` 로 컴파일되는 C, 외부 소스 없음, `_dtoa` mode 0 과 자릿수 동일, 행마다 호출)에서 Schubfach 가 표 하나·루프 없음·증명이 논문에 있음으로 가장 단순하다. 프로토타입이 이미 그 선택을 검증했다.

## 3. 비교 경로 최적화 — 증명과 반례

### 3.1 두 단계 비교의 조건 (`twostep_check.py`, `numconv*.out`)
주장: nearest(n) < d ⇒ n < shortest(d). 근거: 가장 가까운 double 로의 반올림은 단조이고 shortest(d) 는 d 로 반올림되므로, n ≥ shortest(d) 이면 nearest(n) ≥ nearest(shortest(d)) = d. **단, nearest(n) 이 정확히 반올림된 값일 때만** 성립한다. 엔진의 NUMERIC→DOUBLE(`numeric_coerce_num_to_double`: fl(fl(C)/fl(10^s)))은 정확 반올림이 아니다 — 계수 1~40자리·scale −214..252 의 1억 쌍에서 **최대 2 ulp 오차**(1 ulp 이상 31%, 2 ulp 0.23%; `work/numconv2.out`). 오차 0 인 부류는 "scale 0" 또는 "계수 < 2^53 이고 scale ≤ 22"(`work/numconv.out`) 뿐이다.
→ 설계(#567)의 선택지: (가) 비교 전용 정확 반올림 NUMERIC→DOUBLE 을 새로 쓰거나(128비트 계수 / 10^s 를 정확 반올림 — 정수 나눗셈 1회 + 반올림 판정), (나) 현행 변환을 쓰되 |ulp 차| ≤ 2 이면 가장 짧은 십진수 경로로 떨어지는 보호 띠, (다) 두 단계를 버리고 항상 십진수 경로(41.8 ns — 이미 현행 DOUBLE 비교의 변환 비용과 같은 자릿수). (다)가 가장 단순하고 증명이 필요 없다.

### 3.2 정수 DOUBLE 의 지름길 — **반례 있음** (`intcheck.out`)
"지수 ≥ 0 인 DOUBLE 의 가장 짧은 십진수는 그 정수 자체" 는 **|d| < 2^54 에서만** 참이다. 가장 작은 반례 18014398509481992 (= 2^54 + 8) → 1801439850948199e1 (= …990). 2^57 = 144115188075855872 → 14411518807585587e1 (= …870); [2^59, 2^63) 에서 표본 4천만 개 **100%** 가 정수와 다르다. 1e17 은 1e17 이고 2^53 은 자기 자신이다.
→ **사양 결과(#566 에 올림)**: ADR 0037 의 규칙(비교값 = 가장 짧은 십진수)을 그대로 두면 `144115188075855872 = 144115188075855872e0` 이 **거짓**(develop 참, 수학적으로도 참)이고 `144115188075855870 = 144115188075855872e0` 이 참이 된다. 즉 2^54 이상의 정수 DOUBLE 에서는 (C)가 정확값보다 덜 정확하다. 대안: 비교값을 "|d| ≥ 2^53(모든 double 이 정수)이면 정확한 정수값, 그 아래는 가장 짧은 십진수" 로 두는 혼합 규칙 — 단조성은 유지된다(두 값 모두 d 의 반올림 구간 안에 있고 구간은 겹치지 않음). 이 선택은 사용자 결정.

### 3.3 Matula 경계 (`matula.out`)
15자리 십진수는 double 로 항상 왕복(실패 0/4천만), 16자리 9.2% 실패, 17자리 83% 실패; float 는 6자리 왕복, 7자리 0.12% 실패, 8자리 70% 실패. 따라서 "NUMERIC n 이 어떤 double 의 가장 짧은 십진수와 같다" 는 n 이 16자리 이하일 때만 흔하고, 17자리 NUMERIC 은 대부분 어떤 DOUBLE 과도 같지 않다 — ADR 0037 의 `0.10000000000000001 = 0.1e0` 거짓이 그 예.

### 3.4 비용
현행 열 대 열 비교는 행마다 NUMERIC→DOUBLE 변환(`numeric_coerce_num_to_double`, 나눗셈 1회) + DOUBLE 비교. 새 경로 (다)는 행마다 `sf_double`(41.8 ns) + 정수 비교(계수·scale 정렬, 10^k 표 곱 1회). survey S1-2 의 정확 비교(변환 없음)가 0.79배였으므로, 십진수 생성이 붙어도 JIRA AC(1.5배)는 여유가 크다 — 실측은 #572.

## 4. 검증 계획 (#568 완료 조건)
- 엔진 밖 독립 프로그램(단위 테스트 아님): (1) `_dtoa` mode 0 대 자체 구현, 입력 부류 — 무작위 비트 패턴, 2^(e−1074)±1 ulp(e < 1100), 10^e±1 ulp(−320 ≤ e ≤ 308), i/1000·i×0.1(i < 2M), 2^53+2i, 무작위 정수 ≫ 무작위 시프트, 17자리 이하 무작위 십진수, [2^53, 2^93)+0..3 ulp — 프로토타입 하네스 `harness_double.cpp` 가 이 부류로 31,945,790 개를 만든다; (2) float32 2^31 전수 대 정확 oracle(`oracle_f32.cpp`, 197 s) **과** `_dtoa((double) f)` 7자리 절단 대 새 CAST 경로(결과 불변 증명용); (3) 옛 CAST 경로 대 새 경로(prec·scale·부호·계수) — survey 의 106,772,134 쌍 방식 재사용(`harness/old_vs_new.cpp` 의 생성 방식만); (4) NaN·inf·0·denormal 은 알고리즘 밖에서 특수 처리하므로 각각 고정 케이스로.
- 엔진의 `_dtoa` 는 `src/base/` 의 David Gay 구현(이미 저장소 안, 변경 없음)을 하네스가 링크한다.

## 5. 리드가 정할 것
1. (3.2) 2^53 이상 정수 DOUBLE 의 비교값: 가장 짧은 십진수(ADR 0037 그대로) vs 정확 정수값(혼합 규칙) — **#566 경계 사양**.
2. (3.1) 두 단계 비교를 쓸지, 쓰면 정확 반올림 변환을 새로 쓸지 — **#567**. 권고: 항상 십진수 경로((다)), 측정 뒤 필요할 때만 두 단계.
3. 표를 헤더 상수(9.9 KB)로 둘지 시작 시 생성(28 ms, `tabgen.cpp`)할지 — 권고: 헤더 상수(생성기 스크립트를 저장소에 두고 주석으로 생성식 명시).
4. FLOAT CAST 의 결과 불변(DOUBLE 로 넓힌 값의 7자리)을 유지할지, FLOAT 의 가장 짧은 십진수로 바꿀지(`cast(92003296f as numeric)` 92003290 → 92003300 류의 변화) — 지도 결정 Q2-2 는 유지.

## 6. 검증되지 않은 것
- 프로토타입은 scratch 품질이다: 부호·0·inf·NaN·denormal 처리는 하네스가 알고리즘 밖에서 걸렀고(`add()` 가 제외), 엔진 코드로 옮길 때 다시 다룬다.
- 속도는 단일 코어·캐시 뜨거운 상태의 ns/호출이며 호스트 부하 미기록.
- 논문 메모(`work/*.txt`)는 워커가 웹에서 읽은 내용의 요약이고 리드가 원문을 다시 열지 않았다; 표의 Ryu·Dragonbox 곱셈 횟수는 그 메모에 의존한다.
- 워커의 구조화 보고가 없어 "금지 파일을 열지 않았다" 는 툴 호출 기록(Read/Bash 인자)으로 확인한 것이다.
