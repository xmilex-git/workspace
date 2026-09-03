# CBRD-27365 PR-2a: 튜플 조립기 도입·라이터 수렴·정렬 레코드 리더 (티켓 #190, 지도 #179)

PR-1b(#196) 위에 쌓은 fork PR — 리스트 튜플 **라이터** 전 지점을 튜플 조립기(`qfile_tuple_size/fill`)로 수렴시키고,
정렬 레코드(SORT_REC) 본문을 접근자/조립기로 읽고 쓰며, `qfile_fast_*` 3함수를 삭제한다. **포맷은 불변**(레거시
`[len][prev_len]` + 값마다 `[flag][len]` 헤더). 결정 ID `D-190-*`. 코드 위치는 worktree `~/dev/worktrees/cbrd27365`
브랜치 `CBRD-27365-pr2a`.

## 왜 PR-2 를 둘로 나눴나 (D-190-1)

포맷 교체는 라이터·리더가 동시에 바뀌어야 하는 원자적 변경이라 중간에 CTP green 게이트를 둘 수 없다. 라이터 수렴·정렬
레코드 리더·`fast_*` 삭제는 포맷 불변으로 먼저 끝낼 수 있고, 그러면 PR-2b(#199)의 diff 가 `qfile_tuple_layout.{h,c}`
내부 + 페이지 레벨 소수 지점으로 좁아진다. PR-1a/1b 와 같은 분할 원리(D-182-17).

## 결정

| ID | 결정 | 근거 | 되돌림 |
|---|---|---|---|
| D-190-1 | PR-2 = PR-2a(포맷 불변 수렴, 이 티켓) → PR-2b(포맷 교체 + 구 포맷 삭제, #199). | 위 절. | 2a 위에 2b squash. |
| D-190-2 | **P_sort_key 본문 = 조립기로 만든 레거시 미니튜플**(8B 튜플 헤더 포함). 비교자는 `key_tl` 에 bind 한 스택 슬롯 2개로 읽는다. 2a 에서 정렬 레코드가 8B 커진다(2b 에서 4B 헤더로 감소). | 접근자(`qfile_slot_locate`)가 튜플 헤더를 전제로 하므로 미니튜플이 온전한 튜플이어야 한다. 정렬 레코드는 인메모리/정렬 임시 파일이라 리스트 포맷 불변에 영향 없음. | 헤더 없는 본문 + 전용 워커(접근자 미사용). |
| D-190-3 | T_NORMAL(`f_valp[]`) 오버로드 `qfile_tuple_size/fill_from_values` 는 fill 에서 디스크 크기를 **재계산**한다(D-182-11 "size 가 len 되쓰기" 미적용). | 문자열 디스크 크기는 첫 계산에서 DB_VALUE 에 캐시(압축 결과)되어 두 번째는 싸다 — 레거시(`qdata_generate_tuple_desc_for_valptr_list` + `qdata_copy_db_value_to_tuple_value`)와 같은 비용. `f_len[]` 배열 추가는 #193 측정 뒤. | 디스크립터에 `f_len[]` 추가. |
| D-190-4 | **컬럼 소스 버퍼 소유**: (a) 페이지 라이터는 출력 리스트의 `tpl_descr.col_src`(리스트 소유, `qfile_tpl_descr_col_src` 로 성장, `qfile_clear_list_id` 가 해제, 복제 시 NULL — `f_valp` 와 동일 규약); (b) 정렬 레코드 빌드·A키 재구성은 스택 64 + 힙 폴백(`QFILE_COL_SRC_ACQUIRE`); (c) private 버퍼 값 라이터는 `DB_VALUE *` 스택 64 + 힙 폴백. | 병렬 정렬 put 워커는 각자 출력 list_id 를 가지므로 (a) 가 스레드 안전. `SORTKEY_INFO` 는 워커 간 읽기 전용 공유라 버퍼를 둘 수 없음. 행당 malloc 은 64 컬럼 초과에서만(cold). | 버퍼를 SORT_INFO/merge 상태로 이동. |
| D-190-5 | **`key_tl.domp[i] = types->domp[key[i].col]`**(리스트의 실제 컬럼 도메인), 비교 도메인 `col_dom` 은 별도 유지. | 키 값은 리스트 본문의 raw 복사라 2b 레이아웃은 리스트 타입을 따라야 한다. `pos_descr.dom` 은 VARIABLE 등으로 다를 수 있음. | — |
| D-190-6 | **A_sort_key 본문 슬롯 = SORT_REC 전용 규약 `[len 4B][pad 4B][data]`**, `offset[]` 은 data 를 가리키고 data 8B 정렬 유지. 길이는 `QFILE_SORT_REC_A_LEN`. | 옛 `offset-8` 값 헤더 의존 3곳 제거, 튜플 포맷 의존을 SORT_REC 안에서 끊음(#186 §2.2). `sort_f` 가 8B 값을 역참조할 수 있어 정렬 유지. | — |
| D-190-7 | `QFILE_TUPLE_TYPE` 은 `T_NORMAL`/`T_COL_SRC` 둘. `T_SINGLE_BOUND_ITEM`/`T_SORTKEY`/`T_MERGE` 와 디스크립터의 경로별 필드(`item`, `sortkey_info/sort_rec`, `tplrec1/2/merge_info`) 삭제. | 세 경로 모두 "컬럼 소스 배열 → 조립기" 로 같아진다(#186 §5.3). | — |
| D-190-8 | 머지 라이터 통합: `qfile_merge_tuple_add_list`(list_file.c) 하나로 `qexec_merge_tuple/size_remaining/merge_tuple_add_list`(executor)와 `hjoin_merge_tuple`(hash join)을 대체. `hjoin_merge_tuple_to_list_id` 는 프로파일 훅을 위한 얇은 래퍼로 유지. BIG 버퍼 성장은 페이지 배수. | 두 함수가 같은 O(n²) 헤더 워크를 복제하고 있었다; 슬롯 캐시로 O(n). | — |
| D-190-9 | 라이터 측 타입 프로브(디버그): `qfile_tuple_check_col_type` — 값 타입 == `domp[col]` 타입, 예외 = VARIABLE 미확정 / 문자열군 / 집합군(+VOBJ) / OBJECT·OID. `qfile_tuple_size*` 는 `n == tl->type_cnt` 도 assert. | 2b 에서 열 레이아웃이 `domp[col]` 에서 나오므로 불일치는 곧 오손. CTP 전수가 프로브. | 관측된 정당한 불일치 쌍을 허용 목록에 추가. |
| D-190-10 | `hjoin_probe_key` 인메모리 엔트리의 `tuple_record->size = QFILE_GET_TUPLE_VALUE_LENGTH(tpl)`(사실상 prev_len 워드 읽기) → `0`(PEEK). | 그 경로에서 `size` 를 소비하는 코드 없음(grep); 2b 에서 prev_len 워드가 사라짐. 기존 이상 동작 정정. | — |
| D-190-12 | **BIT_AND/BIT_OR/BIT_XOR 누산기 도메인 = `tp_Bigint_domain`**(serial `qexec_resolve_domains_for_aggregation` + px fallback). 이전엔 선언 agg 도메인(INTEGER)이었으나 `qdata_bit_*_dbval` 은 항상 BIGINT 를 만든다. | D-190-9 프로브가 CTP 에서 잡은 기존 불일치(`agg_group_by.sql` bit 집계 + 해시 GROUP BY spill). 2b 에서는 domp 가 레이아웃이라 INTEGER 4B 슬롯에 BIGINT 8B 를 쓰면 오손. 투영 결과는 여전히 agg 도메인으로 캐스트됨. | 프로브 정수군 예외(2b 에서는 불가). |
| D-190-13 | 손으로 비운 `SORTKEY_INFO`(`nkeys=0; key=NULL`) 3곳(분석함수 no-sort 경로, 해시 GROUP BY 컨텍스트 2곳) → `qfile_init_empty_sort_key_info`(finalize 된 빈 `key_tl`). | `key_tl` 이 미초기화 쓰레기 → `qfile_build_sort_rec` assert(C), `qfile_clear_sort_key_info` 의 free 가 `munmap_chunk(): invalid pointer`(B). 스택 ANALYTIC_STATE 는 memset 되지 않음. | — |
| D-190-11 | `qdata_copy_valptr_list_to_tuple`/`qdata_copy_val_list_to_tuple`/`qdata_generate_tuple_desc_for_valptr_list`/`qfile_copy_tuple_descr_to_tuple`/`qfile_save_tuple` 에 **출력 리스트의 `type_list` 인자** 추가(호출자 12곳). | 2b 라이터는 디스크립터 없이 튜플을 만들 수 없다. 2a 에서 배선만 먼저. | — |

## 수렴 결과 (구 포맷 지식이 남은 곳) — PR-2b 진입 조건 확인

커밋 `adf720122` 기준 grep:

- 값 헤더 매크로(`QFILE_TUPLE_VALUE_HEADER_*`, `QFILE_GET/PUT_TUPLE_VALUE_*`) 사용처: **`qfile_tuple_layout.h` 만**
  (정의는 `query_list.h`). 서버·SA·클라이언트 어디에도 직접 사용 0.
- 튜플 헤더 크기 `QFILE_TUPLE_LENGTH_SIZE`: `qfile_tuple_layout.{h,c}` 안(슬롯 리셋 `off`, 조립기 size/fill, walk init) 만.
- `prev_len`: 라이터 `qfile_add_tuple_to_list_id`(list_file.c 1곳), 리더 `qfile_scan_prev`(list_file.c)·`cursor_prev_tuple`(cursor.c)
  — #184 가 예측한 페이지 레벨 3지점 그대로. 두 리더에 `QFILE_LIST_IS_BACKWARD` assert 부착.
- 그 밖의 페이지 레벨 리더(`QFILE_GET_TUPLE_LENGTH` 로 튜플 경계만 걷는 곳: 오버플로 조립, network_interface_sr 첫 페이지 크기,
  px 슬롯 이터레이터 등)는 길이 워드만 읽으므로 2b 에서 bit31 마스킹(PR-1b 에 이미 적용)으로 충분.

→ PR-2b 의 diff 는 `qfile_tuple_layout.{h,c}` 내부 + 위 3지점 + `qfile_open_list` 의 `hdr_size` 한 줄로 닫힌다.

## 검증

| 단계 | 대상 | 결과 |
|---|---|---|
| optdebug 증분 빌드 | `b50f00979` | 컴파일 오류 2건 수정 후 green(경고 0): (1) `qfile_tuple_layout.h` 가 `db_get_string_length` 선언(`string_opfunc.h`)을 자기 include 로 갖지 않아 SA `method_scan.cpp` 에서 실패, (2) px `write()` 의 `qdata_generate_tuple_desc_for_valptr_list` 호출에 새 `type_list` 인자 누락. |
| smoke 1차 | `b50f00979`, 설치 `~/optdebug/CUBRID-cbrd27365`, DB `cbrd27365s` 를 이 빌드로 재생성(D-189-3), 포트 claim 1702 / broker 36200·36230 | csql 12항목 PASS + JDBC 역방향 커서 PASS × 2회, 코어 0. 설치 단계가 conf 포트를 1523/30000/33000 으로 되돌리므로 매 install 뒤 claim 포트 재적용 필요(운영 메모). |
| optdebug 증분 빌드 | `1ba4cdc0b`(플래그 커밋, amend) | 1회 수정(px `merge_list_ids` 는 자유 함수라 `m_` 접근 불가 → assert 를 `write_finalize` 호출자로 이동; sign-compare 경고 2건 캐스트) 후 green, 경고 0. |
| smoke 2차 | `1ba4cdc0b`, DB 재생성, 포트 1702/36200·36230 | csql PASS + scroll PASS × 2회, 코어 0. |
| CTP sql 전수 1차 | `1ba4cdc0b`, 감시 ON | **3.5분 만에 감시 중단, 코어 23개**(shard 2–6). 시그니처 A: `qfile_tuple_check_col_type` assert — `select f1,bit_and(i1+2),bit_or(i1-2),bit_xor(i1*1) from t1 group by d1`(`_14_mysql_compatibility_2/.../agg_group_by.sql`), 누산기 값 BIGINT vs partial 리스트 컬럼 INTEGER → D-190-12. 시그니처 C: `qfile_tuple_size` `type_cnt == n` assert, `key_tl` 쓰레기(`p_cont/p_disc_partition_hash.sql`) → D-190-13. 시그니처 B: `munmap_chunk(): invalid pointer`(분석함수 `row_number/count/max over`, 3 shard 3 파일) → D-190-13 과 동일 원인(clear 시 쓰레기 free). 부수: shard 2 복구 REDO `spage_find_empty_slot_at` assert 는 크래시 후속(#198 관찰과 동일). |
| PR #258 리뷰 | 4건 | P1×3 "도메인 확정 뒤 size pass"(serial·px writer·px snapshot) → `qdata_size_tuple_desc` 분리·순서 교정; P2 `qexec_add_intval_tuple` 반환값 전파. 커밋 `5b2bbb6d5`. |
| optdebug 증분 빌드 | `5b2bbb6d5` | green, 경고 0. |
| smoke 3차 | `5b2bbb6d5`, DB 재생성, 포트 1702/36200·36230 | csql PASS + scroll PASS × 2회, 코어 0. |
| CTP sql 전수 2차 | `5b2bbb6d5`, 감시 ON, out 초기화, testcases a2c76731d | **17,456 / 17,457 통과, 코어 0**, 감시 미발동, shard 358~520초(전체 ~8.7분). 유일한 실패 `_14_mysql_compatibility_2/_15_host_variable/_12_common/agg_group_by.sql` 의 prepared `bit_and(i1+?)/bit_xor(i1*?)`: 기존 답안 `0/1, 0/2, 0/10` 은 레거시가 BIGINT 누산기를 INTEGER 도메인으로 읽어 상위 워드(0)를 돌려준 오답이고, 같은 파일의 리터럴 버전 답안(`3/0, 4/0, 12/10`)·실제 데이터(d1=1.2 그룹 i1=1,1 → 3, 1^1=0)와 PR-2a 결과가 일치 → **엔진 회귀 아님, `cubrid-testcases` 답안 갱신 대상**(D-190-12 의 사용자 가시 효과; test.md 에 기록). |

## 다음 세션으로 넘기는 것 (#190 마감 시점)

- `cubrid-testcases` `sql/_14_mysql_compatibility_2/_15_host_variable/_12_common/answers/agg_group_by.answer` 의 prepared bit 집계 3행 갱신(PR 제출 시 tc PR 동반, #194 test.md).
- fork PR xmilex-git/cubrid#258 리뷰 4건 반영 완료·답글 완료, draft 해제. 추가 리뷰가 오면 2b 시작 전에 반영.

## PR-2b 로 넘기는 것

- `hdr_size = QFILE_FLAG_BACKWARD ? 8 : 4`(D-181-8) 한 줄과 `key_tl` 헤더 4, `qfile_duplicate_list` 의 backward 상속(2a 에서는 hdr_size 가 상수라 상속할 것이 없음).
- 비교자 스택 슬롯의 VAR/SCRATCH 폴백(D-182-10): 2a 는 레거시라 스크래치가 필요 없지만 2b 는 `qfile_compare_partial_sort_record` 가 슬롯 소유 스크래치 대신 스택 버퍼를 써야 한다.
- 조립기 fill 의 가변 값 기록: `data_writeval` → `index_writeval`/직접 복사 + "기록==계산" assert(#183).
