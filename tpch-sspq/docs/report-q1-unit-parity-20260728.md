# Q1 실행 단위 파리티 교정 — A 항목 재측정

2026-07-28. ADR 0014 교정의 실측. 원인·병목 후보 지목 없음(ADR 0005). worker 합산
CPU를 wall time에서 감산하거나 직접 비교하지 않았다. 표는 ADR 0009 + 0011 형식
(SUT CPU / broker+CAS / 파싱·플랜 열 분리, 합산 단일 숫자 없음) + ADR 0014의 실행 단위 행.

## 결론 (5줄)

1. **형님 예측이 맞았다.** wall 비가 **3.555x → 3.049x**로 내려가 SUT CPU 비
   **3.056x**와 **0.2 % 차**로 수렴했다. 숫자를 예측에 맞춘 것이 아니라 그대로 나왔다.
2. **PG 총 CPU 작업량은 불변** — 62.163 → 62.090 s (**−0.12 %**). 바뀐 것은 단위 수뿐이고
   wall만 8.957 → 10.442 s로 올랐다. 7/6 배 예측치 10.450 s와 **−0.07 %** 일치.
3. **리더는 worker 5개 구성에서도 동등 참여** — leader CPU 10.340 s vs worker 평균
   10.350 s, 비 **0.9990**. `Parallel Seq Scan`의 `loops=6`이 leader + 5 worker다.
4. **양쪽 6 실행 단위, 활용도도 사실상 같다** — CUBRID 5.959/6 = 99.3 %,
   PG 5.946/6 = 99.1 %.
5. 4행 결과는 양쪽 모두 기준선과 **바이트 단위 동일**, 집계 6런 물리 read 최대 0.8 MiB.

## 측정 조건

Q1. **CUBRID는 현행 그대로 `parallelism=6`**(재기동 없음, conf 무변경),
**PG만 세션 GUC `max_parallel_workers_per_gather=5`**. `parallel_leader_participation`은
기본 `on` 유지(ADR 0014 §3). WARM 레짐(세트 전 warmup 1회 미집계 + 엔진 전환 직후
재수행), AB/BA `A B | B A | A B` 3회, 양쪽 서버 node0 `0-15` 핀, 클라이언트도 `0-15`
(ADR 0012 공유 정책), 수집기 `20-23`. 300 s timeout, 초과 0건.

CPU 브래킷은 **클라이언트 세션 안에서**(CUBRID `;SHELL_Cmd`/`;SHELL`, PG `\!`),
`/proc/<pid>/stat` utime+stime 델타. PG worker는 postmaster `cutime/cstime` 델타로 정확
포착.

## A. 쿼리 구간 총 CPU 초 vs wall 초 — 2트랙 (ADR 0014 §4)

| 지표 | 트랙 (1) 자연 구성값 | | 트랙 (2) **단위 파리티 통제값** | |
|---|---|---|---|---|
| | **CUBRID** | **PostgreSQL** | **CUBRID** | **PostgreSQL** |
| 설정 | `parallelism=6` | `max_parallel_workers_per_gather=6` | `parallelism=6` | **`…_per_gather=5`** |
| worker 수 (플랜) | 6 | 6 | 6 | **5** |
| **실행 단위 수** | **6** | **7** | **6** | **6** |
| **wall** | 31.846 s (sd 0.622) | 8.957 s (sd 0.004) | **31.842 s** (sd 0.093) | **10.442 s** (sd 0.008) |
| **SUT CPU 합계** | 188.673 s (sd 1.371) | 62.163 s (sd 0.025) | **189.747 s** (sd 1.045) | **62.090 s** (sd 0.085) |
| ├ user | 184.560 | 61.963 | 185.980 | 61.863 |
| └ sys | 4.113 | 0.200 | 3.767 | 0.227 |
| **SUT CPU / wall** | 5.926 | 6.940 | **5.959** | **5.946** |
| 단위당 활용도 | 98.8 % | 99.1 % | **99.3 %** | **99.1 %** |
| ├ **leader CPU** | 0.470 s | 8.870 s | **0.460 s** | **10.340 s** |
| └ **worker 합** | 188.0 s (×6) | 53.293 s (×6) | **189.1 s** (×6) | **51.750 s** (×5) |
| worker 평균/단위 | 31.4 s | 8.88 s | 31.52 s | 10.350 s |
| **broker + CAS** (클라이언트측 역할) | 경로에 없음; `csql` 0.084 s | **N/A (backend 내부)**; `psql` 0.070 s | 경로에 없음; `csql` **0.090 s** (u 0.063 / s 0.027) | **N/A (backend 내부)**; `psql` **0.073 s** (u 0.050 / s 0.023) |
| **파싱 + 플랜 생성** (ADR 0011 의무) | 3.0 ms (클라이언트측) | 0.640 ms (backend) | **3.0 ms** (클라이언트측, 무변경) | **0.597 ms** (backend, 0.620/0.589/0.582) |
| 파싱+플랜 / wall | 0.0094 % | 0.0071 % | 0.0094 % | 0.0057 % |
| **wall 비** | **3.555x** | | **3.049x** | |
| **SUT CPU 비** | **3.035x** | | **3.056x** | |

원시 3회 (트랙 2): CUBRID wall 31.813 / 31.768 / 31.946 s, SUT CPU 188.72 / 189.71 /
190.81 s. PG wall 10.445 / 10.448 / 10.433 s, SUT CPU 62.10 / 62.17 / 62.00 s,
leader 10.34 / 10.35 / 10.33 s, worker 합 51.76 / 51.82 / 51.67 s.

미집계 warmup: CUBRID 32.453 / 32.197 s, PG 10.412 / 10.404 s.

## 예측 검증 — 맞았다

| 예측 | 값 | 실측 | 차 |
|---|---|---|---|
| PG wall = 8.957 × 7/6 | 10.450 s | **10.442 s** | **−0.07 %** |
| PG SUT CPU 불변 | 62.163 s | **62.090 s** | **−0.12 %** |
| wall 비가 SUT CPU 비 수준(3.035x)으로 수렴 | ~3.04x | **3.049x** (SUT CPU 비 3.056x) | wall 비와 CPU 비의 차 **0.2 %** |

분해가 닫혔다:

```
트랙 (1) 자연:      wall 3.555x = SUT CPU 3.035x × 1.1711  (단위 수 7/6 = 1.1667이 100.4 % 설명)
트랙 (2) 단위 파리티: wall 3.049x = SUT CPU 3.056x × 0.998  (잔여 항 소멸)
```

즉 자연 구성에서 보였던 두 번째 항은 **병렬 효율 차이가 아니라 계약의 단위 수
불일치**였고, 교정 후 사라졌다. 남은 것은 SUT CPU 비 하나다. **원인은 지목하지
않는다**(ADR 0005).

## 채증

### 실행 단위 수 — 플랜 원문

PostgreSQL (`max_parallel_workers_per_gather=5`):
```
 Finalize GroupAggregate  (actual time=10647.322..10655.933 rows=4.00 loops=1)
   ->  Gather Merge  (actual time=10647.257..10655.853 rows=24.00 loops=1)
         Workers Planned: 5
         Workers Launched: 5
         ->  Sort  (actual time=10643.605..10643.606 rows=4.00 loops=6)
             ->  Parallel Seq Scan on public.lineitem  (actual time=0.076..1128.749 rows=9857101.50 loops=6)
```
`Workers Launched: 5`이고 스캔 노드 `loops=6` → **leader + 5 worker = 6 실행 단위**.
`rows=9,857,101.50 × 6 = 59,142,609` = 필터 통과 행수와 일치.

CUBRID (`parallelism=6`, 무변경):
```
    SCAN (table: dba.lineitem), (heap time: 32329, fetch: 682982, ioread: 682949, readrows: 59986052, rows: 59986052)
         (parallel workers: 6, heap time: 32208..32329, readrows: 9938887..10011920, rows: 9938887..10011920, gather: mergeable list)
```
`parallel workers: 6`, worker별 readrows 9,938,887~10,011,920 → **6 실행 단위**.
leader 스레드(`transaction`) CPU 0.460 s = SUT CPU의 0.24 %로, 튜플 처리에 참여하지 않음.

### 리더 참여 양상 — worker 5개에서도 변하지 않았다

| | worker 6개 (자연) | worker 5개 (단위 파리티) |
|---|---|---|
| PG leader CPU | 8.870 s | 10.340 s |
| PG worker 평균 | 8.882 s | 10.350 s |
| **leader / worker 비** | **0.9986** | **0.9990** |

이 교정의 전제(리더가 실제로 스캔에 참여한다)가 5 worker 구성에서도 유지된다.
양상 변화 없음.

### 결과 정합성

| 비교 | 결과 |
|---|---|
| PG 4행 (5 worker) vs 기준선 (6 worker) | **바이트 단위 동일** (`diff` 무차이) |
| CUBRID 4행 vs 기준선 | **바이트 단위 동일** |

### warm 검증 (ADR 0006)

| 런 | CUBRID sda read | PG sda read |
|---|---|---|
| run1 / run2 / run3 | 0.6 / 0.0 / 0.8 MiB | 0.2 / 0.0 / 0.0 MiB |

집계 6런 최대 **0.8 MiB** — 잠정 문턱(1 % / 100 MiB) 대비 스캔량 10,671 MiB의
**0.0075 %**. 무효 런 0건.

기록: 이 라운드의 **CUBRID warmup1이 958.0 MiB**를 읽었다(미집계). 직전 D 항목의
스크래치 DB 작업이 page cache를 밀어낸 상태였고 warmup이 그것을 되채웠다 — WARM 규칙이
설계대로 동작한 사례다.

### 격리 / 상태

| 항목 | 상태 |
|---|---|
| CUBRID conf | 무변경 (`parallelism=6`, `stats_on` 부재, 히스토그램 `y`) — 재기동 없음 |
| PG 변경 | 세션 GUC만 (`max_parallel_workers_per_gather=5`). 클러스터 기본값 6은 그대로, `parallel_leader_participation=on` 유지 |
| `cub_server` affinity | 0-15 |
| 클라이언트 | 0-15 (SUT와 공유, ADR 0012) |
| 수집기 | 20-23 |
| 데이터 | 재적재 0건 |
| `~/CUBRID` | 불변 |

## 채증 색인

| 산출물 | 경로 |
|---|---|
| 원시 TSV + 스냅샷 JSON | `.git_ignored_dir/g1-abcd/raw/A-unitparity/` |
| 하네스 | `.git_ignored_dir/g1-abcd/scratch/run-a-unitparity.sh` |
| PG 플랜 (5 worker) | `.../A-unitparity/plan-pg5.txt` |
| CUBRID trace | `.../A-unitparity/trace-cubrid.txt` |
| 런별 결과 출력 | `.../A-unitparity/{cubrid,pg}-run{1,2,3}.out` |
| 자연 구성 트랙 원본 | `.git_ignored_dir/g1-abcd/raw/A/` |
