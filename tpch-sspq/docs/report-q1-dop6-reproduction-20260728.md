# Q1 DOP 6 재측정 — 파일럿 재현 대조

2026-07-28. 3단계는 **DOP 스윕 취소 후 DOP 6 단일 재측정**으로 축소됐다.
산출물은 숫자와 플랜뿐이다 — **원인·병목 후보를 지목하지 않는다**(ADR 0005).

## 결론 (5줄)

1. **PG는 재현됐다**: 8.908 s (sd 0.008) vs 파일럿 8.974 s — **−0.74 %**.
2. **CUBRID는 재현되지 않았다**: 31.511 s (sd 0.301) vs 파일럿 34.699 s —
   **−9.19 %**, 파일럿 sd(0.120)의 **26.6배**. 즉 노이즈로 설명되는 범위 밖이다.
3. 그 결과 비율이 **3.867x → 3.537x**로 내려갔다.
4. **플랜 형상은 양쪽 다 파일럿과 동일**하고 worker도 양쪽 6/6이다. 바뀐 것은
   CUBRID의 **추정 카디널리티**뿐이다(히스토그램 효과): `sel 0.1 → 0.9868`,
   `card 5,998,605 → 59,194,236`(실제 59,142,609).
5. 4행 결과는 양쪽 모두 파일럿과 **바이트 단위 동일**하다. 물리 read는 집계 런 전부
   0.0 MiB.

파일럿 이후 바뀐 것은 **(a) 7테이블 추가 적재, (b) 히스토그램 활성화 + 통계
재구축**이고, 여기에 이번 측정에서 **(c) 서버 코어핀을 실제로 적용**한 것이 추가된다
(§6). 어느 것이 −9.19 %를 만들었는지는 **지목하지 않는다.**

## 1. 측정 조건

| 항목 | 값 |
|---|---|
| 질의 | `queries/q1-cubrid.sql` / `queries/q1-pg.sql` (무수정) |
| DOP | 양쪽 6 |
| CUBRID DOP 설정 | `cubrid.conf` `parallelism=6` + 서버 재기동. **세션 설정 불가** — `PRM_FOR_SERVER\|PRM_FOR_CLIENT\|PRM_FORCE_SERVER`이고 `PRM_USER_CHANGE`가 없다(`system_parameter.c:5113`) |
| PG DOP 설정 | `SET max_parallel_workers_per_gather = 6` (세션), `max_parallel_workers=8`, `max_worker_processes=16` |
| 반복 | DOP당 엔진별 3회, **AB/BA 교차** `A B \| B A \| A B` |
| warmup | 세트 전 1회 + **엔진 전환 직후마다** 1회, 전부 미집계 → DOP당 warmup 4회 / 집계 6회 (ADR 0006) |
| timeout | 300 s (ADR 0005). 초과 0건 |
| SUT 핀 | 양쪽 서버 `taskset -c 0-15` (node0) — 재기동으로 적용, `taskset -pc`로 확인 |
| 클라이언트 핀 | **주 결과: `taskset -c 0-15`(파일럿과 동일)**. 부수 결과: `taskset -c 16-19`(node1) |
| wall time 측정 | `date +%s.%N`으로 `csql`/`psql` 호출 전체를 감쌈(파일럿과 동일) |

CUBRID paramdump 채증: `[C*] parallelism=6 (4)` / `[S*] parallelism=6 (4)`
(`*`=기본값 이탈, `(4)`=기본값). `cub_server 322454 affinity: 0-15`.

## 2. wall time — DOP 6, 3회

**주 결과 (클라이언트 node0 = 파일럿과 동일한 배치)**

| 엔진 | run1 | run2 | run3 | 평균 | sd |
|---|---|---|---|---|---|
| CUBRID | 31.856 | 31.304 | 31.372 | **31.511** | 0.301 |
| PostgreSQL | 8.910 | 8.914 | 8.899 | **8.908** | 0.008 |
| | | | | **비율 3.537x** | |

**부수 결과 (클라이언트 node1 = SUT와 분리)**

| 엔진 | run1 | run2 | run3 | 평균 | sd |
|---|---|---|---|---|---|
| CUBRID | 32.123 | 31.800 | 31.706 | 31.876 | 0.219 |
| PostgreSQL | 8.913 | 8.915 | 8.908 | 8.912 | 0.004 |
| | | | | 비율 3.577x | |

클라이언트 배치 차이는 CUBRID +1.16 %, PG +0.04 %로 이 규모에서는 무의미하다
(ADR 0009의 코어핀 판단 근거로 사용).

미집계 warmup 값(참고): CUBRID 32.110 / 31.505, PG 8.905 / 8.873.

## 3. 파일럿 대비 재현 대조

| 엔진 | 파일럿 평균 (sd) | 이번 평균 (sd) | 차이 | 파일럿 sd 배수 | 판정 |
|---|---|---|---|---|---|
| CUBRID | 34.699 (0.120) | 31.511 (0.301) | **−3.188 s / −9.19 %** | **26.6×** | **재현 안 됨** |
| PostgreSQL | 8.974 (0.018) | 8.908 (0.008) | −0.066 s / −0.74 % | 3.7× | 재현 (실질 동일) |
| 비율 | **3.867x** | **3.537x** | −0.330 | — | 비율 하락 |

PG의 3.7× sd도 형식상 sd 밖이지만 절대차가 66 ms이고 sd 자체가 8~18 ms로 매우
작다. CUBRID의 3.19 s와는 규모가 다르다.

**파일럿 이후 달라진 것 (전부 사실, 인과 지목 없음)**

| # | 변경 | 근거 |
|---|---|---|
| a | 7테이블 추가 적재 (86,586,077행 중 lineitem 외 26,600,025행) | `report-g1-assets-20260728.md` |
| b | 히스토그램 활성화 + 통계 전체 재구축 (61컬럼, 300버킷, full scan) | `report-cubrid-histogram-enabled-20260728.md`, ADR 0008 |
| c | **서버 코어핀을 실제로 적용** — 측정 직전 확인 결과 두 서버 모두 `0-31`이었고(파일럿 이후 여러 번 재기동됨) 이번에 `taskset -c 0-15`로 재기동했다 | 본 보고서 §6 |
| d | 상주 배경 부하가 다르다 — `bun` 프로세스 2개(평균 56 % / 8.5 % CPU, 미핀) | 본 보고서 §6 |

## 4. worker 수 채증

| 엔진 | 채증 | 목표 DOP | 실제 | 파일럿 |
|---|---|---|---|---|
| CUBRID | `;trace on text` → `SCAN … (parallel workers: 6, …)` | 6 | **6** | 6 (동일) |
| PostgreSQL | `EXPLAIN (ANALYZE …)` → `Workers Planned: 6` / `Workers Launched: 6` | 6 | **6 / 6** | 6 / 6 (동일) |

CUBRID trace 원문:
```
Trace Statistics:
  SELECT (time: 32083, fetch: 683074, fetch_time: 5394, ioread: 682957)
    SCAN (table: dba.lineitem), (heap time: 32081, fetch: 682982, ioread: 682950, readrows: 59986052, rows: 59986052)
         (parallel workers: 6, heap time: 31545..32081, readrows: 9938887..10011920, rows: 9938887..10011920, gather: mergeable list)
    GROUPBY (time: 1, hash: partial, sort: true, page: 0, ioread: 0, rows: 4)
```

## 5. 플랜 동일성 판정

### CUBRID — 형상 동일, 추정 카디널리티만 변경

`;plan detail`은 이번에 빈 덤프를 냈다(측정 런들이 이미 XASL을 캐시해 최적화가
생략된 것으로 보인다 — 사실만 기록). 그래서 2.6단계에서 검증한
`SET OPTIMIZATION LEVEL 514`(실행 없이 플랜만)로 다시 잡았다.

| | 파일럿 (히스토그램 없음) | 이번 (히스토그램 있음) |
|---|---|---|
| term[0] | `l_shipdate range (min inf_le date '09/02/1998')` **`(sel 0.1)`** | 동일 술어, **`(sel 0.9868)`** |
| 스캔 노드 | `sscan class: lineitem node[0]`, `sargs: term[0]` | **동일** |
| 스캔 cost / card | `cost: 832902 card 5998605` | `cost: 832902 card **59194236**` |
| 상위 노드 | `temp(group by)`, `sort: 1 asc, 2 asc` | **동일** |
| 상위 cost / card | `cost: 868407 card 5998605` | `cost: **1183217** card **59194236**` |

**판정: plan family 동일.** 연산자·순서·sargs 배치·sort key가 전부 같고, 바뀐 것은
추정 행수와 그로부터 나온 상위 cost뿐이다. 실제 적격 행수는 59,142,609이므로
추정 정확도는 **0.101배 → 1.00087배**로 교정됐다.

### PostgreSQL — 연산자 트리 동일

연산자만 추출해 diff한 결과 차이는 하네스 에코 2줄(`SET` vs `Timing is on`,
파일럿의 `Time` 줄)뿐이다.

```
Finalize GroupAggregate → Gather Merge (Workers Planned/Launched: 6)
  → Sort (Sort Key: l_returnflag, l_linestatus; quicksort 26kB)
    → Partial GroupAggregate → Sort → Parallel Seq Scan on public.lineitem
```

| | 파일럿 | 이번 |
|---|---|---|
| Parallel Seq Scan 추정 rows | 9,845,461 | 9,842,310 |
| 실제 rows / loops | 8,448,944.14 / 7 | **동일** |
| Rows Removed by Filter | 120,492 | **동일** |

**판정: plan family 동일**, 추정 rows 차이 0.03 %는 `ANALYZE` 재표본에 따른 것.

## 6. warm 및 격리 채증

**물리 read (ADR 0006)** — `/proc/diskstats` sda sectors-read 델타, 파일럿과 같은 계수기:

| 런 | CUBRID | PG |
|---|---|---|
| run1 / run2 / run3 | 0.0 / 0.0 / 0.0 MiB | 0.0 / 0.0 / 0.0 MiB |
| warmup (미집계) | 0.0 / 0.0 MiB | 0.0 / 0.0 MiB |

집계 6런 전부 **0.0 MiB**로 잠정 문턱(1 % / 100 MiB)을 충족한다. 무효 런 0건.
클라이언트 major fault 델타도 전부 0. (부수 실험의 pg warmup1만 19.4 MiB —
PG 서버 재기동 직후였고 미집계다.)

**격리**

| 항목 | 상태 |
|---|---|
| `cub_server` (322454) | `taskset -pc` → **0-15** |
| PostgreSQL (259423 및 자식) | **0-15** |
| `cub_master` (43200) | `0-31` — 재기동하지 않음. 질의를 실행하지 않으므로 무관 |
| 클라이언트 | 주 결과 `0-15`(파일럿 동일) / 부수 `16-19` |
| broker / CAS | **없음** — `cubrid broker status` → not running |
| 배경 부하 | `bun` 2개(평균 56 % / 8.5 % CPU)가 **미핀 상태로 상주**. 내 프로세스가 아니라 정리하지 않았다. AB/BA 교차가 이에 대한 방어다(ADR 0005) |

## 7. 결과 정합성

| 비교 | 결과 |
|---|---|
| CUBRID 이번 4행 vs 파일럿 4행 | **바이트 단위 동일** (10열 × 4행 전부) |
| PG 이번 4행 vs 파일럿 4행 | **바이트 단위 동일** (`diff` → 차이 없음) |
| CUBRID vs PG (이번) | `sum_*`·`count_order` 전부 자리수까지 일치. `avg_*`는 출력 정밀도만 다름 (CUBRID 16자리 지수표기 `2.550097510300710e+01` ↔ PG `numeric` `25.5009751030070973`) — 파일럿과 같은 성질 |
| `count_order` 합 | 59,142,609 = 적격 행수. `59,986,052 − 59,142,609 = 843,443` |

DOP 무관 동일성은 이번 스코프(DOP 6 단일)에서는 검증 대상이 아니다.

## 8. 취소된 DOP 스윕의 부분 값 (참고용, 집계 아님)

지시 전에 DOP 1이 진행 중이었고, 진행 중인 런만 마치고 폐기했다. 세트가
미완성이므로 **평균·sd·speedup을 산출하지 않는다.** 원문만 남긴다.

| DOP | 엔진 | 라벨 | wall (s) | sda read |
|---|---|---|---|---|
| 1 | CUBRID | warmup1 | 186.628 | 0.0 MiB |
| 1 | CUBRID | run1 | 184.635 | 0.1 MiB |
| 1 | CUBRID | warmup2 | 187.984 | 0.1 MiB |
| 1 | PG | warmup1 | 64.295 | 0.0 MiB |
| 1 | PG | run1 | 59.993 | 0.0 MiB |
| 1 | PG | run2 | 60.219 | 0.0 MiB |

DOP 1은 양쪽 모두 병렬 완전 비활성이다 — CUBRID는 `parallelism<=1`이
`PT_SPEC_FLAG_NO_PARALLEL_SCAN`을 세우고(`plan_generation.c:3219`), PG는
`max_parallel_workers_per_gather=0`이다. 측정 후 `parallelism=6`으로 복원하고
재기동해 `[S*] parallelism=6`을 확인했다.

## 9. CPU 계정 — 이번 산출물에는 없다

ADR 0009가 SUT CPU 경계를 정의했지만, 이번 단계는 **wall time과 플랜만** 모았다.
프로파일러를 붙이지 않았으므로 CPU 열은 측정하지 않았다. 형식상 표를 미리 고정해 둔다.

| 지표 | CUBRID | PostgreSQL |
|---|---|---|
| wall time (end-to-end) | 31.511 s (sd 0.301) | 8.908 s (sd 0.008) |
| **SUT CPU** (`cub_server` / backend+workers) | 미측정 | 미측정 |
| **broker+CAS** (클라이언트측 질의 처리) | 미측정 — 현재 경로에 CAS 없음, 해당 역할은 `csql` | **N/A (backend 내부)** |

worker 합산 CPU를 wall time에서 감산하거나 직접 비교하지 않았다.

## 증거 색인

| 산출물 | 경로 |
|---|---|
| 주 결과 timings | `.git_ignored_dir/g1-dop/dop6-pilotpin/timings.tsv` |
| 부수 결과 timings | `.git_ignored_dir/g1-dop/dop6/timings.tsv` |
| 취소된 DOP1 부분 | `.git_ignored_dir/g1-dop/dop1/timings.tsv` |
| CUBRID trace / worker | `.../dop6-pilotpin/plan-cubrid.txt` |
| CUBRID 플랜(level 514) | `.../dop6-pilotpin/plan514-cubrid.txt` |
| PG EXPLAIN ANALYZE | `.../dop6-pilotpin/plan-pg.txt` |
| 런별 결과 출력 | `.../dop6-pilotpin/{cubrid,pg}-run{1,2,3}.out` |
| paramdump / affinity | `.../dop6-pilotpin/cubrid-paramdump-dop6.txt`, `cubrid-affinity-dop6.txt` |
| 하네스 | `.git_ignored_dir/g1-dop/scratch/dop-sweep.sh` |
| 파일럿 원본 | `.git_ignored_dir/tpch-sspq/g1-q1-pilot/{plans,raw}/` |
