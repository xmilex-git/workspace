# CBRD-27365 연구: 리스트 파일 in-place 덮어쓰기 5지점 증명표

- 티켓: xmilex-git/workspace #185 (Part of #179)
- 대상 소스: `/home/cubrid/dev/cubrid` @ `77bd76baba` (develop, 2026-09-02 기준)
- 질문: 각 in-place 덮어쓰기 지점에서 (a) 자리표시자가 **bound**로 먼저 기록되는가, (b) 자리표시자와 덮어쓰기 값의 **인코딩 크기가 항상 같은가**, (c) 새 포맷(has-null 비트·NULL 0바이트·1B/4B 가변 헤더)에서도 계약이 유지되는가.

## 0. 결론 (먼저)

**계약 "bound 값만, 동일 인코딩 크기로만 덮어쓴다"는 5지점 모두에서 성립한다.** 단 두 가지 주의점이 있다.

1. `qexec_ordby_put_next`의 orderby_num 갱신은 `qfile_set_tuple_column_value`가 아니라 `qdata_copy_db_value_to_tuple_value`를 직접 호출하여 **값 헤더(flag+length)까지 다시 쓴다**(query_executor.c:3882/3904/3935). bound 검사도 없다. 오늘 포맷에서는 결과가 동일(bound BIGINT 8B → bound BIGINT 8B)하지만, 새 포맷에서는 값별 8B 헤더가 없으므로 이 지점은 반드시 **본문만 쓰는 접근자**로 바꿔야 한다. 이것이 5지점 중 유일한 "헤더 재기록" 지점이다.
2. orderby_num 위치(`ordbynum_pos`, query_executor.c:4250-4256)와 inst_num 위치(`rownum_col_indices`, px_scan_instnum.cpp:231-238)는 **outptr_list의 regu 인덱스**로 계산되는데, 튜플 작성기 `qdata_copy_valptr_list_to_tuple`(query_opfunc.c:446-450)은 `REGU_VARIABLE_HIDDEN_COLUMN`을 건너뛴다. HIDDEN regu가 그 앞에 있으면 열 번호가 어긋난다. 현재 HIDDEN 열은 클라이언트 측 UPDATE/DELETE/MERGE의 선두 classoid 열(compile.c:213-215, 298)과 cume_dist/percent_rank 인자(xasl_generation.c:28572)뿐이어서 실제 충돌 경로는 확인되지 않았지만, 새 접근자의 **도메인 타입 assert**로 방어하는 것이 맞다(§5).

## 1. 오늘의 튜플/값 인코딩 (증명의 기준)

- 튜플 = `[len 4B][prev_len 4B]` (`QFILE_TUPLE_LENGTH_SIZE` 8, query_list.h:229) + 값들.
- 값 = `[flag 4B][length 4B]` (`QFILE_TUPLE_VALUE_HEADER_SIZE` 8, query_list.h:233) + 본문. 본문 length는 `DB_ALIGN(disk_size, MAX_ALIGNMENT=8)`(query_opfunc.c:398-400). NULL이면 flag=V_UNBOUND, length=0(query_opfunc.c:366-369).
- 열 위치 탐색은 앞 열들의 length를 누적하는 선형 걷기(`QFILE_GET_TUPLE_VALUE_HEADER_POSITION` query_list.h:267-277, `qfile_locate_tuple_value_r` list_file.c:986-1008).
- `qfile_set_tuple_column_value`(list_file.c:7130-7244): 열을 찾아 `flag == V_BOUND`일 때만 `pr_type->data_writeval`로 **본문만** 덧쓴다(7168-7183). unbound면 `ER_FAILED`(7184-7188). 헤더는 건드리지 않는다.

### 타입별 인코딩 크기

| 타입 | disk size 근거 | 본문 크기 | 슬롯(8B 정렬) | 새 포맷 예상 |
|---|---|---|---|---|
| INTEGER | `tp_Integer.disksize = sizeof(int)` (object_primitive.c:922) | 4 | 8 | 고정 4B, 헤더 없음 |
| BIGINT | `tp_Bigint.disksize = sizeof(DB_BIGINT)` (object_primitive.c:972) | 8 | 8 | 고정 8B, 헤더 없음 |
| BIT(floating) | `mr_data_lengthval_bit` floating 분기: `db_get_string_size + OR_INT_SIZE` (object_primitive.c:13065-13075); write: `or_put_int(bit_length)` + `or_put_data(BITS_TO_BYTES)` (13157-13176) | 4 + 40 = **44** | 48 | 가변 44B, **1B 짧은 헤더**(≤127) |

`sizeof(QFILE_TUPLE_POSITION)` = **40** (query_list.h:488-496; `gdb -batch -ex 'p sizeof(struct qfile_tuple_position)' ~/CUBRID/lib/libcubrid.so` → 40). 비트 길이 320.

`DB_DEFAULT_PRECISION`(-1, dbtype_def.h:616) == `TP_FLOATING_PRECISION_VALUE`(-1, object_domain.h:119). `db_make_bit(v, DB_DEFAULT_PRECISION, …)` → `db_value_domain_init(BIT, -1)` → `char_info.length = TP_FLOATING_PRECISION_VALUE`(db_macro.c:204-207). 즉 parent_pos BIT는 항상 **floating precision**이며, 인코딩 크기는 오직 실제 비트 길이(320)로 결정된다. 고정 precision 분기(`STR_SIZE(prec)`)는 타지 않는다.

## 2. 증명표

| # | 지점 (file:line) | 열 / 도메인 | 자리표시자 최초 기록 경로 | 자리표시자 bound? / 크기 | 덮어쓰기 값 / 크기 | 헤더 재기록? | 판정 |
|---|---|---|---|---|---|---|---|
| 1 | `qexec_ordby_put_next` query_executor.c:3881-3882, 3903-3904, 3934-3935 | orderby_num, BIGINT | `xasl->ordbynum_val`을 `db_make_bigint(…,0)`(15217-15220; 병렬 topn 27449; 리셋 3816, 27582). `TYPE_ORDERBY_NUM` regu의 dbvalptr가 이 DB_VALUE(xasl_generation.c:7295-7302, fetch.c:4163-4167 peek). 튜플은 `qdata_copy_valptr_list_to_tuple`→`qdata_copy_db_value_to_tuple_value`로 기록 | **bound**, 8B (슬롯 8) | `ordbynum_val` (3713에서 `data.bigint++`; 도메인 BIGINT 유지, 27581 assert) 8B | **예** — `qdata_copy_db_value_to_tuple_value`가 flag/length를 다시 씀. bound 검사 없음 | 크기 동일. 새 포맷에서는 본문 전용 접근자로 교체 필수 |
| 2 | `renumber_instnum_lists` px_scan_instnum.cpp:332-333 | inst_num 패스스루, BIGINT (`tp_Bigint_domain`) | 워커 TLS 준비 시 `db_make_bigint(tl.xasl->instnum_val, 0)`(px_scan_result_handler.cpp:300-304, 주석 "guarantee a V_BOUND 8-byte BIGINT slot"); ATOMIC_DRAW는 emit 전 `db_make_bigint(…, drawn)`(874-877). 직렬 초기화도 BIGINT(`qexec_init_instnum_val` 14983, key-limit 하한도 BIGINT로 coerce, fetch.c:5265-5276). 출력 열은 `TYPE_CONSTANT` && `dbvalptr == instnum_val`(px_scan_instnum.cpp:234) | **bound**, 8B | `db_make_bigint(&rownum_val, ++counter)` 8B | 아니오 (`qfile_set_tuple_column_value`, unbound면 ER_FAILED) | 성립 |
| 3 | CONNECT BY ISCYCLE query_executor.c:18018-18024 | `valptr_cnt - PCOL_ISCYCLE_TUPLE_OFFSET(1)`, INT (`tp_Integer_domain`) | `qexec_set_pseudocolumns_val_pointers`가 outptr_list 슬롯 dbvalptr를 잡아 `db_make_int(*iscycle_valp, 0)`(19271-19275); prior_outptr_list 슬롯도 같은 DB_VALUE로 aliasing(19289-19300). 이후 오직 `db_make_int`만 호출(15237, 18018). 대상 튜플 = 직전에 `qfile_add_tuple_get_pos_in_list`로 listfile0에 추가한 부모 튜플(17921 / 18010)이며 prior_outptr_list로 만들어짐(17899 / 18001) | **bound**, 4B (슬롯 8) | `db_make_int(iscycle_valp, iscycle_value)` 4B | 아니오 | 성립 (4B를 8B 슬롯 앞부분에 씀, 뒤 4B 패딩 불변) |
| 4 | CONNECT BY ISLEAF query_executor.c:18028-18033 | `- PCOL_ISLEAF_TUPLE_OFFSET(2)`, INT | 위와 동일(19266-19270 `db_make_int(*isleaf_valp, 0)`, 17892/17994 `db_make_int`) | **bound**, 4B | `db_make_int(isleaf_valp, isleaf_value)` 4B | 아니오 | 성립 |
| 5a | `qexec_recalc_tuples_parent_pos_in_list` query_executor.c:19471-19477 (level == prev_level) | `type_cnt - PCOL_PARENTPOS_TUPLE_OFFSET(5)`, BIT floating (`tp_Bit_domain`, precision TP_FLOATING) | 자식 튜플(LEVEL ≥ 2)은 17918 `db_make_bit(parent_pos_valp, DB_DEFAULT_PRECISION, &parent_pos, sizeof(parent_pos)*8)` **이후에만** 삽입됨(`parent_tuple_added` 가드 17874-17925 → 자식 삽입 17975+/17972). ORDER SIBLINGS 경로는 18097-18102에서 튜플 → DB_VALUE 재읽기(`mr_readval_bit_internal` floating: `db_make_bit(v, TP_FLOATING_PRECISION_VALUE, ptr, bit_length=320)` 13205-13226) 후 재기록 | **bound**, 44B (슬롯 48) | `db_make_bit(&parent_pos_dbval, DB_DEFAULT_PRECISION, &pos_info_p->tpl_pos, sizeof(tpl_pos)*8)` = 320bit → 44B | 아니오 | 성립. `if (level > 1)` 가드(19470) |
| 5b | 같은 함수 19502-19511 (level > prev_level) | 동일 | 동일 | 동일 | 동일 44B | 아니오 | 성립. `prev_level`은 1로 시작(19427)하고 항상 실제 LEVEL이므로 `level > prev_level ⇒ level ≥ 2` |
| 5c | 같은 함수 19537-19546 (level < prev_level) | 동일 | 동일 | 동일 | 동일 44B | 아니오 | 성립. `if (level > 1)` 가드(19535) |

### 2.1 (iii) NULL parent_pos 자리표시자 행이 덮어쓰기 대상이 아님의 증명

- NULL parent_pos가 생기는 곳: (1) `qexec_set_pseudocolumns_val_pointers`의 `db_value_domain_init(*parent_pos_valp, DB_TYPE_BIT, …)`(19250-19254) → START WITH/입력 리스트 튜플(19693-19708에서 `xasl->outptr_list`로 기록)은 parent_pos = NULL; (2) 부모 루프마다 17783 `db_make_bit(parent_pos_valp, DB_DEFAULT_PRECISION, NULL, 8)`로 리셋.
- listfile0(= `xasl->list_id`, 17683)에 들어가는 부모 튜플의 parent_pos는 17896-17897 / 17996-17999에서 **자기 부모 리스트(listfile1) 튜플의 값을 그대로 복원**한다(`qexec_get_tuple_column_value`; unbound면 `db_make_null` 18826-18829). 따라서 START WITH에서 온 루트(LEVEL 1)만 NULL, LEVEL ≥ 2는 항상 bound.
- LEVEL은 각 층 시작 시 `level_value++; db_make_int(level_valp, level_value)`(17742-17744)로 튜플 삽입 전에 bound INT로 기록되며, 루트는 반드시 LEVEL 1이다.
- 재계산 루프의 세 덮어쓰기 분기는 모두 LEVEL ≥ 2에서만 실행된다(5a/5b/5c 판정 열). 즉 NULL 행(LEVEL 1)은 구조적으로 대상이 아니다. 2차 방어로 `qfile_set_tuple_column_value`가 unbound면 ER_FAILED를 돌려 조용히 진행하지 않는다.
- 참고: 17783의 NULL 리셋은 DB_VALUE에만 작용하고 튜플에는 기록되지 않는다. 튜플로 흘러가는 경로는 17896/17996의 복원값 또는 17918의 bound값이다.

### 2.2 (iv) `qfile_set_tuple_column_value`의 오버플로 튜플 분기 (list_file.c:7190-7231)

- 흐름: 튜플 전체 복사본 확보(스캐너 PEEK 복사본 `tuple_p` 재사용 7196-7201, 또는 `qfile_get_tuple` 7204) → 복사본에서 `qfile_locate_tuple_value`로 열 찾고 본문만 `data_writeval` (7213-7221) → `qfile_overwrite_tuple`(7223)로 **튜플 전체를** 첫 페이지+오버플로 페이지에 `qfile_Max_tuple_page_size` 단위로 memcpy(7285-7313).
- 포맷 의존 부분은 두 가지뿐: (a) 열 위치 탐색(`qfile_locate_tuple_value`) — 새 접근자(deform)로 대체해야 함; (b) `QFILE_GET_TUPLE_LENGTH(tuple) != tuple_record_p->size` sanity check(7269-7273) — 새 포맷에서 길이 워드 최상위 비트가 has-null 플래그가 되므로 `QFILE_GET_TUPLE_LENGTH`가 마스킹된 길이를 돌려주면 그대로 성립. 페이지 분할·memcpy는 페이지 레이아웃이라 포맷 무관.
- 유지 조건: 덮어쓰기가 튜플 길이를 바꾸지 않을 것(= 동일 크기 계약). 복사본 갱신 후 통째로 쓰기 방식 자체는 새 포맷에서도 유효하다. 참고로 `qexec_ordby_put_next`의 오버플로 분기(3893-3910)는 덮어쓰기가 아니라 복사본 갱신 후 `qfile_add_tuple_to_list`로 새 리스트에 추가하므로 계약과 무관하다.

### 2.3 (v) PG식 1B 짧은 헤더 도입 시 parent_pos BIT

- parent_pos 본문은 `pr_type` 인코딩(floating BIT: 4B 비트길이 접두 + 40B) = **44B로 컴파일타임 상수**. 자리표시자(17918)와 덮어쓰기(19473/19508/19539) 모두 `sizeof(QFILE_TUPLE_POSITION) * 8`을 쓰고, ORDER SIBLINGS 재읽기도 `bit_length`를 그대로 보존(13205-13226)하므로 44B가 깨질 경로가 없다.
- 44 ≤ 127이므로 짧은 헤더 규칙이 어떻게 정해지든(길이 기준이면) 양쪽 모두 1B 헤더. 새 포맷이 pr_type 내부의 4B 접두를 떼고 튜플 헤더 길이만 쓰기로 해도 40B로 여전히 상수. `tp_Bit.alignment = 1`(object_primitive.c:13458)이라 자연정렬에서 BIT 본문 앞 패딩은 없고, 뒤따르는 열의 패딩은 크기가 같으므로 불변.
- 유일한 전제: 덮어쓰기 대상이 **bound**여야 한다(NULL은 0바이트 + 비트맵이므로 덮어쓰면 레이아웃이 바뀐다). 이는 §2.1로 보장.

## 3. 접근자 설계에 대한 함의

- 5지점 중 4지점은 이미 "본문만 쓰기"이고 bound 검사가 있다. 1지점(`qexec_ordby_put_next`)만 헤더까지 다시 쓰며 bound 검사가 없다 → 새 접근자로 **통일**해야 한다.
- 새 포맷에서 열 위치는 deform 캐시/접두 증분으로 구하므로 `QFILE_GET_TUPLE_VALUE_HEADER_POSITION`/`qfile_locate_tuple_value` 직접 호출 지점 전부(§2 표의 8개 라인)가 접근자 호출로 바뀐다.
- 오버플로 튜플: "복사본 → 접근자로 본문 갱신 → `qfile_overwrite_tuple`" 골격 유지.

## 4. 권장 assert (접근자 `qfile_tuple_overwrite_value(list_id, tuple, col, dbval)` 가정)

```c
/* 계약: bound 값만, 동일 인코딩 크기로만, 같은 타입으로만 덮어쓴다 (CBRD-27365) */
assert (!DB_IS_NULL (dbval));                                   /* 새 값이 NULL이면 계약 위반 */
assert (col >= 0 && col < list_id->type_list.type_cnt);
assert (!qfile_tuple_value_is_null (tuple, col));               /* 자리표시자가 NULL(0B)이면 레이아웃이 바뀜 */
assert (TP_DOMAIN_TYPE (list_id->type_list.domp[col]) == DB_VALUE_DOMAIN_TYPE (dbval)); /* HIDDEN regu 인덱스 어긋남 방어 */
assert (pr_data_writeval_disk_size (dbval) == qfile_tuple_value_length (tuple, col));   /* 인코딩 크기 동일 */
```

- release 빌드에서는 오늘처럼 unbound/크기 불일치 시 `ER_FAILED`를 돌려 조용히 진행하지 않도록 한다(`qfile_set_tuple_column_value` 7184-7188 동작 보존).
- 크기 비교는 새 포맷에서 본문 길이가 정확(패딩 미포함)하므로 등호로 충분하다. 오늘 포맷으로 임시 구현할 때는 `DB_ALIGN(size, MAX_ALIGNMENT)`와 비교.
- `qexec_ordby_put_next`에는 추가로 `assert (DB_VALUE_TYPE (ordbynum_val) == DB_TYPE_BIGINT)`(27581에 이미 있는 것과 동일)를 3지점 앞에 두는 것을 권장.

## 5. 놀라운 점 / 후속 확인 항목

1. **헤더 재기록 지점 1곳**: orderby_num 갱신이 `qdata_copy_db_value_to_tuple_value`로 헤더를 다시 쓴다. 새 포맷 이행 시 가장 먼저 손봐야 할 지점.
2. **HIDDEN regu 인덱스 불일치 가능성**: `ordbynum_pos`/`rownum_col_indices`는 HIDDEN regu를 포함해 세고, 튜플 작성기는 HIDDEN을 건너뛴다. 현재 HIDDEN이 선두에 오는 경로(클라이언트 측 UPDATE/DELETE/MERGE의 classoid, compile.c:298)와 orderby_num/inst_num 패스스루가 공존하는 쿼리는 확인되지 않았으나, 접근자의 도메인 타입 assert로 방어 권장. 별도 확인 티켓 후보.
3. LEVEL 자리표시자는 `db_value_domain_init(VARCHAR)`로 NULL 초기화되지만(19258-19262) 튜플 삽입 전 항상 `db_make_int`로 채워지고, in-place 덮어쓰기 대상이 아니므로 계약과 무관. 다만 domain init 타입(VARCHAR)과 실제 값(INT)이 다른 점은 코드 냄새.
4. BIT 자리표시자와 덮어쓰기 값이 같은 크기인 것은 `sizeof(QFILE_TUPLE_POSITION)`(40B, 포인터 `tpl` 포함)이라는 구조체 크기에 의존한다. 구조체 필드 변경 시에도 양쪽이 같은 `sizeof`를 쓰므로 계약은 유지되지만, 값 안에 raw 포인터가 들어간다는 점은 별개의 기존 설계 특성.
