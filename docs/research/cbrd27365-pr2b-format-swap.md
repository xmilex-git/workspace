# CBRD-27365 PR-2b: 튜플 포맷 교체 — ADR 0016 §1.1 포맷으로 접근자·조립기 내부 교체 + 구 포맷 삭제 (티켓 #199, 지도 #179)

PR-2a(#190) 위에 쌓은 fork PR — `qfile_tuple_layout.{h,c}` 내부를 PG MinimalTuple식 단일 포맷
(`[len(bit31=has-null)][prev_len, backward만][널비트맵, has-null만][자연정렬 값, 가변은 1B/4B 길이 헤더]`)으로
바꾸고, `hdr_size = QFILE_FLAG_BACKWARD ? 8 : 4`, 구 포맷 매크로군을 삭제한다. 결정 ID `D-199-*`. 코드 위치는
worktree `~/dev/worktrees/cbrd27365` 브랜치 `CBRD-27365-pr2b`(베이스 `CBRD-27365-pr2a` 5b2bbb6d5).

## 진입 조건 확인 (#190 인계)

값 헤더 매크로 사용처가 `qfile_tuple_layout.h` 뿐이라는 2a의 수렴 결과는 맞았지만, **"body 포인터의 의미"가 바뀌는
것**은 매크로 grep에 잡히지 않는다. `qfile_slot_locate()`가 돌려주는 본문을 자기 손으로 `or_init + data_readval`
하는 소비자가 약 35곳(evaluator 8, cursor 4, executor 5, hash join 2, aggregate/analytic 2, hash scan 1, opfunc 1,
merge 1, 정렬 비교자 2, dump 2 …) 있었고, 새 포맷에서 가변 컬럼 본문은 `index_*` 인코딩(DIRECT) 또는 비정렬
`data_*`(SCRATCH)라 그대로 `data_readval` 할 수 없다. 그래서 2b의 diff 는 layout 파일 + 페이지 3지점을 넘어
**소비자 전수 치환**을 포함한다(§치환 목록).

## 결정

| ID | 결정 | 근거 | 되돌림 |
|---|---|---|---|
| D-199-1 | **OBJECT/OID 컬럼은 VAR/SCRATCH** (`has_index_readval()` 이지만 DIRECT 제외). 분류 함수 `qfile_col_layout_of_domain()` 한 곳. | `mr_index_writeval_object`는 pageid/slotid/volid 를 호스트 오더 raw `or_put_data` 로 쓰고, `mr_data_writeval_object`는 `or_put_oid`(네트워크 오더) 또는 클라이언트에서 VOBJ 집합 — 두 인코딩이 바이트가 다르다. 스펙 D-180-5 "index_* 는 문자열/BIT/NUMERIC" 의 원래 의도와 일치. | 서버 전용 FIXED 8B 특례(클라이언트 SA 라이터가 VOBJ 를 쓰는 경우 불가). |
| D-199-2 | **슬롯은 스크래치를 소유하지 않는다**: VAR/SCRATCH 본문은 읽을 때마다 일시 정렬 버퍼(스택 256B, 초과는 힙 즉시 해제)로 복사해 `data_readval(copy=true)` 로 디코드한다(DB_VALUE 가 바이트를 소유). 라이터·in-place 덮어쓰기·정렬 비교자·cursor OID/VOBJ prefetch 도 같은 `QFILE_SCRATCH_ACQUIRE/RELEASE`. D-182-10 "슬롯 소유 스크래치" 는 **폐기**. | 1차 smoke 에서 서버가 트랜잭션 종료 시 resource tracker(디버그 힙 누수 감시) assert 로 죽었다: 스캔이 채우는 스택 `QFILE_TUPLE_RECORD`(수십 곳, `{NULL,0}` 초기화 후 `qfile_scan_list_next` PEEK)는 닫힐 때 `qfile_slot_clear` 를 부르지 않으므로 슬롯이 할당한 스크래치가 새는데, 전 지점에 clear 를 심는 것은 leak 재발 구조다. PEEK 소비자는 모두 읽기 전 값을 clear 하고(fetch 의 `vfetch_to`, hash join key, tuple_to_val_list), SET/JSON 은 copy 와 무관하게 힙 객체라 소유권 의미 변화가 없다. 복사 대상은 리스트에 드문 타입(SET/JSON/ELO)과 8B OID 뿐. | 스캔 소유 스크래치를 레코드가 빌려 쓰는 구조(레코드에 owner 포인터 추가). |
| D-199-3 | **`qfile_add_tuple_to_list_from (list, tpl, src_hdr_size)`**: 다른 리스트에서 온 raw 튜플을 붙일 때 헤더 크기가 다르면 길이 워드만 다시 쓰고 `src+src_hdr` 이후를 그대로 복사. `qfile_add_tuple_to_list()` 는 "이 리스트용으로 조립된 튜플" 전용 래퍼. 적용: `qfile_copy_tuple`(UNION/CTE), `qfile_combine_two_list` act 함수(lhs/rhs hdr 전달), 정렬 P 경로 put(list_file·orderby_num put_fn; 오버플로 튜플은 hdr 다르면 `qfile_get_tuple` 후 append). 해시조인 파티션·`qfile_duplicate_list` 는 `QFILE_LIST_BACKWARD_FLAG(src)` 로 헤더 상속. | `data_off(8)-data_off(4) = ALIGN4(8+b)-ALIGN4(4+b) = 4` 항상 → 비트맵·패딩·값 영역은 바이트 동일. 최종 결과(A, backward)가 forward 자식들의 UNION/정렬 출력인 경우가 흔해 헤더 재작성 없이는 오손. | 자식 리스트에도 부모의 backward 플래그 전파(리스트 크기 +4B/튜플). |
| D-199-4 | **`qfile_generate_sort_tuple(..., out_tl)`**: A_sort_key 로 전체 튜플을 재조립할 때 `key_tl`(키 순서) 대신 출력 리스트의 `type_list`(리스트 컬럼 순서)로 조립. 호출자 4곳(list_file BIG 경로, orderby_num put_fn, hash GROUP BY put_next 2곳). | `qfile_sort_rec_a_sources()` 는 src 를 리스트 컬럼 순서로 놓지만 `key_tl.domp[i] = domp[key[i].col]` 은 키 순서. 2a(자기 기술 포맷)에서는 도메인 순서가 바이트에 영향이 없어 드러나지 않았다. | — |
| D-199-5 | **`qfile_add_item_to_list()` 삭제**: DISTINCT 집계/분석함수/px GROUP_CONCAT·보간 리스트의 "raw disk_repr" 라이터 5곳을 `qfile_add_values_tuple_to_list(list, &val, 1)` 로. | raw 항목은 `data_writeval` 이미지인데 문자열 컬럼(DIRECT)은 `index_*` 인코딩이어야 한다. 조립기가 인코딩을 고르므로 값 API 가 유일한 올바른 라이터. per-row malloc/free 도 사라진다. | — |
| D-199-6 | 정렬 비교자 `sort_f = qfile_col_cmpdisk_function(key_tl.col[i], dom)`: FIXED→`data_cmpdisk`, DIRECT→`index_cmpdisk`(신설 getter `pr_type::get_index_cmpdisk_function`), SCRATCH→`data_cmpdisk`. A 경로 슬롯은 8B 정렬이라 그대로, P 경로(`qfile_compare_partial_sort_record`)는 SCRATCH 키만 256B 스택(+힙 폴백) 복사 후 비교. 보간 비교 `qfile_compare_with_interpolation_domain` 은 `qfile_col_read_body` 로 디코드. | D-180-8. `mr_data_cmpdisk_bit` 가 `OR_GET_INT` 캐스트(#183). | — |
| D-199-7 | 슬롯 위치 캐시는 **지연 시작**(`nvalid = -1` 센티널): `set_tuple` 은 포인터+2 필드만 쓰고, 첫 접근자가 has-null 비트·`first_null_col`·`fast_limit`·`off` 를 계산(`qfile_slot_start`). 디스크립터에 `first_non_cached_off`(고정 접두 끝 오프셋) 추가 — `fast_limit` 컬럼의 시작 오프셋을 상수로 알기 위해. | 읽지 않는 튜플(스킵·카운트)에 비트맵 스캔 비용을 물리지 않는다(cpp-perf: 행당 분기 1개 vs 스캔). | `set_tuple` 에서 즉시 계산. |
| D-199-8 | `qexec_setup_list_id()` 의 손조립 DML 결과 리스트는 **hdr 8**(class A: top-most 결과, RETURN_GENERATED_KEYS 튜플을 클라이언트가 fetch). | #184 A 규칙. | — |
| D-199-9 | 도메인 구동 walk 는 `qfile_tuple_walk_init(walk, tpl, hdr_size, type_cnt)` — 디스크립터가 줄 두 값을 호출자가 준다. px XASL_SNAPSHOT 리더는 `m_list_id_p->type_list.hdr_size`(open 시 고정, `m_valid` 발행 뒤에만 읽음)와 `m_type_cnt`; 해시 GROUP BY 스필 로더 `qdata_load_agg_hentry_from_tuple(..., hdr_size, ...)` 는 partial 리스트의 hdr. walk 의 SCRATCH 디코드도 D-199-2 의 일시 복사. | D-182-16 스레드 계약: 가변 디스크립터는 읽지 않되 open 시 고정되는 두 값은 안전. | — |
| D-199-10 | `or_unpack_unbound_listid` 는 hdr_size 가 4/8 이 아니면 assert + 에러(구 바이너리와의 혼합은 방어하지 않지만 오독 대신 실패). | ADR §1.6 lockstep. | — |
| D-199-11 | `qfile_slot_locate()` 의 계약 명문화: raw 역참조는 FIXED 컬럼(해시키 INT, 카운터)만; 일반 디코드는 `qfile_slot_read_value()`; OID/VOBJ prefetch(cursor) 는 일시 정렬 복사(`QFILE_SCRATCH_ACQUIRE`) 뒤 raw 읽기. cursor 의 `cursor_get_tuple_value_to_dbvalue` 는 슬롯+컬럼을 받는다(`QFILE_TUPLE_VALUE_FLAG` 삭제). | 새 포맷은 자기 기술적이지 않다(D-182-1). | — |
| D-199-12 | 머지 조인 비교 `qexec_cmp_tpl_vals_merge` 는 body/len 배열 대신 두 스캔 슬롯 + 컬럼 인덱스 배열로 읽는다(`QEXEC_MERGE_PVALS` 의 lenp 는 NULL 판정용으로 유지). | 슬롯 캐시로 위치는 O(1); 디코드 비용은 이전과 같다. | — |
| D-199-13 | **조립기가 미확정 컬럼을 첫 bound 값에서 확정**: `qfile_tuple_size*` 가 `DB_TYPE_VARIABLE` 컬럼에 bound 값이 오면 `tp_domain_resolve_value(val)` 로 `domp[col]` 을 바꾸고 재finalize 한 뒤 레이아웃한다(mutator-owns-finalize). 라이터 프로브는 "VARIABLE 컬럼에 bound 값" 을 assert. 크기 pass 의 `tl` 은 non-const. | #186 의 "확정 전 튜플의 해당 컬럼은 NULL" 은 **거짓**이었다: `qfile_update_domains_on_type_list` 는 regu 도메인으로 확정하는데 regu 도메인 자체가 VARIABLE 인 동안(집계·파생 컬럼) bound 값이 여러 튜플 기록된다. 자기 기술적이지 않은 포맷에서 그 튜플들은 VAR 레이아웃으로 남고, 뒤늦은 확정 후 FIXED 로 읽혀 `0x0800000000000001`(1B 헤더 0x08 + BIGINT 1) 같은 값이 나왔다(CTP 4차 실패 8건의 원인). 값의 타입은 레이아웃을 완전히 결정하므로 값에서 확정하는 것이 유일하게 안전하다. | 리스트 열림 전 컴파일러가 도메인을 확정하도록 XASL 생성 수정(범위 밖). |
| D-199-14 | ORDER SIBLINGS BY 의 계층 인덱스 문자열 타입(`bf2df_str_type`, `tp_String` 복제)에 `set_index_cmpdisk_function(bf2df_str_cmpdisk)` 추가. | 문자열 컬럼은 VAR/DIRECT 라 정렬키 비교자가 `index_cmpdisk` 인데(D-199-6) 이 타입은 `data_cmpdisk` 만 덮어써 일반 문자열 순서로 정렬됐다("1.10" < "1.2", CTP bug_4178). `bf2df_str_cmpdisk` 는 index 인코딩과 같은 `[len byte][bytes]` 접두만 읽으므로 그대로 쓸 수 있다. 교훈: **`data_cmpdisk` 를 덮어쓰는 특수 타입은 `index_cmpdisk` 도 덮어써야 한다**(grep `set_data_cmpdisk_function` — 이 1곳뿐). | — |

## 치환 목록 (body 포인터 소비자)

- `qfile_slot_read_value` 로: query_evaluator.c 8곳(eval_sub_*), query_opfunc.c `qdata_tuple_to_val_list`, query_hash_join.c `hjoin_...key`(coerce 경로 포함), query_aggregate.cpp/query_analytic.cpp DISTINCT 리스트 재읽기, query_hash_scan.c 덤프, query_executor.c `qexec_compare_valptr_with_tuple`·`qexec_analytic_sort_key_header_load`·머지 비교, list_file.c `qfile_compare_tuple_values`(슬롯 인자로 변경), cursor.c 값 읽기.
- FIXED raw 유지: hjoin 해시키 INT(assert `len == disksize`), 분석함수 group/value 헤더 카운터 INT, `QEXEC_MERGE_PVALS`(NULL 판정), 정렬 레코드 빌드(raw src, 같은 도메인), 머지 라이터(raw src).
- 일시 정렬 복사 후 raw: cursor OID prefetch 2곳(OBJECT/VOBJ, SCRATCH), VOBJ 값 디코드.
- walk → `qfile_tuple_walk_read_value`: px 스냅샷 리더, 해시 GROUP BY 스필 로더, `qfile_print_tuple`.
- network_interface_sr.cpp 압축 길이 추정: 문자열 DIRECT 본문의 압축 접두는 data 인코딩과 같아 무수정(주석).

## 구 포맷 삭제

`query_list.h`: `QFILE_TUPLE_LENGTH_SIZE`, `QFILE_TUPLE_VALUE_HEADER_*`, `QFILE_TUPLE_VALUE_FLAG_*`, `QFILE_TUPLE_VALUE_LENGTH_*`,
`QFILE_GET/PUT_TUPLE_VALUE_*`, `QFILE_TUPLE_VALUE_FLAG`(V_BOUND/V_UNBOUND), `QFILE_TUPLE_VALUE_HEADER`; layout: `QFILE_TL_HDR_SIZE_LEGACY`,
`QFILE_LEGACY_VALUE_*`, `qfile_legacy_put_value`; query_opfunc.h `UNBOUND()`. 신설: `QFILE_TUPLE_HDR_SIZE_FORWARD/BACKWARD`,
`QFILE_GET_TUPLE_HAS_NULL`, `QFILE_PUT_TUPLE_LENGTH(tpl,len,has_null)`, 비트맵·가변 헤더 매크로, `QFILE_LIST_BACKWARD_FLAG(list)`.

## 스텁 헤더(#180 `cbrd27365-qfile_tuple_layout.h`)와 실제 헤더 대조

스텁은 명세의 코드 표현이었고 API 이름은 #182 에서 확정됐다. 대응: `qfile_varhdr_*`→`qfile_var_hdr_*`, `qfile_bitmap_first_null`→
`qfile_first_null_col`, `qfile_bitmap_is_null`→`QFILE_BITMAP_IS_BOUND` 매크로, `qfile_deform_cache`→`QFILE_TUPLE_RECORD` 슬롯 필드
(`nvalid/fast_limit/data_off/has_null/off`), `qfile_tuple_value_ptr`→`qfile_slot_locate`, `qfile_tuple_overwrite_fixed`→
`qfile_slot_overwrite_value`(가변 컬럼도 허용, 길이 불변 assert). 바이트 규칙은 스텁과 동일하다(D-180-1~9).

## 검증

설치 `~/optdebug/CUBRID-cbrd27365`(optdebug), 검증 DB `cbrd27365s` 는 매번 검증 대상 빌드로 재생성(D-189-3), 포트 claim 1702 / broker 36200·36230(매 install 뒤 conf 재적용).

| 단계 | 대상 | 결과 |
|---|---|---|
| optdebug 증분 빌드 | `eb152ba76` | 1회 수정(px hpp 의 `QFILE_TUPLE_WALK` include 누락, sign-compare 2건) 후 green, 경고 0. |
| smoke 1차 | `eb152ba76` | **서버 abort ×2**: `INSERT ... SELECT`(SET/JSON 컬럼) 직후 트랜잭션 종료 시 resource tracker 가 `qfile_slot_scratch_grow` 의 private alloc 18개 누수를 잡아 assert(코어 2개, gdb 확인: `resource_tracker.hpp:414`). 원인 = 스캔이 채우는 스택 레코드는 `qfile_slot_clear` 를 부르지 않음 → D-199-2 개정(슬롯 소유 스크래치 폐기). |
| optdebug 증분 빌드 | `5eb998373` | green, 경고 0(신규). |
| smoke 2차 | `5eb998373` | csql 12항목 PASS + JDBC 역방향 커서 PASS × 2회, 코어 0, err 로그에 누수 덤프 없음. |
| CTP sql 전수 1차 | `5eb998373`, 감시 ON | **5분 만에 감시 중단, 코어 27개(33GB)**. 트리거 `_03_object_oriented/_02_collection_type/_003_manipulation/1020.sql`(`--[er]` SETEQ 다중행 서브쿼리): 오류 종료로 `xasl->list_id` 가 열리지 않은 채(모두 0) `qexec_get_xasl_list_id → qfile_copy_list_id → qfile_type_list_copy` 의 hdr_size assert. PR-1b 의 폴백을 2b 가 assert 로 바꾼 것이 원인 → 미개방 소스는 FORWARD 로 두고 `!finalized` 만 assert(`94589a8ce`). 부수 인시던트: 감시 폴링 30초 동안 크래시 루프 shard 하나가 코어 13개 → 오케스트레이터 폴링 5초·즉시 kill 로 변경(툴링 `d1760cd`). |
| optdebug 증분 빌드 + smoke 3차 | `94589a8ce` | green(경고 0), csql PASS + scroll PASS × 2회, 코어 0. |
| CTP sql 전수 2차 | `94589a8ce`, 감시 ON(5초) | 5분 만에 중단, **코어 1개**(폴링 단축 효과). 트리거 `_19_apricot/_03_index_skip_scan/_05_iss_covering_choice.sql`: `qfile_slot_read_value` 의 디코딩 도메인 vs 저장 kind 프로브 assert. gdb: 리스트 컬럼 1 은 STRING(VAR) 정상 데이터 `'aaaa'`, regu 의 `pos_descr.dom` 이 `tp_Null_domain`(컴파일러가 미확정으로 남긴 rest_regu) — 레거시도 `mr_data_readval_null` 로 NULL 을 돌려주던 경로라 **프로브 완화**(`50993cb13`), 데이터 오손 아님. |
| optdebug 증분 빌드 + smoke 4차 | `50993cb13` | green, PASS×2, 코어 0. |
| CTP sql 전수 3차 | `50993cb13`, 감시 ON | 5분 만에 중단, 코어 1개 + CAS assert 1건. (a) 서버: `_21_enum_aggregate_functions.sql` `count(col5) over(partition by col3 order by col4)` 에서 ENUM 인덱스 0x8000 → `mr_setval_enumeration_internal` assert. (b) CAS: `_t24_03_everycolumns_const.sql` `CHAR(9) ''` 을 커버링 인덱스로 읽는 커서에서 `or_advance` 오버런(csql 로 재현, 클라이언트 코어 gdb: 본문 len 32, 첫 바이트 0x20). **공통 원인 = 리더 버그**: `qfile_slot_start` 가 첫 NULL 컬럼 `lim` 에서 걷기를 `col[lim].off`(정렬된 시작)에서 시작했으나, 라이터는 NULL 컬럼에 패딩을 쓰지 않으므로 걷기는 `col[lim-1]` 의 (비정렬) 끝에서 시작해야 한다. `[SMALLINT bound][INT NULL]…` 에서 2B 어긋나 이후 모든 컬럼이 밀렸다. `qfile_prefix_end()` 로 수정, `first_non_cached_off` 삭제(`25eb07205`). smoke 가 놓친 이유: smoke 의 NULL 혼합 행은 첫 NULL 이 가변 컬럼 뒤에 오거나 상수 접두가 없었다 — TC 후보에 "고정 컬럼 사이의 NULL" 추가(#194 test.md). |
| optdebug 증분 빌드 + smoke 5차 + 재현 2건 | `25eb07205` | green, PASS×2, `repro_char.sql`·`repro_enum.sql` 정상(EXIT 0), 코어 0. |
| CTP sql 전수 4차 | `25eb07205`, 감시 ON | **완주, 코어 0, 17,440/17,457**. 실패 17: 플랜/TRACE 텍스트·행 순서 노이즈 4(cbrd_23665, cbrd_24148, cbrd_25447, bug_4178), 기존 답안 drift 1(agg_group_by, D-190-12), 값 오류 의심 8+(p_cont/p_disc_collection: SET 파티션 행의 percentile 값 쓰레기; hash_agg_for_prepare_complex: 집계 67108864; lt_numeric/short_to_char_varchar: count 0x0800000000000001; cbrd_25382 ×2, join_orderby_skip, cbrd_25519, _02_group_basic, hash_agg_query_profile, cbrd_20865 미확인). 라이터/리더 폭 불일치 의심 → 디코딩 프로브를 폭·접근 방식까지 강화하고 해당 디렉터리만 격리 재실행(다음 행). |
| 격리 부분 실행 + CTP sql 전수 5차 | `a25bded25`, 감시 ON | 격리 10 디렉터리 154 케이스: 값 오류 전부 해소(4 NOK 는 플랜 텍스트). **전수 완주, 코어 0, 17,448/17,457**. 남은 9: `agg_group_by`(D-190-12 답안 drift), 플랜/TRACE 텍스트 7(`hash temp(h)→(m)`, hash join `BUILD method: hybrid→memory`, `(parallel workers…)` 줄 소실 — 튜플이 작아져 리스트 페이지 수 기준 판단이 바뀐 결과, 답안 갱신 대상·#193 관찰 항목), **bug_4178: ORDER SIBLINGS BY sort_sord 순서 오류(값 11 이 27/37/47 뒤)** — 실제 버그, 재현 중. |
| CTP sql 전수 6차 | `286b6ab8a`(ORDER SIBLINGS 비교자) | 완주·코어 0. 실패 9: 7 플랜/TRACE 텍스트(#194 답안 갱신), **bug_4178 해소**(ORDER SIBLINGS 순서 정정), 신규 1 `_03_adhoc_delete_update_3`. |
| 미해결 조사(#199 잔여, D-199-15) | `_03_adhoc_delete_update_3` -495 | DELETE 의 `id IN ((connect by … order by id) UNION …)` 서브쿼리(START WITH 없음 → 100행 전부 루트, 1300행 DF)에서 `qexec_recalc_tuples_parent_pos_in_list` 의 레벨 언더플로(POSINFO_NULL_B, 계측으로 확정). 원인: CONNECT BY 의 BF→DF 정렬이 PR-2b 에서 문자열 계층 인덱스 컬럼을 VAR/DIRECT 로 보고 정렬키 비교를 `index_cmpdisk` 로 라우팅(D-199-6). 레거시는 `bf2df_str_cmpdisk` 를 `data_cmpdisk` 로만 설치했고 자기 기술 포맷에서 그 경로로 비교했다. D-199-14 가 `index_cmpdisk` 도 그 함수로 덮어써 bug_4178(정렬 SELECT)은 고쳐졌으나, 이 다중 루트 DELETE 서브쿼리에서는 정렬 순서가 레거시와 달라져(index vs data 인코딩 바이트는 짧은 문자열에서 동일하다는 분석과 모순 — 컬럼 오프셋/포지션 차이 의심, 미확정) recalc DF 불변식을 깬다. crash 는 없음(핸들된 -495). 재현: 위 5줄. 판정: **에러(무결성 손상 아님)** 는 bug_4178 을 되돌렸을 때의 무성 오정렬보다 안전하므로 비교자 fix 유지, 이 케이스는 #192 검증 티켓에서 CONNECT BY+새 포맷 정렬 비교자 경로를 정밀 조사해 마감. |
| 크기 확인(게이트 6) | `5eb998373` vs `~/CUBRID`(구 포맷 optdebug, develop 8/30) 같은 호스트 A/B, `t_sz(i INT, b BIGINT)` 100만 행 | `SELECT i,b FROM t_sz ORDER BY b DESC`: `Num_sort_data_pages` 19,047 → **14,041**(−26%); `LIMIT 999990,10` 변형 10,792 → 8,314(−23%). `LIMIT 1` 은 top-N 정렬이라 리스트를 만들지 않음(page 0). 이 카운터는 정렬 런(키 레코드, 두 빌드 동일) 페이지까지 세므로 튜플 40→20B(backward 리스트) 의 이론치 −50% 보다 작게 나온다 — 방향 확증용, 정량은 #193 release A/B. |
