# CBRD-27365 #192 정합성 검증 기록 (PR-2b `a2456c390` → 수정 커밋)

맵 #179 의 실행 티켓. 대상 fork PR xmilex-git/cubrid#259(`CBRD-27365-pr2b`). 결정 ID `D-192-*`.
운영: 설치 `~/optdebug/CUBRID-cbrd27365`(optdebug), DB `cbrd27365s`@1702(포트 클레임 등록), 참조 빌드 `~/optdebug/CUBRID-11.5.develop`(develop c67e642, DB `i192ref`@1700).

## 1. 게이트 (기준 HEAD `a2456c390`, 수정 전)

| 단계 | 결과 |
|---|---|
| smoke ×2 (csql 12항목 + JDBC 역방향 커서) | PASS/PASS ×2, err 로그 assert/Fatal/leak 0 |
| CTP sql 전수 (`just ctp-parallel`, 7 shard, 감시 ON) | **17,449 / 17,457, 코어 0**, 실패 8 = #191 기준선과 동일(KNOWN): 플랜텍스트 7(cbrd_23665·cbrd_24148·cbrd_25382_1/_5·cbrd_25447·cbrd_25519·join_orderby_skip) + agg_group_by 답안 drift(D-190-12). 신규 실패 0 |
| medium 전수 (`just ctp-medium-isolated`, 975 케이스 8 bucket) | **975 / 975, 코어 0** — `_01_fixed` 외 7 bucket 은 이 캠페인의 첫 실행 |

로그: `.git_ignored_dir/scratch/i192/ctp-sql.log`, `ctp-medium.log`; 결과 `ctp-parallel-out/`, `ctp-iso/20260903T145149Z-*-medium/`.
운영 메모: 이전 세션의 스테일 `cub_master`(바이너리 삭제됨)가 1702 를 점유 → kill 뒤 진행. deletedb 가 빈 스텁 디렉터리를 남겨 createdb 가 "Volume already exists" → 수동 정리.

## 2. 신규 TC 10건 A/B (docs/research/cbrd27365-new-tcs/)

PR-2b 빌드와 develop 참조 빌드에서 각각 실행해 `.answer.pr2b` / `.answer.develop` 을 diff.

| 파일 | 결과 |
|---|---|
| tc01 NULL 혼합, tc02 고정/가변+127/128/129B, tc03 오버플로, tc04 CONNECT BY, tc05 해시조인, tc06 분석함수, tc07 SET/JSON, tc09 64+컬럼, tc10 in-place | **9/9 바이트 동일** |
| tc08 늦은 도메인 | (1)~(5),(8),(9) 동일. **(6) `EXECUTE s6 USING NULL, 7` 에서 두 빌드 모두 서버 abort** — `qfile_unify_types` `assert_release (list_id1_p->tuple_cnt == 0)` (list_file.c), `qexec_execute_cte` 1차 반복 뒤 타입 통일 시점. develop 동일 재현 → 기존 결함(맵 fog "qfile_unify_types assert_release 모순(미재현)" 항목이 재현됨) |

코어(콜스택 텍스트): `~/optdebug/CUBRID-cbrd27365/log/coredump/cub_server_20260903234934.223.coredump`, `~/optdebug/CUBRID-11.5.develop/log/coredump/cub_server_20260903235208.354.coredump`.

## 3. R1 / R2 점검 (#191 이관)

### R1 — 스캔 열린 채 append + 미확정 컬럼 확정
`qfile_reopen_list_as_append_mode` 8지점 분류:

| 지점 | 스캔 열린 채 append? | 미확정 컬럼 가능? | 판정 |
|---|---|---|---|
| query_executor.c 해시 group-by 부분 리스트 덤프 | 아니오(정렬 스캔은 덤프 뒤 열림) | 가능 | 무관 |
| query_executor.c 파티션 클래스 폴백 heap scan ×2 (xasl->list_id) | 아니오(생산 중 리더 없음) | 가능 | 무관 |
| scan_manager.c 커버링 인덱스 리스트(backward) | 재개방 뒤 스캔 다시 열림 | 아니오(B-tree 키 도메인) | 무관 |
| query_hash_join.c / px_hash_join 파티션 리스트 | 아니오(파티션 완료 뒤 읽음), raw 복사 | 아니오(입력 리스트 확정 뒤 생성) | 무관 |
| external_sort.c origin_list_id | 아니오 | — | 무관 |
| **query_executor.c 재귀 CTE 공용 리스트 최적화** | **예**(같은 리스트를 스캔하며 append) | **예**(호스트 변수 표현식 컬럼이 NULL 로 시작) | **위험 실재** |

재귀 CTE 도달 조건: 앵커 컬럼이 DB_TYPE_VARIABLE(예: `SELECT 1, ? … USING NULL`) → 1차 반복 뒤 `qfile_unify_types`. 디버그 빌드는 여기서 abort(§2). 릴리스 빌드는 assert_release 가 로그만 남기고 지나가며, 재귀부도 아직 NULL 만 썼다면(첫 bound 값이 2번째 반복 이후, tc08 (6b)) 컬럼이 VARIABLE 로 남은 채 공용 리스트 최적화가 켜짐 → 스캔의 디스크립터 복사본은 VAR, 라이터는 첫 bound 값에서 FIXED 로 확정 → 같은 반복에서 append 된 행을 stale 레이아웃으로 읽음. 구 포맷은 regu 도메인으로 디코드해 무관했으므로 **릴리스 기준 PR-2b 회귀**.

**D-192-1** `qfile_unify_types` 의 `assert_release(tuple_cnt == 0)` 2개 제거. 근거: D-199-13 불변식 — 컬럼이 VARIABLE 인 동안 기록된 값은 전부 NULL(0바이트, 패딩 없음)이라 상대 리스트의 도메인을 넘겨받아도 이미 쓴 튜플의 레이아웃은 바뀌지 않음. `qfile_union_list`·`qfile_combine_two_list` 의 누적 경로도 같은 함수를 지나므로 일관. 부수 효과: develop 에도 있던 디버그 abort 해소.
**D-192-2** 재귀 CTE 공용 리스트 최적화를 `qfile_type_list_is_resolved (&non_recursive_part->list_id->type_list)` 일 때만 켬. 미확정 컬럼이 남으면 기존 복사 경로(매 반복 별도 리스트, 스캔은 반복마다 현재 디스크립터로 열림)로 폴백. 비용: 그런 CTE 에서만 반복당 리스트 복사(기존 코드 경로), 정상 CTE 는 컬럼 수만큼의 비교 1회.
헬퍼 `qfile_type_list_is_resolved()` 를 `qfile_tuple_layout.h` 에 추가.

### R2 — px 스냅샷 도메인 발행 2지점
`px_scan_result_handler.cpp` XASL_SNAPSHOT 라이터: `update_domains_on_type_list_by_val_list` 직후 `m_type_list[i].store`, 그 다음 `qdata_copy_val_list_to_tuple`(조립기, 값 기반 확정 가능), 그리고 close 시 재발행. 조립기가 추가로 확정한 컬럼은 close 전까지 stale 발행 상태. 현재는 val_list 도메인이 스키마 확정형(속성 도메인)이라 조립기가 추가 확정할 컬럼이 없어 **빈 집합** — 관찰만(#191 판단 유지). 권고(후속): 발행 루프를 조립기 뒤(`qfile_add_tuple_to_list` 앞)로 옮기면 불변식 없이 구조적으로 안전(동일 비용).

## 4. 수정 뒤 재검증 (커밋 `de9018bf2`, 설치 2026-09-03 23:57)

| 단계 | 결과 |
|---|---|
| 증분 컴파일(Ninja, 헤더 변경으로 101 타깃) | 경고·에러 0 |
| install 뒤 conf 포트 재적용 | install 이 conf 를 기본값(1523/30001/30000)으로 되돌림 → 백업본 복원(맵 운영 메모와 동일 현상) |
| DB `cbrd27365s` 재생성(새 빌드) + smoke ×2 | PASS/PASS ×2 |
| tc08 전 문장 | 서버 생존. (6) s6 3회: hv = NULL,7,7,7,7 / NULL,'seven'×4 / NULL,7.25×4. (6b) NULL,NULL,7,7,7,7. (7) NULL,50×5, `hv IS NULL` = 1,0,0,0,0,0. (1)~(5),(8),(9) develop 출력과 동일. err 로그 assert/-495 0 |
| tc01~07,09,10 재실행 | develop 답안과 전부 동일 |
| 격리 CTP CTE 서브셋(`_29_CTE_recursive/_01~_07`, `_30_banana_pie_qa/_01_recursive_cte`, `_31_cherry/issue_22161_CTE_extensions`) | **204 / 204, 코어 0** |
| CTP sql 전수(수정 빌드) | §6 |

tc08 (6b)(CASE 표현식) 는 수정 전에도 두 빌드에서 정상이었다 — CASE 가 정적 타입을 받아 컬럼이 VARIABLE 로 남지 않음. 따라서 D-192-2 가드의 실제 트리거는 드물고(방어선), (6)/(7) 은 D-192-1 이 직접 해소한다.

## 5. 플랜텍스트 7건의 인과 (develop 대조로 확정)

같은 6개 디렉터리(52 케이스)를 격리 CTP 로 develop 참조 빌드(c67e642)와 PR 빌드에서 실행: **develop 52/52 PASS, PR 45/52 — 실패 7건이 정확히 대상 7건**. 따라서 testcases 답안 drift 나 develop 변경이 아니라 **PR-2b 가 만든 플랜 변화**다(브랜치 베이스 = origin/develop 8e355ff59 최신, testcases a2c76731d 고정, 실행 중 pull 없음). 저장소 답안 대비 clean diff: `.git_ignored_dir/scratch/i192plan/clean/pr-*.diff`(워커 1차 diff 의 "새 패턴" 2종은 `cases/` 의 옛 `.result` 잔재와 비교한 오류).

세 패턴 모두 **실행기의 리스트 페이지 수(`list_id->page_cnt`) 기반 결정**이 튜플 축소(−26%)로 바뀐 것이며, 코드 결함이 아니다:

| 패턴 | 케이스 | 결정 지점 | 입력 |
|---|---|---|---|
| `hash temp(h)→(m)`, `BUILD method: hybrid→memory` | cbrd_23665, cbrd_25382_1, join_orderby_skip | `query_hash_join.c` in-memory 판정 `in_mem_size = slots + entries + page_cnt*DB_PAGESIZE <= mem_limit` | 빌드 리스트 페이지 수 |
| `(parallel workers…)` 줄 소실(병렬 정렬/해시조인 → 직렬) | cbrd_24148, cbrd_25382_5, cbrd_25447, cbrd_25519(ORDERBY 아래 8줄) | `px_parallel.cpp` `compute_parallel_degree(type, num_pages, hint)`; 호출자 `external_sort.c`(`input_file->page_cnt`), `query_hash_join.c`(`max(outer,inner page_cnt)`) | 리스트 페이지 수 vs `parallel_sort/hash_join_page_threshold`(hidden, 기본 2048 페이지) |
| 스캔 순서 스왑(BUILD=ta, PROBE=t_bigint) | cbrd_25382_1 | `query_hash_join.c` JOIN_INNER 빌드측 선택: tuple_cnt 같으면 `page_cnt` 작은 쪽이 build | 구 포맷은 INT/BIGINT 모두 8B 정렬이라 두 리스트 페이지 수가 같아 fallthrough(inner=t_bigint 빌드); 새 포맷은 INT 리스트가 작아져 ta 가 빌드 — 의도된 규칙이 이제 실제로 작동 |

의미: 새 포맷은 임시 리스트가 작아진 만큼 "페이지 수" 로 표현된 임계들이 **같은 데이터에 대해 상대적으로 높아진다**(같은 행 수라도 페이지가 적으니 병렬/hybrid 로 덜 간다). 행 수 기준으로는 임계가 올라간 셈이며, 이것이 옳은지(페이지 수가 진짜 비용 대리변수인가)는 별도 판단 사항 — 사용자와 의논(§5.1).

### 5.1 처리 방향 (사용자 결정, 2026-09-04)
- 엔진 임계·판정 로직은 건드리지 않는다(포맷 PR 범위 유지). 임계 단위의 옳고 그름은 이 이슈에서 다루지 않음.
- **TC 측에서 원래 의도 복원**: upstream PR 오픈 시 자동 생성되는 TC PR(`tc/pr-<n>`)에서 (1) 6건은 입력 크기를 키워 리스트가 원래 임계를 다시 넘게, (2) cbrd_25382_1 은 빌드/프로브 스왑이 일어나지 않게 데이터를 재설계해 원래 trace 가 나오게. 답안 텍스트는 유지. 검증은 PR·develop 양쪽 격리 CTP 통과.
- JIRA design.md 에 부수효과(페이지 수 기반 실행기 결정이 달라질 수 있음)를 명시. 기록 위치는 #194(upstream PR 티켓).

## 6. 수정 빌드(`de9018bf2`) CTP sql 전수 + develop 대조

| 실행 | 결과 |
|---|---|
| 전수 1차 | shard 4 에서 코어 → 감시가 전 shard 중단(2,387건만 완주, 실패 3 = known). 코어 분석 §6.1 |
| 전수 2차(재실행) | **17,457 중 17,449 통과, 코어 0, 실패 8건 = known8 과 바이트 동일** — 신규 회귀 0 |
| develop 대조(6 디렉터리 52건) | develop c67e642 **52/52**, PR **45/52**(실패 = 대상 7건) → 7건은 PR 의 플랜 변화(§5) |

로그: `.git_ignored_dir/scratch/i192/ctp-sql-fix.log`, `ctp-sql-fix2.log`, `i192plan/run-{develop,pr2b}.log`.

### 6.1 1차 실행의 코어 — PR 무관 기존 레이스 (별도 이슈 후보)
`cbrd_25382_1` 의 `UPDATE STATISTICS … WITH FULLSCAN` 중 `stats_update_statistics_internal → btree_get_stats_with_fullscan → btree_find_lower_bound_leaf → btree_find_leftmost_leaf → btree_find_boundary_leaf (btree.c:17686) ASSERT_ERROR()`: `pgbuf_fix()` 가 NULL 을 돌려줬는데 `er_errid()==NO_ERROR`(에러코드 미설정 불변식 위반). 스택에 `qfile_*/list_file/external_sort` 프레임 없음, PR 브랜치는 statistics_sr.c·btree.c 미수정. 같은 디렉터리 격리 반복 4회(plan-check 1 + gate2 3) 코어 0 → 7 shard 동시 실행 하의 페이지버퍼 경합에서만 드러나는 레이스로 판단. gdb: `.git_ignored_dir/scratch/i192/stats-core-bt.txt`, 메모 `new-fail-cbrd_25382_1-CRASH.txt`.

## 7. 셸 테스트
로컬 `just shell-debug*` 는 CTP 셸 init 이 이 사용자의 모든 `cub_*` 를 pkill 하는데 host 에 1523 포트 장기 실행 `cub_master`(포트 레지스트리 고정 점유자)가 살아 있어 실행하지 않음. 티켓 문구대로 upstream PR CI 셸(#194)로 이관. 후보 목록(스크롤 커서 83 + CONNECT BY/정렬·임시볼륨 파라미터 33, `_25_unstable` 제외): `.git_ignored_dir/scratch/i192_shell_scroll.txt`, `i192_shell_list.txt`.

## 8. 결정 ID
- **D-192-1** `qfile_unify_types` assert_release(tuple_cnt==0) 제거 — D-199-13 불변식으로 안전; develop 디버그 abort 도 해소.
- **D-192-2** 재귀 CTE 공용 리스트 최적화는 `qfile_type_list_is_resolved()` 일 때만 — #191 R1 창 차단, 폴백은 기존 복사 경로.
- **D-192-3** R2(px 스냅샷 발행 순서)는 현재 빈 집합 → 코드 무수정, 발행을 조립 뒤로 옮기는 안은 후속 권고로만 기록.
- **D-192-4** 플랜텍스트 7건은 엔진이 아닌 TC 측에서 입력 확대·재설계로 원래 경로 복원(사용자 결정) — #194.
- **D-192-5** 셸은 로컬 pkill 위험으로 CI 이관.

