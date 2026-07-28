# Q1 대칭 프로파일링 — 행당 명령어 3.006x의 분해

2026-07-28. 단위 파리티 트랙(양쪽 6 실행 단위) 고정. ADR 0005의 해제 범위대로
**증거에 근거한 원인 후보 도출은 허용**되며, 모든 판단에 근거 숫자를 붙였다. 증거 없는
추정과 사전 지목은 하지 않았다.

## 결론 (5줄)

1. **격차의 최대 기여는 식 평가/튜플 구성(28.8%, 5.57x)이다** — CUBRID 299.7 G vs
   PG 53.8 G instructions. `fetch_peek_arith`·`qdata_add_dbval`·`fetch_val_list` 대
   PG의 `ExecInterpExpr` 하나.
2. **두 번째는 값/도메인 변환(22.9%)이고 PG에는 대응물이 아예 없다** — CUBRID
   195.6 G vs PG **0**. `tp_value_cast_internal`·`db_value_domain_init`·
   `pr_type_from_id`·`pr_clear_value`·`pr_value_mem_size`.
3. **수치 연산은 양쪽 최대 단일 버킷이지만 배수는 1.77x로 전체 평균 3.01x보다 낮다** —
   CUBRID 319.2 G(24.97 %) vs PG 180.2 G(**42.43 %**). DECIMAL 산술 자체는 격차의 주
   동인이 아니다.
4. **메모리 할당은 CUBRID가 오히려 적다** — 57.4 G vs 70.3 G = 0.82x, 격차 기여
   **−1.5 %**.
5. **정렬은 양쪽 0 %** (Q1은 4행만 정렬), **버퍼·래치도 양쪽 0.2 % 미만**.

## 검증 (먼저)

### 프로파일링 오버헤드 — 질의 구간 기준 ±1.7 % 이내

| | 기준선 | instructions:u 런 | cycles:u 런 |
|---|---|---|---|
| CUBRID 질의 구간 | 31.842 s | 32.037 s (**+0.61 %**) | 31.501 s (**−1.07 %**) |
| PostgreSQL 질의 구간 | 10.442 s | 10.307 s (**−1.29 %**) | 10.272 s (**−1.63 %**) |

전부 5 % 문턱 안이므로 샘플 주기를 낮출 필요가 없었다.

기록해 둘 구분: `perf record`를 감싼 **외부 wall**은 PG에서 +10 %였다(11.49 s vs
10.442 s). 이는 16코어 `-a -C` 세팅·기록의 **고정 비용**이고 질의 지연이 아니다.
통제 실험으로 분리했다 — 같은 질의의 서버 보고 시간이 perf 없이 10,399.504 ms,
`-c 10,000,000`에서 10,403.273 / 10,408.992 ms(**+0.04 % / +0.09 %**),
`-c 100,000,000`에서 10,377.436 / 10,402.068 ms였다. 즉 샘플링이 질의를 늦추지 않는다.

### 귀속 검증 — (B) SUT 부착 실측과 자릿수 일치, 그 이상으로 소수점까지

| 프로파일 | SUT 귀속 (샘플 × 주기) | (B) SUT 부착 실측 | 일치 |
|---|---|---|---|
| CUBRID instructions:u | 127,853 × 10 M = **1,278,530,000,000** | 1,278,870,326,058 | **99.97 %** |
| PG instructions:u | 42,461 × 10 M = **424,610,000,000** | 425,447,800,136 | **99.80 %** |
| CUBRID cycles:u | 50,616 × 10 M = 506,160,000,000 | 520,437,684,530 | 97.3 % |
| PG cycles:u | 16,706 × 10 M = 167,060,000,000 | 168,606,419,528 | 99.1 % |

cycles의 일치가 약간 낮은 것은 `cycles:u`가 **유저 모드만** 세는데 (B)의 `cycles`는
커널까지 셌기 때문이다(CUBRID sys 3.767 s/189.747 s = 2.0 %, PG 0.227/62.090 = 0.4 %).
`instructions:u`는 99.8 % 이상 일치하므로 주 표의 근거로 쓴다.

### SUT 귀속 비율 (= 오염 제거율)

| 프로파일 | 전체 샘플 | SUT 샘플 | **귀속 비율** |
|---|---|---|---|
| CUBRID instructions:u | 140,727 | 127,853 | **90.9 %** |
| PG instructions:u | 43,913 | 42,461 | **96.7 %** |
| CUBRID cycles:u | 54,873 | 50,616 | 92.2 % |
| PG cycles:u | 18,455 | 16,706 | 90.5 % |

즉 시스템 와이드 수집분의 3~9 %는 SUT 밖 배경이었고 report 단계에서 제거됐다.

## 방법 — 대칭성

| 항목 | 양쪽 동일 |
|---|---|
| 수집 | `perf record -a -C 0-15`, perf 자신은 `taskset -c 20-23`(SUT 밖) |
| 이벤트 | `instructions:u`(주), `cycles:u`(보조) |
| 샘플 주기 | `-c 10000000` 고정 주기(빈도 아님) — 샘플당 명령어 수가 확정되므로 귀속 총량을 (B)와 대조할 수 있다 |
| 구간 | 질의 실행 구간 |
| 콜그래프 | **붙이지 않음** (아래) |
| 귀속 | report 단계에서 SUT 프로세스로 필터 |

**PG parallel worker가 별도 fork 프로세스라 `-p` attach가 불가능한 비대칭**은 이렇게
흡수했다: 수집은 코어 단위로 하고, 귀속은 pid 집합으로 한다.
SUT 집합 = CUBRID는 `cub_server` 단일 pid(전 스레드가 같은 tgid), PG는 실행 전에
존재하지 않았던 `postgres` pid = leader + parallel worker. 사전 존재한 보조
프로세스(checkpointer/bgwriter 등)는 ADR 0009 경계대로 제외했다.

**콜그래프는 붙이지 않았다.** CUBRID는 `-fno-omit-frame-pointer`로 빌드됐고 PG는
아니어서 fp 언와인딩이 비대칭이기 때문이다. 그리고 그럴 필요가 없었다 — 플랫 결과가
범용 leaf 함수에 지배되지 않는다. `__mem*`류 합계가 CUBRID **1.32 %**, PG **2.82 %**
뿐이고 상위 심볼이 전부 의미 있는 엔진 함수다. 따라서 dwarf 재수집 조건이 성립하지
않았다.

실행 단위 파리티도 프로파일에서 재확인됐다 — PG instructions 프로파일의 SUT pid별 샘플
수가 7,069 / 7,078 / 7,080 / 7,080 / 7,080 / 7,071로 **6개가 균등**하다(leader + 5 worker).

## top 20 심볼 — `instructions:u`, self

### CUBRID (`cub_server` pid 409978, SUT 1,278,530,000,000 instructions)

| # | self % | 누적 % | self instructions | 심볼 | 모듈 |
|---|---|---|---|---|---|
| 1 | 9.78 | 9.78 | 125,040,234,000 | `float_numeric_db_value_add` | `libcubrid.so.11.5` |
| 2 | 5.93 | 15.71 | 75,836,829,000 | `float_numeric_db_value_mul` | `libcubrid.so.11.5` |
| 3 | 5.00 | 20.71 | 63,926,500,000 | `qdata_add_dbval` | `libcubrid.so.11.5` |
| 4 | 4.94 | 25.65 | 63,159,382,000 | `heap_attrinfo_read_dbvalues` | `libcubrid.so.11.5` |
| 5 | 4.36 | 30.01 | 55,763,908,000 | `fetch_peek_arith` | `libcubrid.so.11.5` |
| 6 | 4.24 | 34.25 | 54,209,672,000 | `tp_value_cast_internal` | `libcubrid.so.11.5` |
| 7 | 3.97 | 38.22 | 50,757,641,000 | `qdata_evaluate_aggregate_list` | `libcubrid.so.11.5` |
| 8 | 3.38 | 41.60 | 43,214,314,000 | `pr_clear_value` | `libcubrid.so.11.5` |
| 9 | 2.96 | 44.56 | 37,844,488,000 | `float_numeric_db_value_sub` | `libcubrid.so.11.5` |
| 10 | 2.60 | 47.16 | 33,241,780,000 | `malloc` | `libc-2.28.so` |
| 11 | 2.43 | 49.59 | 31,068,279,000 | `mr_data_readval_numeric` | `libcubrid.so.11.5` |
| 12 | 2.42 | 52.01 | 30,940,426,000 | `qdata_generate_tuple_desc_for_valptr_list` | `libcubrid.so.11.5` |
| 13 | 2.31 | 54.32 | 29,534,043,000 | `fetch_val_list` | `libcubrid.so.11.5` |
| 14 | 2.27 | 56.59 | 29,022,631,000 | `qexec_hash_gby_agg_tuple` | `libcubrid.so.11.5` |
| 15 | 2.25 | 58.84 | 28,766,925,000 | `db_value_domain_init` | `libcubrid.so.11.5` |
| 16 | 2.03 | 60.87 | 25,954,159,000 | `pr_type_from_id` | `libcubrid.so.11.5` |
| 17 | 1.89 | 62.76 | 24,164,217,000 | `fetch_peek_dbval_slow` | `libcubrid.so.11.5` |
| 18 | 1.89 | 64.65 | 24,164,217,000 | `_int_free` | `libc-2.28.so` |
| 19 | 1.70 | 66.35 | 21,735,010,000 | `qdata_is_zero_value_date` | `libcubrid.so.11.5` |
| 20 | 1.64 | 67.99 | 20,967,892,000 | `pr_value_mem_size` | `libcubrid.so.11.5` |

(21~24위: `mr_setval_numeric` 1.62 %, `qdata_aggregate_value_to_accumulator` 1.53 %,
`qdata_add_numeric_to_dbval` 1.35 %, `__memset_evex_unaligned_erms` 1.32 %.
전체 183개 심볼, 누적 99.9 %. top 30 누적 80.3 %.)

### PostgreSQL (leader + 5 worker, SUT 424,610,000,000 instructions)

| # | self % | 누적 % | self instructions | 심볼 | 모듈 |
|---|---|---|---|---|---|
| 1 | 12.68 | 12.68 | 53,840,548,000 | `ExecInterpExpr` | `postgres` |
| 2 | 9.78 | 22.46 | 41,526,858,000 | `init_var_from_num` | `postgres` |
| 3 | 8.47 | 30.93 | 35,964,467,000 | `AllocSetAlloc` | `postgres` |
| 4 | 6.16 | 37.09 | 26,155,976,000 | `make_result_safe` | `postgres` |
| 5 | 5.03 | 42.12 | 21,357,883,000 | `mul_var` | `postgres` |
| 6 | 4.97 | 47.09 | 21,103,117,000 | `detoast_attr` | `postgres` |
| 7 | 4.70 | 51.79 | 19,956,670,000 | `AllocSetFree` | `postgres` |
| 8 | 4.55 | 56.34 | 19,319,755,000 | `accum_sum_add` | `postgres` |
| 9 | 4.35 | 60.69 | 18,470,535,000 | `tts_buffer_heap_getsomeattrs` | `postgres` |
| 10 | 2.96 | 63.65 | 12,568,456,000 | `strip_var` | `postgres` |
| 11 | 2.86 | 66.51 | 12,143,846,000 | `sub_abs` | `postgres` |
| 12 | 2.25 | 68.76 | 9,553,725,000 | `do_numeric_accum` | `postgres` |
| 13 | 1.99 | 70.75 | 8,449,739,000 | `bpchareq` | `postgres` |
| 14 | 1.79 | 72.54 | 7,600,519,000 | `palloc` | `postgres` |
| 15 | 1.69 | 74.23 | 7,175,909,000 | `add_abs` | `postgres` |
| 16 | 1.62 | 75.85 | 6,878,682,000 | `lookup_hash_entries` | `postgres` |
| 17 | 1.52 | 77.37 | 6,454,072,000 | `LookupTupleHashEntry` | `postgres` |
| 18 | 1.50 | 78.87 | 6,369,150,000 | `numeric_avg_accum` | `postgres` |
| 19 | 1.39 | 80.26 | 5,902,079,000 | `tts_minimal_getsomeattrs` | `postgres` |
| 20 | 1.37 | 81.63 | 5,817,157,000 | `numeric_mul_safe` | `postgres` |

(21~24위: `__memmove_evex_unaligned_erms` 1.34 %, `hashbpchar` 1.29 %,
`__memcmp_evex_movbe` 1.16 %, `pg_newlocale_from_collation` 1.11 %.
전체 100개 심볼, 누적 99.9 %. top 30 누적 92.1 %.)

## 주 산출물 — 기능 단계별 분해와 격차 기여

총 격차 = 1,278,530,000,000 − 424,610,000,000 = **853,920,000,000 instructions**
(비 **3.011x**; (B)의 행당 3.006x와 동일).

| 기능 단계 | CUBRID | PG | 비 | 절대 격차 | **격차 기여** |
|---|---|---|---|---|---|
| **식 평가/튜플 구성** | 299,687,432,000 (23.44 %) | 53,840,548,000 (12.68 %) | **5.57x** | +245,846,884,000 | **28.8 %** |
| **값/도메인 변환** | 195,615,090,000 (15.30 %) | **0** (0 %) | **∞** | +195,615,090,000 | **22.9 %** |
| **수치 연산 (DECIMAL/NUMERIC)** | 319,248,941,000 (24.97 %) | 180,162,023,000 (**42.43 %**) | **1.77x** | +139,086,918,000 | **16.3 %** |
| 집계·해시 | 125,295,940,000 (9.80 %) | 27,642,111,000 (6.51 %) | 4.53x | +97,653,829,000 | 11.4 % |
| 스캔/레코드 디코드 | 144,473,890,000 (11.30 %) | 63,691,500,000 (15.00 %) | 2.27x | +80,782,390,000 | 9.5 % |
| 미분류 | 47,049,904,000 (3.68 %) | 1,698,440,000 (0.40 %) | 27.70x | +45,351,464,000 | 5.3 % |
| 술어 평가 | 54,337,525,000 (4.25 %) | 14,054,591,000 (3.31 %) | 3.87x | +40,282,934,000 | 4.7 % |
| TLS/런타임 | 14,958,801,000 (1.17 %) | 0 | ∞ | +14,958,801,000 | 1.8 % |
| libc 메모리이동 | 16,876,596,000 (1.32 %) | 11,974,002,000 (2.82 %) | 1.41x | +4,902,594,000 | 0.6 % |
| 버퍼·래치 | 2,173,501,000 (0.17 %) | 806,759,000 (0.19 %) | 2.69x | +1,366,742,000 | 0.2 % |
| **정렬** | **0** | **0** | — | 0 | **0.0 %** |
| **메모리 할당/해제** | 57,405,997,000 (4.49 %) | 70,272,955,000 (**16.55 %**) | **0.82x** | **−12,866,958,000** | **−1.5 %** |
| 합계 | 1,277,123,617,000 (99.89 %) | 424,142,929,000 (99.89 %) | 3.01x | +852,980,688,000 | 99.9 % |

분류 규칙은 양쪽에 대칭으로 적용했고 스크립트는 채증에 포함된다. **미분류를 감추지
않았다** — CUBRID 3.68 %(상위: `cfree@GLIBC` 1.12 %, `memset@plt` 0.44 %,
`lang_fastcmp_byte` 0.33 %, `operator` 0.26 %), PG 0.40 %(상위:
`date_cmp_timestamp_internal` 0.07 %, `ResourceOwnerForget` 0.06 %). CUBRID의
`cfree`(1.12 %)를 메모리 할당 버킷에 넣으면 그 버킷은 4.49 % → 5.61 %가 되지만 여전히
PG(16.55 %)보다 작다.

`cycles:u` 프로파일도 같은 순위를 보인다(CUBRID `float_numeric_db_value_add` 10.33 %,
`heap_attrinfo_read_dbvalues` 6.18 % / PG `ExecInterpExpr` 14.21 %,
`init_var_from_num` 9.85 %) — IPC가 양쪽 동일하므로(2.339 vs 2.357) 예상된 결과다.

## 증거 기반 원인 후보 3개

**후보 1 — 값마다 도메인 디스패치를 수행하는 인터프리터형 식 평가 경로.**
근거 숫자: 기능 단계 표의 "식 평가/튜플 구성" **5.57x, 격차 기여 28.8 %**
(CUBRID 299.7 G vs PG 53.8 G). 심볼 근거: CUBRID는 `fetch_peek_arith` 4.36 %,
`qdata_add_dbval` 5.00 %, `fetch_val_list` 2.31 %, `fetch_peek_dbval_slow` 1.89 %,
`qdata_generate_tuple_desc_for_valptr_list` 2.42 %로 **여러 함수에 분산**돼 있고,
PG는 `ExecInterpExpr` **단일 함수 12.68 %**로 처리한다. 같은 4개 SUM/3개 AVG 식을
평가하는데 CUBRID가 5.57배의 명령을 쓴다.

**후보 2 — PG에 대응물이 없는 DB_VALUE 도메인·수명 관리 계층.**
근거 숫자: "값/도메인 변환" 버킷이 CUBRID **195.6 G(15.30 %)** vs PG **0**,
격차 기여 **22.9 %**. 심볼 근거: `tp_value_cast_internal` 4.24 %,
`pr_clear_value` 3.38 %, `db_value_domain_init` 2.25 %, `pr_type_from_id` 2.03 %,
`pr_value_mem_size` 1.64 %. PG의 top 100 심볼 어디에도 이에 대응하는 항목이 없다 —
`ExecInterpExpr`는 컴파일 시점에 타입이 고정된 Datum을 다루므로 값마다 도메인을
조회·초기화·해제하는 작업이 존재하지 않는다. 후보 1과 같은 뿌리(값 단위 인터프리테이션)의
다른 측면이지만 **심볼 집합이 겹치지 않아 별개로 계량된다.**

**후보 3 — 집계 경로의 값 단위 누산.**
근거 숫자: "집계·해시" **4.53x, 격차 기여 11.4 %**(CUBRID 125.3 G vs PG 27.6 G).
심볼 근거: CUBRID `qdata_evaluate_aggregate_list` 3.97 %,
`qexec_hash_gby_agg_tuple` 2.27 %, `qdata_aggregate_value_to_accumulator` 1.53 %,
`qdata_add_numeric_to_dbval` 1.35 % ↔ PG `do_numeric_accum` 2.25 %,
`accum_sum_add` 4.55 %(수치 버킷), `numeric_avg_accum` 1.50 %,
`lookup_hash_entries` 1.62 %, `LookupTupleHashEntry` 1.52 %. 4행 그룹만 만드는데
CUBRID의 집계 버킷이 4.53배다.

### 후보에서 **배제**되는 것 (근거와 함께)

* **DECIMAL 산술 자체가 주 동인이라는 설명은 성립하지 않는다.** "수치 연산" 버킷 비가
  **1.77x**로 전체 평균 **3.011x**보다 낮고, PG 쪽 비중이 오히려 훨씬 크다
  (42.43 % vs 24.97 %). 절대 격차 기여는 16.3 %로 3위다.
* **메모리 할당 오버헤드는 CUBRID 쪽 문제가 아니다.** 0.82x로 CUBRID가 적고 격차 기여가
  **−1.5 %**다(PG `AllocSetAlloc` 8.47 % + `AllocSetFree` 4.70 % + `palloc` 1.79 %
  = 15.0 % vs CUBRID `malloc` 2.60 % + `_int_free` 1.89 % = 4.5 %).
* **I/O·버퍼·래치 경합은 이 질의에서 요인이 아니다.** 버퍼·래치가 양쪽 0.2 % 미만이고,
  물리 디스크 read는 (A)에서 양쪽 0이었다.
* **정렬은 요인이 아니다.** 양쪽 0 % — Q1은 4행만 정렬한다.
* **D 항목의 바이트 1.214x가 이 격차를 설명하지 못한다.** 스캔/레코드 디코드 버킷이
  2.27x이고 격차 기여 9.5 %로, 3.011x의 대부분을 설명하지 않는다.

## 채증 색인

| 산출물 | 경로 |
|---|---|
| perf 데이터 (4개: 양쪽 × 2이벤트) | `.git_ignored_dir/g1-prof/raw/{cubrid,pg}-{instructions,cycles}.data` |
| SUT pid 집합 / 사전 pid 집합 | `.../raw/*.sutpids`, `*.prepids` |
| 전체 심볼 목록 (183 / 100개) | `.../raw/{cubrid,pg}-instructions.symbols` |
| 질의 출력 (질의 구간 시간 포함) | `.../raw/*.qout` |
| 수집 하네스 | `.../scratch/run-prof.sh` |
| 분류 스크립트 | `.../scratch/classify.py` |
| 오버헤드 통제 실험 | `.../raw/p10-*.data`, `p100-*.data` |

## 상태

| 항목 | 상태 |
|---|---|
| 데이터 | 무변경 (재적재 0건) |
| CUBRID conf | 무변경 (`parallelism=6`, 재기동 없음) |
| PG | 세션 GUC만 (`max_parallel_workers_per_gather=5`), 클러스터 기본값 6 유지 |
| cpuset | SUT `0-15`(클라이언트 공유), perf `20-23` |
| `~/CUBRID` | 불변 |
