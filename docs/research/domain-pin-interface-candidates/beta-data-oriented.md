# 설계안 β — 데이터 지향·공통 경로 0비용 (전략 A 안의 인터페이스)

지도 #312 · 티켓 #323 · 제약: **정적 계획(GATE 슬롯 0)은 G1/G2 비용 0, 행 경로 간접 참조 0. 노드는 필드 하나를 읽고 포인터 하나를 부른다.** 슬롯 ID 로 인덱싱되는 평면 배열, 변환기는 로드 시 노드의 비팩 필드에 직접 설치, 게이트 표는 XASL_STATE 의 병렬 배열.
전략·기각·결정(D-318-01~10, D-327-01~11, D-322-01~04, P0~P7)은 재론하지 않는다. 변환기 표의 **내용**은 #325; 여기서는 seam 과 포인터 타입만.
인용 표기는 `domain-pin-exec-sites.md` 와 같다(`qx:` query_executor.c, `fe:` fetch.c, `sx:` stream_to_xasl.c, `xs:` xasl_to_stream.c, `sm:` scan_manager.c, `pxt:` px_scan_task.cpp, `pd:` parse_dbi.c, `xg:` xasl_generation.c, `vdb:` db_vdb.c, `mc:` method_callback.cpp).

핵심 그림 한 줄: **노드 안 8바이트(`original_domain` 자리) = R 부류면 변환기 함수 포인터, K/S/G 부류면 슬롯 ID.** 부류는 로드 도출이 `flags` 의 비팩 비트에 쓴다. 실행 상태(값·게이트 도메인·게이트 변환기)는 XASL_STATE 의 슬롯 ID 인덱스 병렬 배열이다.

---

## 1. 인터페이스

### 1.1 타입 — 노드 비팩 필드의 재사용 (MEM-02: 구조체 크기 불변)

```c
/* src/query/domain_plan.hpp  (server-only, PHYS-05: 클라이언트 헤더 include 금지) */

/* 계획된 변환기: (원 값, 목표 도메인) → 결과. 실패 정책은 변환기가 아니라 호출 자리(슬롯)의 속성. */
typedef int (*dpin_conv_fn) (const DB_VALUE * src, DB_VALUE * dst, const TP_DOMAIN * to);
/* 반환: NO_ERROR / ER_TP_CANT_COERCE(strict 실패) / ER_IT_DATA_OVERFLOW … — 변환기 자체는 오류를 er_set 하지 않는다 */

typedef enum { DPIN_POLICY_ERROR = 0, DPIN_POLICY_NULL = 1, DPIN_POLICY_KEEP = 2 } DPIN_POLICY;   /* X1, D-327-10 */

/* 노드의 8바이트 자리. 어느 멤버가 유효한지는 flags 의 DPIN_CLASS 비트가 말한다. */
union dpin_ref
{
  dpin_conv_fn conv;		/* R 부류: 행마다 부르는 변환기 (NULL = 변환 없음, 항등) */
  struct
  {
    int32_t slot_id;		/* K/S/G 부류: 게이트 표·값 배열 인덱스 (0-based, 트리 전체 유일) */
    int16_t policy;		/* DPIN_POLICY — K 참조 자리의 실패 정책 (X1) */
    int16_t val_pos;		/* K 부류 중 TYPE_POS_VALUE 만: 바인드 배열 인덱스(참조 → 값 대응, §3) */
  } s;
};
static_assert (sizeof (union dpin_ref) == sizeof (TP_DOMAIN *), "MEM-02");
```

노드별 자리:

| 노드 | 지워지는 필드 | 들어가는 필드 | 비고 |
|---|---|---|---|
| `regu_variable_node` | `TP_DOMAIN *original_domain` | `union dpin_ref dp` | `domain` 은 컴파일 확정값 그대로(스트림). GATE 슬롯이면 placeholder(#325) + GATE 비트 |
| `arith_list_node` | `original_domain` | `union dpin_ref dp` | 결과 도메인 변환기(R) 또는 게이트 의존 노드 슬롯 ID(G) |
| `aggregate_list_node` | `original_domain`, `original_opr_dbtype` | `dpin_conv_fn opr_conv`(8B), `int32_t slot_id`(4B) | 피연산자 행 변환기 + 누산기 도메인 슬롯(F7 G 면 ≥0, C 면 -1) |
| `analytic_list_node` | `original_domain`, `original_opr_dbtype` | 위와 같음 | |
| `qfile_tuple_value_position` | `original_domain` | `union dpin_ref dp` | `dom` 은 컴파일 확정; G 리스트 컬럼 참조면 슬롯 ID |

`flags` 비트(`regu_var.hpp`, 기존 최댓값 0x2000):

```c
const int REGU_VARIABLE_GATE_SLOT  = 0x4000;  /* 컴파일이 세팅, 스트림에 실림: 게이트 확정 슬롯 (D-318 결정 1) */
const int REGU_VARIABLE_DPIN_K     = 0x8000;  /* 로드 도출 비트 3종 — 스트림에는 절대 없음(sx 에서 assert) */
const int REGU_VARIABLE_DPIN_R     = 0x10000;
const int REGU_VARIABLE_DPIN_S     = 0x20000;
/* G(게이트 의존 노드) = GATE_SLOT 없이 dp.s.slot_id 를 갖는 arith/agg/analytic → 별도 비트 없이 "슬롯 ID ≥ 0 && !K && !S" 로 판별 */
```
`ARITH_TYPE`·`AGGREGATE_TYPE` 에는 `flags` 가 없다 → arith 는 자기 regu 껍데기(`regu->flags`)의 비트를 쓰고, agg/analytic 은 `slot_id` 부호로 판별한다(-1 = 정적).

### 1.2 타입 — 로드 도출 결과(트리당 1개, 불변, 언팩 arena 소유)

```c
struct dpin_gate_node		/* 게이트 의존 노드 목록 원소 — 생산자 우선 순서 */
{
  enum { DPIN_GN_REGU, DPIN_GN_ARITH, DPIN_GN_AGG, DPIN_GN_ANALYTIC, DPIN_GN_LIST_COL, DPIN_GN_KEY_RANGE } kind;
  void *node;			/* regu / arith / agg / analytic / xasl(list col) / KEY_RANGE */
  int32_t slot_id;		/* 이 노드가 채우는 게이트 표 항목 */
  int32_t in_slot[3];		/* 피연산자 슬롯(생산자), 없으면 -1 — G1 이 이 항목들을 먼저 읽는다 */
  int16_t opcode;		/* OPERATOR_TYPE / FUNC_CODE — 도메인 해석기 입력 */
  int16_t ctx;			/* DPIN_CTX_ARITH/COMPARE/ASSIGN/AGG/LIST/KEY … 실패 정책·격자 선택 */
};

struct dpin_plan		/* stx_map_stream_to_xasl 끝에서 1회 도출, XASL_UNPACK_INFO 가 소유·해제 */
{
  int32_t n_slots;		/* 게이트 표 길이 = K 참조 + S 자리 + G 노드 + 리스트 컬럼 G + 키 range 항목 */
  int32_t n_kref;		/* 그중 K 참조 수(TYPE_POS_VALUE·TYPE_DBVAL 참조, 슬롯 ID 0..n_kref-1 을 차지) */
  int32_t n_gate;		/* 게이트 의존 노드 수 — 정적 계획이면 0 */
  const TP_DOMAIN **bind_domain;/* [n_kref] 참조별 바인드 도메인 = 그 regu 의 domain (GATE 슬롯이면 NULL) */
  int16_t *kref_val_pos;	/* [n_kref] 슬롯 → val_pos */
  dpin_gate_node *gate;		/* [n_gate] 생산자 우선 */
  struct dpin_key_plan *key;	/* [n_key] access spec key range 계획 (§4) */
  int32_t n_key;
  const char **slot_name;	/* [n_slots] 덤프용 ("?:0", "arith@qx", "agg#2", "key[1].k1[0]") — 트레이스 켜진 빌드에서만 채움 */
};
/* XASL_UNPACK_INFO 에 `dpin_plan *plan;` 한 필드 추가(비팩, 비-hot). xasl_node 는 건드리지 않는다. */
```

불변식(로드 경계 (a)): 도출 끝에 (i) 스트림에서 온 `flags` 에 DPIN_K/R/S 비트 0, (ii) `domain` 이 `DB_TYPE_VARIABLE` 또는 `COLL_LEAVE` 인 노드는 GATE_SLOT 비트가 있거나 예외 표(§5)에 있음, (iii) 슬롯 ID 는 0..n_slots-1 유일·연속. 세 로드 경로가 같은 스트림에서 같은 순서로 걷으므로 같은 ID 를 얻는다(D-318-02).

### 1.3 타입 — 게이트 표(실행별, XASL_STATE 소유, 병렬 배열)

```c
struct dpin_gate_table
{
  int32_t n_slots;		/* == plan->n_slots; 0 이면 아래 포인터 전부 NULL, 할당 0 */
  const TP_DOMAIN **domain;	/* [n_slots] 게이트 확정 도메인(collation 포함 — 한 쌍, D-322 귀결 1). C 확정 슬롯은 노드 domain 을 복사해 둔다 → 소비자는 항상 여기만 읽는다 */
  dpin_conv_fn *conv;		/* [n_slots] G 노드·G 리스트 컬럼·키 원소가 행마다 부를 변환기(G1 이 선택) */
  DB_VALUE *value;		/* [n_kref] 변환된 K 참조 값. 소유 = 이 표를 만든 스레드. 이후 [n_kref..n_slots) 는 없음 */
  TP_DOMAIN **key_setdomain;	/* [n_key] midxkey setdomain (K 키는 G1, S 키는 range open 이 덮어씀) */
  THREAD_ENTRY *owner;		/* ALLOC-08/A64: value/key_setdomain 을 해제할 수 있는 유일한 스레드 */
};

struct xasl_state			/* query_executor.h:88 확장 */
{
  VAL_DESCR vd;			/* 그대로. vd.dbval_ptr = 호출자가 준 입력 배열(const 별칭, 절대 쓰지 않음) */
  QUERY_ID query_id;
  int qp_xasl_line;
  dpin_gate_table gate;		/* NEW */
};
```

메모리 형상: `domain`·`conv`·`value`·`key_setdomain` 은 **한 번의 `db_private_alloc`** 으로 잡고 64B 정렬(`value` 가 첫 블록: `DB_VALUE` 는 행 경로가 매번 읽는 유일한 배열). PX 워커 사본은 워커 힙에서 같은 형상으로 따로 잡는다 → 루트/워커가 같은 캐시 라인을 쓰지 않는다(false sharing 0; `domain[]` 은 `tp_domain_cache` 된 불변 객체 포인터라 공유 읽기만).

### 1.4 함수

```c
/* ---- 로드 (stream_to_xasl.c 끝, 세 호출자 공통) ---- */
int dpin_derive_plan (THREAD_ENTRY * thread_p, xasl_node * root, XASL_UNPACK_INFO * unpack);
/*  전제: 트리 언팩 완료. 후조건: 모든 노드의 dp/opr_conv/slot_id 설치, flags 부류 비트 설치, unpack->plan 채움, 경계 (a) 검사.
    오류: ER_QPROC_DOMAIN_NOT_PLANNED(§5) — 로드 실패로 취급(클론 생성 실패 → 캐시 항목 무효). 비용: O(노드 수), 클론 재사용 시 0 */
int dpin_reject_if_gated (const xasl_node * root_or_pred);   /* 필터/함수 인덱스 로드: GATE_SLOT 하나라도 있으면 오류 */

/* ---- G1 실행 게이트 (query_executor.c) ---- */
int dpin_gate_execute (THREAD_ENTRY * thread_p, xasl_node * root, xasl_state * xs);
/*  전제: xs->vd 형성 직후, aptr 실행 전, PX clone 전, sq cache 조회 전. 실행당 정확히 1회.
    하는 일(순서 고정): ① gate 배열 할당(n_slots==0 이면 아무것도 안 함, 반환) ② K 참조 루프: value[i] = conv(vd.dbval_ptr[val_pos[i]], bind_domain[i]) (실패 → policy: ERROR 는 즉시 반환, NULL 은 value[i]=NULL, KEEP 은 원 값 복제 + domain[i]=값 도메인) ③ gate 목록을 0..n_gate-1 순서로: 해석기(opcode, domain[in_slot[k]]…) → domain[slot], conv[slot] ④ 키 K range: strict-or-keep 1회 → key_setdomain[r].
    출력: xs->gate 만. 플랜 노드 쓰기 0. 오류: 변환 오류 코드 현행(-494 계열) 그대로, 위치 인자만 추가. 비용: O(n_kref + n_gate + n_key), 정적 계획 = O(n_kref) */

/* ---- G2 블록 게이트 ---- */
int dpin_gate_block (THREAD_ENTRY * thread_p, xasl_node * block, xasl_state * xs);
/*  전제: block 의 aptr 실행·precompute 뒤, qexec_start_mainblock_iterations 전. 결정 0.
    하는 일: block 이 소비하는 S 자리(aptr 리스트 컬럼·비상관 서브쿼리 결과)에 conv[slot] 을 적용해 value 없이 도메인만 맞춘다 — 실제로는 리스트 컬럼 도메인이 이미 게이트 표에 있으므로 `qdata_get_valptr_type_list` 가 그것을 읽는 것으로 충분하고, 값 변환은 S 소비 regu 의 R 변환기가 행마다 한다. 정적 계획이면 no-op(n_gate==0 조기 반환) */

/* ---- 상관·조인 키: range open ---- */
int dpin_key_open (THREAD_ENTRY * thread_p, const dpin_key_plan * kp, xasl_state * xs, int range_idx, DB_VALUE * out_key);
/*  S 키만. 계획된 (strict_conv, keep_conv) 쌍을 값에 적용, 전략 재추론 0 (L-45(a)(b)). key_setdomain[range_idx] 갱신 */

/* ---- PX 상속 ---- */
xasl_state *qexec_deep_copy_xasl_state (THREAD_ENTRY * thread_p, xasl_state * src);   /* 기존 함수 확장: vd + gate 전부 깊은 복사, owner = thread_p */
void qexec_free_xasl_state (THREAD_ENTRY * thread_p, xasl_state * xs);                 /* assert (xs->gate.owner == thread_p) */

/* ---- 행 경로 인라인 (fetch.h) ---- */
static inline const DB_VALUE *dpin_slot_value (const xasl_state * xs, const regu_variable_node * r)
{ return &xs->gate.value[r->dp.s.slot_id]; }
static inline const TP_DOMAIN *dpin_slot_domain (const xasl_state * xs, int32_t slot) { return xs->gate.domain[slot]; }
```

### 1.5 소유·수명

| 객체 | 만드는 곳 | 소유 | 해제 |
|---|---|---|---|
| `dpin_plan` + 노드 dp 필드 | `dpin_derive_plan`(로드) | `XASL_UNPACK_INFO` | `free_xasl_unpack_info` — 클론 풀 재사용 시 살아남는다 |
| `gate.*` 루트 | `dpin_gate_execute`(연결 스레드) | `xasl_state`(스택, qx:17456) | `qexec_execute_query` 종료 시 연결 스레드 |
| `gate.*` 워커 | `qexec_deep_copy_xasl_state`(워커 스레드) | 워커 `xasl_state` | 워커 `qexec_free_xasl_state`(pxq:235·px_query_executor.cpp:94) |
| `vd.dbval_ptr` | 호출자 | 호출자(qmgr 배열 또는 SA_MODE `parser->host_variables`) | 호출자 — 게이트는 읽기만 |

---

## 2. 호출 순서

### 2.1 G1 — `qexec_execute_query` qx:17456

```c
  xasl_state.vd.dbval_cnt = dbval_cnt;
  xasl_state.vd.dbval_ptr = (DB_VALUE *) dbval_ptr;      /* qx:17579 — 별칭, 절대 쓰지 않음 (SA_MODE: parser->host_variables 자체) */
  xasl_state.query_id = query_id;  … sys_datetime …
  memset (&xasl_state.gate, 0, sizeof xasl_state.gate);
  if (dpin_gate_execute (thread_p, xasl, &xasl_state) != NO_ERROR)   /* NEW: mainblock 전, aptr 전, PX 전, sq cache 전 */
    { qexec_failure_line (__LINE__, &xasl_state); goto query_error; }
  … qexec_execute_mainblock (thread_p, xasl, &xasl_state, NULL) …
  /* query_end: */ dpin_gate_clear (thread_p, &xasl_state);              /* owner 검사 뒤 value 배열 clear + free */
```
결과 캐시 키(`params.vals`)와 `copy_bind_value_to_tdes` 는 `vd.dbval_ptr` 원 값 기준 그대로(D-318-03). 서브쿼리 캐시(fe:4763)는 fetch 가 돌려준 **변환 값**으로 키를 만든다(게이트 뒤이므로 일관).

### 2.2 G2 — `qexec_execute_mainblock_internal` qx:16150

aptr 루프(qx:16538) → precompute 루프(qx:16696~16716) → **`dpin_gate_block (thread_p, xasl, xasl_state)`** → `qexec_start_mainblock_iterations`(qx:16720). 정적 계획은 첫 줄에서 반환.

### 2.3 상관·조인 키 — `scan_regu_key_to_index_key` sm:2328

K 키(`plan->key[r].cls == DPIN_K`): 값 = `gate.value[slot]`, setdomain = `gate.key_setdomain[r]` (G1 이 만듦) → `scan_dbvals_to_midxkey` 의 strict/재시도/`need_new_setdomain` 블록을 타지 않는다. S 키: `dpin_key_open` 1회. ISS·MRO 는 §4.

### 2.4 PX 상속

`px_query_executor.cpp:48`·`px_query_task.cpp:123` 는 이미 `qexec_deep_copy_xasl_state` — 확장된 함수가 gate 를 복사한다. `px_scan_task.cpp:648~672` 의 `memcpy (m_vd, m_orig_vd)` + clone 루프는 **삭제**하고 `m_xasl_state = qexec_deep_copy_xasl_state (&thread_ref, m_orig_vd->xasl_state)` 로 대체(D-318-06). 워커가 언팩한 트리(pxt:623)는 같은 `dpin_derive_plan` 을 지나 같은 슬롯 ID 를 얻는다. pxt:675 `qexec_mark_aggregate_operand_expressions` 는 로드 도출로 흡수(§9 M8).

### 2.5 행 경로 모양 — `int_col = ?` (B4)

컴파일: 슬롯 INTEGER 미러(C). 로드: rhs regu = K, `dp.s = {slot 0, KEEP, val_pos 0}`; lhs regu(TYPE_ATTR_ID INT) = R, `dp.conv = NULL`(항등). G1: `value[0] = int_strict(vd[0])`; 성공 → `domain[0] = INT`, 비교 변환기 `conv[0] = NULL`; 실패(1.5) → KEEP: `value[0] = 1.5(DOUBLE)`, `domain[0] = DOUBLE`, `conv[0] = int_to_double`(lhs 쪽 R 변환기로 설치할 수 없으므로 **비교 노드**의 슬롯에 둔다 — pred 의 `et_comp` 는 `dp` 가 없으니 rhs regu 의 슬롯을 비교가 공유).

```c
/* eval_value_rel_cmp (qe:220) 새 모양 */
  fetch_peek_dbval (…lhs…, &dbval1);   /* TYPE_ATTR_ID: 값 그대로 */
  dbval2 = dpin_slot_value (xs, rhs);   /* 한 필드(slot_id) + 배열 인덱스 */
  if (rhs->dp 의 conv 가 아니라 xs->gate.conv[slot] != NULL)  /* KEEP 인 실행에만 참 — 실행당 고정, 분기 예측 100% */
    { xs->gate.conv[slot] (dbval1, &tmp, xs->gate.domain[slot]); dbval1 = &tmp; }
  result = pr_type->cmpval (dbval1, dbval2, …);   /* tp_value_compare_with_error(do_coercion=1) 경로 제거 */
```
`TYPE_POS_VALUE` 분기(fe:4745)는 `*peek_dbval = &vd->dbval_ptr[val_pos]` → `dpin_slot_value` 로 바뀐다. `FETCH_ALL_CONST` 세팅과 fe:5225~5262 도메인 확정 블록은 사라지고 FAST_PEEK 판정(fe:5273)은 로드 도출의 R/K 비트로 대체된다.

### 2.6 행 경로 — 키 range 원소

`scan_dbvals_to_midxkey` 의 원소 루프: `val = (elem 이 K) ? &gate.value[slot] : fetch(…)`; `conv = plan->key[r].elem_conv[i]`(로드 고정, S 원소만 non-NULL); `setdomain = gate.key_setdomain[r]`. `tp_value_coerce_strict`·NUMERIC/CHAR/BIT 정확 일치 검사·`new_setdomain_built` 전부 제거(sm:2010~2150).

---

## 3. `val_pos` 다중 참조 — 참조별 K 변환기 + 참조별 값 자리

확인된 발생 경로 2곳(같은 `?` 인덱스를 가진 PT_HOST_VAR 노드가 트리에 복수 존재):
- **R1** `qo_reduce_equality_terms`(query_rewrite_term.c:448~900): `t1.i = ? AND t1.i = t2.b` → `?` 사본이 `t2.b` 자리에 치환된다(:618 `parser_copy_tree (expr)`, :862~880 `parser_copy_tree_list (arg2)` + 타입이 다르면 `pt_wrap_with_cast_op`). 사본 노드마다 `expected_domain` 이 따로 붙는다(tc:8617 은 마지막 쓰기만 남김) → regu 두 개가 같은 `val_pos`, 다른 `domain`(INT / BIGINT 또는 CAST 안 MAYBE).
- **R2** `pt_copypush_terms`(view_transform.c:4505~4506): UNION 파생 테이블에 `v.c = ?` 를 두 가지에 복사 → `int_col = ?` 와 `dbl_col = ?` 가 같은 `val_pos`.

설계: **슬롯 ID 는 참조(regu)마다, `val_pos` 는 바인드 값마다.** `plan->kref_val_pos[slot] = val_pos`(다대일), `plan->bind_domain[slot]` = 그 regu 의 도메인. G1 K 루프는 슬롯을 돈다:

```c
for (i = 0; i < plan->n_kref; i++)
  {
    const DB_VALUE *src = &xs->vd.dbval_ptr[plan->kref_val_pos[i]];       /* 공유 원 값, 불변 */
    if (plan->bind_domain[i] == NULL)  { /* GATE 슬롯: 값 그대로 복제, 도메인 = 값 도메인 + collation 병합 (C3) */ … continue; }
    err = plan->kref_conv[i] (src, &xs->gate.value[i], plan->bind_domain[i]);   /* 참조별 변환기, 로드 고정 */
    if (err != NO_ERROR) switch (policy[i]) { case NULL: db_make_null (&value[i]); break; case KEEP: pr_clone_value (src, &value[i]); domain[i] = tp_domain_resolve_value (src); break; default: return err_with_location (i); }
  }
```
같은 `?` 의 산술 자리 NULL(파라미터 yes)은 그 참조 슬롯에만 들어가고 `vd.dbval_ptr[val_pos]` 는 불변(D-327-10). `n_kref` 는 참조 수이므로 R1/R2 로 늘어난 참조는 값 하나를 두 번 변환하는 비용만 진다(실행당 상수). "가장 좁은 공통 도메인" 은 만들지 않는다(D-318 결정 1).

`TYPE_DBVAL`(auto-param, B33)도 K 참조: `kref_val_pos = -1`, src = `regu->value.dbvalptr`(플랜 값, 읽기 전용), 목표 = `regu->domain` → "값 타입 = 계획 도메인" 불변식(L-22·L-49)이 G1 뒤 성립. 리터럴 폴딩 상수는 컴파일이 이미 목표 도메인으로 실어 K 참조가 아니다(변환기 항등이면 도출이 슬롯을 배정하지 않는다 — 정적 계획 비용 0 의 조건).

---

## 4. 인덱스 키 변환 계획

### 4.1 스트림: `INDX_INFO.key_type`
- `xts_process_indx_info` xs:4760: `func_idx_col_id` 다음(offset 27 줄)에 `ptr = OR_PACK_DOMAIN_OBJECT_TO_OID (ptr, indx_info->key_type, 0, 0)`; `xts_sizeof_indx_info` 에 `or_packed_domain_size`. `stx_build_indx_info` sx:4784 같은 자리에 `or_unpack_domain (ptr, &indx_info->key_type, NULL)`. access spec 레이아웃(디스크 없음). 컴파일 측 `pt_to_index_info`(xg) 가 `index_entryp->key_type` 을 그대로 싣는다(L-45(f); 카탈로그 재조회 0).
- 단일 컬럼 인덱스: `key_type` = 컬럼 도메인. 다중 컬럼: `key_type->setdomain` 사슬(is_desc 포함).

### 4.2 로드 도출: `dpin_key_plan`
```c
struct dpin_key_plan
{
  KEY_RANGE *range;		/* 대상 */
  int32_t setdomain_slot;	/* gate.key_setdomain 인덱스 */
  int8_t cls;			/* DPIN_K(전 원소 K) / DPIN_S(원소 하나라도 S) */
  int8_t ncols1, ncols2;	/* key1 / key2 원소 수 — 분리(L-45(c)) */
  dpin_conv_fn *conv1;		/* [ncols1] 원소 strict 변환기(로드 고정: (원소 regu domain, key_type 원소) → 함수) */
  dpin_conv_fn *conv2;		/* [ncols2] key2 별도 */
  dpin_conv_fn *cmp1, *cmp2;	/* strict 실패(keep) 시 btree 비교에 쓸 (값 도메인 → 비교 도메인) 변환기 — 두 결과가 다 계획됨 */
  const TP_DOMAIN *asc_key_type;/* key_type 의 오름차순 사본(is_desc 전부 0) — ISS 첫 컬럼·MRO sort_col_dom 시딩 (L-44·L-45(e)) */
  struct { int32_t lo_slot, hi_slot; } iss_fetch;	/* ISS 내림차순 bound 이동용 계획 쌍 (L-45(d)); 미사용 -1 */
};
```
- **K 키**: G1 ④ 가 원소마다 `conv1[i]` 를 `gate.value[elem_slot]` 에 적용(strict). 성공 → 원소 도메인 = 인덱스, 실패 → 값 유지 + 그 원소만 값 도메인(B30·B31 strict-or-keep 현행) → `gate.key_setdomain[r]` 를 1회 조립. 이후 `scan_get_index_oidset` 의 range 마다 값 변환 0.
- **S 키**(상관·조인·skip-scan): range open 마다 `dpin_key_open` — 같은 `conv1/cmp1` 쌍을 값에 적용, 결과에 따라 setdomain 갱신. "어느 변환기를 쓸지" 는 로드 때 정해졌고 range open 은 성공/실패 두 갈래만 있다(L-45(a)(b): 전략 재추론 0).
- **ISS**: `scan_get_next_iss_value` sm:405 의 `last_key` → key1 TYPE_DBVAL 교체 + 도메인 ← 값(S-31) 은 `asc_key_type->setdomain` 첫 원소로 고정; 내림차순에서 유일 bound 를 key1→key2 로 옮길 때 `iss_fetch.{lo,hi}_slot` 의 계획된 원소를 쓴다(`iss_range.key1` 만 스트림에 있고 key2 는 NULL 인 xs:4814 계약 유지).
- **MRO**: `btree_range_opt_check_add_index_key` bt:22282 의 `tp_Null_domain` 시딩(S-32) → `plan->key[r].asc_key_type` 로 스캔 준비 시 1회.
- `INDX_SCAN_ID.prebuilt_midxkey_domains`(sm.h:291·345)·`need_new_setdomain`(sm:1889)·sm:3745 할당·sm:5418 해제 삭제 → L-45(g) 누수는 필드 소멸로 해소.

---

## 5. 검증 경계

### 5.1 경계 (a) — 로드 (`dpin_derive_plan` 끝, `stream_to_xasl.c`)

거부 조건: `TP_DOMAIN_TYPE (d) == DB_TYPE_VARIABLE || COLLATION_FLAG != NORMAL` 이면서 GATE_SLOT 비트도 없고 아래 예외 표에도 없는 노드. 예외 표는 도출 코드 바로 위에 `static const struct { REGU_DATATYPE type; int flag_mask; const char *why; } dpin_load_exceptions[]` 로 둔다:

| 예외 | 왜 설계상 VARIABLE 인가 | 근거 |
|---|---|---|
| `TYPE_REGU_VAR_LIST` 포장 regu(CUME_DIST/PERCENT_RANK 인자 묶음) | 값이 없는 구조 노드 | L-48(a) |
| 분석 윈도우 정렬 키 regu(`REGU_VARIABLE_ANALYTIC_WINDOW`) | 정렬 키는 리스트 type_list 의 컬럼 도메인을 쓴다(pos_descr 가 정본) | L-48(a) |
| 집합 연산(UNION/DIFF/INTERSECT) 결과 outptr 의 상대 가지 컬럼 | 도메인은 `qfile_unify_types` 대신 컴파일 공통 타입(U2)이 실리므로 원칙상 0건 — 남는 건 C8 G 리스트 컬럼(GATE 비트 있음) | 검증용 항목: 0건 목표 |
| `TYPE_ORDERBY_NUM`/`TYPE_INST_NUM` 등 값 없는 regu | 도메인 무의미 | — |

필터 predicate·함수 인덱스: `stx_map_stream_to_filter_pred` sx:291 / `stx_map_stream_to_func_pred` sx:349 끝에서 `dpin_reject_if_gated` — GATE_SLOT 하나라도 있으면 `ER_QPROC_DOMAIN_NOT_PLANNED`. `fpcache_claim`(filter_pred_cache.c:355~416)이 로드 오류에 NO_ERROR + NULL 을 돌려주는 삼킴(S-42)은 오류 그대로 반환하도록 고친다.

### 5.2 경계 (b) — 실행

```c
#define ER_QPROC_DOMAIN_NOT_PLANNED                 -1382     /* error_code.h; ER_LAST_ERROR → -1383 */
/* cubrid.msg $set 5 */
1382 Query domain was not fixed by the plan or the gate (query "%1$s", plan slot %2$d, node %3$s, domain %4$s).
```
인자: `query_alias`(xasl_node) / 슬롯 ID 또는 -1 / `plan->slot_name[slot]`(없으면 kind 문자열) / `pr_type_name`. optdebug 는 같은 자리에 `assert (false)` 를 먼저 둔다(`#define DPIN_BOUNDARY(cond, xs, slot, node) do { if (!(cond)) { assert (false); er_set (…ER_QPROC_DOMAIN_NOT_PLANNED…); return ER_QPROC_DOMAIN_NOT_PLANNED; } } while (0)`).

재컴파일 트리거 **제외** 확인: vdb:2277 목록(`XASLNODE_RECOMPILE_REQUESTED`/`INVALID_XASLNODE`/`RESULT_CACHE_INVALID`), vdb:1102·2174·2218·2314·2390·2537, cas_execute.c:1188·1502·2376, cas_common_execute.c:364, method_callback.cpp:276, trigger_manager.c:4971 — 어느 목록에도 새 코드를 넣지 않는다. 클라이언트는 이 코드를 받으면 사용자에게 그대로 올린다(경계 위반 = 버그 노출, D-318-04).

경계 위치(도달 0 assert): `qdata_get_valptr_type_list`(리스트 컬럼 VARIABLE), `fetch_peek_dbval_slow` VARIABLE 분기 자리, `btree_compare_key` bt:22095 폴백, `eval_value_rel_cmp` coercion 자리, `qexec_resolve_domains_for_aggregation` 첫값 대기 자리, `scan_dbvals_to_midxkey` 재시도 자리 — 각각 마이크로벤치 카운터(#324)의 0 목표와 짝.

---

## 6. 클라이언트 경로

- **`pt_set_host_variables` pd:3072**: 루프 본문을 `pr_clear_value (hv); pr_clone_value (val, hv);` + 참조 OID 검사로 축소. `tp_value_cast_preserve_domain` 분기·CHAR/VARCHAR 원 값 유지 분기 삭제(후자의 의미는 게이트 CHAR 변환기 B7 로, D-327-01). `MSGCAT_SEMANTIC_CANT_COERCE_TO` 오류는 이 지점에서 사라지고 서버 G1 의 -494 계열이 된다(F-5: 시점 이동, 코드 동일).
- **`host_var_expected_domains[]` 남는 소비자**(전수): db_vdb.c:2954·3116(prepare 정보 pack/unpack — prepare 응답 파라미터 메타), db_query.c:461·546·639(직렬화), db_vdb.c:3209(바인드 피크 재계획 입력 — 값을 비용 추정에만, D-318-05), db_vdb.c:3347~3449(PL 부모 파서 공유), mc:657(PL 보고 S6), semantic_check.c:13412(`SET @v = ?` 대입 도메인 — 컴파일 결정, 유지), tc:8617 쓰기, nr:11901 확장, parse_tree.c:1268·vdb:4324 해제. **삭제되는 소비자**: pd:3110 하나.
- **`pt_make_regu_hostvar` xg:6391**: 2단계(xg:6418~6445 `parser->flag.set_host_var == 1 || typ != DB_TYPE_NULL` 블록) 삭제; 4단계의 `else if (typ != exptyp …) tp_value_cast (val, val, regu->domain)`(xg:6493~6500) 삭제(클라이언트 값 캐스트). 미바인드 `db_value_domain_init` 프리셋(xg:6484)은 typed NULL 의미라 유지. 순서 = data_type → expected_domain → type_enum, 값 무관 → 같은 sha1 항목이 어떤 바인드 타입에서도 같은 슬롯 도메인(L-49).
- **카운트 불변식(L-30)**: `assert (parser->host_var_count + parser->auto_param_count == xasl->dbval_cnt)` 를 `pt_to_xasl` 끝과 `qexec_execute_query` 입구(`dbval_cnt == xasl->dbval_cnt`)에; `plan->kref_val_pos[i] < vd.dbval_cnt` 는 로드 경계 (a) 에.
- **결과 컬럼 메타(L-31)**: prepare 응답은 컴파일 도메인(현행 경로). 게이트 확정 결과 컬럼(S1·U3·F7 `SELECT ?`, `? UNION ?`, `sum(?)`)은 컴파일이 outptr 도메인을 placeholder 로 두고 `include_column_info`(cas_execute.c:1292~1305·1637·1834)가 실행 응답에서 리스트 type_list(= 게이트 표 도메인)를 다시 보낸다 — 드라이버 무변경. 미실행 문장(S2)은 후속.
- **PL/CSQL 선언 타입(S6)**: 방향 역전 없이 **prepare 요청**에 실린다. mc:608 prepare 콜백 요청에 `n_param_types` + `or_pack_domain` 배열(선언 타입; 미지정은 DB_TYPE_NULL)을 추가하고, `db_compile_statement` 전에 `pt_set_host_var_declared_domains (parser, n, domains)` 가 `host_var_expected_domains[i]` 를 **선점**(파서는 이미 채워진 슬롯을 형제로 취급 → P1 미러 입력). NULL 바인드는 선언 도메인의 typed NULL(L-16). mc:650~675 의 보고 경로는 그대로(이제 선언 타입을 되돌려 준다).

---

## 7. SHOW PLAN / trace 출력

- **서버 트레이스**(`SET TRACE ON` → `SHOW TRACE`, `qdump_print_stats_json` query_dump.c:3175): xasl 노드마다 `"dpin": { "slots": n_slots, "krefs": n_kref, "gate": n_gate, "entries": [ {"id":0, "name":"?:0", "class":"K", "bind":"INTEGER", "policy":"keep", "resolved":"DOUBLE", "conv":"int_to_double"} … ] }`. `resolved`/`conv` 는 실행 뒤 게이트 표에서(실행 상태가 남아 있는 트레이스 수집 시점에 채움). 텍스트 트레이스(`QUERY_TRACE_TEXT`)는 같은 내용을 `plan slots: 3 (K 2, gate 1)` 한 줄 + 항목 줄.
- **디버그 덤프** `qdump_print_xasl`(CUBRID_DEBUG): regu 인쇄에 `dp=K#0`, `dp=R:int_to_double`, `dp=S#4` 를 덧붙인다. 변환기 이름은 #325 표의 `const char *name` 열에서(함수 포인터 → 이름 역조회는 표 순회, 덤프 전용).
- 클라이언트 `SHOW PLAN` 텍스트(`?:0` 표기)는 불변(§7 불변 목표 `cbrd_25374`).

---

## 8. 도메인 해석기 seam

```c
/* src/query/domain_resolver.hpp — server-only (SERVER_MODE || SA_MODE), object/ 로 내려가지 않음 (PHYS-05) */
typedef enum { DPIN_CTX_ARITH, DPIN_CTX_COMPARE, DPIN_CTX_ASSIGN, DPIN_CTX_AGG, DPIN_CTX_ANALYTIC, DPIN_CTX_LIST, DPIN_CTX_KEY, DPIN_CTX_FUNC } DPIN_CTX;

/* G 행 격자: (연산자, 피연산자 도메인들) → (결과 도메인, 피연산자별 변환기). 현행 서버 값 격자(#321 §2)를 그대로 옮긴 순수 함수. */
int dpin_resolve (int opcode, DPIN_CTX ctx, int nargs, const TP_DOMAIN * const args[3],
                  const TP_DOMAIN ** result, dpin_conv_fn conv[3]);
/* 변환기 조회: (원 도메인, 목표 도메인, ctx) → 함수 포인터. 항등이면 NULL. 없으면 ER_TP_CANT_COERCE. */
dpin_conv_fn dpin_converter (const TP_DOMAIN * from, const TP_DOMAIN * to, DPIN_CTX ctx);
/* 값 collation 병합 (C3): LANG_RT_COMMON_COLL 그대로 */
int dpin_merge_collation (const TP_DOMAIN * a, const TP_DOMAIN * b, int *coll_out);
```
호출자 둘: `dpin_derive_plan`(R 변환기·키 원소 변환기 — 도메인이 전부 C 확정인 자리)과 `dpin_gate_execute`(G 노드 — 게이트 표 도메인을 인자로). 한 그리드, 두 시점. #325 는 `dpin_converter` 의 표(원 타입 × 목표 타입 × ctx → 함수, 실패 정책 열)와 `dpin_resolve` 의 케이스 본문을 채운다; 이 인터페이스는 바뀌지 않는다. 파서 C 격자(`pt_infer_common_type`)는 클라이언트에 그대로 — 두 그리드 각 한 벌(D-318-07).

---

## 9. 삭제 목록과 테스트 표면

| 축 | 지점 | 도달 불가로 만드는 인터페이스 요소 |
|---|---|---|
| CP | S-03 S-11 S-13 S-14 S-15 S-16 S-17 S-18 S-19 S-20 S-21 S-22 S-24 S-25 S-29 S-37 | 노드 `domain` 확정(VARIABLE 0) + G 리스트 컬럼은 `gate.domain[pos_descr.dp.slot]` — 조건식 자체 삭제, 자리에 `DPIN_BOUNDARY` |
| CP+G1 | S-01 S-02 S-04 S-05 S-06 S-23 S-26 S-27 S-28 S-36 | arith/agg/analytic 의 `dp`/`slot_id` — 도메인은 노드 또는 `gate.domain[slot]`, 첫값 대기·시도 캐스트·두 값 공통 타입 추론(S-04) 삭제; 다중 행 VALUES(S-06) 는 G1 이 열마다 병합(C9) |
| G1 | S-07 S-09 S-10 S-39 S-40 S-41 | K 참조 값 = `gate.value[slot]`(제자리 coerce 0, 힙 전환 0); 세션변수 읽기·TO_CHAR 포맷·PL 인자는 슬롯(S7) |
| LD | S-38(원복 5곳 + sx 6곳 + sp 3곳), M8 `FETCH_ALL_CONST`/`FAST_PEEK`/`AGG_OPERAND` 재도출·클리어(qx:1519~1536, pxt:675) | `original_domain`/`original_opr_dbtype` 필드 소멸(union 이 자리를 차지), 부류 비트는 로드 1회 |
| G1+G2 | S-12 S-30 S-31 S-32 S-34 S-35 | `dpin_key_plan` + `gate.key_setdomain`; PX 는 `qexec_deep_copy_xasl_state` 만(역전파 코드 삭제) |
| KEEP | S-08 S-33, S-10/S-12 의 함수 자체 | 게이트 뒤 결정적; 경계 assert 자리 |
| 경계 | S-42(fpcache 삼킴 수정 + 거부), S-43(#320) | `dpin_reject_if_gated` |
| collation | #314 §4 26곳 | `COLL_LEAVE` 0(D-322-01) → 쌍 조건의 두 축이 함께 삭제; `qfile_unify_types` -1509 분기·`qexec_end_one_iteration` 플래그 분기 포함 |
| X | F10 | 유지(경계 예외로 등록) |

**테스트 표면 = 인터페이스 그대로**: (1) `dpin_derive_plan` 단위 — 스트림 → 슬롯 ID·부류·변환기·gate 목록이 결정적인가(세 로드 경로 동치 = 같은 스트림을 세 번 로드해 `plan` 을 memcmp), 경계 (a) 예외 표 밖 VARIABLE 거부; (2) `dpin_gate_execute` 단위 — (계획, 값 배열) → 게이트 표 (규칙표 §2~§4 행 = 케이스), 실패 정책 3종, 다중 참조 R1/R2 케이스; (3) `dpin_resolve`/`dpin_converter` 표 단위 — #321 §5 24행 불일치를 그대로 재현(P0); (4) 카운터 8종(#324) 0 = 경계 도달 0; (5) CTP sql 전수·medium(§7 답안 변경 행만 diff 허용).

---

## 10. 트레이드오프

- **레버리지가 높은 곳**: 행 경로. R 노드는 `dp.conv` 한 포인터, K 노드는 `value[slot]` 한 인덱스 — 오늘의 `tp_value_compare_with_error` rank 판정·`tp_value_cast_internal` switch·`DB_VALUE_DOMAIN_TYPE` 2단 디스패치(BR-06/A61)가 전부 사라지고 분기는 실행당 고정된 값(`conv != NULL`)뿐이라 예측기가 100% 맞춘다(BR-04). 정적 계획은 G1 = K 루프 n_kref 회, gate 할당 0, G2 = 조기 반환 — "정적이면 0 순회" 를 문자 그대로 만족. `original_domain` 원복(A59/A62)이 사라져 실행 종료 비용도 준다.
- **레버리지가 얇은 곳**: 게이트 표 병렬 배열은 "슬롯 ID → 4개 배열" 이라 항목 하나를 읽는 코드가 흩어진다(도메인은 `domain[]`, 변환기는 `conv[]`); 구조체 배열(AoS)보다 캐시 지역성은 좋지만 덤프·디버깅 시 한 항목의 전체 상태를 보려면 네 배열을 모아야 한다 — §7 의 덤프가 이를 갚는다.
- **삭제 테스트**: `dpin_plan`/`gate` 를 지우면 43 지점의 늦은 바인딩이 그대로 되살아나야 한다 → 모듈이 밥값을 한다. 반대로 `dpin_gate_block`(G2)는 지워도 리스트 컬럼 도메인이 게이트 표에 있으면 소비자가 그냥 읽을 수 있어 **거의 pass-through** — 이 안에서 G2 는 "S 부류 키 range open" 과 "카운터 지점" 을 빼면 얕다. 정직하게 적는다: G2 의 실체는 `dpin_key_open` 과 리스트 컬럼 도메인 읽기이지 별도 패스가 아니다.
- **어려워지는 것**: (1) 함수 포인터는 인라인이 안 된다 — 항등 변환(가장 흔한 경우)은 `NULL` 로 표현해 호출 자체를 건너뛰므로 실제 비용은 non-identity 변환에만 생기고, 그 자리는 오늘도 switch 를 탄다. (2) `flags` 의 비팩 비트 3개가 스트림 비트와 한 정수를 공유 — 로드 경계에서 "스트림에 비팩 비트 0" 을 assert 하고 `xts_process_regu_variable` 에서 마스킹해 팩. (3) union 은 판별자를 노드 밖(flags/부호)에 두므로 잘못 읽으면 함수 포인터를 정수로 읽는다 — optdebug 에서 `dp` 접근 매크로가 부류 비트를 assert. (4) 노드당 메모리는 0 증가, 트리당 `dpin_plan` 배열이 언팩 arena 에 O(슬롯 수) 추가(클론 풀에 상주). (5) agg/analytic 은 8B+4B 로 자리가 넉넉해 R 변환기와 슬롯 ID 를 동시에 갖지만, regu/arith 는 8B 하나라 "R 변환기도 있고 G 슬롯도 있는 노드" 를 표현할 수 없다 — 그런 노드는 정의상 없다(G 노드의 변환기는 G1 이 `gate.conv[slot]` 에 둔다).

---

## 11. 렛저 대응표

| L | 이 안에서 |
|---|---|
| L-30 | §6 카운트 불변식 3곳(`pt_to_xasl`·`qexec_execute_query`·로드 경계); 클라이언트 캐스트 삭제로 OOB 경로 자체 소멸 |
| L-40 | §1.2 `dpin_plan` 은 스트림 밖(언팩 arena), 세 로드 경로가 `stx_map_stream_to_xasl` 끝 한 곳에서 도출; 필터/함수 인덱스는 §5.1 거부 |
| L-41 | §1.2 gate 목록에 `DPIN_GN_LIST_COL`·agg·analytic·pos_descr 포함(파생 소비자), G1 ③ 생산자 우선; MERGE/CTE 하위는 aptr 순서로 슬롯 ID 가 먼저 |
| L-42 | §1.5 플랜 쓰기 0 — 노드 `domain` 불변, 실행별 답은 `gate.domain[]`; `original_domain` 필드 소멸 |
| L-43 | §1.1 agg/analytic `opr_conv` + `slot_id`; 누산기 도메인은 G1 이 `gate.domain[slot]` 에, 첫값 대기 삭제(S-23·S-27·S-28) |
| L-45 | §4 (a) 로드 고정 변환기 쌍 (b) K=G1/S=range open (c) conv1/conv2 분리 (d) iss_fetch 쌍 (e)(f) `asc_key_type`←`INDX_INFO.key_type` (g) `prebuilt_midxkey_domains` 소멸 |
| L-46 | §1.3 `gate.owner` + 워커 사본은 워커 힙(§2.4), 값 제자리 coerce 0(S-39), 역전파 0(S-35); 64B 정렬 블록으로 false sharing 0 |
| L-48 | §5.1 예외 표를 도출 코드 옆 정적 배열로, fpcache 삼킴 수정; §5.2 새 코드 + 재컴파일 트리거 제외 목록 |
| L-49 | §3 auto-param K 참조 → "값 타입 = 계획 도메인" 불변식; §6 `pt_make_regu_hostvar` 2단계 삭제로 플랜이 바인드 타입에 독립 |
