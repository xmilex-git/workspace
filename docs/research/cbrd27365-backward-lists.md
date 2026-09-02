# CBRD-27365 — 역방향 스캔이 필요한 리스트 전수 분류 (`backward_capable` 근거표)

- 티켓: xmilex-git/workspace#184 (맵 #179)
- 대상 소스: `/home/cubrid/dev/cubrid` @ `77bd76bab` (develop, 2026-09-02 기준)
- 모든 인용은 `src/` 기준 `파일:행`. 소스는 읽기만 했고 수정하지 않았다.

## 0. 결론 (먼저)

1. **역방향으로 튜플을 걷는 코드는 서버·클라이언트 합쳐 정확히 두 곳**이다. 둘 다 `QFILE_GET_PREV_TUPLE_LENGTH`로 같은 페이지 안의 이전 튜플로 후진한다.
   - 서버 `qfile_scan_prev` — `list_file.c:5214-5215`
   - 클라이언트 `cursor_prev_tuple` — `cursor.c:1590-1591`
   페이지 경계에서는 둘 다 이전 페이지 헤더의 `QFILE_GET_LAST_TUPLE_OFFSET`을 쓰므로(`list_file.c:5239`, `cursor.c:925`) prev-length 없이도 동작한다. 즉 **prev-length 4B는 "같은 페이지 안에서 한 칸 뒤로"에만 쓰인다.**
2. `qfile_scan_prev`에 도달하는 서버 소비자는 **4종**뿐이다.
   - (S1) **정렬 입력 리스트의 un-read**: `qfile_make_sort_key`가 sort record가 버퍼에 안 맞으면(`SORT_REC_DOESNT_FIT`) 방금 읽은 튜플을 되돌리기 위해 `qfile_scan_prev`를 부른다(`list_file.c:3633`). **정렬되는 모든 리스트가 잠재적 역방향 소비자**라는 뜻이며, 이 항목이 가장 큰 숨은 소비자다. 다행히 이 후진은 "직전에 읽은 그 튜플"로만 돌아가므로 `qfile_save_current_scan_tuple_position`/`qfile_jump_scan_tuple_position`(`list_file.c:5295`, `5369`)로 대체 가능 → **정렬 입력은 forward-only로 만들 수 있다.**
   - (S2) **merge join의 inner 리스트** — `qexec_merge_list`의 `QEXEC_MERGE_PREV_SCAN`(`query_executor.c:6152`, 사용 6481~6594) 및 `qexec_merge_list_outer`가 `scan_prev_scan`→`scan_prev_scan_local`→`qfile_scan_list_prev`로 후진(`query_executor.c:6187`, `scan_manager.c:7862`). merge join은 hidden 파라미터 `optimizer_enable_merge_join` 기본값 **false**(`system_parameter.c:3542-3548`)지만 켤 수 있으므로 살아 있는 경로다.
   - (S3) **분석함수(analytic) 그룹/값 리스트** — `qexec_analytic_value_advance`가 `group_list_id`/`value_list_id`를 앞뒤로 움직인다(`query_executor.c:23906`, `23940`).
   - (S4) 그 외 서버 소비자는 **없다**. hash join, 집계 DISTINCT/ORDER BY 리스트, CONNECT BY, CTE, covering index, px 병렬 경로, method/PL 커서, 네트워크 페이지 전송은 전부 `qfile_scan_list_next` 또는 페이지 내 정방향 워크만 쓴다(§2 표).
3. **클라이언트로 나가는 최종 결과 리스트는 항상 backward_capable이어야 한다.** CAS의 scrollable fetch는 `db_query_seek_tuple`을 쓰고(`cas_execute.c:2664`, `5071`, `5308`, `1169`), 그 내부의 상대 이동 루프가 음수 방향이면 `db_query_prev_tuple`→`cursor_prev_tuple`을 부른다(`db_query.c:2707`, `2762`). JDBC `absolute/relative/previous`가 모두 이 경로다. 클라이언트 측 리스트는 오직 최종 결과 리스트이므로 **클라이언트에 플래그를 전달할 필요는 없다**(`or_pack_listid`에 플래그 필드 없음, `object_representation.c:5262-5290`).
4. **"클라이언트로 나간다"를 생성 시점에 알려주는 기존 플래그는 없다.** `QFILE_FLAG_RESULT_FILE`은 `XASL_TOP_MOST_XASL && XASL_TO_BE_CACHED`일 때만 켜지고(`query_executor.c:5424-5428` 등), `XASL_TO_BE_CACHED`는 결과 캐시가 허용될 때만 세팅된다(`query_manager.c:1206-1209`). 따라서 RESULT_FILE ≠ 최종 결과. 생성 시점 판별의 실질적 근거는 **`XASL_IS_FLAGED (xasl, XASL_TOP_MOST_XASL)`**(세터 `xasl_generation.c:23695`, `24900`)이다. 단, 최종 결과 리스트는 자식 xasl의 리스트가 `qfile_copy_list_id`로 옮겨져 되는 경우(CTE 재귀 union, UNION, hash join, px 병렬)가 있어 TOP_MOST만으로는 누락 위험이 있다 → §5의 방어 assert로 보강.
5. **플래그 보존성**: `qfile_copy_list_id`는 구조체 `memcpy`(`list_file.c:475`)이므로 `QFILE_LIST_ID`에 넣은 비트는 copy/clone/holdable/list-cache 경로 전부에서 자동 보존된다. 반대로 `qfile_duplicate_list`(`list_file.c:4939`)는 **페이지 raw 복사**(`qfile_copy_list_pages`)이므로 원본과 같은 포맷을 갖게 되며, 새 list_id의 플래그는 **원본에서 상속**시켜야 한다(호출자 `query_manager.c:1609`가 `QFILE_FLAG_RESULT_FILE`만 넘김). `qfile_connect_list`/`qfile_append_list`(`list_file.c:3134`, `2957`)는 페이지 체인을 이어 붙이므로 **두 리스트의 포맷이 같아야 한다**(assert 필요).

### 권고 규칙 (요약)

- `backward_capable`은 **기본 false**. 다음 세 경우에만 true:
  - **R-A (최종 결과)**: 리스트의 소유 xasl이 `XASL_TOP_MOST_XASL`이면 true (TO_BE_CACHED/orderby 여부 무관). 현재 RESULT_FILE 조건식을 계산하는 8개 지점 + hash join(`query_hash_join.c:838`) + px 결과 병합(`px_scan_result_handler.cpp:246`) + 정렬 출력(`query_executor.c:4278`) + 병렬 정렬 워커(`external_sort.c:6499`, 이미 `ori flag | ...` 상속) + UNION/CTE(`query_executor.c:15522`, `18455`)에 적용. 자식 xasl 리스트가 `qfile_copy_list_id`로 최상위에 승격되는 경로는 부모의 TOP_MOST를 자식 open 시점에 볼 수 없으므로, **xasl_generation에서 MERGELIST/UNION/CTE의 자식 xasl에 "결과 승격 가능" 표시를 내려주거나, 단순히 `qmgr_process_query:1232` 직후 `assert (list_id->backward_capable)`로 누락을 CTP에서 잡는다.**
  - **R-B (서버 역방향 소비자)**: merge join의 두 입력 xasl 리스트(`ptqo_to_merge_list_proc`에서 `outer_xasl`/`inner_xasl`에 XASL 플래그로 표시 → `query_executor.c:15118` open 시 반영), 분석함수 그룹/값 리스트 4지점(`query_executor.c:22377`, `22397`, `22497`, `22512`).
  - **R-C (정렬 입력)**: `qfile_make_sort_key`의 `qfile_scan_prev`(`list_file.c:3633`)를 save/jump로 교체해 **정렬 입력을 forward-only로 유지**한다. 교체하지 않으면 "정렬되는 모든 리스트"가 backward가 되어 절감 효과가 거의 사라진다.
- 방어: `qfile_scan_prev` 진입 시 `assert (scan_id_p->list_id.backward_capable)` + release에서는 `S_ERROR`; `qfile_connect_list`/`qfile_append_list`/`qfile_duplicate_list`에서 포맷 일치 assert; `cursor_prev_tuple`은 최종 결과만 다루므로 변경 불필요(디버그용으로 `or_pack_listid`에 1B 플래그를 실어 assert만 추가하는 선택지는 있음).

---

## 1. 역방향 읽기 경로 전수 (b)

### 1.1 페이지 내 후진 프리미티브 (`QFILE_GET_PREV_TUPLE_LENGTH` 전체 사용처)

| 위치 | 코드 | 비고 |
|---|---|---|
| `query_list.h:246-247` | 매크로 정의 (`OR_GET_INT (tpl + 4)`) | 헤더 8B = length 4B + prev_length 4B (`query_list.h:229-231`) |
| `list_file.c:1598` | `QFILE_PUT_PREV_TUPLE_LENGTH (page_p, list_id_p->lasttpl_len)` in `qfile_add_tuple_to_list_id` | **유일한 writer**. 모든 튜플 쓰기 경로(1641, 1892, 1952, 2040, 2119, 2167, 6985)가 이 함수를 경유 |
| `list_file.c:5214-5215` | `qfile_scan_prev`: `curr_offset -= PREV_LEN; curr_tpl -= PREV_LEN` | 서버 유일 reader. `curr_tplno > 0`일 때만; 페이지 첫 튜플이면 이전 페이지 헤더 `LAST_TUPLE_OFFSET` 사용(5238-5239) |
| `cursor.c:1590-1591` | `cursor_prev_tuple`: 동일 산술 | 클라이언트 유일 reader. 페이지 경계는 `cursor_fetch_page_having_tuple (..., LAST_TPL)`→`cursor_point_current_tuple`이 페이지 헤더 `LAST_TUPLE_OFFSET` 사용(`cursor.c:922-926`) |

`lasttpl_len`(`QFILE_LIST_ID`, `query_list.h:440`)은 prev-length를 쓰기 위한 상태값이며 `or_pack_listid`로 클라이언트에도 전달된다(`object_representation.c:5284`, `5372`). forward-only 리스트에서는 죽은 값이 되지만 무해하다.

### 1.2 `qfile_scan_prev` 호출자

| 호출자 | 위치 | 어떤 리스트를 후진하나 | 조건 |
|---|---|---|---|
| `qfile_scan_list_prev` | `list_file.c:5579-5582` | 공개 API (아래 3 호출자) | — |
| `qfile_make_sort_key` | `list_file.c:3633` | **정렬 입력 리스트**(`qfile_sort_list_with_func`의 `list_id_p`, 병렬 정렬 워커는 `qfile_clone_list_id`한 동일 리스트 `external_sort.c:6639`, `6774`) | sort record가 `key_record_p->area_size`보다 크면 한 칸 되돌려 `SORT_REC_DOESNT_FIT` 반환. `sort_inphase_sort`가 run을 flush한 뒤 `get_fn`을 다시 불러 같은 튜플을 재읽음(`external_sort.c:2033-2060`) |

### 1.3 `qfile_scan_list_prev` 호출자

| 호출자 | 위치 | 후진되는 리스트 | 조건 |
|---|---|---|---|
| `QEXEC_MERGE_PREV_SCAN` (→`QEXEC_MERGE_REV_SCAN_PVALS`) | `query_executor.c:6150-6155`, 사용 `6478`, `6497`, `6532-6594` | `qexec_merge_list`의 **inner 리스트** = `inner_xasl->list_id` (`query_executor.c:7345`) | inner merge join, 같은 키 그룹 내 재스캔 |
| `scan_prev_scan_local` | `scan_manager.c:7862` (S_LIST_SCAN 전용, 7823 주석) | `qexec_merge_list_outer`의 inner `SCAN_ID` — `inner_spec_list` 위 list scan (`query_executor.c:7359-7362`) = `inner_xasl->list_id` | outer merge join, `QEXEC_MERGE_OUTER_PREV_SCAN_PVALS`(`6187`)→`scan_prev_scan`(`scan_manager.c:7964`) |
| `qexec_analytic_value_advance` | `query_executor.c:23906` | `func_state->value_list_id` (open `22512`; 또는 `22397`의 `order_list_id`가 `22481`에서 이관) | 분석함수 윈도우 이동(amount<0) |
| `qexec_analytic_value_advance` | `query_executor.c:23940` | `func_state->group_list_id` (open `22497`; 또는 `22377`의 `group_list_id`가 `22475`에서 이관) | 동일 |

### 1.4 `S_BACKWARD` 사용처 정리

| 위치 | 의미 | 리스트 관련? |
|---|---|---|
| `query_executor.c:6481, 6510, 6528, 6532-6594` | `qexec_merge_list` 지역 변수 `direction` — inner 리스트 후진 모드 | **예** (S2) |
| `query_executor.c:7042, 7071, 7089, 7093-7182, 7221` | `qexec_merge_list_outer` 동일 | **예** (S2); 7221 분기는 `scan_jump_scan_pos`(위치 점프, prev-length 불필요) |
| `scan_manager.c:4917, 5135, 5231`, `px_scan.cpp:206, 726, 1157` | index scan의 OID 순회 방향 / heap scan 방향 토글 | 아니오 (리스트 파일과 무관) |
| `scan_manager.c:7810` | `S_END`일 때 position을 BEFORE/AFTER로 정하는 불변식 | 간접 |

### 1.5 클라이언트 경로 (`cursor_prev_tuple`에 도달하는 API)

| API | 위치 | 호출자 |
|---|---|---|
| `db_query_prev_tuple` | `db_query.c:2296-2314` | 직접 호출자 없음(compat 외부). `db_query_seek_tuple` 내부에서만 사용 |
| `db_query_seek_tuple` | `db_query.c:2600-2770` — 시작점(first/last/current) 중 가까운 곳을 고른 뒤 `rel_n<0`이면 `db_query_prev_tuple` 루프(`2707`), 또 다른 분기 `2762` | **CAS** `cas_execute.c:1169`(max_row 위치 이동), `2664`(cursor update), `5071`, `5308`(fetch with cursor_pos — JDBC scrollable fetch/absolute/relative/previous) |
| `db_query_last_tuple` | `db_query.c:2490` → `cursor_last_tuple` (`cursor.c:1696`) | `checksumdb.c:1358`, seek의 "end 기준" 분기. 페이지 헤더 `LAST_TUPLE_OFFSET`로 위치만 잡음 → prev-length 불필요, 하지만 이어지는 seek 루프가 prev를 쓸 수 있음 |
| `db_query_set_tplpos` | `db_query.c:2905-2925` | 저장된 (vpid, tpl_no, tpl_off)로 점프 — prev-length 불필요 |

결론: **CAS를 거치는 모든 SELECT 결과는 언제든 뒤로 읽힐 수 있다.** 최종 결과 리스트는 조건 없이 backward_capable이어야 한다.

---

## 2. `qfile_open_list` 호출 지점 전수표 (a) — 44곳

분류 기호: **B-CLIENT** = 최상위 xasl의 결과가 될 수 있어 클라이언트에서 후진 가능 / **B-SERVER** = 서버 코드가 후진 스캔 / **S** = 정렬 입력이 되어 `qfile_make_sort_key`의 un-read 대상(R-C 적용 시 F로 전환) / **F** = 정방향 전용.

### 2.1 `list_file.c` (3)

| # | 위치 (함수) | 리스트 내용 | 소비자 / 읽기 방식 | 분류 |
|---|---|---|---|---|
| 1 | `2769` `qfile_combine_two_list` | UNION/INTERSECT/DIFFERENCE 결과 | 호출자 `query_executor.c:15522`(UNION_PROC → `15528`에서 `xasl->list_id`로 copy), `18455`(CTE 재귀 union), `query_hash_join.c:1900`(hash join 파티션 결과 병합). 이후 정방향 스캔 또는 클라이언트 | **B-CLIENT**(15522/18455가 TOP_MOST일 때) — `flag` 인자로 상속됨 |
| 2 | `4656` `qfile_sort_list_with_func` | 정렬 출력 | 호출자 `query_executor.c:4291`(ORDER BY/DISTINCT — 최상위면 최종 결과), `19189`(CONNECT BY order siblings — 이후 정방향), `list_file.c` 내부 `qfile_sort_list`(`4791`; aggregate `query_aggregate.cpp:1409`, analytic `query_analytic.cpp:835`, set-op용 `2753`) | **B-CLIENT**(4291이 TOP_MOST) 그 외 F. 플래그는 `flag` 인자로 전달 가능 |
| 3 | `4939` `qfile_duplicate_list` | 원본 페이지 raw 복사 | `query_manager.c:1609` — 결과 캐시에 넣기 위해 최종 결과를 FILE_QUERY_AREA로 복제; 복제본이 클라이언트에 반환됨(`1614`) | **B-CLIENT**; 포맷은 원본과 동일하므로 **플래그를 원본에서 상속**해야 함 |

### 2.2 `query_executor.c` (23)

| # | 위치 (함수) | 리스트 내용 | 소비자 | 분류 |
|---|---|---|---|---|
| 4 | `5432` `qexec_groupby` | GROUP BY 출력(`after_groupby_list`) | `5459`/`5505`/`5697`에서 `list_id`(= `xasl->list_id`)로 copy → 최종 결과 또는 이후 ORDER BY 정렬 입력 | **B-CLIENT**(TOP_MOST 조건식 이미 존재 `5424`) / 아니면 S |
| 5 | `6280` `qexec_merge_list` | inner merge join 출력 | `7385`에서 `xasl->list_id`로 copy | **B-CLIENT**(TOP_MOST, `7336-7340` 조건식) / 아니면 F 또는 S |
| 6 | `6715` `qexec_merge_list_outer` | outer merge join 출력 | 동일 | 동일 |
| 7 | `15056` `qexec_start_mainblock_iterations` CONNECTBY_PROC | CONNECT BY 결과(자식 프로시저) | 부모 BUILDLIST가 list scan으로 정방향 소비; `qfile_set_tuple_column_value`로 in-place 갱신 | **F** |
| 8 | `15118` 〃 BUILDLIST_PROC | BUILDLIST 본체 리스트 | 최상위면 클라이언트; 서브쿼리/조인 입력이면 정방향 list scan; **MERGELIST_PROC의 outer/inner xasl이면 `qexec_merge_list*`가 후진**; ORDER BY가 있으면 정렬 입력 | **B-CLIENT**(TOP_MOST) / **B-SERVER**(merge join 자식) / S / F — 가장 분기 많은 지점 |
| 9 | `15158` 〃 BUILD_SCHEMA_PROC | 스키마 조회 결과 | 클라이언트 | **B-CLIENT** |
| 10 | `15322` `qexec_end_buildvalueblock_iterations` | BUILDVALUE 단일 튜플 | `15338` copy → 클라이언트 | **B-CLIENT**(조건식 `15316`) |
| 11 | `17697` `qexec_execute_connect_by` listfile2 | 현재 자식 레벨 | `17757` 정방향 scan; 다음 레벨의 listfile1로 교대 | **F** |
| 12 | `17706` 〃 listfile2_tmp | order siblings by 임시 | `19189` 정렬 입력 → `18054` 정방향 | **S** |
| 13 | `17772` 〃 indx_cov.list_id 재생성 | covering index 키 버퍼 | `scan_manager.c:6759/6822/6892` 정방향 | **F** |
| 14 | `18117` 〃 listfile2_tmp 재생성 | 동일 #12 | 동일 | **S** |
| 15 | `18136` 〃 listfile2 재생성 | 동일 #11 | 동일 | **F** |
| 16 | `19610` `qexec_start_connect_by_lists` start_with_list_id | START WITH 결과 | `17690` listfile1로 사용 → 정방향; order siblings 있으면 정렬 입력 | **F** / S |
| 17 | `19626` 〃 input_list_id | CONNECT BY 입력 | 정방향 list scan | **F** |
| 18 | `21544` `qexec_groupby_index` | 인덱스 기반 GROUP BY 출력 | `21564`/`21702` copy → `xasl->list_id` | **B-CLIENT**(단, 이 지점은 RESULT_FILE 조건식이 없음 `21541` — TOP_MOST 검사 추가 필요) |
| 19 | `22056` `qexec_execute_analytic` interm_list_id | 분석함수 중간 파일 | 다음 iteration 정렬 입력/정방향 | **S** / F |
| 20 | `22089` 〃 output_list_id | 분석함수 출력 | `is_last`면 `22257` copy → 결과 | **B-CLIENT**(조건식 `22072`) / S |
| 21 | `22377` `qdata_setup_analytic_eval_list` group_list_id | (group tuple count, nn count) | `22475`에서 func_state로 이관 → `23940` **후진** | **B-SERVER** |
| 22 | `22397` 〃 order_list_id | (sort key count, value) | `22481` 이관 → `23906` **후진** | **B-SERVER** |
| 23 | `22497` `qexec_initialize_analytic_function_state` group_list_id | 동일 #21 | `23940` **후진** | **B-SERVER** |
| 24 | `22512` 〃 value_list_id | 동일 #22 | `23906` **후진** | **B-SERVER** |
| 25 | `28096` `qexec_alloc_agg_hash_context` part_list_id | 해시 집계 partial | `28098` sorted_part_list_id의 정렬 입력 | **S** |
| 26 | `28098` 〃 sorted_part_list_id | 정렬된 partial | 정방향 | **F** |

### 2.3 `scan_manager.c` (3)

| # | 위치 (함수) | 리스트 내용 | 소비자 | 분류 |
|---|---|---|---|---|
| 27 | `747` `scan_init_indx_coverage` | covering index 키 버퍼(`QFILE_FLAG_USE_KEY_BUFFER`) | `6759/6822/6892` `qfile_scan_list_next` | **F** |
| 28 | `4974` `scan_reset_scan_block` | 동일, 재생성 | 동일 | **F** |
| 29 | `6637` `scan_next_index_scan` | 동일, 재생성 | 동일 | **F** |

(index scan의 `S_BACKWARD`(4917, 5135)는 OID 배열 순회 방향이며 이 리스트의 스캔 방향이 아님.)

### 2.4 `query_hash_join.c` (5) / `px_hash_join*.cpp` (2)

| # | 위치 (함수) | 리스트 내용 | 소비자 | 분류 |
|---|---|---|---|---|
| 30 | `query_hash_join.c:502` `hjoin_outer_fill_null_values` | outer join NULL 채움 결과 | `1900` combine 또는 `1921/1935` append/connect → `268` `xasl->list_id`로 copy | **B-CLIENT**(TOP_MOST) — `manager->qlist_flag`(`838`)에 비트 추가 |
| 31 | `1435` `hjoin_prepare_partition` outer_part | outer 파티션 | `3132/3168` build 정방향, 페이지 워크 | **F** |
| 32 | `1442` 〃 inner_part | inner 파티션 | 동일 | **F** |
| 33 | `1769` `hjoin_split_qlist` temp_part | 재분할 임시 | `1746/1801` append → 파티션 | **F** (append 대상과 포맷 일치 필요) |
| 34 | `3365` `hjoin_probe` | probe 결과(비병렬) | `268` copy → `xasl->list_id` | **B-CLIENT**(TOP_MOST) |
| 35 | `px_hash_join.cpp:333` | 병렬 probe 컨텍스트 결과 | `1921/1935` append/connect → `268` | **B-CLIENT**(TOP_MOST); connect 대상과 포맷 일치 |
| 36 | `px_hash_join_task_manager.cpp:416` | 병렬 재분할 임시 | `386/477` append | **F** |

hash join 코드에는 `qfile_scan_list_prev`가 전무하며 페이지 워크(`px_hash_join_task_manager.cpp:263-290`)도 `QFILE_GET_TUPLE_LENGTH`로 정방향만 진행한다.

### 2.5 `external_sort.c` (1)

| # | 위치 | 리스트 내용 | 소비자 | 분류 |
|---|---|---|---|---|
| 37 | `6499` `sort_put_result_for_parallel` | 병렬 정렬 워커 출력(첫 워커는 원 출력 파일 재사용) | `5692/5702` `qfile_append_list`/`qfile_connect_list`로 origin에 이어 붙임 | origin과 동일 — `ori_sort_info_p->flag | QFILE_NOT_USE_MEMBUF`로 **이미 플래그 상속**, 새 비트도 자동 전파 |

### 2.6 `query_aggregate.cpp` / `query_analytic.cpp` (2)

| # | 위치 | 리스트 내용 | 소비자 | 분류 |
|---|---|---|---|---|
| 38 | `query_aggregate.cpp:98` `qdata_process_distinct_or_sort` | 집계 DISTINCT/ORDER BY 값 누적 | `1409` `qfile_sort_list` 정렬 입력 → `1469`/`2723` 정방향 | **S** |
| 39 | `query_analytic.cpp:85` `qdata_initialize_analytic_func` | 분석함수 DISTINCT 값 | `835` 정렬 입력 → `888` 정방향 | **S** |

### 2.7 `px_scan_result_handler.cpp` (5)

| # | 위치 | 리스트 내용 | 소비자 | 분류 |
|---|---|---|---|---|
| 40 | `246` `write_initialize` (MERGEABLE_LIST) | 워커별 결과 조각 | `591/612` `qfile_connect_list`로 병합 → `623` `xasl->list_id`로 copy | **B-CLIENT**(curr_xasl TOP_MOST); connect 대상과 포맷 일치 |
| 41 | `1047` list_id_header 스트리밍 리스트 | 워커→리더 파이프 | `785` `qfile_scan_list_next` | **F** |
| 42 | `1394` 집계 DISTINCT | 워커별 집계 값 | `2274-2438` copy/connect → 원 agg list → 정렬 입력 | **S** |
| 43 | `1419` MEDIAN/PERCENTILE | 동일 | 동일 | **S** |
| 44 | `1445` GROUP_CONCAT(ORDER BY) | 동일 | 동일 | **S** |

### 2.8 집계

| 분류 | 개수 | 비고 |
|---|---|---|
| B-CLIENT 가능 | 15 (#1-6, 8-10, 18, 20, 30, 34, 35, 40) | 모두 "소유 xasl이 TOP_MOST인가"로 판별 가능. #18(`21544`)과 hash join/px는 현재 조건식 없음 |
| B-SERVER | 4 (#21-24) + #8의 merge join 자식 | 분석함수 4지점은 무조건 true; merge join 자식은 xasl 플래그로 표시 |
| S (정렬 입력) | 12 (#12, 14, 19, 25, 38, 39, 42-44, 및 #4/#8/#16의 ORDER BY 경로) | R-C(save/jump 교체) 적용 시 전부 F |
| F | 나머지 13 | covering index, CONNECT BY 작업 리스트, hash join 파티션, px 파이프 |

---

## 3. 최종 결과 리스트를 생성 시점에 식별하는 방법 (c)

### 3.1 결과가 클라이언트로 가는 경로

```
qexec_execute_query → qexec_get_xasl_list_id (query_executor.c:3602-3624: xasl->list_id를 새 QFILE_LIST_ID로 copy)
  → qmgr_process_query (query_manager.c:1232: query_p->list_id = ...; 1252: clone → 반환)
  → xqmgr_execute_query (1559 clone; 1609 결과 캐시용 duplicate)
  → network_interface_sr.cpp:5947 / 6460 or_pack_listid (+ 첫 페이지 raw 전송 5900-5917)
  → 클라이언트 cursor_open → cursor_copy_list_id (cursor.c:1234)
```

즉 **최종 결과 = 최상위 xasl(`XASL_TOP_MOST_XASL`)의 `xasl->list_id`가 가리키는 파일**이다. 그 파일은 §2의 B-CLIENT 15지점 중 하나에서 만들어져 (a) 그대로 `xasl->list_id`이거나 (b) `qfile_copy_list_id`로 옮겨진다(`5459`, `7385`, `15338`, `15528`, `18446-18522`, `22257`, `268`, `623`, `28492`, `px_query_task.cpp:188/199`).

### 3.2 기존 플래그 평가

| 후보 | 판정 |
|---|---|
| `QFILE_FLAG_RESULT_FILE` (`query_list.h:521`) | **부적합.** `TOP_MOST && TO_BE_CACHED && (orderby 없음 …) && !DISTINCT`일 때만 세팅(`query_executor.c:5424-5428`, `15109-15114`, `15316-15320`, `7336-7340`, `15514-15518`, `22072-22077`, `4278`). `TO_BE_CACHED`는 결과 캐시 허용 시에만(`query_manager.c:1206-1209`). 용도는 temp 파일 종류(FILE_QUERY_AREA) 선택(`list_file.c:1235-1237`) |
| `XASL_TOP_MOST_XASL` (`xasl.h:523`) | **적합(1차 기준).** `pt_to_xasl`(`xasl_generation.c:23695`)과 `24900`에서 최상위에만 세팅, 자식은 `19186`에서 해제. 리스트 open 지점 대부분이 이미 `xasl`을 손에 들고 있음 |
| `list_id->is_result_cached` (`query_list.h:449`) | 서브쿼리 결과 캐시 마킹용(`28494`), 무관 |
| `QMGR_QUERY_ENTRY.is_holdable` (`query_manager.c:1530-1536`) | 실행 후 세션에 보관할지 여부. 리스트 포맷과 무관하며 `xsession_store_query_entry_info`(`2359`)는 `QFILE_LIST_ID`를 그대로 넘기므로 구조체 비트는 보존됨 |

### 3.3 TOP_MOST 기준의 빈틈 (자식 리스트가 결과로 승격되는 경우)

| 경로 | 위치 | 설명 |
|---|---|---|
| UNION/DIFFERENCE/INTERSECT | `15522` | `qfile_combine_two_list`가 **새 리스트**를 만들므로 `ls_flag`에 TOP_MOST 반영하면 충분 |
| CTE 재귀 union | `18446`, `18463`, `18472`, `18506`, `18522` | `non_recursive_part->list_id`(자식 BUILDLIST, `15118`에서 open)가 그대로 `xasl->list_id`가 되는 분기 존재 → 자식 open 시 부모 TOP_MOST를 모름 |
| hash join | `query_hash_join.c:268` | `single_context->list_id`(`502`/`3365`/px `333`) → `xasl->list_id`. `hjoin` 진입 시 `xasl` 접근 가능(`268`)하므로 `qlist_flag`(`838`)에 반영 가능 |
| px 병렬 결과 | `px_scan_result_handler.cpp:623`, `px_query_task.cpp:188/199` | 워커 리스트 connect 후 copy. `write_initialize`가 `curr_xasl`을 받음(`228`) → 반영 가능 |
| 정렬 출력 | `4291` | 새 리스트, `ls_flag`로 반영 가능 |
| 결과 캐시 duplicate | `query_manager.c:1609` | 원본에서 상속 |

→ **권고**: 1차는 TOP_MOST 기반 `ls_flag` 계산을 공통 헬퍼로 통일하고, 2차 방어로 `qmgr_process_query:1232` 직후(또는 `qexec_get_xasl_list_id`) `assert (list_id->backward_capable)`를 두어 CTP에서 누락을 잡는다. CTE 재귀 union처럼 자식이 승격되는 곳은 자식 xasl에 플래그를 내려주거나(xasl_generation), 승격 전 `qfile_duplicate_list`류로 포맷을 맞추는 대신 **자식 리스트 자체를 backward로 열도록 부모가 표시**하는 쪽이 단순하다.

### 3.4 플래그 보존성 검증

| 연산 | 위치 | 보존 여부 |
|---|---|---|
| `qfile_copy_list_id` / `qfile_clone_list_id` | `list_file.c:469-475`, `564` | `memcpy (dest, src, sizeof (QFILE_LIST_ID))` → **자동 보존** (domp/sort_list/tpl_descr/dependent만 재설정) |
| holdable 커서 | `query_manager.c:2342-2362` (`xsession_store_query_entry_info`) | `QFILE_LIST_ID*` 포인터를 그대로 이관 → 보존 |
| list cache | `query_manager.c:1550`, `1559` | clone → 보존 |
| `qfile_duplicate_list` | `list_file.c:4939` | 새 open 후 raw 페이지 복사 → **호출자가 `flag`로 상속시켜야 함** |
| `qfile_connect_list` / `qfile_append_list` | `list_file.c:3134`, `2957` | 페이지 체인 결합. base의 `lasttpl_len`을 append의 것으로 덮음(`3090`, `3187`) → **양쪽 포맷 동일 필수** |
| `or_pack_listid` / `or_unpack_listid` | `object_representation.c:5250-5290`, `5340-5378` | 플래그 필드 없음. 클라이언트는 최종 결과만 다루므로 **불필요**(디버그 assert용으로 추가는 선택) |
| `qfile_reopen_list_as_append_mode` | `list_file.c:1377` | 기존 list_id 재사용 → 보존 |

---

## 4. 페이지 내 튜플을 걷는 그 외 reader (d)

| 코드 | 위치 | 방향 / prev-length 사용 |
|---|---|---|
| `qfile_scan_next` | `list_file.c:5136-5140` | 정방향 (`+= TUPLE_LENGTH`) |
| `qfile_reallocate_tuple` | `list_file.c:3431-3460` | 버퍼 realloc만, 워크 없음 |
| `qfile_get_tuple` / `qfile_assemble_overflow_tuple` | `4975-5060` | overflow 체인을 `QFILE_GET_OVERFLOW_VPID`로 **정방향** 순회. overflow 튜플은 페이지당 1개(`tuple_cnt==1` assert `px_hash_join_task_manager.cpp:277`)이므로 후진 시 항상 페이지 경계 분기(헤더 LAST_TUPLE_OFFSET) |
| `qfile_add_overflow_tuple_to_list` | `2142-2167` | 쓰기, 정방향; 첫 조각 헤더에 prev-length 기록(`2167`→`1598`) |
| `qfile_set_tuple_column_value` / `qfile_overwrite_tuple` | `7130`, `7258` | in-place 값 덮어쓰기, 튜플 위치는 호출자가 제공. 워크 없음 |
| `qfile_jump_scan_tuple_position` / `qfile_save_current_scan_tuple_position` | `5369`, `5295` | (vpid, offset, tplno) 절대 위치 점프 — prev-length 불필요. merge outer join(`scan_jump_scan_pos`, `7221`)과 sort의 P_sort_key original 회수에 사용 |
| `QFILE_GET_TUPLE_VALUE_HEADER_POSITION` | `query_list.h:275-284` | 튜플 내부 컬럼 정방향 워크 (포맷 변경의 본체, 이 티켓 범위 밖) |
| 클라이언트 `cursor_prefetch_first_hidden_oid` / `cursor_prefetch_column_oids` | `cursor.c:802-830`, `857-905` | 페이지 내 **정방향** 워크 |
| 클라이언트 `cursor_point_current_tuple` | `cursor.c:911-937` | LAST_TPL은 페이지 헤더 offset 사용 |
| `network_interface_sr.cpp:5905-5912`, `6412-6419` | 첫 페이지 전송 크기 계산 | 헤더 LAST_TUPLE_OFFSET + 마지막 튜플 길이. prev-length 무관 |
| `px_scan_slot_iterator_list.cpp:108-136` | 병렬 스캔 슬롯 이터레이터 | 정방향 |
| `px_scan_input_handler_list.cpp:145` | overflow 연속 페이지 skip | 정방향 |
| `px_scan_result_handler.cpp:766` | write-phase 페이지 회피 | `curr_tplno` 비교만 |
| `method_scan.cpp:267`, `pl_query_cursor.cpp:140`, `network_interface_sr.cpp:5616` | method/PL/서버측 커서 | `qfile_scan_list_next`만 |
| `query_evaluator.c:587/729/956/1132`, `query_opfunc.c:6439/7134/9504/9539` | 서브쿼리 결과 IN/EXISTS 등 | 정방향 |

→ **prev-length를 읽는 코드는 §1.1의 두 곳이 전부**다.

---

## 5. 권고 규칙과 잔여 리스크

### 5.1 `backward_capable` 설정 규칙 (open 시점)

```
D1. QFILE_LIST_ID에 bool backward_capable 추가, qfile_open_list의 flag 비트(QFILE_FLAG_BACKWARD, 예 0x1000)로 결정. 기본 false.
D2. true로 여는 곳:
    (A) 소유 xasl이 XASL_TOP_MOST_XASL인 리스트 — 결과 후보 15지점(§2.8). 조건식을 헬퍼 하나로 통일:
        ls_flag |= XASL_IS_FLAGED (xasl, XASL_TOP_MOST_XASL) ? QFILE_FLAG_BACKWARD : 0;
        (TO_BE_CACHED·orderby·DISTINCT 조건은 RESULT_FILE에만 남긴다.)
        hash join: manager->qlist_flag (query_hash_join.c:838) 에 반영; px: write_initialize (px_scan_result_handler.cpp:246) 에 반영.
    (B) MERGELIST_PROC의 outer_xasl/inner_xasl 리스트 — xasl_generation.c:14887-14888에서 자식 xasl에 새 XASL 플래그(예 XASL_LIST_BACKWARD)를 세팅하고 query_executor.c:15118에서 반영.
    (C) 분석함수 group/value 리스트 4지점(22377, 22397, 22497, 22512) — 무조건 true.
D3. 정렬 입력은 forward 유지: qfile_make_sort_key (list_file.c:3520-3634)를 "scan_next 전에 qfile_save_current_scan_tuple_position, DOESNT_FIT면 qfile_jump_scan_tuple_position"으로 바꾼다. 페이지 경계 처리는 jump가 이미 담당(5369-5460).
D4. 상속: qfile_duplicate_list는 원본의 backward_capable을 flag에 OR; external_sort.c:6499는 이미 ori flag를 상속.
D5. 방어: qfile_scan_prev 진입 assert + release S_ERROR(ER_QPROC_UNKNOWN_CRSPOS 재사용 가능);
    qfile_connect_list / qfile_append_list 에 assert (base->backward_capable == append->backward_capable);
    qmgr_process_query:1232 직후 assert (query_p->list_id->backward_capable) — 결과 승격 누락 감지.
```

### 5.2 잔여 리스크

| 리스크 | 근거 | 완화 |
|---|---|---|
| 자식 리스트가 결과로 승격되는 경로 누락(CTE 재귀 union `18446-18522`, 향후 새 PROC) | TOP_MOST를 자식 open 시점에 모름 | D5의 `qmgr_process_query` assert가 CTP 전수에서 잡음. 실패 시 `qfile_duplicate_list`로 포맷 변환하는 fallback도 가능 |
| D3 미적용 시 절감 효과 소멸 | 정렬 입력은 GROUP BY/ORDER BY/DISTINCT/집계/분석함수 전부 | D3 필수. 교체 후 `sort_inphase_sort`의 재호출 시나리오(`external_sort.c:2033-2060`) TC 필요(레코드가 버퍼 초과하는 긴 튜플 정렬) |
| `qfile_connect_list`로 이질 포맷 결합 | px 결과 병합(`591/612`), 병렬 정렬(`5692/5702`), hash join(`1921/1935`) | D5 assert; 각 지점이 같은 `flag` 소스를 쓰는지 리뷰 |
| merge join은 기본 off라 CTP 커버리지 낮음 | `optimizer_enable_merge_join=false` | TC에 `optimizer_enable_merge_join=yes` 세트를 따로 두거나, 기존 shell TC 확인 |
| 클라이언트 `cursor_prev_tuple`이 잘못된 리스트를 받는 경우 | 서버가 forward-only 리스트를 결과로 내보낸 경우에만 | D5 서버 assert로 차단. 선택적으로 `or_pack_listid`에 1B 추가해 클라이언트에서도 assert (lockstep 정책상 프로토콜 변경 허용) |
| overflow 튜플의 헤더 | 첫 조각 헤더에 prev-length 존재 | 후진 시 overflow 페이지는 항상 `curr_tplno==0` 분기 → 헤더 4B 축소 시에도 영향 없음 |
| `lasttpl_len`/`or_pack_listid`의 lasttpl_len 필드 | forward-only 리스트에서 무의미 | 그대로 두어도 무해. 정리는 후속 |

### 5.3 새로 확인된 사실 (놀라운 점)

1. **정렬 입력의 un-read**(`list_file.c:3633`)가 `qfile_scan_prev`의 실질적 최대 소비자다. 이 한 줄이 "정렬되는 모든 리스트"를 backward로 만들 수 있었고, save/jump로 제거 가능하다.
2. `QFILE_FLAG_RESULT_FILE`은 "클라이언트로 나간다"의 표식이 아니라 "결과 캐시에 넣을 수 있다"의 표식이다.
3. merge join은 hidden 파라미터로 **기본 비활성**이지만 코드는 살아 있고 inner 리스트를 후진한다.
4. 분석함수 상태 리스트 4개는 무조건 양방향이다(윈도우 프레임 이동).
5. 클라이언트 후진은 `db_query_prev_tuple` 직접 호출자가 없고 **`db_query_seek_tuple`(CAS scrollable fetch) 내부에서만** 발생한다. JDBC 사용자 관점에선 모든 SELECT가 대상.
6. prev-length writer는 `qfile_add_tuple_to_list_id`(`list_file.c:1598`) 단일 지점이다 → 포맷 전환 시 쓰기 측 변경 지점이 하나다.
