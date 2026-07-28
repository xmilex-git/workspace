# CUBRID 옵티마이저 히스토그램 활성화 — 적용·생성·소비 채증

2026-07-28. 결정은 ADR 0008. **쿼리 wall time은 재지 않았고, 플랜을 해석하거나
병목 후보를 지목하지 않는다**(ADR 0005). 데이터는 건드리지 않았다 —
`lineitem` 포함 8테이블 재적재 0건, 통계만 재구축했다.

## 결론 (5줄)

1. `update_statistics_update_histogram=yes`를 측정 install의 `cubrid.conf`에 넣고
   래퍼로 재기동해 `[C*]`/`[S*]` 양쪽 `y`를 채증했다. `~/CUBRID` 심링크 불변.
2. **`UPDATE STATISTICS ... WITH FULLSCAN`만으로는 의도한 히스토그램이 안 만들어진다** —
   `bucket_count=-1`이 기본값 300 대신 **최소값 4**로 클램프되고, `ON ALL CLASSES`
   경로는 `WITH FULLSCAN`을 버려 샘플링으로 만든다. 테이블별
   `ANALYZE TABLE … DROP HISTOGRAM` → `UPDATE HISTOGRAM WITH FULLSCAN`으로 바로잡았다.
3. 생성 확정: `db_histogram` **0 → 283행**, 8테이블 **61컬럼 전부** 300버킷·`full scan`,
   MCV·`null_frequency`가 실제로 채워졌다.
4. **히스토그램이 소비된다** — `l_shipdate < date` 추정이 실제의 **0.232배 → 1.004배**로,
   `BETWEEN` 범위는 **0.066배 → 1.001배**로 교정됐다. 소스가 예측한 대로 `attr op attr`
   (`0.158배`)과 `IN` 목록은 **불변**이다.
5. **여전히 없는 것**: 물리 correlation, avg_width(소스에 개념 자체가 없음), 정확한
   도메인 min(최저 버킷이 `(-inf, hi]`로 열림), `attr op attr` 히스토그램 경로.

## 1. 파라미터 적용 경로

세션 설정이 아니라 **측정 install의 `cubrid.conf`**를 골랐다. G1 하네스는 런마다
새로 접속하므로 세션 스코프로는 지속되지 않는다.

적용 파일 `~/tpch-sspq-install/cubrid-f30f1c260/conf/cubrid.conf` — 추가한 블록
(`[common]` 섹션 끝, 기존 `max_parallel_workers=100` 다음):

```
# --- tpch-sspq 2.6 (2026-07-28): optimizer histogram ENABLED -------------
# DELIBERATE DEPARTURE FROM THE CUBRID DEFAULT. Ships as `no`; set to `yes`
# here so `UPDATE STATISTICS` also builds column histograms + MCV + null
# frequency into `_db_histogram`. Rationale, scope and the mandatory citation
# caveat are in tpch-sspq/docs/adr/0008-enable-cubrid-optimizer-histogram.md.
# Numbers produced on this configuration must NOT be quoted as
# default-configuration CUBRID.
update_statistics_update_histogram=yes
# default_histogram_bucket_count is deliberately LEFT UNSET so CUBRID's own
# default (300) applies, mirroring PostgreSQL being left at its own default
# (default_statistics_target=100). The 300-vs-100 asymmetry is recorded as a
# fact, not aligned. See ADR 0008 §4.
```

원본은 `.git_ignored_dir/g1-assets/raw/hist-probe/cubrid.conf.before`에 보존.

재기동은 래퍼만 사용:
`.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh restart tpch_sf10_q1`
→ `RESULT: OK`, `Server tpch_sf10_q1 (rel 11.5.0, pid 192002)`.

### 채증 — `cubrid paramdump tpch_sf10_q1`

재기동 **전** (클라이언트는 새 접속에서 즉시 반영, 서버는 아직 아님):

```
[C ] default_histogram_bucket_count=300 (300)
[C*] update_statistics_update_histogram=y (n)
[S ] update_statistics_update_histogram=n (n)
```

재기동 **후** — 요구된 `[C]`/`[S]` 양쪽 `y`:

```
[C ] default_histogram_bucket_count=300 (300)
[C*] update_statistics_update_histogram=y (n)
[S*] update_statistics_update_histogram=y (n)
```

`*`는 기본값 이탈 표시, 괄호 안 `(n)`이 출시 기본값이다. 즉 이 덤프 자체가
"기본값에서 벗어났다"는 증거로 쓰인다.

불가침 확인: `readlink ~/CUBRID` → `/home/cubrid/jdbc-direct-poc-release/CUBRID-jdbc-direct-v3-r1`
(변경 없음).

## 2. 버킷 수 — 각 엔진 기본값, 비대칭은 기록만

| 엔진 | 파라미터 | 값 | 의미 범위 |
|---|---|---|---|
| CUBRID | `default_histogram_bucket_count` | **300** | 버킷 수만 |
| PostgreSQL | `default_statistics_target` | **100** | 버킷 수 + MCV 상한 + 표본 크기(300×target = 30,000행) |

두 값은 **동일 의미가 아니다.** PG의 target은 표본 크기까지 좌우하고 CUBRID의
버킷 수는 그렇지 않다. 지금은 맞추지 않고 사실로만 남긴다(ADR 0008 §4).

**정렬 비용 실측** — 8테이블 DROP+재구축 wall:

| 버킷 수 | region | nation | supplier | customer | part | partsupp | orders | lineitem | 합계 |
|---|---|---|---|---|---|---|---|---|---|
| **300** (기본) | 0.02 | 0.02 | 0.49 | 1.00 | 1.22 | 3.21 | 4.26 | 29.23 | **39.71 s** |
| **100** (PG 정렬 시) | 0.02 | 0.02 | 0.31 | 0.67 | 0.82 | 2.83 | 3.76 | 27.79 | **36.47 s** |

**차이 3.24 s.** 버킷 수 정렬은 40초 이내에 언제든 되돌릴 수 있으므로 값싸게
가역적이다. 지금 결정을 서두를 이유가 없다. (별도 샘플: 300버킷 재구축 2회가
39.74 s / 39.71 s로 재현된다.)

참고로 100버킷 상태의 추정치는 300버킷과 거의 같았다 —
`l_shipdate < date` 0.431372 (300버킷 0.431833, 실제 0.430172)로 100버킷이 오히려
근소하게 가까웠다. 버킷 수가 이 데이터셋의 날짜 술어 추정에서 지배 요인이 아니라는
사실만 기록한다.

## 3. 통계 재실행 기록

### 3-1. 먼저 `UPDATE STATISTICS ON ALL CLASSES WITH FULLSCAN` (요구된 명령)

| 항목 | 값 |
|---|---|
| 시작 | 2026-07-28 18:29:14.039 |
| 종료 | 2026-07-28 18:30:34.142 |
| wall | **79.93 s** (히스토그램 없던 2.5단계의 57.14 s 대비 +22.8 s) |
| 결과 | `db_histogram` 0 → **283행** |
| 그런데 | 전부 **`sampling scan`**, `l_shipdate` 버킷 **4개** |

### 3-2. 왜 4버킷·샘플링인가 (소스 인용)

두 `UPDATE STATISTICS` 경로 모두 `-1`을 넘긴다:

```c
network_interface_cl.c:6196      histogram_info.target_columns = NULL;
network_interface_cl.c:6197      histogram_info.bucket_count = -1;
network_interface_cl.c:6198      histogram_info.with_fullscan = false;
network_interface_cl.c:6199      error = update_or_drop_histogram_helper (NULL, obj, &histogram_info, DO_HISTOGRAM_CREATE);
```
```c
execute_statement.c:4776		  histogram_info.target_columns = NULL;
execute_statement.c:4777		  histogram_info.bucket_count = -1;
execute_statement.c:4778		  histogram_info.with_fullscan = statement->info.update_stats.with_fullscan;
```

수신 측은 **정확히 0일 때만** 기본값을 대입한다:

```c
execute_schema.c:4289	  bucket_count =
execute_schema.c:4290	    (histogram_info->bucket_count ==
execute_schema.c:4291	     0) ? prm_get_integer_value (PRM_ID_DEFAULT_HISTOGRAM_BUCKET_COUNT) : histogram_info->bucket_count;
execute_schema.c:4293	  sysprm_get_range (PRM_ID_DEFAULT_HISTOGRAM_BUCKET_COUNT, &bucket_count_min, &bucket_count_max);
execute_schema.c:4294	  if (bucket_count < bucket_count_min)
execute_schema.c:4296	      bucket_count = bucket_count_min;
```

`-1`은 대입 조건에 안 걸리고 클램프에 걸려 **최소값 4**가 된다
(`system_parameter.c:5349` → min 4). 그리고 `ON ALL CLASSES` 경로는
`with_fullscan = false`를 하드코딩하므로 문장의 `WITH FULLSCAN`이 **버려진다**.

반면 `ANALYZE TABLE … UPDATE HISTOGRAM`은 빈 버킷 절이 `0`이라 기본값 300이 적용된다:

```
csql_grammar.y:4809        : ANALYZE TABLE only_class_name UPDATE HISTOGRAM opt_with_column_list opt_with_n_buckets opt_with_fullscan
csql_grammar.y:4889 opt_with_n_buckets
csql_grammar.y:4890         : /* empty */
csql_grammar.y:4892                         {{ $$ = 0;
```

### 3-3. `with_fullscan` 플래그가 스테일이 되는 문제 — 실측으로 확인

기존 카탈로그 엔트리 위에 다시 만들면 블롭은 갱신되지만 플래그는 원래 값이
남는다(`sm_add_histogram`이 `ER_LC_CLASSNAME_EXIST`를 관용 — `execute_schema.c:4373`).
`region`으로 대조 실험:

```
제자리 재구축 후            : dba.region r_regionkey 'sampling scan'
DROP HISTOGRAM 후           : (행 없음)
UPDATE HISTOGRAM WITH FULLSCAN 후 : dba.region r_regionkey 'full scan'
```

그래서 최종 절차는 **DROP 먼저**다. `.git_ignored_dir/g1-assets/scratch/rebuild-hist.sh`에 고정.

### 3-4. 최종 재구축 (전달 상태)

| 항목 | 값 |
|---|---|
| 명령 | 테이블별 `ANALYZE TABLE <t> DROP HISTOGRAM;` → `ANALYZE TABLE <t> UPDATE HISTOGRAM WITH FULLSCAN;` |
| 시작 | 2026-07-28 18:40:19.790 |
| 종료 | 2026-07-28 18:40:59.499 |
| wall | **39.71 s** (8테이블 합) |
| 버킷 | 300 (엔진 기본값) |
| 스캔 | 전체 스캔 |

## 4. 생성 채증

### 4-1. 카탈로그 카운트

```sql
SELECT count(*) AS histogram_rows FROM db_histogram;
-- 2.5단계:      0
-- 2.6단계:    283
```

TPC-H 8테이블 컬럼의 스캔 플래그 (`db_histogram`, TPC-H 컬럼 접두어 필터):

```
  with_fullscan                         cols
============================================
  'full scan'                             61
  'sampling scan'                        104
```

**61 = 16+9+9+8+7+5+4+3**, 즉 8테이블 전체 컬럼 수와 정확히 일치한다. 나머지 104는
접두어가 우연히 겹친 시스템 카탈로그 클래스들이다(283행 중 나머지).

### 4-2. 테이블·컬럼별 보유 현황 (`SHOW HISTOGRAM <t>` 집계)

| 테이블 | 컬럼 | MCV 합 | 버킷 합 | 버킷 보유 컬럼 | MCV만(버킷 0) |
|---|---|---|---|---|---|
| region | 3 | 15 | 0 | 0 | **3** |
| nation | 4 | 80 | 0 | 0 | **4** |
| supplier | 7 | 102 | 1819 | 7 | 0 |
| customer | 8 | 1 | 1829 | 8 | 0 |
| part | 9 | 493 | 1460 | 9 | 0 |
| partsupp | 5 | 52 | 1500 | 5 | 0 |
| orders | 9 | 85 | 1807 | 9 | 0 |
| lineitem | 16 | 291 | 2484 | 16 | 0 |
| **계** | **61** | **1029** | **10899** | **45** | **7** |

`region`(5행)·`nation`(25행)은 도메인 전체가 MCV에 들어가 버킷이 0이다 — PG가
`l_quantity`(50개)·`o_orderstatus`(3개)에서 `histogram_bounds`를 비우는 것과 같은
동작이다. 2.5단계에서 "16개 중 1개만 통계"였던 것과 대비된다: **이제 61/61 전부**가
컬럼 통계를 갖는다.

### 4-3. `l_shipdate` 히스토그램 실제 경계

```
+------------------ HISTOGRAM -------------------+
|  column : l_shipdate (date)                    |
|  rows   : 59986052                             |
|  null frequency : 0.000                        |
|  mcv : 71   buckets : 300                      |
+------------------------------------------------+
MCV#00 [2448739] freq=0.00057
MCV#01 [2448769] freq=0.00058
#00 (-inf, 2448667] rows=188623(0.003) ndv=41  cum=0.003
#01 (2448667, 2448685] rows=190622(0.003) ndv=18  cum=0.006
#02 (2448685, 2448698] rows=185290(0.003) ndv=13  cum=0.009
   ...
#297 (2451076, 2451093] rows=207952(0.003) ndv=17  cum=0.954
#298 (2451093, 2451114] rows=189956(0.003) ndv=21  cum=0.957
#299 (2451114, 2451147] rows=119305(0.002) ndv=30  cum=0.959
```

값은 **julian day 정수**로 출력된다(`bucket_hi_dump_with_type`이 DATE를 정수로
찍는다). 변환하면:

| 슬롯 | julian | 날짜 |
|---|---|---|
| bucket#00 hi | 2448667 | 1992-02-14 |
| bucket#01 hi | 2448685 | 1992-03-03 |
| bucket#297 hi | 2451076 | 1998-09-19 |
| bucket#299 hi (최대) | 2451147 | 1998-11-29 |
| MCV#00 | 2448739 | 1992-04-26 |

### 4-4. `o_orderdate` 히스토그램 실제 경계

```
|  column : o_orderdate (date)                   |
|  rows   : 15000000                             |
|  null frequency : 0.000                        |
|  mcv : 27   buckets : 300                      |
MCV#00 [2448761] freq=0.00059
MCV#01 [2448905] freq=0.00060
#00 (-inf, 2448630] rows=47667(0.003) ndv=8  cum=0.003
#01 (2448630, 2448637] rows=46666(0.003) ndv=7  cum=0.006
#02 (2448637, 2448644] rows=47834(0.003) ndv=7  cum=0.009
   ...
#297 (2451011, 2451019] rows=48000(0.003) ndv=8  cum=0.980
#298 (2451019, 2451027] rows=50000(0.003) ndv=8  cum=0.983
#299 (2451027, 2451028] rows=6667(0.000) ndv=1  cum=0.984
```

bucket#00 hi = 2448630 = **1992-01-08**, bucket#299 hi = 2451028 = **1998-08-02**.

### 4-5. `null_frequency` — 채워지지만 이 데이터셋으로는 0만 확인 가능

`db_histogram.null_frequency`는 61컬럼 전부 `0.000000000000000e+00`이다. 이것은
**정답**이다: 정본 스키마에서 nullable인 컬럼은 `r_comment`/`n_comment` 둘뿐이고,
실측하니 둘 다 NULL이 0건이다.

```
 r_comment_nulls | rows        n_comment_nulls | rows
-----------------+------             ----------+------
               0 |    5                      0 |   25
```

PG도 같은 컬럼에서 `null_frac = 0`이다. 즉 **필드는 존재하고 채워지지만, 이
데이터셋은 0이 아닌 값을 만들 수 없다.** 데이터 변경은 금지이므로 0이 아닌 사례는
확인하지 않았다 — 이 한계를 사실로 기록한다.

### 4-6. min/max — **여전히 정확히 얻을 수 없다**

| 컬럼 | 히스토그램에서 얻을 수 있는 최저/최고 | 실제 min/max | 판정 |
|---|---|---|---|
| `l_shipdate` | 최저: 없음 (bucket#00이 `(-inf, 1992-02-14]`) / 최고: 1998-11-29 | 1992-01-02 / **1998-12-01** | min 복원 불가, **max도 2일 짧음** |
| `o_orderdate` | 최저: 없음 (bucket#00이 `(-inf, 1992-01-08]`) / 최고: 1998-08-02 | 1992-01-01 / 1998-08-02 | min 복원 불가, max는 정확 |

`l_shipdate`의 MCV 범위도 1992-04-26 ~ 1998-08-03이라 도움이 되지 않는다
(`max(마지막 버킷 hi, MCV 최대) = 1998-11-29`). 최저 버킷이 **열린 구간**이라
도메인 min은 구조적으로 복원 불가다.

대조: PostgreSQL의 `histogram_bounds` 양 끝은 **실제 양 끝**이다 —
`o_orderdate`는 `{1992-01-01, …, 1998-08-02}`로 실측 min/max와 정확히 일치한다.

## 5. 소비 채증 — 히스토그램이 셀렉티비티 경로에서 실제로 쓰인다

계측 도구: `SET OPTIMIZATION LEVEL 514` (= `0x202`, 상세 플랜 덤프 + `level & 0x02`
= "User is only interested in query plan. Query will not be executed" —
`execute_statement.c:12562-12564`). **쿼리가 실행되지 않으므로 wall time이 발생하지
않는다.** 옵티마이저가 term별 `(sel N)`과 노드별 `card N`을 직접 찍는다.

실제 행수는 같은 데이터의 PG에서 1스캔 `count(*) filter (...)`로 측정
(`raw/hist-probe/ground-truth-*.txt`).

### 켜기 전 / 후 추정 대조표

`x` = 추정 card ÷ 실제 행수 (1.000이 완벽).

| 술어 | 실제 행수 | 실제 sel | **전** sel | **전** x | **후** sel | **후** x |
|---|---|---|---|---|---|---|
| P1 `l_shipdate < date '1995-01-01'` | 25,804,316 | 0.430172 | 0.100000 | **0.232** | 0.431833 | **1.004** |
| P2 `l_shipdate >= '1994-01-01' and < '1995-01-01'` | 9,099,165 | 0.151688 | 0.010000 | **0.066** | 0.151769 | **1.001** |
| P3 `l_quantity < 24` | 27,590,886 | 0.459955 | 0.100000 | 0.217 | 0.481067 | **1.046** |
| P4 `l_returnflag = 'R'` | 14,808,183 | 0.246860 | 0.333333 | 1.350 | 0.247600 | **1.003** |
| P5 `l_shipmode IN ('MAIL','SHIP')` | 17,140,455 | 0.285741 | 0.265306 | 0.928 | 0.265306 | 0.928 **(불변)** |
| P6 `l_commitdate < l_receiptdate` | 37,929,348 | 0.632303 | 0.100000 | 0.158 | 0.100000 | 0.158 **(불변)** |
| P7 `l_discount between .06-0.01 and .06+0.01` | 16,361,562 | 0.272756 | 0.010000 | 0.037 | 0.179467 | 0.658 |
| P8 `o_orderdate >= '1993-07-01' and < '1993-10-01'` | 573,671 | 0.038245 | 0.010000 | 0.261 | 0.039583 | **1.035** |
| P9 `o_orderstatus = 'F'` | 7,309,184 | 0.487279 | 0.333333 | 0.684 | 0.490856 | **1.007** |
| P10 `o_orderkey = 12345` | 0 (키 부재) | — | 6.69798E-08 | card 1 | 6.66667E-08 | card 1 |

원문 term 라인 대조 (전 → 후):

```
전: term[0]: [dba.lineitem].l_shipdate range (min inf_lt date '01/01/1995') (sel 0.1)
후: term[0]: [dba.lineitem].l_shipdate range (min inf_lt date '01/01/1995') (sel 0.431833)

전: term[0]: [dba.lineitem].l_shipdate range (date '01/01/1994' ge_lt date '01/01/1995') (sel 0.01)
후: term[0]: [dba.lineitem].l_shipdate range (date '01/01/1994' ge_lt date '01/01/1995') (sel 0.151769)

전: term[0]: [dba.lineitem].l_commitdate range (min inf_lt [dba.lineitem].l_receiptdate) (sel 0.1)
후: term[0]: [dba.lineitem].l_commitdate range (min inf_lt [dba.lineitem].l_receiptdate) (sel 0.1)
```

### 이 표가 확인하는 사실 (해석 아님)

* **`qo_comp_selectivity` / `PT_RANGE` 경로의 히스토그램 프로브가 성공한다.**
  P1·P2·P3·P8이 상수 `0.1`/`0.01`에서 벗어났다. 2.5단계에서 인용한
  `return success ? selectivity : DEFAULT_COMP_SELECTIVITY;`
  (`query_planner.c:10624`)의 `success`가 이제 참이 된다는 뜻이다.
* **`qo_equal_selectivity`도 히스토그램을 쓴다.** P4는 `1/NDV = 1/3 = 0.333333`에서
  `0.2476`으로 바뀌었다 — NDV 경로가 낼 수 없는 값이므로
  `histogram_get_equal_selectivity`가 성공한 것이다. P9도 같다.
* **`attr op attr`은 불변** (P6, 0.1 고정). 2.5단계에서 인용한
  `query_planner.c:10523-10525`의 `/* TODO: add histogram selectivity */`와
  정확히 일치한다.
* **`IN` 목록은 불변** (P5, 0.265306). `qo_all_some_in_selectivity`는 히스토그램을
  소비하지 않는다.
* P7(`BETWEEN` on numeric)은 개선되었으나 여전히 0.658배로 어긋난다. 사실만 기록한다.

### 부수 관측: NDV 값도 일부 갱신됐다

히스토그램 전체 스캔이 클래스 통계를 함께 갱신한다(`execute_statement.c:4772-4775`
주석). 실측 변화:

| 컬럼 | 2.5단계 NDV | 2.6단계 NDV | 정확값 |
|---|---|---|---|
| `o_orderkey` | 14,929,885 | **15,000,000** | 15,000,000 (정확해짐) |
| `o_orderdate` | 2,398 | **2,406** | 2,406 (정확해짐) |
| `o_custkey` | 992,718 | 992,718 | 999,982 (불변) |
| `o_clerk` | 10,056 | 10,056 | 10,000 (불변) |
| `l_shipdate` | 2,525 | 2,525 | 2,526 (불변) |
| `l_commitdate` | 2,463 | 2,466 | — |

일관되게 정확해지는 것은 아니다. 사실만 기록한다.

## 6. 갱신된 통계 축별 대조표

2.5단계 표를 이 구성 기준으로 대체한다.

| 축 | CUBRID **2.5단계**(기본값) | CUBRID **2.6단계**(히스토그램 on) | PostgreSQL |
|---|---|---|---|
| 테이블 행수 | 정확 | 정확 | 표본 추정 (`reltuples`) |
| 테이블 페이지 수 | 있음 | 있음 | 있음 (`relpages`) |
| 컬럼 NDV | 표본 외삽 | 표본 외삽 (일부 정확해짐) | 표본 외삽 (`n_distinct`) |
| **컬럼 null 비율** | **없음** | **있음** (`null_frequency`; 이 데이터셋은 전부 0) | 있음 (`null_frac`) |
| **도수분포** | **없음** | **있음** — 300 equi-depth 버킷 | 있음 — 100 equi-depth 버킷 |
| **MCV + 빈도** | **없음** | **있음** (`SHOW HISTOGRAM`의 `MCV#nn … freq=`) | 있음 (`most_common_vals`/`_freqs`) |
| MCV 저장 위치 | — | `_db_histogram.histogram_values` **불투명 BIT VARYING 블롭** | `pg_stats` 배열 컬럼(SQL로 직접 조회) |
| **컬럼 min/max** | **없음** | **여전히 정확히 불가** (최저 버킷 열림, max도 불일치 사례 있음) | 사실상 있음 (`histogram_bounds` 양 끝 = 실제 양 끝) |
| **물리 correlation** | **없음** | **여전히 없음** (소스에 개념 없음) | 있음 (`correlation`) |
| **평균 폭** | **없음** | **여전히 없음** (소스에 개념 없음) | 있음 (`avg_width`) |
| 컬럼 통계 보유 컬럼 수 | lineitem 16개 중 **1개** | **61/61 전부** | 전부 |
| 범위 술어 셀렉티비티 | 상수 0.1 / 0.01 | **히스토그램 유래** (실측 오차 1.00~1.05배) | 히스토그램 유래 |
| `attr op attr` 셀렉티비티 | 상수 0.1 | **상수 0.1 (불변)** | 히스토그램/통계 유래 |
| `IN` 목록 셀렉티비티 | NDV 유래 | **NDV 유래 (불변)** | MCV 유래 |
| 버킷 수 파라미터 | — | `default_histogram_bucket_count=300` | `default_statistics_target=100` |
| 표본 크기 | NDV 추정용 표본 | 전체 스캔(`WITH FULLSCAN`) | 300×target = 30,000행 |

`correlation`/`avg_width` 부재 근거:
`grep -E 'correlation|avg_width|average_width|clustering' src/optimizer/histogram/ src/storage/statistics.h src/storage/statistics_sr.c`
→ **0건**.

## 7. "통계 파리티"의 재정의 (2.6단계 판)

2.5단계가 이 표현을 "freshness 파리티"로 축소했다. 이제 한 단계 올라가지만
**여전히 완전 파리티가 아니다.**

> **통계 파리티 (2.6단계 정의)**: 양쪽 엔진이 각자 표준 명령으로 같은 데이터에서
> 갱신됐고(freshness), **양쪽 모두 컬럼 히스토그램·MCV·null 비율을 보유한다**
> (information class). 단 다음은 여전히 CUBRID에 없다: 물리 correlation,
> avg_width, 정확한 도메인 min/max, `attr op attr` 술어의 히스토그램 경로.
> 버킷 수도 정렬되지 않았다(300 vs 100, 의미도 다름).

G4는 이 네 항목을 여전히 전제로 명기해야 한다. 다만 2.5단계와 달리 **범위 술어
카디널리티 추정은 양쪽 다 데이터에 반응하는 상태**이므로, plan 형상 차이를
"CUBRID는 범위 셀렉티비티를 상수로 본다"로 설명할 수는 없게 됐다.

## 8. 대외 인용 단서 (필수)

> 이 측정의 CUBRID는 `update_statistics_update_histogram=yes`(기본값 `no`)로
> 옵티마이저 히스토그램을 활성화한 구성이다. 기본 설정 CUBRID는 컬럼 히스토그램을
> 만들지 않으며, 그 경우 범위 술어 셀렉티비티가 상수로 추정된다. 따라서 이 수치는
> 기본 설정 CUBRID의 성능이 아니다.

ADR 0002의 PostgreSQL 단서와 **함께** 붙는다.

## 9. 상태 / 불가침 확인

| 항목 | 상태 |
|---|---|
| 데이터 | **재적재 0건.** `lineitem` 포함 8테이블 무변경 (통계만 재구축) |
| `~/CUBRID` | 불변 — `jdbc-direct-poc-release/CUBRID-jdbc-direct-v3-r1` |
| 공용 `~/databases` | 불변 (전용 `databases.txt` 사용) |
| CUBRID 서버 | 기동 중 (재기동 후 pid 192002), 래퍼 경유만 |
| PG 서버 | 기동 중 (pid 43415, port 5442), 무변경 |
| 쿼리 wall time | **0건 측정.** 플랜 덤프는 `level & 0x02`로 실행 없이 획득 |
| 최종 히스토그램 상태 | 61컬럼 / 300버킷 / `full scan` |

## 증거 색인

| 산출물 | 경로 |
|---|---|
| conf 원본 | `.git_ignored_dir/g1-assets/raw/hist-probe/cubrid.conf.before` |
| paramdump 후 | `.git_ignored_dir/g1-assets/raw/hist-probe/paramdump-after.txt` |
| 셀렉티비티 프로브 SQL | `.git_ignored_dir/g1-assets/raw/hist-probe/sel-probe.sql` |
| 켜기 전 플랜 | `.../hist-probe/before-plan.txt` |
| 4버킷 중간 상태 | `.../hist-probe/after-b4-plan.txt` |
| 100버킷 상태 | `.../hist-probe/after-b100-plan.txt` |
| 최종 300버킷 | `.../hist-probe/after-final-plan.txt` |
| 실제 행수 | `.../hist-probe/ground-truth-{lineitem,orders}.txt` |
| 히스토그램 덤프 | `.../hist-probe/hist-{l_shipdate,o_orderdate}.txt`, `showhist-<t>.txt` |
| 재구축 스크립트 | `.git_ignored_dir/g1-assets/scratch/rebuild-hist.sh` |
| 재구축 로그 | `.git_ignored_dir/g1-assets/logs/hist-{b300-clean,b100,b300-restore}/` |
| UPDATE STATISTICS 로그 | `.git_ignored_dir/g1-assets/logs/cubrid-stats-hist300.{log,time}` |
