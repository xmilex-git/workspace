# Q1 DOP6 — A~D 카운터 측정

2026-07-28. **프로파일러 미부착, 카운터만.** 원인·병목 후보 지목 없음(ADR 0005).
worker 합산 CPU를 wall time에서 감산하거나 직접 비교하지 않았다 — CPU는 CPU 축,
wall은 wall 축으로 따로 보고한다. 표는 ADR 0009 형식(SUT CPU / 클라이언트측 처리
분리, 합산 단일 숫자 없음).

## 결론 (5줄)

1. **CPU 작업량 비 3.03x vs wall 비 3.56x** — 두 축이 다르다. CUBRID SUT CPU
   188.67 s, PG 62.16 s.
2. **명령 수 비도 3.02x** (CUBRID 1,285.4 G instructions vs PG 425.5 G),
   **IPC는 사실상 동일**(2.49 vs 2.52). 즉 "같은 명령을 더 느리게 도는" 것이 아니라
   **명령 수 자체가 3배**다.
3. **평균 병렬 활용도는 CUBRID 5.93 / PG 6.94.** CUBRID는 참여 스레드 6개(리더
   스레드 CPU 0.47 s), PG는 리더가 스캔에 참여해 7개(리더 8.87 s + 워커 53.29 s).
4. **물리 디스크 read는 양쪽 0**이지만 버퍼풀 미스는 다르다 — CUBRID
   `Num_data_page_ioreads` 682,957(16 KiB 페이지, 10,674 MiB), PG
   `shared read` 1,071,848(8 KiB, 8,374 MiB).
5. **1.21x 바이트 격차는 전부 컬럼 저장 표현에서 나온다**: CHAR +21.91 B/행,
   DECIMAL +12.53, VARCHAR +7.89, DATE +1.50, INTEGER ±0. 행 구조 오버헤드는 CUBRID가
   오히려 **10.96 B 작다**.

## 측정 조건

Q1, DOP 6, warm 규칙(세트 전 warmup 1회 미집계 + 엔진 전환 직후 재수행), 양쪽 서버
`taskset -c 0-15`(node0), 클라이언트 `0-15`(파일럿과 동일), **수집기(perf, snapshot,
statdump) `taskset -c 20-23`** = SUT와 다른 cpuset. 300 s timeout, 초과 0건.
집계 런 물리 read(`/proc/diskstats` sda) 전부 **0.0 MiB**, 무효 런 0건.

`perf`는 설치돼 있고 동작한다(`/usr/bin/perf`, `perf version 4.18.0-553...`,
`perf_event_paranoid=-1`) — `ENVIRONMENT.md`의 "사용자 sudo 설치 pending" 기재는
stale이었고 이 보고서와 함께 정정했다.

---

## A. CPU 초 vs wall 초

구간 브래킷은 **클라이언트 세션 안에서** 잡았다 — CUBRID는 `;SHELL_Cmd`/`;SHELL`,
PG는 `\!`. 따라서 클라이언트 기동·파싱이 아니라 **질의 구간 자체**다.

계측 방식과 그 정확성 근거:

| 엔진 | 방법 | 왜 정확한가 |
|---|---|---|
| CUBRID | `/proc/<cub_server>/stat` utime/stime 델타 | 단일 프로세스이고 이 필드는 **전 스레드 합산**이라 워커 스레드가 구간 안에서 생성·소멸해도 누락되지 않는다 |
| CUBRID 스레드별 | `/proc/<pid>/task/*/stat` 델타 | 잔차(프로세스 델타 − 스레드 합) **평균 0.007 s**로 분해가 사실상 정확 |
| PG 리더 | `/proc/<backend>/stat` 델타 | 세션이 유지되므로 프로세스가 살아 있다 |
| PG 워커 | `/proc/<postmaster>/stat` **cutime/cstime** 델타 | 병렬 워커는 postmaster가 reap하므로 종료된 워커의 CPU가 정확히 누적된다. 샘플링 불필요 |

### A 표 (측정 3회, ADR 0009 형식)

| 지표 | CUBRID | PostgreSQL | CUBRID/PG |
|---|---|---|---|
| **wall (질의 구간)** | 31.846 s (sd 0.622) | 8.957 s (sd 0.004) | **3.555x** |
| **SUT CPU 합계** | **188.673 s** (sd 1.371) | **62.163 s** (sd 0.025) | **3.035x** |
|  ├ user | 184.560 s | 61.963 s | 2.978x |
|  └ sys | 4.113 s | 0.200 s | 20.6x |
| **SUT CPU / wall**(평균 병렬 활용도) | **5.926** | **6.940** | — |
| ├ leader | 0.470 s (`transaction` 스레드) | 8.870 s (sd 0.000) | — |
| └ worker 합 | 188.0 s (`parallel-query` × 6) | 53.293 s (sd 0.025) | — |
| 참여 실행 단위 수 | 6 (워커만) | 7 (리더 + 워커 6) | — |
| 단위당 CPU | 31.4 s | 8.88 s | 3.54x |
| **broker + CAS** (클라이언트측 질의 처리) | **경로에 없음** — `cubrid broker status` = not running. 해당 역할은 `csql`: **0.084 s** (user 0.057 / sys 0.027) | **N/A (backend 내부)**. `psql`은 결과 포맷만: 0.070 s (user 0.043 / sys 0.027) | — |

원시 3회 값: CUBRID SUT CPU 190.08 / 187.34 / 188.60 s, wall 32.554 / 31.388 / 31.597 s.
PG SUT CPU 62.14 / 62.19 / 62.16 s, wall 8.954 / 8.962 / 8.955 s.

CUBRID run1 스레드 내역(원문): `parallel-query` 32.37 / 31.69 / 31.42 / 31.40 / 31.39
/ 31.14 s, `transaction` 0.47, `dwb-flush-block` 0.09, `pgbuf-page-flus` 0.03,
`dwb-file-sync` 0.03, `vacuum-master` 0.03, `pgbuf-flush-con` 0.01,
`log-checkpoint` 0.01.

**이번 단계의 1차 산출물**: CPU 작업량 비 **3.035x** ≠ wall 비 **3.555x**.
두 값을 서로 감산하거나 나눠서 해석하지 않는다.

---

## B. perf stat (SUT 프로세스 부착)

부착 전략과 그 검증:

| 엔진 | 부착 | 검증 |
|---|---|---|
| CUBRID | `-p <cub_server>` — 단일 프로세스, 전 스레드 포함 | task-clock 191.18 s vs A의 /proc 188.67 s (+1.3 %, 별개 런) |
| PG | `-p <postmaster>` — 리더 backend와 병렬 워커 **둘 다 부착 후 fork되는 자식**이므로 perf 기본 `inherit=1`로 포착 | task-clock **62.36 s** vs A의 /proc **62.16 s (+0.3 %)** → 부착 집합이 SUT 경계와 일치함을 독립 확인 |

6개 이벤트를 한 그룹으로 넣었고 perf가 **스케일링 표시를 출력하지 않았다**(멀티플렉싱 없음).

### B 표 (2회 평균)

| 카운터 | CUBRID | PostgreSQL | CUBRID/PG |
|---|---|---|---|
| task-clock | 191,180 ms | 62,356 ms | 3.066x |
| cycles | 517,096,375,306 | 168,572,988,349 | 3.068x |
| **instructions** | **1,285,376,141,839** | **425,471,947,690** | **3.021x** |
| **IPC** | **2.485** | **2.520** | 0.986x |
| 실효 주파수 | 2.705 GHz | 2.704 GHz | 1.000x |
| LLC-load-misses | 78,869,740 | 5,161,116 | 15.28x |
| LLC-store-misses | 9,882,419 | 324,530 | 30.45x |
| branch-misses | 764,487,429 | 301,394,753 | 2.536x |

### 행당 정규화

| 지표 | 기준 | CUBRID | PostgreSQL | 비 |
|---|---|---|---|---|
| instructions / 행 | 스캔 59,986,052행 | 21,428 | 7,093 | 3.021x |
| instructions / 행 | 필터통과 59,142,609행 | 21,734 | 7,194 | 3.021x |
| cycles / 행 | 스캔 59,986,052행 | 8,620 | 2,810 | 3.068x |
| cycles / 행 | 필터통과 59,142,609행 | 8,743 | 2,850 | 3.068x |
| LLC-load-misses / 행 | 스캔 | 1.315 | 0.086 | 15.28x |
| branch-misses / 행 | 스캔 | 12.74 | 5.02 | 2.536x |

### B의 한계 — 반드시 함께 읽어야 함

* **PG 캐시 이벤트가 부착 방식에 따라 15배 흔들린다.** 처음에 기존 postgres
  프로세스 전부(`-p 259423,...,259431`)에 붙였을 때 LLC-load-misses **82,561,959 /
  82,624,131**이 나왔고, postmaster 단독 부착에서는 **5,073,456 / 5,248,775 /
  5,632,361**이 나왔다. 같은 런에서 instructions는 2.5 % 안에서 일치한다
  (436.3 G vs 425.5 G). **표에는 task-clock이 A의 /proc 값과 0.3 %로 일치하는
  postmaster 단독 부착값을 실었다.** 15배 불일치의 원인은 **미해결**로 남긴다.
* **시스템 와이드 계수(`perf stat -a -C 0-15`)로 중재를 시도했으나 신뢰할 수 없다.**
  질의 없이 `sleep 9`만 한 idle 기준선이 instructions **469,750,944,116**,
  LLC-load-misses **426,385,444**로 나왔다 — 부하 평균 ~2인 장비에서 물리적으로
  불가능한 값이다. `perf` 4.18(el8)과 커널 6.9.4의 조합 문제로 보이며
  (`ENVIRONMENT.md`가 예고한 위험), 이 경로는 중재에 쓰지 않았다.
* CUBRID 쪽은 부착 방식이 하나뿐이고(단일 프로세스) 3회 값이
  78.63 M / 79.11 M / 79.18 M로 안정적이다.

---

## C. 엔진 내부 카운터 (A/B와 **별개 런**)

`EXPLAIN (ANALYZE)`와 `stats_on`은 계측 오버헤드가 있어 A/B 타이밍과 섞지 않았다.

### C-1 CUBRID

`cubrid statdump`의 세부 카운터는 **`stats_on`이 켜져야 수집된다**
(`stats_on`은 `PRM_FOR_SERVER|PRM_HIDDEN`, 기본 `false` —
`system_parameter.c:4476-4479`). 기본 상태로 뜬 델타는 비어 있었다(비영 카운터 6개,
페이지 페치 0). 그래서 **C 전용으로 `stats_on=yes`를 넣고 재기동해 측정한 뒤 즉시
제거하고 재기동해 원상복구**했다(`grep -c stats_on` = 0으로 확인, `parallelism=6`과
`update_statistics_update_histogram=y` 유지 확인). 이 런의 질의 시간은 31.813 s로
A의 평균 31.846 s와 사실상 같아 `stats_on` 오버헤드는 이 규모에서 무의미하다.

비영 델타 47개 중 주요 항목:

| 카운터 | 델타 |
|---|---|
| **Num_data_page_fetches** | **683,137** |
| **Num_data_page_ioreads** (= `Num_file_ioreads`) | **682,957** |
| Num_alloc_bcb | 682,969 |
| Num_page_locks_acquired | 682,969 |
| Num_unfix_void_aout_not_found | 682,969 |
| Num_unfix_void_to_shared_mid | 682,962 |
| Num_data_page_hash_anchor_waits | 2,048,920 |
| Total_time_alloc_bcb | 415,000 |
| Time_data_page_hash_anchor_wait | 143,000 |
| Num_data_page_dirties | 116 |
| Num_data_page_iowrites / Num_data_page_flushed | 13 / 13 |

`stats_on` 없이도 얻히는 per-query 카운터(`;trace on text`, 3단계 채증):
`SCAN (table: dba.lineitem), (heap time: 32081, fetch: 682982, ioread: 682950,
readrows: 59986052, rows: 59986052)`, `GROUPBY (… page: 0, ioread: 0, rows: 4)`.
statdump 델타와 fetch/ioread가 0.03 % 내로 일치한다.

### C-2 PostgreSQL

`SET track_io_timing = on` (세션), `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)`.

| 항목 | 값 |
|---|---|
| **Buffers: shared hit** | **53,322** |
| **Buffers: shared read** | **1,071,848** |
| 합계 fetch | 1,125,170 |
| **I/O Timings: shared read** | **41.612 ms** |
| 워커별 read | 153,024 / 153,216 / 153,216 / 153,248 / 153,216 / 152,640 |
| 워커별 hit | 7,682 / 7,625 / 7,564 / 7,631 / 7,588 / 7,473 |

교차 확인 `pg_statio_user_tables`(누적): `heap_blks_read` 50,441,351 /
`heap_blks_hit` 6,002,944 — 이 세션만이 아닌 누적값이므로 대조용으로만 기록한다.

### C-3 정규화 대조

| 지표 | CUBRID | PostgreSQL | 비 |
|---|---|---|---|
| 페이지 크기 | 16,384 B | 8,192 B | 2.0x |
| 버퍼 fetch 수 | 683,137 | 1,125,170 | 0.607x |
| 버퍼 fetch / 행 | 0.011388 (1 fetch / 87.8행) | 0.018757 (1 / 53.3행) | 0.607x |
| 버퍼풀 미스(ioread / shared read) | 682,957 (99.97 %) | 1,071,848 (95.26 %) | 0.637x |
| **fetch된 바이트** | **10,674 MiB** | **8,791 MiB** | **1.214x** |
| fetch된 바이트 / 행 | 186.6 B | 153.7 B | 1.214x |
| 물리 디스크 read (`/proc/diskstats`) | 0.0 MiB | 0.0 MiB | — |

스캔 범위: 양쪽 모두 **테이블 전체**를 읽는다 — CUBRID `readrows: 59986052`,
PG `Parallel Seq Scan` actual rows 8,448,944.14 × 7 loops = 59,142,609 통과 +
`Rows Removed by Filter: 120,492` × 7 = 843,443 제외 = 59,986,052. 인덱스는 쓰이지
않는다(양쪽 순차 스캔).

---

## D. 스캔 바이트량 분해

### D-1 8테이블 전체 — 1.21x는 lineitem 특유가 아니다

| 테이블 | 행 | CUBRID MiB | PG MiB | CUBRID B/행 | PG B/행 | 비 | CUBRID 행/페이지 | PG 행/페이지 |
|---|---|---|---|---|---|---|---|---|
| lineitem | 59,986,052 | 10,670.9 | 8,790.1 | 186.53 | 153.65 | **1.214** | 87.84 | 53.31 |
| orders | 15,000,000 | 2,370.1 | 2,041.1 | 165.68 | 142.68 | 1.161 | 98.89 | 57.41 |
| partsupp | 8,000,000 | 1,457.5 | 1,367.6 | 191.04 | 179.26 | 1.066 | 85.76 | 45.70 |
| part | 2,000,000 | 380.5 | 320.2 | 199.50 | 167.87 | 1.188 | 82.13 | 48.80 |
| customer | 1,500,000 | 328.9 | 281.1 | 229.91 | 196.52 | 1.170 | 71.26 | 41.69 |
| supplier | 100,000 | 20.0 | 17.6 | 209.88 | 184.81 | 1.136 | 78.06 | 44.33 |
| **8테이블 합** | | **15,228** | **12,818** | | | **1.188** | | |

### D-2 구조 상수 (소스 인용)

| 항목 | CUBRID | PostgreSQL |
|---|---|---|
| 페이지 크기 | 16 KiB (`spacedb`: "pagesize 16.0K") | 8 KiB (`show block_size` = 8192) |
| 페이지 헤더 | `SPAGE_HEADER` **32 B** (`slotted_page.h`, 필드 합) | `PageHeaderData` **24 B** |
| 행당 슬롯/포인터 | `SPAGE_SLOT` **4 B** (`slotted_page.h:60`, 14+14+4 비트) | line pointer **4 B** |
| 행 헤더 | MVCC: repid/flags 4 B + insert MVCCID 8 B (+ delete 8, prev-version LSA 8 — 조건부) — `object_representation.h:475,484,488,492` | `HeapTupleHeaderData` 23 B → `t_hoff` MAXALIGN **24 B** |
| VARCHAR | `charlen < 255`면 **1 B + charlen** (`or_varchar_length_internal`, `OR_MINIMUM_STRING_LENGTH_FOR_COMPRESSION 255`) | varlena short header 1 B + charlen |
| CHAR(n) | 고정 n B(공백 패딩) + 정렬 | varlena 1 B + n B |
| DECIMAL | 고정폭 packed. 자릿수→크기 표 `_gv_mr_fixed_numeric_bytes_to_size[17] = {0,4,8,8,8,8,12,12,12,12,16,16,16,16,20,20,20}` (`object_primitive.c:151-153`) + 3 B 헤더(`object_primitive.c:8383-8388`) | `numeric` 가변길이 |

### D-3 페이지 산술 검증

```
PG    : 53.31 행/8192 B  ->  (8192 - 24 PageHeader)/53.31 = 153.20 B  -> 튜플 149.20 B (line ptr 4 B 제외)
        측정 pg_column_size(lineitem.*) = 144.32 B   -> 차 4.9 B = 페이지 잔여 공간(페이지당 약 278 B) ✔ 독립 일치
CUBRID: 87.84 행/16384 B ->  (16384 - 32 SPAGE_HEADER)/87.84 = 186.17 B -> 레코드 182.17 B (slot 4 B 제외)
```

### D-4 컬럼별 저장 바이트 — CUBRID는 실측(격리 스크래치 DB), PG는 실측(`pg_column_size`)

CUBRID 쪽은 **측정 DB를 건드리지 않고** 별도 `CUBRID_DATABASES` 경로에 스크래치
DB를 만들어 컬럼군별 변형 테이블 5개(각 500,000행)를 적재하고 힙 페이지 수를 읽어
**기준 테이블 대비 한계 비용**으로 구했다. 측정 후 스크래치 DB는 삭제했고 측정
`databases.txt`는 무변경이다.

| 변형 (500,000행) | 힙 페이지 | B/행 | 기준 대비 한계 |
|---|---|---|---|
| `v_base` (INTEGER 1개) | 685 | 22.45 | — |
| `v_dec` (+ DECIMAL(15,2) 4개) | 1,777 | 58.23 | **+35.78** |
| `v_char` (+ CHAR 1,1,25,10) | 2,605 | 85.36 | **+62.91** |
| `v_date` (+ DATE 3개) | 1,097 | 35.95 | **+13.50** |
| `v_varchar` (+ VARCHAR(44), 평균 24.04자) | 1,765 | 57.84 | **+35.39** |

모델 검증: lineitem 예측 = 22.45 + 12.00(추가 INTEGER 3개 × `OR_INT_SIZE` 4, 소스
파생) + 35.78 + 62.91 + 13.50 + 35.39 = **182.03 B/행**. lineitem의 `l_comment`
평균은 26.50자로 변형 테이블의 24.04자보다 2.46자 길므로 +2.46 B 보정 → **184.5**.
**측정 186.53** → 잔차 **+2.0 B (1.1 %)**. 이 잔차는 컬럼 수에 따라 커지는 bound
bits / 가변컬럼 오프셋 테이블과 정렬 패딩으로 추정되며 **귀속시키지 않고 잔차로
남긴다.**

### D-5 1.21x 항목별 (요청한 형태)

| 항목 | CUBRID B/행 | PG B/행 | 차 | 격차 기여 |
|---|---|---|---|---|
| 4 × INTEGER | 16.00 | 16.00 | ±0.00 | 0 % |
| **4 × DECIMAL(15,2) / numeric(15,2)** | 35.78 | 23.25 | **+12.53** | **38 %** |
| **4 × CHAR (1, 1, 25, 10)** | 62.91 | 41.00 | **+21.91** | **67 %** |
| 3 × DATE | 13.50 | 12.00 | +1.50 | 5 % |
| 1 × VARCHAR(44) | 35.39 | 27.50 | +7.89 | 24 % |
| **컬럼 데이터 소계** | **163.59** | **119.75** | **+43.85** | **133 %** |
| 행 구조 오버헤드 (행 헤더 + 슬롯/line ptr + 페이지 헤더 + 잔여공간) | 22.94 | 33.90 | **−10.96** | **−33 %** |
| **합계** | **186.53** | **153.65** | **+32.88** | **100 %** |
| | | | | **비 1.214x** |

PG 컬럼 실측(`pg_column_size` 평균, 59,986,052행 전수):
`l_orderkey/partkey/suppkey/linenumber` 각 4.00 · `l_quantity` 5.00 ·
`l_extendedprice` 8.65 · `l_discount` 4.82 · `l_tax` 4.78 ·
`l_returnflag/linestatus` 각 2.00 · `l_shipdate/commitdate/receiptdate` 각 4.00 ·
`l_shipinstruct` 26.00 · `l_shipmode` 11.00 · `l_comment` 27.50 ·
`lineitem.*` 전체 144.32.

**읽히는 바이트**: 두 엔진 모두 테이블 전체를 순차 스캔한다. CUBRID
682,957 페이지 × 16 KiB = **10,671 MiB**, PG 1,071,848 페이지 × 8 KiB =
**8,374 MiB**(+ shared hit 53,322 페이지 417 MiB = fetch 총 8,791 MiB). 인덱스
페이지는 양쪽 0.

---

## 채증 색인

| 산출물 | 경로 |
|---|---|
| A 원시 TSV + 스냅샷 JSON | `.git_ignored_dir/g1-abcd/raw/A/` |
| A 수집기 | `.../g1-abcd/scratch/{snap.py,reduce_a.py,run-a.sh}` |
| B perf 출력 (부착 4종 + 교차확인 + 시스템와이드) | `.../g1-abcd/raw/B/*.perf` |
| C statdump 전/후, EXPLAIN, pg_statio | `.../g1-abcd/raw/C/` |
| C용 conf 백업(원상복구 근거) | `.../g1-abcd/raw/C/cubrid.conf.before-stats-on` |
| D 페이지 수, 컬럼 크기, 변형 페이지 수 | `.../g1-abcd/raw/D/` |

## 상태

| 항목 | 상태 |
|---|---|
| 데이터 | 재적재 0건, 8테이블 무변경 (측정 후 `count(*)` 59,986,052 재확인) |
| CUBRID conf | `stats_on` 제거 완료, `parallelism=6` / `update_statistics_update_histogram=y` 유지 |
| 서버 | 양쪽 기동 중, `cub_server` affinity 0-15 |
| `~/CUBRID` | 불변 |
| 스크래치 DB | 삭제, 측정 `databases.txt` 무변경 |
