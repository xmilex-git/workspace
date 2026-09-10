# PoC T2/T3 — 결과 첫 페이지 2단 복사 제거(소유권 move) — C×1 + memmove 계수

- 티켓: [workspace#245](https://github.com/xmilex-git/workspace/issues/245) (맵 #207, 기준선 #244 상속)
- 일자: 2026-09-10 · 측정 환경: #244 runbook 그대로(SMT off·nproc 32·idle 게이트·G2 체크포인트-조용 conf·golden→copydb)
- 기준 sha `d533969e4` · PoC 브랜치 `poc/t23-result-page-move` (xmilex-git/cubrid, 2커밋: `bf7bfa540` move, `870b4ec39` B-lite) · 설치본 `/home/cubrid/release/CUBRID-wf-poc-t23`
  (`libcubrid.so.11.5` sha256 `145c7ec9…`, `cub_server` `7b7d10f7…`, JDBC 0076 동일)
- 원자료: 툴링 리포 `.git_ignored_dir/scratch/wf-poc/results/t23/{smoke,c1,c2,perfC,perfC_ungated}` · diff `patches/t23-result-page-move.diff`

## 1. 무엇을 바꿨나 (throwaway, 3파일 +39/−13)

폴드의 SELECT 결과 1건은 실행 시점에 `qmgr_attach_first_page_copy`(network_interface_cl.c)가 첫 페이지를 `malloc(DB_PAGESIZE)`+memcpy 해 `list_id->last_pgptr`에 달고,
`pt_new_query_result_descriptor`(query_result.c) → `cursor_open` → `cursor_copy_list_id`(cursor.c)가 그 사본을 **다시** malloc+memcpy 한 뒤 원본 list_id를 즉시 free 했다.
게다가 `cursor_open`은 첫 페이지와 무관하게 `buffer_area`(IO_MAX_PAGE_SIZE)를 선할당했다. 결과당 16 KiB memcpy ×2 + 16 KiB malloc ×3.

| 커밋 | 변경 | 규칙 |
|---|---|---|
| `bf7bfa540` **옵션 A — move** | `pt_new_query_result_descriptor`: `cursor_open` 전에 `list_id->last_pgptr`를 떼어(NULL) 커서가 열리면 `r->res.s.cursor_id.list_id.last_pgptr`에 붙인다. 실패 시 이 자리에서 free. 다른 7개 `cursor_open` 호출지·`cursor_copy_list_id` 시그니처 무변경 | COH-12(복사→이전) |
| `870b4ec39` **B-lite — 지연 할당** | `cursor_open`의 `buffer_area` malloc 제거, `cursor_get_list_file_page`가 실제 list-file 페이지를 가져와야 할 때만 할당(OOM은 `ER_OUT_OF_VIRTUAL_MEMORY`). 첫 페이지만 읽는 커서는 끝까지 할당 안 함 | ALLOC-01 |

**소유권 규칙(코드 주석과 동일):** 첫 페이지 사본은 `qmgr_attach_first_page_copy`가 만들고(malloc), 폴드 경로에서는 결과 디스크립터의 커서(`cursor_id.list_id.last_pgptr`)가 유일한 소유자이며 `cursor_free_list_id`가 해제한다.
`pt_new_query_result_descriptor`는 원본 list_id의 포인터를 NULL로 만든 뒤 free 하므로 이중 해제·누수 경로가 없다(cursor_open 실패 시엔 디스크립터 쪽이 NULL이라 이 함수가 직접 free).

**옵션 B(query 수명 pin) 기각:** 사본을 없애고 pgbuf 페이지를 pin 하려면 커서가 `xqmgr_end_query` 이후에도 첫 페이지를 읽는 autocommit generated-keys read-back 계약(network_interface_cl.c:201-209)과 충돌한다.
동일한 바이트 목표(−32 KiB)는 A+B-lite로 계약을 건드리지 않고 달성된다.

**결과당 회계:** 이전 malloc 3(16 KiB×3) + memcpy 2 → 이후 **malloc 1 + memcpy 1**(qmgr_attach_first_page_copy의 사본 하나만 남음). 행 수 무관.

## 2. 게이트 — fresh release 빌드 + smoke

- fresh `release`(RelWithDebInfo) 빌드 OK, 변경 파일 경고 0.
- `smoke.sh smk` 14케이스: 첫 실행 **12/14** — PLCSQL·PLCSQL NESTED가 `-1360 Can't connect PL server`. 원인은 패치가 아니라 **설치본 conf**: 빌드가 템플릿한 `cubrid.conf`에 `stored_procedure=no`가 있어 cub_pl이 기동되지 않았다(`PL server is not running.` ×4). 기준선 설치본은 20_apply_conf.sh로 캠페인 conf(해당 키 없음)가 덮여 있었다.
  대조: 기준선 설치본에서 같은 2케이스 PASS → t23에 캠페인 conf 적용 후 재실행 **2/2 PASS**(`smoke/smoke_sh_plcsql_rerun_pocconf.log`). 최종 **14/14**.
- `smoke_jdbc.sh smk 33000`: SUCCESS(41 s).

## 3. 측정 — C×1 (기록용) + 확인용 C×1 추가

| leg | ops/s | READ p50 | READ p95 | READ p99 | checkpoints | errors | loadavg_before |
|---|---|---|---|---|---|---|---|
| base c1/c2/c3 (#244) | 115,550 / 118,374 / 119,919 | 766/750/742 | – | 2,433/2,299/2,293 | 0 | 0 | 4.97/4.67/5.05 |
| **t23 c1** | **125,357** | 713 | 1,566 | 2,121 | 0 | 0 | 5.08 |
| **t23 c2** | **123,912** | 719 | 1,579 | 2,139 | 0 | 0 | 3.28 |

- t23 median **124,635** vs base 118,374 → **+5.29 %**(= +4.1 base-MAD, floor 113,739 통과). 두 레그 모두 base 최대치(119,919)보다 위.
- READ p50 750→716(**−4.5 %**), p99 2,299→2,130(**−7.4 %**, hold 2,529 미달 → G2 hold 없음). 회귀·크래시·오류 없음.
- 20M ops 완주 시간 173/169/167 s → 160/161 s.
- 판정 규약(#244 7항): C×1 ≥ floor → **스택 포함**. 단일 실행 판정 금지(MEAS-04)라 c2를 추가했고 두 값이 MAD 723 안에서 일치한다.

## 4. perf — memmove 계수 소거 여부 (cycles, dwarf, 30 s @ t=20 s, 5M ops)

| symbol (self) | base perfC | t23 perfC (gated) | t23 perfC_ungated* |
|---|---|---|---|
| `__memmove_evex_unaligned_erms` | 2.89 % | **1.75 %** | 1.82 % |
| ├ `cursor_copy_list_id` 경로 | 1.31 % | **0 (소멸)** | **0 (소멸)** |
| └ `qmgr_attach_first_page_copy` 경로 | 1.17 % | 1.36 % | 1.39 % |
| `malloc` | 2.53 % | 2.30 % | 2.31 % |
| `malloc_consolidate` | 2.11 % | 1.91 % | 1.97 % |
| `__pthread_mutex_lock` | 2.42 % | 2.59 % | 2.61 % |
| `cursor_copy_list_id` self | 0.02 % | 0.02 % | 0.02 % |

\* perfC_ungated: 직전 c2 레그의 자체 loadavg 감쇠 중(loadavg1 5.19, 타 테넌트·busy 프로세스 0)에 게이트 없이 시작된 첫 perf 레그. 게이트 스크립트의 종료코드가 파이프 뒤에서 무시된 운용 실수(수정: `set -o pipefail`). 기록용으로 보존, 판정은 gated 열.

- memmove 총량은 base 2.89 %에서 t23 **1.75 %**로 줄고, **cursor_copy_list_id 경로는 caller 목록에서 사라졌다**(계수 소거 확인). 남은 memmove는 전부 `qmgr_attach_first_page_copy`(옵션 B 영역).
- malloc 계열 감소는 소폭(16 KiB large-bin 요청 2개 제거) — 처리량 +5 %는 memmove 1.1 pp 절감보다 크며 100스레드 arena 경합(`_int_free`·tcache 미스) 완화가 겹친 결과로 해석. 정밀 귀속은 스택 티켓(#253)의 C×3·hot-symbol 몫.
- **새 사실(양쪽 perf 공통):** `malloc_consolidate`(base 2.11 % → t23 1.91 %)의 caller는 **100 % `qmgr_attach_first_page_copy`의 `malloc(DB_PAGESIZE)`**(_int_malloc → large-bin 요청이 fastbin 병합을 유발). 즉 남은 attach 사본 1개가 memmove 1.36 % + consolidate 1.91 % + `_int_malloc` 일부 ≈ **3.3 %+**를 쥐고 있다 — 이번에 제거한 몫보다 크다. 사본 자체는 read-back 계약상 필요하지만 **malloc은 필요 없다**: 세션(driver_session)당 16 KiB 슬롯을 재사용하면 계약을 지키면서 large-bin malloc/free를 결과당 0으로 만들 수 있다(후속 PoC 후보 T2/T3-b, 아래 §5).

## 5. 처분 제안

**후속 구현 채택**(스택 포함). 이득이 3 MAD 밖에서 재현되고 p99까지 개선되며, 변경 반경이 3파일·1 호출지로 작다.

후속(제품) 구현이 추가로 증명해야 할 불변식:
1. `cursor_open` 8개 호출지 중 원본 list_id를 즉시 free 하지 않는 7곳(parse_evaluate.c ×2, execute_statement.c ×4, query_result.c empty)은 여전히 복사 경로 — 제품판이 move를 `cursor_copy_list_id`/`cursor_open` 안으로 옮기면 그 호출지들이 원본 `last_pgptr`를 이후 재사용하지 않음을 각각 증명(같은 list_id로 커서 2회 개방 케이스 포함).
2. `buffer_area` 지연 할당: `cursor_id->buffer`가 NULL인 상태로 `cursor_next/prev/first/last_tuple` 이외 경로에서 참조되지 않음(현재 grep 상 buffer 역참조는 모두 fetch 이후) — CTP sql/medium 전체 + holdable cursor·scroll(JDBC 역방향) TC.
3. CS 모드(레거시 fat 클라이언트)에서 `last_pgptr`가 wire 사본인 경우도 동일 규칙으로 동작(폴드 전용 분기 아님). SA 모드는 `last_pgptr`가 항상 NULL(query_manager.c:1274)이라 no-op.
4. generated-keys autocommit read-back(smoke_jdbc B2 케이스)·holdable cursor의 end_query 이후 첫 페이지 접근.
5. OOM 경로: 지연 할당 실패가 `ER_OUT_OF_VIRTUAL_MEMORY`로 상위에 전파되고 커서 상태가 재시도 가능.
6. 옵션 B 잔여(`qmgr_attach_first_page_copy` 사본 1회)는 계약상 필요 — 제거하려면 read-back 계약 자체를 바꿔야 하므로 별도 결정. 다만 **malloc 제거는 계약과 무관**: 세션 소유 재사용 페이지 슬롯(커서 수명 ≤ 세션, 세션당 동시 열린 결과 디스크립터 수만큼 슬롯 — JDBC는 statement당 1) → 후속 PoC **T2/T3-b**로 분리 제안(기대: malloc_consolidate 1.9 % 전량 + _int_malloc/_int_free 일부).

## 6. 운용 메모
- `scripts/40_perf_leg.sh`에 memmove·malloc_consolidate caller 리포트 추가(#245). 기준선 perf.data에서도 같은 명령으로 계수 확인(cursor_copy_list_id 1.31 / attach 1.17).
- 기준선 설치본의 idle cub_master(1523)를 smoke 전에 정지(`cubrid service stop`); 스모크 DB `smk`는 각 설치본 `databases/` 아래(YCSB DB와 분리).
