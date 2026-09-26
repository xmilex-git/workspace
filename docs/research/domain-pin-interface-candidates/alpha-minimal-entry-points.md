# 설계 α — 최소 인터페이스: 서버 공개 진입점 3개 (`xplan_derive` · `xgate_apply` · `xgate_peek`)

티켓 #323 · 전략 A(D-318-01) 안에서의 인터페이스 안 · 제약: **서버 측 공개 진입점 ≤ 3, 진입점당 레버리지 최대**. 기준 엔진 `develop cad27172b`(워크트리 `~/dev/cubrid-worktree/dpin`). 인용 표기는 `domain-pin-exec-sites.md` 와 같다(`qx:` query_executor.c, `fe:` fetch.c, `sx:` stream_to_xasl.c, `xs:` xasl_to_stream.c, `sm:` scan_manager.c, `pd:` parse_dbi.c, `xg:` xasl_generation.c, `vdb:` db_vdb.c, `mc:` method_callback.cpp, `pxt:` px_scan_task.cpp).

**모듈 하나, seam 둘.** 새 모듈 `xasl_plan`(서버 전용, `src/query/xasl_plan.{hpp,cpp}` + 내부 `xasl_domain_resolver.{hpp,cpp}`)이 "이 노드의 도메인·변환기는 무엇인가" 를 소유한다. 외부 seam 은 (1) 로드 seam — `stx_map_stream_to_xasl` 안에서 `xplan_derive` 1회, (2) 실행 seam — `xgate_apply` 를 스코프(실행/블록/range)마다 부르고 행 경로는 `xgate_peek` 로 읽기만. 나머지(슬롯 ID 부여, 부류 판정, 변환기 선택, 게이트 의존 목록, 표 채우기, 값 소유)는 전부 **구현**이다. 삭제 테스트: 이 모듈을 지우면 43곳(S-01~S-43)의 복잡도가 다시 흩어진다 — 깊은 모듈이다.

---

## 1. 인터페이스

### 1.1 공개 함수 3개 (`src/query/xasl_plan.hpp`, 서버 전용 — 클라이언트 헤더로 새지 않는다, PHYS-05)

```c
/* E1 로드 도출 — stx_map_stream_to_xasl / _filter_pred / _func_pred 의 언팩 직후 1회.
 * 순수 함수: 같은 스트림 → 같은 슬롯 ID·항목(세 로드 경로 동치). 결과는 unpack arena 에 산다. */
typedef enum { XPLAN_KIND_QUERY, XPLAN_KIND_PRED /* 필터/함수 인덱스: GATE 비트 있으면 거부 */ } XPLAN_KIND;
int xplan_derive (THREAD_ENTRY *thread_p, xasl_node *root, XASL_UNPACK_INFO *arena, XPLAN_KIND kind);

/* E2 게이트 적용 — 스코프당 1회. EXEC(G1) 만 결정하고 나머지는 계획된 변환기 적용만. */
typedef enum
{
  XGATE_SCOPE_EXEC,	/* G1: qexec_execute_query, vd 형성 직후. 게이트 표·참조값 배열 생성(결정 지점) */
  XGATE_SCOPE_BLOCK,	/* G2: mainblock_internal, precompute 뒤·iterations 전. S 부류 변환기 적용 */
  XGATE_SCOPE_RANGE	/* 키 range open: scan_regu_key_to_index_key. S 키 변환기 적용 */
} XGATE_SCOPE;
int xgate_apply (THREAD_ENTRY *thread_p, xasl_node *xasl, xasl_state *xs, XGATE_SCOPE scope);

/* E3 읽기 — 행 경로의 유일한 접근자(inline, 분기 0). */
static inline DB_VALUE *xgate_peek (const VAL_DESCR *vd, const REGU_VARIABLE *regu);          /* 참조별 변환값 */
static inline const XGATE_ENTRY *xgate_entry (const VAL_DESCR *vd, const XPLAN_ITEM *item);   /* 항목의 실행당 답 */
#define XPLAN_DOMAIN(vd, item)   (xgate_entry ((vd), (item))->domain)
#define XPLAN_CONV(vd, item, k)  (xgate_entry ((vd), (item))->conv[(k)])
```

`xgate_peek`·`xgate_entry` 는 한 진입점(읽기)의 두 형태로 센다. XASL_STATE 수명은 기존 `qexec_deep_copy_xasl_state`/`qexec_free_xasl_state` 가 그대로 담당하되 구현이 이 모듈로 옮겨지고, 루트(스택 XASL_STATE)용으로 내용만 비우는 `qexec_clear_xasl_state (thread_p, xs)` 가 기존 짝에 추가된다 — 새 모듈 진입점이 아니라 기존 수명 함수군의 변형이다.

### 1.2 타입 — 로드 도출 결과(불변, arena 소유)

```c
typedef int (*XCONV_FN) (THREAD_ENTRY *thread_p, const DB_VALUE *src, DB_VALUE *dst, const TP_DOMAIN *dom);  /* #325 표의 원소 */
typedef enum { XFAIL_ERROR /* -494 계열 */, XFAIL_NULL /* return_null_on_function_errors */, XFAIL_KEEP /* 비교 strict-or-keep */, XFAIL_ROUND /* 대입 */ } XFAIL_POLICY;
typedef enum { XPLAN_K = 1, XPLAN_R = 2, XPLAN_S = 3 } XPLAN_CLASS;

typedef struct xgate_entry XGATE_ENTRY;   /* 게이트 표 항목 = 실행당 답 */
struct xgate_entry
{
  TP_DOMAIN *domain;		/* 확정 도메인 — collation·codeset 은 이 도메인 안(collation_flag 항상 NORMAL) */
  XCONV_FN conv[3];		/* 피연산자별 계획된 변환기(left/right/third 또는 lhs/rhs/키원소), NULL = 변환 없음 */
  TP_DOMAIN *setdomain;		/* 키 range 항목만: strict-or-keep 결과로 조립한 midxkey setdomain(게이트 표 소유) */
};

typedef struct xplan_item XPLAN_ITEM;     /* 노드마다 1개, original_domain 자리에 포인터 */
struct xplan_item
{
  short cls;			/* XPLAN_CLASS */
  short flags;			/* XPLAN_GATE 0x01(답은 표에) · XPLAN_KEY1 0x02 · XPLAN_KEY2 0x04 · XPLAN_ISS 0x08 · XPLAN_ALIAS 0x10(파생 소비자: 생산자 slot 공유) · XPLAN_KEEP_LAZY 0x20 */
  int slot;			/* 게이트 표 인덱스, -1 = 정적(답은 st) */
  int ref;			/* K 슬롯 참조의 참조값 인덱스(gate.vals[]); TYPE_POS_VALUE 외 -1 */
  int val_pos;			/* 바인드 배열 인덱스(TYPE_POS_VALUE) 또는 -1 */
  XFAIL_POLICY fail;		/* 이 참조 자리의 실패 정책(X1) */
  XGATE_ENTRY st;		/* 정적 항목의 답(로드 확정: 도메인 = 노드 domain, conv = xconv_lookup 결과) */
  const XPLAN_ITEM *pair;	/* ISS 내림차순 fetch 범위 짝(key1↔key2), 아니면 NULL */
};

typedef struct xplan XPLAN;               /* 트리당 1개, 루트 xasl_node->xplan(모든 블록이 같은 포인터) */
struct xplan
{
  int n_items;  XPLAN_ITEM *items;	/* 부여 순서 배열(덤프·경계 검사) */
  int n_slots;				/* 게이트 표 길이 = GATE 항목 + KEEP_LAZY 항목 + 키 range 항목 */
  int n_refs;				/* 참조값 배열 길이 = dbval_cnt + 2차 참조 수 */
  int dbval_cnt;			/* root->dbval_cnt 사본(경계 검사) */
  int n_gate_nodes;  XPLAN_ITEM **gate_nodes;	/* 게이트 의존 노드, 생산자 우선 순서 */
  int n_refs_k;      XPLAN_ITEM **refs_k;	/* K 참조 항목(ref 오름차순) */
  int n_blocks;      struct xplan_block *blocks;
};
struct xplan_block { XPLAN *plan; int n_s; XPLAN_ITEM **s_items; };   /* 블록당 G2 대상(S 부류) — xasl_node->xplan_blk */
```

**필드 재사용(MEM-02, 구조체 크기 불변)**: `regu_variable_node::original_domain` → `XPLAN_ITEM *xplan`; `ARITH_TYPE::original_domain` → `XPLAN_ITEM *xplan`; `aggregate_list_node::original_domain` → `XPLAN_ITEM *xplan`, `original_opr_dbtype`(DB_TYPE, 4B) → `int xplan_acc`(누산기 value2 항목 인덱스, -1 없음); `analytic_list_node` 동일; `qfile_tuple_value_position::original_domain` → `XPLAN_ITEM *xplan`. 새 필드: `xasl_node::xplan`(XPLAN*)·`xasl_node::xplan_blk`(xplan_block*) 2개 — xasl_node 는 디스크에 없고 블록당 1개라 허용. **GATE 스트림 비트**: `REGU_VARIABLE_GATE = 0x4000`(regu flags 의 다음 미사용 비트; 레이아웃 불변). arith 는 flags 가 없으므로 소유 regu(TYPE_INARITH) 의 비트로, agg 는 `flag.dummy` 를 `flag.gate` 로 개명, analytic 은 `flag |= ANALYTIC_GATE 0x?`(기존 `int flag` 의 미사용 비트), pos_descr 는 비트 없음(생산자에서 로드 도출).

### 1.3 타입 — 실행 상태(XASL_STATE 소유)

```c
typedef struct xgate_state XGATE_STATE;
struct xgate_state
{
  const DB_VALUE *in;		/* 입력 배열(const 유지; SA_MODE 에서는 parser->host_variables 자체) */
  DB_VALUE *vals;		/* n_refs: 참조별 변환값. 만든 스레드가 db_private_alloc, 같은 스레드가 해제 */
  XGATE_ENTRY *table;		/* n_slots: 게이트 표. G1 뒤 불변 */
  int n_vals, n_slots;
  THREAD_ENTRY *owner;		/* 소유 스레드(assert), PX 사본은 워커 자신 */
  const XPLAN *plan;
};
struct xasl_state { VAL_DESCR vd; QUERY_ID query_id; int qp_xasl_line; XGATE_STATE gate; };   /* query_executor.h:88 확장 */
```

**불변식.** (I1) G1 뒤 `vd.dbval_ptr == gate.vals` 이고 `vals[val_pos]`(0 ≤ val_pos < dbval_cnt) 는 그 `?` 의 **1차 참조** 도메인 값, `vals[dbval_cnt..n_refs)` 는 2차 참조 값 — 기존 `vd->dbval_ptr[val_pos]` 소비자(서브쿼리 캐시 키 fe:4763, 결과 캐시)는 무변경으로 1차 값을 본다. (I2) 게이트 뒤 모든 K 참조에서 `DB_VALUE_DOMAIN_TYPE(vals[ref]) == TP_DOMAIN_TYPE(XPLAN_DOMAIN(item))` 이거나 `fail == XFAIL_KEEP` 으로 표에 기록된 항목(B4)이다 — 경계 (b) 의 assert. (I3) `gate.in` 은 실행 중 어떤 스레드도 쓰지 않는다. (I4) 같은 트리를 세 로드 경로 중 어느 것으로 로드해도 `n_items/n_slots/n_refs` 와 각 항목의 `slot/ref` 가 같다(PX 워커가 자기 트리의 XPLAN 으로 루트의 `gate.table` 을 읽을 수 있는 근거; 워커 진입 시 `assert (worker_plan->n_slots == root_gate->n_slots)`). (I5) 게이트 의존 노드 목록은 생산자 우선: 항목 i 의 피연산자 항목 j 는 `gate_nodes` 에서 i 앞에 온다.

**오류 모드.** `xplan_derive`: 경계 (a) 위반 → `ER_QPROC_DOMAIN_UNRESOLVED`(§5), PRED 종류에서 GATE 비트 → 같은 코드(phase "load"). `xgate_apply(EXEC)`: K 변환 실패 → 항목의 `fail` 정책(ERROR 면 현행 -494 계열 `ER_TP_CANT_COERCE`/`ER_QPROC_INCOMPATIBLE_TYPES` 그대로, 실행 전 오류이므로 행 중간 오류 없음), collation 병합 실패 → -1150/-622 그대로. `xgate_apply(BLOCK/RANGE)`: 변환기 반환 코드 전파(결정 없음). **성능 특성.** 로드 도출 = 트리 크기 O(N) 1회(언팩과 같은 차수, 클론 풀 재사용 시 0). G1 = O(n_refs_k + n_gate_nodes)(정적 계획 = 두 배열 길이 0 → 0 순회, 할당 0: `n_refs == dbval_cnt && n_slots == 0` 이면 `vals = in` 별칭 없이 `dbval_cnt` 만 clone). 행 경로 = 포인터 역참조 1회 + 간접 호출 1회(BR-06/A61: switch 제거).

### 1.4 슬롯 ID·참조·게이트 의존 목록 부여 순서 (구현 규칙, 문서화된 것은 "결정적" 뿐)

트리 순회 1개가 항목·슬롯·참조·목록을 동시에 만든다: `aptr_list`(리스트 순, 각각 재귀) → 이 블록의 `spec_list`(spec 순: 키 range key1→key2 → 키 필터 → 데이터 필터) → `val_list/outptr_list` → `after_join/if_pred` → `groupby`(g_regu → agg 피연산자 → 누산기 → g_outptr) → `orderby`·`instnum/ordbynum` → 분석 → `dptr_list` → `scan_ptr`. 식 내부는 **후위**(피연산자 먼저) — 이것이 곧 생산자 우선 순서라 `gate_nodes` 는 별도 정렬 없이 순회 순서 그대로다(I5). 파생 소비자(리스트 컬럼 pos_descr·정렬 키·누산기·BUILDVALUE 출력 regu·집합 연산 컬럼)는 `XPLAN_ALIAS` 로 생산자 항목의 `slot` 을 공유하고 표 항목을 새로 만들지 않는다(L-41: 생산자를 채우면 소비자는 자동).

### 1.5 값 소유·해제·PX 상속

G1 이 `vals/table` 을 연결 스레드 private heap 에 만들고(`gate.owner = thread_p`), `qexec_execute_query` 종료 시 같은 스레드가 `qexec_clear_xasl_state` 로 해제(ALLOC-08/A64). 실행 중 어느 워커도 루트 배열을 해제하지 않는다(S-39 `db_change_private_heap` 전환 삭제 — in-place coerce 자체가 없다). PX: `qexec_deep_copy_xasl_state`(qx:3678) 하나가 `vals` 를 `pr_clone_value` 로, `table` 은 **읽기 전용 공유**(포인터 복사; 항목의 TP_DOMAIN 은 캐시 도메인이고 `setdomain` 은 루트가 워커 join 뒤 해제)한다 — pxt:648 의 `memcpy(m_vd, m_orig_vd)` + clone 루프는 이 함수 호출 한 줄로 교체(D-318-06). 워커의 `qexec_free_xasl_state` 는 자기 `vals` 만 해제(`owner == 자기`).

---

## 2. 호출 순서

```
qexec_execute_query (qx:17456)
  xasl_state.vd.dbval_ptr = (DB_VALUE *) dbval_ptr;  vd.dbval_cnt = dbval_cnt;   (qx:17578~17579, 그대로)
  … sys_datetime/epoch …
+ xgate_apply (thread_p, xasl, &xasl_state, XGATE_SCOPE_EXEC);      ← G1. 실패 = 실행 전 오류(query_error 로)
  qdump / qexec_execute_mainblock (…)
  …
+ qexec_clear_xasl_state (thread_p, &xasl_state);                  ← 정상·오류 경로 모두(vals/table 해제, vd.dbval_ptr = NULL)

qexec_execute_mainblock_internal (qx:16150)
  aptr_list 실행 (qx:16538~)  — 하위 블록은 같은 xasl_state 를 받고 자기 블록의 G2 를 돈다
  precompute (qx:16696~16716)
+ xgate_apply (thread_p, xasl, xasl_state, XGATE_SCOPE_BLOCK);      ← G2: xasl->xplan_blk->s_items 의 변환기 적용만
  qexec_start_mainblock_iterations (qx:16720)

scan_regu_key_to_index_key (sm:2328) / scan_get_index_oidset
+ xgate_apply (thread_p, xasl, vd->xasl_state, XGATE_SCOPE_RANGE);  ← S 키만 변환(K 키는 G1 에서 끝, 항목 플래그로 건너뜀)

fetch_peek_dbval TYPE_POS_VALUE (fe:4745)      *peek_dbval = xgate_peek (vd, regu_var);   (FETCH_ALL_CONST 설정 삭제 — 로드 도출)
EXECUTE_REGU_VARIABLE_XASL (xasl.h:554) 뒤 TYPE_CONSTANT 상관 값     item->cls == XPLAN_S 면 conv 적용(스코프 = 외부 행)
px_query_executor.cpp:48 / px_query_task.cpp:123    qexec_deep_copy_xasl_state (gate 포함)
pxt:648                                              → 위 함수로 교체
```

**G1 알고리즘(xgate_apply EXEC).** ① `assert (plan->dbval_cnt == vd.dbval_cnt)`; `vals[n_refs]`·`table[n_slots]` 할당, `gate.in = vd.dbval_ptr`. ② `refs_k` 순회(ref 오름차순): `src = in[val_pos]`; 정적 항목이면 `fn = xconv_lookup (DB_VALUE_DOMAIN_TYPE (src), item->st.domain, item->fail)` 로 **실행당 1회** 조회 후 `fn (src, &vals[ref], dom)`; 실패 시 정책 — ERROR: 오류 반환 / NULL: `vals[ref] = NULL` / KEEP: `pr_clone_value (src, &vals[ref])` + 항목이 `XPLAN_KEEP_LAZY` 이므로 `table[slot]` 을 해석기로 재확정(비교 도메인 = 현행 표: INT vs DOUBLE → DOUBLE, `conv[0] = int→double`) / ROUND: 대입 캐스트. GATE 슬롯(P2)은 `table[slot].domain = tp_domain_resolve_value (src)`(문자면 codeset/collation 포함, C3 병합의 입력) + clone. ③ `gate_nodes` 순회(생산자 우선): 피연산자 도메인을 `XPLAN_DOMAIN` 으로 읽어 `xdom_resolve (op, doms, n, &table[slot])` — 산술 결과·비교 도메인·COALESCE 류 공통 타입·누산기·리스트 컬럼·collation 병합(`LANG_RT_COMMON_COLL`)이 여기서 1회. ④ 키 range 항목: K 키 strict-or-keep → `table[slot].setdomain` 조립(§4). 정적 계획은 ②③④ 가 빈 배열 = 0 순회.

**SA_MODE 별칭.** `gate.in` 이 `parser->host_variables` 자체여도 쓰지 않으므로(I3) 클라이언트 값 불변; 결과 캐시 키(`params.vals`)·`copy_bind_value_to_tdes` 는 `gate.in` 기준(게이트 전 값) — 현행과 같다.

---

## 3. `val_pos` 다중 참조

**실제 발생 경로(소스 확인).** R1 `qo_reduce_equality_terms`(query_rewrite_term.c:448~): `qo_is_reduceable_const` 가 `PT_IS_CONST_INPUT_HOSTVAR` 를 참이라 하므로 `t1.i = ? AND t1.i = t2.b` 는 `t2.b = ?`(같은 `index`) 를 추가 생성한다 — 파라미터화 타입 컬럼이면 사본을 `CAST(? AS <t1.i 타입>)` 로 감싼다(:868). 파생 테이블 경로(:615~623)도 `parser_copy_tree (expr)` 로 같은 `?` 를 복제. R2 `pt_copypush_terms`(view_transform.c:4505~4506)는 UNION 파생 테이블의 `arg1`·`arg2` 양쪽에 같은 술어 사본을 밀어 넣는다 — `(SELECT int_c … UNION ALL SELECT dbl_c …) v WHERE v.c = ?` 의 `?` 가 INTEGER 형제와 DOUBLE 형제를 동시에 가진다. 각 사본 노드는 자기 `expected_domain` 을 가지고 `pt_make_regu_hostvar` 가 노드별로 도메인을 실으므로 **같은 val_pos 의 regu 들이 다른 도메인을 갖는 것은 이미 현행**이며, 클라이언트 캐스트만 `host_var_expected_domains[idx]`(마지막 기록자 승) 하나를 썼다.

**설계.** 참조 = (val_pos, 목표 도메인, 실패 정책) 삼중. 로드 도출이 `TYPE_POS_VALUE` regu 를 만날 때마다 이 삼중으로 참조를 **중복 제거**해 `ref` 를 준다: 첫 참조(순회 순서)는 `ref = val_pos`(1차), 삼중이 다른 뒤 참조는 `ref = dbval_cnt + k`(2차). 같은 삼중은 같은 `ref` 를 공유(변환 1회). G1 은 `refs_k` 를 돌며 각 `ref` 에 한 번 변환한다 — `t1.i = ?`(INT, KEEP) 와 `t2.b = ?`(BIGINT, KEEP) 는 두 자리, `vals[0]` = INT 값, `vals[dbval_cnt]` = BIGINT 값. 실패 정책 NULL(X1)은 그 `ref` 자리에만 들어가고 `gate.in` 은 불변(D-327-10). 소비자(`fetch`)는 `xgate_peek` 로 자기 `ref` 를 읽으므로 참조별 값이 분기 없이 나온다. 게이트 표에는 참조가 항목을 만들지 않는다(값 배열만).

---

## 4. 인덱스 키 변환 계획

- **`INDX_INFO.key_type`**(TP_DOMAIN*, 인덱스 키 도메인 — 단일 컬럼은 그 컬럼 도메인, midxkey 는 setdomain 체인): 컴파일이 `index_entryp->key_type` 을 그대로 싣는다(L-45(f)). 스트림 위치: `xts_process_indx_info`(xs:4760) 에서 `func_idx_col_id` 다음·`cov_list_id` 오프셋 앞에 `OR_PACK_DOMAIN_OBJECT_TO_OID (ptr, key_type, 0, 0)`, `stx_build_indx_info`(sx:4784) 같은 자리에 `or_unpack_domain`; `xts_sizeof_indx_info`(xs:7024) 에 `or_packed_domain_size`. access-spec 레이아웃이라 디스크 무관, 클라이언트·서버 lockstep 은 현행 요구 그대로.
- **항목**: key range 마다 `key1`·`key2` regu 각각 항목(`XPLAN_KEY1`/`XPLAN_KEY2`, L-45(c) 분리). midxkey(`TYPE_FUNCTION` T_MIDXKEY)는 원소 regu 마다 항목, 목표 = `key_type->setdomain[i]`. 부류: 바인드·auto-param·상수식 = K(G1), 상관 `TYPE_CONSTANT`/조인 `TYPE_POSITION`/ISS `TYPE_DBVAL` = S(RANGE).
- **K 키(G1 1회)**: 원소마다 `tp_value_coerce_strict` 의미의 변환기 → 성공 = 인덱스 도메인 값, 실패 = 값 유지(B30·B31, 의미 현행). range 항목의 `table[slot].setdomain` 을 이때 1회 조립(실패 원소만 값 도메인) — `need_new_setdomain`/`prebuilt_midxkey_domains`(sm:1889, sm:2251, sm:3745, sm:5418) 삭제, 해제는 게이트 표와 함께(L-45(g) 누수 소멸). `btree_compare_key` 폴백(S-12) 자리는 `conv[]`(원소별 `idx_elem→값 도메인` 비교 변환기) 호출로.
- **S 키(range open, 전략 재추론 0)**: 로드가 외부 컬럼 도메인(알려짐)→인덱스 도메인의 변환기와 **keep 경로용 대체 setdomain** 을 둘 다 arena 에 미리 만들어 둔다(`item->st.conv[0]` = strict, `item->st.setdomain` = 값 도메인판). range open 은 변환 결과(성공/실패)로 둘 중 하나를 **고르기만** 한다 — 도메인을 새로 만들지도, 값을 보고 전략을 다시 정하지도 않는다(L-45(a)(b)).
- **ISS**: `iss_range.key1` 의 `TYPE_DBVAL` 첫 컬럼 도메인 = `key_type->setdomain`(sm:447~458 이 이미 그렇게 읽음; S-31 의 `last_key` 값 도메인 대입 삭제). 내림차순 bound 이동(key1→key2)은 두 항목이 `pair` 로 서로를 가리키는 fetch 범위 짝 — 스텝은 `pair` 의 계획으로 변환(L-45(d)).
- **MRO**: `btree_range_opt_check_add_index_key`(S-32)의 `sort_col_dom` 을 로드 도출이 `key_type` 오름차순 사본(`is_desc` 제거, arena)으로 시딩(L-44·L-45(e)); `has_null_domain` 루프 삭제. KEYLIMIT 슬롯은 BIGINT K(B34).

---

## 5. 검증 경계

**(a) 로드 경계(`xplan_derive` 끝).** 항목 순회로 "도메인이 VARIABLE/LEAVE 인데 GATE 비트도 ALIAS 도 아닌" 노드를 찾으면 오류. 예외 표는 `xasl_plan.cpp` 의 `xplan_derive` 바로 옆 정적 배열 `xplan_load_exceptions[]` 로 두고 각 행에 근거를 단다:

| # | 자리 | 왜 설계상 VARIABLE 인가 | 처리 |
|---|---|---|---|
| X-1 | `TYPE_REGU_VAR_LIST` 포장 regu(CUME_DIST/PERCENT_RANK 인자 묶음) | 값이 아니라 목록 | 항목 없음(자식만 도출) |
| X-2 | `REGU_VARIABLE_ANALYTIC_WINDOW` 정렬 키 regu | 윈도우 프레임 계산용, 리스트 컬럼 도메인을 ALIAS 로 받음 | ALIAS |
| X-3 | 집합 연산(UNION/DIFFERENCE/INTERSECTION) 리스트 컬럼 pos_descr | 두 가지가 모두 GATE 면 공통 도메인은 게이트 표(U3/C8) | ALIAS→GATE 항목 |
| X-4 | `TYPE_LIST_ID`·`TYPE_ORDERBY_NUM`·`TYPE_INST_NUM` 등 값 도메인이 고정인 특수 regu | 도메인 필드를 안 씀 | 항목 없음 |
| X-5 | `TYPE_FUNCTION` 집합 생성자(F_SEQUENCE/F_SET…) 결과 | 컬렉션 도메인은 원소에서 | 정적(원소 ALIAS) |
| X-6 | `T_EVALUATE_VARIABLE` 세션변수 읽기 | S4 형제 있으면 미러 정적, 없으면 GATE(S5) — 컴파일이 비트를 단다 | GATE 비트 요구 |

필터/함수 인덱스: `stx_map_stream_to_filter_pred`/`_func_pred` 가 `xplan_derive (…, XPLAN_KIND_PRED)` 를 부르고, GATE 비트가 하나라도 있으면 거부. `fpcache_claim`(filter_pred_cache.c:355~416)은 `stx_map_stream_to_filter_pred` 오류를 `NO_ERROR + NULL` 로 삼키지 않고 그대로 반환하도록 고친다(S-42).

**(b) 실행 경계.** 신설 코드 **`ER_QPROC_DOMAIN_UNRESOLVED = -1383`**(`ER_LAST_ERROR` → -1384), `cubrid.msg $set 5`: `1383 Domain of a query node is unresolved at %1$s (query %2$s, node %3$d, domain %4$s).` 인자 = phase("load"/"execute"), `xasl->query_alias`(없으면 `qp_xasl_line`), 항목 인덱스, 도메인 이름. optdebug 는 같은 자리에 `assert`. 설치 자리(D-318 결정 3): `qdata_get_valptr_type_list`, `fetch_peek_dbval_slow` 의 옛 VARIABLE 분기 자리, `btree_compare_key` 폴백 자리, `eval_value_rel_cmp` coercion 자리, 집계 첫값 대기 자리, `scan_dbvals_to_midxkey` 전략 재추론 자리 + I2 assert(`xgate_apply` 끝). 재컴파일 트리거 목록 — vdb:2277(`RECOMPILE_REQUESTED | INVALID_XASLNODE | RESULT_CACHE_INVALID`), vdb:1102·2174·2314·2390·2537, cas_execute.c:1188·1502·2376, cas_common_execute.c:364, trigger_manager.c:4971, mc:276 — 어디에도 **넣지 않는다**(조용한 재컴파일 금지, D-318-04). 클라이언트는 이 코드를 일반 오류로 사용자에게 올린다.

---

## 6. 클라이언트 경로

- **`pt_set_host_variables`(pd:3072)**: `is_ref` 검사 + `pr_clear_value/pr_clone_value` 만 남기고 `tp_value_cast_preserve_domain` 분기·CHAR 원 값 유지 분기(pd:3128) 삭제(B7 의미는 게이트 CHAR 변환기로, D-327-01). `set_host_var = 1` 유지(재계획 입력).
- **`host_var_expected_domains[]` 남는 소비자**: vdb:2954 `prepare_info` 팩(→ 드라이버 파라미터 메타), mc:657 PL 보고(`semantics.hvs[idx].type`), semantic_check.c:13412(대입 lhs 도메인 추론), vdb:3350·3436(하위 세션 공유), 바인드 피크 재계획(값은 비용에만, D-318-05). 쓰기는 tc:8617 `pt_preset_hostvar` 그대로.
- **`pt_make_regu_hostvar`(xg:6391)**: 2단계(값 타입 → 도메인, xg:6418~6445)와 꼬리의 `db_value_domain_init`/`tp_value_cast (val, val, …)`(xg:6474~6500) 삭제 — 남는 순서 = data_type → expected_domain → type_enum, 그리고 GATE 슬롯이면 placeholder 도메인 + `REGU_VARIABLE_GATE`. 리터럴 형제 미러·소비자 도메인 우선은 타입 검사 첫 패스에서 확정(F-3 멱등).
- **카운트 불변식(L-30)**: `pt_to_xasl` 끝에 `assert (parser->dbval_cnt == parser->host_var_count + parser->auto_param_count)`; PREPARE 이름 재사용·`EXECUTE PREPARE` 경로도 같은 자리(하나).
- **결과 컬럼 메타(L-31)**: prepare 응답은 컴파일 도메인(현행 경로). GATE 결과 컬럼(`SELECT ?`·`SELECT ? UNION SELECT ?`·`SELECT sum(?)`)은 서버의 `list_id.type_list` 가 게이트 표 도메인으로 만들어지므로(`qdata_get_valptr_type_list` 가 `XPLAN_DOMAIN` 을 읽음) 실행 응답 `include_column_info`(cas_execute.c:1292·1637·1834) 경로가 현행 그대로 갱신 — wire 변경 0. 미실행 문장(S2)은 후속.
- **PL/CSQL 선언 타입(S6)**: prepare 입력에 `param_types` 를 싣는다 — PL 서버 → `method_callback.cpp` prepare 요청에 마커별 (DB_TYPE, precision, scale, codeset, collation) 배열 추가, 클라이언트 파서에 `parser->host_var_decl_domains[]`(NULL 허용, JDBC 는 NULL) 를 두고 `db_compile_statement` 전에 `db_set_host_var_declared_domains (session, n, doms)` 로 주입; 타입 검사는 이 도메인을 `?` 노드의 **형제**(P1 의 "PL 선언 타입")로 본다. 보고 경로(mc:650~675 `semantics.hvs[idx].type`)는 그대로 — 입력만 추가된다. NULL 바인드는 typed NULL(L-16).

---

## 7. SHOW PLAN / trace 출력

- `qdump_print_regu_variable`(query_dump.c)가 regu 마다 `{plan: #<item> cls=K|R|S slot=<n>|static ref=<n> conv=<name>|- fail=ERR|NULL|KEEP|RND gate}` 를 덧붙인다(`xplan_conv_name (fn)` 은 #325 표의 이름 열). `qdump_print_xasl` 첫 줄에 XPLAN 요약 `plan: items=N slots=S refs=R(+k) gate_nodes=G`.
- trace JSON(`qdump_print_stats_json`, query_dump.c:3175): 루트 객체에 `"plan": {"slots":S,"refs":R,"gate_nodes":G}`(정적) — 실행당 답(게이트 표)은 XASL_STATE 에만 있으므로 `SHOW EXEC STATISTICS` 카운터(`Num_domain_gate_convert` 등, #324)로 관찰하고 JSON 에는 넣지 않는다(플랜 캐시 텍스트 불변, L-50).

---

## 8. 도메인 해석기 seam

`src/query/xasl_domain_resolver.hpp`(서버 전용; `parser/` 는 include 하지 않는다 — PHYS-05; 클라이언트 그리드 `type_checking.c` 와는 별개의 한 벌, P0·P6·D-318-07):

```c
struct xdom_result { TP_DOMAIN *domain; XCONV_FN conv[3]; };
int xdom_resolve (OPERATOR_TYPE op /* T_ADD… 또는 FUNC_CODE 를 op 공간에 매핑 */, const TP_DOMAIN *const *args, int n_args,
                  XFAIL_POLICY fail, xdom_result *out);        /* 현행 값 격자(#321 §2·§3)를 도메인 입력으로 옮긴 순수 함수 */
XCONV_FN xconv_lookup (DB_TYPE src, const TP_DOMAIN *dst, XFAIL_POLICY fail);   /* (원 타입, 목표) → 고정 함수, #325 의 표 */
```

로드 도출은 R 항목(컬럼×컬럼·컬럼×리터럴)에 `xconv_lookup` 을 1회 불러 `item->st.conv` 를 채우고, G1 은 GATE 항목·게이트 의존 노드에 `xdom_resolve` 를, K 참조에 `xconv_lookup` 을 실행당 1회 부른다 — 두 호출자가 같은 모듈을 쓰므로 "로드가 고른 변환기 ≠ 게이트가 고른 변환기" 가 구조적으로 불가능하다. #325 는 이 두 함수의 **표**(행 = (src, dst, 정책) → 함수, 격자 = (op, 도메인들) → 결과)만 채운다; 인터페이스·호출 순서는 이 문서로 고정.

---

## 9. 삭제 목록과 테스트 표면

| 축 | 지점 | 도달 불가하게 만드는 인터페이스 요소 |
|---|---|---|
| CP | S-03 S-11 S-13 S-14 S-15 S-16 S-17 S-18 S-19 S-20 S-21 S-22 S-24 S-25 S-29 S-37 | 노드 도메인 확정(VARIABLE·LEAVE 0) + 파생 소비자 ALIAS → `XPLAN_DOMAIN` 읽기만; S-14 자리에 경계 (b) |
| CP+G1 | S-01 S-02 S-04 S-05 S-06 S-23 S-26 S-27 S-28 S-36 | 정적이면 `item->st`, GATE 면 `table[slot]`(G1 ③ 생산자 우선) — 첫값 대기·탈착·복원·시도 캐스트 코드 삭제; S-06 다중 행 VALUES 는 열 항목 하나(C9 병합은 G1) |
| G1 | S-07 S-09 S-10 S-39 S-40 S-41 | K 참조 변환(`refs_k`), `xgate_peek`; S-09/S-10 자리는 `conv[]` 호출 + I2 assert; S-39 힙 전환은 in-place coerce 소멸로 |
| LD | S-38(sx 6곳·sp 3곳·qx 원복 5곳) S-33 M8(`FETCH_ALL_CONST`/`FAST_PEEK`/`AGG_OPERAND` 재도출: fe:4745·fe:5273·qx:1533~1536·qx:21839·pxt:655) | `original_domain` 필드 자체가 `xplan` 으로 바뀜(G-02); 상수성·AGG_OPERAND 는 `item->cls` 로 로드 시 1회(A59/A62) |
| G1+G2 | S-12 S-30 S-31 S-32 S-34 S-35 | §4 키 계획(K=EXEC, S=RANGE), `pair`, MRO 시딩; S-34/S-35 는 워커가 `table` 을 상속만 |
| KEEP | S-08(`qdata_*_dbval` 값 타입 dispatch) S-10/S-12 함수 자체 | I2 뒤 결정적; 경계 assert 위치 |
| 경계 | S-42(PRED 종류 거부 + `fpcache_claim` 전파) S-43(파라미터, #320) | `XPLAN_KIND_PRED` |
| X | F10 `median(varchar_col)` | 항목 정적(DOUBLE 시도 캐스트는 실행 결정 잔존으로 명시, 경계 예외 목록에 처음부터) |
| collation | #314 §4 26곳(fe:4479 5226 5239 · lf:7082 qx:1362 21193 21249 21277 21405 23137 27787 sm:8231 8254 8287 8293 · qx:21328 21336 21440 21605 qa:1876 3343 qn:59 188 sm:8240 8264 · fe:5273 qn:59 `qdata_agg_is_plain_sum_avg`) | 쌍 조건의 두 축이 함께 사라진다: `XGATE_ENTRY.domain` 의 collation_flag 는 항상 NORMAL(C3 병합은 G1 ③) |

**테스트 표면 = 인터페이스.** (T1) 로드 도출 결정성: 같은 스트림을 xcache 클론·비캐시·PX 워커 경로로 로드해 `items[]` 의 (cls, slot, ref, val_pos) 를 비교 — 워커 진입 assert(I4)를 상시 검사로 두고, 단위 테스트는 `stx_map_stream_to_xasl` 에 캡처한 스트림(CTP 셀 5종)을 두 번 로드해 동치 확인. (T2) G1 단위: 합성 XPLAN + 바인드 배열 → `vals/table` 기대값(다중 참조 R1·R2, KEEP, NULL 정책, GATE 슬롯 collation 병합 -1150). (T3) 경계: VARIABLE 노드가 든 스트림 → -1383; PRED 종류 + GATE 비트 → -1383. (T4) 행동 표면: #317 규칙 셀(17타입×6상황×5경로)·§7 답안 변경 목록·CTP sql 전수+medium(optdebug). (T5) 도달 0: #324 카운터 8종 = 0(경계 위치와 1:1).

---

## 10. 트레이드오프

- **레버리지가 높은 곳**: `xgate_apply` 하나가 G1·G2·range 를 다 받으므로 호출자(query_executor·scan_manager)는 "스코프가 열렸다" 만 알면 된다; `xgate_peek` 하나로 참조별 값·다중 참조·실패 정책 NULL 이 행 경로에서 분기 0 으로 해결된다; ALIAS 로 파생 소비자 11종이 항목 하나로 닫힌다(L-41). 삭제 테스트를 통과한다.
- **얇은 곳**: 스코프 enum 이 세 의미를 한 함수에 묶어 구현 안에 `switch (scope)` 가 생긴다(호출자 단순 ↔ 구현 안 분기 1개, 행당 아님). `XPLAN_ITEM` 이 K/R/S·키·ISS 를 한 구조체로 받아 필드 8개 중 자리마다 2~3개는 비어 있다(항목당 ~56B, 트리당 노드 수만큼 — arena 라 실행당 비용 0).
- **어려워지는 것**: (i) 게이트 표를 워커가 포인터 공유하므로 루트가 워커 join 전에 해제하면 안 된다(현행도 vd 를 join 전 유지; 계약을 `owner` assert 로 고정). (ii) `xasl_node` 에 필드 2개 추가(디스크 무관·클라이언트 lockstep). (iii) S 키 keep 경로의 대체 setdomain 을 로드가 미리 만들어야 하므로 arena 가 midxkey 원소 수만큼 커진다(range 마다 재조립하던 현행보다 총량은 작다). (iv) 진입점이 적어 구현 파일이 커진다 — 내부 seam(`xplan_walk`·`xgate_run_k`·`xgate_run_nodes`·`xgate_run_keys`)을 정적 함수로 두고 T2 가 그 내부를 직접 테스트한다(내부 seam 은 인터페이스가 아니다).
- **기각한 변형**: 슬롯 ID 를 컴파일이 팩(레이아웃 변경) · 게이트 표를 XASL 노드에 쓰고 원복(L-42) · G2 를 별도 진입점으로(호출자가 잊는 사고 부류 — 하나로 묶으면 스코프 누락이 컴파일러 경고 없이도 한 자리에서 보인다).

---

## 11. 렛저 대응표

| L | 이 설계에서 |
|---|---|
| L-30 | §6 카운트 불변식 assert 1곳; 클라이언트 캐스트 삭제로 OOB 순회 자체 소멸 |
| L-40 | §1.2 XPLAN 은 arena(pack 0), §1.1 E1 이 세 로드 경로 공통 자리(I4), §5 PRED 종류 거부 |
| L-41 | §1.4 ALIAS(파생 소비자는 생산자 slot 공유), G1 ③ 생산자 우선, MERGE/CTE 하위 XASL 은 aptr 순서로 같은 순회 |
| L-42 | §1.2 `original_domain` → `xplan`(원복 코드·필드 소멸), 상태는 §1.3 XGATE_STATE 만 |
| L-43 | 누산기·분석 = `xplan_acc` 항목(ALIAS/GATE), 첫값 블록 삭제(S-23·S-27·S-28·S-36), 경계 (b) |
| L-45 | §4 (a) 전략은 로드/G1 1회 (b) K=EXEC·S=RANGE (c) KEY1/KEY2 항목 분리 (d) `pair` (e)(f) `key_type` 스트림 (g) setdomain 은 게이트 표 소유 |
| L-46 | §1.5 소유 스레드·해제 시점, `qexec_deep_copy_xasl_state` 하나(pxt:648 교체), 워커 결정 0(표 읽기 전용), S-39 힙 전환 소멸 |
| L-48 | §5 예외 표 X-1~X-6 를 도출 코드 옆에, `fpcache_claim` 삼킴 수정, 실행 경계 = 신설 코드 -1383 |
| L-49 | I2 불변식(값 타입 = 계획 도메인, KEEP 은 표에 기록), S-33 KEEP, B33 auto-param 은 K 참조로 실제 변환 |
