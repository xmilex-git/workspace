# CBRD-27365 PR-1b: 접근자 치환 롤아웃 기록 (티켓 #196, 지도 #179)

PR-1a(#189) 위에 쌓은 fork PR — 리스트 튜플 **리더**와 in-place 라이터를 슬롯 접근자로 바꾸고, 레이아웃
디스크립터를 계산(미사용)하며, 포맷은 불변. 결정 ID `D-196-*`. 코드 위치는 worktree `~/dev/worktrees/cbrd27365`
브랜치 `CBRD-27365-pr1b`.

## 결정

| ID | 결정 | 근거 | 되돌림 |
|---|---|---|---|
| D-196-1 | PR-1b의 모든 리스트는 `hdr_size = 8`(레거시 `[len][prev_len]`). backward 플래그·44개 open 지점 분류는 PR-2. | 구 포맷은 항상 8B 헤더라 정확히 참. | — |
| D-196-2 | 레거시 접근자 구현: `off` = "컬럼 `nvalid`의 값 헤더 오프셋", `set_tuple`이 `nvalid=0, off=8`로 리셋. `fast_limit` 미사용. | 값 헤더 워크에 필요한 캐시는 진행 위치뿐. | — |
| D-196-3 | 값 접근자·in-place는 **디코딩 도메인을 인자**로 받는다(`qfile_slot_read_value (rec, col, dom, v, copy, &is_null)`). 레이아웃은 bind된 디스크립터, 디코딩은 호출자 도메인. NULL이면 DB_VALUE 불변. | fetch는 `pos_descr.dom`, 해시조인은 `fetch_info` 도메인 등 리스트 `domp[col]`과 다를 수 있어 동작 불변에 필수. | tl->domp[col] 고정(D-182-7 원안) |
| D-196-4 | 디스크립터 없이 읽는 곳(px XASL_SNAPSHOT 리더, 집계 해시 엔트리 역직렬화)은 `qfile_tuple_walk_*`(D-182-16 원시 함수)를 PR-1b에서 도입. | 스레드 계약(D-181-10)·호출자 소유 도메인. | — |
| D-196-5 | 범위 경계: 리더·in-place만 접근자. 복사형 라이터(merge·정렬키 본문·hjoin merge)는 접근자로 위치만 얻고 `qfile_legacy_put_value`로 구 헤더 재기록(assembler bridge). 조립기(D-182-11)·정렬 레코드 본문 리더(D-182-14)는 PR-2. | 조립기 API는 포맷과 함께 들어와야 의미가 있다. | — |
| D-196-6 | D-181-7 교차검증은 `qfile_open_list_scan`(스캔당 1회)에서 assert. 접근자 진입마다 하지 않음. | 진입마다 O(ncols) 재계산은 optdebug CTP를 느리게 함. | 진입 assert 추가 |
| D-196-7 | mutator-owns-finalize 지점 **정정**: 설계 4곳 + `qfile_unify_types`, DISTINCT agg/analytic 도메인 확정 4곳, 해시 GROUP BY 부분 리스트 2곳, RETURN_GENERATED_KEYS 1곳, `qexec_setup_list_id`(손으로 만든 1컬럼 리스트 → `qfile_type_list_alloc`). ADR 0016 §1.3 각주. | 구현 조사·smoke 크래시로 발견. | — |
| D-196-8 | 커서: `current_tuple_value_index/_p` → 비소유 슬롯 `current_slot`. 커서 이동마다 `tpl=NULL`로 리셋(mutator-owns-reset), 첫 컬럼 읽기에서 `set_tuple(current_tuple_p)`. | 소유 버퍼(`tuple_record`)와 페이지 튜플을 한 슬롯이 가리킬 수 없음. | — |
| D-196-9 | filler-owns-bind: `qfile_retrieve_tuple`이 채운 레코드를 스캔의 type_list에 bind(`qfile_slot_fill`). (#189 리뷰 반영, PR-1a 커밋 1599122b0) | 호출자마다 새로 만드는 지역 레코드에 bind를 맡기면 누락 반복. | — |
| D-196-10 | 일괄 접근자 별도 API 없음 — 슬롯 캐시로 순차 `read_value`가 O(n). | — | — |
| D-196-11 | VAR 판정 = `pr_type::has_computed_disk_size()`(lengthmem ∨ lengthval). `is_size_computed()`의 쌍 assert는 DB_TYPE_OBJECT(값 쪽 length만 존재, VOBJ→집합)에서 터짐. **OBJECT 컬럼은 새 포맷에서 VAR**. #180 댓글. | smoke DELETE 크래시. | — |

## smoke가 잡은 미바인드/미finalize 지점 (라운드별)

1. `qexec_setup_list_id`: 손으로 malloc한 1컬럼 type_list → finalize가 `hdr_size` assert. → `qfile_type_list_alloc`.
2. `pr_type::is_size_computed()` 쌍 assert (OBJECT). → D-196-11.
3. CONNECT BY: `qexec_check_for_cycle`/`qexec_compare_valptr_with_tuple`, `query_opfunc.c` SYS_CONNECT_BY_PATH 계열 3곳 — raw `tpl`을 슬롯에 넣으며 bind 없음. 호출자의 `type_list`는 INPUT 리스트라 `finalized=false` → 스캔 사본 `s_id.list_id.type_list`에 bind.
4. 해시조인 in-memory 엔트리 payload(`hjoin_probe_key`) → `qfile_slot_fill(..., &list_scan_id->list_id.type_list)`. px 해시조인 페이지 튜플 6곳 + `tpl += len` 직접 전진 3곳(setter 우회, D-182-5 위반) 함께 수정.
5. px 리스트 슬롯 반복자 출력 레코드(`m_tplrecp`) bind 전달.

교훈: **접근자 진입 assert(`tl && finalized`)가 PR-1b의 핵심 검출 장치**다. smoke 12항목만으로 5라운드에 걸쳐 5계열을 잡았고, CTP 전수가 최종 게이트.

## CTP 전수 1차(2026-09-03 15:35, `--abort-on-core` 없이 실행 → 15분 만에 코어 281개·600GB, 강제 중단)

shard 별 sonnet 에이전트 병렬 분석(gdb, `set solib-search-path <build>/lib` 필요 — 컨테이너 내부 경로 때문):

| shard | assert | 원인 | 크래시 테스트 |
|---|---|---|---|
| 2,3,4,6 | `qfile_slot_locate`: `rec->tl != NULL` (tl=NULL, size=16352, off=0 → bind/set_tuple 미경유) | `scan_next_index_scan`의 multi-range 최적화/TOP-N 경로: `scan_dump_key_into_tuple`이 채운 `multi_range_opt.tplrec`를 `tplrec.tpl = …` 직접 대입으로 fetch에 전달 | `_026_asc_desc_idx/CUBRID210*.sql`, `_03_index_keylimit/_006_keylimit_multiple_ranges_1.sql`, `_14_range_search_optimization/_001_top_n_asc_index.sql`, `_06_optimizing_limit*/_58,_59,_67,_68`, `bug_bts_4563_2.sql` |
| 5 | `qfile_open_list_scan`: D-181-7 `qfile_type_list_check` (type_cnt=0, domp=NULL, finalized=false) | 상관 파생 테이블이 결과를 내지 않아 한 번도 open/finalize되지 않은 XASL list_id를 스캔 | `_32_damson/cbrd_23696/…correlated_subquery_and_in-line_view.sql`, `_33_elderberry/cbrd_24042/cbrd_24101/impossibility/correlated.sql` |

수정: (a) `qfile_slot_fill (&tplrec, mro.tpl, &indx_cov.list_id->type_list)`, `indx_cov->tplrec` 초기화·bind; (b) `qfile_type_list_check`는 빈 리스트(type_cnt 0·domp NULL)를 finalize 여부와 무관하게 통과.

부수 관찰(범위 밖, 별도 이슈 후보): shard 2의 첫 크래시 뒤 **복구(병렬 REDO)** 중 `spage_find_empty_slot_at` `slot_id(3) > num_slots` assert (`heap_rv_mvcc_redo_insert`, `rcv.reference_lsa = -1/-1`). 로그 `.git_ignored_dir/scratch/cbrd27365/core2_bt_fixed.log`, `core2_vars.log`.

## CTP 전수 2차(2026-09-03 16:29, 수정 후, `--abort-on-core` 기본 ON)

AGGREGATE: **17,457 중 17,451 통과 / 6 실패 / 코어 0**, 감시 미발동, shard 당 5~8분. 실패 6건은 모두 **testcases 최신화 문제**(develop c5645f9 → 8e355ff59·testcases a2c76731d 사이의 답안 갱신): `cbrd_24906_1/2`, `_01_covering_index_01`(CBRD-27176 GROUP BY 종속 컬럼 제거 트레이스), `cbrd_25447`(parallel gather 모드 문구)은 갱신된 답안과 **바이트 일치**; `cbrd_25596`·`cbrd_25486_05`는 케이스 .sql 자체가 CBRD-27258에 맞춰 바뀐 것이라 `just ctp-sql-isolated _35_fig_cake/grant_revoke_redefine` 재실행 **17/17 통과**로 확인. 접근자 치환에 의한 회귀는 0건.

## CTP 전수 3차(develop 8e355ff59 머지 후, 빌드 11.5.0.2527)

smoke 2회 PASS/PASS, **CTP 17,457 / 17,457 통과, 실패 0, 코어 0**(`ctp_full_pr1b_merged.log`).

## 범위 밖 관찰 (수정하지 않음)

- `cursor_prefetch_first_hidden_oid`: 첫 컬럼이 NULL이면 `continue`가 `current_tuple`을 전진시키지 않아 같은 튜플을 재검사(잠재 결함, 결과에는 무해). 원동작 유지.
- `qdata_tuple_to_val_list`: 호출자 없음(dead code). 접근자로 변환만 함.
- `hjoin_fetch_key`: 이중 루프를 단일 루프로 바꾸며 들여쓰기 유지를 위해 블록 한 겹을 남김(포맷터 대상).
- 설치본 `~/optdebug/CUBRID-cbrd27365`의 실제 포트는 1523/33000(등록부 claim 1700/36000과 불일치 → claim 해제).

## PR-2 로 넘기는 것

- 조립기(D-182-11)로 `qfile_legacy_put_value` 호출 지점 교체: `qfile_save_merge_tuple`, `qfile_make_sort_key`(P/A), `qfile_sort_get_next_parallel`, `qexec_merge_tuple`, `hjoin_merge_tuple`.
- 정렬 레코드 본문 리더(D-182-14): `list_file.c`의 SORT_REC 헤더 워크(`qfile_generate_sort_tuple`, `qfile_compare_partial_sort_record`, interpolation 비교 등).
- 라이터 측 "값 타입 == `domp[col]` 타입" 일관성 assert — 새 포맷은 열 레이아웃이 `domp[col]`에서 나오므로 필수(PR-1b의 `qfile_slot_overwrite_value` 도메인 assert가 첫 프로브).
- backward 플래그·`hdr_size` 4 도입(D-181-8), `qfile_scan_prev`/`cursor_prev_tuple`의 `hdr_size==8` assert.
