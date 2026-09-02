# CBRD-27365 연구: 정렬 레코드(P/A_sort_key) 경로와 늦은 도메인 확정 정밀 조사

- 티켓: xmilex-git/workspace #186 (맵 #179의 일부)
- 조사 대상: `/home/cubrid/dev/cubrid` (develop, `77bd76bab`), 읽기 전용
- 작성일: 2026-09-02

## 0. 결론 요약 (답부터)

1. **SORT_REC는 두 표현이 하나의 union을 공유한다.** `use_original = (nkeys != type_cnt)` 한 줄이 선택한다(`list_file.c:4475`).
   P_sort_key(부분 키)는 `[next 8B][pageid 4][volid 2][offset 2][8B 정렬 패딩][8B hdr+data 반복]`, A_sort_key(전체 컬럼 정렬)는 `[next 8B][int offset[nkeys]][8B 정렬 패딩][8B hdr+data 반복(NULL 제외)]`이며 `offset[i]==0`이 NULL, 0이 아니면 SORT_REC 시작에서 **데이터 바이트(8B 헤더 뒤)** 까지의 거리다.
2. **P 본문을 "키 컬럼만의 새 포맷 미니 튜플"로 바꿀 때 바뀌는 함수는 5개**: `qfile_make_sort_key`(P 분기), `qfile_sort_get_next_parallel`(P 분기, 복제 코드), `qfile_compare_partial_sort_record`, `qfile_compare_with_interpolation_domain`, `qfile_initialize_sort_key_info`(키 레이아웃 디스크립터 준비). P의 **소비자**(put_next 계열 5곳)는 `s.original.{pageid,volid,offset}`만 읽으므로 본문 변경에 무관하다.
   **A_sort_key의 offset[] 테이블과 `0=NULL` 규약은 그대로 둘 수 있다.** 단, A 본문 슬롯의 "길이"를 오늘은 `offset-8` 위치의 옛 8B 헤더에서 읽으므로(`3664`, `1743`, `4181`) 이 길이 조회를 SORT_REC 전용 규약(예: `[4B len][data]`)으로 바꾸고, A의 출력 쓰기 2곳(`qfile_save_sort_key_tuple`, `qfile_generate_sort_tuple`)이 새 튜플 조립기를 쓰면 된다. `qfile_compare_all_sort_record`는 데이터 포인터만 쓰므로 무변경.
3. **`external_sort.c`는 RECDES를 완전히 불투명하게 다룬다.** 7,521줄 중 SORT_REC를 만지는 곳은 `->next` 링크 8곳뿐이고 `QFILE_*` 튜플 매크로는 0회다. 병렬 정렬(`SORT_LISTFILE_PX_ARG`)도 `key_info`·`input_list` 포인터를 전달만 한다. 단 두 가지 **프로토콜 의존**은 유지해야 한다: (i) `next`가 레코드 오프셋 0에 있어야 하고, (ii) get 함수는 버퍼가 모자라도 필요한 전체 길이를 `recdes->length`에 써서 `SORT_REC_DOESNT_FIT`를 돌려야 한다(2패스 "pretend copy").
4. **늦은 도메인 확정: 확정 전에 튜플이 쓰일 수 있다. 그러나 그 튜플의 해당 컬럼은 반드시 NULL이다.** `qexec_generate_tuple_descriptor`는 `is_domain_resolved==false`인 동안 **매 튜플마다** `qfile_update_domains_on_type_list`를 호출하고, 값이 NULL이어서 regu 도메인이 아직 `DB_TYPE_VARIABLE`이면 미확정 상태로 그 튜플을 그냥 쓴다(`query_executor.c:982-988`, `list_file.c:7063-7076`). 값이 non-NULL이면 `fetch.c:4582-4587`이 항상 regu 도메인을 확정한다. 따라서 **NULL이 레이아웃 무관(비트맵 비트 + 0바이트)인 새 포맷에서는 확정 후 레이아웃 디스크립터를 다시 finalize해도 안전하다.** 단 미확정 컬럼은 그 시점까지 "가변 길이·상수 오프셋 접두 종료"로 취급해야 한다.
   클라이언트로는 `xqmgr_execute_query`가 **완료된 뒤** `or_pack_listid`가 `type_list.domp[]`를 패킹하므로(`network_interface_sr.cpp:5819` → `5947`) 확정된 도메인이 전달된다.
5. **4개 QFILE_TUPLE_DESCRIPTOR 경로 + 3개 hand-rolled 라이터 + 페이지 밖 조립기 5곳은 단일 조립기로 수렴 가능하다.** 공통 입력은 "컬럼별 `(data*, len, is_null)` 또는 `DB_VALUE*`" 배열이고, 조립기는 `size(desc, cols)` → `fill(desc, cols, out_buf)` 2패스면 된다. 페이지가 아닌 임의 버퍼(top-n, 해시 조인 오버플로, 정렬 재구성)에도 써야 하므로 조립기 출력은 `char *out`이어야 한다.

## 1. SORT_REC 생산·소비 전수 지도

### 1.1 구조체와 표현 선택

`src/storage/external_sort.h:77-99`:

```
struct SORT_REC {
  SORT_REC *next;                     /* 중복 키 체인 (external_sort.c 전용) */
  union {
    struct { INT32 pageid; INT16 volid; INT16 offset; char body[1]; } original;  /* P */
    int offset[1];                    /* A: 0 = NULL, else SORT_REC 시작→데이터 바이트 거리 */
  } s;
};
```

- `SORTKEY_INFO.use_original`(`external_sort.h:132`)이 표현을 고른다. `qfile_initialize_sort_key_info`(`list_file.c:4454`)에서 `n = sort_list 길이(또는 type_cnt)`, `use_original = (n != types->type_cnt)`(`4474-4475`).
  - P: 정렬 키가 컬럼의 진부분집합 → 키만 복사하고 원본 튜플 위치를 기억, 출력 시 원본 페이지를 다시 fix.
  - A: 전체 컬럼이 정렬 키(DISTINCT, 전 컬럼 ORDER BY, 집계 없는 GROUP BY) → 정렬 레코드에서 튜플을 재구성하므로 원본 재방문 없음.
- 호출자가 강제하는 경우: 분석 함수는 항상 P(`query_executor.c:22148`, `22611`), GROUP BY는 재계산(`5639`), 해시 GROUP BY 파티션 정렬은 `qfile_initialize_sort_key_info` 결과 그대로(`4495`, `5559`).
- `permuted_col`(`4520-4527`): P에서는 `key[i].permuted_col = i`. A에서는 `key[pos_no].permuted_col = i`, 즉 **컬럼 위치로 색인해서 "그 컬럼이 들어간 정렬 슬롯 번호"** 를 얻는다. SUBKEY_INFO 배열이 `col/col_dom/sort_f`는 정렬 순서로, `permuted_col`은 컬럼 순서로 색인되는 2중 인덱싱이며 A에서 `nkeys == type_cnt`라서 성립한다.
- 잠재 결함(참고): `4505-4508`에서 `pos_descr.dom`이 `DB_TYPE_VARIABLE`이면 `types->domp[i]`를 쓰는데 `i`는 정렬 키 순번이지 `pos_no`가 아니다. 호출자들이 사전에 `pos_descr.dom`을 확정해 두므로(`query_executor.c:20833-20845` `qexec_resolve_domains_on_sort_list`, `22683-22690` 분석 함수) 실제로는 거의 도달하지 않는다.

### 1.2 생산자 (SORT_REC를 만드는 곳)

| 함수 | 위치 | 역할 |
|---|---|---|
| `qfile_make_sort_key` | `list_file.c:3511-3639` | 유일한 직렬 빌더. `qfile_scan_list_next(PEEK)`로 입력 튜플을 얻고 P/A 본문을 만든다. |
| `qfile_sort_get_next_parallel` | `list_file.c:3863-4020` (SERVER_MODE) | 병렬 워커용. 섹터 비트맵으로 페이지를 훔쳐 오고 `3927-3999`가 `qfile_make_sort_key`를 **그대로 복제**한다("mirrors qfile_make_sort_key"). `external_sort.c:6662`, `6801`에서 워커 `get_fn`으로 연결. |
| `qfile_get_next_sort_item` | `list_file.c:4038` | `sort_listfile` 기본 get. `qfile_make_sort_key` 래퍼. |
| `qexec_gby_get_next` / `qexec_hash_gby_get_next` / `qexec_analytic_get_next` | `query_executor.c:5050`, `4880`, `22705` | 모두 `qfile_make_sort_key` 래퍼. |

P 본문 생성(`3531-3568`): `data = PTR_ALIGN(&s.original.body[0], 8)`; 키 i마다 `QFILE_GET_TUPLE_VALUE_HEADER_POSITION(tpl, key[i].col)`로 입력 튜플을 **선형 탐색**한 뒤 `[8B hdr][data]`를 `memcpy`. NULL은 `V_UNBOUND, len 0` 헤더 8B가 그대로 들어간다(P에서 NULL은 8B 비용).
A 본문 생성(`3570-3620`): `data = PTR_ALIGN(&s.offset[nkeys], 8)`; non-NULL만 `[8B hdr][data]`를 복사하고 `offset[i] = data - rec + 8`(데이터 시작). NULL은 `offset[i] = 0`, 바이트 없음.
두 분기 모두 "버퍼에 안 들어가도 길이는 끝까지 계산"하고(`3557-3563` 주석 "Always pretend that we copied"), 넘치면 `qfile_scan_prev`로 되감고 `SORT_REC_DOESNT_FIT`(`3629-3636`).

### 1.3 비교자

| 함수 | 위치 | 표현 | 방식 |
|---|---|---|---|
| `qfile_compare_partial_sort_record` | `4234-4310` | P | 두 본문을 앞에서부터 **순차 워크**. `QFILE_GET_TUPLE_VALUE_FLAG`로 NULL 판정, `QFILE_GET_TUPLE_VALUE_LENGTH`로 다음 키로 전진(`4302-4303`). 값 비교는 `sort_f(d0, d1, col_dom, 0, 1, NULL)` = `pr_type::data_cmpdisk`(디스크 표현 직접 비교). `use_cmp_dom`이면 아래 함수. |
| `qfile_compare_all_sort_record` | `4312-4350` | A | `offset[i]`가 0이면 NULL, 아니면 `rec + offset[i]`를 `sort_f`에. 헤더를 전혀 읽지 않는다. |
| `qfile_compare_with_interpolation_domain` | `7332-7430` | P만 | MEDIAN/PERCENTILE 문자열 키. `fp0/fp1`(헤더 포인터)에서 `QFILE_GET_TUPLE_VALUE_LENGTH`로 `or_init` 크기를 잡고 `data_readval` → `tp_value_cast` → `cmpval`. 첫 호출 때 `cmp_dom`을 지연 결정(`7353-7370`). `use_cmp_dom`은 `query_executor.c:22664-22673`에서 세팅. |
| `qfile_compare_with_null_value` | `4366-4400` | 공통 | `is_nulls_first`로 NULL 순서. |
| 롤업 레벨 판정 | `query_executor.c:19992-20005` | P/A | `key_info.nkeys`를 1..n으로 잘라 `cmp_fn`을 반복 호출(접두 비교). |

`sort_listfile`에는 `cmp_arg = &key_info`가 그대로 전달된다(`list_file.c:4726`, `external_sort.c:1390-1392`).

### 1.4 소비자 (정렬 결과를 출력 리스트로)

| 함수 | 위치 | P 처리 | A 처리 |
|---|---|---|---|
| `qfile_put_next_sort_item` | `list_file.c:4074-4222` | `qmgr_get_old_page_simple_fix(vpid)` → 오버플로 없으면 `page + s.original.offset`을 `qfile_add_tuple_to_list`(원시 복사), 있으면 `qfile_add_overflow_tuple_to_list` | `tpl_size = 8 + 8*nkeys + Σ len(offset-8 헤더)`(`4171-4186`); 페이지 안이면 `tpl_descr.sortkey_info/sort_rec`를 채워 `T_SORTKEY`로 `qfile_generate_tuple_into_list`(`4196`), 크면 `qfile_generate_sort_tuple` 후 `qfile_add_tuple_to_list`(`4207-4213`) |
| `qfile_save_sort_key_tuple` | `1719-1753` | - | T_SORTKEY 라이터. `c = key[i].permuted_col; offset[c]`로 컬럼 순서 재구성, `[8B hdr][data]` memcpy |
| `qfile_generate_sort_tuple` | `3647-3712` | - | 위와 같은 재구성을 private 버퍼로(BIG 튜플, 그리고 GROUP BY/해시 GROUP BY/ORDER BY 경로가 공용) |
| `qexec_ordby_put_next` | `query_executor.c:3779-3945` | 원본 페이지 fix 후 **in-place로 `orderby_num()` 덮어쓰기**(`3876-3883`, 오버플로 시 `qfile_get_tuple`로 복사 후 덮어쓰기 `3893-3905`) | `qfile_generate_sort_tuple` 결과에 덮어쓰기(`3924-3935`) |
| `qexec_gby_put_next` | `5066-5331` | `s.original`로 원본 재방문 | `qfile_generate_sort_tuple`(`5162`) |
| `qexec_hash_gby_put_next` | `4895-4990` | 원본 재방문 후 `qdata_load_agg_hentry_from_tuple` | `qfile_generate_sort_tuple`(`4973`) |
| `qexec_analytic_put_next` | `22722-22909` | 항상 P. 페이지 캐시(`curr_sort_page`)로 재방문 | - |

관찰: **P의 모든 소비자는 `s.original.{pageid, volid, offset}` 세 필드만 읽고 본문(body)은 한 번도 읽지 않는다.** 본문은 비교자 전용이다. 반대로 A의 소비자는 본문을 읽어 튜플을 재구성한다.

### 1.5 크기 추정

`qfile_get_estimated_pages_for_sorting`(`4415-4445`)은 P는 `offsetof(s.original.body)`, A는 `offsetof(s.offset)+4*nkeys`만 오버헤드로 더한다(본문 크기는 미포함, 주석의 P/A 설명이 서로 바뀌어 있음). 새 표현으로 바꿔도 이 추정은 손댈 필요가 없다.

## 2. P 본문 → "키 컬럼만의 새 포맷 미니 튜플"로 바꿀 때

### 2.1 바뀌는 지점 (전수)

| # | 함수 | 변경 내용 |
|---|---|---|
| 1 | `qfile_initialize_sort_key_info` (`4454`) | `SORTKEY_INFO`에 **키 미니 튜플의 레이아웃 디스크립터**(키 개수, 각 `col_dom`의 고정/가변·정렬 요구)를 추가로 만든다. 정렬은 리스트가 완전히 쓰인 뒤 실행되므로 이 시점의 `types->domp[]`는 확정 상태다(4장 참고). `qfile_clear_sort_key_info`(`4552`)에서 해제. |
| 2 | `qfile_make_sort_key` P 분기 (`3531-3568`) | 입력 튜플을 새 접근자로 deform해 키 컬럼의 `(data*, len, is_null)`을 얻고, 미니 튜플 조립기 `size → fill`로 본문을 만든다. `DOESNT_FIT` 프로토콜(길이는 끝까지 계산, `recdes->length`에 기록)은 `size` 패스가 그대로 만족시킨다. |
| 3 | `qfile_sort_get_next_parallel` P 분기 (`3936-3961`) | #2와 동일. 이 기회에 두 함수의 본문 빌드를 **하나의 정적 helper**로 합치면 복제 코드가 사라진다(오늘은 SORT_REC 빌드 60줄이 두 벌). |
| 4 | `qfile_compare_partial_sort_record` (`4234`) | 순차 헤더 워크를 미니 튜플 deform으로 교체. 모든 키가 고정 길이·non-NULL이면 상수 오프셋으로 O(1) 접근(오늘은 키 i에 도달하기 위해 i-1개 헤더를 읽는다). 롤업의 "nkeys 잘라 접두 비교"(`19992`)는 접두 deform과 자연스럽게 호환. |
| 5 | `qfile_compare_with_interpolation_domain` (`7332`) | 시그니처를 헤더 포인터 `fp0/fp1`에서 `(data*, len)` 쌍으로 바꾼다. 내부의 `QFILE_GET_TUPLE_VALUE_LENGTH(fp0)` 4회(`7357`, `7383`, `7391` 등)가 `len` 인자로 대체된다. |

**바뀌지 않는 곳**: `qfile_put_next_sort_item` P 분기, `qexec_ordby_put_next`, `qexec_gby_put_next`, `qexec_hash_gby_put_next`, `qexec_analytic_put_next`, `qfile_get_next_sort_item`, `qfile_get_estimated_pages_for_sorting`, `external_sort.c` 전체. (이들이 원본 튜플에 쓰는 `QFILE_GET_TUPLE_VALUE_HEADER_POSITION` 등은 **주 포맷 교체**의 변경 지점이지 정렬 레코드 변경 지점이 아니다.)

### 2.2 A_sort_key: offset[] 테이블은 유지 가능

- `offset[i]`의 의미("0=NULL, 아니면 SORT_REC 시작→데이터 바이트")와 이를 읽는 `qfile_compare_all_sort_record`는 **무변경**.
- 오늘 A 본문 슬롯은 `[8B hdr][data]`이고 길이를 `offset[i] - 8` 위치의 옛 헤더에서 읽는 곳이 3곳이다: `qfile_generate_sort_tuple:3664`, `qfile_save_sort_key_tuple:1743`, `qfile_put_next_sort_item:4181`. 옛 헤더 매크로를 없애려면 A 본문 슬롯을 SORT_REC 전용 규약 `[4B len][data(8B 정렬)]`로 두고 `SORT_REC_A_LEN(rec, off)` 같은 전용 접근자로 바꾸면 된다(3곳 + 빌더 2곳의 `memcpy` 원본이 헤더 없는 `data*`가 됨). 길이 자체를 `col_dom`에서 유도(고정 타입)하거나 새 포맷 가변 헤더에서 읽는 방법도 가능하지만, 규약을 SORT_REC 안에 닫아 두는 쪽이 튜플 포맷 의존을 끊는다.
- A 출력 쓰기 2곳(`qfile_save_sort_key_tuple`, `qfile_generate_sort_tuple`)은 `permuted_col`로 컬럼 순서를 복원한 `(data*, len, is_null)` 배열을 만들어 새 조립기에 넘기면 된다(5장).
- `qfile_put_next_sort_item:4171-4186`의 `tpl_size` 사전 계산은 조립기 `size` 패스로 대체된다.

### 2.3 비교 함수 계약 주의

`sort_f`는 `pr_type::data_cmpdisk`이며 **디스크 표현의 시작 포인터**를 받는다(`4281`, `4327`). 문자열 계열 디스크 표현은 자체 길이 접두를 포함하므로 오늘 8B 헤더의 길이 필드는 비교에 쓰이지 않고 오직 "다음 키로 전진"에만 쓰인다. 새 포맷에서 가변 값 앞에 1B/4B 길이 헤더를 두기로 했으므로(맵 확정 사항), 비교자는 그 헤더를 건너뛴 디스크 표현 포인터를 `sort_f`에 넘겨야 한다. 포맷 명세 티켓이 "가변 값의 1B/4B 헤더가 OR 내부 길이 접두와 중복되는지"를 확인할 때 이 사실을 함께 볼 것.

## 3. `external_sort.c`는 포맷 무관인가 — 검증

- `grep -n "QFILE_" external_sort.c`: 튜플 매크로 0회. 나오는 것은 `QFILE_LIST_ID`/`QFILE_FREE_AND_INIT_LIST_ID`/`QFILE_LIST_SECTOR_SCAN_INFO` 타입 관리(`216`, `5641`, `5698`, `6436-6774`)만이다. `s.original`, `s.offset` 접근 0회.
- SORT_REC를 만지는 8곳은 전부 `->next` 링크: `sort_append:903-913`(중복 키 체인 연결), `sort_run_flush:2432-2445`(체인 순회), 머지 출력 `3008-3010`, `3417-3419`, `4613-4615`, 병렬 머지 `5827`(`next = NULL` 컷오프).
- 레코드 저장은 바이트 복사: `sort_spage_insert:631-655`가 `memcpy(pgptr+roffset, recdes->data, recdes->length)`. 큰 레코드는 `REC_BIGONE`으로 오버플로 파일에 넣고 `sort_retrieve_longrec:2518`이 `overflow_get`으로 되읽는다. 내용 해석 없음.
- 메모리 정렬 단계(`sort_inphase_sort:1954-`)는 `temp_recdes.area_size <= sizeof(SORT_REC)`이면 get을 부르지 않고 `DOESNT_FIT`(`2027`), 아니면 `get_fn`이 채운 `recdes->length`로 배치한다(`2034`). 따라서 **get 함수는 안 들어가도 필요 길이를 알려 줘야 한다**는 계약이 유지 조건.
- 병렬: `SORT_LISTFILE_PX_ARG`(`external_sort.h:158-166`)는 `key_info`, `input_list`, `hash_eligible`, `stats`, `parallelism` 포인터/정수만 담는다. `sort_check_parallelism:6430-6445`, `sort_start_parallelism:6731-6774`는 `page_cnt/tuple_cnt`로 병렬도를 정하고 `qfile_open_list_sector_scan`, `qfile_clone_list_id`를 부를 뿐이다. 워커의 `get_fn`은 `list_file.c`의 `qfile_sort_get_next_parallel`(`6662`, `6801`)이며 포맷 지식은 여전히 `list_file.c` 안에 있다. `btree_load.c`도 같은 `sort_listfile`을 자기 레코드 포맷으로 쓴다는 점이 "불투명" 주장을 뒷받침한다(`btree_load.c:5449`).

결론: 맵의 "external_sort.c는 포맷 무관" 주장은 사실이다. 유지해야 할 것은 `next`가 오프셋 0이라는 구조체 접두와 `DOESNT_FIT` 2패스 프로토콜 둘뿐이다.

## 4. 늦은 도메인 확정 흐름

### 4.1 `DB_TYPE_VARIABLE` 도메인은 어디서 생기나

- 파서: `PT_TYPE_MAYBE → DB_TYPE_VARIABLE`(`parse_dbi.c:2420-2421`). 호스트 변수(`?`)와 그 위의 연산 결과처럼 컴파일 시점에 타입을 모르는 노드.
- 타입 검사: 늦은 바인딩 연산(`pt_is_op_hv_late_bind`)이나 서브쿼리 인자는 CAST로 감싸고 `expected_domain = NULL`로 두어 "XASL 생성 시 DB_TYPE_VARIABLE 도메인으로 대체"된다(`type_checking.c:4655-4667`). IFNULL/COALESCE/NVL의 인자 도메인 해석에도 등장(`13035`).
- 실행기 주석이 든 예: `ORDER BY val + ?`(`query_executor.c:27279`), `SELECT ?` 류의 outptr, 집계 피연산자(`21234-21265`), 분석 함수 피연산자(`query_analytic.cpp:140`, `607-679`). 같은 함수가 `collation_flag != TP_DOMAIN_COLL_NORMAL`(콜레이션 미확정 문자열)도 함께 확정한다(`7079-7093`).

### 4.2 확정 메커니즘

1. **regu 변수 레벨** — `fetch.c`: 산술식은 평가 직전 `regu_var->domain`을 NULL로 비우고(`676-680`) 평가 후 `tp_domain_resolve_value(value)`로 확정, 값이 NULL이면 `DB_TYPE_VARIABLE`을 유지(`3825-3837`). 일반 regu는 `*peek_dbval`이 **non-NULL일 때만** `tp_domain_resolve_value`(`4582-4587`). 즉 non-NULL 값이 한 번 나오면 regu 도메인은 확정된다.
2. **리스트 레벨** — `qfile_update_domains_on_type_list(list_file.c:7038-7111)`: `type_list.domp[count]`가 VARIABLE이고 regu 도메인이 확정돼 있으면 복사(`7073-7076`), regu도 VARIABLE이면 `is_domain_resolved = false`로 남기고 "다음 튜플에서 재시도"(`7065-7071`). 한 번 non-VARIABLE로 채워진 컬럼은 다시 바뀌지 않는다.
3. **호출 시점** — `qexec_generate_tuple_descriptor(query_executor.c:952-993)`가 `qdata_generate_tuple_desc_for_valptr_list` 직후 `if (list_id->is_domain_resolved == false)`이면 호출(`982-988`). 호출자 4곳: BUILDLIST 본체(`1200`), BUILDVALUE(`15350`), `qexec_insert_tuple_into_list`(`18749`, CONNECT BY 등), GROUP BY 출력(`20243`). 리스트는 `QFILE_CLEAR_LIST_ID`로 `is_domain_resolved = false`에서 시작(`query_list.h:480`).

### 4.3 확정 전에 쓰인 튜플이 있을 수 있는가

**있다. 단, 그 튜플의 미확정 컬럼 값은 반드시 NULL이다.**

- 근거 1: 미확정이 남는 유일한 분기는 "regu 도메인도 VARIABLE"(`7065`)이고, 이는 `fetch.c`가 값이 NULL일 때만 남기는 상태다(`4582`, `3829-3836`).
- 근거 2: `qexec_generate_tuple_descriptor`는 `is_domain_resolved`가 false여도 `status`를 그대로 돌려 호출자가 튜플을 쓴다(`991`). 실패로 바꾸지 않는다.
- 근거 3: 튜플 값 바이트는 `type_list` 도메인이 아니라 **DB_VALUE 자신의 타입**으로 기록된다(`qdata_copy_db_value_to_tuple_value`, `query_opfunc.c:356-408`: `pr_type_from_id(DB_VALUE_DOMAIN_TYPE(dbval))->data_writeval`). 따라서 도메인 확정은 리더 메타데이터만 바꾸며 이미 쓰인 바이트를 재해석하게 만들지 않는다.
- 예: `SELECT CASE WHEN a > 0 THEN ? ELSE NULL END FROM t` 에서 첫 행이 ELSE 분기면 컬럼은 VARIABLE 상태로 NULL 튜플이 쓰이고, 다음 행이 THEN 분기일 때 확정된다.

새 포맷에 대한 함의:
- NULL은 비트맵 비트 + 0바이트이므로 레이아웃(고정 폭, 정렬 요구)에 독립적이다. → **확정 후 레이아웃 디스크립터를 다시 finalize해도 기존 튜플은 그대로 읽힌다.**
- 조건: 미확정 컬럼은 확정 전까지 "가변 길이(폭 미상)"로 취급해 상수 오프셋 접두를 그 앞에서 끊어야 한다. 미확정 컬럼이 NULL인 튜플은 어차피 has-null 튜플이라 비트맵 경로로 deform되므로 그 뒤 컬럼의 상수 오프셋도 쓰이지 않는다.
- 리스트 밖으로 나가는 사본: 정렬 출력 리스트는 `qfile_sort_list_with_func`가 `&list_id_p->type_list`로 열어(`list_file.c:4656`, `qfile_open_list`가 `domp` memcpy) 정렬 시점(= 모든 튜플이 쓰인 뒤)의 도메인을 물려받는다. UNION 등 `qfile_unify_types(895-935)`는 VARIABLE을 만나면 반대편 도메인을 채택하되 `assert_release(tuple_cnt == 0)`를 건다(`913`, `920`) — 위 4.3에 따르면 "NULL만 든 튜플이 있는 VARIABLE 리스트"가 가능하므로 이 assert는 이론상 깨질 수 있는 기존 잠재 결함이다(이번 조사에서 재현하지는 않음).

### 4.4 확정된 도메인이 클라이언트에 도달하는가

- `sqmgr_execute_query(network_interface_sr.cpp:5682)`: `xqmgr_execute_query`(`5819`)가 **리스트 실행을 끝내고 돌아온 뒤** `or_pack_listid(replydata, list_id)`(`5947`)로 응답을 만든다. `or_pack_listid`는 `type_cnt`와 `domp[i]`를 `or_pack_domain`으로 직렬화한다(`object_representation.c:5286-5292`).
- 클라이언트 `cursor.c`는 `type_list.domp[i]`로 `pr_type->data_readval`을 부른다(`469`, `375-401`). `V_UNBOUND`면 데이터를 읽지 않고 반환(`389-393`)하므로, 모든 행이 NULL이어서 끝까지 VARIABLE로 남은 컬럼도 안전하다. 새 포맷에서 클라이언트가 `type_list`로 레이아웃 디스크립터를 만들 때 VARIABLE 컬럼을 가변으로 두면 같은 이유로 안전하다.
- 정렬 키 도메인: `qfile_initialize_sort_key_info`는 정렬 직전에 `types->domp[]`를 읽으므로 확정된 도메인을 본다. `sort_f`(`data_cmpdisk`)는 도메인 포인터를 그대로 받는다(`4506`, `4509`).

## 5. 네 경로가 단일 "튜플 조립기"로 수렴 가능한가

### 5.1 오늘의 라이터와 각각의 입력

| 경로 | 함수 | 크기 계산 | 채우기 입력 |
|---|---|---|---|
| T_NORMAL | `qfile_save_normal_tuple:1699` | 사전에 `qdata_generate_tuple_desc_for_valptr_list`(`query_opfunc.c:625-700`)가 `pr_data_writeval_disk_size`로 합산 → `tpl_descr.tpl_size` | `f_cnt`개의 `DB_VALUE *`(`f_valp[]`); 컬럼마다 `data_writeval`을 목적지에 직접 |
| T_SORTKEY | `qfile_save_sort_key_tuple:1719` | `qfile_put_next_sort_item:4171-4186`이 offset 테이블로 합산 | `(SORTKEY_INFO*, SORT_REC*)`; 컬럼 i의 소스는 `offset[permuted_col]` → `(data*, len, is_null)` |
| T_MERGE | `qfile_save_merge_tuple:1755` | 호출자는 두 입력 튜플 길이 합을 **상한**으로만 넘기고(`query_executor.c:6079`, `query_hash_join.c:4266-4268`) 실제 길이는 채우면서 계산해 `*tuple_length_p`로 돌려준다 | `tplrec1/tplrec2 + QFILE_LIST_MERGE_INFO(ls_pos_list, ls_outer_inner_list)`; 소스 튜플이 없으면 UNBOUND. 컬럼마다 `QFILE_GET_TUPLE_VALUE_HEADER_POSITION` 선형 탐색(컬럼 수 n에 O(n²)) |
| T_SINGLE_BOUND_ITEM | `qfile_save_single_bound_item_tuple:1676` | `qfile_add_item_to_list:2446-2455` | `(item*, item_size)` 1개, 항상 bound |
| hand-rolled | `qfile_fast_intint_tuple_to_list:1912` | 인라인 상수 | int 2개 |
| hand-rolled | `qfile_fast_intval_tuple_to_list:1972` | 인라인(`pr_data_writeval_disk_size`) | int 1개 + `DB_VALUE*` 1개(NULL 가능) |
| hand-rolled | `qfile_fast_val_tuple_to_list:2059` | 인라인 | `DB_VALUE*` 1개(NULL 가능) |

페이지 밖(private 버퍼)에 같은 포맷을 만드는 조립기도 다섯 곳 더 있다: `qdata_copy_valptr_list_to_tuple`(`query_opfunc.c:421`, BIG 튜플·SET 포함 튜플; 값마다 재평가하며 버퍼를 늘림), `qexec_merge_tuple`(`query_executor.c:5973`)과 `qexec_size_remaining`(`5929`), `hjoin_merge_tuple`(`query_hash_join.c:4314`), `qfile_generate_sort_tuple`(`list_file.c:3647`), `qfile_add_item_to_list` BIG 분기(`2476-`), 그리고 top-n이 메모리 튜플에 `qfile_save_tuple(T_NORMAL)`을 직접 호출하는 곳(`query_executor.c:4723`).

### 5.2 수렴 설계

공통 입력 추상은 **컬럼별 소스 1개**로 충분하다:

```
struct tuple_col_src {
  const DB_VALUE *val;   /* != NULL 이면 data_writeval 경로 (T_NORMAL, fast_*val) */
  const char *data;      /* val == NULL 이면 원시 바이트 복사 (T_SORTKEY, T_MERGE, SINGLE_ITEM) */
  int len;
  bool is_null;
};
```

- **size 패스**: 디스크립터의 고정 폭/정렬 규칙 + 소스의 `len` 또는 `pr_data_writeval_disk_size(val)` + NULL이면 0 + has-null이면 비트맵 워드. 결과가 `tpl_size`. T_MERGE의 "상한 후 실측" 2단계와 T_SORTKEY의 사전 합산 루프가 모두 이 패스로 대체된다. BIG 튜플 판정(`>= QFILE_MAX_TUPLE_SIZE_IN_PAGE`)과 `qfile_fast_*`의 "크면 크기만 돌려주기"도 여기서 나온다.
- **fill 패스**: 길이 워드(has-null 비트) → 비트맵 → 컬럼 순서대로 정렬 패딩 후 값(`val`이면 `data_writeval`을 목적지에 직접, 아니면 `memcpy`). 출력 목적지는 `char *out`(페이지든 private 버퍼든).
- 각 경로가 조립기 앞에서 해야 할 일:
  - T_NORMAL: `f_valp[i] → src[i].val`. (`qdata_generate_tuple_desc_for_valptr_list`가 이미 값을 모아 두므로 배열 변환만 필요)
  - T_SORTKEY: `i`마다 `c = permuted_col[i]`, `offset[c]`로 `(data, len, is_null)`.
  - T_MERGE: 두 소스 튜플을 **한 번씩 deform**해 컬럼 배열을 얻고 `ls_pos_list[i]`로 골라 담는다. 없는 쪽은 `is_null`. 오늘의 O(n²) 헤더 탐색이 O(n)이 된다.
  - T_SINGLE_BOUND_ITEM: n=1 원시 소스.
  - `fast_intint/intval/val`: int를 로컬 4B 버퍼에 `OR_PUT_INT`해 원시 소스로, `DB_VALUE`는 `val` 소스로. 세 함수는 조립기 위의 얇은 래퍼가 되거나 제거 가능(주석이 "qfile_generate_tuple_into_list와 동일한 바이트를 써야 한다"고 요구하므로 조립기 공용화가 그 계약을 기계적으로 보장).
  - 페이지 밖 5곳: 같은 조립기를 `out = private buffer`로 호출. `qdata_copy_valptr_list_to_tuple`는 오늘 값마다 재평가하며 버퍼를 키우는데, `qdata_get_dbval_from_constant_regu_variable`로 이미 얻은 `DB_VALUE*`를 `src[]`로 모아 두면 size 패스가 가능하다(SET 값도 `pr_data_writeval_disk_size`로 크기가 나온다).
- 조립기가 알아야 하는 디스크립터: 컬럼 수, 컬럼별 고정 폭/정렬(또는 가변), 첫 가변 컬럼 인덱스. T_SORTKEY의 A 재구성과 P 미니 튜플(2장)은 각각 "출력 리스트의 디스크립터"와 "키 디스크립터"를 넘기면 같은 함수를 쓴다.

### 5.3 수렴에 걸리는 것

- `qfile_generate_tuple_into_list(1852)`는 `tpl_descr.tpl_size`로 페이지를 먼저 확보한 뒤 채운다. size 패스가 정확한 값을 주므로 T_MERGE의 "상한으로 페이지 확보 후 실제 길이 기록" 관행이 사라지고 `qfile_add_tuple_to_list_id(1596)`의 `(tuple_length, written_tuple_length)` 두 인자도 하나로 줄 수 있다.
- in-place 덮어쓰기 계약(맵의 5지점, 이 조사 범위에서는 `qexec_ordby_put_next:3876-3883`, `3924-3935`)은 조립기가 아니라 접근자 API의 "같은 인코딩 크기 값만" assert로 다룬다.
- `qfile_save_tuple(1808)`의 switch는 소스 배열을 만드는 4개 어댑터로 바뀌고, 디스크립터 안의 경로별 필드(`item/item_size`, `f_valp`, `sortkey_info/sort_rec`, `tplrec1/tplrec2/merge_info`, `query_list.h:368-387`)는 어댑터 입력으로 남기거나 `tuple_col_src[]` 하나로 대체할 수 있다.

## 6. 놀란 점 / 맵에 반영할 사실

1. P 본문은 **비교자만** 읽는다. 소비자 5곳은 원본 위치 3필드만 쓴다 → 미니 튜플 교체의 폭발 반경이 작다.
2. `qfile_sort_get_next_parallel`이 `qfile_make_sort_key`의 SORT_REC 빌드 60줄을 그대로 복제한다. 교체 시 helper 하나로 합칠 것.
3. 늦은 도메인 확정은 "첫 튜플"이 아니라 "**확정될 때까지 매 튜플**"이며, 확정 전 튜플은 존재할 수 있고 그 컬럼은 항상 NULL이다. 값 바이트는 `type_list`가 아닌 DB_VALUE 타입으로 기록된다. → 재finalize 안전.
4. `qfile_unify_types`의 `assert_release(tuple_cnt == 0)`(`list_file.c:913`, `920`)는 위 3과 모순되는 기존 잠재 결함(미재현).
5. `qfile_initialize_sort_key_info:4505`의 `types->domp[i]`는 정렬 순번 인덱스라 `pos_no`와 다를 수 있다(호출자 사전 확정으로 사실상 비활성).
6. T_MERGE 라이터의 컬럼 위치 탐색은 O(n²)이다. deform 1회로 바꾸면 해시 조인/머지 조인 출력에서 부수적 이득.
7. `sort_f = data_cmpdisk`는 디스크 표현 포인터를 받으며 옛 8B 헤더의 길이는 비교에 쓰이지 않는다. 새 포맷 가변 헤더는 비교자가 건너뛰어야 한다.
