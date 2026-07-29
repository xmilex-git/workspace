# Q9 격차 규명 — 2.741x = 플랜 0.984x × 행당 실행 비용 2.785x (플랜 축 없음)

조사 2026-07-29. 단위 파리티 트랙(CUBRID `parallelism=6` ↔ PG 세션 `max_parallel_workers_per_gather=5`+leader
= 양쪽 6 실행 단위, ADR 0014), WARM 하위 레짐 **single-query-repeat**(ADR 0016).
대상은 G2 절대격차 Pareto **3위 Q9**(stream 레짐 19.682 / 7.062 = 2.79x, positive_pareto 9.11 %).

**대외 인용 단서 3건 유효**: PG 개발 스냅샷 핀 · CUBRID `update_statistics_update_histogram=yes`(기본값 이탈) ·
PG `dynamic_shared_memory_type=mmap`(기본값 이탈). 어느 엔진도 "출시 기본 설정 제품의 성능"이 아니다.

## 결론 (5줄)

1. **Q9는 Q1형이다.** 격차가 곱으로 갈렸다 — **2.741x = 플랜·조인 전략 0.984x × 행당 실행 비용 2.785x**
   (같은 세션 검산 `0.9844 × 2.7371 = 2.6944` = 실측 `2.6944`, **오차 0.00 %**).
   **플랜 축의 기여는 0이다** — Q21(4.436x)과 정반대다.
2. **두 옵티마이저가 각자 옳았다.** CUBRID에 PG 플랜 형상을 강제하면 **1.6 % 느려지고**(19.542 → 19.852 s),
   PG에 CUBRID 조인 순서를 강제하면 **35 % 느려진다**(7.253 → 9.798 s).
3. **실행 단위 축도 닫혔다.** wall 비 2.741x ↔ **SUT CPU 비 2.735x**(0.23 % 차). 시간 가중 이용률은
   CUBRID **98.8 %**(질의 실행분 5.927/6) / PG 96.4 %(5.785/6) → 양쪽 `병렬 유지`(ADR 0018).
   `1×2 2×5 2×6`의 2워커 노드는 gather 래퍼이고 그 아래가 6워커다.
4. **지배 버킷이 없다.** 상위 6개가 격차의 89.5 %를 나눈다 — 스캔·레코드 디코드 23.8 %, 식 평가/튜플 구성
   23.6 %, 버퍼 고정·래치 13.3 %, B-tree 11.6 %, 값/도메인 변환 9.2 %, 수치 연산 8.0 %.
   Q1형 3버킷 합 40.8 %(Q1 69.5 %) + Q21의 B-tree 11.6 %(Q21 51.5 %)의 **하이브리드**이며 제3의 축은 없다.
5. **instructions 4.233x가 wall 2.741x를 과장한다** — **IPC CUBRID 1.929 vs PG 1.378 (1.40x)**.
   **cycles 3.022x**가 시간 비에 가깝고, cycles에서 **버퍼 고정·래치가 1위(27.8 %)**로 올라오고
   **집계·해시는 기여 부호가 뒤집힌다**(+2.2 % → −4.7 %, PG `ExecParallelScanHashBucket` IPC 0.27).

## 1. 재현과 플랜 (1단계)

### 1.1 재현

| 항목 | CUBRID | PG |
|---|---|---|
| 실행 단위 수 | **6** (`parallelism=6`, 서버 conf 무변경) | **6** (worker 5 + leader, 세션 `SET`) |
| B1 / B2 / B3 wall | 20.463 / 19.676 / 19.507 | 7.238 / 7.257 / 7.263 |
| **평균 (within-set sd)** | **19.882 s (0.510)** | **7.253 s (0.013)** |
| **배수** | — | **2.741x** |
| G2 stream 기준값 대비 | 19.682 → +1.02 % | 7.062 → +2.70 % |
| 파싱·플랜 시간 (ADR 0011) | **2–3 ms 클라이언트측(SUT 밖)**, 초회 8 ms | `Planning Time` **3.551 ms** (backend 안) |
| warm 채증 sda 물리 read | 6.2 / 0.1 / 0.0 MiB | 0.0 / 0.0 / 0.0 MiB |
| 결과 | **175행**, 정규화 후 PG와 바이트 동일 | 175행, B1=B2=B3 동일 |

배수는 stream 2.788x → single-query-repeat **2.741x**(−1.66 %).

### 1.2 하위 레짐 채증 (ADR 0016)

| 채증 | stream (G2) | single-query-repeat (이번) | 델타 |
|---|---|---|---|
| PG `shared hit` | 20,165,807 | 20,567,873 | +402,066 |
| PG `shared read` | 1,007,160 | 605,102 | **−402,058 (−39.9 %)** |
| **PG `hit+read`** | **21,172,967** | **21,172,975** | **+8 (동일)** |
| PG `temp read/written` | 26,548 / 26,626 | 26,550 / 26,628 | +0.008 % |
| **PG wall** | 7.062 s | 7.253 s | **+2.70 % (개선 아님)** |
| CUBRID trace 최상위 `fetch` | 5,413,536 | 5,413,437 | −0.002 % |
| CUBRID wall | 19.682 s | 19.882 s | +1.02 % |

**Q21과 방향이 다르다.** Q21은 미스 −695 K → wall −11.75 %였는데 Q9는 미스 −402 K → wall **+2.70 %**다.
이유는 구조적이다 — PG `read` 605,102 전량이 `Parallel Seq Scan on lineitem` 노드에 있고(hit 520,026 /
read 605,102), lineitem 힙은 1,125,128 블록 = **8.6 GB > `shared_buffers` 8 GB**다. Q9 PG는 미스 처리
경로에 묶여 있지 않다. CUBRID는 Q21과 같이 무감하다.

### 1.3 플랜 전문 노드 대조

CUBRID `SET OPTIMIZATION LEVEL 514` + `;trace on`, PG `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`.
PG 플랜은 G2와 cost까지 동일(`1581491.07..1581521.56`) → 형상 재현 확인.

| # | 논리 단계 | CUBRID | PG |
|---|---|---|---|
| 1 | part 필터 | `sscan part` sargs `p_name like '%green%'` (5 worker) 2,000,000 → 108,782 | `Parallel Seq Scan on part` 동일 (6 loops) → 108,782 |
| 2 | partsupp 진입 | **없음** | `Parallel Hash Join` `ps_partkey=p_partkey` ← partsupp 8,000,000 seq scan (138 ms) → **435,128** |
| 3 | 해시 빌드 | `BUILD rows 108,782, method: hybrid` | `Parallel Hash` **435,128행**, 32,128 kB, Batches 1 |
| 4 | lineitem 스캔 | `sscan lineitem` (6 worker) 59,986,052, heap time **9,081 ms** | `Parallel Seq Scan lineitem` (6 loops) **1,441 ms** |
| 5 | 해시 프로브 | `PROBE` (6 worker) term[4] `p_partkey=l_partkey` **1컬럼** → **3,261,613**, 2,196 ms | `Parallel Hash Join` `(l_suppkey=ps_suppkey AND l_partkey=ps_partkey)` **2컬럼** → **3,261,613**, 누적 3,651 ms |
| 6 | partsupp 해결 | **`iscan partsupp.pk(ps_partkey,ps_suppkey)` 인덱스 NL, 3,261,603 조회, btree 5,293 + lookup 1,205 ms** | **5번에서 이미 끝남 (추가 0)** |
| 7 | orders 해결 | `iscan orders.pk` btree 3,331 + lookup 819 ms | `Index Scan orders_pkey`, **Index Searches 3,261,613** |
| 8 | supplier 해결 | `iscan supplier.pk` btree 2,814 + lookup 735 ms | `Index Scan supplier_pkey`, **Index Searches 3,261,613** |
| 9 | nation 조인 | `iscan nation.pk` + `MEMOIZE hit 13,045,952 / miss 500` | `Hash Join` ← `Seq Scan nation` 25행 (0.02 ms) |
| 10 | 정렬·집계 | `GROUPBY (hash: partial, page 0, ioread 0) 2 ms` + `ORDERBY 0 ms` | `Sort` **external merge Disk 35,472 kB ×6 스필** → `Partial GroupAggregate` → `Gather Merge` → `Finalize` = **1,355 ms** |

**유일한 형상 차이는 partsupp가 들어오는 자리**다. 그 외에는 둘 다 동일한 전략을 쓴다 —
part LIKE 스캔 → 해시 조인 → lineitem 전체 스캔 프로브 → PK 인덱스 NL로 supplier·orders 채우기 → nation.
정렬·집계 단계는 **CUBRID가 이긴다**(hash partial vs PG의 디스크 스필 정렬).

노드별 워커 (플랜 채증만, ADR 0018): CUBRID **`1×2 2×5 2×6`**(2 = `SUBQUERY(uncorrelated)` gather /
5 = `SCAN(temp)`·`sscan part` / 6 = `PROBE`·`sscan lineitem`) — G2 분포와 완전 일치.
PG `Workers Planned 5 / Launched 5`, 모든 병렬 노드 `loops = 6`.

### 1.4 추정 카디널리티 대 실제 — 두 엔진의 공통 실패

| 노드 | CUBRID est | 실제 | est/실제 | PG est(총) | 실제 | est/실제 |
|---|---|---|---|---|---|---|
| part + LIKE | **60,000** (`sel 0.03` 상수) | 108,782 | **0.55x** | 202,015 (40,403×5) | 108,782 | **1.86x** |
| partsupp 스캔 | 8,000,000 | — | — | 8,001,290 | 8,000,000 | 1.00x |
| part⋈partsupp | (해당 없음) | — | — | 646,570 | 435,128 | 1.49x |
| lineitem 스캔 | 59,986,052 | 59,986,052 | 1.00x | 59,988,190 | 59,986,052 | 1.00x |
| **문제의 조인** | **56** | **3,261,603** | **1/58,243** | **200** | **3,261,613** | **1/16,308** |
| +orders/+supplier/+nation | 27 | 3,261,613 | 1/120,800 | 200 | 3,261,613 | 1/16,308 |
| 최종 그룹 | 27 | 175 | 0.15x | 200 | 175 | 1.14x |

CUBRID의 붕괴는 산술로 확정된다 — `term[3] sel 9.97835E-06` × `term[5] sel 4.37128E-07`를 **독립 곱**으로
적용: `1,606,292 × 8,000,000 × 9.97835e-06 × 4.37128e-07 = 56.1`. `(ps_partkey, ps_suppkey)`는 복합 PK라
짝당 1행이므로 옳은 값은 1.6 M이다. **PG도 `rows=40`(×5=200)으로 같은 실수를 한다.**
이 축은 두 엔진의 공통 결함이므로 격차 설명에 쓸 수 없다.

## 2. 축 분리 (2단계)

### 2.1 실행 단위 이용률 — 시간 가중

| 채증 | CUBRID | PG |
|---|---|---|
| SUT CPU (런당) | **123.18 s** | **45.037 s** (N=3 + settle 2 s 브래킷, ADR 0017) |
| ↳ leader | `transaction` 8.34 s (6.7 %) | 7.357 s (16.3 %) |
| ↳ worker | `parallel-query` 109.34 s (87.6 %), **12개 생성** | 37.680 s (83.7 %) |
| ↳ 내부 배경 | **`pgbuf-page-flush` 7.02 s (5.6 %)** | **N/A — 별개 프로세스라 SUT 밖** |
| wall (같은 브래킷) | 19.533 s | 7.785 s |
| **CPU/wall** | **6.306 (6의 105.1 %)** | **5.785 (96.4 %)** |
| 질의 실행분만 | **5.927 (98.8 %)** | 5.785 (96.4 %) |
| 라벨 | 병렬 유지 | 병렬 유지 |
| PG `io worker` (별개 열) | N/A | **2.953 s/런 = SUT CPU의 +6.56 %** |
| **wall 비 2.741x vs SUT CPU 비 2.735x** | | **차 −0.23 %** |

`CPU/wall = 6.306 > 6`은 `pgbuf-page-flush` 0.354단위 때문이다. ADR 0009 경계가 CUBRID에서는
`cub_server` 전 스레드(배경 flusher 포함)를, PG에서는 backend+worker만 세므로 **이 5.6 %는
제거 대상이 아니라 기록 대상인 비대칭**이다.

**스레드 동시성 직접 표본화** (0.05 s × 402표본, 수집기 코어 20-23):

| 구간 | t | `parallel-query` 존재/실행중 | 대응 노드 |
|---|---|---|---|
| 1 | 0.6–6.0 s | **12 / 6** | `sscan part`(5) + `sscan lineitem`(6) + gather(2) 중첩 |
| 2 | 6.0–14.0 s | 7 / 6 | `HASHJOIN PROBE`(6) |
| 3 | 14.0–20.0 s | 5–6 / **5** | `SCAN(temp)` 인덱스 NL 체인(5) |

3구간(격차 시간의 54 %)이 5워커인 것은 기록 대상이지만, 시간 가중 이용률 98.8 %가 판정을 닫는다.

### 2.2 같은 엔진 A/B — 플랜 축과 행당 비용 축의 곱

**A** = CUBRID 정본. **B** = PG 플랜 형상 강제. 강제 수단은 `/*+ ORDERED USE_HASH(partsupp) */`
+ FROM 절 순서뿐이고 **WHERE·SELECT·GROUP BY·ORDER BY는 불변**이다.

형상 일치를 노드 단위로 채증:

| 노드 | B (CUBRID) | PG 정본 | 일치 |
|---|---|---|---|
| part LIKE 필터 | 2,000,000 → **108,782** | **108,782** | O |
| partsupp 스캔 | 8,000,000 | 8,000,000 | O |
| **part ⋈ partsupp** | **435,128** | **435,128** | O |
| lineitem 스캔 | 59,986,052 | 59,986,052 | O |
| **lineitem ⋈ (part⋈partsupp), 2컬럼 해시** | **3,261,613** | **3,261,613** | O |
| supplier PK 인덱스 NL | 3,261,554 조회 | Index Searches 3,261,613 | O |
| orders PK 인덱스 NL | 있음 | Index Searches 3,261,613 | O |
| nation | 인덱스 NL + MEMOIZE | Hash Join 25행 | 잔차 (0.02 ms) |
| 최종 그룹 / 결과 md5 | 175 / `dbf9c874…` | 175 / 정규화 후 동일 | O |

| 변형 | 런 (stmt s) | 평균 | sd | sda 물리 read |
|---|---|---|---|---|
| **A 정본** | 19.541 / 19.467 / 19.619 | **19.542** | 0.076 | 0.0 MiB |
| **B PG형상** | 20.001 / 19.951 / 19.786 / 19.672 | **19.852** | 0.151 | 0.0–3.6 MiB |
| B 별기 (read 유의) | 23.613 (30.7 MiB) / 24.168 (51.7 MiB) | — | — | 문턱 통과, 평균에서 제외 |
| B 무효 | 33.208 | — | — | **809.9 MiB — warm 검증 실패** |
| PG 정본 | 7.238 / 7.257 / 7.263 | **7.253** | 0.013 | 0.0 |
| **PG + CUBRID 조인 순서** | 9.786 / 9.781 / 9.828 | **9.798** | 0.026 | ≤0.6 MiB (결과 md5 동일) |

| 축 | 측정 방식 | 값 |
|---|---|---|
| **(i) 플랜·조인 전략** | CUBRID A / CUBRID B | **0.984x** ← CUBRID 플랜이 1.6 % 유리 |
| **(ii) 실행 단위 이용률** | CUBRID 5.927 / PG 5.785 단위 | **0.98x** → wall/CPU 비 차 **0.23 %** |
| **(iii) 행당 실행 비용** | 형상 일치 상태의 엔진 간 비 (B/PG) | **2.737x** (헤드라인 스케일 **2.785x**) |
| **곱** | | `0.9844 × 2.7371 = 2.6944` = 실측 **2.6944**, **오차 0.00 %** |
| 역방향 대조 | PG A / PG(CUBRID 순서) | **0.741x** ← PG 플랜이 35 % 유리 |

**B가 더 느린 이유 (교환 관계, trace)**

| 구간 | A 정본 | B PG형상 | 델타 |
|---|---|---|---|
| `HASHJOIN` 총 | 11,412 ms (BUILD 108,782행, 비분할) | **15,472 ms** (BUILD 435,128행, `SPLIT partitions:4`, **parallel workers: 4**) | **+4,060** |
| ↳ partsupp 8 M seq scan 추가 | 없음 | 852 ms | +852 |
| `SCAN(temp)` 인덱스 NL 체인 | **13,305 ms** (partsupp+orders+supplier+nation) | **8,091 ms** (supplier+orders+nation) | **−5,214** |
| 최상위 `fetch` / `ioread` | 5,413,437 / 1,029,622 | 7,264,106 (+34.2 %) / 1,593,178 (+54.7 %) | |

B는 3.26 M회 partsupp PK 인덱스 NL을 없애 5.2 s를 벌지만, 435 K행 빌드가 **분할 해시 조인(degree 4)** 으로
떨어지고 버퍼 fetch가 34 % 늘어 4.9 s를 잃는다. `HASH_JOIN` degree가 `MIN(degree, context_cnt)`로
4로 깎이는 것(ADR 0018)이 B의 상한을 만든다.

### 2.3 Q21 방법의 적용 가능성

| 방향 | 가능? | 근거 |
|---|---|---|
| **CUBRID → PG 형상** | **성공** | 5개 주 노드 행수가 PG와 완전 일치. 곱 검산 0.00 % |
| **PG → CUBRID 형상 (완전)** | **불가** | ① 파생 테이블·`LATERAL` 두 형태 모두 PG가 2컬럼 `Parallel Hash Join`으로 **pull-up**해 partsupp 인덱스 NL에 도달하지 않는다. ② `LIMIT 1`로 pull-up을 막으면 LATERAL rel이 parallel-restricted가 되어 **`Gather`가 NL 아래로 내려가고** orders·supplier가 full seq scan 해시로 뒤집힌다 — 한 번에 3가지가 바뀌어 단일 축 A/B가 아니다. ③ `enable_hashjoin=off`는 조인 단위로 범위를 좁힐 수 없어 CUBRID 정본이 쓰는 part⋈lineitem 해시까지 파괴한다 |
| **PG → CUBRID 조인 순서 (부분)** | **대조로 사용** | `join_collapse_limit=1`로 순서만 강제 → 1.349x 악화 |

느린 엔진 쪽 A/B만으로 곱이 0.00 %로 닫히므로 역방향 완전 강제는 불필요하다.

## 3. 대칭 프로파일링 (3단계)

### 3.1 방법과 귀속 검증

`perf record -a -C 0-15 -e {instructions:u,cycles:u} -c 10,000,000`, perf 자신은 `taskset -c 20-23`(SUT 밖).
콜그래프 미부착(CUBRID `-fno-omit-frame-pointer` ↔ PG 아님 → fp 언와인딩 비대칭).
SUT 귀속은 report 단계 pid 집합 — CUBRID `cub_server` 단일 pid, PG는 런 전 미존재 postgres pid 6개.

| 항목 | 값 |
|---|---|
| SUT 샘플 / 외부 샘플 (instructions) | CUBRID 61,502 / 570 · PG 14,529 / 798 |
| **CUBRID 귀속 검증** | 프로파일 **615.02 G** ↔ `perf stat -p` **614.73 G** = **100.05 %** (cycles 318.78 ↔ 316.89 = 100.59 %) |
| **PG 귀속 검증** | 프로파일 **145.29 G** ↔ (`-a -C 0-15` 158.02 − idle 보정 10.34) = 147.68 G → **98.38 %** (cycles 105.47 ↔ 105.38 = **100.08 %**) |
| 오버헤드 (PG) | perf 없음 7,227.4 ms → `-c 10 M` 7,261.9 ms = **+0.48 %** (`-c 100 M` +0.01 %) |
| 오버헤드 (CUBRID) | perf 없음 19.476 s → 부착 19.322 s = **−0.79 %** |

| 지표 | CUBRID | PG | 비 |
|---|---|---|---|
| instructions:u (SUT) | **615.02 G** | **145.29 G** | **4.233x** |
| cycles:u (SUT) | **318.78 G** | **105.47 G** | **3.022x** |
| **IPC** | **1.929** | **1.378** | **1.401x** |
| SUT CPU | 123.18 s | 45.04 s | 2.735x |
| wall | 19.882 s | 7.253 s | 2.741x |

### 3.2 기능 단계 버킷 — Q9 주 표 (instructions)

| 기능 단계 | CUBRID | PG | 비 | 절대격차 | **기여** | C % | P % |
|---|---|---|---|---|---|---|---|
| 스캔·레코드 디코드·힙 접근 | 138.32 G | 26.70 G | 5.18x | +111.62 G | **23.8 %** | 22.5 | 18.4 |
| 식 평가/튜플 구성 | 123.60 G | 12.61 G | **9.80x** | +110.99 G | **23.6 %** | 20.1 | 8.7 |
| 버퍼 고정·해제·래치 | 81.92 G | 19.35 G | 4.23x | +62.57 G | **13.3 %** | 13.3 | 13.3 |
| 인덱스 탐색·키 비교 (B-tree) | 79.69 G | 25.28 G | **3.15x** | +54.41 G | **11.6 %** | 13.0 | 17.4 |
| 값/도메인 변환 | 51.25 G | 8.21 G | 6.24x | +43.04 G | 9.2 % | 8.3 | 5.7 |
| 수치 연산 (DECIMAL) | 45.05 G | 7.65 G | 5.89x | +37.40 G | 8.0 % | 7.3 | 5.3 |
| MVCC·가시성·트랜잭션 | 14.55 G | 0.47 G | 30.96x | +14.08 G | 3.0 % | 2.4 | 0.3 |
| TLS/런타임 | 13.58 G | 0 | 무한 | +13.58 G | 2.9 % | 2.2 | 0.0 |
| 집계·해시·해시조인 | 30.43 G | 20.00 G | 1.52x | +10.43 G | 2.2 % | 4.9 | 13.8 |
| 술어 평가 | 12.81 G | 5.90 G | 2.17x | +6.91 G | 1.5 % | 2.1 | 4.1 |
| 임시파일·스필 | 4.45 G | 0.02 G | 222.5x | +4.43 G | 0.9 % | 0.7 | 0.0 |
| libc 메모리이동 | 6.39 G | 2.02 G | 3.16x | +4.37 G | 0.9 % | 1.0 | 1.4 |
| **미분류** | 10.33 G | 6.33 G | 1.63x | +4.00 G | 0.9 % | **1.7** | **4.4** |
| 병렬 인프라 | 0.31 G | 0 | 무한 | +0.31 G | 0.1 % | 0.1 | 0.0 |
| 정렬 | **0** | 3.31 G | 0.00x | −3.31 G | −0.7 % | 0.0 | 2.3 |
| 메모리 할당/해제 | 2.34 G | 7.44 G | **0.31x** | −5.10 G | −1.1 % | 0.4 | 5.1 |
| **합계** | **615.02 G** | **145.29 G** | **4.23x** | **+469.73 G** | 100.0 % | | |

버킷 규칙은 **Q1 규칙 ∪ Q21 규칙**(B-tree 범주 포함)이며 세 쿼리에 같은 규칙을 적용해 재분류했다
(`.git_ignored_dir/q9/scratch/classify.py`). 원 보고서의 per-query 규칙 결과와 다를 수 있고,
그 차이는 규칙 차이지 측정 차이가 아니다.

**규칙 정정 1건**: PG `ExecParallelScanHashBucket`이 Q21 규칙에서 `^ExecParallel`에 걸려 `병렬 인프라`로
갔다. 이 함수는 `nodeHash.c`의 해시 버킷 체인 탐색이므로 `집계·해시·해시조인`이 맞다.
**Q9 PG cycles의 21.2 %**를 쥐고 있어 방치하면 표가 왜곡된다. Q21 재분류에도 같은 정정을 적용했다.

**미분류** — CUBRID 1.7 %(`lang_fastcmp_byte` 0.23 %, `intl_utf8_to_cp` 0.20 %, `memoize_get` 0.06 %),
PG 4.4 %(`cmp_numerics` 0.54 %, `radix_sort_recursive` 0.34 %, `IndexNext` 0.18 %, `j2date` 0.15 %,
`addHyperLogLog` 0.15 %). **PG 미분류에 정렬 관련이 1.03 %p 섞여 있어 PG `정렬` 2.3 %는 과소 계상**이다 —
CUBRID에 불리하지 않은 방향이므로 결론을 바꾸지 않는다.

### 3.3 cycles 대조 — 순위 역전 지점

| 기능 단계 | instr 기여 (순위) | **cycles 기여 (순위)** | instr 비 | cycles 비 | 판정 |
|---|---|---|---|---|---|
| **버퍼 고정·해제·래치** | 13.3 % (3위) | **27.8 % (1위)** | 4.23x | 4.38x | **역전 — cycles 1위** |
| 스캔·레코드 디코드·힙 접근 | 23.8 % (1위) | 20.1 % (2위) | 5.18x | 3.27x | 1↔2 역전 |
| 식 평가/튜플 구성 | 23.6 % (2위) | 17.7 % (3위) | 9.80x | 8.40x | 2↔3 역전 |
| 인덱스 탐색 (B-tree) | 11.6 % (4위) | 11.9 % (4위) | 3.15x | 3.13x | 불변 |
| 값/도메인 변환 | 9.2 % (5위) | 8.2 % (5위) | 6.24x | 6.33x | 불변 |
| 수치 연산 | 8.0 % (6위) | 5.9 % (6위) | 5.89x | 5.13x | 불변 |
| **집계·해시·해시조인** | **+2.2 %** | **−4.7 %** | 1.52x | **0.68x** | **부호 역전** |
| MVCC·가시성 | 3.0 % | 3.2 % | **30.96x** | **5.36x** | 비 6배 축소 |
| 총 비 | **4.233x** | **3.022x** | | | |

**부호 역전의 실체**: PG `ExecParallelScanHashBucket` = instructions 6.08 G ↔ cycles 22.34 G → **IPC 0.27**.
60 M lineitem 행이 435 K행 해시 테이블(32 MB, L3 밖)의 버킷 체인을 훑는 메모리 지연 구간이고
**PG cycles의 21.2 %**가 여기 있다. CUBRID의 대응 구간(`hjoin_fetch_key` 12.25 G instr / 5.78 G cycles,
IPC 2.12)은 빌드 측이 108,782행(캐시 적합)이라 지연에 덜 묶인다. **이것이 2단계의 "CUBRID 정본 플랜이
1.6 % 유리"의 미시적 근거이기도 하다.**

즉 **instructions 비 4.233x는 시간 격차의 상한**이고 실질은 **cycles 3.022x**다.

### 3.4 세 쿼리 나란히 (같은 UNION 규칙, instructions)

`%C` = 그 엔진(CUBRID) 총량 대비 비중 · `기여` = 격차 기여도 · `비` = CUBRID/PG

| 기능 단계 | **Q1** %C / 기여 / 비 | **Q21** %C / 기여 / 비 | **Q9** %C / 기여 / 비 |
|---|---|---|---|
| 인덱스 탐색·키 비교 (B-tree) | 0.0 / 0.0 % / — | **49.3 / 51.5 % / 69.7x** | 13.0 / **11.6 %** / **3.2x** |
| 식 평가/튜플 구성 | **25.1 / 31.2 % / 5.9x** | 4.2 / 3.7 % / 6.5x | 20.1 / **23.6 %** / **9.8x** |
| 스캔·레코드 디코드·힙 접근 | 9.5 / 9.9 % / 3.3x | 15.7 / 14.3 % / 7.1x | **22.5 / 23.8 % / 5.2x** |
| 값/도메인 변환 | 16.8 / **22.0 %** / 8.0x | 2.8 / 3.0 % / 175.5x | 8.3 / 9.2 % / 6.2x |
| 수치 연산 (DECIMAL) | 25.0 / 16.3 % / **1.8x** | **0.0 / 0.0 % / —** | 7.3 / 8.0 % / **5.9x** |
| 버퍼 고정·해제·래치 | **0.2 / 0.1 % / 1.3x** | 12.4 / 12.4 % / 19.0x | 13.3 / 13.3 % / 4.2x |
| 집계·해시·해시조인 | 9.0 / 10.6 % / 4.7x | 0.2 / −0.6 % / 0.3x | 4.9 / 2.2 % / 1.5x |
| MVCC·가시성·트랜잭션 | 0.6 / 0.9 % / 189.7x | 2.7 / 2.9 % / 235.2x | 2.4 / 3.0 % / 31.0x |
| 메모리 할당/해제 | 5.6 / 0.2 % / 1.0x | 5.1 / 5.3 % / 41.4x | 0.4 / **−1.1 % / 0.31x** |
| TLS/런타임 | 1.5 / 2.2 % / 무한 | 0.5 / 0.5 % / 무한 | 2.2 / 2.9 % / 무한 |
| 술어 평가 | 2.6 / 2.1 % / 2.3x | 3.7 / 3.7 % / 18.5x | 2.1 / 1.5 % / 2.2x |
| 정렬 | 0.0 / 0.0 % / — | 0.0 / 0.0 % / 1.5x | 0.0 / −0.7 % / 0.0x |
| 임시파일·스필 | 0.0 / 0.0 % / — | 0.3 / 0.3 % / 5.4x | 0.7 / 0.9 % / 222.5x |
| libc 메모리이동 | 1.8 / 1.3 % / 1.9x | 0.7 / 0.7 % / 6.9x | 1.0 / 0.9 % / 3.2x |
| 미분류 | 2.5 / 3.2 % | 2.0 / 2.0 % | 1.7 / 0.9 % |
| **총 instructions 비** | **3.011x** | **17.748x** | **4.233x** |
| **총 wall 비 (단위 파리티)** | **3.070x** | **14.319x** | **2.741x** |

**세 쿼리를 가르는 축**

| | Q1 | Q21 | **Q9** |
|---|---|---|---|
| Q1형 3버킷 합 (식 평가+값/도메인+수치) | **69.5 %** | 5.3 % | **40.8 %** |
| Q21형 B-tree | 0.0 % | **51.5 %** | 11.6 % |
| 스캔+버퍼 합 | 10.0 % | 26.7 % | **37.1 %** |
| 플랜 축 기여 | (미측정) | **4.436x** | **0.984x (없음)** |
| IPC (C / P) | 2.339 / 2.357 (**동일**) | (미측정) | **1.929 / 1.378 (1.40x)** |

**판정: Q9는 Q1형이다.** 플랜 축이 0.984x로 닫혔고 Q1의 세 버킷이 40.8 %를 쥔다.
**순수 Q1형은 아니다** — Q1에서 0.1 %였던 버퍼 고정·래치가 13.3 %(cycles 27.8 %로 1위)이고,
Q1에 없던 B-tree가 11.6 %다. **제3의 축은 없다** — 관측된 모든 버킷이 Q1·Q21 규칙의 합집합 안에서
설명되고 미분류는 양쪽 5 % 미만이다.

## 4. 소스 규명과 개선 후보 (4단계)

### 4.1 상위 버킷의 file:line

핀 소스 `~/dev/wt-tpch-sspq` @ `f30f1c26003e5aa8e93182648e06cad76fc77064`.

| 버킷 | 심볼 (instr / cycles / IPC) | file:line |
|---|---|---|
| **스캔·디코드 23.8 %** | `heap_attrinfo_read_dbvalues` 60.15 / 24.25 G / 2.48 | `src/storage/heap_file.c:10464` → `:10315 heap_attrvalue_read` → `heap_attrvalue_transform_to_dbvalue` (`pr_clear_value` + `pr_type_from_id` + `data_readval` **매 컬럼마다**). 호출부 `src/query/scan_manager.c:6167-6172`(힙), `:7007`(인덱스 lookup) — **스캔 술어 통과 후 `rest_attrs` 전량 무조건 디코드** |
| | `spage_get_record` 14.91 G, `or_header_size` 10.61 G, `spage_get_record_data` 8.97 G, `heap_next_1page` 8.81 G | `src/storage/slotted_page.c:3815`, `src/object/object_representation.c:5771` |
| **식 평가/튜플 구성 23.6 %** | `qdata_generate_tuple_desc_for_valptr_list` 31.91 / 10.67 G | `src/query/query_opfunc.c:625` |
| | `qdata_copy_db_value_to_tuple_value` 27.61 / 9.65 G | `:356` |
| | `qdata_get_tuple_value_size_from_dbval` 14.66 / 4.53 G | `:6327` |
| | `qfile_generate_tuple_into_list` 11.40 / 4.00 G | 호출부 `px_scan_result_handler.cpp:789`, `query_executor.c:970` |
| **버퍼 13.3 % / cycles 27.8 %** | `__pthread_mutex_lock` 21.62 / **13.24 G / 1.63**, `unlock_usercnt` 17.74 / 11.56 G / 1.53, `trylock` 3.57 / **4.21 G / 0.85** | `src/storage/page_buffer.c:950-957` — `PGBUF_BCB_LOCK/TRYLOCK/UNLOCK` = `pthread_mutex_lock (&(bcb)->mutex)` |
| | `pgbuf_fix_release` 15.23 / **20.26 G / IPC 0.75** | `:2211`. 해시 탐색 `:7545 pgbuf_search_hash_chain` → `:7613`/`:7804`/`:7857`/`:7977`/`:8069` `pthread_mutex_lock (&hash_anchor->hash_mutex)` |
| | `pgbuf_unfix` 8.16 G, `pgbuf_get_victim_candidates_from_lru` 2.20 / **9.63 G** | `:3024`, `:3769 pthread_mutex_lock (&…buf_LRU_list[lru_idx].mutex)` |
| **B-tree 11.6 %** | `btree_search_nonleaf_page` 15.40 / 6.25 G, `btree_search_leaf_page` 11.31 / **9.68 G / 1.17**, `btree_compare_key` 13.23 / 4.44 G, `pr_midxkey_compare` 11.70 / 3.39 G | `src/storage/btree.c:5190`, `:19461`; `src/object/object_primitive.c:7731` |
| **값/도메인 9.2 %** | `pr_clear_value` 14.58 G, `pr_type_from_id` **11.61 G (3줄 배열 룩업)**, `db_value_domain_init` 6.91 G, `pr_data_writeval_disk_size` 4.97 G, `pr_clear_value@plt` 1.39 G | `src/object/object_primitive.c:1866`, `:8968`, `object_primitive.h:402` |
| **수치 8.0 %** | `mr_data_readval_numeric` 24.41 G, `writeval` 9.56 G, `lengthval` 5.57 G. **산술은 5.18 G(0.84 %)뿐** | `src/object/object_primitive.c:8743` |
| **TLS 2.9 %** | `__tls_get_addr` 7.31 G, `__tls_init` 5.44 G (**PG 0**) | `px_scan_result_handler.hpp:80`, `px_scan_input_handler_heap.hpp:49-54`, `…_list.hpp:72-76` — `libcubrid.so` 동적 TLS |

**두 개의 큰 구조 사실**

1. **디스크 바이트 → DB_VALUE → 디스크 바이트 왕복이 격차의 48.9 %다.**
   읽기 측 125.61 G + 쓰기 측 104.28 G = **229.89 G = CUBRID 총량의 37.4 %**.
2. **`수치 연산` 45.05 G 중 실제 산술은 5.18 G(11.5 %)뿐**이고 88.5 %가 표현 변환이다.
   Q1이 "DECIMAL 산술이 주 동인"을 배제한 것과 같은 구조이며 Q9에서 더 강하다.

**CUBRID trace 중첩 스캔 카운터 읽는 법 (부수 발견)**: 중첩 인덱스 스캔의 `readkeys`/`fetch`는
**출력 깊이에 비례해 배수로 인쇄된다.** A 플랜은 partsupp 1x / orders 2x / supplier 3x / nation 4x,
B 플랜은 supplier 1x / orders 2x / nation 3x — 배수가 테이블이 아니라 **인쇄 깊이를 따른다**.
깊이로 나누면 조회당 fetch가 A·B에서 일관된다(supplier 3.00, orders 4.00). 실제 레벨별 조회 수는
**3.26 M으로 PG의 `Index Searches 3,261,613`과 일치**한다. 정확한 누적 규칙은 미규명이나 결론에
영향이 없다.

### 4.2 절제 실험 (측정 앵커)

조인·필터·GROUP BY 불변, lineitem 프로젝션 NUMERIC 3개 → 1개(`sum(l_quantity)`).

| 노드 | 정본 | 절제 | 델타 |
|---|---|---|---|
| CUBRID wall (3런) | **19.542 s** | **16.073 s (sd 0.188)** | **−3.469 s (−17.75 %)** |
| ↳ `SCAN (table: lineitem)` heap time | 9,081 ms | **7,137 ms** | **−1,944 ms** ← 프로젝션 컬럼 2개분 |
| ↳ lineitem 리스트 `fetch` | 1,643,181 | **1,341,583** | −18.4 % |
| ↳ `HASHJOIN` | 11,412 ms | 9,168 ms | −2,244 ms |
| ↳ partsupp 인덱스 NL | btree 5,064 + lookup 1,154 = 6,218 ms | **4,312 ms, `covered: true`** | **−1,906 ms** ← 힙 lookup 소멸 |
| PG wall | 7.253 s | 7.940 s (+9.5 %) | 플랜 변경(`Index Only Scan` + NL) — 비교 불가 |

**혼입 고지**: 절제는 partsupp를 covering으로 바꿔 플랜을 일부 변형시킨다. 따라서 −3.469 s 전체를
프로젝션 비용으로 귀속하지 않는다. 순수 프로젝션 귀속분은 lineitem 스캔 노드의 **−1,944 ms(컬럼 2개)**
= **컬럼당 −0.97 s (−5 %)** 뿐이고, partsupp의 −1,906 ms는 커버링 효과다.

### 4.3 개선 후보 5개

wall 환산: CUBRID 19.542 s ↔ cycles 318.78 G → **cycles 1 % = 0.195 s** (IPC 불변 가정).

#### 후보 1 — 해시 조인 프로브 입력을 병렬 스캔에 융합 (리스트 파일 물질화 제거)

| | |
|---|---|
| **겨냥 버킷** | 식 평가/튜플 구성 23.6 % + 수치 연산 8.0 % + 값/도메인 변환 9.2 %의 lineitem 지분, 버퍼 버킷의 리스트 재읽기 지분(7,485,890 / 45.0 M fix = 16.6 %) |
| **문제** | 프로브 측 lineitem **59,986,052행 전량**이 QFILE 리스트 파일 튜플로 물질화된다. 생존은 **3,261,613행(5.44 %)** 뿐이다. PG는 `Parallel Seq Scan` → `Parallel Hash Join`을 직결해 물질화가 없다 |
| **파일·함수** | `src/query/parallel/px_scan/px_scan_result_type.hpp:28-34` — `RESULT_TYPE`에 `MERGEABLE_LIST`/`XASL_SNAPSHOT`/`BUILDVALUE_OPT`만 있고 **프로브 융합 타입이 없다**. `px_scan_result_handler.cpp:777-789`. `src/query/query_opfunc.c:625`/`:356`/`:6327`. `src/query/query_hash_join.c:2895 hjoin_fetch_key`(리스트에서 키를 다시 읽는다, 12.25 G). `src/query/scan_manager.c:6167-6172` |
| **예상 절감** | 측정 앵커: 컬럼당 −0.97 s × lineitem 6컬럼 × 회피율 94.6 % ≈ **−2.8 s**. cycles 귀속 상한(쓰기 34.58 + NUMERIC 읽기 9.93 + 리스트 재읽기 12.76 = 57.3 G × 0.946 = 54.2 G = 17.0 %) ≈ **−3.3 s**. 범위 **−2.8 ~ −3.3 s (−14 ~ −17 %)** → 배수 **2.27 ~ 2.36x** |
| **난이도 / 위험** | 높음 / 중 (`gather: mergeable list` 순서, `SPLIT` 분할 해시 조인 경로 별도 처리) |
| **upstream 유사 시도** | 같은 패턴 선례 **전부 pin 포함**: `c01876ac0 [CBRD-26982]`·`d0b290459 [CBRD-26846]`·`65d691543 [CBRD-26711]`(집계 융합 = `BUILDVALUE_OPT`), **`a4b37fd80 [CBRD-26522] Support NL join during parallel heap scan (#6806)`**(NL 융합), `5795b1ab6 [CBRD-26900] Evaluate eligible after-join predicates in the hash join probe loop (#7269)`. **해시 조인 프로브 융합만 없다 — 기존 작업선의 빈칸** |
| **Q21 겹침** | 없음 |

#### 후보 2 — BCB 뮤텍스를 원자 연산으로 + per-thread pin 캐시  **[Q21 후보 5와 겹침]**

| | |
|---|---|
| **겨냥 버킷** | 버퍼 고정·해제·래치 — instr 13.3 %, **cycles 27.8 %(1위)**. 뮤텍스 3종 **42.93 G instr / 29.01 G cycles**, `pgbuf_fix_release` 15.23 / **20.26 G (IPC 0.75)** |
| **파일·함수** | `src/storage/page_buffer.c:950-957`(`PGBUF_BCB_LOCK/TRYLOCK/UNLOCK` = `pthread_mutex`), `:7545 pgbuf_search_hash_chain` + `:7613`/`:7804`/`:7857`/`:7977`/`:8069`(`hash_anchor->hash_mutex`), `:3769`(`buf_LRU_list[].mutex`), `:2211`, `:3024` |
| **PG 대조** | 같은 21,172,975 버퍼 접근을 `PinBuffer` 1.79 + `GetPrivateRefCountEntrySlow` 2.28 + `LWLockAttemptLock` 1.47 + `LWLockRelease` 1.78 = **7.32 G**에 한다. 재핀은 백엔드 사설 refcount 배열에서 **락 0회** |
| **예상 절감** | 뮤텍스 cycles 29.01 G의 60~80 % + `pgbuf_fix_release`의 20~30 % = **22~29 G cycles (7~9 %)** → wall **−1.4 ~ −1.8 s**, 하한 −1.1 s |
| **난이도 / 위험** | 높음 / **높음** — 사고 이력 `e8b961468`·`b4f3d4f5b [CBRD-27084]`(page fix 무한 스핀), `d979d1bef [CBRD-26863]`(병렬 인덱스 스캔 데드락), `8bb2d6df8`~`0c46fecab [CBRD-26975]`(백포트 5건) |
| **upstream 유사 시도** | **`58cef8e01 [CBRD-26425] Replace bcb mutex lock into atomic_latch (#6704)`(2026-01-14, pin 포함)** — **page latch만 원자화했고 BCB mutex는 pthread로 남겼다.** `2c85653a6 [CBRD-26941] (#7305)`(pin 포함)은 fix 카운터를 `THREAD_ENTRY`로, `10c300aee [CBRD-26898]`(pin 포함)은 카운터 샤딩. **per-thread pin 캐시(PG `PrivateRefCount` 대응물)는 CUBRID에 없다** |
| **Q21 겹침** | **있음** — Q21 후보 5 (instr 12.04 % / **cycles 23.67 %**). **두 쿼리 모두 cycles 1위 → 최우선** |

#### 후보 3 — B-tree descent 페이지 캐시 + midxkey 비교 특화  **[Q21 후보 4·5와 겹침]**

| | |
|---|---|
| **겨냥 버킷** | 인덱스 탐색·키 비교 11.6 %(cycles 11.9 %) + 버퍼 버킷의 인덱스 지분(인덱스 fix 35.9 M / 전체 45.0 M = **79.8 %**) |
| **측정 사실** | 조회당 페이지 fix — CUBRID partsupp **4.00** / orders **4.00** / supplier **3.00** (16 KiB) vs PG supplier 3.00 / orders 3.08 (8 KiB) → **조회당 바이트 2.6x**. `btree_search_leaf_page` IPC **1.17** |
| **파일·함수** | `src/storage/btree.c:5190 btree_search_nonleaf_page`, `:19461 btree_compare_key`, `src/object/object_primitive.c:7731 pr_midxkey_compare`(컬럼 루프에서 `index_cmpdisk` + `get_index_size_of_mem` 간접 호출 2회 + 도메인 링크드리스트 워크), `src/storage/page_buffer.c:2211` |
| **예상 절감** | descent 상위 2단 유지 → 인덱스 fix 13.0 M(전체의 29 %) 제거 = 버퍼 cycles 61.3 G의 29 % = 17.8 G + `btree_search_nonleaf_page` 40 % = 2.5 G + midxkey 특화 30 % = 2.3 G → **22~25 G cycles (7~8 %)** → wall **−1.4 ~ −1.6 s**, 하한 −1.0 s |
| **난이도 / 위험** | 높음 / 높음 — midxkey 회귀 이력 `2c927aae6 [CBRD-26888]`, `7edcb2be5 [CBRD-26565]` |
| **upstream 유사 시도 — 2건 모두 pin 밖** | **`9f2465838 cache btree non-leafs (7): enhance performance`**(2025-12-18, `origin/feature/refactor-pgbuf`, `btree.c` +13 / `page_buffer.c` +2). **`906b5d7c2 [gate-free] F3 btree_probe_leaf_memo`**(2026-06-13, `xmilex/feat/gate-free-f3-leaf-memo`, `btree.c` +443 — `BTREE_SCAN`마다 최근 leaf 4개를 LSA와 함께 MRU로 기억해 descent를 건너뛴다). pin에 들어간 인접 작업 `b334446d6 [CBRD-27041] page-copy-then-peek scan (#7441)`은 **순차 힙 스캔 전용** |
| **Q21 겹침** | **있음** — Q21 후보 4(midxkey, Q21 instr 21.91 %) + 후보 5. **Q9(11.6 %)·Q21(51.5 %) 양쪽에 걸치는 유일한 실행기 후보** |

#### 후보 4 — 값 계층 핫 함수의 PLT 호출·동적 TLS 제거 (기계적)

| | |
|---|---|
| **겨냥 버킷** | 값/도메인 변환 9.2 % + TLS/런타임 2.9 %(**PG 0**) |
| **파일·함수** | `src/object/object_primitive.c:8968 pr_type_from_id` — 본문이 `if (id <= DB_TYPE_LAST && id != DB_TYPE_TABLE) type = tp_Type_id_map[id];` **3줄인데 11.61 G(1.89 %)**. 아웃오브라인 + `libcubrid.so` export라 PLT 경유(`pr_clear_value@plt` 1.39 G, `intl_utf8_to_cp@plt` 0.34 G, `memcpy@plt` 0.58 G 등 동일 증상). `px_scan_result_handler.hpp:80 thread_local static tls tl` + `px_scan_input_handler_heap.hpp:49-54`(6개) + `…_list.hpp:72-76`(5개) → `__tls_get_addr` 7.31 G + `__tls_init` 5.44 G |
| **예상 절감** | `pr_type_from_id` 헤더 `STATIC_INLINE`화 −11.6 G instr, TLS `-ftls-model=initial-exec` 또는 행 루프 밖 호이스팅 −8~12 G, PLT 정리 −2 G = **−22 ~ −26 G instr (3.6~4.2 %) / −10 ~ −12 G cycles** → wall **−0.6 ~ −0.75 s** |
| **난이도 / 위험** | **낮음 / 낮음** (동작 불변. `initial-exec`는 `libcubrid.so`가 `dlopen` 경로로 열리는지만 확인) |
| **upstream 유사 시도** | `294a04048 [CBRD-25576]`(pin 포함), `8ac881d52 [CBRD-26369]`(pin 포함) — 같은 값 계층을 **함수 단위**로 다듬은 선례. **TLS 모델·PLT 관점 작업은 로그에 없다** |
| **Q1 겹침** | **있음** — Q1 값/도메인 변환이 격차의 22.0 %(7.96x, PG 대응물 사실상 0)이고 `pr_type_from_id`가 그 버킷 안 |

#### 후보 5 — QFILE 튜플 값 크기 이중 계산 제거

| | |
|---|---|
| **겨냥** | 식 평가/튜플 구성 안의 순수 중복 |
| **파일·함수** | `src/query/query_opfunc.c:6327`이 `get_disk_size_of_value` + `DB_ALIGN`으로 크기를 계산해 `tpl_descr->tpl_size`에 누적(14.66 G). 그런데 `:379`가 **같은 DB_VALUE에 대해** `val_size = pr_data_writeval_disk_size (dbval_p)`를 다시 호출(4.97 G / 2.90 G cycles, IPC 1.71). NUMERIC은 `mr_data_lengthval_numeric`(5.57 G)이 양쪽에서 불린다 |
| **예상 절감** | `tpl_descr`에 값별 크기 배열을 실어 넘긴다 → **−4 ~ −7 G instr / −3 ~ −4 G cycles (1.0~1.3 %)** → wall **−0.2 ~ −0.25 s** |
| **난이도 / 위험** | **아주 낮음 / 아주 낮음** |
| **upstream 유사 시도** | 없음 |
| **부기 (범위 밖)** | 절제 실험의 **커버링 인덱스 상한 −1.906 s** — `ps_supplycost`가 `pk_partsupp`에 없어 3,261,603회 힙 lookup이 발생한다. 인덱스 추가는 스키마 불변 규칙 밖이므로 상한만 기록 |

### 4.4 우선순위 (여러 쿼리 걸침 = 상위)

| 순위 | 후보 | 걸치는 쿼리 | Q9 예상 | 난이도 | 위험 |
|---|---|---|---|---|---|
| **1** | 후보 2 (BCB 뮤텍스 → 원자 + pin 캐시) | **Q9 cycles 1위 27.8 % + Q21 cycles 1위 23.67 %** | −1.4~1.8 s | 높음 | 높음 |
| **2** | 후보 3 (B-tree descent 캐시 + midxkey) | **Q9 11.6 % + Q21 51.5 %** | −1.4~1.6 s | 높음 | 높음 |
| **3** | 후보 1 (프로브 융합) | Q9 단독 (Q3·Q5·Q7·Q8·Q10도 같은 형상 가능 — 미측정) | **−2.8~3.3 s** | 높음 | 중 |
| **4** | 후보 4 (PLT·TLS) | **Q1 22.0 % + Q9 12.1 % + Q21 3.5 %** | −0.6~0.75 s | **낮음** | **낮음** |
| **5** | 후보 5 (크기 이중 계산) | Q9 · Q1 | −0.2~0.25 s | **아주 낮음** | **아주 낮음** |

후보 1·2·3은 버퍼 버킷에서 겹치므로 **합산이 아니다.** 전부 적용 시 낙관 −5.5 s / 보수 −4.0 s →
19.542 → **14.0 ~ 15.5 s**, 배수 **1.93 ~ 2.14x**. 후보 4·5만으로도 **−0.8 ~ −1.0 s (−4~5 %)** 를
저위험으로 얻는다.

### 4.5 후보에서 배제되는 것 (근거 숫자와 함께)

| 배제 대상 | 근거 |
|---|---|
| **플랜·조인 순서 개선** | CUBRID 정본이 PG 형상보다 **1.6 % 빠르다**(19.542 vs 19.852). PG에 CUBRID 순서를 강제하면 PG가 **35 % 느려진다**. 두 옵티마이저가 각자 옳았다 |
| **카디널리티 추정 교정** | CUBRID est 56 vs 실제 3,261,603(1/58,243)이지만 **PG도 1/16,308로 같은 실수**를 한다. CUBRID는 B를 7.35배 비싸다고 봤고 **실측 부호가 맞았다** → 고쳐도 고를 더 좋은 플랜이 없다 |
| **실행 단위 붕괴 (`1×2 2×5 2×6`)** | 시간 가중 이용률 **98.8 %**(질의 실행분). wall 비 2.741x ≈ SUT CPU 비 2.735x(**0.23 % 차**). ADR 0018 80 % 문턱 통과 → `병렬 유지`. `SUBQUERY` degree 2는 gather 래퍼이고 그 아래가 6워커다 |
| **DECIMAL/NUMERIC 산술** | `수치 연산` 45.05 G 중 **산술 5.18 G(11.5 %)**뿐. 나머지 88.5 %는 표현 변환(후보 1·4 대상) |
| **메모리 할당/해제** | CUBRID 2.34 G vs **PG 7.44 G = 0.31x** — CUBRID가 3.2배 **적다**. 기여 −1.1 % |
| **정렬** | CUBRID **0 G**(hash partial GROUPBY, 2 ms) vs PG 3.31 G + 미분류 1.03 %p + 35 MB×6 디스크 스필. **이 단계는 CUBRID가 이긴다** |
| **`memoize_memory_limit` 확대** | **측정으로 배제.** supplier PK는 distinct 100,000 키를 3,261,613회 조회(32.6x 재사용)해 이득이 커야 하는데 MEMOIZE가 nation에만 붙는다. 2 MB(기본, `system_parameter.c:5318-5322`) → **64 MB로 올려도 trace 불변**(supplier MEMOIZE 없음, nation 160 KB/500 miss 그대로, wall 24.262 → 24.315 s). 크기 제약이 아니다 |
| **하위 레짐(버퍼 미스) 통제** | PG `shared read` −39.9 %인데 wall **+2.70 %**. lineitem 힙 8.6 GB > `shared_buffers` 8 GB의 **구조적** 결과 |
| **PG `io worker`** | PG SUT CPU의 +6.56 %(2.953 s/런). 주 지표 밖 별개 열, CUBRID에 대응물 없음 |
| **CUBRID `pgbuf-page-flush` 스레드** | SUT CPU의 5.6 %(7.02 s). PG 대응물(bgwriter/checkpointer)은 ADR 0009 경계 밖 → **제거 대상이 아니라 기록 대상인 비대칭** |

### 4.6 미규명으로 남기는 것

| 항목 | 상태 |
|---|---|
| **supplier·orders·partsupp 인덱스 NL에 memoize가 붙지 않는 게이트** | `memoize_memory_limit` 확대로 크기 가설은 **측정 배제**했다. 남은 게이트 후보 3곳: `query_executor.c:16374-16379`(`spec_level==0 && level>=1 && !mvcc_select_lock_needed`) / `:8501-8510`(`if (xasl->memoize_storage)`) / `memoize.cpp:699 checker`. 이번 라운드에서 특정하지 못했다 |
| **CUBRID trace 중첩 스캔 카운터의 정확한 누적 규칙** | 배수가 인쇄 깊이를 따르는 것은 A·B 양쪽에서 확인했고 깊이로 나눈 값이 PG와 일치한다. 정확한 누적 식은 미확정이며 결론에 영향이 없다 |
| **Q3·Q5·Q7·Q8·Q10에 후보 1이 적용되는지** | 같은 "해시 조인 프로브 측 대량 스캔" 형상일 가능성이 있으나 **측정하지 않았다.** 측정 전에는 후보 1의 걸침 범위를 Q9 단독으로 둔다 |

## 5. 채증 색인

| 산출물 | 경로 |
|---|---|
| 하네스 | `.git_ignored_dir/q9/scratch/{run-s1.sh,run-s1p.sh,run-s2a.sh,run-pgcpu.sh,run-s2c.sh,run-prof.sh,symbols2.sh,run-stat.sh}` |
| 분석기 | `.git_ignored_dir/q9/scratch/{classify.py,subgroup.py,show_threads.py,sample-threads.py}` |
| 1단계 raw | `.git_ignored_dir/q9/raw/{s1-times.tsv,s1/,s1p/}` |
| 2단계 raw | `.git_ignored_dir/q9/raw/{s2a-cpu.tsv,s2a/,s2b/thr.json,pgcpu/,s2c-times.tsv,s2c/,s2d/}` |
| 3단계 raw | `.git_ignored_dir/q9/raw/prof/{*.data,*.symbols,*.sutpids,stat-*.txt,classify-*.txt,subgroup-*.txt}` |
| 4단계 raw | `.git_ignored_dir/q9/raw/s4/{abl-*,mem2*,mem64*}` |
| stream 레짐 대조 | `.git_ignored_dir/g2-stream/raw/{plans2/pg-q9.ana,plans/cub-q9.trace,plans/pg-q9.plan}` |
| 소스 핀 | `~/dev/wt-tpch-sspq` @ `f30f1c26003e5aa8e93182648e06cad76fc77064` |
| 구현 | **없음** (4단계는 후보 도출까지) |
