# PoC T2/T3-b — attach 첫 페이지 사본의 결과당 malloc을 세션 소유 재사용 슬롯으로 — C×1 + malloc_consolidate 계수

- 티켓: [workspace#254](https://github.com/xmilex-git/workspace/issues/254) (맵 #207, 기준선 #244 상속, [PoC T2/T3 #245](https://github.com/xmilex-git/workspace/issues/245)의 파생)
- 일자: 2026-09-10 · 측정 환경: #244 runbook 그대로(SMT off·nproc 32·idle 게이트·G2 체크포인트-조용 conf·golden→copydb)
- 기준 sha `d533969e4` · t23 `870b4ec39` 위 1커밋 `1cc2fee7b` · PoC 브랜치 `poc/t23b-first-page-slot` (xmilex-git/cubrid) · 설치본 `/home/cubrid/release/CUBRID-wf-poc-t23b`
- 원자료: 툴링 리포 `.git_ignored_dir/scratch/wf-poc/results/t23b/{smoke,c1,c2,perfC}` · diff `patches/t23b-first-page-slot.diff`

## 1. 무엇을 바꿨나 (throwaway, t23 위 4파일 +120/−5)

#245 이후 폴드의 SELECT 결과 1건에는 첫 페이지 사본이 **하나** 남는다: `qmgr_attach_first_page_copy`(network_interface_cl.c)의 `malloc(DB_PAGESIZE)`+memcpy → `list_id->last_pgptr` → (move) 결과 디스크립터 커서 → `cursor_free_list_id`의 `free`.
#245 perf에서 `malloc_consolidate`(≈2 %)의 caller가 100 % 이 malloc이었다(16 KiB는 fastbin/tcache 밖의 large-bin 요청이라 매번 fastbin 병합을 유발). 사본은 autocommit generated-keys read-back 계약상 필요하지만 **결과당 malloc은 계약과 무관**하다.

| 파일 | 변경 | 규칙 |
|---|---|---|
| `client_session_context.hpp/.cpp` | 세션 컨텍스트(#123 D3 앵커, 브래킷으로 직렬화)에 `fp_slot[4]`(DB_PAGESIZE, 지연 할당)·`fp_slot_busy[4]`·`fp_slot_overflow` 추가. `csc_first_page_slot_acquire()`: 브래킷 밖/전 슬롯 busy면 NULL. `csc_first_page_slot_release(p)`: 현 브래킷 슬롯 주소면 반납 true, 아니면 false. 소멸자가 슬롯 해제 | ALLOC-01(핫패스 할당 제거), COH-12 |
| `network_interface_cl.c` | attach: 슬롯 acquire → NULL이면 기존 `malloc` 폴백. `qmgr_get_old_page` 실패 시 release-or-free | — |
| `cursor.h` | `cursor_free_list_id` 매크로의 유일한 `last_pgptr` free를 `cursor_release_first_page`로: SERVER_MODE는 release 실패 시 free, CS/SA는 기존 `free_and_init` | 분기 1(주소 비교) |

**소유권 규칙:** 사본 버퍼의 출처는 슬롯 또는 heap 둘 중 하나이고, 구분은 **주소**로만 한다(현 브래킷 ctx의 `fp_slot[i] == p`). `cursor_copy_list_id`가 만드는 복제(t23 이후 폴드 결과 경로에서는 소멸, 다른 7개 `cursor_open` 호출지에는 잔존)는 항상 heap이라 free 분기로 간다. 슬롯 수 4 = 세션당 동시 열린 결과 디스크립터 상한 가정(JDBC autocommit은 statement당 1); 초과분은 `fp_slot_overflow`에 계수되고 malloc 폴백.

**전제(제품 구현이 증명해야 할 것):** (a) 사본의 release는 **같은 세션의 브래킷 안**에서 일어난다 — 결과 디스크립터는 세션 소유(db_qres 레지스트리 세션당 1)이고 정리는 브래킷 teardown 안에서 돈다. 브래킷 밖에서 release가 불리면 false→free→세션 소멸자에서 이중 해제가 된다(PoC는 이 경로가 없다고 가정, assert 없음). (b) `QFILE_CLEAR_LIST_ID`처럼 free 없이 NULL 하는 경로는 슬롯을 세션 종료까지 점유(누수 아님, 폴백 증가).

## 2. 게이트 — fresh release 빌드 + smoke

- fresh `release`(RelWithDebInfo) 빌드 6 m 11 s, 변경 파일 경고 0. 설치본 `CUBRID-wf-poc-t23b`: `libcubrid.so.11.5` sha256 `d926948b…`, `cub_server` `36e7e5c9…`, JDBC 0076 동일(`3e876fb1…`).
- 캠페인 conf(`20_apply_conf.sh 100`)를 **먼저** 적용한 뒤 `smoke.sh smk` **14/14 PASS**(PLCSQL 2건 포함 — #245의 `stored_procedure=no` 함정 회피), `smoke_jdbc.sh smk 33000` **SMOKE_JDBC: SUCCESS**. 서버 .err에 core/fatal/assert 0.
- 사전 컴파일 검사: t23 빌드 트리의 compile_commands로 4개 TU를 SERVER/CS/SA 3모드 각각 컴파일(-Werror 통과; 첫 시도의 `-Werror=redundant-decls`는 선언을 cursor.h 한 곳으로 모아 해소).

## 3. 측정 — C×1 (기록용) + 확인용 c2

| leg | ops/s | READ p50 | READ p99 | checkpoints | errors | loadavg_before |
|---|---|---|---|---|---|---|
| base c1/c2/c3 (#244) | 115,550 / 118,374 / 119,919 | 766/750/742 | 2,433/2,299/2,293 | 0 | 0 | 4.97/4.67/5.05 |
| t23 c1/c2 (#245) | 125,357 / 123,912 | 713/719 | 2,121/2,139 | 0 | 0 | 5.08/3.28 |
| **t23b c1 / c2** | **127,971 / 120,476** | 690 / 729 | 2,211 / 2,395 | 0 | 0 | 3.78 / 4.79 |

- t23b median **124,224**(MAD 3,748) — vs base 118,374 **+4.94 %**(+3.8 base-MAD, floor 113,739 통과) · vs t23 124,635 **−0.33 %**. t23 대비 증분은 **판별 불가**(레그 간 편차 7,495가 차이 411의 18배). c1은 트랙 최고 단일치, c2는 게이트 통과(loadavg 3.45) 후 기동 시점 loadavg 4.79에서 측정된 낮은 쪽.
- p50 709.5(t23 716, base 750) · p99 2,303(t23 2,130, base 2,299; hold 2,529 미달 → G2 hold 없음). 회귀·크래시·오류 없음.

## 4. perf — malloc 계열 계수 (cycles, dwarf, 30 s @ t=20 s, 5M ops, 게이트 통과 후 기동)

| symbol (self) | base | t23 | **t23b** | 비고 |
|---|---|---|---|---|
| `malloc_consolidate` | 2.11 % | 1.91 % | **0.03 %** | **목표 계수 소멸** — caller 100 % attach malloc이었음 |
| `malloc` | 2.53 % | 2.30 % | 1.97 % | attach 경로 caller 목록에서 소멸(슬롯 overflow 없음) |
| `_int_malloc` | 1.44 % | 1.37 % | **2.47 %** | `db_cp_query_type_helper` 경로 0.55 → **1.49 %**, `db_alloc_query_format` 0.38 %, `sm_domain_copy` 0.30 %; attach 0.31 → 0 |
| `_int_free` | 1.03 % | 1.01 % | 1.11 % | `db_free_query_format`←`db_free_query_result` 0.46 → 0.56 % |
| `cfree` | 0.45 % | 0.45 % | 0.55 % | |
| **malloc 계열 합계** | 7.56 % | 7.04 % | **6.13 %** | **−0.91 pp** (t23 대비) |
| `__memmove` self | 2.89 % | 1.75 % | 1.72 % | attach 경로 1.36 → 1.31 % — 사본 memcpy는 계약상 잔존(예상대로) |
| `qmgr_attach_first_page_copy` self / slot acquire / release | – | 0.02 / – / – | 0.02 / 0.06 / 0.03 % | 슬롯 경로 자체 비용 ≈0.1 % |

**해석.** 가설(consolidate = attach의 16 KiB large-bin 요청)은 검증됐다. 그러나 그 consolidate는 동시에 폴드 결과당 **소형 할당 군의 fastbin 정리**였다: 없어지자 후속 소형 malloc이 `_int_malloc`의 bin 순회에서 그 비용의 상당 부분(≈+1.1 pp)을 대신 냈다. 순이득은 malloc 계열 −0.9 pp에 그치고 C×1에는 드러나지 않았다.
따라서 이 경로에서 남은 진짜 소비자는 16 KiB 페이지가 아니라 **결과당 query type 복사**(`db_cp_query_type` → `db_alloc_query_format`/`sm_domain_copy`, 해제는 `db_free_query_result`→`db_free_query_format`)다 — t23b perf에서 malloc 계열의 최대 단일 caller(≈2 %).

## 5. 처분과 후속 입력

- **처분: 스택 포함, t23 → t23b 교체(#244 7항 규약 — 회귀·크래시 아님)**. 단독 채택 근거(C×1 이득)는 없으므로 **후속 구현 채택은 보류**: 스택 hot-symbol 귀속에서 malloc 계열이 남으면 "결과당 query type 복사 제거"와 묶어 판정한다. 스택에 t23b를 넣는 이유는 consolidate 계수를 지워 그 소형 할당 군을 프로파일에서 선명하게 보기 위함이다.
- **후속(제품) 구현이 증명해야 할 불변식(슬롯 방식 채택 시)**
  1. 사본의 release는 **같은 세션 브래킷 안**에서만 — 브래킷 밖/타 세션 브래킷에서 release되면 heap으로 오인해 free → 세션 소멸자 이중 해제. 제품판은 슬롯 헤더(owner ctx 포인터)나 assert로 검출해야 한다.
  2. 세션당 동시 열린 결과 디스크립터 수(holdable/kept statement 커서, 다중 statement) ≥ 슬롯 수일 때의 폴백 빈도(`fp_slot_overflow`) 계측.
  3. `QFILE_CLEAR_LIST_ID`처럼 free 없이 NULL 하는 경로는 슬롯을 세션 종료까지 점유 — 누수는 아니나 폴백 증가.
  4. CS/SA 빌드 무변경(`#if SERVER_MODE`) — CTP sql/medium 전건.
- **새 PoC 후보 입력(#253 처분표·맵 fog)**: 결과당 query type 복사(`db_cp_query_type`)를 statement(prepared) 소유로 바꿔 재실행 간 재사용 — 기존 T1/R7·P6과의 겹침 여부는 스택 티켓이 판정.

운용 메모: perfC는 타 테넌트 부하(loadavg 45.8)로 게이트가 5분 대기 후 3.94에서 통과; perf record가 "lost 287 chunks" 경고를 냈으나 exit 0·293K 샘플. c2는 게이트 통과 후 기동 시점 loadavg 4.79 — 기준선 레그(4.67~5.05)와 동급.
