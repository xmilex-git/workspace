# PR 8196 항목 2 — 힙 스캔이 페이지를 놓았다 다시 잡을 때: dealloc·vacuum, fixed/cached scan 측면

대상: CUBRID/cubrid#8196 head `908bdc5af` (develop merge-base `c966fabc6`). 1번 세션 작성, 2026-10-21.

## TL;DR

PR 이 페이지를 놓고 다시 잡는 자리(필터 반복자, px `rows` 노드, 직렬 다음 페이지)는 develop 의 dealloc 방지 규칙("이 스냅샷이 본 행이 남은 페이지만 놓는다", 다음 페이지는 `OLD_PAGE_PREVENT_DEALLOC`)을 그대로 지킵니다. vacuum 이 빈 페이지를 지우는 동시 부하에서도 head 직렬 경로는 오류 없이 정답을 냈습니다(merge-base 와 같음).
대신 fixed/cached scan 의 다른 규칙, 곧 "fixed 가 아닌 스캔은 페이지를 잡은 채 저장소에 다시 들어가는 일을 하지 않는다"를 필터 반복자가 깹니다. 조인 바깥 힙 스캔의 필터에 SP 가 있으면 PR 은 페이지를 잡은 채 SP 를 부르고, 그 SP 가 같은 페이지를 고치면 자기 latch 를 기다립니다. optdebug 에서 재현하면 서버가 abort 하고, develop 은 같은 질의를 정상 처리합니다 (Blocking 1).

## 배경: develop 이 페이지 해제를 안전하게 만드는 두 규칙

1. **dealloc 규칙.** vacuum 은 빈 페이지만 지웁니다(`vacuum_heap_page()` → `heap_remove_page_on_vacuum()`, `spage_number_of_records <= 1`). 활성 스냅샷이 본 행은 vacuum 이 지우지 못하므로, 그런 행이 남은 페이지는 놓아도 해제되지 않습니다. 그래서 cached scan 은 "보이는 행을 하나 내줄 때까지 원본 페이지를 놓지 않는다"(`heap_file.c` `heap_next_internal()`·`heap_next_1page()` 주석, CBRD-27041 b334446d6), log 탐색이 페이지를 놓는 경우도 "탐색한 레코드가 vacuum 되지 않은 버전을 잡고 있다"(CBRD-27322 b394c89f3)는 논리로 안전합니다. 체인의 다음 페이지는 지금 페이지를 잡은 채 `OLD_PAGE_PREVENT_DEALLOC` 으로 잡습니다(latch 를 기다리는 동안 vacuum 의 재확인 `pgbuf_has_prevent_dealloc()` 이 해제를 포기). 이 표지는 latch 를 얻는 순간 풀리므로(`page_buffer.c` `pgbuf_fix` fast_path 의 unregister), 놓았다 다시 잡는 페이지를 보호하는 것은 표지가 아니라 위 1번 논리입니다.
2. **hold 규칙.** fixed scan 은 페이지를 행 사이에도 잡습니다. 그래서 행 처리 중 다른 페이지를 잡거나 저장소에 다시 들어갈 수 있는 블록에서는 fixed scan 을 끕니다: 인덱스 스캔이 있는 조인, 상관 부질의(dptr), HAVING 부질의, 지연 실행 부질의(`XASL_LINK_TO_REGU_VARIABLE`), 컴파일 시 `XASL_NO_FIXED_SCAN`(serial NEXT_VALUE 등, `xasl_generation.c:9347` 주석 "A fixed (PEEK) scan deadlocks with either") — `query_executor.c` `qexec_execute_mainblock_internal()` 의 `fixed_scan_xasl` 결정. 이때 단계 0 스캔은 cached scan 이 되고, cached scan 은 행을 내준 뒤 원본 페이지를 쥐지 않습니다(`heap_next_1page()` 끝의 assert `!is_cached_scan || scan != S_SUCCESS || page_watcher.pgptr == NULL`).

## PR 의 페이지 해제·재fix 지점 점검 (dealloc 규칙)

| 지점 | 언제 놓나 | 다시 잡을 때 페이지가 살아 있는 이유 | 판정 |
|---|---|---|---|
| 필터 반복자 `scan_batch_iter_next()` `scan_manager.c:8707` | 청크에서 필터를 통과한 행이 있을 때(`n_sel > 0`), 그 레코드를 복사한 뒤 | 통과 행은 `heap_page_collect_visible()` 이 스냅샷 판정으로 모은 보이는 행 → vacuum 불가 → 페이지 비지 않음. 재fix `scan_manager.c:8645` `OLD_PAGE_PREVENT_DEALLOC` | develop 과 같은 논리 |
| px `rows` 노드 `scan_batch_rows_consume()` `scan_manager.c:8449` | cached scan 일 때만, 복사 뒤 | 같음. 다음 청크의 재fix 는 `heap_page_collect_visible()` 의 `OLD_PAGE` | 같음 |
| 직렬 다음 페이지 `scan_batch_next_page()` `scan_manager.c:8389` | 지금 페이지를 잡은 채 `heap_vpid_next()` → 다음 페이지 `OLD_PAGE_PREVENT_DEALLOC` → 이전 페이지 해제 | `heap_next_internal()` 과 같은 순서 | 같음 |
| log 탐색이 페이지를 놓은 뒤 `scan_batch_next_page()` 의 재fix `scan_manager.c:8366` | CBRD-27322 탐색이 놓음 | 탐색한 레코드(스냅샷보다 새 버전)가 vacuum 불가 | develop 행 경로와 같음 (f93d675ac 가 "빈 watcher = 힙 끝" 오인을 고침) |
| px 페이지 공급 | 변경 없음 (`px_scan_input_handler_heap.cpp`, 비트맵 + `OLD_PAGE_MAYBE_DEALLOCATED`) | — | PR 무관 |

`heap_page_collect_visible()` 은 `REC_HOME` 이 아닌 레코드와 스냅샷이 log 버전을 요구하는 레코드에서 페이지를 통째로 행 경로로 넘기므로(`S_DOESNT_FIT`), 페이지 밖을 가리키는 행을 배치가 쥐는 일도 없습니다. MVCC 가 꺼진 클래스(물리 삭제)는 배치가 받지 않습니다(`scan_batch_open_internal()` `mvcc_disabled_class`).

## 발견 사항

### Blocking

1. **필터 반복자가 페이지를 잡은 채 필터의 SP·부질의를 실행한다** (`scan_manager.c:8654-8665`, `expr_batch.c:3660-3690`)
   - **무엇인가:** 조인·부질의 아래 힙 스캔은 PR 에서 "필터 반복자"가 됩니다(`qexec_batch_filter_eligible()`, `scan_batch_open_filter()`). 반복자는 페이지를 fix 한 채 청크를 모으고(`scan_batch_collect_chunk()`), 같은 fix 아래에서 필터를 돌립니다(`expr_batch_run()`). 필터 항 중 원시 리프가 아닌 것은 "행별 항"으로 남아 `eb_filter()` 가 행마다 `expr_scan_pred_eval_kid()` 로 컴파일된 필터를 부릅니다. 이 항에는 SP 호출과 지연 실행 부질의(fetch 경로 `expr_emit_fetch()`, `expr_compile.c:5213-5220` "the fetch EXECUTES the XASL")가 들어갈 수 있습니다.
   - **문제:** develop 에서 이 스캔(인덱스 안쪽 스캔을 둔 NL 조인의 바깥)은 fixed 가 아니라 cached scan 이고, 필터는 행이 반환된 뒤 원본 페이지를 놓은 상태에서 돕니다. PR 은 같은 필터를 페이지 read latch 를 쥔 채 돌립니다. SP 가 같은 페이지의 행을 UPDATE 하면 SP 의 SQL 을 처리하는 다른 워커 스레드(같은 트랜잭션)가 그 페이지의 write latch 를 기다리고, 그 latch 는 SP 의 응답을 기다리는 바깥 스레드가 쥐고 있어 풀리지 않습니다.
   - **재현 (실행함):** 아래 SQL, `page_latch_timeout_in_msecs=20000`.
     ```sql
     create table t (id int primary key, v int, pad varchar(200));   -- 20000행, 262페이지
     create table u (k int); create index iu on u(k);                  -- t.id 와 같은 값
     create or replace function f_upd2(p int) return int as
     begin if p <= 50 then update t set v = v + 100 where id = p + 1; end if; return 1; end;
     select /*+ recompile ordered use_nl no_parallel_scan */ count(*)
       from t a, u b where a.v >= 0 and f_upd2(a.id) = 1 and b.k = a.id;
     ```
     - merge-base `c966fabc6` optdebug: 20000, 1.37초. 바깥 스캔 trace `SCAN (table: dba.t) ... readrows: 20000, rows: 20000`.
     - head `908bdc5af` optdebug: 20초 뒤 `LATCH ON PAGE(0|4673) TIMEDOUT`(-836, `page_buffer.c:7337`) → `pgbuf_timed_sleep()` assert(`page_buffer.c:7340`)로 서버 abort, csql 은 "Server no longer responding". 코어의 두 스레드:
       - 기다리는 쪽: `qexec_execute_update` → `heap_get_last_version` → `heap_prepare_object_page` → `pgbuf_ordered_fix (OLD_PAGE, WRITE)` → `pgbuf_timed_sleep`.
       - 쥔 쪽: `qexec_intprt_fnc` → `scan_batch_iter_next (scan_manager.c:8665)` → `expr_batch_run` → `eb_filter (expr_batch.c:3676)` → `expr_scan_pred_eval_kid` → `cubpl::executor::execute` → `callback_execute`(SP 의 SQL 응답 대기).
     - 같은 필터에 읽기만 하는 SP(`f_ro`)를 두면 head trace 가 `batch pages: 262 (row path: 0)` 를 찍어, 이 모양을 배치가 받는 것을 확인했습니다.
     - head `908bdc5af` release: 서버는 살지만 20초 뒤 SP 의 UPDATE 가 latch 타임아웃으로 트랜잭션 강제 abort(-72, `page_buffer.c:7355`) → 질의는 `ERROR: Stored procedure execute error: ... has been unilaterally aborted by the system`(-889)로 실패. 기본 설정(`page_latch_timeout_in_msecs` 기본값)이면 이 대기가 300초이고, 그동안 그 페이지를 읽으려는 다른 세션도 줄을 섭니다.
   - **develop 도 같은가:** 단일 테이블(`select count(*) from t a where a.v >= 0 and f_upd2(a.id) = 1`)은 develop 도 fixed scan 이 페이지를 쥔 채 `eval_data_filter()` 에서 SP 를 불러 똑같이 abort 합니다(CBRD-27591, PR #8133 닫힘; 지금은 CBRD-27579 PR #8182 가 SP 의 DML 을 제한하는 방향). 그 모양은 PR 과 무관합니다. PR 이 새로 들인 것은 develop 이 cached scan 으로 피하던 **조인 바깥 스캔** 모양입니다.
   - **고치는 방법:** fixed 가 아닌 스캔에서는 행별 항이 있는 필터를 반복자가 받지 않습니다. `scan_batch_open_internal()` 의 `cached_ok` 경로(반복자·px `rows`)에서 plan 이 만들어진 뒤 `!scan_id->fixed && plan->n_row_kids > 0` 이면 거절하는 한 줄이 가장 작습니다. 원시 리프만 있는 필터(PR 의 성능 표 F01-F15 모양)는 그대로 배치에 남습니다. 행별 항을 살리고 싶다면 행별 항은 페이지를 놓은 뒤(복사본 위에서) 돌리는 방법이 있지만 코드가 더 늘어납니다.
   - **놔두면:** 조인 바깥 테이블을 고치는 SP 가 필터에 있는 질의가, develop 에서는 되던 것이 latch 타임아웃으로 실패합니다(debug 계열 빌드는 서버 abort). 같은 원리로 지연 실행 부질의·serial NEXT_VALUE 같은 "스캔 중 저장소 재진입"을 develop 이 fixed scan 에서 막는 이유(`xasl_generation.c:9347` 주석, `fixed_scan_xasl` 결정)가 반복자에는 적용되지 않습니다. 이 두 모양은 재현하지 않았습니다.

### Non-blocking

없음. dealloc 측면에서 PR 이 새로 들인 결함은 찾지 못했습니다(위 표와 아래 스트레스 결과).

### Questions

1. 반복자가 행별 항을 돌리는 동안 다른 힙 페이지를 잡는 부질의가 `pgbuf_ordered_fix()` 의 순서 맞추기로 바깥 페이지를 잠깐 놓았다 다시 잡으면(`page_was_unfixed`), 배치가 PEEK 로 쥔 `batch->rows[].recdes` 가 그 사이 바뀐 페이지를 가리킬 수 있습니다. 반복자는 `page_was_unfixed` 를 보지 않습니다. 경합이 있어야 생기는 경로라 재현하지 못했습니다. Blocking 1 의 수정(행별 항이 있으면 거절)으로 같이 사라지므로, 수정 방향을 정할 때 함께 보면 됩니다.

## 참고: develop 에서 재현된 vacuum·px 결함 (PR 무관)

사용자가 말한 "vacuum 과 엮여 간간이 나는 오류"는 병렬 힙 스캔 쪽에서 재현됐고, merge-base 에서도 납니다.
- 부하: 10,001페이지 테이블에서 한 트랜잭션이 300행을 복사 후 삭제(페이지가 통째로 비어 vacuum 이 지움)하는 것을 반복하면서, 다른 세션이 직렬·병렬(`parallel(8)`) 집계와 NL 조인을 반복.
- head: 67초 만에 vacuum 스레드 `heap_remove_page_on_vacuum()` assert(`heap_file.c:3462` "Unexpected page waiters"). 기다리던 쪽은 px 워커 `input_handler_heap::get_next_vpid_with_fix()` 의 `OLD_PAGE_MAYBE_DEALLOCATED` fix(표지 없는 대기).
- merge-base: 112초 만에 px 워커가 같은 `get_next_vpid_with_fix()` 에서 read latch 20초 타임아웃 → assert(`page_buffer.c:7340`). 같은 시각 vacuum 워커 여럿이 `vacuum_heap_page()` 안에서 latch 대기 중.
- px 페이지 공급 코드는 PR 이 바꾸지 않았습니다. 원인은 이후 develop 코어로 확정해 CBRD-27723 으로 등록했습니다(2026-10-21): 병렬 스캔 워커는 파일 페이지 목록 순서로 페이지를 읽어, vacuum 이 체인에서 떼어 낸 빈 페이지를 R 로 잡은 채 vacuum 이 W 로 쥔 다음 페이지를 기다리고, vacuum 은 그 빈 페이지의 할당 해제(file_perm_dealloc)를 기다리는 교착입니다. "Unexpected page waiters" 는 같은 원인에서 해제 방지 표시 없는 대기자가 생긴 경우입니다.

## 실행한 검증

- 빌드: CI tarball, head `908bdc5af` optdebug·release, merge-base `c966fabc6` optdebug. 각자 scratch 사본, 포트 1713(head)·1714(base), campaign conf + `page_latch_timeout_in_msecs=20000`, DB `en_US.utf8`.
- SP 재현(Blocking 1): 위 SQL. head optdebug abort 1/1, head release 트랜잭션 abort 후 질의 실패 1/1, merge-base optdebug 정상 1/1. 단일 테이블 대조: 두 optdebug 빌드 모두 abort(develop 기존 결함). 코어 3개 backtrace 확인 후 삭제.
- dealloc 스트레스(직렬 경로만): 테이블 `d` 10만 행(행당 약 1.4KB, 페이지당 약 10행, 10,001페이지), 쓰기 세션 300행 이동 × 3000 트랜잭션(`--no-auto-commit`), 읽기 세션이 다음 세 질의를 540초 동안 반복:
  - R1 직렬 체인(fixed scan) `select count(*), sum(v) from d where g >= 0`
  - R2 필터 반복자(NL 바깥, 거의 모든 행 통과 → 청크마다 해제·재fix) `... from d a, u2 b where a.g >= 0 and b.k = a.g`
  - R5 필터 반복자(선택적 필터 `a.v = 7`)
  - head: R1·R2 각 990회 전부 `100000 / 49950000`, R5 989회 전부 `100 / 700`, 오류 0, 코어 0. 체인 페이지 수 10,001 → 21,321(이동한 행은 약 9만 페이지 분량이므로 빈 페이지가 vacuum 으로 지워지거나 재사용되며 진행).
  - merge-base: R1·R2·R5 각 887회 전부 같은 값, 오류 0, 코어 0, 체인 페이지 수 10,001 → 18,984. 두 빌드 모두 쓰기 3000 트랜잭션 완료(rc 0).
- 하지 않은 것: 빌드·CTP(이 항목은 동시성·latch 경로라 CTP 로 드러나지 않고, CI 결과는 5번 세션이 봄), release 빌드의 dealloc 스트레스, 병렬 경로의 PR 대 develop 빈도 비교(둘 다 develop 결함으로 먼저 죽음).

## 확인하지 못한 것

- 지연 실행 부질의·serial NEXT_VALUE 를 필터에 둔 조인 바깥 스캔(Blocking 1 과 같은 원리)의 실제 교착·오답.
- `page_was_unfixed` 경로(Questions 1).
- px 워커의 `rows` 노드가 non-cached·non-fixed 로 도는 경우: develop 에서 단계 0 병렬 힙 스캔은 fixed 가 아니면 cached 이므로 도달 경로를 찾지 못했습니다.
- RC 에서 SP 안의 문장이 새 스냅샷을 잡을 때 바깥 문장의 스냅샷이 vacuum 을 계속 막는지(dealloc 규칙 1의 전제). develop 공통 사항이라 PR 범위 밖으로 두었습니다.
