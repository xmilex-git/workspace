# CBRD-26396 PR #3582 성능 비교 보고서

- 측정 일시: 2026-07-15 13:23–13:25 KST
- 측정 호스트: `cubrid@192.168.6.33` (`ilhansong33`, 32 CPU)
- 대상 PR: <https://github.com/CUBRID/cubrid-testcases-private-ex/pull/3582>
- 대상 엔진 커밋: `4170e13d` → `7bb1fed5` → `f7432203`

## 1. 측정 조건

- 모두 release(`RelWithDebInfo`) 빌드로 측정했다.
- PR TC의 테이블, 5,000,000행 fixture, 인덱스, `USE_IDX ORDERED` SQL을 그대로 사용했다.
- multi-key와 single-key 각각 `warm-up 1회 → 실측 3회 → ;trace on 1회` 순서로 단일 세션 실행했다.
- trace 실행시간은 실측 3회에 포함하지 않았다.
- PR에 포함된 `11.4.5.1866-e9c17f7` baseline은 실행하지 않았다.
- `4170e13d`에서 만든 DB를 호환되는 `7bb1fed5`에서 그대로 재사용했다.
- `f7432203`은 DB 비호환 가능성을 반영하여 동일 DDL/DML로 새 DB를 생성했다.
- 서버 시작·종료·상태 확인은 `cubrid-server-ctl.sh`를 사용했다.
- 세 버전에 공통으로 `4170e13d`의 기본 `cubrid.conf`를 사용하고 `stored_procedure=no`만 추가했다.
- 요청에 따라 CoV 판정과 추가 반복은 수행하지 않았다.

SQL:

```sql
-- multi-key
SELECT /*+ USE_IDX ORDERED */ COUNT(*)
FROM a26396, b26396_multi
WHERE a26396.id = b26396_multi.id
  AND b26396_multi.name = 'math';

-- single-key
SELECT /*+ USE_IDX ORDERED */ COUNT(*)
FROM a26396, b26396_single
WHERE a26396.id = b26396_single.id
  AND b26396_single.name = 'math';
```

모든 실행의 결과는 `count(*) = 3000000`이었다.

## 2. 버전별 `cubrid_rel`

### 2.1 커밋 직전

```text
CUBRID 11.5.0 (11.5.0.2039-4170e13) (64bit release build for Linux) (Jul 15 2026 13:12:30)
```

### 2.2 커밋 직후

```text
CUBRID 11.5.0 (11.5.0.2040-7bb1fed) (64bit release build for Linux) (Jul 15 2026 13:14:34)
```

### 2.3 최신 develop

```text
CUBRID 11.5.0 (11.5.0.2328-f743220) (64bit release build for Linux) (Jul 15 2026 13:16:36)
```

## 3. 실측 결과

단위: 초. 대표값은 3회 중앙값이다.

| 쿼리 | 버전 | 1회 | 2회 | 3회 | 중앙값 |
|---|---|---:|---:|---:|---:|
| multi-key | `4170e13d` 직전 | 3.767000 | 3.194000 | 3.670999 | **3.670999** |
| multi-key | `7bb1fed5` 직후 | 4.322000 | 4.658000 | 4.853000 | **4.658000** |
| multi-key | `f7432203` develop | 0.891000 | 0.926000 | 0.954000 | **0.926000** |
| single-key | `4170e13d` 직전 | 2.431000 | 2.455000 | 2.428000 | **2.431000** |
| single-key | `7bb1fed5` 직후 | 4.150999 | 3.780000 | 3.656000 | **3.780000** |
| single-key | `f7432203` develop | 0.881000 | 0.934000 | 0.986000 | **0.934000** |

중앙값 기준 변화:

| 쿼리 | 직전 → 직후 | 직후 → develop | 직전 → develop |
|---|---:|---:|---:|
| multi-key | **26.89% 느려짐** | **80.12% 단축** | **74.78% 단축** |
| single-key | **55.49% 느려짐** | **75.29% 단축** | **61.58% 단축** |

관측 결과만 놓고 보면, PR이 대상으로 삼은 `7bb1fed5`는 바로 이전 커밋보다 빨라지지 않았다. 반대로 최신 develop은 두 쿼리 모두 크게 빨라졌다. 다만 아래 trace처럼 최신 develop은 병렬 worker 수와 gather 방식까지 달라졌으므로, 최신 develop의 차이를 `7bb1fed5` 한 커밋의 효과로 귀속할 수 없다.

## 4. 전체 trace 원문

### 4.1 `4170e13d` 직전 — multi-key

```text
=== Query Trace ===

trace on text


=== <Result of SELECT Command in Line 2> ===

              count(*)
======================
               3000000

1 row selected. (4.462000 sec) Committed. (0.000000 sec) 

=== Auto Trace ===

Trace Statistics:
  SELECT (time: 4460, fetch: 5031901, fetch_time: 2250, ioread: 0)
    SCAN (table: dba.a26396), (heap time: 1657, fetch: 5031886, ioread: 0, readrows: 5000000, rows: 5000000)
         (parallel workers: 2, heap time: 2861..2862, readrows: 2379267..2620733, rows: 2379267..2620733, gather: row by row)
      SCAN (index: dba.b26396_multi.idx_b26396_multi), (btree time: 0, fetch: 5, ioread: 0, readkeys: 5, filteredkeys: 3, rows: 0, covered: true, count_only: true)
      MEMOIZE (time: 958, hit: 4999995, miss: 5, size: 1KB, enabled: true)


=== Query Trace ===

trace off
```

### 4.2 `7bb1fed5` 직후 — multi-key

```text
=== Query Trace ===

trace on text


=== <Result of SELECT Command in Line 2> ===

              count(*)
======================
               3000000

1 row selected. (6.182000 sec) Committed. (0.000000 sec) 

=== Auto Trace ===

Trace Statistics:
  SELECT (time: 6180, fetch: 5031901, fetch_time: 3849, ioread: 0)
    SCAN (table: dba.a26396), (heap time: 3353, fetch: 5031886, ioread: 0, readrows: 5000000, rows: 5000000)
         (parallel workers: 2, heap time: 4765..4766, readrows: 2315592..2684408, rows: 2315592..2684408, gather: row by row)
      SCAN (index: dba.b26396_multi.idx_b26396_multi), (btree time: 0, fetch: 5, ioread: 0, readkeys: 5, filteredkeys: 3, rows: 0, covered: true, count_only: true)
      MEMOIZE (time: 944, hit: 4999995, miss: 5, size: 1KB, enabled: true)


=== Query Trace ===

trace off
```

### 4.3 `f7432203` develop — multi-key

```text
=== Query Trace ===

trace on text


=== <Result of SELECT Command in Line 2> ===

              count(*)
======================
               3000000

1 row selected. (1.489000 sec) Committed. (0.000000 sec) 

=== Auto Trace ===

Trace Statistics:
  SELECT (time: 1487, fetch: 3, fetch_time: 0, ioread: 0)
    SCAN (table: dba.a26396), (heap time: 1487, fetch: 0, ioread: 0, readrows: 0, rows: 0)
         (parallel workers: 4, heap time: 1387..1487, readrows: 1236096..1269504, rows: 1236096..1269504, gather: buildvalue)
      SCAN (index: dba.b26396_multi.idx_b26396_multi), (btree time: 0, fetch: 20, ioread: 0, readkeys: 20, filteredkeys: 12, rows: 12, covered: true, count_only: true)
      MEMOIZE (time: 0, hit: 4999980, miss: 20, size: 4KB, enabled: true)


=== Query Trace ===

trace off
```

### 4.4 `4170e13d` 직전 — single-key

```text
=== Query Trace ===

trace on text


=== <Result of SELECT Command in Line 2> ===

              count(*)
======================
               3000000

1 row selected. (3.201000 sec) Committed. (0.000000 sec) 

=== Auto Trace ===

Trace Statistics:
  SELECT (time: 3200, fetch: 5031902, fetch_time: 1459, ioread: 0)
    SCAN (table: dba.a26396), (heap time: 1285, fetch: 5031883, ioread: 0, readrows: 5000000, rows: 5000000)
         (parallel workers: 2, heap time: 2043..2043, readrows: 2494629..2505371, rows: 2494629..2505371, gather: row by row)
      SCAN (index: dba.b26396_single.idx_b26396_single), (btree time: 0, fetch: 9, ioread: 0, readkeys: 5, filteredkeys: 4, rows: 4) (lookup time: 0, rows: 3)
      MEMOIZE (time: 1264, hit: 4999995, miss: 5, size: 1KB, enabled: true)


=== Query Trace ===

trace off
```

### 4.5 `7bb1fed5` 직후 — single-key

```text
=== Query Trace ===

trace on text


=== <Result of SELECT Command in Line 2> ===

              count(*)
======================
               3000000

1 row selected. (5.440000 sec) Committed. (0.000000 sec) 

=== Auto Trace ===

Trace Statistics:
  SELECT (time: 5439, fetch: 5031905, fetch_time: 3609, ioread: 0)
    SCAN (table: dba.a26396), (heap time: 3564, fetch: 5031886, ioread: 0, readrows: 5000000, rows: 5000000)
         (parallel workers: 2, heap time: 4428..4428, readrows: 2190834..2809166, rows: 2190834..2809166, gather: row by row)
      SCAN (index: dba.b26396_single.idx_b26396_single), (btree time: 0, fetch: 9, ioread: 0, readkeys: 5, filteredkeys: 4, rows: 4) (lookup time: 0, rows: 3)
      MEMOIZE (time: 1169, hit: 4999995, miss: 5, size: 1KB, enabled: true)


=== Query Trace ===

trace off
```

### 4.6 `f7432203` develop — single-key

```text
=== Query Trace ===

trace on text


=== <Result of SELECT Command in Line 2> ===

              count(*)
======================
               3000000

1 row selected. (1.327000 sec) Committed. (0.000000 sec) 

=== Auto Trace ===

Trace Statistics:
  SELECT (time: 1321, fetch: 3, fetch_time: 0, ioread: 0)
    SCAN (table: dba.a26396), (heap time: 1321, fetch: 0, ioread: 0, readrows: 0, rows: 0)
         (parallel workers: 4, heap time: 1235..1320, readrows: 1236096..1269504, rows: 1236096..1269504, gather: buildvalue)
      SCAN (index: dba.b26396_single.idx_b26396_single), (btree time: 0, fetch: 24, ioread: 0, readkeys: 20, filteredkeys: 16, rows: 16) (lookup time: 0, rows: 12)
      MEMOIZE (time: 0, hit: 4999980, miss: 20, size: 4KB, enabled: true)


=== Query Trace ===

trace off
```

## 5. trace에서 확인되는 차이

### 직전과 직후

- 구조는 동일하다: outer heap scan, index scan, `MEMOIZE`, `parallel workers: 2`, `gather: row by row`.
- multi-key의 `readkeys=5`, `MEMOIZE hit=4,999,995/miss=5`도 동일하다.
- single-key의 `readkeys=5`, lookup rows, `MEMOIZE hit/miss`도 동일하다.
- 직후 trace가 느린 주된 관측값은 outer heap/fetch 시간 증가다.
  - multi-key: SELECT 4460ms → 6180ms, fetch_time 2250ms → 3849ms
  - single-key: SELECT 3200ms → 5439ms, fetch_time 1459ms → 3609ms

### 최신 develop

- `parallel workers: 2`에서 `4`로 증가했다.
- gather 방식이 `row by row`에서 `buildvalue`로 변경됐다.
- coordinator 측 outer scan `fetch/readrows/rows`가 거의 0으로 바뀌고 worker별 약 125만 행 처리로 표시된다.
- worker별 inner index probe로 인해 전체 `readkeys`와 `MEMOIZE miss`가 4배가 됐다.
- 이 실행 구조 변화가 최신 develop의 큰 시간 단축과 함께 관측된다.

## 6. 최신 develop 빌드 주의사항

`f7432203a3a496a0286204bd6e9607cea1fdcfc6`의 clean checkout은 release 빌드에 실패했다. `src/query/execute_schema.c`의 histogram 권한 오류 분기 세 곳이 존재하지 않는 `AU_ENABLE(save)`를 호출하며, 해당 커밋의 CircleCI release/debug 상태도 failure였다.

측정을 진행하기 위해 세 호출을 기존 함수의 정상 복원 매크로인 `AU_RESTORE(save)`로 바꾼 **빌드 unblock 3-line patch**를 격리된 develop worktree에만 적용했다. 이 경로는 이번 SELECT에서 실행되지 않지만, 최신 develop 결과는 엄밀히 말해 clean `f7432203` 바이너리가 아니라 **`f7432203` + 해당 compile-only patch** 결과다. 패치 원문은 다음 증거 파일에 보존했다.

- `.not_git_tracking/cbrd26396-benchmark-evidence/develop-build-unblock.patch`

## 7. 증거 위치

로컬 복사본:

- `.not_git_tracking/cbrd26396-benchmark-evidence/`

원격 원본:

- `/home/cubrid/dev/cbrd26396-bench/evidence/` on `192.168.6.33`

각 버전 디렉터리에 다음을 보존했다.

- `cubrid_rel.txt`, `metadata.txt`, `times.tsv`
- `multi|single/warmup.log`
- `multi|single/run1.log`, `run2.log`, `run3.log`
- `multi|single/trace.sql`, `trace.log`
- 서버 시작·종료·상태 로그
