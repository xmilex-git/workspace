# Q3 격차 규명 — 플랜형(옵티마이저 오선택형), 새 범주

`contract_revision: 2` (원칙 v2 적용 첫 보고서).
트랙 **SINGLE_QUERY_REPEAT** (ADR 0016 하위 레짐) — `PER_QUERY_CONNECTION_DIAG`(구 G2) 값과 같은 표에 합치지 않는다.
`connection_mode`: wall 세트 = `per-query-connection`, CPU/프로파일 세트 = `single-connection-n-statements`.
metadata: `.git_ignored_dir/q3/raw/*/meta.json` (10세트), raw manifest·백업 `docs/MANIFEST-raw-evidence.md`.

**상태: `measured, correctness-unverified`.** SF1 reference correctness는 수행하지 않았다(ADR 0020 §7) — 이
보고서의 어떤 항목도 "완료"가 아니다. 대체 채증은 **양쪽 엔진 결과 동일성**(top-10 `l_orderkey`·`revenue`·
`o_orderdate`·`o_shippriority` 전부 일치)과 **노드별 실제 행수 일치**뿐이며, 이는 correctness의 하위 증거다.

---

## 결론 5줄

1. **Q3는 새 범주 `플랜형(옵티마이저 오선택형)`이다.** 기존 다섯 범주(플랜형-Q21 / 행당형-Q1·Q9 /
   행당+단위손실-Q8 / 규칙파열-Q18 / 필터지배형+양쪽 단위붕괴-Q15) 어디에도 들어가지 않는다.
   `2.2573x [wall] = 플랜 1.2465x [wall] × 실행단위 0.7986x [time-weighted active units 비] ×
   행당 2.2676x [질의실행분 CPU-초 비]`, 검산 오차 **0.00 %**.
2. **CUBRID의 총 CPU-초는 플랜 형상과 무관하다** — idx-NL 47.30 s ↔ USE_HASH 47.60 s(**0.6 %**).
   따라서 플랜 축 1.2465x는 "일이 줄어서"가 아니라 **실행 단위가 5.61 → 7.05로 늘어서** 생기며,
   configured cap 6으로 정규화하면 두 형상이 동률(7.95 s ↔ 7.93 s)이다. **CUBRID에게 플랜 선택은
   시간을 바꾸지만 일을 바꾸지 않는다.**
3. **형상 일치 배수가 둘로 갈리는 첫 쿼리다** — PG 형상에서 **1.8109x [wall]**, CUBRID 형상에서
   **1.1826x [wall]**. CUBRID의 인덱스 NL 경로는 PG 대비 `cycles` **1.234x**로 거의 대등하고
   (버퍼 1.19x / B-tree 1.10x), 해시 경로는 **2.549x**로 벌어진다. **어느 형상에서 재는지가 배수를 결정한다.**
4. **`instructions` 비가 두 번째로 하한이 된다** — 1.9522x < wall 2.2771x이고 **IPC 비 0.799**
   (CUBRID 1.55 / PG 1.94)로 ±20 %를 벗어난다 → `instructions` 기반 서술 금지(ADR 0019 §2).
   `cycles` 2.4397x가 정본이고, wall 대비 잔차 +7.1 %는 유효 클럭 비(2.476/2.289 = 1.0817)와
   time-weighted active units 비(1.0098)로 2 % 내에 닫힌다.
5. **`cycles`에서 버퍼 고정·래치 역전이 다섯 번째로 재현**된다(instr 2위 31.0 % → cycles 2위 47.5 %,
   **절대 델타가 28.31 → 33.57 G로 증가**해 1위 B-tree 49.3 %와 1.8 %p 차로 동률화). 뿌리는
   **플랜이 버퍼 페이지를 27.79배 더 만진다**는 것이다 — CUBRID 39,538,926 page fix ↔ PG 1,422,457
   buffer access. 형상을 맞추면 39.54 M ↔ 36.13 M(**1.094x**)로 붙는다.

---

## 0단계 — configured-cap parity 채증 (원칙 v2 §4)

"6 실행 단위 파리티"라는 표현을 폐기하고 아래 5개 축을 분리 기록한다.

| 축 | CUBRID cubN(정본) | CUBRID cubH(A/B) | PG pgN(정본) | PG pgNL(A/B) |
|---|---|---|---|---|
| configured cap (노드 단위) | `parallelism=6` | `parallelism=6` | `max_parallel_workers_per_gather=5` (+leader=6) | 동일 |
| configured cap (전역 예산) | **`max_parallel_workers=100`** | **100** | **`max_parallel_workers=8`** | 8 |
| planned | trace `parallel workers: 6` | 노드별 중첩 `6 / 3 / 5 / 6 / 2 / 2` | `Workers Planned: 5` | `Workers Planned: 5` |
| launched | `parallel-query` tid **6** | tid **16**(생성 누계) | `Workers Launched: 5` (5회 전부) | `Workers Launched: 5` |
| 동시 활성 (표본 최대) | **6** | **12** | 6 (leader+5) | 6 |
| time-weighted active units | **5.607 = cap의 93.5 %** | **7.05 = cap의 117.5 %** | **5.605 = 93.4 %** | 5.792 = 96.5 % |
| serial tail | 0.50 s = wall의 **5.9 %** | 0.75 s = **11.0 %** | 385.6 ms = **10.2 %** | (미분리) |
| 라벨 | `병렬 유지` | **`configured-cap 초과`** | `병렬 유지` | `병렬 유지` |

**신규 사실 — `parallelism`은 쿼리 단위 상한이 아니라 노드 단위 상한이다.**
`src/query/parallel/px_parallel.cpp:172 degree = MIN (auto_degree, (UINT32) parallelism)`는 노드마다
독립 적용되고, 쿼리 전체 예산은 `src/query/parallel/px_worker_manager_global.cpp:57-78`의
`PRM_ID_MAX_PARALLEL_WORKERS`(이 구성에서 **100**)다. 즉 현재 파리티 계약은 **노드 단위 cap만 맞추고
전역 예산은 100 ↔ 8(12.5배 비대칭)로 방치**한다. cubH가 동시 12단위까지 올라간 것이 그 비대칭이
실제로 물린 첫 사례다. **이 비대칭은 제거 대상이 아니라 기록 대상**이며(PG 클러스터 기본값 변경 금지),
배수 인용 시 `CUBRID 전역 예산 100 / PG 8`을 명기한다.

표본화 오버헤드(IV=0.25 s): CUBRID cubN **+0.66 %** / cubH **−0.04 %** / PG **−0.40 %** (문턱 5 % 내).
단위-초 검산: cubN 47.75 ↔ 실측 47.30~48.04(**+0.5 %**), cubH 48.75 ↔ 47.60(+2.4 %),
pgN 21.75 ↔ 19.94~20.85(+4.3 %).

---

## 1단계 — 재현·플랜

### 1.1 재현 (WARM AB/BA, 네 변형 인접 배치)

정본 세트 `raw/final` = 6블록 AB/BA(`cubN cubH pgN pgNL` ↔ 역순), 변형 전환마다 warmup 1회 미집계.
**블록 6은 무효**다 — 배경 부하 loadavg가 9.9 → **33.15**로 튀었다(같은 장비의 다른 세션
`bun /home/cubrid/.bun/bin/gjc`, affinity 0-31). 유효 블록 B1–B5.

| 변형 | wall mean [s] | sd | n | 최대 sda read |
|---|---|---|---|---|
| cubN (정본 idx-NL) | **8.3754** | 0.1034 | 5 | 0.5 MiB |
| cubH (`/*+ USE_HASH */`) | 6.7192 | 0.0962 | 5 | 0.2 MiB |
| pgN (정본 hash) | **3.7104** | 0.0354 | 5 | 0.0 MiB |
| pgNL (강제 idx-NL) | 7.0824 | 0.0664 | 5 | 0.0 MiB |

블록 내 배수 산포(드리프트 면역): `cubN/pgN` 2.2163 / 2.2207 / 2.2697 / 2.2875 / 2.2932.

| 세트 | 하위 레짐 | CUBRID | PG | 배수 [wall] |
|---|---|---|---|---|
| `raw/final` B1–B5 (정본) | single-query-repeat | 8.3754 s | 3.7104 s | **2.2573x** |
| `raw/s1` AB/BA 3블록 | single-query-repeat | 8.681 s | 3.594 s | 2.4155x |
| `PER_QUERY_CONNECTION_DIAG` 대조 | stream | 8.6153 s (sd 0.0304) | 3.6997 s (sd 0.0232) | 2.3285x |

**세 값의 폭(2.257~2.416x)은 하위 레짐 차가 아니라 between-session drift다**(ADR 0010).
근거: §1.3의 버퍼 카운터가 두 레짐에서 **완전히 동일**하고, 세션 진행에 따라 CUBRID는 8.681 → 8.375 s로
단조 감소, PG는 3.594 → 3.710 s로 증가했으며 그 사이 loadavg가 5.0 → 9.7로 올랐다.

### 1.2 플랜 전체 덤프·노드 대조

**형상이 네이티브로 완전히 다르다** — Q15(네이티브 형상 일치)의 정반대다.

| 논리 단계 | CUBRID (trace, SELECT 11,498 ms) | PG (`EXPLAIN ANALYZE`, 3,791 ms) |
|---|---|---|
| customer 접근 | `iscan pk_customer_c_custkey` (inner, 7.29 M 재탐색) | `Parallel Seq Scan` + `Parallel Hash` (build) |
| orders 접근 | `sscan dba.orders` **parallel workers 6**, heap 11,077 ms | `Parallel Seq Scan`, 355.7 ms/worker |
| lineitem 접근 | `iscan pk_lineitem_l_orderkey_l_linenumber` (inner, 1.46 M 재탐색), btree 2,684 + lookup 1,100 ms | `Parallel Seq Scan`, 1,487.7 ms/worker |
| 조인 방법 | `idx-join` × 2 (인덱스 NL 2단) | `Parallel Hash Join` × 2 |
| 그룹 | `GROUPBY (time 316, hash: partial, sort: true)` | `Sort` → `Gather Merge` → `GroupAggregate` (직렬) |
| 정렬·제한 | `ORDERBY (time 105)` | `Sort (top-N heapsort 26 kB)` → `Limit` |

**노드별 실제 행수는 자릿수까지 일치한다.**

| 논리 지점 | CUBRID | PG | 일치 |
|---|---|---|---|
| orders 필터 통과 | `readkeys 7,289,440` | 1,214,907 × 6 = **7,289,442** | ✓ (2행 차 = trace 반올림) |
| orders ⋈ customer | `lookup rows 1,461,923` | 243,653.83 × 6 = **1,461,923** | ✓ |
| lineitem 필터 통과 | (정본에선 미노출) cubH `PROBE readrows 32,334,250` | 5,389,041.67 × 6 = **32,334,250** | ✓ |
| 최종 조인 | cubH `PROBE rows 302,114` | 50,352.33 × 6 = **302,114** | ✓ |
| 그룹 | `GROUPBY rows 114,003` | `GroupAggregate rows 114,003` | ✓ |
| 결과 | 10행, 값 동일 | 10행, 값 동일 | ✓ |

### 1.3 추정 카디널리티 대 실제 — **양쪽이 최종 조인을 크게 과대추정한다**

| 지점 | 실제 | CUBRID 추정 | 오차 | PG 추정(×6) | 오차 |
|---|---|---|---|---|---|
| customer 필터 | 300,276 | 304,850 | +1.5 % | 452,712 | **+50.8 %** |
| orders 필터 | 7,289,442 | 7,347,185 | +0.8 % | 8,801,256 | +20.7 % |
| orders ⋈ customer | 1,461,923 | 1,493,193 | +2.1 % | 1,771,104 | +21.1 % |
| lineitem 필터 | 32,334,250 | 32,311,154 | −0.1 % | 38,760,408 | +19.9 % |
| **최종 조인** | **302,114** | **1,547,275** | **+412 % (5.12x)** | **3,813,546** | **+1,162 % (12.6x)** |
| 그룹 수 | 114,003 | 1,547,275 | 13.6x | 3,177,954 | **27.9x** |

단일 술어 추정은 양쪽 다 정확하다. 깨지는 곳은 **`l_orderkey = o_orderkey` 조인과
`l_shipdate > date` · `o_orderdate < date`의 상관관계**로, 양쪽 옵티마이저 모두 독립 가정을 쓴다.
CUBRID의 오차가 더 작은데도(5.12x vs 12.6x) 더 나쁜 플랜을 고른다 — 원인은 추정이 아니라 **비용 모델**이다(§4.1).

### 1.4 ADR 0016 하위 레짐 — **PG는 사실상 무감**

| PG `EXPLAIN (ANALYZE, BUFFERS)` 최상위 | stream | single-query-repeat | 델타 |
|---|---|---|---|
| `shared hit` | 637,063 | 1,046,641 | +409,578 |
| `shared read` | 785,394 | 375,816 | **−409,578 (−52.1 %)** |
| **`hit + read`** | **1,422,457** | **1,422,457** | **0 (완전 동일)** |
| ↳ lineitem 노드 hit/read | 339,734 / 785,394 (잔존율 **30.2 %**) | 749,367 / 375,761 (**66.6 %**) | +36.4 %p |
| `temp read / written` | 153,449 / 153,760 | 153,449 / 153,644 | −0.08 % |
| `Execution Time` | 3,863.330 ms | 3,791.523 ms | **−1.86 %** |
| 구간 sda 물리 read | 0.0 MiB | 0.0 MiB | 양쪽 0 |

**신규 조항 후보 — 잔존율이 크게 움직여도 무감할 수 있다.** ADR 0016의 Q8 정정은 판정 기준을
"버퍼 잔존율이 상태에 따라 움직이는가"로 바꿨다. Q3는 **잔존율이 30.2 → 66.6 %(+36.4 %p)로
Q8(43.3 → 53.3 %)보다 3.6배 크게 움직이는데 `Execution Time`은 −1.86 %**다. 미스 단가
**0.175 µs/미스**로 Q21(0.81) · Q8(2.62)보다 자릿수가 작다. 이유는 이 미스가 전부
`Parallel Seq Scan on lineitem`의 순차 read이고 `io_method=worker` 프리페치가 스캔의
CPU 시간(1,488 ms/worker) 뒤에 숨기 때문이다. → **판정 기준을 "잔존율 이동"에서
"미스 단가 × 미스 감소량이 wall에서 관측되는가"로 좁혀야 한다**(ADR 0020 §5에 등재).

CUBRID는 무감하다: trace `fetch` **29,157,760 / 10,379,864 자릿수까지 불변**,
`ioread` 1,163,268 → 1,091,008(−6.2 %), wall +0.77 %.

---

## 2단계 — 축 분리

### 2.1 3축 분해와 검산 (이벤트 단위 명시, 원칙 v2 §5)

| 축 | 이벤트 단위 | 값 | 측정 방법 |
|---|---|---|---|
| 정본 배수 | **wall** | **2.2573x** | `raw/final` B1–B5, cubN/pgN |
| 플랜 축 | **wall** | **1.2465x** | 같은 엔진 A/B: cubN/cubH |
| 실행 단위 축 | **time-weighted active units 비** (PG/CUBRID) | **0.7986x** | 5.629 / 7.049 (`raw/cpu2` 브래킷) |
| 행당 실행 비용 축 | **질의실행분 CPU-초 비** | **2.2676x** | 형상 일치 쌍(cubH/pgN) CPU 비 2.2828을 final 세트로 정규화 |
| 검산 | — | 1.2465 × 0.7986 × 2.2676 = **2.2573** | **오차 0.00 %** |

**실행 단위 축이 1 미만인 첫 쿼리다.** CUBRID 쪽 A/B 변형이 configured cap을 초과하므로(§0)
이 축은 CUBRID에 유리하게 작동한다. 정본 형상끼리는 **0.9996x로 닫힌다**(93.4 % / 93.5 %).

### 2.2 같은 엔진 A/B — 양방향 성공

| 방향 | 강제 방법 | 형상 일치 채증 | 결과 [wall] |
|---|---|---|---|
| CUBRID → PG 형상 | `/*+ USE_HASH */` | 노드 계열 일치(hash-join×2 + sscan×3, build/probe 방향까지) + 실제 행수 6지점 일치 | 8.3754 → **6.7192 s** = **1.2465x** |
| PG → CUBRID 형상 | `enable_hashjoin/mergejoin/memoize/incremental_sort=off` + `join_collapse_limit=1` + 명시 조인 순서 | `Parallel Seq Scan orders → Index Scan customer_pkey (loops 7,289,442) → Index Scan lineitem_pkey (loops 1,461,923)`, 노드 6개 행수 일치 | 3.7104 → **7.0824 s** = **1.9088x** |

`raw/pair`의 인접 쌍 5회 반복: `cubN/cubH` 쌍비 평균 **1.2546 (sd 0.0187)**,
`pgN/pgNL` 쌍비 평균 **0.5376 (sd 0.0165)** → `pgNL/pgN` **1.8601x**.

**형상 일치 배수를 정본 배수와 병기한다(ADR 0019 §1)** — 둘이 20 % 이상 벌어진다:

> **Q3: `2.2573x [wall]` (형상 일치 **1.8109x**(PG 형상) ↔ **1.1826x**(CUBRID 형상))**

### 2.3 CPU-초 표 — CUBRID는 형상과 무관하게 같은 일을 한다

브래킷 N=3 + settle 2 s (ADR 0017). io worker는 별개 열.

| 세트 | wall [s] | SUT CPU/런 [s] | 질의실행분 [s] | 내부 배경 스레드 | time-weighted units | io worker |
|---|---|---|---|---|---|---|
| cubN (`raw/cpu`) | 8.567 | 48.110 | **48.037** (pq 47.523 / leader 0.513) | 0.073 | 5.607 (93.5 %) | N/A |
| cubN (`raw/cpu3`) | 8.455 | 47.387 | **47.300** (pq 46.807 / leader 0.510) | 0.087 | 5.595 (93.2 %) | N/A |
| cubH (`raw/cpu2`) | 6.752 | 49.697 | **47.597** (pq 7.100 / leader 3.577 / 잔차 36.920) | 2.100 | 7.049 (**117.5 %**) | N/A |
| pgN (`raw/cpu`) | 3.558 | **19.943** (leader 3.483 / workers 16.460) | 19.943 | N/A (별개 프로세스) | 5.605 (93.4 %) | 1.257 s/런 = 6.3 % |
| pgN (`raw/cpu2`) | 3.704 | **20.850** (leader 3.613 / workers 17.237) | 20.850 | N/A | 5.629 (93.8 %) | 2.377 s/런 = 11.1 % |
| pgNL (`raw/cpu3`) | 7.143 | **41.373** (leader 6.950 / workers 34.423) | 41.373 | N/A | 5.792 (96.5 %) | 0.990 s/런 = 2.4 % |

| 비교 | 질의실행분 CPU-초 비 |
|---|---|
| CUBRID idx-NL ↔ CUBRID hash | 47.300 ↔ 47.597 = **1.006x (0.6 %)** |
| PG hash ↔ PG idx-NL | 20.850 ↔ 41.373 = **1.984x** |
| 형상 일치(PG 형상) cubH/pgN | 47.597 / 20.850 = **2.2828x** |
| 형상 일치(CUBRID 형상) cubN/pgNL | 47.300 / 41.373 = **1.1432x** |
| 정본 cubN/pgN | 48.037 / 19.943 = 2.4087x |

**configured cap 6 정규화**: CUBRID 47.30/6 = 7.88 s ↔ 47.60/6 = 7.93 s → **플랜 축이 1.006x로
붕괴한다.** 즉 `USE_HASH`가 빨라 보이는 이유 전부가 전역 예산 100을 이용한 중첩 병렬 스코프다.

### 2.4 구간별 실행 단위 (시간 가중, IV=0.25 s)

| 세트 | 활성 단위 분포 | serial tail | 단위-초 적분 ↔ 실측 |
|---|---|---|---|
| cubN | **6단위 7.50 s (88.2 %)**, 5단위 0.25 s, 4단위 0.25 s | **1단위 0.50 s (5.9 %)** = leader GROUPBY+ORDERBY | 47.75 ↔ 47.30~48.04 (**+0.5 %**) |
| cubH | 12단위 1.25 s, 9단위 1.00 s, 7단위 2.50 s, 6단위 0.75 s, 5·3단위 0.50 s | 1단위 0.75 s (11.0 %) | 48.75 ↔ 47.60 (+2.4 %) |
| pgN | **6단위 3.50 s**, 2단위 0.25 s | **1단위 0.25 s** (플랜 타이밍으로 385.6 ms = 10.2 %) | 21.75 ↔ 19.94~20.85 (+4.3 %) |

PG serial tail은 `EXPLAIN ANALYZE` 노드 타이밍으로 정밀하게 잡힌다 —
병렬 구간(worker `Sort`) 종료 3,405.9 ms → `Execution Time` 3,791.5 ms = **385.6 ms**가
`Gather Merge` + `GroupAggregate` + top-N `Sort`의 직렬 구간이다.

---

## 3단계 — 대칭 프로파일링

수집: `perf record -a -C 0-15`, 고정 주기 `-c 10000000`, 콜그래프 미부착, `instructions:u`/`cycles:u`,
perf는 코어 20-23. 네 세트(cubrid/pg/cubhash/pgcubshape) × 2 이벤트 = 8 레코드.

### 3.1 채증 함정 등재 — `perf record -a`의 심볼 해석 실패 (신규)

**perf 4.18의 `-a -C`는 레코드 시작 시점에 이미 존재하던 sibling 스레드의 map group을 프로세스에
연결하지 못한다.** CUBRID는 `parallel-query` 워커 6개를 풀로 재사용하므로 정본 프로파일의
**99.95 %가 `[unknown]`**으로 떨어졌고(워커를 추가 생성하는 `USE_HASH`는 63 %만 해석), PG는 워커가
매 런 fork되므로 영향이 없다(100 % 해석).

| tid 유형 | cubrid-instructions | cubhash-instructions |
|---|---|---|
| 레코드 시작 전 존재 | 6 tid, unknown **100 %** | 6 tid, unknown 100 % |
| 레코드 중 생성 | 0 | 5 tid, unknown **0 %** |

**대책(이번 회차 신규 도구 `q3/scratch/resolve.py`)**: `PERF_RECORD_MMAP2`로 `[start,end,pgoff,path]`를
얻고 각 ELF의 `.symtab`+`.dynsym`(`readelf -sW`) + `c++filt`로 ip를 직접 심볼로 바꾼다.
`libcubrid.so.11.5`는 `readelf -lW`에서 `R E` LOAD가 vaddr 0 / offset 0 하나뿐이라 로드 베이스 =
mmap start이고 `vaddr = ip − start`다. **검산: perf가 스스로 해석한 샘플과 대조해
instructions 95.68 % / cycles 96.42 % 일치**(불일치는 대부분 `@plt` 엔트리 경계). PG는 perf 해석을
그대로 쓴다(오프라인 폴백은 fork 상속 매핑이 없어 부적합).
**이전 회차(Q1·Q21·Q9·Q8·Q18·Q15) CUBRID 프로파일 중 워커 풀 재사용 조건에 걸린 것이 있으면
같은 함정을 가질 수 있다 — 재검증 대상으로 등재한다.**

### 3.2 프로파일 배수 (독립 실측 `perf stat -p`, 인접 paired)

CUBRID는 `perf stat -p <cub_server>`, PG는 **`perf stat -p <postmaster>` + 새 psql 세션**(Q15 신규법).

| 이벤트 | cubN | pgN | 비 | cubH | pgNL |
|---|---|---|---|---|---|
| `instructions:u` | 185.857 G | 95.203 G | **1.9522x** | 269.498 G | 114.263 G |
| `cycles:u` | 119.562 G | 49.006 G | **2.4397x** | 124.923 G | 96.880 G |
| **IPC** | **1.55** | **1.94** | **0.799** | **2.16** | **1.18** |
| `task-clock` | 48.295 s | 21.409 s | 2.2559x | 49.698 s | 41.642 s |
| 유효 클럭(`cycles:u`/task-clock) | 2.476 GHz | 2.289 GHz | 1.0817 | 2.514 GHz | 2.326 GHz |
| CPUs utilized | 5.633 | 5.688 | — | 7.422 | 5.806 |
| wall | 8.552 s | 3.756 s | **2.2771x** | 6.674 s | 7.164 s |

**IPC 비 0.799 → `instructions` 기반 서술 금지**(ADR 0019 §2). `instructions` 1.9522x < wall 2.2771x로
**Q18에 이어 두 번째로 하한이 된다.**

`cycles` 2.4397x가 wall 2.2771x보다 7.1 % 큰 이유의 분해:
`2.2559(task-clock) × 1.0817(유효 클럭) = 2.4400` ↔ `cycles 2.4397` (**−0.01 %**),
`2.2559 × 1.0098(units 비) = 2.2780` ↔ `wall 2.2771` (**−0.04 %**). 잔차 전량이 유효 클럭 차이며
그 원인은 PG의 커널 시간 비중이 크다는 것이다(`cycles:u`는 user만, `task-clock`은 user+sys).

**형상별 IPC 대비가 이 쿼리의 핵심이다** — 같은 엔진에서 idx-NL은 IPC 1.55(CUBRID) / 1.18(PG)로
메모리 스톨 지배, hash는 2.16(CUBRID) / 1.94(PG)로 명령 지배다. CUBRID의 `USE_HASH`는
**명령을 45 % 더 실행하고도(269.5 vs 185.9 G) cycles는 4.5 %만 늘어난다**(124.9 vs 119.6 G).

### 3.3 귀속 검증과 오버헤드

| 세트 | record 합 (샘플×10 M) | `perf stat -p` | 귀속률 |
|---|---|---|---|
| cubN instructions | 185.87 G | 185.857 G | **100.01 %** |
| cubN cycles | 119.96 G | 119.562 G | 100.33 % |
| pgN instructions | 94.69 G | 95.203 G | **99.46 %** |
| pgN cycles | 49.29 G | 49.006 G | 100.58 % |
| cubH instructions / cycles | 269.51 / 125.08 G | 269.498 / 124.923 G | 100.01 % / 100.13 % |
| pgNL instructions / cycles | 113.07 / 96.54 G | 114.263 / 96.880 G | 98.96 % / 99.65 % |

PG SUT pid 판정(ADR 0017 §2, 중위값 10 % 문턱)에서 걸러낸 것: `io worker 2`(81 samples),
`io worker 3`(43), `bgwriter`(20), 단명 pid(1~2). **io worker는 별개 열: 0.990~2.377 s/런 =
PG SUT CPU의 2.4~11.1 %, pid 개수가 런 중 4 → 8로 동적 증가한다.**

프로파일링 오버헤드(같은 세션 대조): CUBRID `8.527 / 8.566` → `-c 10M` `8.580` = **+0.39 %**,
PG `3.7087 / 3.7164` → `3.7345` = **+0.59 %**. 둘 다 5 % 문턱 훨씬 아래.

### 3.4 기능 단계 버킷 — `cycles` (정본 축), 격차 70.67 G

분류 규칙: **Q1∪Q21∪Q9∪Q8∪Q18∪Q15 UNION 규칙 그대로, 규칙 확장 0건 / 심볼 이동 0건.**

| 기능 단계 | CUBRID | PG | 비 | 절대 델타 | 기여 | C% | P% |
|---|---|---|---|---|---|---|---|
| **인덱스 탐색·키 비교 (B-tree)** | 34.83 G | 0 | ∞ | **+34.83 G** | **49.3 %** | 29.0 % | 0.0 % |
| **버퍼 고정·해제·래치** | 36.54 G | 2.97 G | **12.30x** | **+33.57 G** | **47.5 %** | 30.5 % | 6.0 % |
| MVCC·가시성·트랜잭션 | 5.11 G | 0.40 G | 12.78x | +4.71 G | 6.7 % | 4.3 % | 0.8 % |
| 술어 평가 | 4.16 G | 0.20 G | 20.80x | +3.96 G | 5.6 % | 3.5 % | 0.4 % |
| 값/도메인 변환 | 3.71 G | 0.09 G | 41.22x | +3.62 G | 5.1 % | 3.1 % | 0.2 % |
| 미분류 | 3.95 G | 1.07 G | 3.69x | +2.88 G | 4.1 % | 3.3 % | 2.2 % |
| libc 메모리이동 | 3.75 G | 1.60 G | 2.34x | +2.15 G | 3.0 % | 3.1 % | 3.2 % |
| 수치 연산 (DECIMAL) | 0.37 G | 0.09 G | 4.11x | +0.28 G | 0.4 % | 0.3 % | 0.2 % |
| TLS/런타임 | 0.19 G | 0.02 G | 9.50x | +0.17 G | 0.2 % | 0.2 % | 0.0 % |
| 병렬 인프라 | 0.09 G | 0 | ∞ | +0.09 G | 0.1 % | 0.1 % | 0.0 % |
| 정렬 | 0.06 G | 0.15 G | 0.40x | −0.09 G | −0.1 % | 0.1 % | 0.3 % |
| 메모리 할당/해제 | 0.84 G | 1.41 G | 0.60x | −0.57 G | −0.8 % | 0.7 % | 2.9 % |
| **스캔·레코드 디코드·힙 접근** | 23.09 G | 24.21 G | **0.95x** | **−1.12 G** | −1.6 % | 19.2 % | 49.1 % |
| 임시파일·스필 | 0.25 G | 1.55 G | 0.16x | −1.30 G | −1.8 % | 0.2 % | 3.1 % |
| 식 평가/튜플 구성 | 2.35 G | 4.81 G | 0.49x | −2.46 G | −3.5 % | 2.0 % | 9.8 % |
| **집계·해시·해시조인** | 0.67 G | 10.72 G | **0.06x** | **−10.05 G** | −14.2 % | 0.6 % | 21.7 % |
| 합계 | 119.96 G | 49.29 G | 2.43x | +70.67 G | 100.0 % | | |

미분류 CUBRID 3.29 %(`_init` 1.43 % = 심볼표 경계 잔여, `lang_fastcmp_byte` 0.50 %),
PG 2.17 %(`asm_exc_page_fault` 0.71 %, `LockBufHdr` 0.32 %). **추측 이동 없음.**

### 3.5 `cycles` 순위 역전 지점 (다섯 번째 재현)

| 기능 단계 | instructions 델타 / 기여 | cycles 델타 / 기여 | 해당 코드 IPC |
|---|---|---|---|
| 인덱스 탐색·키 비교 (B-tree) | +71.92 G / **78.9 % (1위)** | +34.83 G / **49.3 % (1위)** | 71.92/34.83 = **2.06** |
| **버퍼 고정·해제·래치** | +28.31 G / **31.0 % (2위)** | **+33.57 G** / **47.5 % (2위)** | 30.21/36.54 = **0.83** |
| 스캔·레코드 디코드·힙 접근 | −9.21 G / −10.1 % (**0.82x**) | −1.12 G / −1.6 % (**0.95x**) | — |
| 집계·해시·해시조인 | −13.84 G / −15.2 % | −10.05 G / −14.2 % | — |

**역전의 형태가 이전 네 쿼리와 다르다.** Q9·Q8·Q18·Q15에서는 버퍼 고정·래치의 **순위**가 올라갔지만,
Q3에서는 순위는 2위로 같고 **절대 델타 자체가 28.31 → 33.57 G로 커져** 1위와의 격차가
47.9 %p → **1.8 %p로 붕괴한다**. 원인은 IPC 대비다 — B-tree 코드는 IPC 2.06으로 명령이 싸고,
버퍼 고정 경로는 IPC 0.83으로 명령마다 스톨한다. 두 버킷 합계가 **격차의 96.8 %**다.
스캔·디코드는 Q15의 부호 반전과 같은 방향으로 움직이되(0.82x → 0.95x) 부호는 유지한다.

### 3.6 상위 심볼 (cycles, self)

| CUBRID cubN | % | PG pgN | % |
|---|---|---|---|
| `pgbuf_fix_release` | **17.31** | `tts_buffer_heap_getsomeattrs` | **25.83** |
| `btree_search_leaf_page` | 9.28 | `ExecInterpExpr` | 9.66 |
| `spage_get_record` | 7.83 | `ExecParallelScanHashBucket` | 8.50 |
| `pgbuf_unfix` | 4.41 | `heap_fill_tuple` | 5.72 |
| `btree_search_nonleaf_page` | 4.17 | `ExecParallelHashJoin` | 3.57 |
| `btree_compare_key` | 3.21 | `BufFileReadCommon` | 2.98 |
| `heap_attrinfo_read_dbvalues` | 3.17 | `hash_search_with_hash_value` | 2.94 |
| `__memmove_evex_unaligned_erms` | 3.03 | `heapgettup_pagemode` | 2.70 |
| `__pthread_mutex_trylock` | 2.40 | `heap_deform_tuple` | 2.54 |
| `spage_get_record_data` | 1.97 | `ExecSeqScanWithQualProject` | 2.07 |
| `__pthread_mutex_lock` | 1.95 | `StrategyGetBuffer` | 1.87 |
| `or_mvcc_get_repid_and_flags` | 1.78 | `pr_midxkey_compare` (CUBRID 1.65) | — |

**형상 일치 쌍의 상위 심볼이 구조적으로 같다** — PG를 CUBRID 형상으로 강제하면
`_bt_compare` **18.85 %**, `LWLockAttemptLock` 10.81 %, `PinBuffer` 7.33 %,
`hash_search_with_hash_value` 7.02 %가 상위를 차지한다. 즉 **인덱스 NL 경로에서는 두 엔진이
같은 종류의 비용을 낸다**(B-tree 비교 + 버퍼 pin + 버퍼 해시 탐색).

### 3.7 행위자별 프로파일 (ADR 0019 §4 — serial tail이 5 % 초과이므로 필수), `cycles`

| 행위자 | cycles | 비중 | IPC | 상위 버킷 | 상위 심볼 | 역산 클럭 |
|---|---|---|---|---|---|---|
| CUBRID worker (`parallel-query`) | 118.62 G | **98.9 %** | 1.544 | 버퍼 30.7 % / B-tree 29.4 % / 스캔 19.5 % | `pgbuf_fix_release` 17.5 %, `btree_search_leaf_page` 9.4 % | 118.62/47.2 s = **2.513 GHz** |
| CUBRID leader (`transaction`) | 1.22 G | **1.0 %** | 2.18 | 수치 14.8 % / 임시파일 13.9 % / 식 평가 13.1 % | `qfile_compare_partial_sort_record` 8.2 %, `mr_data_cmpdisk_numeric` 7.4 %, `sort_run_merge` 4.1 % | 1.22/0.513 s = **2.378 GHz** |
| CUBRID 배경 스레드 | 0.12 G | 0.1 % | — | — | — | — |
| PG worker | 40.49 G | 82.1 % | 1.914 | 스캔 49.2 % / 집계·해시 21.9 % | `tts_buffer_heap_getsomeattrs` 25.9 % | 40.49/16.50 s = 2.454 GHz |
| PG leader | 8.80 G | 17.9 % | 1.954 | 스캔 48.5 % / 집계·해시 21.2 % | `tts_buffer_heap_getsomeattrs` 25.7 % | 8.80/3.76 s = 2.340 GHz |

**신규 사실 두 개.**
(a) **CUBRID leader가 격차에 기여하지 않는다** — 전체 cycles의 **1.0 %**뿐이고, 직렬 GROUP BY
정렬 병합(`qfile_compare_partial_sort_record` / `sort_run_merge`)은 그룹이 114,003개뿐이라 싸다.
Q18(leader 28.5 %)·Q15(leader 50.1 % of wall)와 정반대이므로 **`external_sort.c:5232` 직렬화는
Q3에서 레버가 아니다**(0.50 s = wall의 5.9 %, 6단위 환산 상한 −0.42 s → 배수 2.257 → 2.144x).
(b) **ADR 0019 §4-c의 leader turbo 클럭 이득이 재현되지 않는다** — leader 2.378 GHz < worker
2.513 GHz다. Q15는 직렬 구간이 5.377 s로 길어 코어 1개만 바빴지만, Q3의 직렬 구간은 0.50 s로
짧아 병렬 구간의 열 상태를 물려받는다. **조항을 "직렬 구간이 wall의 20 % 이상일 때만 클럭 이득을
가정한다"로 좁혀야 한다**(ADR 0020 §5에 등재).

### 3.8 일곱 쿼리 나란히 (`cycles`, 기여도 % / CUBRID·PG 비)

| 기능 단계 | Q21 | Q9 | Q8 | Q18 | Q15 | **Q3** |
|---|---|---|---|---|---|---|
| 인덱스 탐색·키 비교 (B-tree) | 35.9 % / 42.4x | 11.9 % / 3.1x | 35.1 % / ∞ | −0.2 % / 0.0x | 0.0 % / — | **49.3 % / ∞** |
| 버퍼 고정·해제·래치 | 24.4 % / 23.8x | **27.8 % / 4.4x** | 19.8 % / 11.3x | **94.2 % / 13.7x** | **26.1 % / 4.5x** | **47.5 % / 12.3x** |
| 스캔·레코드 디코드·힙 접근 | 12.8 % / 6.3x | 20.1 % / 3.3x | 12.4 % / 1.8x | −135.1 % / 0.4x | −2.5 % / 1.0x | **−1.6 % / 0.95x** |
| 식 평가/튜플 구성 | 5.4 % / 11.9x | 17.7 % / 8.4x | 14.6 % / 12.6x | **101.9 % / 4.1x** | 0.0 % / 1.0x | −3.5 % / 0.49x |
| 술어 평가 | 3.9 % / 30.0x | 1.2 % / 2.2x | 4.3 % / 49.5x | 29.9 % / 60.0x | **47.7 % / 22.0x** | 5.6 % / 20.8x |
| 값/도메인 변환 | 2.9 % / 290.8x | 8.2 % / 6.3x | 7.9 % / ∞ | 57.5 % / 29.0x | 11.5 % / 7.7x | 5.1 % / 41.2x |
| MVCC·가시성 | 3.7 % / 36.3x | 3.2 % / 5.4x | 4.2 % / 12.8x | 12.9 % / 6.8x | 19.3 % / 11.7x | 6.7 % / 12.8x |
| 수치 연산 (DECIMAL) | — | 5.9 % / 5.1x | 3.5 % / 64.4x | 0.0 % / 1.0x | −4.9 % / 0.6x | 0.4 % / 4.1x |
| 정렬 | −0.0 % | −0.9 % | −0.0 % | −25.8 % / 0.4x | 6.9 % / 4.9x | −0.1 % / 0.4x |
| 임시파일·스필 | 0.4 % | 1.0 % | 0.9 % | 31.1 % / 10.5x | 9.7 % / 352x | −1.8 % / 0.16x |
| 집계·해시·해시조인 | −0.8 % | −4.7 % | −10.0 % | −51.4 % | −9.9 % | **−14.2 % / 0.06x** |
| TLS/런타임 | 0.7 % | 3.2 % | 2.3 % | 25.8 % / 306x | 1.6 % | 0.2 % / 9.5x |

### 3.9 일곱 쿼리 프로파일 배수 표 (CONTEXT.md 갱신분)

| Q | instructions | cycles | wall | CUBRID IPC | PG IPC | IPC 비 | `instructions`의 지위 |
|---|---|---|---|---|---|---|---|
| Q1 | 3.011x | — | 3.070x | 2.339 | 2.357 | 0.992 | 상한 |
| Q21 | 17.748x | 15.353x | 14.32x | 1.807 | 1.563 | 1.156 | 상한 |
| Q9 | 4.233x | 3.022x | 2.741x | 1.929 | 1.378 | 1.401 | 상한 |
| Q8 | 5.796x | 3.734x | 3.960x | 2.132 | 1.374 | 1.552 | 상한 |
| Q18 | **0.858x** | 1.159x | 1.247x | 1.811 | 2.447 | **0.740** | **하한** |
| Q15 | 2.0094x | 1.7024x | 2.1650x | 2.29 | 1.94 | 1.180 | 상한 |
| **Q3** | **1.9522x** | **2.4397x** | **2.2771x** | **1.55** | **1.94** | **0.799** | **하한 (2번째)** |

---

## 4단계 — 소스 규명

### 4.1 플랜 축의 뿌리 — NL 인덱스 probe와 해시 스필의 상대 가격이 4.9배 뒤집혀 있다

```c
/* src/optimizer/query_planner.c:98-99 */
#define ISCAN_IO_HIT_RATIO 0.5
#define SSCAN_DEFAULT_CARD 50

/* src/optimizer/query_planner.c:3406-3418  qo_nljoin_cost() */
inner_cpu_cost = guessed_result_cardinality * inner->variable_cpu_cost;
if (qo_is_iscan (inner))
  inner_io_cost = guessed_result_cardinality * inner->variable_io_cost * (1 - ISCAN_IO_HIT_RATIO);
```

```c
/* src/optimizer/query_planner.c:85-90 */
#define HJ_BUILD_CPU_OVERHEAD_FACTOR 40
#define HJ_PROBE_CPU_OVERHEAD_FACTOR 20
#define HJ_MEM_ALLOC_CONSTANT 1500  /* Heuristic offset to prefer NL join over hash join */
#define HJ_FILE_IO_WEIGHT 0.5       /* per-row IO weight for partitioned hash-join spill */

/* src/optimizer/query_planner.c:3650-3658  qo_hashjoin_cost() */
if ((outer_cardinality * per_entry_size) > mem_limit * HJ_PARTITION_FILL_FACTOR)
  outer_build_io_cost += (inner_cardinality + outer_cardinality) * HJ_FILE_IO_WEIGHT;
```

**프로파일 숫자 매핑 (플랜 덤프 `raw/s1/cub-q3.plan`의 비용값을 위 식으로 재현):**

| 항목 | 모델 비용 | 산식 | 실측 |
|---|---|---|---|
| idx-join 1단 (orders × customer.pk) | 3,972,993 | 189,189(outer) + 7,347,185 probe × ~0.515 | — |
| idx-join 2단 (× lineitem.pk) | **4,809,163** | +1,493,193 probe × ~0.56 | wall 8.375 s / 119.96 G cycles |
| hash-join 1단 (customer × orders) | 4,439,648 | 24,799 + 189,189 + 스필 (7,347,185+304,850)×0.5 = 3,826,018 | — |
| hash-join 2단 (× lineitem) | **23,944,017** | +32,311,154×0.0025×20 + 1,493,193×0.0025×40 + 1500 + **스필 (32,311,154+1,493,193)×0.5 = 16,902,174** | wall 6.719 s / 124.92 G cycles |
| 모델 비 | **4.98x (idx-NL 유리)** | | **실측 0.80x (hash 유리)** |

**해시 조인 2단 추가 비용 18,671,467 중 16,902,174(90.5 %)가 스필 항이다.** 스필 예측 자체는
맞았다(trace `SPLIT (partitions: 12)`, `BUILD method: hybrid`) — 틀린 것은 **단가**다.

| 단가 | 모델 | 실측 (`cycles`) | 비 |
|---|---|---|---|
| 인덱스 NL probe 1회 | ~0.5 비용 단위 | 119.96 G / 8,782,633 probe = **13,660 cycles** | — |
| 해시 조인 행 1개 | ~0.55 비용 단위 | 124.92 G / 41,123,692 row = **3,041 cycles** | — |
| **probe : row** | **0.91 : 1** | **4.49 : 1** | **4.9배 역방향 오차** |

기제 확증(측정): **인덱스 NL은 page fix를 27.79배 더 만든다.**

| 지표 | cubN (idx-NL) | cubH (hash) | pgN (hash) | pgNL (idx-NL) |
|---|---|---|---|---|
| 페이지 접근 수 | **39,538,926** (trace `fetch` 합) | ~8,072,638 | **1,422,457** (`hit+read`) | **36,134,170** |
| CUBRID/PG 비 | vs pgN **27.79x** | vs pgN 5.68x | — | cubN/pgNL **1.094x** |

`ISCAN_IO_HIT_RATIO 0.5`는 **probe당 IO를 절반으로 깎는 하드코드 상수**이고,
`HJ_MEM_ALLOC_CONSTANT 1500`의 주석은 **"Heuristic offset to prefer NL join over hash join"**으로
NL 선호를 명시한다. 두 항 모두 같은 방향으로 틀린다.

### 4.2 버퍼 고정 경로 — hit 경로 1회에 659 cycles

```c
/* src/storage/page_buffer.c:2211  pgbuf_fix_release() */
PGBUF_STATUS *show_status = &pgbuf_Pool.show_status[thread_get_entry_index (thread_p)];   /* :2232 */
...
if (logtb_get_check_interrupt (thread_p) == true) { ... }                                  /* :2295 (per fix) */
...
pgptr = pgbuf_lockfree_fix_ro (thread_p, vpid, fetch_mode);                                /* :2313 fast path */
```

```c
/* src/storage/page_buffer.c:7670  pgbuf_lockfree_fix_ro() */
PGBUF_BCB *bufptr = pgbuf_search_hash_chain_no_bcb_lock (...);   /* :7735 해시 체인 탐색 */
do { impl = get_impl (&bufptr->atomic_latch); ... new_impl.impl.fcnt++; }
while (!bufptr->atomic_latch.compare_exchange_weak (...));        /* 공유 캐시라인 CAS */
holder = pgbuf_find_thrd_holder (thread_p, bufptr);               /* 홀더 리스트 선형 탐색 */
```

| 측정 | 값 |
|---|---|
| `pgbuf_fix_release` cycles | 20.77 G (worker의 17.5 %) |
| `pgbuf_unfix` cycles | 5.29 G (4.4 %) |
| pthread mutex 3종 (`trylock`/`lock`/`unlock_usercnt`) | 2.88 + 2.34 + 1.92 = **7.14 G (6.0 %)** — lock-free fast path를 못 타는 fix가 남아 있다 |
| 합계 / page fix 수 | (20.77+5.29) G / 39.54 M = **659 cycles/fix** |
| 이 버킷 IPC | 30.21 G instr / 36.54 G cycles = **0.83** |

**lock-free RO fast path는 이미 있다**(`:7670`) — 그래도 659 cycles다. 남은 비용은
(a) 버퍼 해시 테이블 랜덤 접근(8 GB / 16 KB = 524,288 BCB → LLC 미스),
(b) `atomic_latch` CAS(공유 라인 locked RMW),
(c) `pgbuf_find_thrd_holder` 선형 탐색,
(d) fast path **이전에** 매 fix 실행되는 `thread_get_entry_index`(`:2232`)와
`logtb_get_check_interrupt`(`:2295`)다.

### 4.3 B-tree descent — 형상 일치 시 PG와 1.10x

| 심볼 | cycles | file:line |
|---|---|---|
| `btree_search_leaf_page` | 11.13 G | `src/storage/btree.c:5538` |
| `btree_search_nonleaf_page` | 5.00 G | `src/storage/btree.c:5190` |
| `btree_compare_key` | 3.85 G | `src/storage/btree.c:19461` |
| `pr_midxkey_compare` | 1.98 G | `src/object/object_primitive.c:7731` |
| 합계 | **21.96 G** (버킷 34.83 G의 63.0 %) | |

**형상 일치(Q3n)에서 이 버킷은 CUBRID 34.83 G ↔ PG 31.64 G = 1.10x**이고
버퍼 고정·래치는 36.54 ↔ 30.75 G = **1.19x**다. 따라서 **정본 버킷 표의 "B-tree 49.3 %"는
플랜 축이 아니라 플랜 형상의 부산물**이며, Q8에서 확정한 같은 성질이 더 강하게 재현된다.
`btree.c:5190`(후보 ④)의 격차 설명력은 **형상을 맞추면 13.6 %로 떨어진다.**

### 4.4 형상 일치 시 남는 CUBRID 고유 비용 (Q3n, 격차 23.42 G)

| 기능 단계 | CUBRID | PG | 비 | 기여 | 대표 심볼 (file:line) |
|---|---|---|---|---|---|
| 스캔·레코드 디코드·힙 접근 | 23.09 G | 7.83 G | **2.95x** | **65.2 %** | `spage_get_record` `slotted_page.c:3815`, `spage_get_record_data` `:3850`, `heap_attrinfo_read_dbvalues` `heap_file.c:10464`, `or_mvcc_get_repid_and_flags` |
| 버퍼 고정·해제·래치 | 36.54 G | 30.75 G | 1.19x | 24.7 % | `page_buffer.c:2211` |
| 값/도메인 변환 | 3.71 G | 0.05 G | **74.20x** | 15.6 % | `pr_clear_value`, `pr_type_from_id`, `mr_data_readval_*` (`object_primitive.c`) |
| 인덱스 탐색·키 비교 | 34.83 G | 31.64 G | 1.10x | 13.6 % | `btree.c:5538/5190` |
| libc 메모리이동 | 3.75 G | 1.01 G | 3.71x | 11.7 % | `__memmove_evex_unaligned_erms` |
| 집계·해시·해시조인 | 0.67 G | 7.84 G | 0.09x | −30.6 % | (PG `Partial HashAggregate` 잔여) |

### 4.5 CUBRID 형상 무관 CPU 동률의 소스적 이유

`px_parallel.cpp:172`의 `MIN (auto_degree, parallelism)`은 **노드 단위**이고 전역 예산은
`px_worker_manager_global.cpp:57-78`의 `PRM_ID_MAX_PARALLEL_WORKERS`(=100)다.
`USE_HASH` 플랜은 `HASHJOIN(6) ⊃ SUBQUERY(2) ⊃ HASHJOIN(3) ⊃ SUBQUERY(2) ⊃ sscan(5/6)`으로
스코프가 중첩되므로 각 스코프가 독립적으로 예산을 받아 **동시 12단위**까지 올라간다.
`query_executor.c:16048-16071`의 `assert (n_workers_to_reserve == 1)` + 주석
`TODO: Temporarily limited to 2.`는 SUBQUERY gather 쪽 상수이며(ADR 0018 §3), 전역 예산과는 별개 축이다.

---

## 5. 개선 후보 5개 (구현 없음)

상한은 전부 **worker 클럭 2.513 GHz** 기준이며, 직렬 구간을 병렬화하는 후보에는 클럭 하락을 반영했다.
`configured cap 6 / 전역 예산 CUBRID 100 · PG 8` 조건에서의 값이다.

| # | 후보 | 근거 (file:line) | 상한 [wall 배수] | 난이도 | 위험 | upstream / pin | 기존 후보 |
|---|---|---|---|---|---|---|---|
| **A** | **NL 인덱스 probe 비용을 실측 단가로 재교정** — `ISCAN_IO_HIT_RATIO` 하드코드 제거(버퍼 적중률을 통계로), `HJ_MEM_ALLOC_CONSTANT`의 NL 선호 오프셋 폐기, probe 비용에 인덱스 높이 × 페이지 fix 단가 반영 | `query_planner.c:98`, `:3411`, `:87`, `:3650-3658` | 2.2573 → **1.8109x** (형상 일치 배수까지, −19.8 %). configured cap 6 정규화 시 2.2573 → **2.244x**(−0.6 %) — **CPU를 줄이지 않으므로 cap 안에서는 거의 이득이 없다** | 중 | **높음** — 22쿼리 전체 플랜이 바뀐다. Q21·Q8·Q18의 플랜 축이 동시에 흔들린다 | pin 내 코드, upstream 영향 큼 | **신규** |
| **B** | **`pgbuf_fix_release` hit 경로 단축** — fast path 진입 **전에** 실행되는 `thread_get_entry_index`(`:2232`)·`logtb_get_check_interrupt`(`:2295`)를 fast path 뒤로 이동, `pgbuf_find_thrd_holder` 선형 탐색을 per-thread 소형 해시/직접 인덱스로, BCB 해시 테이블 프리페치 | `page_buffer.c:2211`, `:2232`, `:2295`, `:7670`, `:7735` | 버퍼 버킷 36.54 G 중 30 % 절감 가정 시 11.0 G → cycles 119.96 → 108.96 G, **2.2573 → 2.050x** | 중 | 중 — 정확성 위험은 낮으나 fast path 재배치가 latch 의미를 건드릴 수 있다 | pin 내, `pgbuf_lockfree_fix_ro`는 이미 도입된 패턴 | **③ 확장** (BCB 뮤텍스 원자화는 이미 부분 구현) |
| **C** | **힙 튜플 디코드 특화** — `spage_get_record`/`spage_get_record_data`/`heap_attrinfo_read_dbvalues`의 행당 인터프리테이션 제거 | `slotted_page.c:3815`, `:3850`, `heap_file.c:10464` | 형상 일치(Q3n) 기여 **65.2 %**. 스캔 버킷 23.09 → PG 수준 7.83 G면 cycles −15.26 G → 형상 일치 1.1826 → **0.99x**. 정본 형상에서는 −1.6 %(**레버 아님**) | 높음 | 중 | pin 내 | **①** |
| **D** | **전역 병렬 예산을 쿼리 단위로** — `parallelism`을 노드 cap이 아니라 쿼리 예산으로 해석하거나 쿼리별 예산을 신설. **성능 개선이 아니라 계약 정합 후보**다 | `px_parallel.cpp:172`, `px_worker_manager_global.cpp:57-78` | 배수 개선 **0** (오히려 cubH가 6.72 → 7.93 s로 느려진다). 대신 `configured-cap parity`가 성립하고 CUBRID 100 ↔ PG 8 비대칭이 사라진다 | 낮음 | **높음** — 기존 병렬 쿼리 성능이 내려간다 | pin 내, 정책 결정 필요 | **신규** |
| **E** | **B-tree descent 페이지 캐시 + midxkey 비교 특화** | `btree.c:5538`, `:5190`, `:19461`, `object_primitive.c:7731` | 정본 형상 기여 49.3 %지만 **형상 일치 시 1.10x = 13.6 %**로 떨어진다. B-tree 버킷 21.96 G 중 20 % 절감 시 **2.2573 → 2.174x** | 높음 | 중 | pin 내 | **④** |

**A + B 동시 착지**: 형상이 hash로 바뀌면 B-tree·버퍼 비용 구조가 통째로 달라지므로 곱하지 않는다.
A만으로 8.375 → 6.719 s, 여기에 B를 얹으면 cubH의 버퍼 버킷 20.75 G 중 30 % = 6.2 G 절감 →
6.719 → 6.39 s, **2.2573 → 1.722x**. 절대 격차 4.665 → 2.680 s(**−42.6 %**).

### 기존 후보 목록 판정 (전부 채증)

| 기존 후보 | Q3 판정 | 채증 |
|---|---|---|
| ① 힙 튜플 디코드 인터프리테이션 제거 | **정본 형상 레버 아님 / 형상 일치 시 1위** | 정본 스캔·디코드 **0.95x(−1.6 %)**, Q3n에서 **2.95x(65.2 %)** |
| ② 노드 경계 튜플 재구성 제거 | **정본에서 배제** | 식 평가/튜플 구성 **0.49x**(CUBRID가 더 적다). 단 cubH에서는 3.76x / 17.5 % |
| ③ BCB 뮤텍스 → 원자 연산 + pin 캐시 | **유지·최우선(후보 B)** | 버퍼 고정·래치 cycles **47.5 %**, 659 cycles/fix, pthread mutex 잔여 6.0 % |
| ④ B-tree descent 캐시 + midxkey | **유지하되 형상 의존(후보 E)** | 정본 49.3 % → 형상 일치 13.6 % |
| ⑤ 중간 리스트 스캔 병렬화 문턱 | **해당 없음** | Q3 정본에 gather 위 리스트 스캔이 없다. cubH의 `SCAN (temp fetch 1,648)`는 302,114행/1,069페이지로 문턱 미달이나 자기 시간 49 ms(0.7 %) |
| ⑥ NUMERIC pass-through | **정본 배제** | 수치 연산 cycles **0.37 G = 0.4 %**(4.11x). cubH에서는 6.25 G / 8.1 % |
| ⑦ GROUP BY 병합·최종화 병렬화 | **해당 없음** | 그룹 114,003개, leader cycles **전체의 1.0 %**, 직렬 0.50 s(5.9 %). 6단위 환산 상한 2.257 → 2.144x |
| ⑧ `px_scan_result_handler::write()` `thread_local` 호이스팅 | **정본 배제** | TLS/런타임 cycles **0.19 G = 0.2 %**. cubH에서는 2.07 G / 2.7 %(`TLS init function for parallel_scan::result_handler<…>::tl` 1.37 %) |
| ⑫ 술어 평가 스캔 융합 | **부분 해당** | 술어 평가 cycles 4.16 G / **5.6 %** (20.8x). Q15(47.7 %)와 달리 지배적이지 않다 |
| ⑬ 반복 뷰 CSE | **해당 없음** | Q3에 뷰·반복 참조가 없다 |
| ⑭ MVCC 페이지 단위화 | **부분 해당** | MVCC 5.11 G / **6.7 %** (12.78x), `or_mvcc_get_repid_and_flags` 2.14 G |
| ⑮ 적재 밀도 대칭화 (채증만) | **채증** | 페이지 접근 형상 일치 시 CUBRID 39.54 M(16 KB) ↔ PG 36.13 M(8 KB) = **1.094x** → CUBRID가 2배 큰 페이지로 같은 수의 페이지를 만진다 = 인덱스 엔트리 밀도 열위. lineitem PK 인덱스 PG 1,285 MB |

---

## 6. 범주 판정

**Q3는 새 범주 `플랜형(옵티마이저 오선택형)`이다.** Q21의 `플랜형`과 구별해야 한다.

| 축 | Q21 (플랜형) | **Q3 (플랜형-옵티마이저 오선택)** |
|---|---|---|
| 플랜 축 [wall] | **4.436x** | **1.2465x** |
| 플랜 축이 CPU를 바꾸는가 | 예 (일 자체가 줄어든다) | **아니오 — CPU-초 1.006x 동률** |
| 플랜 축의 정체 | 조인 순서·전략이 실제 일의 양을 바꾼다 | **실행 단위 수만 바꾼다**(5.61 → 7.05, cap 초과) |
| 행당 축 [CPU-초 비] | 3.228x | **2.2676x (PG 형상) ↔ 1.1432x (CUBRID 형상)** |
| 형상 일치 배수 | 3.23x (단일값) | **1.8109x ↔ 1.1826x (둘로 갈린다)** |
| 실행 단위 축 | 1.002x | **0.7986x (1 미만 첫 사례)** |
| 지배 버킷 [cycles] | B-tree 35.9 % 단독 | **B-tree 49.3 % + 버퍼 47.5 % 동률 쌍 = 96.8 %** |

**한 줄 판정**: Q3의 격차는 (1) CUBRID 옵티마이저가 인덱스 NL을 고른 것 — 그러나 이는 시간만 바꾸고
일은 바꾸지 않는다 — 과 (2) **그 형상에서 페이지 fix를 27.79배 만들면서 fix 1회에 659 cycles를
쓰는 것**의 곱이다. 형상을 맞추면 배수가 1.18x까지 내려가므로 **"CUBRID가 PG에 근접했다"는 서술은
CUBRID 형상 기준으로만 성립하고, 사용자가 실제로 겪는 값은 2.26x다**(ADR 0019 §1).

---

## 7. 채증 · 재현

| 항목 | 경로 |
|---|---|
| raw 산출물 | `.git_ignored_dir/q3/raw/{s1,s2,s2b,final,pair,cpu,cpu2,cpu3,thr,prof}/` |
| metadata (원칙 v2 §2) | 각 세트의 `meta.json` (10개, `contract_revision: 2`) |
| manifest·백업 | `docs/MANIFEST-raw-evidence.md`, `.git_ignored_dir/backup/q3-raw-20260729.tar.gz` (sha256 `f5b4f7d9874f062a…`) |
| 하네스 | `.git_ignored_dir/q3/scratch/{run-s1.sh,run-s2.sh,run-s2b.sh,run-final.sh,run-pair.sh,run-cpu.sh,run-thr.sh,run-prof.sh,run-stat.sh,meta.sh}` |
| 분석 도구 | `symbols2.sh`, `classify.py`(UNION 규칙 + `Q3`/`Q3h`/`Q3n` 세트 추가), **`resolve.py`(perf 심볼 해석 실패 보정 — 신규)**, **`actors.py`(행위자별 분해 — 신규)**, `actor-classify.py` |
| 버킷 표 | `raw/prof/buckets-{cycles,instructions}.txt` |
| 플랜 | `raw/s1/{pg-q3.plan,cub-q3.plan,cub-q3.trace,pg-q3.estplan}`, `raw/s2/{pg-nl.plan,cub-hash.trace}` |
| 무효 run | `raw/final` 블록 6 (loadavg 33.15), `raw/s2` `pg-nl R1`(sda 1,551 MiB = WARM 실패), `raw/s2b` `cubH B2`(배경 부하) — **삭제하지 않고 무효로 표시** |
