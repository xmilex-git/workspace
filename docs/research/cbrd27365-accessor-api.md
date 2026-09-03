# CBRD-27365 접근자 API·deform 캐시·튜플 조립기·in-place·정렬 레코드 설계 (티켓 #182, 지도 #179)

명세 v1(#180)과 레이아웃 디스크립터(#181) 위에서, 새 포맷을 읽고 쓰는 **접근자 API**와 그 성능 구조를 확정한다. 결정 ID `D-182-*`. 2026-09-03 그릴링 2라운드로 잠금. 코드 위치는 `/home/cubrid/dev/cubrid` develop 기준.

## 0. 핵심 발견 — 새 포맷은 자기 기술적이지 않다

구 포맷은 값마다 `[flag 4B][len 4B]` 헤더가 있어 `char *tpl` 하나로 걸을 수 있었다. 새 포맷은 컬럼 위치를 알려면 레이아웃 디스크립터(`type_list`)가 반드시 필요하다. 그런데 regu 평가 경로는 raw `QFILE_TUPLE tpl`만 넘긴다(`fetch_peek_dbval` TYPE_POSITION 분기 fetch.c:4086 → `qfile_locate_tuple_value(tpl, pos_no)`).

| 함수 | 호출 지점 수 |
|---|---|
| `fetch_peek_dbval` | 155 |
| `fetch_val_list` | 51 |
| `eval_pred` | 47 |
| `fetch_copy_dbval` | 13 |

→ "튜플 + 디스크립터 + deform 캐시"를 묶은 **튜플 슬롯**이 이 경로를 타야 한다(D-182-1). 클라이언트 `CURSOR_ID`는 이미 같은 캐시를 갖고 있다(`current_tuple_value_index/_p`, cursor.c:442-462, 정방향 재개만).

## 1. 결정 목록

| ID | 결정 | 근거 | 되돌림 |
|---|---|---|---|
| D-182-1 | **리더 진입점**: `fetch_peek_dbval`/`fetch_copy_dbval`/`fetch_val_list`/`eval_pred`(및 pass-through 호출자 ~270지점)의 `QFILE_TUPLE tpl` 파라미터를 **`QFILE_TUPLE_RECORD *`(=슬롯)** 로 교체. `VAL_DESCR` 숨은 채널·`QFILE_TUPLE` typedef 의미 변경은 불채택. | 명시적·컴파일러가 검증. 숨은 채널은 한 평가에 리스트가 둘일 때 모호. | — |
| D-182-2 | **슬롯 = 기존 `QFILE_TUPLE_RECORD` 확장**(별도 타입 없음). 필드: `char *tpl; int size;`(기존, `size>0` 소유 버퍼 / `0` 비소유 PEEK — 의미 불변) + `const QFILE_TUPLE_VALUE_TYPE_LIST *tl;` + `int16 nvalid; int16 fast_limit; int32 off;` + `char *scratch; int scratch_size;`. 소유/비소유와 캐시는 직교. 접근자 접두 `qfile_slot_*`. | `qfile_scan_list_next(&tplrec)`가 이미 이 구조체를 채우므로 새 전달 경로 0. hash join `tuple_record`·오버플로 버퍼 등 기존 사용처가 그대로 슬롯이 된다. | 별도 `QFILE_TUPLE_SLOT` 신설(내부에 RECORD 포함) — 접근자 코드 불변 |
| D-182-3 | **캐시 필드 이름은 PG와 동일**: `nvalid`(PG `tts_nvalid`, "여기까지 걸었다"), `off`(PG `HeapTupleTableSlot.off`). `fast_limit`은 PG에 저장 필드가 없어(지역 변수 `firstNonCacheOffsetAttr = Min(…, firstNullAttr)`, execTuples.c:1158) 우리 이름. 슬롯은 PG처럼 `tts_values[]`를 **물질화하지 않고 위치만** 기억한다. | CUBRID 소비자는 결국 `data_readval`로 DB_VALUE를 만들어 중간 Datum 배열이 이득이 없다. | — |
| D-182-4 | **`fast_limit`은 튜플별 값**: `has_null ? min(tl->first_non_cached_col, first_null(bitmap)) : tl->first_non_cached_col`. `set_tuple`에서 1회 계산(≤64컬럼: 바이트 로드 + ctz), PG처럼 매 deform 재계산하지 않음. | TYPE_POSITION 임의 위치 읽기가 컬럼마다 접근자를 부르므로 캐시가 맞다. | 매 호출 재계산(필드 제거) |
| D-182-5 | **캐시 무효화 = mutator-owns-reset**: `tpl`을 바꾸는 유일한 길은 `qfile_slot_set_tuple(rec, tpl)`이며 그 안에서 `nvalid=fast_limit`, `off=data_off[has_null]`를 리셋. 포인터 동등성 검사(`cache.tpl==tpl`)는 두지 않음. 디버그: 직접 대입을 잡기 위해 "리셋됨" 표식 assert. | `scan_id->tplrec.tpl` 오버플로 버퍼(list_file.c:5336)·`cursor_id->tuple_record`는 같은 포인터에 다른 튜플을 재사용 → 포인터 비교는 불안전. D-181-6과 같은 원칙. | — |
| D-182-6 | **`tl`은 bind 1회**: `qfile_open_list_scan`이 `&scan_id->list_id.type_list`, `cursor_open`이 `&cursor_id->list_id.type_list`로 `qfile_slot_bind(rec, tl)`. 늦은 도메인 확정은 같은 주소의 내용을 바꾸므로 포인터 안정. `{NULL,0}` 초기화 사용처는 `tl==NULL`로 남고 접근자 진입 `assert(tl && tl->finalized)`(D-181-7 교차검증 포함)가 미바인드를 잡는다. | 튜플마다 tl을 넘기는 인자 1개 절약, 바인드 실수는 assert로 즉시 검출. | — |
| D-182-7 | **접근자 세 층**(CPU 캐시 L0/1/2와 혼동을 피해 용어 사용): **위치 접근자** `qfile_slot_locate(rec, col, &body_len, &is_null) → const char*` — FIXED: 정렬된 본문, VAR/DIRECT: 헤더 뒤 비정렬 본문, VAR/SCRATCH: 스크래치 사본; **값 접근자** `qfile_slot_read_value(rec, col, DB_VALUE*, copy)` — kind/var_access에 따라 `data_readval` / `index_readval(size=L)` 분기를 안에 감춤(#180 이관 조건 2); **일괄 접근자** `qfile_slot_read_val_list(rec, VAL_LIST*)` — `qdata_tuple_to_val_list`, method_scan.cpp:275, pl_query_cursor.cpp:170, `cursor_get_tuple_value_list`의 O(n²)를 O(n)으로. 위치 접근자를 소비자가 직접 쓰는 곳은 해시조인 키·분석함수 카운터·비교자처럼 DB_VALUE를 만들지 않는 곳으로 한정. | 8B FIXED는 memcpy 읽기(SER-03). | — |
| D-182-8 | **`fetch_peek_dbval_pos` 삭제**(fetch.c:4655-4700, 호출자 4901 1곳). 슬롯 캐시가 일반 TYPE_POSITION 분기에 같은 순차 비용을 주므로 특수 경로 불필요. | BR-04/A59: 같은 일을 하는 분기 둘을 두지 않음. 삭제 조건: PR-1b CTP에서 pos 정렬 assert(4684)에 의존하는 동작 없음 확인. | — |
| D-182-9 | **헤더 4B/8B 분기는 접근자에 없다**: `tl->data_off[has_null]`이 `hdr_size`를 흡수. prev_len 리더 2곳(`qfile_scan_prev`, `cursor_prev_tuple`)만 `assert(hdr_size==8)`. 접근자 변형(variant) 선택 불필요. | 루프 밖으로 뺄 분기 자체가 없다. | — |
| D-182-10 | **VAR/SCRATCH 스크래치는 슬롯 소유**: `scratch/scratch_size`를 `db_private_alloc`(클라이언트 malloc)으로 지연 확장, 슬롯 소유자(`qfile_close_scan`/`cursor_free`)가 해제. 리스트에 SCRATCH 타입이 없으면 영원히 NULL(비용 0). **정렬 비교자**는 슬롯이 없으므로 SCRATCH 키일 때 스택 8B 정렬 버퍼(256B) + 초과 시 malloc/free(cold; PG detoast palloc과 동일). 스레드 로컬(`THREAD_ENTRY.log_data_ptr` 선례) 불채택. | 오버플로 페이지와 무관 — 순수 **정렬** 문제: D-180-5로 가변 값이 비정렬이라 `or_get_int`(`ASSERT_ALIGN 4`)를 버퍼에 직접 거는 SET/JSON/ELO만 사본 필요. 스레드 계약이 슬롯 소유자와 일치, SA/CS 분기 없음, ALLOC-08 교차 스레드 해제 없음. | 대안 (c) `OR_GET_INT/SHORT` memcpy화 + `or_get_*` ASSERT_ALIGN 해제로 스크래치 제거 — 힙·B-tree까지 쓰는 `or_buf` 계약 변경이라 **Out of scope**로 맵에 기록 |
| D-182-11 | **튜플 조립기 입력**: `struct qfile_tuple_col_src { const DB_VALUE *val; const char *data; int len; bool is_null; }` 배열(val≠NULL → writeval 경로, 아니면 raw 복사). 2패스 `qfile_tuple_size(tl, src, n, &has_null)` → `qfile_tuple_fill(tl, src, n, out, size)`. **size 패스가 계산한 본문 길이를 `src[i].len`에 되써서** fill이 `pr_data_writeval_disk_size`/`index_lengthval`을 재호출하지 않음. T_NORMAL(`f_valp[]`)은 배열 변환 없이 받는 오버로드 `qfile_tuple_size/fill_from_values`. 출력은 항상 `char *out`(페이지·private 버퍼 공용). 두 함수는 `static inline`. | #186 §5: 4 디스크립터 경로 + fast_* 3 + 페이지 밖 5곳 수렴, T_MERGE O(n²)→O(n). inline은 D-182-12의 상수 전파 조건. | — |
| D-182-12 | **`qfile_fast_intint/intval/val_tuple_to_list` 삭제**(호출 8곳: 분석함수 6 + INSERT RETURN_GENERATED_KEYS 2). 호출자는 스택 `src[2]`로 조립기 호출. | cpp-perf 판정: `fast_val` 2곳(query_executor.c:13562/13737)은 문장당 1회 cold; `fast_intint/intval`은 그룹당·정렬키 값당 1회(행당 아님). 일반 경로 추가 비용 = 컬럼당 예측되는 분기 3개 × 2 ≈ 수 cycle, 같은 호출의 페이지 fix + memcpy(수백 cycle)에 묻힘. MEAS-01: 병목 측정 없음 → 특수 경로 유지 근거 없음. A59: inline 후 `is_null=false`/`val==NULL` 상수 전파로 분기가 접힘. | #193 마이크로벤치(고카디널리티 PARTITION BY)에서 회귀 시 래퍼 복원 |
| D-182-13 | **in-place**: `qfile_slot_overwrite_value(rec, col, const DB_VALUE*)` — assert 4개(#185: 값 non-NULL, 기존 열 non-NULL, 도메인 타입 일치, `pr_data_writeval_disk_size == 저장 길이`), release는 `ER_FAILED`. `qfile_set_tuple_column_value`는 페이지/오버플로 골격(복사본 갱신 → `qfile_overwrite_tuple`)을 유지하고 내부만 교체. orderby_num 3지점(query_executor.c:3882/3904/3935, 현재 `qdata_copy_db_value_to_tuple_value`로 헤더 재기록)이 이것으로 통일. | 값 헤더가 없으므로 "헤더까지 다시 쓰는" 경로는 구조적으로 사라짐. | — |
| D-182-14 | **정렬 레코드**: `qfile_initialize_sort_key_info`가 `col_dom[]`로 **키 미니튜플 디스크립터 `key_tl`**(hdr 4, `qfile_type_list_alloc/finalize`)을 만들어 `SORTKEY_INFO`에 넣고 `qfile_clear_sort_key_info`가 해제. 병렬 정렬 워커가 `key_info`를 **읽기 전용 공유**하므로 슬롯은 넣지 않고, `qfile_compare_partial_sort_record`가 호출마다 스택 슬롯 2개를 bind+set_tuple(스토어 ~6개). P 본문은 입력 슬롯 deform → 조립기(`qfile_make_sort_key`·`qfile_sort_get_next_parallel` 60줄 복제를 helper 1개로). 가변 키 `sort_f`는 `index_cmpdisk`, 없으면 D-182-10 폴백 후 `data_cmpdisk`. `qfile_compare_with_interpolation_domain`은 `(data*, len)` 시그니처. A_sort_key `offset[]`·0=NULL 유지, 슬롯 길이는 SORT_REC 전용 `[4B len][data]`(#186). | 오늘 키 i 도달에 i-1개 헤더 워크 → 고정 키는 O(1). | — |
| D-182-15 | **해시조인 선두 키**(query_hash_join.c:3065-3072 라이터 + 3171/3509/3821 리더 3벌, `assert(len==MAX_ALIGNMENT)` + 고정 오프셋 16 직접 읽기) → 위치 접근자 col 0(항상 bound·FIXED 4B라 fast path, has_null 비트 검사 1회) + 디스크립터 assert `col[0].kind==FIXED && size==4`. `hjoin_fetch_key`(2938-3028)·`hjoin_merge_tuple`(4362-4366) 순차 워크는 슬롯 접근자로. **분석함수 2필드**(query_executor.c:23783/23825 `DB_ALIGN(disksize, MAX_ALIGNMENT)` stride) → 위치 접근자 col 0/1. group/value 스캔은 prev도 쓰므로(23906-23960) 두 방향 모두 `set_tuple` 경유. | 직접 캐스트 잔존 지점을 접근자 내부 한 곳으로(#180 이관 조건 3). | — |
| D-182-16 | **도메인 구동 순차 원시 함수**(px XASL_SNAPSHOT 리더 전용, D-181-10): `struct qfile_tuple_walk { const char *tpl; const uint8 *bitmap; int col; int off; }` + `qfile_tuple_walk_next(walk, const TP_DOMAIN *dom, char **ptr, int *len, bool *is_null)` — kind/size/alignby를 도메인에서 호출마다 파생. px 리더(px_scan_result_handler.cpp:812-831)는 `hdr_size`를 `list_id_header`에서 atomic으로 읽어 시작 `off`를 잡고, 818의 미검사 반환값을 검사로 바꿈. 디버그: 디스크립터 경로와 결과 교차 assert. | 리더는 이미 컬럼마다 도메인을 load하므로 파생 비용은 분기 몇 개. | — |
| D-182-17 | **PR 분할**(fog 졸업): **PR-1a** = D-182-1/2/5/6 슬롯 도입 + fetch 경로 시그니처 교체(순수 기계적, 컴파일러 검증) / **PR-1b** = 접근자 호출 치환(`QFILE_GET_TUPLE_VALUE_HEADER_POSITION` 14, `qfile_locate_tuple_value` 12, `qfile_locate_tuple_next_value` 8, 해시조인 4벌, 분석함수 2, orderby_num 3, cursor.c, `hjoin_fetch_key`/`hjoin_merge_tuple`) + `QFILE_GET_TUPLE_LENGTH` 마스킹·`OR_GET_DOUBLE/FLOAT` memcpy + `qfile_type_list_alloc/finalize`·pack flag(#181) + 정렬 입력 un-read save/jump(#184) + `fetch_peek_dbval_pos` 삭제. 접근자 **구현체**는 PR-1에서 구 포맷 헤더 워크로 동작, **PR-2**가 구현체와 조립기 내부만 새 포맷으로 교체. 모두 개인 fork 브랜치 간 PR. | 1a는 diff 크기와 무관하게 리뷰가 쉽고, 1b가 CTP sql 전수를 실제로 요구하는 단계. | — |

## 2. 슬롯 구조체 (최종)

```c
struct qfile_tuple_record {                  /* = 튜플 슬롯 (D-182-2) */
  char *tpl;                                 /* 기존 */
  int size;                                  /* 기존: >0 소유 버퍼, 0 비소유(PEEK). 캐시와 직교 */
  const QFILE_TUPLE_VALUE_TYPE_LIST *tl;     /* qfile_slot_bind 1회 (D-182-6) */
  int16_t nvalid;                            /* 여기까지 걸었다 (PG tts_nvalid) */
  int16_t fast_limit;                        /* 튜플별 상수 접두 끝 (D-182-4) */
  int32_t off;                               /* nvalid 컬럼의 시작 오프셋 (PG off), 튜플 시작 기준 */
  char *scratch;                             /* VAR/SCRATCH 전용, 지연 할당 (D-182-10) */
  int scratch_size;
};
```

## 3. API 요약

```c
/* 슬롯 수명 */
void qfile_slot_bind      (QFILE_TUPLE_RECORD *rec, const QFILE_TUPLE_VALUE_TYPE_LIST *tl);   /* open 시 1회 */
void qfile_slot_set_tuple (QFILE_TUPLE_RECORD *rec, char *tpl);                               /* tpl 변경의 유일한 길 */
void qfile_slot_clear     (QFILE_TUPLE_RECORD *rec);                                          /* scratch 해제 */

/* 읽기 — 위치 / 값 / 일괄 */
const char *qfile_slot_locate        (QFILE_TUPLE_RECORD *rec, int col, int *body_len, bool *is_null);
int         qfile_slot_read_value    (QFILE_TUPLE_RECORD *rec, int col, DB_VALUE *v, bool copy);
int         qfile_slot_read_val_list (QFILE_TUPLE_RECORD *rec, VAL_LIST *vl);

/* 쓰기 — 조립기(2패스, static inline) / in-place */
int  qfile_tuple_size (const QFILE_TUPLE_VALUE_TYPE_LIST *tl, QFILE_TUPLE_COL_SRC *src, int n, bool *has_null);
void qfile_tuple_fill (const QFILE_TUPLE_VALUE_TYPE_LIST *tl, const QFILE_TUPLE_COL_SRC *src, int n, char *out, int size, bool has_null);
int  qfile_tuple_size_from_values (const QFILE_TUPLE_VALUE_TYPE_LIST *tl, DB_VALUE **vals, int n, bool *has_null);   /* T_NORMAL */
int  qfile_slot_overwrite_value (QFILE_TUPLE_RECORD *rec, int col, const DB_VALUE *v);   /* D-182-13 */

/* 정렬 비교 */
DB_VALUE_COMPARE_RESULT qfile_slot_cmp_value (QFILE_TUPLE_RECORD *a, QFILE_TUPLE_RECORD *b, int col, const SUBKEY_INFO *k);

/* px 리더 전용, 디스크립터 없음 (D-182-16) */
int qfile_tuple_walk_next (QFILE_TUPLE_WALK *w, const TP_DOMAIN *dom, char **ptr, int *len, bool *is_null);
```

## 4. 이 티켓이 넘기는 것

- **#188 ADR 0016** 잠금 항목: D-182-1(슬롯이 fetch 경로를 탄다 — 포맷이 자기 기술적이지 않음), D-182-2(RECORD 확장), D-182-10(슬롯 소유 스크래치, or_buf 계약 불변).
- **#189 PR-1**: D-182-17의 1a/1b 분할과 각 범위. `fetch_peek_dbval_pos` 삭제 검증 조건(D-182-8).
- **#190 PR-2**: 접근자 구현체·조립기 내부 교체, fast_* 삭제(D-182-12), 정렬 레코드(D-182-14), px walk(D-182-16).
- **#193 성능**: D-182-12 마이크로벤치 조건(고카디널리티 PARTITION BY), SCRATCH 타입 리스트 실측(#180 §14.2).
- **맵 Out of scope**: `or_buf` 정렬 계약 변경(`OR_GET_INT/SHORT` memcpy화 + ASSERT_ALIGN 해제).
- **용어(CONTEXT.md)**: 튜플 슬롯, 위치/값/일괄 접근자, 튜플 조립기.
