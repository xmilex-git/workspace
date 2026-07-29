# Q8 격차 규명 — 절대격차 Pareto 4위 (2026-07-29)

대상은 TPC-H Q8(National Market Share) 하나다. 8-way 조인 + 날짜 범위 + CASE 식 집계.
G2 stream 레짐 기준값 **CUBRID 9.386 s (sd 0.050) / PG 2.512 s (sd 0.008) = 3.74x**,
positive_pareto 4.96 %, 완주 19개 중 배수 2위.

**판정: Q8은 Q1형이다.** 단 두 가지가 앞의 세 쿼리와 다르다 —
(1) **실행 단위 축이 처음으로 닫히지 않았다**(Q21 0.2 %, Q9 0.23 % → **Q8 12.9 %**),
(2) 정본 플랜에서 B-tree가 격차의 35~39 %를 쥐지만 **그것은 플랜 축이 아니라 플랜 형상의
부산물**이며, 형상을 맞추면 B-tree는 **0 %**가 되고 Q1형 3버킷이 그 자리를 그대로 차지한다.

| 축 | 값 | 근거 |
|---|---|---|
| **플랜·조인 전략** | **0.999x** (같은 브래킷) / 0.977~0.980x (교차 A/B) — **격차 없음** | §2.1 |
| **실행 단위 이용률** | **1.129x** (CUBRID 86.5 % vs PG 97.6 %) — **닫히지 않음** | §2.2 |
| **행당 실행 비용** | **3.508x** (정본 형상) / **4.256x** (형상 일치) | §2.3 |
| 검산 오차 | **0.01 %** (형상 일치 3축) / **0.02 %** (정본 2축) | §2.4 |

---

## 0. 측정 계약 · 스냅샷

| 항목 | 값 |
|---|---|
| 트랙 | **단위 파리티** — CUBRID `parallelism=6`(서버 conf) ↔ PG **세션 GUC** `max_parallel_workers_per_gather=5`(+leader) = 양쪽 6 실행 단위 (ADR 0014) |
| PG 클러스터 기본값 | `max_parallel_workers_per_gather=6` — **세션 SET이 반드시 필요**했고 모든 하네스가 첫 줄에서 건다. 클러스터 값은 건드리지 않았다 |
| WARM 하위 레짐 | **single-query-repeat** (ADR 0016). G2의 `stream` 값과 같은 표에 합치지 않는다 |
| 캐시 채증 | 집계 런 전부 sda 물리 read ≤ 0.2 MiB (문턱 1 % / 100 MiB) — 무효 런 2건은 §1.4 |
| 격리 | SUT·클라이언트 node0 `0-15`, 수집기 `20-23` (ADR 0012) |
| CUBRID | `f30f1c260`, `data_buffer_size=8G`, `sort_buffer_size=2M`, `update_statistics_update_histogram=yes` |
| PG | `5713b437`(20devel), `shared_buffers=8GB`, `work_mem=4MB`, `dynamic_shared_memory_type=mmap`, `io_method=worker`, `parallel_leader_participation=on` |
| 쿼리 | `queries/q8-{cubrid,pg}.sql` — **방언 diff 0바이트**(양쪽 동일 SQL). `queries/diff/q8.diff` 빈 파일 |
| 결과 정합 | 2행, 값 일치(십진 스케일 범주): `1995 0.03882014251433219621787549…` / `1996 0.03948968749183991638443237…` |
| 파싱·플랜 시간 (ADR 0011) | CUBRID **8~10 ms**(`SET OPTIMIZATION LEVEL 514`, 실행 없음, 3회) ↔ PG **2.83~2.94 ms**(`Planning Time`) |
| `broker+CAS` 열 (ADR 0009/0011) | CUBRID = `csql` 자신 **user 0.01 s / sys 0.00 s** ↔ PG **N/A (backend 내부)**. 합산 단일 숫자 없음 |
| `io worker` 열 (ADR 0017) | PG **3.196 s/런** (io worker 0~5) = SUT CPU의 **+20.8 %**. CUBRID 대응물 없음. 합산 금지 |

---

## 1단계 — 재현 · 플랜

### 결론 5줄

1. 정본 Q8을 WARM AB/BA 3블록으로 두 창에서 재현했고 **CUBRID는 안정(9.10~9.27 s), PG는 두 상태(2.33 s / 2.69 s)로 갈렸다.** 배수는 **3.43x ↔ 3.96x**.
2. 갈림의 원인은 **PG shared buffer의 hit/read 분할**이다 — `hit+read`가 **1,465,669 블록으로 두 상태에서 완전히 동일**하고 분할만 `828,069/637,600` → `939,944/525,725`로 바뀌었다. ADR 0016 Q21형 서명이 그대로 재현됐고, **Q8 PG는 이 축에 민감하다**(Q9는 무감이었다).
3. **CUBRID는 같은 축에 무감**하다 — trace 최상위 `fetch` 731,859 → 731,845(−0.002 %), `ioread` 256,916 → 270,213.
4. **두 엔진의 플랜은 형상이 완전히 다르다.** PG는 `lineitem` 전체 순차 스캔 → `part` 해시로 60 M → 403,487행으로 줄이고 마지막에 `orders`를 붙인다. CUBRID는 `orders` 전체 힙 스캔(날짜 sarg) → **`lineitem` PK 인덱스 NL로 18,227,506행을 만든 뒤** `part` 해시로 122,404행까지 줄인다.
5. **행 추정은 CUBRID가 전 구간 2.1~2.4배 과소, PG가 1.16~1.49배 과대**다. CUBRID의 과소는 `idx-join orders→lineitem` 카디널리티(8,718,007 추정 vs 18,227,506 실제)에서 시작해 상위로 전파된다.

### 1.1 재현 (단위 파리티, WARM, single-query-repeat)

| 세트 | 창 | CUBRID (s) | sd | PG (s) | sd | 배수 | PG `shared read` |
|---|---|---|---|---|---|---|---|
| s1 (AB/BA 3블록, end-to-end) | 11:24 | 9.245 / 9.183 / 9.153 → **9.194** | 0.047 | 2.712 / 2.662 / 2.656 → **2.677** | 0.031 | 3.435x | 637,600 |
| s1r (AB/BA 3블록, end-to-end) | 11:35 | 9.307 / 9.241 / 9.249 → **9.266** | 0.036 | 2.694 / 2.741 / 2.693 → **2.709** | 0.027 | 3.420x | 637,600 |
| **final (AB/BA 3블록, end-to-end)** | 12:00 | 9.016 / 9.297 / 8.992 → **9.102** | 0.169 | 2.333 / 2.327 / 2.318 → **2.326** | 0.008 | **3.913x** | 525,725 |
| **final (CPU 브래킷, 문장시간 ×5)** | 12:02 | **9.278** | 0.084 | **2.343** | 0.022 | **3.960x** | 525,725 |
| (참고) G2 stream 레짐 | 07-28 | 9.386 | 0.050 | 2.512 | 0.008 | 3.74x | — |

* **실행 단위 수**: CUBRID 6 / PG 6(worker 5 + leader). PG 플랜 `Workers Planned: 5 / Launched: 5`, 스캔 노드 `loops=6`. 파리티 성립.
* 헤드라인은 **final 세트**를 쓴다 — 3축 분해의 CPU·프로파일이 전부 이 창에서 나왔기 때문이다. s1/s1r는 **PG read-heavy 상태의 같은 하위 레짐 값**으로 병기한다.

### 1.2 ADR 0016 하위 레짐 채증 — Q8 PG는 민감, CUBRID는 무감

| PG `EXPLAIN (ANALYZE, BUFFERS)` 최상위 | read-heavy 상태 | read-light 상태 | 델타 |
|---|---|---|---|
| `shared hit` | 828,069 | 939,944 | +111,875 |
| `shared read` | 637,600 | 525,725 | **−111,875 (−17.5 %)** |
| **`hit + read`** | **1,465,669** | **1,465,669** | **0 (완전 동일)** |
| `Execution Time` | 2,950.006 ms | 2,657.179 ms | **−292.8 ms (−9.9 %)** |
| SUT CPU/런 | 15.348 s | 13.720 s | −10.6 % |
| wall(문장, ×5 평균) | 2.620 s | 2.343 s | **−10.6 %** |
| 구간 sda 물리 read | 0.0 MiB | 0.0 MiB | 양쪽 0 |

`read` 전량이 `Parallel Seq Scan on public.lineitem`에 있고(hit 487,528/read 637,600 → 599,403/525,725,
합 1,125,128 = lineitem 힙 전체), lineitem 힙 8.6 GB > `shared_buffers` 8 GB다.
**Q9와 구조는 같은데 방향이 반대다** — Q9는 미스를 39.9 % 줄여도 wall이 +2.70 %였고,
Q8은 17.5 % 줄이자 wall이 −10.6 %다. 미스 단가는 **2.62 µs/미스**(`Execution Time` 기준).
차이는 워킹셋 초과폭이다: Q9 lineitem은 힙만으로 8 GB를 넘겨 어떤 상태에서도 미스가 남지만,
Q8은 lineitem 스캔이 힙 전체를 훑되 **동시 상주 압력이 낮아**(`part` 해시 704 kB, `orders` 해시 43.9 MB)
버퍼 잔존율이 43.3 % ↔ 53.3 %로 움직인다.

CUBRID 대조군(같은 두 창, `;trace on`):

| CUBRID trace 최상위 `SELECT` | read-heavy | read-light | 델타 |
|---|---|---|---|
| `fetch` | 731,859 | 731,845 | **−14 (−0.002 %)** |
| `ioread` | 256,916 | 270,213 | +5.2 % |
| `time` (trace on) | 11,435 ms | 11,813 ms | +3.3 % |

→ **CUBRID 무감**(Q21·Q9와 동일). 이 비대칭은 제거 대상이 아니라 기록 대상이다.

### 1.3 양쪽 플랜 전체 덤프 — 노드 단위 대조

채증: `raw/s1p/pg-q8.plan`(EXPLAIN ANALYZE/BUFFERS/VERBOSE, 358행),
`raw/s1p/cub-q8.plan`(`SET OPTIMIZATION LEVEL 514` 전체 조인 그래프+비용),
`raw/s1p/cub-q8.trace`(`;plan detail on` + `;trace on`).

**조인 순서·방식**

| | CUBRID (정본) | PostgreSQL (정본) |
|---|---|---|
| 1 | `sscan orders` (sargs 날짜 BETWEEN) | `Parallel Seq Scan lineitem` |
| 2 | **`idx-join` → `iscan lineitem.pk(l_orderkey,l_linenumber)`** | `Parallel Hash Join` ← `Parallel Hash(part)` |
| 3 | `hash-join` ← `sscan part` (sargs p_type) | `Parallel Hash Join` ← `Parallel Hash(orders ⋈ customer ⋈ n1 ⋈ region)` |
| 4 | **`idx-join` → `iscan customer.pk`** | `Parallel Hash Join` ← `Parallel Hash(supplier)` |
| 5 | `hash-join` ← `sscan n1` | `Hash Join` ← `Hash(n2)` |
| 6 | `hash-join` ← `sscan region` (sargs r_name) | `Sort` → `Partial GroupAggregate` |
| 7 | **`idx-join` → `iscan supplier.pk`** | `Gather Merge` → `Finalize GroupAggregate` |
| 8 | `hash-join` ← `sscan n2` → `temp(group by)` hash | |
| 인덱스 사용 | **PK 3개**(lineitem, customer, supplier) | **0개** (전부 순차 스캔 + 해시) |

**행 추정 대 실제**

| 노드 | CUBRID 추정 | CUBRID 실제 | 비 | PG 추정(×loops) | PG 실제 | 비 |
|---|---|---|---|---|---|---|
| lineitem 스캔 | — (인덱스 진입) | 22,785,019 키 read / **18,227,506** 통과 | — | 71,985,828 | **59,986,052** | 1.20x 과대 |
| part 필터 | 13,282 | **13,452** | 0.987x | 19,998 | **13,452** | 1.49x 과대 |
| orders 날짜 필터 | 4,531,771 | **4,557,513** | 0.994x | 5,423,898 | **4,557,513** | 1.19x 과대 |
| lineitem ⋈ part | 8,718,007 (idx-join 산출) | **18,227,506** | **0.478x (2.09x 과소)** | 479,910 | **403,487** | 1.19x 과대 |
| ⋯ ⋈ orders | 51,676 | **122,404** | **0.422x (2.37x 과소)** | 28,920 | **24,254** | 1.19x 과대 |
| ⋈ customer | 51,676 | **122,393** | 0.422x | — | 910,360(해시측) | — |
| ⋈ region 이후 | 10,335 | **24,254** | **0.426x (2.35x 과소)** | 28,158 | **24,254** | 1.16x 과대 |
| 최종 | 10,313 | **24,254** | 0.425x | 28,158 | **24,254** | 1.16x |

* CUBRID의 **한 자릿수 스칼라 추정(orders 날짜 0.994x, part 0.987x)은 정확**하다 — ADR 0008의 히스토그램이 실제로 먹고 있다.
* 무너지는 지점은 **조인 카디널리티** 하나다: `orders ⋈ lineitem`을 8.72 M으로 보고 실제는 18.23 M(2.09x). 그 오차가 상위 전 노드로 그대로 전파돼 최종 2.35x 과소가 된다.
* CUBRID 자기 비용 모델: 정본 플랜 **3,237,206**, PG 형상 강제 시 **6,887,730**(2.13배 비싸다고 봄). 그런데 실측은 9.278 s ↔ 9.287 s로 **사실상 동률**이다(§2.1). 즉 **비용 모델의 상대 순위는 실측과 어긋나지만, 어긋남이 결과를 바꾸지 않는다**.

**CUBRID 노드별 워커 분포 (ADR 0018 — 플랜 채증으로만 인용)**

G2 표기 `4×2 1×5 2×6`을 trace로 재확인했고, **시간 가중은 §2.2**에서 별도로 낸다.
표기가 빠뜨린 것이 하나 있다 — **워커 0(직렬) 노드**다. Q8에서 이용률을 잃는 곳이 바로 거기다.

| 노드 | 워커 | 자기 시간 (trace, ms) | 비중 |
|---|---|---|---|
| `SUBQUERY (uncorrelated)` ×4 | 2 (gather 래퍼) | ~0 | 0 % |
| `SCAN (table: dba.part)` | 5 | 120 | 1.0 % |
| `SCAN (table: dba.orders)` + 하위 `iscan lineitem` | **6** | **9,480** | **82.9 %** |
| `HASHJOIN PROBE` (part) | **6** | 385 | 3.4 % |
| **`SCAN (index: customer.pk)`** | **없음(직렬)** | **1,826** (btree 1,176 + lookup 650) | **16.0 %** |
| `SCAN (index: supplier.pk)` | **없음(직렬)** | 89 | 0.8 % |
| 나머지 hash/temp/groupby | 직렬 | ~50 | 0.4 % |

### 1.4 무효 런 (ADR 0006)

| 런 | 사유 | 처리 |
|---|---|---|
| `PGSER-cubshape rep1` | sda 물리 read **1,065.7 MiB** (문턱 100 MiB 초과) | 폐기 |
| `PGSER-cubshape rep2` | sda 물리 read **1,485.3 MiB** | 폐기 |

→ warmup부터 재수행한 `PGSER-cubshape2` 세트(sda 0.0~0.1 MiB)로 대체했다. 그 값만 §2.1에 쓴다.
그 외 모든 집계 런의 sda 델타는 0.0~0.2 MiB다.

---

## 2단계 — 축 분리 (플랜 / 실행 단위 / 행당 실행 비용)

### 결론 5줄

1. **플랜 축은 격차를 만들지 않는다.** CUBRID에 PG 형상을 강제해도 **0.999x**(같은 브래킷 5런) — 즉 CUBRID가 PG의 좋은 플랜을 받아도 여전히 PG보다 **3.96배** 느리다.
2. 반대 방향은 크게 벌어진다 — **PG에 CUBRID 형상을 강제하면 1.870x 느려진다**(직렬 대 직렬). 형상 자체는 실제로 나쁘고, **CUBRID만 그 나쁨을 못 느낀다**. 이유는 §2.3의 행당 비용이 형상 차이를 압도하기 때문이다.
3. **실행 단위 축이 처음으로 닫히지 않았다** — CUBRID 이용률 **5.187/6 = 86.5 %**, PG **5.856/6 = 97.6 %**, 비 **1.129x**. ADR 0018 라벨은 **`병렬 유지`**(80 % 이상)지만 측정된 세 쿼리 중 최저다.
4. 이용률 손실의 정체를 스레드 표본화(0.05 s × 225표본)로 특정했다 — **질의 마지막 1.4 s(전체의 15.1 %)에 `parallel-query` 실행 스레드가 0**이고 leader(`transaction`) 하나만 돈다. 그 구간은 `customer` PK 인덱스 NL(1,826 ms)이다.
5. 3축 곱 **0.999 × 0.931 × 4.256 = 3.960**, 실측 3.9599 → **검산 오차 0.01 %**. 정본 형상 2축 분해도 **3.508 × 1.129 = 3.960**(오차 0.02 %).

### 2.1 플랜·조인 전략 축 — 같은 엔진 A/B

**(A) CUBRID에 PG 형상 강제** — `/*+ ORDERED USE_HASH */` + FROM 순서 `lineitem, part, orders, customer, n1, region, supplier, n2`.

형상 일치를 **노드별 실제 행수로 채증**했다 (`raw/s2/cub-pgshape.trace` ↔ `raw/s1p/pg-q8.plan`):

| 노드 | CUBRID(PG형상 강제) | PG(정본) | 일치 |
|---|---|---|---|
| lineitem 스캔 | 59,986,052 | 59,986,052 | ✅ 완전 일치 |
| part 스캔 → 필터 | 2,000,000 → 13,452 | 2,000,000 → 13,452 | ✅ |
| lineitem ⋈ part | **403,487** | **403,487** | ✅ 완전 일치 |
| orders 스캔 → 날짜 필터 | 15,000,000 → 4,557,513 | 15,000,000 → 4,557,513 | ✅ |
| customer 스캔 | 1,500,000 | 1,500,000 | ✅ |
| 최종 | 24,254 | 24,254 | ✅ |

| CUBRID 변형 | wall (문장, ×5) | sd |
|---|---|---|
| **정본 플랜** | **9.278 s** | 0.084 |
| **PG 형상 강제** | **9.287 s** | 0.032 |
| **플랜 축** | **0.999x** | 두 sd 안 — 유의차 없음 |

교차 검증(정본↔형상 강제를 6회 번갈아, 다른 창): 정본 9.208/9.077 vs 형상 9.321/9.338 → **0.980x**.
별도 세트(s2, read-heavy 창): 정본 9.230 vs 형상 9.450 → **0.977x**.
→ **플랜 축은 0.98~1.00 구간이고, 어느 값을 써도 결론은 같다: 플랜은 격차의 원인이 아니다.**

**(B) PG에 CUBRID 형상 강제** — `join_collapse_limit=1` + `cross join lateral (… offset 0)` 펜스.
`join_collapse_limit=1`만으로는 **조인 트리만 고정되고 outer/inner가 뒤집혀**(PG가 lineitem을 outer로 잡음)
CUBRID 형상이 되지 않았다. `enable_hashjoin=off`도 마찬가지였다(`Memoize` + orders를 inner로).
`offset 0` 펜스가 유일하게 성공했으나 **그 펜스가 병렬 경로를 죽인다** — 그래서 **양쪽을 직렬로 놓고**(`max_parallel_workers_per_gather=0`) 비교했다. 병렬 축을 제거했으므로 플랜 축만 남는다.

형상 일치 채증 (`raw/s2/pg-cubshape-ser.ana` ↔ CUBRID 정본 trace):

| 노드 | PG(CUBRID형상 강제) | CUBRID(정본) | 일치 |
|---|---|---|---|
| orders 스캔(날짜) | 4,557,513 | 4,557,513 | ✅ |
| **인덱스 NL → lineitem PK** | **18,227,506** (Index Searches 4,557,513) | **18,227,506** (readkeys 22,785,019 → filteredkeys 18,227,506) | ✅ 완전 일치 |
| ⋈ part (hash, build 13,452) | 122,404 | 122,404 | ✅ |
| ⋈ customer (인덱스 NL) | 122,404 | 122,393 | ✅ |
| ⋈ n1 / region / supplier / n2 | 122,404 / 24,254 / 24,254 / 24,254 | 122,404 / 24,254 / 24,248 / 24,254 | ✅ |

| PG 변형 (양쪽 직렬) | wall (end-to-end) | sd | 물리 read |
|---|---|---|---|
| **정본 플랜** | 12.345 / 12.317 / 12.407 → **12.356 s** | 0.045 | 0.0 MiB |
| **CUBRID 형상 강제** | 23.082 / 23.170 / 23.084 → **23.112 s** | 0.050 | 0.0~0.1 MiB |
| **역방향 플랜 축** | **1.870x** | | |

PG 직렬 CUBRID형상의 시간 내역: `Nested Loop(orders→lineitem PK)` **21,720 ms / 24,638 ms = 88.2 %**.
CUBRID 정본에서 같은 부분은 **9,480 ms를 6단위로** 돌린다 → 단위-초 환산 **56.9 vs 21.7 = 2.62x**.

**해석**: CUBRID 형상은 PG에서 실제로 1.87배 나쁘다. 그런데 CUBRID에서는 두 형상이 동률이다.
**CUBRID의 행당 비용이 워낙 커서 "18.2 M행 인덱스 NL"과 "60 M행 순차 스캔 + 해시"가 같은 값이 된다** —
즉 CUBRID 옵티마이저가 좋은 플랜을 골랐는지 나쁜 플랜을 골랐는지가 **관측 불가능한 수준**이다.

### 2.2 실행 단위 이용률 축 (ADR 0018)

| 채증 | CUBRID 정본 | CUBRID PG형상 | PG 정본 |
|---|---|---|---|
| wall (문장, ×5 평균) | 9.278 s | 9.287 s | 2.343 s |
| **SUT CPU / 런** | **49.378 s** | **63.842 s** | **13.720 s** |
| ↳ 질의 실행분(`parallel-query`+`transaction`+단명 워커 잔차) | **48.130 s** | **58.390 s** | 13.720 s (leader 2.202 + workers 11.518) |
| ↳ **내부 배경 스레드** (`pgbuf-page-flush` 외) | **1.248 s** | **5.452 s** | **N/A (SUT 경계 밖 — bgwriter/checkpointer)** |
| **CPU/wall (질의 실행분)** | **5.187** | **6.287** | **5.856** |
| **6단위 대비 이용률** | **86.5 %** | **104.8 %** | **97.6 %** |
| ADR 0018 라벨 | **병렬 유지** (80 % 이상) | 병렬 유지 | 병렬 유지 |
| PG `io worker` (별개 열) | N/A | N/A | **3.196 s/런 = SUT의 +20.8 %** |
| `broker+CAS` 역할 (별개 열) | csql user 0.01 s | 동일 | N/A (backend 내부) |

세 열(SUT CPU / 배경 스레드 / io worker)을 합산한 단일 숫자는 내지 않는다.

**교차 검증**: `perf stat -p <cub_server>`(프로세스 스코프) task-clock **49,048.74 ms**
↔ `/proc` 브래킷 SUT CPU **49.378 s** → **−0.7 %**.

#### 이용률을 어디서 잃는가 — 스레드 동시성 직접 표본화

수집기 코어 20-23에서 0.05 s × 225 표본(`raw/thr/thr.json`). 질의는 t=1.05에 시작해 t≈10.32에 끝난다.

| 구간 | t (s) | 길이 | `parallel-query` 존재/실행 | leader 실행 | 대응 노드 |
|---|---|---|---|---|---|
| 1 | 1.07–6.19 | **5.12 s** | 12 / **6** | 0 | `sscan orders`(6) + `iscan lineitem`, `sscan part`(5)·gather(2) 중첩 |
| 2 | 6.19–8.95 | **2.76 s** | 7 / **6** (8.18–8.65 구간 5) | 0 | `HASHJOIN PROBE`(part, 6) |
| 3 | **8.95–10.32** | **1.37 s** | 7 / **0** | **1** | **`iscan customer.pk` NL + 상위 hash/groupby — 완전 직렬** |

산술 검증: 7.88 s × 6 + 1.37 s × 1 = **48.6 단위-초** ↔ 실측 질의 실행분 CPU **48.13 s** (−1.0 %).

**직렬 구간의 정체는 gather 위의 중간 리스트 스캔이다.** trace에서 `SUBQUERY (parallel workers: 2)` 아래
`SCAN (temp … fetch: 668)`가 122,404행짜리 리스트 파일을 읽고, 그 위 `iscan customer.pk`에는
`(parallel workers: N)` 주석이 **없다**.

소스: `src/query/parallel/px_scan/px_scan.cpp:885`가 리스트 스캔의 병렬도를
`compute_parallel_degree(SCAN, list_id->page_cnt, hint)`로 정하고,
`src/query/parallel/px_parallel.cpp:118-122`가 **`num_pages < parallel_scan_page_threshold`면 0(직렬)** 을 먼저
반환한다. 기본값은 `src/base/system_parameter.c:5135-5140`의 **2048**(hidden, `PRM_FOR_SERVER`).
Q8의 중간 리스트는 668페이지 → **직렬 확정**. 그리고 **문턱 검사가 힌트 처리보다 먼저**이므로
`/*+ PARALLEL(n) */`로도 못 넘긴다.

기제 확증(정본 Q8 아닌 진단 변형, `p_type like 'ECONOMY%'`로 중간 리스트를 3,628페이지로 키움):
같은 위치의 `SCAN (temp …)`에 **`(parallel workers: 2)`가 나타난다**
(`raw/s2/cub-wide.trace`). 문턱을 넘으면 병렬이 켜지되 `floor(log2(3628/2048))+2 = 2`로 **degree 2**에 그친다.

**상한 산정**: 그 1.37 s가 6단위로 돌면 1.37 × (1 − 1/6) = **1.14 s** 절감 → 9.278 → **8.14 s**,
배수 3.960x → **3.47x**. 즉 이 한 항목이 Q8 격차의 **12.9 %**다.

**ADR 0018 부기 제안**: G2 분류표의 `4×2 1×5 2×6` 표기는 **워커 0(직렬) 노드를 아예 세지 않는다.**
Q8에서 이용률을 잃는 노드는 그 표기에 등장조차 하지 않는다. 분포 표기에 **직렬 노드 수**를 함께 적어야 한다.

### 2.3 행당 실행 비용 축

형상이 일치한 상태(CUBRID PG형상 ↔ PG 정본, §2.1 A에서 노드별 행수 완전 일치)의 CPU 비:

| | CUBRID (PG형상) | PG (정본) | 비 |
|---|---|---|---|
| 질의 실행분 CPU/런 | **58.390 s** | **13.720 s** | **4.256x** |
| 처리 행수 | 동일 (노드별 채증) | 동일 | 1.000x |

정본 형상끼리의 CPU 비도 함께 낸다 — 이쪽은 **처리 행수가 다르다**(CUBRID 18.2 M 인덱스 NL vs PG 60 M 순차):

| | CUBRID (정본) | PG (정본) | 비 |
|---|---|---|---|
| 질의 실행분 CPU/런 | **48.130 s** | **13.720 s** | **3.508x** |

### 2.4 곱 분해와 검산

**형상 일치 기준 3축**

```
wall 배수 3.9599  =  플랜 0.9990  ×  실행단위 0.9314  ×  행당 4.2559
                  =  3.9596                                    검산 오차 0.01 %
   플랜   = 9.278 / 9.287                (CUBRID 정본 ÷ CUBRID PG형상)
   실행단위 = 5.856 / 6.287                (PG 이용률 ÷ CUBRID PG형상 이용률)  ← 1 미만: CUBRID가 더 씀
   행당    = 58.390 / 13.720              (형상 일치 CPU 비)
```

**정본 형상 기준 2축 (더 단순하고 같은 값)**

```
wall 배수 3.9599  =  SUT CPU(질의실행분) 3.5080  ×  이용률 1.1290
                  =  3.9605                            검산 오차 0.02 %
```

**두 분해가 말하는 것은 하나다** — CUBRID 옵티마이저는 **CPU 작업량이 더 적은 플랜**(48.13 s vs 형상강제 58.39 s,
−17.6 %)을 골랐고, 그 대가로 **이용률을 잃었다**(86.5 % vs 104.8 %). 두 효과가 정확히 상쇄돼
wall이 0.1 % 차로 같아진다. 옵티마이저의 선택은 **CPU 기준으로는 옳고 wall 기준으로는 무의미**하다.

**부기**: CUBRID PG형상 변형은 이용률이 **104.8 %로 6단위를 넘는다.** 표본화에서 t=1.27–2.30(약 1.0 s) 동안
`parallel-query` **실행 스레드가 12개**로 관측됐다(`lineitem` 6워커 스캔과 `orders` 6워커 스캔이 서로 다른
gather 아래에서 동시에 돈다). 단위 파리티는 **노드 단위 상한이지 질의 단위 상한이 아니다** — 기록 대상이다.

---

## 3단계 — 대칭 프로파일링

### 결론 5줄

1. 수집은 양쪽 동일 — `perf record -a -C 0-15`, 고정 주기 `-c 10000000`, **콜그래프 미부착**, `instructions:u`/`cycles:u` 둘 다. perf 자신은 코어 20-23. SUT 귀속은 report 단계에서 pid 집합으로 한다.
2. **귀속 검증 통과** — CUBRID `perf stat -p <cub_server>` 실측 260,138,992,131 instr / 121,803,325,638 cycles ↔ 샘플 귀속 합 **260.34 G / 122.11 G** → **+0.08 % / +0.25 %**.
3. **오버헤드 5 % 이내 통과** — PG: perf 없음 2.323/2.368 s ↔ `-c 10M` 2.343/2.362 s(**+0.3 %**) ↔ `-c 100M` 2.350 s. CUBRID: perf 없음 9.372/9.217 s ↔ perf 부착 8.972 s(**−3.5 %**, 노이즈 방향).
4. **IPC가 크게 갈린다** — CUBRID **2.132** vs PG **1.374** = **1.552x**(Q9 1.40x보다 크다). 따라서 **`instructions` 비 5.796x는 시간 격차의 상한**이고 **`cycles` 비 3.734x가 wall 3.960x에 가깝다.**
5. **정본 형상에서는 B-tree가 1위(instr 39.2 % / cycles 35.1 %)지만 형상을 맞추면 B-tree는 0 %가 되고 그 자리를 식 평가/튜플 구성(cycles 26.9 %)·스캔/힙 디코드(22.0 %)·버퍼 래치(15.9 %)가 채운다.** Q8의 본질은 후자다.

### 3.1 프로파일 배수 (이벤트 명기 의무)

| 비교쌍 | instructions:u | cycles:u | wall | IPC (C / P) |
|---|---|---|---|---|
| **정본 형상** CUBRID ↔ PG | **5.796x** (260.34 G / 44.92 G) | **3.734x** (122.11 G / 32.70 G) | 3.960x | 2.132 / 1.374 = **1.552x** |
| **형상 일치** CUBRID(PG형상) ↔ PG | **8.067x** (362.37 G / 44.92 G) | **4.910x** (160.55 G / 32.70 G) | 3.964x | 2.257 / 1.374 = **1.643x** |

* `instructions` 비는 두 경우 모두 wall을 **46~103 % 과장**한다. 주 표는 `instructions`로 두되 판단은 `cycles`로 한다.
* 형상 일치 쌍에서 **`cycles` 비 4.910x가 wall 3.964x보다 크다** — 이유는 두 가지이고 둘 다 측정으로 닫힌다:
  (a) CUBRID PG형상의 이용률이 **6.287**로 PG 5.856보다 **1.074x** 높다,
  (b) `cycles:u`는 커널 시간을 세지 않는데 PG의 sys 비중이 **23.2 %**(3.184/13.720)로 CUBRID 11.9 %보다 크다.
  4.910 ÷ (1.074 × 1.131[유효 주파수 비 2.68 GHz vs 2.37 GHz]) = **4.04** ≈ wall 3.96 (2 % 내).

### 3.2 기능 단계 버킷 — 분류 규칙은 Q1 ∪ Q21 ∪ Q9 UNION (변경 없이 적용)

`ExecParallelScanHashBucket`은 **집계·해시·해시조인**으로 분류된다(`^ExecParallel` 병렬 인프라 규칙보다
앞선 명시 규칙). Q8에서도 그대로다 — PG cycles의 **20.34 %**를 쥔 단일 심볼이다.

#### (a) 정본 형상 — instructions:u (CUBRID 260.34 G / PG 44.92 G / 격차 215.42 G)

| 기능 단계 | CUBRID | PG | 비 | 기여 | C% | P% |
|---|---|---|---|---|---|---|
| **인덱스 탐색·키 비교 (B-tree)** | 84.50 G | 0 | ∞ | **39.2 %** | 32.5 % | 0.0 % |
| 스캔·레코드 디코드·힙 접근 | 54.42 G | 21.88 G | 2.49x | 15.1 % | 20.9 % | 48.7 % |
| 식 평가/튜플 구성 | 34.11 G | 2.64 G | 12.92x | 14.6 % | 13.1 % | 5.9 % |
| 값/도메인 변환 | 18.67 G | 0.08 G | 233.4x | 8.6 % | 7.2 % | 0.2 % |
| 버퍼 고정·해제·래치 | 20.10 G | 2.06 G | 9.76x | 8.4 % | 7.7 % | 4.6 % |
| 술어 평가 | 9.45 G | 0.21 G | 45.0x | 4.3 % | 3.6 % | 0.5 % |
| MVCC·가시성·트랜잭션 | 9.02 G | 0.11 G | 82.0x | 4.1 % | 3.5 % | 0.2 % |
| 수치 연산 (DECIMAL) | 8.66 G | 0.03 G | 288.7x | 4.0 % | 3.3 % | 0.1 % |
| TLS/런타임 | 4.50 G | 0 | ∞ | 2.1 % | 1.7 % | 0.0 % |
| **집계·해시·해시조인** | 8.13 G | 15.53 G | **0.52x** | **−3.4 %** | 3.1 % | 34.6 % |
| (그 외 6버킷 합) | 8.83 G | 2.35 G | — | 2.8 % | — | — |

#### (b) 정본 형상 — cycles:u (CUBRID 122.11 G / PG 32.70 G / 격차 89.41 G)

| 기능 단계 | CUBRID | PG | 비 | 기여 | instr 순위 → cycles 순위 |
|---|---|---|---|---|---|
| **인덱스 탐색·키 비교 (B-tree)** | 31.38 G | 0 | ∞ | **35.1 %** | 1 → **1** |
| **버퍼 고정·해제·래치** | 19.45 G | 1.72 G | 11.31x | **19.8 %** | **5 → 2 (역전)** |
| 식 평가/튜플 구성 | 14.16 G | 1.12 G | 12.64x | 14.6 % | 3 → 3 |
| **스캔·레코드 디코드·힙 접근** | 25.63 G | 14.50 G | 1.77x | **12.4 %** | **2 → 4 (역전)** |
| 값/도메인 변환 | 7.09 G | 0 | ∞ | 7.9 % | 4 → 5 |
| 술어 평가 | 3.96 G | 0.08 G | 49.5x | 4.3 % | 6 → 6 |
| MVCC·가시성·트랜잭션 | 4.08 G | 0.32 G | 12.75x | 4.2 % | 7 → 7 |
| 수치 연산 (DECIMAL) | 3.22 G | 0.05 G | 64.4x | 3.5 % | 8 → 8 |
| **집계·해시·해시조인** | 4.24 G | 13.20 G | **0.32x** | **−10.0 %** | −3.4 % → **−10.0 %** |

**cycles에서 순위가 뒤집히는 지점 (명시 의무)**
1. **버퍼 고정·해제·래치: instr 5위 8.4 % → cycles 2위 19.8 %.** `pgbuf_fix_release`가 instr 2.31 % → cycles 3.78 %, `pgbuf_unfix`가 cycles 2.13 %. 메모리 대기가 명령 수에 안 잡힌다.
2. **스캔·힙 디코드: instr 2위 15.1 % → cycles 4위 12.4 %.** CUBRID 쪽이 상대적으로 IPC가 높다.
3. **집계·해시: 기여 −3.4 % → −10.0 %.** PG `ExecParallelScanHashBucket`의 IPC가 **0.85**(instr 12.62 %/cycles 20.34 %)로 PG 평균 1.374보다 훨씬 낮아, cycles로 보면 PG가 이 버킷에서 훨씬 더 손해다.

#### (c) 형상 일치 — cycles:u (CUBRID PG형상 160.55 G / PG 32.70 G / 격차 127.85 G)

| 기능 단계 | CUBRID(PG형상) | PG | 비 | 기여 |
|---|---|---|---|---|
| **식 평가/튜플 구성** | 35.49 G | 1.12 G | **31.69x** | **26.9 %** |
| **스캔·레코드 디코드·힙 접근** | 42.64 G | 14.50 G | 2.94x | **22.0 %** |
| **버퍼 고정·해제·래치** | 22.08 G | 1.72 G | 12.84x | **15.9 %** |
| 값/도메인 변환 | 14.76 G | 0 | ∞ | 11.5 % |
| 수치 연산 (DECIMAL) | 10.84 G | 0.05 G | 216.8x | 8.4 % |
| TLS/런타임 | 5.91 G | 0 | ∞ | 4.6 % |
| MVCC·가시성·트랜잭션 | 4.70 G | 0.32 G | 14.69x | 3.4 % |
| 술어 평가 | 3.87 G | 0.08 G | 48.4x | 3.0 % |
| **인덱스 탐색·키 비교 (B-tree)** | **0** | **0** | — | **0.0 %** |
| 집계·해시·해시조인 | 14.49 G | 13.20 G | 1.10x | 1.0 % |

**Q1형 3버킷(식 평가 + 값/도메인 + 수치) 합 = cycles 46.8 % / instructions 53.3 %.**
여기에 스캔·힙 디코드 22.0 %를 더하면 **68.8 %**다. **지배 버킷이 하나 있다: 행당 인터프리테이션.**

### 3.3 상위 심볼 정면 대조 (형상 일치, cycles)

| 역할 | CUBRID (PG형상) | PG | 비 |
|---|---|---|---|
| **튜플 디코드** | `heap_attrinfo_read_dbvalues` 13.22 % = **21.22 G** | `tts_buffer_heap_getsomeattrs` 28.53 % = **9.33 G** | **2.27x** |
| **튜플 재구성·전달** | `qdata_generate_tuple_desc_for_valptr_list` 6.20 + `qdata_copy_db_value_to_tuple_value` 5.71 + `fetch_val_list` 4.88 + `qdata_get_tuple_value_size_from_dbval` 2.55 + `qfile_generate_tuple_into_list` 2.52 = 21.86 % = **35.10 G** | `ExecInterpExpr` 3.43 + `ExecJustHashOuterVarStrict` 1.74 + `ExecStoreBufferHeapTuple` 1.90 + `MemoryContextReset` 2.29 = 9.36 % = **3.06 G** | **11.5x** |
| **수치 디코드** | `mr_data_readval_numeric` 4.47 % = **7.18 G** | `do_numeric_accum`+`init_var_from_num`+`make_result_safe` 0.09 % = **0.03 G** | **234x** |
| **버퍼 관리** | `pgbuf_get_victim_candidates_from_lru` 5.09 % + `pgbuf_fix_release`/`pgbuf_unfix` = **22.08 G**(버킷) | `LWLockAttemptLock` 1.74 % + `LockBufHdr` 0.46 % 등 = **1.72 G** | **12.8x** |
| **해시 조인** | `mht_get_hls` 2.75 + `hjoin_fetch_key` 2.73 % = **14.49 G**(버킷) | `ExecParallelScanHashBucket` 20.34 + `ExecParallelHashJoin` 6.02 + `dsa_get_address` 5.11 % = **13.20 G**(버킷) | **1.10x** |
| 타입 디스패치 | `pr_type_from_id` 2.05 %, `__tls_get_addr` 1.94 % | (대응물 없음 — 컴파일타임 인라인) | ∞ |

**해시 조인만 1.10x다.** CUBRID의 해시 조인 자체는 PG와 대등하다. 격차 전부가 **그 앞뒤에서
튜플을 DB_VALUE로 풀고 다시 리스트 파일 튜플로 싸는 비용**에 있다.

### 3.4 네 쿼리 나란히 (Q1 ∪ Q21 ∪ Q9 UNION 규칙, 동일 적용)

**instructions:u — 격차 기여도 / CUBRID 비중 / 엔진 간 비**

| 기능 단계 | Q1 (3.070x) | Q21 (14.32x) | Q9 (2.741x) | **Q8 정본 (3.960x)** | **Q8 형상일치** |
|---|---|---|---|---|---|
| 인덱스 탐색·키 비교 (B-tree) | 0.0 % | **51.5 %** (69.7x) | 11.6 % (3.2x) | **39.2 %** (∞) | **0.0 %** |
| 스캔·레코드 디코드·힙 접근 | 9.9 % (3.3x) | 14.3 % (7.1x) | **23.8 %** (5.2x) | 15.1 % (2.5x) | **26.1 %** (4.8x) |
| 식 평가/튜플 구성 | **31.2 %** (5.9x) | 3.7 % (6.5x) | **23.6 %** (9.8x) | 14.6 % (12.9x) | **30.6 %** (37.8x) |
| 값/도메인 변환 | **22.0 %** (8.0x) | 3.0 % (175x) | 9.2 % (6.2x) | 8.6 % (233x) | **13.5 %** (538x) |
| 버퍼 고정·해제·래치 | 0.1 % | 12.4 % (19.0x) | 13.3 % (4.2x) | 8.4 % (9.8x) | 4.1 % (7.4x) |
| 수치 연산 (DECIMAL) | **16.3 %** (1.8x) | 0.0 % | 8.0 % (5.9x) | 4.0 % (289x) | 9.2 % (975x) |
| MVCC·가시성 | 0.9 % | 2.9 % | 3.0 % | 4.1 % (82x) | 3.6 % (105x) |
| 술어 평가 | 2.1 % | 3.7 % | 1.5 % | 4.3 % (45x) | 3.2 % (49x) |
| 집계·해시·해시조인 | 10.6 % (4.7x) | −0.6 % | 2.2 % | **−3.4 %** (0.52x) | 4.0 % (1.8x) |
| **Q1형 3버킷 합** | **69.5 %** | 6.7 % | **40.8 %** | 27.2 % | **53.3 %** |

**cycles:u — 격차 기여도 (Q1은 cycles 미수집)**

| 기능 단계 | Q21 | Q9 | **Q8 정본** | **Q8 형상일치** |
|---|---|---|---|---|
| 인덱스 탐색·키 비교 (B-tree) | **35.9 %** (42.4x) | 11.9 % (3.1x) | **35.1 %** (∞) | 0.0 % |
| 버퍼 고정·해제·래치 | 24.4 % (23.8x) | **27.8 %** (4.4x) | **19.8 %** (11.3x) | **15.9 %** (12.8x) |
| 식 평가/튜플 구성 | 5.4 % | 17.7 % (8.4x) | 14.6 % (12.6x) | **26.9 %** (31.7x) |
| 스캔·레코드 디코드·힙 접근 | 12.8 % | 20.1 % (3.3x) | 12.4 % (1.8x) | **22.0 %** (2.9x) |
| 값/도메인 변환 | 2.9 % | 8.2 % | 7.9 % | 11.5 % |
| 수치 연산 (DECIMAL) | 0.0 % | 5.9 % | 3.5 % | 8.4 % (217x) |
| 집계·해시·해시조인 | −0.8 % | −4.7 % | **−10.0 %** (0.32x) | 1.0 % |

**축 분해 나란히**

| | Q1 | Q21 | Q9 | **Q8** |
|---|---|---|---|---|
| wall 배수 (단위 파리티) | 3.070x | 14.32x | 2.741x | **3.960x** (read-light) / 3.43x (read-heavy) / 3.74x (G2 stream) |
| 플랜 축 | 미측정 | **4.436x** | 0.984x | **0.999x** |
| 역방향 플랜 축 (상대에 형상 강제) | — | — | 1.35x | **1.870x** |
| 실행 단위 축 | ~1 | **1.002x (0.2 %)** | **0.998x (0.23 %)** | **1.129x (12.9 %)** ← **처음으로 열림** |
| 행당 실행 비용 축 | 3.070x | 3.228x | 2.785x | **3.508x (정본) / 4.256x (형상 일치)** |
| CUBRID 이용률 | 98.8 % | 96.97 % | 98.8 % | **86.5 %** |
| IPC (C / P) | 2.339 / 2.357 | — | 1.929 / 1.378 | **2.132 / 1.374** |
| 유형 | Q1형 | 플랜형 | Q1형+B-tree 하이브리드 | **Q1형 + 단위 손실** |

---

## 4단계 — 소스 규명 · 개선 후보

### 결론 5줄

1. Q8의 격차는 **행당 인터프리테이션 4.256x**(형상 일치 CPU 비)와 **실행 단위 손실 1.129x**의 곱이고, **플랜은 기여하지 않는다**.
2. 행당 비용의 단일 최대 심볼은 **`heap_attrinfo_read_dbvalues`(cycles 13.22 %)** 이며, 그 아래 `heap_attrvalue_read` → `heap_attrvalue_transform_to_dbvalue`가 **속성마다 `pr_clear_value` + `pr_type_from_id` 테이블 조회 + 가상 함수 `data_readval` 디스패치**를 돈다. PG는 같은 일을 `slot_deform_heap_tuple` 인라인 루프로 한다.
3. 두 번째는 **튜플 재구성 체인 11.5x** — CUBRID는 노드 경계마다 DB_VALUE를 리스트 파일 튜플 바이트로 복사한다(`qdata_copy_db_value_to_tuple_value`). PG는 `TupleTableSlot` 포인터를 넘긴다.
4. **NUMERIC 234x**가 그 위에 얹힌다 — `l_extendedprice`/`l_discount`는 조인 구간에서 값이 필요 없는데도 CUBRID는 행마다 `db_make_numeric`으로 DB_VALUE 내부 버퍼에 복사한다. PG는 최종 집계까지 varlena 포인터로 흘린다.
5. **교차 후보 2개(BCB 뮤텍스·pin 캐시 / B-tree descent·midxkey)는 Q8에서도 유효**하고, 여기에 **3개를 신규 등재**한다. 그중 ①·②는 Q1·Q9·Q8 세 쿼리에 걸치므로 **최우선**이다.

### 4.1 후보표

| # | 후보 | file:line | Q8 프로파일 근거 | 난이도 | 위험 | 교차 |
|---|---|---|---|---|---|---|
| **①** | **힙 튜플 디코드 인터프리테이션 제거** — 속성별 `pr_type_from_id` 조회와 가상 `data_readval` 디스패치를 스캔 오픈 시점에 고정 함수 포인터/스위치로 특화(per-`OR_ATTRIBUTE` 캐시), `pr_clear_value`를 고정폭 타입에서 생략 | `src/storage/heap_file.c:10255-10302` (`heap_attrvalue_transform_to_dbvalue`), `:10315-10358` (`heap_attrvalue_read`), `:10464-10525` (`heap_attrinfo_read_dbvalues`), `src/object/object_primitive.c:8968-8978` (`pr_type_from_id`) | cycles **13.22 %** 단일 심볼, 스캔·힙 버킷 22.0 % / 2.94x. PG 대응물 `tts_buffer_heap_getsomeattrs` 대비 **2.27x** | 중 | **중** — 표현(representation) 변경 이력이 있는 코드(`heap_attrinfo_recache` 경로), 회귀 범위 넓음 | **Q1 (스캔·힙 9.9 %) · Q9 (23.8 %) · Q8 (26.1 %)** — 3쿼리 |
| **②** | **노드 경계 튜플 재구성 제거** — 중간 결과를 리스트 파일 튜플로 직렬화하지 않고 슬롯 참조로 전달(최소한 해시 조인 build/probe 사이의 pass-through 컬럼) | `src/query/query_opfunc.c:625` (`qdata_generate_tuple_desc_for_valptr_list`), `:356` (`qdata_copy_db_value_to_tuple_value`), `:6327` (`qdata_get_tuple_value_size_from_dbval`), `src/query/fetch.c:4852` (`fetch_val_list`) | cycles **21.86 %**(5심볼 합) = 35.10 G vs PG 3.06 G → **11.5x**. 식 평가/튜플 구성 버킷 기여 **26.9 %** | **상** | **상** — 실행기 데이터 흐름의 근간, XASL 캐시·병렬 gather와 얽힘 | **Q1 (31.2 %) · Q9 (23.6 %) · Q8 (30.6 %)** — 3쿼리, 기여도 최상위 |
| **③** | **BCB 뮤텍스 → 원자 연산 + per-thread pin 캐시** | `src/storage/page_buffer.c:950-957` (`PGBUF_BCB_LOCK/TRYLOCK/UNLOCK` 매크로), `:2211` (`pgbuf_fix_release`), `:3024` (`pgbuf_unfix`), `:3738` (`pgbuf_get_victim_candidates_from_lru`) | cycles 버퍼 버킷 **19.8 %(정본) / 15.9 %(형상일치)**, 11.3~12.8x. 형상일치에서 `pgbuf_get_victim_candidates_from_lru` 단독 **5.09 %** | 중 | 중 | **기존 교차 후보 — Q9 cycles 1위 27.8 %, Q21 cycles 23.67 %, Q8 2~3위**. 4쿼리 |
| **④** | **B-tree descent 페이지 캐시 + midxkey 비교 특화** | `src/storage/btree.c:5190` (`btree_search_nonleaf_page`), `:5538` (`btree_search_leaf_page`), `:19461` (`btree_compare_key`), `src/object/object_primitive.c:7731` (`pr_midxkey_compare`) | **정본 형상에서만** — cycles **35.1 %**(31.38 G). `pr_midxkey_compare` 5.53 %, `btree_search_nonleaf_page` 2.99 %, `btree_search_leaf_page` 2.08 %. **형상 일치에서는 0 %** | 중 | 중 | **기존 교차 후보 — Q21 51.5 %, Q9 11.6 %, Q8 39.2 %(정본)**. 3쿼리 |
| **⑤** | **중간 리스트 스캔 병렬화 문턱을 페이지 수가 아니라 상위 비용으로 판정** — `parallel_scan_page_threshold`(2048) 검사가 힌트보다 먼저 걸려 668페이지 리스트 위의 인덱스 NL이 전부 직렬로 떨어진다 | `src/query/parallel/px_scan/px_scan.cpp:885` (리스트 스캔 degree 결정), `src/query/parallel/px_parallel.cpp:118-122` (문턱 우선 검사), `:139-172` (log2 공식), `src/base/system_parameter.c:5135-5140` (기본 2048) | 스레드 표본화: **wall의 15.1 %(1.37 s)가 실행 단위 1**. 이용률 86.5 % vs PG 97.6 %. **제거 시 3.960x → 3.47x** | **하~중** | 중 — 문턱을 낮추면 작은 리스트에서 워커 기동 비용이 역효과. **비용 기반 판정(하위 노드 예상 행수 × 상위 행당 비용)이 필요** | **Q8 단독(현재)**. ADR 0018이 미측정으로 남긴 **Q5·Q11이 같은 `N×2` 양상**이므로 후속 확인 대상 |
| **⑥** | **NUMERIC pass-through** — 조인 구간에서 소비되지 않는 NUMERIC 컬럼을 DB_VALUE로 풀지 않고 디스크 표현 그대로 전달 | `src/object/object_primitive.c:8743-8800` (`mr_data_readval_numeric` — `db_make_numeric`이 내부 버퍼로 복사) | 수치 버킷 cycles **8.4 %**, **216.8x**. 단일 심볼 `mr_data_readval_numeric` **4.47 %** = 7.18 G vs PG 0.03 G | 중 | 중 | **Q1 (16.3 %) · Q9 (8.0 %) · Q8 (9.2 %)** — 3쿼리. ①의 부분집합으로 묶어 구현 가능 |

**구현은 하지 않았다.**

### 4.2 upstream 유사 시도 (pin 포함 여부)

| 후보 | 유사 커밋/구조 | pin `f30f1c260` 포함 |
|---|---|---|
| ⑤ | `978b628c8 [CBRD-26931] Parallelize uncorrelated scalar subquery inner scan (#7316)` — `SUBQUERY` degree를 1(+gather 2)로 하드코드하고 호출측에 `assert (n_workers_to_reserve == 1)` + 주석 `TODO: Temporarily limited to 2.`를 남김 (`src/query/query_executor.c:16049-16071`) | **포함** |
| ⑤ | 병렬 결정의 단일 창구 `parallel_query::compute_parallel_degree` (`px_parallel.cpp:37`) — SCAN/HASH_JOIN/SORT/SUBQUERY 4타입만 있고 **인덱스 NL 조인용 타입이 없다**(`px_parallel.hpp:29-35`). gather 위의 NL은 리스트 스캔 degree에 전적으로 종속 | **포함** |
| ③ | `pgbuf_Monitor_locks` 디버그 경로가 매크로에 상시 분기로 남아 있음 (`page_buffer.c:950-957`) — 원자화 시 함께 정리 대상 | **포함** |
| ① | `a9fca9002` (CBRD-26663 revert, CHAR/VARCHAR 저장 포맷) — 디코드 경로를 최근 건드린 커밋. 표현 변경 회귀 위험의 근거 | **포함** (ADR 0007) |

### 4.3 Q8이 앞의 세 쿼리에 주는 정정 2건

1. **ADR 0018 부기 필요** — 노드별 워커 분포 표기(`4×2 1×5 2×6`)는 **워커 0(직렬) 노드를 세지 않는다.**
   Q8은 이용률을 잃는 노드가 그 표기에 아예 등장하지 않는 첫 사례다. 분포에 **직렬 노드**를 함께 적어야 하고,
   ADR 0018이 미측정으로 남긴 **Q5·Q11**은 이 관점에서 다시 봐야 한다.
2. **ADR 0016의 "PG 민감도는 쿼리 조건부"에 사례 추가** — Q8 PG는 **민감**하다(미스 −17.5 % → wall −10.6 %,
   단가 2.62 µs/미스). `hit+read` 1,465,669 블록 완전 동일이 근거다. Q9(무감)와 Q21(민감) 사이의 판정 기준은
   "워킹셋이 `shared_buffers`에 들어가는가"보다 **"버퍼 잔존율이 상태에 따라 움직이는가"**가 정확하다 —
   Q8 lineitem 힙은 8.6 GB > 8 GB로 Q9와 같은 조건인데도 잔존율이 43.3 % ↔ 53.3 %로 움직였다.

---

## 채증 색인

| 산출물 | 경로 |
|---|---|
| 1단계 재현 TSV (2세트) | `.git_ignored_dir/q8/raw/{s1-times.tsv, s1r-times.tsv}` |
| **정본 최종 세트** (wall AB/BA + CPU 브래킷) | `.git_ignored_dir/q8/raw/final/{wall.tsv, cub.out, pg.out, cub-reduce.json, pg-reduce.json, cubs.out, cubs-reduce.json}` |
| PG 플랜 (EXPLAIN ANALYZE/BUFFERS/VERBOSE) | `raw/s1p/pg-q8.plan` (read-heavy), `raw/final/pg-q8-2.plan` (read-light) |
| CUBRID 플랜 (OPT LEVEL 514 전체 덤프) | `raw/s1p/cub-q8.plan` |
| CUBRID trace (`;plan detail on` + `;trace on`) | `raw/s1p/cub-q8.trace`, `raw/final/cub-q8-2.trace` |
| 2단계 A/B — CUBRID PG형상 | `raw/s2/{CUB-pgshape-*.out, cub-pgshape.plan, cub-pgshape.trace}`, `scratch/{h-cub-pgshape.sql, r-cub-pgshape.sql}` |
| 2단계 A/B — PG CUBRID형상(직렬) | `raw/s2/{PGSER-native-*.out, PGSER-cubshape2-*.out, pg-cubshape-ser.ana}`, `scratch/{x-pg-native-ser.sql, x-pg-cubshape-ser.sql}` |
| 실패한 형상 강제 시도 2건 (기록) | `scratch/{x-pg-cuborder.sql, x-pg-cubnl.sql}` — `join_collapse_limit=1` / `enable_hashjoin=off`로는 outer/inner가 뒤집혀 CUBRID 형상이 되지 않는다 |
| 병렬 문턱 기제 확증 변형 | `raw/s2/cub-wide.trace`, `scratch/v-cub-wide.sql` |
| 스레드 동시성 표본화 | `raw/thr/{thr.json, thr2.json}` (0.05 s × 225표본) |
| 3단계 perf 데이터·심볼 | `raw/prof/{cubrid,pg,cubshape}-{instructions,cycles}.{data,symbols,sutpids,meta}` |
| 귀속 검증·오버헤드 | `raw/prof/{stat-cubrid.txt, stat-pg.txt, stat-pg-idle.txt, ov-*.rec}` |
| 하네스 | `.git_ignored_dir/q8/scratch/{run-s1.sh, run-s1p.sh, run-s2ab.sh, run-cpu.sh, run-final.sh, run-prof.sh, run-stat.sh, symbols2.sh, classify.py}` |
| 분류 규칙 | `scratch/classify.py` — Q1 ∪ Q21 ∪ Q9 UNION 규칙 **무변경**, `SETS`에 `Q8`(정본) / `Q8s`(형상 일치) 두 항목만 추가 |

### perf 수집 파라미터 (양쪽 동일)

```
perf record -a -C 0-15 -e {instructions:u | cycles:u} -c 10000000 -o <out>.data -- <client>
  수집기: taskset -c 20-23 (SUT 밖)      콜그래프: 미부착
  SUT 귀속: CUBRID = cub_server 단일 pid / PG = 런 전 미존재 postgres pid 집합
            (io worker·checkpointer·bgwriter는 ADR 0009 경계 밖 → 제외.
             instructions 런에서 구간 중 생성된 io worker 1개(pid 715117, 3샘플)를 사후 제외)
```

| 검증 | CUBRID | PG |
|---|---|---|
| 독립 실측 | `perf stat -p` instr 260,138,992,131 / cycles 121,803,325,638 / task-clock 49,048.74 ms | `perf stat -a -C 0-15` instr 49.927 G − idle 1.154 G = **48.77 G** |
| 샘플 귀속 합 | **260.34 G / 122.11 G** | **44.92 G** |
| 차 | **+0.08 % / +0.25 %** | **−7.9 %** = io worker + psql + 경계 밖 PG 프로세스 (ADR 0017의 별개 열, 합산 금지) |
| SUT 샘플 / 그 외 | 26,034 / 204 | 4,492 / 1,221 |
| 오버헤드 | 9.372·9.217 s(perf 없음) ↔ 8.972 s(부착) = **−3.5 %** | 2.323·2.368 s ↔ 2.343·2.362 s = **+0.3 %**, `-c 100M` +0.2 % |
