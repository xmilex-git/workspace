# PR 8196 리뷰 항목 3 — cpp-perf-rules 기반 성능 리뷰

2번 세션 작성, 2026-10-21. 대상: CUBRID/cubrid#8196 (CBRD-27361), head `908bdc5af`, merge-base `c966fabc6`.

## TL;DR

배치가 맡는 필터·집계 스캔은 PR 주장대로 빠릅니다. 직렬 기준 명령어는 develop 의 0.29~0.45배, 벽시계는 0.39~0.42배입니다.
하지만 두 가지는 머지 전에 고쳐야 합니다.

- **런타임 필터 경합**: 해시 조인 런타임 필터가 행마다 공유 카운터를 원자 증가시킵니다. 이 때문에 필터가 붙는 병렬 질의가 develop 보다 1.4~1.9배 느립니다(Blocking 1).
- **배치를 못 쓰는 경로의 회귀**: develop 대비 명령어를 4~10% 더 쓰고, 가장 나쁜 경우(ALTER 를 거친 테이블)는 벽시계로 14~23% 느립니다(Blocking 2·3).
  - 해당 경로: ALTER 를 거친 테이블, 조건 없는 `COUNT(*)`, 배치가 거절한 해시 GROUP BY, 일반 행 경로.
  - 원인: 포기 없는 페이지 재시도, 행마다 부르는 빈 함수 호출, 인라이닝이 풀린 컬럼 디코드, GROUP BY 키 이중 해시.

## 검토 방법

- 규칙집: `cpp-perf-rules`(CHECKLIST, ANTIPATTERNS, BR/ALIAS/MEM/COH/PAR/CC/MEAS). 보고서의 규칙 ID 는 이 규칙집 기준입니다.
- 정적 검토
  - head worktree 의 소스를 읽었습니다.
  - CI release 바이너리를 `objdump`/`nm` 으로 확인했습니다.
  - 핫 심볼 레이아웃 게이트(규칙집 부록 E)를 돌렸습니다.
  - CI 와 같은 GCC 8.5.0 으로 `heap_file.c` 한 파일만 IPA 인라인 덤프를 떴습니다.
- 실행 측정
  - Sonnet 워커 3개(레인 A·B·C)가 맡았고, 리드는 smoke 만 직접 했습니다.
  - 빌드는 모두 CI 의 **release** tarball 입니다(head `11.5.0.2736-908bdc5`, base `11.5.0.2703-c966fab`). optdebug 는 쓰지 않았습니다.
- 데이터: TPC-H SF10 load 파일의 앞부분입니다(lineitem 200만 행 등). PR 표의 SF10 전체가 아니므로, 절대 시간은 PR 표와 비교하지 않습니다.
- 지표
  - 이 호스트는 6개 세션이 같이 쓰고 있어 부하(loadavg 6~108)가 큽니다.
  - 그래서 판정은 `instructions:u` 정확 계수(SA, (R4−R1)/3, 3회 중앙값, 반복 간 편차 0.05% 이하)를 1차 지표로 합니다.
  - 그다음 perf 프로파일·c2c 로 원인을 짚습니다. 벽시계는 head/base 를 교대로 재고, 5% 미만 차이는 잡음으로 봅니다.

## Blocking

### 1. 런타임 필터의 행당 원자 카운터가 병렬 워커 사이에서 캐시 라인을 다툼

규칙: PAR-01, COH-01/COH-04, GLOB-09, MEM-03 (A03, A27)

- **위치**
  - `src/query/query_hash_join.c:4987`, `:5004`(`hjoin_rtf_pass` 안의 `__atomic_add_fetch`).
  - 구조체는 `:4687-4697` 입니다. `rows`·`dropped` 가 읽기 전용 필드 `slots`·`used`·`mask`·`is_date` 와 같은 56바이트 안에 있습니다.
  - 호출: 직렬은 `query_executor.c:12821`, 병렬은 `px_scan_task.cpp:967`.
  - `hjoin_rtf_bind_clone()` 이 모든 워커에 **같은 구조체 포인터**를 줍니다.
- **무엇**: probe 쪽 가장 바깥 스캔의 행마다 `rows` 를, 떨어뜨린 행마다 `dropped` 를 원자 증가시킵니다. 이 두 값은 trace 의 `RUNTIME FILTER (keys, rows, dropped)` 표시에만 쓰입니다.
- **기계어**: release `libcubrid.so.11.5` 의 `hjoin_rtf_pass` 에서 확인했습니다.
  - 매 호출 `lock addq $0x1,0x28(%rdi)`.
  - 드롭마다 `lock addq $0x1,0x30(%rdi)`.
  - 같은 줄의 `0x20(%rdi)`(is_date)·`0x10`(mask)·`0x8`(used)·`0x0`(slots)를 매 호출 읽습니다.
- **측정**(레인 B; lineitem 200만 행 probe, 워커 6개, release)
  - **CPU 점유**: `hjoin_rtf_pass` 자기 시간이 전체 cycles 의 19.3%(RNON: 모든 행이 매치), 73.0%(RSEL: 99% 드롭), 71.8%(NEST: 기본 설정, IN 서브쿼리 안의 해시 조인)입니다.
  - **함수 안 분포**: RNON 은 샘플의 82% 가 공유 줄 접근(is_date 읽기, rows 원자 증가)에 있고, 실제 해시 탐색은 17% 입니다.
  - **perf c2c**: 전체 load HITM 중 이 함수 몫이 RNON 1336/1636(81.7%), RSEL 2431/2576(94.4%)입니다.
    - RNON 의 핫 오프셋은 0x20 읽기 946, 0x28 원자 증가 312 HITM 입니다.
    - 원격 소켓 HITM 의 평균 지연은 450~1221 cycles 입니다.
    - base 대조군(필터 없음)의 load HITM 은 291/245 이고, 집중된 줄이 없습니다.
  - **벽시계**: C/S, 병렬입니다. RSEL·RNON 은 부하가 내려간 5라운드, NEST 는 대조 실험 5라운드의 중앙값입니다.

    | 질의 | head | base | head/base |
    |---|---|---|---|
    | RSEL | 406 ms | 215 ms | 1.89 |
    | RNON | 452 ms | 312 ms | 1.45 |
    | NEST | 437 ms | 276 ms | 1.58 |

    같은 head 설치에서 필터를 켠 경우와 안 켠 경우(힌트로 전환)는 RSEL 338 대 138 ms(2.4배), RNON 403 대 293 ms(1.38배)입니다.
  - **직렬**: RSEL 은 이득입니다(명령어 0.47배, 벽시계 0.50배). 문제는 병렬에서만 생깁니다.
- **수정**(가장 작은 것)
  - `hjoin_rtf_pass` 에서 원자 연산 두 줄을 뺍니다.
  - 그 대신 호출자가 행 수를 지역 변수(직렬: 블록 지역, 병렬: `task` 멤버)에 세고, 끝날 때 한 번 `hj->rtf_rows` 에 더합니다(워커당 원자 연산 1회).
  - 그러면 구조체는 실행 중 읽기 전용이 되고(COH-05), is_date 줄의 HITM 도 같이 사라집니다.
  - 확인 방법: 같은 질의를 perf c2c 로 다시 재서 `hjoin_rtf_pass` 의 HITM 이 거의 0 인지 봅니다.
- **건너뛰면**: 기본 설정에서도 IN/EXISTS 서브쿼리 안의 해시 조인(NEST 모양)이 develop 보다 1.6배 느려집니다. 워커가 늘수록 더 나빠집니다.

### 2. 배치가 매 페이지 폴백해도 포기하지 않음 — ALTER 를 거친 테이블과 조건 없는 COUNT(*)

규칙: 우선순위 절차 1단계(일 자체를 없애기), PAR-06 의 폴백 조건(배치판), CC-05

- **위치**
  - 폴백 경로: 직렬 `query_executor.c:12512-12580`(`qexec_batch_scan_chain`), 필터 반복자 `scan_manager.c:8607-8700`, 병렬 `px_scan_task.cpp:877-922`.
  - 세 곳 모두 페이지마다 청크를 다시 모읍니다. 폴백 횟수는 trace 용 `pages_fallback`(`expr_batch.c:4331-4338`)에만 쌓이고, 배치를 끄는 조건은 없습니다.
- **2a. ALTER 이후 테이블**
  - `ALTER TABLE ... ADD COLUMN` 뒤 기존 레코드는 예전 대표(representation)를 유지합니다.
  - 그러면 `eb_layout_rows()`(`expr_batch.c:3152-3156`)가 청크마다 "a record of another representation" 으로 폴백합니다.
  - 그 결과 페이지마다 가시성 판정을 한 번 더 하고, 그다음 행 경로가 그 페이지를 처음부터 다시 걷습니다.
  - 측정(레인 A, li_alt = lineitem 200만 행 복사 후 `ADD COLUMN`):
    - trace: `batch pages: 3 (row path: 23875, last: a record of another representation)`.
    - 명령어: develop 대비 ALT01 1.101배, ALTQ6 1.074배.
    - 벽시계: SA 1.16~1.21배 / 1.16~1.23배, 매번 새 서버를 띄운 C/S 1.15배 / 1.14배.
    - 프로파일: `heap_page_collect_visible` 포함 11.5%, `or_mvcc_get_repid_and_flags` 7.04%(base 1.15%).
- **2b. 조건 없는 `COUNT(*)`**
  - `plan->repid` 는 컬럼이나 GROUP BY 키를 디코드할 때만 설정됩니다(`expr_batch.c:692`, `:2379`).
  - 그런데 필터 없는 집계 전용 계획은 컬럼이 0개여도 받아들여집니다(`:2631-2640`). 이때 `repid` 가 0 으로 남아, 모든 청크가 대표 검사에서 떨어집니다.
  - smoke(리드, head release, 30만 행):
    - 단일 `CREATE TABLE` 로 만든 테이블에서도 `SELECT COUNT(*) FROM t_one` 이 `batch pages: 1 (row path: 901, last: a record of another representation)` 입니다.
    - 같은 테이블에 `WHERE a > -1` 이나 `SUM(c)` 를 주면 `batch pages: 902 (row path: 0)` 입니다.
  - 측정(레인 C, lineitem 200만 행): 명령어 행당 1065.8 대 976.6(+9.1%). 벽시계는 smoke 수준에서 잡음 범위였습니다.
- **수정**
  - (1) 컬럼도 키도 없는 계획은 대표 검사를 건너뜁니다. 더 나은 방법은 가시 행 수만 세어 바로 집계하는 것인데, 그러면 `COUNT(*)` 이 이득으로 바뀝니다.
  - (2) 같은 사유의 폴백이 연속 N 페이지 나오면 그 스캔의 배치를 끕니다(`batch_state = 2`). 대표가 다른 레코드는 한 페이지 걸러 나타나지 않기 때문입니다.
- **건너뛰면**: 운영에서 흔한 "컬럼을 추가한 테이블"의 필터 스캔이 develop 보다 15~20% 느립니다. 조건 없는 `COUNT(*)` 도 일만 늘어납니다.

### 3. 배치가 맡지 않는 행 경로에 PR 이 더한 비용

배치가 거절한 스캔이나 폴백한 페이지도 이 비용을 냅니다. 세 가지가 겹치며, 레인 A 의 ROWGBY 에서 합쳐 측정했습니다.

- ROWGBY 는 배치가 거절한 해시 GROUP BY 입니다(`WHERE l_comment LIKE '%a_e%' GROUP BY l_shipmode`).
- develop 대비 명령어 1.059배, cycles 1.175배, SA 벽시계 1.16~1.19배(부하 낮을 때), C/S 1.04~1.06배였습니다.

**3a. 해석형 필터가 행마다 빈 함수를 부름**

규칙: CC-05, A60

- **위치**: `src/query/query_evaluator.c:3561-3567`.
- **무엇**
  - base 는 `state == 1 && !signature_ok` 와 `state == 0` 을 인라인으로 검사했습니다. 그래서 컴파일러가 거절한 필터(`scan_prog_state == 2`, trace 의 "interpreted (not covered)")는 호출 없이 통과했습니다.
  - head 는 `state != 1 || ...` 이 참이면 `eval_data_filter_ensure_prog()` 를 부릅니다. 그 결과 해석형 필터의 **모든 행**에서 아무 일도 하지 않는 함수 호출이 하나 생깁니다.
  - 해석형 필터는 드물지 않습니다. 레인 A 의 F01(`l_quantity < 24`)·F06·F11·GHI 가 모두 "interpreted" 였습니다.
- **측정**: `eval_data_filter_ensure_prog` 자기 시간 +193 Mcycles(ALT01 head 의 3.5%), ROWGBY +44 Mcycles.
- **수정**(한 줄): 조건을 `state == 0 || (state == 1 && !expr_scan_pred_signature_ok (...))` 로 바꿉니다.

**3b. `heap_attrvalue_read` 인라이닝이 풀림**

규칙: CC-08 규칙 2, CC-05

- **위치**: `src/query/heap_attrinfo.h:131-138`, `src/storage/heap_file.c:10933-10940`. PR 이 `heap_rec_layout_init()` 를 헤더의 `heap_rec_layout_init_repr()` 로 재구성한 부분입니다.
- **무엇**
  - 이 재구성으로 `heap_attrvalue_read` 의 추정 크기가 81→85 로 늘었습니다.
  - 그러자 GCC 8.5.0 의 판정이 뒤집혔습니다. base 덤프는 "Inlined ... big_speedup" 이고, head 덤프는 `heap_attrinfo_read_dbvalues` 와 `heap_attrinfo_read_dbvalues_without_oid` 두 호출 지점에 대해 "--param max-inline-insns-auto limit reached" 입니다.
  - 그 결과 release 바이너리에서 `heap_attrinfo_read_dbvalues` 크기가 0x83c → 0x1f3 이 됐고, 컬럼마다 out-of-line 호출이 생겼습니다.
  - 로컬에서 같은 컴파일러로 재현했습니다(`scratch/pr8196-item3/inline/`).
- **영향 범위**: `heap_attrinfo_read_dbvalues` 를 행마다 부르는 모든 곳입니다.
  - 직렬 힙 스캔(`scan_manager.c:6521`), 인덱스 스캔의 힙 조회(`:7359`), 병렬 힙 스캔(`px_scan_slot_iterator.cpp:155`), 병렬 인덱스 스캔.
  - 인덱스 생성(`btree_load.c:6001`, `:6297`), 통계 수집, 배치 투영(`scan_manager.c:8507`).
- **측정**(레인 C, CA3 = lineitem 11컬럼 MAX, 배치 거절 확인)
  - 명령어 행당 8370 대 8042(+4.08%). 그중 디코드가 +211(컬럼당 +19)입니다.
  - uprobe 로 `heap_attrvalue_read` 진입을 세면 정확히 행당 11회입니다.
  - 벽시계 +2.4%(5세션 중 4회 느림)로, 잡음 기준 아래지만 부호가 일관됩니다.
- **수정**
  - 가장 작은 방법은 `heap_file.c` 의 `heap_rec_layout_init()` 를 원래 네 줄 본문으로 되돌리는 것입니다. `heap_rec_layout_init_repr()` 는 expr_batch 만 쓰면 됩니다.
  - 아니면 두 호출자를 위한 always-inline 래퍼를 둡니다(GCC/Clang 전용 속성이고, 리눅스 전용 빌드라 대안은 필요 없습니다).
  - 어느 쪽이든 수정 뒤 `nm -S` 로 `heap_attrinfo_read_dbvalues` 크기가 0x83c 대로 돌아왔는지 확인합니다.
  - 인라이닝 판단은 이렇게 경계에서 쉽게 뒤집히므로, 핫 함수 크기 확인을 PR 체크에 두는 것도 권합니다(CC-09).

**3c. 해시 GROUP BY 가 행마다 키를 두 번 해시함**

규칙: 우선순위 1단계(중복 작업 제거), DS-03, A60

- **위치**: `src/query/query_executor.c:4772`. `qdata_key_sketch_add()`(`query_aggregate.cpp:3678`)가 `qdata_hash_agg_hkey()` 로 키를 해시하고, 바로 다음 `:4775` 의 `mht_get()` 이 같은 키를 다시 해시합니다.
- **무엇**: 이 HLL 스케치는 표가 넘쳤을 때 잔여분 병합에만 쓰입니다. 그런데 넘치지 않는 질의도 매 행 비용을 냅니다.
- **측정**(레인 A): 스케치 포함 시간이 GHI 3.62%, ROWGBY 4.42% 입니다. ROWGBY 는 문자열 키라 `lang_mht2str_byte` +66 Mcycles, `mht_get_hash_number` +125 Mcycles 가 더해집니다.
- **수정**: 해시를 한 번만 계산해 두 곳에서 같이 씁니다(해시를 인자로 받는 `mht_get` 변형). 또는 표가 처음 넘칠 때 표의 키로 스케치를 한 번 채우고, 그 뒤 행부터만 스케치에 넣습니다.

**3 전체를 건너뛰면**: PR 이 손대지 않은 듯 보이는 행 경로 질의(인덱스 조회, 조인, 인덱스 생성 포함)가 develop 보다 수 % 느려집니다. PR 성능표의 직렬 Q3·Q7·Q9·Q11 이 1.02~1.06배로 느린 원인의 후보이기도 합니다(아래 7).

## Non-blocking (측정한 상한이 있는 개선 기회)

### 4. NUMERIC SUM 을 값마다 out-of-line 으로 누산

규칙: FP-07, CC-05 (A65)

- **위치**: `src/query/expr_batch.c:4212-4223`(`expr_batch_agg_sum_rest` → `numeric_sum_acc_add_expr_val` → `numeric_sum_acc_add_core`, 값마다).
- **측정**(레인 A, Q1 head)
  - `numeric_sum_acc_add_core` 17.45%, `numeric_sum_acc_add_expr_val` 3.73%, `expr_batch_agg_sum_rest` 7.63% 입니다. 합쳐서 Q1 cycles 의 28.8% 입니다.
- **제안**
  - 청크 안에서는 같은 scale 끼리 int128 지역 합으로 모읍니다. 0 인 값(곱에 0 이 있으면 scale 0)은 더하지 않아도 됩니다.
  - 오버플로는 `__builtin_add_overflow` 로 잡고 기존처럼 행 경로로 폴백하게 둡니다.
  - 그러면 누산기 호출은 청크당 한 번입니다. 누산 관련 시간이 Q1 cycles 의 28.8% 이므로 줄일 수 있는 상한이 그만큼이고, 실제 이득은 그보다 작습니다.

### 5. 가리킨 NUMERIC 셀을 행마다 PLT 를 거쳐 디코드

규칙: CC-05, CLOW-13

- **위치**: `src/query/expr_batch.c:498`(`eb_cell_num` → `numeric_agg_expr_from_disk@plt`). 이 함수는 바이트마다 uint128 시프트를 합니다(`numeric_opfunc.c` 의 PR 신규 함수).
- **측정**
  - F01: `numeric_agg_expr_from_disk` 자기 10.16% 입니다. `eb_raw_kid` 샘플의 약 50% 도 이 호출 지점과 반환 직후 load 에 있습니다.
  - Q1: 7.4% 입니다.
- **제안**: expr_batch.c 안에 크기 8바이트 이하용 `static inline` 빠른 경로를 둡니다(8바이트 big-endian load + bswap). 나머지는 기존 함수로 보냅니다.

### 6. 가시성 패스가 레코드 헤더를 두 번 해석하고, 첫 접근이 가장 비쌈

규칙: 우선순위 1단계, CC-05, MEM-06(측정 먼저)

- **위치**
  - `src/storage/heap_file.c:8265`: 레코드마다 `or_mvcc_get_header@plt` → `or_mvcc_get_repid_and_flags`.
  - `src/query/expr_batch.c:3152-3157`: 행마다 `OR_HEADER_SIZE` 두 번. 이 매크로는 함수 호출 `or_header_size@plt` 입니다(`object_representation.h:534`).
- **측정**
  - F01/Q6 head 의 최대 심볼이 `or_mvcc_get_repid_and_flags` 로, 각각 19.66%/19.53% 입니다.
  - `or_header_size` 는 3.91%, PLT 가 0.43% 입니다.
- **제안**
  - 가시성 판정 때 이미 읽은 헤더 크기를 `HEAP_PAGE_ROW` 에 남깁니다. 그러면 `eb_layout_rows` 의 행당 호출 두 번이 사라집니다.
  - 19.7% 는 계산보다 레코드 줄을 처음 만질 때의 지연일 가능성이 큽니다. 다음 레코드 헤더를 prefetch 하는 실험을 권하지만, perf mem 으로 먼저 확인해야 합니다(이번에는 확인하지 않았습니다).

### 7. 런타임 필터가 효과 없을 때도 켜져 있고, 표가 두 배열로 나뉨

규칙: MEM-04, PAR-06(폴백 조건)

- **위치**
  - `src/query/query_hash_join.c:4876`: build 쪽이 2^20 행 이하면 무조건 만듭니다.
  - `:4916-4917`: `slots`(INT64)와 `used`(uchar)가 따로 있어, 탐색마다 서로 다른 무작위 줄 두 개를 읽습니다.
- **측정**
  - 레인 B RNON 직렬(100,000 키, dropped 0): `hjoin_rtf_pass` 가 cycles 의 9.24% 입니다. 그 샘플의 86% 가 `used[]`(256KB)·`slots[]`(2MB) load 에 있습니다. head 명령어는 +2.4% 입니다.
  - SF10 TPC-H Q9(레인 B, head, 직렬): 필터가 두 번 만들어졌는데 nation(keys 25, rows 25, dropped 0)과 supplier(keys 98827, rows 100000, dropped 1173)로 효과가 거의 없습니다. Q7 은 해시 조인이 없습니다.
- **제안**
  - 처음 N 행을 보고 dropped/rows 가 낮으면 필터를 끕니다.
  - 표는 키와 사용 표시를 한 배열에 둡니다(빈 칸 sentinel). 키가 많으면 bitmap/bloom 도 고려합니다.

### 8. 실행 중 고정인 상수를 청크마다 다시 계산

규칙: BR-04 확장

- **위치**: `src/query/expr_batch.c:3992`(청크마다 `eb_load_leaf_constants`) → `eb_num_leaf_constant`(`:3042-3139`).
- **무엇**: NUMERIC 리프마다 10^38 을 38번 곱해서 만들고 int128 나눗셈을 합니다.
- **측정**: `__divti3` 가 F01 0.54%, Q6 1.59% 입니다.
- **제안**: 실행당 한 번 계산합니다(상수 DB_VALUE 와 실행 stamp 가 같으면 재사용).

### 9. DOUBLE/FLOAT 셀마다 `ntohd@plt` 호출

규칙: CC-05

- **위치**: `src/query/expr_batch.c:480`(`eb_cell_fixed` 의 `OR_GET_DOUBLE`, `eb_extract` 에 inline 됨).
- **무엇**: release 기계어에서 `eb_extract` 가 DOUBLE 셀마다 `callq ntohd@plt` 를 합니다.
- TPC-H 에는 DOUBLE 컬럼이 없어 측정하지 않았습니다. 낮은 우선순위입니다.

## 측정 방법에 관한 지적

### 10. PR 성능표가 head 바이너리를 잰 것이 아니고, 레이아웃 교란을 배제하지 않음

규칙: MEAS-04/07/08, A74, A80

- PR 본문이 밝힌 대로 수치는 CI 대응 수정과 develop 머지 전의 빌드에서 잰 것입니다. 분산(stddev/MAD)도 없습니다.
- 레이아웃 게이트(부록 E, base → head release):
  - 행 경로 핫 심볼 19개가 모두 이동했고, 그중 9개는 `%32` 위상이 바뀌었습니다(`heap_next_1page`, `spage_next_record`, `fetch_val_list`, `mht_get`, `qfile_scan_list_next` 등).
  - 크기가 처음 갈라진 곳은 `qdata_evaluate_function.cold.129`(−3 B)입니다.
  - 여기에 3b 처럼 실제 코드 변화(인라이닝)도 섞여 있습니다.
- 따라서 직렬 Q3 1.03, Q7 1.06, Q9 1.06 은 잡음이라고도, PR 탓이라고도 아직 말할 수 없습니다. Blocking 2·3 을 고친 뒤 게이트와 함께 다시 재고, 중앙값 옆에 분산을 적어 달라고 요청합니다.

### 11. 배치가 행 경로로 넘긴 페이지의 시간이 trace 에 이중 집계됨

규칙: MEAS-06

- smoke(리드): head 에서 조건 없는 `COUNT(*)` 의 SCAN `heap time` 이 60~90 ms 였습니다. 이는 같은 실행의 `SELECT (time)` 37~56 ms 보다 큽니다.
- base 는 SCAN 28~30 ms 가 SELECT 44~45 ms 안에 들어갑니다.
- `qexec_batch_scan()` 이 체인 전체 시간을 더하고, 그 안의 행 경로도 행마다 시간을 더하는 것으로 보입니다.
- trace 로 성능을 읽을 때 오판 위험이 있습니다. 정합성 문제라 항목 1 쪽에도 알립니다.

## 측정 후 빼거나 작다고 판정한 것

- **`eb_raw_kid`·`eb_extract` 의 행당 leaf 필드 재로드와 rel_op 간접 점프**(BR-04/A59, BR-06/A61, ALIAS-02)
  - release `libcubrid` 기계어에서는 실제로 보입니다. 행마다 `leaf->k_null`·`etype`·`rel_op`·`k.d` 를 다시 읽고 jump table 로 갑니다.
  - 하지만 레인 A annotate(`libcubridsa`)에서 leaf 필드 load 는 함수 샘플의 1.5%(F01)/3.8%(Q6), 간접 점프는 0~1% 였습니다. 질의 전체로는 1% 미만입니다.
  - 특수화 커널로 바꿀 가치는 지금은 없습니다.
- **조인 아래 필터 반복자의 레코드 복사**(`scan_manager.c:8565`)
  - 행당 약 68 명령어(0.6%)입니다.
  - 거의 모든 행을 남기는 필터(CN)에서도 head 가 명령어 2.4%·벽시계 5.5% 적게 씁니다. 선택적 필터(CS)는 56%·39% 적게 씁니다.
- **ALLOC-08**: 해시 병합 아레나와 워커 reader 는 `malloc`/`calloc`(전역 힙)입니다. 워커가 만든 DB_VALUE 복제는 같은 워커가 지웁니다(`qexec_gby_px_worker`). 문제를 찾지 못했습니다(정적 확인).
- **PAR-14**: 집계·투영·해시 GROUP BY·rows 노드·런타임 필터가 직렬과 px 양쪽에 다 들어가 있습니다.

## Questions

1. 레인 A 의 GHI·GPART·GUNIQ(`WHERE l_quantity > 0` 이 있는 GROUP BY 를 파생 테이블로 감쌈)는 trace 에 `batch pages: 23886` 이 찍힙니다. 그런데 `qexec_batch_gby_consume` 은 한 번도 돌지 않았고, 행 경로 `qexec_hash_gby_agg_tuple` 이 처리했습니다. 이 모양을 배치 GROUP BY 노드가 맡지 않는 것이 의도인가요? 그래서 고카디널리티에서 키 캐시(`QEXEC_GBY_CACHE_SIZE` 1024, 절반 차면 전부 비움, 항목마다 `malloc`)가 얼마나 비용을 내는지는 이번에 재지 못했습니다.
2. 런타임 필터는 `!xasl->px_executor` 일 때만 만듭니다(`query_executor.c:19631` 부근). 그래서 기본 설정의 최상위 병렬 해시 조인은 필터가 없고, 서브쿼리 안 해시 조인(NEST)은 필터가 붙습니다. 의도한 범위인가요? PR 의 Q18 수치(31.6 → 25.8 초)는 어느 모양에서 잰 것인가요?

## 실행한 검증

| 무엇 | 빌드 | 방법 | 결과 |
|---|---|---|---|
| 핫 심볼 레이아웃 게이트 | CI release head/base `libcubrid.so.11.5` | `tools/layout-gate.py`(부록 E, py3.6 호환 수정) | 19/19 이동, 9개 `%32` 변화 (`scratch/pr8196-item3/layout-gate-base-vs-head.txt`) |
| 인라이닝 원인 | head/base `heap_file.c`, GCC 8.5.0, release 플래그(SERVER_MODE) | `-fdump-ipa-inline-details` | base 인라인 / head "max-inline-insns-auto limit reached" (`scratch/pr8196-item3/inline/`) |
| 기계어 확인 | CI release head | `objdump -d -l` | `hjoin_rtf_pass` 의 `lock addq`, `eb_raw_kid`/`eb_extract` 의 재로드·jump table, `or_header_size@plt`·`numeric_agg_expr_from_disk@plt`·`ntohd@plt` |
| 레인 A | CI release head 630db4c6…/base cc470b2d… (lib sha256 a17b1104…/6c7c712c…) | SA `perf stat`(R4−R1)/3, `perf record`/`annotate`, C/S trace, 벽시계 교대 | F01·F02·F11·Q6·Q1 명령어 0.29~0.31배, F06 0.45배; ALT01/ALTQ6/ROWGBY 1.10/1.07/1.06배; 프로파일 위 인용 (`scratch/pr8196-item3/laneA-report.txt`) |
| 레인 B | 같음, parallelism 6 | `perf record -p`, `perf c2c`, SA 계수, 벽시계, SF10 Q7/Q9 trace | 위 Blocking 1·Non-blocking 7 (`laneB-report.txt`) |
| 레인 C | 같음 | SA 계수, `perf record`(instructions·cycles), uprobe 진입 횟수, 벽시계 | CA3 +4.08%, CA1 +9.1%, 필터 반복자 복사 0.6% (`laneC-report.txt`) |
| smoke(리드) | 레인 C 의 head/base release 설치, 포트 1711 | csql -C, `;plan detail` + trace | 조건 없는 `COUNT(*)` 전 페이지 폴백, trace heap time 이중 집계 (`scratch/pr8196-item3/smoke/`) |

결과 행은 모든 측정에서 head 와 base 가 같았습니다. CTP 는 이 항목에서 돌리지 않았습니다(성능 리뷰, 소스 변경 없음).
근거를 읽은 뒤 레인 DB·설치본·적재 사본은 지웠습니다. 각 레인의 `out/`·trace·보고서, release tarball, 인라인 덤프 발췌(`inline/excerpt-*.txt`)는 `scratch/pr8196-item3/` 에 남아 있습니다.

## 확인하지 못한 것

- 수정안을 적용한 빌드로 이득을 확인하지는 않았습니다(빌드 없음). Blocking 1 의 크기는 같은 head 에서 필터를 켜고 끈 대조와, 함수 점유율로만 추정했습니다.
- 고카디널리티 배치 GROUP BY 의 키 캐시 비용(Questions 1).
- ALTER 테이블의 병렬 폴백 경로, NUMA 배치 영향, ARM 같은 약한 메모리 모델(COH-10, 이번 수정안은 relaxed 카운터 제거라 해당 없음).
- 6의 "첫 접근 지연" 가설(perf mem 미실행). ROWGBY 에서 cycles 차이(+17.5%)가 명령어 차이(+5.9%)보다 큰 이유.
- SF10 전체 규모의 재측정. 레인 데이터는 SF10 의 앞 200만 행입니다.
