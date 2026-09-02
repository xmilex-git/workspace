# CBRD-27365 레이아웃 디스크립터 설계 (티켓 #181, 지도 #179)

명세 v1(#180, `cbrd27365-tuple-format-spec.md`) 위에서 `QFILE_TUPLE_VALUE_TYPE_LIST`를 레이아웃 디스크립터로 확장하는 설계. 결정 ID `D-181-*`. 2026-09-02 그릴링 2라운드로 잠금.

## 결정 목록

| ID | 결정 | 근거 | 되돌림 |
|---|---|---|---|
| D-181-1 | 디스크립터 필드를 `QFILE_TUPLE_VALUE_TYPE_LIST`에 **추가**한다(별도 `layout` 멤버·heap 객체 아님). 컬럼 배열 `col[type_cnt]`는 `domp[type_cnt]`와 **한 블록**으로 malloc하고 `domp`가 블록 선두를 가리킨다 → 기존 `free(domp)` 8곳 무수정. | 디스크립터는 type_list의 결정적 파생물이며 수명이 domp와 같다. 할당 1회, 해제 지점 추가 0. | 블록을 둘로 나누고 `col`을 따로 free — 해제 8곳 수정 |
| D-181-2 | 구조체는 두 상태를 가진다: **입력용**(domp만, `finalized=false`; query_executor.c 지역 type_list 6곳)과 **확정**(합본 블록, `finalized=true`). `qfile_type_list_alloc(tl, cnt)` 헬퍼로 합본 블록을 만들며, finalize가 일어나는 5곳(open_list·modify_type_list·copy_list_id·or_unpack_unbound_listid·cursor_copy_list_id)은 반드시 헬퍼를 쓴다. 입력용 6곳은 건드리지 않는다. | surgical. 접근자 진입 `assert(finalized)`로 상태 혼동 방어. | — |
| D-181-3 | 컬럼 엔트리 **8B**: `{int16 off; int16 size; uint8 kind; uint8 var_access; uint8 alignby; uint8 _pad}`. hot 필드는 비트 마스킹 없는 온전한 필드. | PG `CompactAttribute` 8B 선례(commit d28dff3f 16B 도입 → d8a859d2 8B 축소; 16컬럼 OLAP +10~25%). LEA scale-8 단일 명령 주소 계산. cpp-perf MEM. | 16B로 되돌려도 접근자 코드 불변 |
| D-181-4 | `off`는 int16이므로 **`off > 32767`이면 그 컬럼부터 캐시를 포기**하고 `first_non_cached_col`에 기록(PG `firstNonCachedOffsetAttr`·tupdesc.c:552와 동일). 명세 §7의 `first_var_col`은 **`first_non_cached_col` = min(첫 가변 컬럼, 첫 오프셋 초과 컬럼)** 로 개명·재정의. | 고정폭 최대 12B(MONETARY·DATETIMETZ)라 고정 컬럼 2700개 이상에서만 발동하고, 발동해도 정확성 아닌 속도만 낮아진다. | int32 off(엔트리 12→16B) |
| D-181-5 | 리스트 필드: `int type_cnt; uint8 hdr_size(4\|8); bool finalized; int16 bitmap_size; int16 data_off[2]; int first_non_cached_col; TP_DOMAIN **domp; QFILE_COL_LAYOUT *col`. `bitmap_size`·`data_off`는 **int16**(uchar 2040컬럼 상한 제거). | 리스트당 +6B는 무의미, 컬럼 수 상한이라는 새 실패 모드를 만들지 않음. | — |
| D-181-6 | **mutator-owns-finalize**: `domp`를 바꾸는 코드가 같은 자리에서 `qfile_type_list_finalize(tl)`를 호출한다. 호출 지점 4곳: ① `qfile_open_list` 끝, ② `qfile_update_domains_on_type_list` 끝, ③ px `update_domains_on_type_list_by_val_list` 끝, ④ 클라이언트 `or_unpack_unbound_listid` 끝. 복제(`qfile_copy_list_id`·`qfile_clone_list_id`·`cursor_copy_list_id`·`qfile_modify_type_list`)는 합본 블록 memcpy로 재계산 없이 상속. finalize는 순수·멱등(입력 = domp, hdr_size), 미확정 `DB_TYPE_VARIABLE` 컬럼은 가변으로 계산(명세 §8). 지연 finalize(접근자에서 계산) 불채택. | 변경 지점이 열거 가능하고 hot path에 assert 외 분기 없음(cpp-perf BR). PG `populate_compact_attribute` "원본 변경 직후 반드시 호출" 계약과 동일. | — |
| D-181-7 | 디버그 빌드: 접근자 진입·finalize 직후 **"저장 레이아웃 == domp에서 재계산"** 교차 assert(PG `verify_compact_attribute` 방식). | 압축본·원본 불일치를 즉시 검출. | — |
| D-181-8 | **`hdr_size`가 backward_capable의 유일한 진실**(8 ⇔ backward). 별도 bool 없음. `QFILE_LIST_IS_BACKWARD(list_id)` 매크로. connect/append/duplicate 일치 assert(#184)·`qfile_scan_prev` 계약 assert 모두 이 값을 본다. `qfile_open_list`의 `flag`에 backward 비트 추가(#184). | 같은 사실을 두 필드에 두면 어긋날 길만 생긴다. | — |
| D-181-9 | **wire: `or_pack_listid`에 int 1개(layout flags = hdr_size) 추가.** `or_listid_length` `OR_INT_SIZE * 8 → * 9`, `or_unpack_listid`·`or_unpack_unbound_listid`에서 읽고 finalize. 디스크립터 본체는 wire로 보내지 않고 양쪽에서 재계산. **#180 §13 "or_pack_listid 변경 불필요"는 정정** — hdr_size는 도메인에서 파생 불가. | 4B 비용 0. "클라이언트는 결과 리스트(=backward)만 본다"는 가정이 깨질 때 조용히 잘못 읽는 대신 assert로 잡음. lockstep 정책이라 wire 변경 자유. | 클라이언트 hdr_size=8 상수 가정 |
| D-181-10 | **스레드 계약: 레이아웃 디스크립터는 그 `QFILE_LIST_ID`를 소유한 스레드만 읽고 쓴다.** px XASL_SNAPSHOT 리더(px_scan_result_handler.cpp:825, atomic 도메인으로 순차 deform)는 디스크립터를 쓰지 않고 **도메인 구동 순차 deform 원시 함수**(도메인에서 kind/size/alignby를 그때그때 파생)를 쓴다 → #182 요구사항. px writer의 per-writer list_id 사본은 각자 finalize. | 리더는 이미 컬럼마다 도메인을 load하므로 파생 비용은 분기 몇 개. 공유 가변 디스크립터라는 동기화 표면을 만들지 않음. | 리더별 사설 레이아웃 + atomic 변화 감지 re-finalize |
| D-181-11 | 신설 파일 `src/query/qfile_tuple_layout.h`(상수·매크로·hot 접근자 static inline) + `src/query/qfile_tuple_layout.c`(finalize·조립기·디버그 교차검증 cold 경로). `.c`를 cs·sa·cubrid 세 CMakeLists에 등록(`cursor.c`는 cs·sa, `list_file.c`는 sa·cubrid). | finalize는 pr_type 테이블 순회 cold 함수, 접근자는 인라인. | header-only |

## 구조체 (최종)

```c
typedef struct qfile_col_layout QFILE_COL_LAYOUT;   /* 8B — 늘리려면 D-181-3 재검토 */
struct qfile_col_layout {
  int16_t  off;         /* data_off 기준 상수 오프셋, 캐시 밖(가변 이후·32767 초과)은 -1 */
  int16_t  size;        /* FIXED: disksize(최대 12). VAR: -1 */
  uint8_t  kind;        /* QFILE_COL_FIXED | QFILE_COL_VAR */
  uint8_t  var_access;  /* VAR만: QFILE_VAR_DIRECT | QFILE_VAR_SCRATCH */
  uint8_t  alignby;     /* FIXED: 2|4. VAR: 1 */
  uint8_t  _pad;
};

struct qfile_tuple_value_type_list {
  TP_DOMAIN **domp;             /* 합본 블록 선두: domp[type_cnt] 바로 뒤에 col[type_cnt] (free(domp) 하나로 해제) */
  int type_cnt;
  /* --- 이하 D-181-1 추가. 입력용 type_list 는 finalized=false 이고 아래를 읽지 않는다 --- */
  QFILE_COL_LAYOUT *col;        /* domp + type_cnt 를 가리키는 편의 포인터 (별도 할당 아님) */
  int first_non_cached_col;     /* min(첫 가변 컬럼, 첫 off>32767 컬럼), 없으면 type_cnt */
  int16_t data_off[2];          /* [0]=no-null [1]=has-null : ALIGN4(hdr_size + bitmap) */
  int16_t bitmap_size;          /* (type_cnt+7)>>3 */
  uint8_t hdr_size;             /* 4 | 8 ; 8 ⇔ backward_capable (D-181-8, 유일한 진실) */
  bool    finalized;
};
```

## finalize 알고리즘 (`qfile_type_list_finalize`)

```
bitmap_size = (type_cnt+7)>>3
data_off[0] = ALIGN4(hdr_size); data_off[1] = ALIGN4(hdr_size + bitmap_size)
off = 0; first_non_cached_col = type_cnt
for i in 0..type_cnt-1:
  t = domp[i]->type
  if TP_DOMAIN_TYPE(domp[i]) == DB_TYPE_VARIABLE or t->is_size_computed():
      col[i] = {off:-1, size:-1, kind:VAR, var_access: t->index_readval ? DIRECT : SCRATCH, alignby:1}
      if first_non_cached_col == type_cnt: first_non_cached_col = i
      continue                      # 이후 컬럼은 모두 off=-1 (캐시 종료)
  a = min(t->alignment, 4)          # D-180-4: BIGINT/DOUBLE 도 4
  if first_non_cached_col == type_cnt:
      off = ALIGN(off, a)
      if off > INT16_MAX: first_non_cached_col = i; col[i].off = -1     # D-181-4
      else: col[i].off = off; off += t->disksize
  else: col[i].off = -1
  col[i] = {size:t->disksize, kind:FIXED, alignby:a}
finalized = true
```

멱등: 같은 (domp, hdr_size)에 대해 같은 결과. 도메인 확정(§8)으로 `domp[k]`가 VARIABLE→구체 타입으로 바뀌면 `first_non_cached_col`이 뒤로 물러나고 `col[k]`가 VAR→FIXED가 된다. 확정 전 튜플의 컬럼 k는 NULL(0B)이므로 기존 튜플 배치는 불변(#186, 명세 §8).

## 이 티켓이 넘기는 것

- **#182 접근자 API**: (a) 진입 `assert(finalized)` + 디버그 교차검증(D-181-7); (b) **도메인 구동 순차 deform 원시 함수** — px XASL_SNAPSHOT 리더용, 디스크립터 없이 `(domain, bitmap, cursor)`만으로 다음 값 위치 계산(D-181-10); (c) `fast_limit = has_null ? min(first_non_cached_col, first_null) : first_non_cached_col`.
- **#189 PR-1**: `qfile_type_list_alloc/finalize` 도입과 pack flag int 추가는 포맷 불변 단계에서 미리 들어갈 수 있음(구 포맷에서는 디스크립터를 계산만 하고 쓰지 않음).
- **#188 ADR 0016**: D-181-1(같은 구조체·한 블록), D-181-9(wire flag), D-181-10(스레드 계약)을 잠금 항목으로.
- 용어(CONTEXT.md): **도메인 확정(domain resolve)** vs **레이아웃 확정(layout finalize)** 구분.
