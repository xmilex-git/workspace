# Q1 격차의 소스 레벨 규명 — PG는 어떻게 싸고 CUBRID는 어디서 비싸지는가

2026-07-28. 대상 트리는 **측정된 빌드와 정확히 같은 커밋**이다 —
CUBRID `~/dev/wt-tpch-sspq` @ `f30f1c26003e5aa8e93182648e06cad76fc77064`,
PostgreSQL `~/dev/postgres` @ `5713b437abed7085e7d59849c6e9e0f4f469633d`.
모든 주장에 `file:line`을 붙였다. 추측은 쓰지 않았다.

대상 버킷(5단계 프로파일): 식 평가/튜플 구성 **28.8 %**, 값/도메인 변환 **22.9 %**,
집계·해시 **11.4 %**.

## 결론 (5줄)

1. **PG는 타입을 초기화 시점에 소거한다.** `ExecInitFunc`가 `fmgr_info`로 함수를 한 번
   해소하고 주소를 스텝에 복사해 두므로(`execExpr.c:2734`, `:2742`), 실행 시점 스텝은
   NULL 검사 후 `op->d.func.fn_addr(fcinfo)` 직접 호출뿐이다
   (`execExprInterp.c:944-969`). 값에는 도메인 기술자가 없다 — `Datum`(8바이트) +
   `isnull` 뿐(`postgres.h:76`, `:84-91`).
2. **CUBRID는 그 결정을 행마다 다시 한다.** `fetch_peek_arith`는 **373개 `case T_*`**
   opcode switch를 **두 번**(`fetch.c:119`, `:681`) 통과하고, T_ADD 팔에서
   시스템 파라미터를 조회하고(`fetch.c:687`) 도메인 타입을 재검사한 뒤
   (`fetch.c:690-691`) `qdata_add_dbval`을 부른다(`fetch.c:701`).
3. **값/도메인 변환 22.9 %의 정체는 "결과를 매번 도메인으로 강제 변환"이다.**
   `qdata_add_dbval`은 꼬리에서 항상 `qdata_coerce_result_to_domain`을 호출하고
   (`query_opfunc.c:2730`) → `tp_value_coerce`(`:2390`) → `tp_value_cast_internal`.
   NUMERIC은 parameterized 도메인이라 **precision·scale이 정확히 일치할 때만** 조기
   반환한다(`object_domain.c:7135-7145`). Q1은 곱셈마다 스케일이 자라 이 조건이 깨지고,
   `src == dest`이므로 임시 값 경로(`:7203-7217`)로 떨어진다.
4. **최대 심볼 `float_numeric_db_value_add`(9.78 %)는 2026-06-03 CBRD-26006으로 들어온
   신규 경로**(`de7bc5ec2`, PR #6486)이며, 호출마다 정밀도·스케일을 재도출하고
   (`numeric_opfunc.c:2509-2510`) **VLA 3개를 잡아 memset 3번**
   (`:2527-2532`) 후 packed→word 표현 변환을 2번 한다(`:2534-2535`). PG는 반대로
   누산기를 질의 내내 유지하고 캐리를 9,999값마다 한 번만 전파한다
   (`numeric.c:11896-11897`), 그리고 `init_var_from_num`은 자릿수를 **복사하지 않는다**
   (`numeric.c:7224` `dest->buf = NULL`).
5. **집계 4.53x의 이유는 그룹 수가 아니다.** 그룹은 4개지만
   `qdata_aggregate_value_to_accumulator`의 SUM/AVG 팔이 **행마다 어그리게이트마다**
   범용 `qdata_add_dbval` 전체를 통과한다(`query_aggregate.cpp:483`) — Q1은 SUM 4개 +
   AVG 3개이므로 행당 7회다.

---

## 1. PostgreSQL — 무엇을 어떻게 하기에 싼가

### 1-1 표현식은 초기화 시점에 선형 스텝 배열로 컴파일된다

| 항목 | 근거 |
|---|---|
| opcode 열거형 `ExprEvalOp` | `src/include/executor/execExpr.h:66` — `EEOP_*` 174개 참조 |
| 스텝 구조 `ExprEvalStep` | `execExpr.h:300-318`. `opcode`가 `intptr_t`인 이유가 주석에 있다 — "later it can be changed to some other type, e.g. a pointer for **computed goto**"(`:303-306`). union은 40바이트 이하로 유지해 **구조체 전체가 64바이트 = 캐시라인 1개**(`:314-318`) |
| 컴파일 진입 | `ExecInitExpr` `src/backend/executor/execExpr.c:142-143` |
| 컴파일 완료 | `ExecReadyExpr` `execExpr.c:902-908` — `jit_compile_expr(state)`가 실패하면 `ExecReadyInterpretedExpr` |

**타입 해소는 실행 시점이 아니라 초기화 시점이다.** `ExecInitFunc`
(`execExpr.c:2697`):

```c
2728	scratch->d.func.finfo = palloc0_object(FmgrInfo);
2729	scratch->d.func.fcinfo_data = palloc0(SizeForFunctionCallInfo(nargs));
2733	/* Set up the primary fmgr lookup information */
2734	fmgr_info(funcid, flinfo);
2738	InitFunctionCallInfoData(*fcinfo, flinfo, nargs, inputcollid, NULL, NULL);
2741	/* Keep extra copies of this info to save an indirection at runtime */
2742	scratch->d.func.fn_addr = flinfo->fn_addr;
2743	scratch->d.func.nargs = nargs;
```

`fmgr_info`는 카탈로그에서 함수를 **한 번** 찾고, `fn_addr`을 스텝에 복사하는 이유가
주석에 명시돼 있다 — 실행 시 간접 참조 1회를 없애기 위해서다.

실행 시점 스텝(`execExprInterp.c:944-969`)이 하는 일 전부:

```c
944		EEO_CASE(EEOP_FUNCEXPR_STRICT)
946			FunctionCallInfo fcinfo = op->d.func.fcinfo_data;
947			NullableDatum *args = fcinfo->args;
954			for (int argno = 0; argno < nargs; argno++)
956				if (args[argno].isnull)
958					*op->resnull = true;
959					goto strictfail;
962			fcinfo->isnull = false;
963			d = op->d.func.fn_addr(fcinfo);
964			*op->resvalue = d;
965			*op->resnull = fcinfo->isnull;
```

**타입 조회 0회, 도메인 조회 0회, 크기 계산 0회, 결과 강제 변환 0회.**

### 1-2 값 표현 — Datum + isnull이 "안 하게" 만드는 것

| 항목 | 근거 |
|---|---|
| `Datum` 크기 | `src/include/postgres.h:76` — `#define SIZEOF_DATUM 8` |
| `NullableDatum` | `postgres.h:84-91` — `Datum value; bool isnull;` 뿐. 주석: "due to alignment padding this could be used for flags for free"(`:90`) — 즉 플래그 자리조차 **아직 안 쓰고 있다** |
| 슬롯 배열 | `src/include/executor/tuptable.h:126,131,133` — `tts_nvalid`, `Datum *tts_values`, `bool *tts_isnull` |

값 하나에 붙는 것: 8바이트 페이로드 + 1바이트 null 플래그. **도메인 기술자·수명
플래그·크기 필드가 없다.** 타입은 값이 아니라 스텝이 안다.

### 1-3 튜플 디코드 — 튜플당 1회, 그 뒤엔 배열 인덱싱

| 단계 | 근거 |
|---|---|
| 스텝 | `EEOP_SCAN_FETCHSOME` `execExprInterp.c:662-669` → `slot_getsomeattrs(scanslot, op->d.fetch.last_var)` |
| `last_var`가 언제 정해지나 | **초기화 시점** — `execExpr.c:2927` `scratch.d.fetch.last_var = info->last_scan` |
| 조기 반환 | `tuptable.h:376-381` — `if (slot->tts_nvalid < attnum) slot->tts_ops->getsomeattrs(...)`. 이미 디코드된 만큼은 **다시 안 한다** |
| 실제 디코드 | `tts_buffer_heap_getsomeattrs` `execTuples.c:751-758` → `slot_deform_heap_tuple(slot, tuple, &bslot->base.off, natts, false)` |
| 증분성 | `slot_deform_heap_tuple` `execTuples.c:1017` — 오프셋을 `*offp`로 이어받아 **필요한 속성까지만** 푼다 |

즉 `tts_buffer_heap_getsomeattrs`(4.35 %)는 **튜플당 최대 1회**이고, 이후 모든 속성
접근은 `tts_values[i]` 배열 인덱싱이다.

### 1-4 수치 집계 — 값마다 무엇을 생략하는가

| 항목 | 근거 |
|---|---|
| 누산기 표현 | `NumericSumAccum` `src/backend/utils/adt/numeric.c:381-390` — `int32 *pos_digits` / `int32 *neg_digits` 와 `num_uncarried`, `have_carry_space` |
| **캐리 지연** | `accum_sum_add` `numeric.c:11881`; `:11896-11897` — `if (accum->num_uncarried == NBASE - 1) accum_sum_carry(accum);` |
| NBASE | `numeric.c:97` — `#define NBASE 10000` |
| 입력 로드가 복사가 아님 | `init_var_from_num` `numeric.c:7217-7225`; `:7224` — `dest->buf = NULL; /* digits array is not palloc'd */` |
| 진입점 | `do_numeric_accum` `numeric.c:4821`; `:4840` `init_var_from_num(newval, &X)` |

**값마다 생략되는 것: 캐리 전파(9,999값마다 1회로 지연), 자릿수 복사(포인터만), 결과
Numeric 재구성(누산기에 누적, 최종화 때 한 번만).** 주석이 근거를 직접 말한다 —
"this needs to be done so seldom, that the performance difference is negligible"
(`numeric.c:11893-11895`).

### 1-5 메모리 — 할당 비중이 커도 총량이 작은 이유

PG의 할당 비중은 16.55 %(CUBRID 4.49 %)로 **더 크지만**, 총 명령은 70.27 G 대
CUBRID 57.41 G로 **0.82x**다.

| 구조 | 근거 |
|---|---|
| 컨텍스트 프리리스트 | `AllocSetFreeList context_freelists[2]` `src/backend/utils/mmgr/aset.c:250-257`; 블록 프리리스트 `set->freelist[]` `aset.c:163` |
| **행마다 일괄 리셋** | `ResetExprContext` → `MemoryContextReset(econtext->ecxt_per_tuple_memory)` `src/include/executor/executor.h:659`, `:559`; `execUtils.c:453` |

즉 PG는 값마다 개별 `free`를 하지 않는다. per-tuple 컨텍스트에 던지고 **행 경계에서
컨텍스트 하나를 리셋**한다. `AllocSetFree`(4.70 %)가 보이는 것은 aggregate 상태처럼
장수하는 객체 몫이고, 짧은 값들은 리셋으로 회수된다. CUBRID 쪽은 대칭적으로
`malloc` 2.60 % + `_int_free` 1.89 % + `cfree@GLIBC` 1.12 %가 **개별 해제**로 나타난다.

### 1-6 JIT는 꺼져 있다 — 그래도 싼 이유

| 사실 | 근거 |
|---|---|
| 빌드에 LLVM 없음 | `pg_config --configure`에 `'--without-llvm'` (4단계 보고서 §측정 조건) |
| 기본값도 off | `jit_enabled = false` `src/backend/jit/jit.c:33`; `provider_init`이 `if (!jit_enabled)`에서 즉시 반환 `jit.c:74` |
| 그래서 실행 경로 | `ExecReadyExpr` `execExpr.c:902-908`에서 `jit_compile_expr`이 false를 반환하고 **항상 인터프리터**로 간다 |

**JIT 없이도 싼 이유는 §1-1~1-4 구조 자체다**: 타입은 초기화 시점에 소거되고, 스텝은
캐시라인 1개에 들어가며(`execExpr.h:314-318`), 값은 8바이트 Datum이고, 디코드는
튜플당 1회, 누산은 캐리를 지연한다. JIT는 이 위에 얹는 추가 최적화이지 전제가 아니다.
프로파일이 이를 확인한다 — `ExecInterpExpr` 단일 함수가 12.68 %로 식 평가 전체를
담당하고, CUBRID의 대응 작업은 5개 함수에 분산돼 23.44 %다.

---

## 2. CUBRID — 어디서 비싸지는가

### 2-1 행마다 다시 결정하는 것 — 디스패치 겹수

`fetch_peek_arith` `src/query/fetch.c:85`

| 겹 | 무엇 | 근거 |
|---|---|---|
| 1 | opcode switch #1 (피연산자 분류) | `fetch.c:119` |
| 2 | opcode switch #2 (연산 수행) | `fetch.c:681` — 두 switch 합계 **373개 `case T_*`** |
| 3 | 시스템 파라미터 조회 | `fetch.c:687` `prm_get_bool_value (PRM_ID_ORACLE_STYLE_EMPTY_STRING)` |
| 4 | 결과 도메인 타입 재검사 | `fetch.c:690-691` `QSTR_IS_ANY_CHAR_OR_BIT (TP_DOMAIN_TYPE (regu_var->domain))` |
| 5 | 범용 add 진입 | `fetch.c:701` `qdata_add_dbval (peek_left, peek_right, arithptr->value, regu_var->domain)` |

`qdata_add_dbval` `src/query/query_opfunc.c:2438` 안에서 다시:

| 겹 | 무엇 | 근거 |
|---|---|---|
| 6 | 도메인 NULL 검사 | `query_opfunc.c:2449` `TP_DOMAIN_TYPE (domain_p) == DB_TYPE_NULL` |
| 7 | 양쪽 값 타입 도출 | `:2454-2455` `DB_VALUE_DOMAIN_TYPE` ×2 |
| 8 | ENUMERATION 분기 ×2 | `:2458` 이후 두 블록 |
| 9 | 파라미터 조회 | `:2501` `prm_get_bool_value (PRM_ID_PLUS_AS_CONCAT)` |
| 10 | 스왑 후 타입 **재도출** | `:2529-2530` `DB_VALUE_DOMAIN_TYPE` ×2 (다시) |
| 11 | 대타입 switch → `qdata_add_numeric_to_dbval` | `:2059` |
| 12 | 그 안에서 **또** 타입 switch | `:2063` `type = DB_VALUE_DOMAIN_TYPE (dbval_p)`; NUMERIC 팔은 `:2073` |
| 13 | **결과 도메인 강제 변환** | `:2730` `return qdata_coerce_result_to_domain (result_p, domain_p);` |

`fetch_val_list` `fetch.c:4852` — 행마다 regu 리스트를 순회하며 원소별로
`pr_clear_value`(이전 값 해제) 후 `fetch_peek_dbval`을 호출한다.
`fetch_peek_dbval_slow` `fetch.c:3985`는 위치 기반 빠른 경로가 안 될 때의 일반 경로다.

`qdata_generate_tuple_desc_for_valptr_list` `query_opfunc.c:625` — 출력 컬럼마다
`DB_VALUE_DOMAIN_TYPE`(함수 내 offset 34)와
`qdata_get_tuple_value_size_from_dbval`(offset 44, → `query_opfunc.c:6327`)을 호출한다.
후자가 `pr_value_mem_size`(`object_primitive.c:9155`, 프로파일 1.64 %)로 들어간다 —
**값의 바이트 크기를 행마다 다시 계산한다.** PG는 이 계산이 없다(스텝이 타입을 알고,
슬롯이 Datum 배열이다).

### 2-2 값 하나당 언제 불리는가

| 심볼 | % | 호출 시점 | 근거 |
|---|---|---|---|
| `tp_value_cast_internal` | 4.24 | **모든 산술 결과마다** | `query_opfunc.c:2730` → `:2390` `tp_value_coerce` → `object_domain.c:6977`. 같은 경로가 subtract `:4795`, multiply `:5375`, divide `:5976`에도 있다 |
| `pr_clear_value` | 3.38 | 이전 값 해제 — regu 원소마다, 캐스트 임시값마다 | `object_primitive.c:1866`; 호출처 `fetch.c:4852` 루프, `query_opfunc.c:2476,2496`(ENUM 캐스트 정리), `object_domain.c:7089,7108` |
| `db_value_domain_init` | 2.25 | 캐스트 대상 초기화, unbound 속성 초기화 | `src/compat/db_macro.c:155`; 호출처 `object_domain.c:7217`(캐스트 경로), `heap_file.c:10274`, `:10294`, `numeric_opfunc.c:2460`, `:2505` |
| `pr_type_from_id` | 2.03 | **속성마다** 타입 기술자 조회 | `object_primitive.c` 정의는 `tp_Type_id_map[(int) id]` 테이블 조회; 호출처 `heap_file.c:10286` |
| `pr_value_mem_size` | 1.64 | 출력 컬럼마다 크기 계산 | `object_primitive.c:9155`, 호출처 §2-1 |

**Q1에 명시적 캐스트가 없는데 `tp_value_cast_internal`이 4.24 %인 이유 — 규명:**

`qdata_coerce_result_to_domain`은 `result_p`를 **src와 dest 둘 다로** 넘긴다
(`query_opfunc.c:2390` `tp_value_coerce (result_p, result_p, domain_p)`).
`tp_value_cast_internal`의 동일 타입 조기 반환은 두 단계다:

```
object_domain.c:7116	if (desired_type == original_type)
:7122		  if (!desired_domain->is_parameterized)      -> 단순 clone 후 return  (:7126-7129)
:7132		  else /* is parameterized domain */
:7135		    case DB_TYPE_NUMERIC:
:7136-7137		      if (desired_domain->precision == DB_VALUE_PRECISION (src)
			          && desired_domain->scale == DB_VALUE_SCALE (src))
:7143			        return (status);
:7145		      break;      <-- 불일치하면 여기로 떨어진다
```

**NUMERIC은 parameterized 도메인이므로 precision과 scale이 모두 정확히 일치해야
조기 반환한다.** Q1의 `l_extendedprice * (1 - l_discount) * (1 + l_tax)`는 곱셈마다
스케일이 커지므로(§2-3의 `result_scale = MAX(scale1, scale2)`,
`result_prec = MAX(calc_prec1, calc_prec2) + result_scale`) 중간 결과의 정밀도·스케일이
목표 도메인과 어긋난다. 그러면 `:7145`에서 빠져나와 일반 변환으로 가고,
`src == dest`(`:7203`)이므로 **임시 DB_VALUE를 만들고**(`:7205` `target = &temp`)
`db_value_domain_init`으로 초기화한 뒤(`:7217`) 변환하고 되쓴다.

즉 4.24 %는 사용자가 쓴 캐스트가 아니라 **엔진이 산술 결과마다 스스로 거는 도메인
강제 변환**이고, NUMERIC의 parameterized 성질 때문에 조기 반환에 실패한다.

### 2-3 `float_numeric_db_value_*` — 무엇이고 언제 들어왔나

| 항목 | 값 |
|---|---|
| 정의 | `src/query/numeric_opfunc.c:2477` (add), `:2742` (sub), mul 동일 파일 |
| 도입 | `de7bc5ec26238ac5f0c7e7a07ef766c2ec99ed93` **2026-06-03**, `[CBRD-26006] Scale Range Expansion and Floating-Point NUMERIC Type Support (#6486)` |
| 질의 산술 경로 연결 | `query_opfunc.c:2073` `float_numeric_db_value_add (numeric_val_p, dbval_p, result_p)` |
| 구 경로 존속 | `numeric_db_value_add` `numeric_opfunc.c:2356` — 아직 있고 `query_opfunc.c:852`, `serial.c:1073,1106`, `log_applier_sql_log.c:413`이 쓴다 |
| 주석이 밝힌 차이 | `:2470-2474` — "legacy numeric_db_value_add() was limited to 16 bytes and up to 38 digits. float_numeric_db_value_add() supports the extended NUMERIC range" |

**호출마다 하는 일**(`numeric_opfunc.c:2477` 이후):

| 라인 | 작업 |
|---|---|
| 2487-2500 | 인자 유효성·타입 검사 3회(`DB_VALUE_TYPE` 포함) |
| 2503-2507 | NULL 검사 + `db_value_domain_init` |
| **2509-2510** | `db_get_numeric_precision_and_scale` **×2 — 값에서 정밀도·스케일을 매번 재도출** |
| 2511-2519 | 결과 정밀도·스케일과 스케일 보정량 재계산 |
| 2522-2524 | 필요 바이트 → 워드 수 → 바이트 수 조회 |
| **2527-2529** | **VLA 3개** `uint64_t dbv1_word[calc_words]`, `dbv2_word`, `result_word` |
| **2530-2532** | **`memset` 3회** |
| **2534-2535** | `numeric_bytes_to_words` **×2 — packed decimal → word 표현 변환을 매번** |
| 2538-2545 | 스케일 불일치 시 `float_numeric_mul_normalize` (곱셈으로 정규화) |
| 2548-2560 | fast path 판정 후 `db_make_numeric`으로 결과 DB_VALUE 재구성 |

프로파일의 `__memset_evex_unaligned_erms` 1.32 %가 `:2530-2532`와 정합한다.

**PG와의 알고리즘·표현 대조**

| 축 | CUBRID `float_numeric_db_value_add` | PG `accum_sum_add` / `mul_var` |
|---|---|---|
| 값 표현 | packed decimal 고정폭 버퍼(`DB_NUMERIC_BUF_SIZE`), 연산마다 word 배열로 변환 (`:2534-2535`) | `NumericVar` = 자릿수 포인터 + weight/sign/dscale (`numeric.c:7217-7225`), **변환 없음** |
| 정밀도·스케일 | 값에서 **매번 재도출** (`:2509-2510`) | 컴파일 시점 타입 + 누산기가 유지 (`NumericSumAccum` `numeric.c:381-390`) |
| 작업 버퍼 | 호출마다 VLA 3개 + memset 3회 (`:2527-2532`) | 누산기 버퍼를 질의 내내 재사용 |
| 캐리 | 호출마다 완결 | **9,999값마다 1회로 지연** (`numeric.c:11896-11897`, NBASE=10000 `:97`) |
| 결과 | 매 호출 `db_make_numeric`으로 DB_VALUE 재구성 (`:2558`) | 누산기에 누적, 최종화 때 1회 |

### 2-4 행당·속성당 간접 호출과 도메인 조회

`heap_attrinfo_read_dbvalues` `src/storage/heap_file.c:10464`
→ 속성마다 `heap_attrvalue_read`가:

```
heap_file.c:10286	pr_type = pr_type_from_id (attrepr->type);        // 타입 기술자 테이블 조회
heap_file.c:10289	rv = pr_type->data_readval (&buf, &value->dbvalue, attrepr->domain, raw->length, false, NULL, 0);
```

즉 **속성마다 타입 조회 1회 + 함수 포인터 간접 호출 1회 + 도메인 포인터 전달**이다.
unbound 속성이면 `db_value_domain_init`(`:10274`), 오류 경로에서도 한 번 더(`:10294`).
`heap_file.c:10440`에도 같은 형태의 `att->domain->type->data_readval` 간접 호출이 있다.

`mr_data_readval_numeric` `object_primitive.c` — 진입부에서 `domain == NULL` 검사,
`size == -1 || size == 1`이면 **버퍼 선두 바이트에서 길이를 읽어 크기를 결정**한다
(가변길이 NUMERIC 저장 때문. CBRD-26006의 "introduce variable-length storage").

Q1이 읽는 lineitem 속성은 7개(`l_returnflag, l_linestatus, l_quantity,
l_extendedprice, l_discount, l_tax, l_shipdate`)이므로 행당 타입 조회 7회 +
간접 호출 7회다. PG는 튜플당 `slot_deform_heap_tuple` 1회(`execTuples.c:1017`) 후
배열 인덱싱이다.

### 2-5 그룹이 4개뿐인데 집계가 4.53x인 이유

**그룹 수와 무관하다. 누산 경로가 행마다 범용 산술 전체를 통과한다.**

```
query_aggregate.cpp:338	qdata_aggregate_value_to_accumulator (...)
query_aggregate.cpp:482	  /* values are added up in acc.value */
query_aggregate.cpp:483	  if (qdata_add_dbval (acc->value, value, acc->value, domain->value_dom) != NO_ERROR)
```

`qdata_add_dbval`은 §2-1의 겹 6~13을 전부 수행한다 — 타입 재도출, ENUM 분기,
파라미터 조회, 중첩 switch, `float_numeric_db_value_add`, 그리고 **결과 도메인 강제
변환**(`query_opfunc.c:2730`). Q1은 SUM 4개 + AVG 3개이므로 **행당 7회**다.

`qexec_hash_gby_agg_tuple` `src/query/query_executor.c:4635` — 행마다
임시 키를 만들고 `mht_get`(함수 내 offset 54)으로 탐색, 미스면 키·값을 새로 할당해
`mht_put`(offset 106). 그룹이 4개라 탐색은 히트하지만 **키 구성과 해싱은 행마다** 한다.
PG 대응은 `lookup_hash_entries` 1.62 % + `LookupTupleHashEntry` 1.52 % = 3.14 %이고
CUBRID는 `qexec_hash_gby_agg_tuple` 2.27 % + `qdata_evaluate_aggregate_list` 3.97 % +
`qdata_aggregate_value_to_accumulator` 1.53 % + `qdata_get_agg_hvalue_size` 0.80 %다.

---

## 3. 개선 후보

각 후보는 프로파일 숫자에 매핑된다. **"일반적으로 좋은 최적화"는 넣지 않았다.**

### 후보 A — 산술 결과의 도메인 강제 변환에 NUMERIC 조기 반환 추가

| 항목 | 내용 |
|---|---|
| 건드릴 곳 | `src/object/object_domain.c:7135-7145` (`tp_value_cast_internal`의 parameterized NUMERIC 팔), 또는 호출측 `src/query/query_opfunc.c:2383-2399` (`qdata_coerce_result_to_domain`) |
| 겨냥 버킷 | **값/도메인 변환 22.9 %** |
| 예상 절감 | `tp_value_cast_internal` 4.24 % + 그에 딸린 `db_value_domain_init` 2.25 %·`pr_clear_value` 3.38 %의 일부. **상한 4.24 %, 현실적으로 2~5 %** (CUBRID 총 명령 기준 27~64 G) |
| 근거 숫자 | 5단계 표: 값/도메인 변환 CUBRID 195.6 G vs **PG 0**. `tp_value_cast_internal` self 4.24 % |
| 설계 | 결과가 이미 NUMERIC이고 목표 도메인도 NUMERIC일 때, precision·scale 불일치라도 **값 손실이 없는 방향**(목표 precision·scale이 더 넓음)이면 도메인 메타만 갱신하고 자릿수 변환을 생략한다. 손실 가능일 때만 기존 경로 |
| 난이도 | 중 |
| 위험 | **정합성 위험 실재.** 스케일 축소 시 반올림 의미가 바뀔 수 있다. `DB_VALUE_PRECISION`/`DB_VALUE_SCALE`이 값의 실제 상태와 목표 도메인 중 무엇을 반영해야 하는지 계약이 바뀐다. `src == dest` 별칭 처리(`:7203`)를 깨면 안 됨 |
| upstream 유사 시도 | `git log -S 'is_parameterized' -- src/object/object_domain.c`로 확인 필요. CBRD-26006(`de7bc5ec2`)이 이 영역의 최근 대규모 변경이며 **성능 최적화를 커밋 메시지에 명시**("optimize performance")하고도 이 경로는 남겨 두었다 |

### 후보 B — `float_numeric_db_value_*`의 호출당 재도출·버퍼 초기화 제거

| 항목 | 내용 |
|---|---|
| 건드릴 곳 | `src/query/numeric_opfunc.c:2477`(add), `:2742`(sub), mul. 특히 `:2509-2510`, `:2527-2532`, `:2534-2535` |
| 겨냥 버킷 | **수치 연산 24.97 %** 중 `float_numeric_db_value_{add,mul,sub}` = 9.78+5.93+2.96 = **18.67 %** |
| 예상 절감 | 정밀도·스케일 재도출과 memset 3회 제거로 **3~6 %** (38~77 G). `__memset` 1.32 %는 거의 전부 회수 가능 |
| 근거 숫자 | `float_numeric_db_value_add` self **9.78 %**(125.0 G)가 단일 최대 심볼. `__memset_evex_unaligned_erms` 1.32 %가 `:2530-2532`와 정합 |
| 설계 | (1) 반복 호출되는 동일 (도메인, 도메인) 쌍의 파생값(result_prec/scale, calc_words, scale_adjust)을 **regu 변수 또는 accumulator에 캐시**한다 — 행마다 불변이다. (2) VLA+memset 대신 호출자 소유 스크래치 버퍼를 재사용한다. (3) `numeric_bytes_to_words` 변환을 누산기 측에 **word 표현으로 상주**시켜 왕복을 없앤다 (PG의 `NumericSumAccum` 구조에 해당) |
| 난이도 | 중~상. (3)은 누산기 표현 변경이라 상 |
| 위험 | 스크래치 버퍼 재사용은 **재진입·병렬 워커 안전성** 문제. `parallel-query` 스레드 6개가 각자 버퍼를 가져야 한다. `float_numeric_add_fast`의 fast-path 판정(`:2548`)이 버퍼 초기화 상태를 가정하므로 함께 봐야 함 |
| upstream 유사 시도 | 도입 커밋 `de7bc5ec2`(CBRD-26006, PR #6486)가 "optimize performance"를 명시했으므로 **이미 한 차례 최적화가 있었고 현 상태가 그 결과다.** 재시도 전에 그 PR의 논의를 읽어야 한다 |

### 후보 C — 이미 존재하는 집계 특화 경로를 GROUP BY 경로로 확장

**이 후보는 조사 중에 근거가 크게 강해졌다. upstream에 특화 구현이 이미 있고, Q1은
GROUP BY라는 이유만으로 그것을 못 받는다.**

| 항목 | 내용 |
|---|---|
| 확인된 사실 | `CBRD-26846`(`d0b290459`, **2026-07-02**, PR #7229)이 parallel heap scan에 **BUILDVALUE_OPT 스칼라 집계 특화 경로**를 넣었다. per-row 디스패치를 `if constexpr` + `template <FUNC_CODE F>`로 정적 특화한다(`src/query/parallel/px_scan/px_scan_result_handler.cpp:1068, 1275, 1481, 2146`) |
| **Q1이 배제되는 지점** | `src/query/parallel/px_scan/px_scan_checker.cpp:596-622` — `case BUILDVALUE_PROC:`는 `buildvalue_opt = true`(`:604`)를 받지만 **`case BUILDLIST_PROC: break;`(`:598-599`)** 로 GROUP BY 경로는 아무 것도 받지 못한다 |
| 함수 지원 여부 | `is_buildvalue_opt_supported_function`(`px_scan_checker.cpp:50`)에 **`PT_SUM`, `PT_AVG`, `PT_COUNT`, `PT_COUNT_STAR`가 모두 포함**된다 — **Q1의 집계 집합과 정확히 일치한다** |
| 즉 | Q1은 지원되는 집계만 쓰는데 **GROUP BY가 있다는 이유만으로** 특화를 못 받고 범용 `qdata_add_dbval` 경로(`query_aggregate.cpp:483`)로 간다. 측정된 트레이스가 이를 확인한다 — `GROUPBY (time: 1, hash: partial, sort: true, ...)` = BUILDLIST |
| 건드릴 곳 | `px_scan_checker.cpp:598`(게이트), `px_scan_result_handler.cpp`의 템플릿 디스패치를 그룹 키가 있는 누산기에 재사용 |
| 겨냥 버킷 | **집계·해시 11.4 %** + 그 누산이 유발하는 식 평가·값 변환 |
| 예상 절감 | `qdata_add_dbval` self 5.00 %의 누산 몫(행당 13회 중 7회 ≈ 54 %) + `qdata_aggregate_value_to_accumulator` 1.53 % + 그에 딸린 결과 강제 변환. **2~4 %** (26~51 G) |
| 근거 숫자 | 집계 버킷 **4.53x**(125.3 G vs 27.6 G)인데 그룹은 4개뿐. Q1 집계 7개 × 59,986,052행 |
| 난이도 | 중. **템플릿 디스패치를 새로 쓰는 것이 아니라 게이트와 누산기 결합부만 확장**하므로 후보 D보다 훨씬 국소적이다 |
| 위험 | 낮~중. 오버플로·NULL 의미가 범용 경로와 비트 단위로 같아야 한다. 그룹 키별 누산기를 워커별로 분할·병합하는 부분이 스칼라보다 복잡하지만, 현재 이미 `gather: mergeable list`로 워커 부분결과를 병합하고 있어 골격은 존재한다 |
| upstream 유사 시도 | **있다 — 바로 이 커밋이다.** 따라서 확장은 설계 의도와 충돌하지 않는다. 대조적으로 후보 A 영역(`git log -S 'is_parameterized' -- src/object/object_domain.c`)은 2012/2014 이후 변경이 **없다** |

### 후보 D — 식 평가 스텝의 초기화 시점 타입 소거 (구조 변경)

| 항목 | 내용 |
|---|---|
| 건드릴 곳 | `src/query/fetch.c:85`(`fetch_peek_arith`), `:119`, `:681` 두 switch. XASL 빌드 측(`src/parser/xasl_generation.c`) |
| 겨냥 버킷 | **식 평가/튜플 구성 28.8 %** (최대 기여 버킷) |
| 예상 절감 | 상한이 가장 크다 — `fetch_peek_arith` 4.36 % + `fetch_val_list` 2.31 % + `fetch_peek_dbval_slow` 1.89 % + `qdata_add_dbval` 5.00 %의 디스패치 몫. **5~10 %** (64~128 G) |
| 근거 숫자 | 식 평가/튜플 구성 **5.57x**(299.7 G vs 53.8 G), 격차 기여 **28.8 %**. PG는 `ExecInitFunc`(`execExpr.c:2697`)로 이 작업을 초기화 시점에 옮겨 실행 시 `fn_addr` 직접 호출(`execExprInterp.c:963`) 하나로 끝낸다 |
| 설계 | XASL 생성 시 각 arith 노드에 (opcode, 좌타입, 우타입, 결과도메인)로 해소한 **연산 함수 포인터를 심는다.** `fetch_peek_arith`의 373-case switch를 포인터 호출로 대체. PG의 `ExprEvalStep`(`execExpr.h:300`)이 참고 모델 |
| 난이도 | **상.** 373개 opcode 전부를 옮기지 않고 Q1이 쓰는 T_ADD/T_SUB/T_MUL부터 점진 적용해야 한다 |
| 위험 | **높다.** XASL은 디스크·네트워크로 직렬화되고 캐시된다(`xasl_cache`). 함수 포인터를 심으면 직렬화 호환성이 깨지므로 **인덱스/식별자를 심고 실행 시 테이블로 해소**해야 한다. 플랜 캐시 무효화 규칙과 버전 호환성 검토 필수 |
| upstream 유사 시도 | 확인 필요. `src/query/fetch.c`의 이력과 `xasl` 관련 리팩터링 PR 검색이 선행돼야 한다 |

### 후보 E — 속성 읽기의 타입 조회·간접 호출 제거

| 항목 | 내용 |
|---|---|
| 건드릴 곳 | `src/storage/heap_file.c:10286`(`pr_type_from_id`), `:10289`(간접 `data_readval`), `:10440` |
| 겨냥 버킷 | **스캔/레코드 디코드 11.30 %** |
| 예상 절감 | `heap_attrinfo_read_dbvalues` 4.94 % + `pr_type_from_id` 2.03 % + `mr_data_readval_numeric` 2.43 %의 디스패치 몫. **1.5~3 %** (19~38 G) |
| 근거 숫자 | 스캔/레코드 디코드 2.27x(144.5 G vs 63.7 G). Q1은 lineitem 7속성을 읽으므로 행당 타입 조회 7회 + 간접 호출 7회 |
| 설계 | `HEAP_CACHE_ATTRINFO`에 속성별 `pr_type` 포인터를 **캐시 구성 시 1회** 해소해 저장한다(현재는 행마다 `pr_type_from_id`). PG의 `CompactAttribute` 캐시(`execTuples.c:1020-1021`)와 같은 취지 |
| 난이도 | **하.** 후보 중 가장 국소적이다 |
| 위험 | 낮음. 스키마 변경 시 attrinfo 캐시 무효화가 이미 존재하는지 확인만 필요 |
| upstream 유사 시도 | 확인 필요 |

### 후보 우선순위 (프로파일 근거 + 위험)

| 순위 | 후보 | 예상 절감 | 난이도 | 위험 | upstream 선례 |
|---|---|---|---|---|---|
| 1 | **C** 집계 특화를 GROUP BY로 확장 | 2~4 % | 중 | 낮~중 | **있음** — CBRD-26846이 스칼라 경로에 이미 구현 |
| 2 | **E** 속성 읽기 타입 캐시 | 1.5~3 % | 하 | 낮음 | 2019 CBRD-22284가 이 파일 마지막 손질 |
| 3 | **A** NUMERIC 도메인 조기 반환 | 2~5 % | 중 | 중(정합성) | 없음 — 2012/2014 이후 무변경 |
| 4 | **B** float_numeric 재도출 제거 | 3~6 % | 중~상 | 중(재진입) | 있음 — CBRD-26006이 이미 한 차례 최적화 |
| 5 | **D** 식 평가 구조 변경 | 5~10 % | 상 | 높음(XASL 호환) | 없음 — 2013/2014 이후 무변경 |

**C를 1순위로 올린 이유**: 특화 구현이 이미 존재하고(`px_scan_result_handler.cpp`의
`template <FUNC_CODE F>` + `if constexpr`), Q1이 쓰는 집계가 모두 지원 목록에 있으며,
막는 것은 `px_scan_checker.cpp:598-599`의 `case BUILDLIST_PROC: break;` 한 줄이다.
새로 설계할 것이 아니라 게이트와 결합부를 확장하는 일이다.

**지금 구현하지 않았다.** 조사와 설계만이다.

## 남은 확인 사항 (정직하게 열어 둔다)

* "upstream 유사 시도" 칸은 **전부 확정했다**: A는 2012/2014 이후 무변경, B는
  CBRD-26006(`de7bc5ec2`)이 이미 최적화, C는 CBRD-26846(`d0b290459`)이 스칼라 경로에
  구현, D는 2013/2014 이후 무변경, E는 2019 CBRD-22284(`a6ce5d46f`)가 마지막.
* `tp_value_cast_internal`이 Q1에서 실제로 **어느 산술 노드에서** 조기 반환에 실패하는지는
  코드 경로로 규명했지만 **런타임 카운터로 세지 않았다.** 확정하려면 `:7145` 분기에
  카운터를 넣은 계측 빌드가 필요하다(측정 빌드 변경이므로 별도 게이트).
* 예상 절감치는 **self instructions 상한**에서 나온 것이고, 제거된 작업이 다른 곳으로
  옮겨가는 몫은 반영하지 않았다. 구현 후 재프로파일로만 확정된다.
