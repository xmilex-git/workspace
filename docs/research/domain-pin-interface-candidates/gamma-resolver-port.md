# 설계안 γ — 포트·어댑터: 도메인 해석기 포트 하나를 seam 으로 (design-it-twice, #323)

지도 xmilex-git/workspace#312 · 티켓 #323 · 전략 A 고정(D-318-01) · 제약: **"서버 전용 도메인 해석기 모듈의 해석 포트 하나가 유일한 seam 이고, 로드 도출(정적 행)과 G1(게이트 행)은 같은 포트 위의 두 어댑터다. 키 변환·collation 병합·PX 상속은 포트로 표현하되 실제 두 번째 어댑터가 있을 때만 seam 을 연다. 인터페이스가 곧 테스트 표면이다."**
어휘: `codebase-design`(모듈·인터페이스·구현·seam·어댑터·깊이·레버리지·지역성; 어댑터 하나 = 가설 seam, 둘 = 실제 seam) + CONTEXT.md(변환 계획·서버 게이트·게이트 표·로드 도출·G1/G2·게이트 확정 슬롯·게이트 의존 노드·계획된 변환기·실패 정책·피연산자 부류 K/R/S). 인용 표기는 `domain-pin-exec-sites.md` 와 같다.

## 0. 한 장 요약

- 새 모듈 **`query/domain_resolver`**(서버 전용, 헤더 `domain_resolver.hpp` + 구현 `.cpp`). 인터페이스는 함수 하나 `dres_resolve()` 와 값 객체 3개(`DRES_CTX`, `DRES_OPERAND`, `DRES_ANSWER`). 규칙표 §2~§4 G 행과 §6 C3/C9/C10 병합 규칙(현행 서버 값 격자 = `tp_infer_common_domain`·`pt_common_type` 서버판·`LANG_RT_COMMON_COLL`)이 전부 이 함수 뒤에 숨는다.
- **두 어댑터, 한 포트**: 로드 도출 어댑터 `dplan_derive()`(`stx_map_stream_to_xasl` 끝, 정적 R 행 — 피연산자 도메인만 넣고 값 도메인은 NULL)와 실행 게이트 어댑터 `dgate_run_g1()`(`qexec_execute_query`, G 행 — 값 도메인을 넣는다). 두 어댑터는 같은 `dres_resolve()` 를 부르므로 "정적이면 컴파일 격자, 게이트면 값 격자" 두 그리드가 서버 안에서는 **한 코드**다(P6). 파서 그리드는 클라이언트에 그대로(P0).
- 그 밖의 포트: 키 변환(`dkey_*`), PX 상속(`qexec_deep_copy_xasl_state` 확장 — 어댑터 하나뿐이라 seam 을 열지 않고 함수 하나로 둔다), collation 병합(해석 포트의 답 필드 — 별도 포트 없음). 테스트 fake 어댑터는 **호출자 쪽**(어댑터의 입력을 만드는 트리 빌더)에만 있고 해석기 자체는 fake 하지 않는다 — 해석기가 곧 테스트 대상이기 때문.

## 1. 인터페이스

### 1.1 해석 포트 (`src/query/domain_resolver.hpp`)

```cpp
// 서버 전용. 클라이언트(parser/, compat/, broker/)는 이 헤더를 포함하지 않는다 (PHYS-05).
namespace cubquery::dres {

  enum class ctx : std::uint8_t {
    ARITH,        // ARITH_TYPE opcode: T_ADD … (A8/A8''/A11/A13/A14 값 격자)
    COMPARE,      // 술어 비교 도메인 (B8·B4 손실 시 비교 도메인·B25 R·R)
    ASSIGN,       // 대입 U0 (INSERT/UPDATE/MERGE 컬럼 ← 값)
    COMMON_VALUE, // U3/U8/U10 COALESCE·CASE·UNION·VALUES 공통값 (C9 열마다)
    AGG,          // F7 누산기 (SUM/AVG/MEDIAN/GROUP_CONCAT 값 규칙 #321 §3)
    ANALYTIC,     // F7 분석 (S-27/S-28 함수별 기본 도메인)
    FUNC_ARG,     // F2/F4 값 요구 함수 인자 (오버로드 선택)
    LIST_COLUMN,  // U17/B19 리스트 컬럼 도메인 (게이트 표 → type_list)
    KEY_ELEM,     // B30/B31 strict-or-keep (키 원소; dkey 어댑터가 호출)
  };

  // 변환기 ID: (원 타입, 목표 도메인) → 고정 함수. 표 자체는 #325. 여기서는 불투명 정수.
  using converter_id = std::uint16_t;
  constexpr converter_id CONV_NONE = 0;      // 변환 없음 (같은 타입)
  constexpr converter_id CONV_GATE = 0xFFFF; // 로드 시점에는 미정 — G1 이 채운다

  enum class fail_policy : std::uint8_t { ERROR_494, NULL_IF_PRM, KEEP };  // X1 (D-327-10)

  struct operand {
    const tp_domain *dom;      // 계획 도메인 (로드 어댑터) 또는 값 도메인 (게이트 어댑터)
    DB_TYPE val_type;          // 게이트 어댑터만; 로드 어댑터는 DB_TYPE_NULL
    int coll_id;               // 문자면 collation, 아니면 -1 (C15: 비문자에 collation 없음)
    std::uint8_t coercibility; // #313 §3.1 8-레벨 (게이트에서는 값 coercibility = 슬롯 레벨)
    bool is_gate_slot;         // 이 피연산자가 게이트 확정 슬롯/게이트 의존 노드인가
  };

  struct answer {
    const tp_domain *dom;        // 결과 도메인 (캐시된 도메인, tp_domain_cache)
    int coll_id;                 // 결과 collation (-1 = 비문자)
    converter_id conv[3];        // 피연산자별 변환기 (left/right/third; 키는 [0])
    fail_policy fail[3];         // 피연산자별 실패 정책
    bool needs_gate;             // 로드 어댑터에서 "값 없이는 못 정함" (= G 행)
    int err;                     // NO_ERROR / ER_QSTR_INCOMPATIBLE_COLLATIONS(-1150) / -622 / -494 계열
  };

  // 유일한 seam. 순수 함수: 입력만으로 결정, 전역 상태·스레드 상태 없음, 할당 없음(도메인은 캐시 참조).
  // 사전조건: opcode 는 ctx 에 맞는 값(ARITH → OPERATOR_TYPE, AGG/ANALYTIC → FUNC_CODE, 그 외 0).
  // 사후조건: needs_gate == false 이면 dom != NULL 이고 conv[i] != CONV_GATE.
  //           needs_gate == true 는 로드 어댑터에서만 나온다(게이트 어댑터는 val_type 이 채워지므로 항상 false).
  // 오류: err != NO_ERROR 이면 dom == NULL. 함수는 er_set 을 부르지 않는다(호출자가 문맥 인자와 함께 보고).
  answer resolve (ctx c, int opcode, const operand *ops, int nops, const tp_domain *consumer_dom /* U0·소비자 도메인 우선, 없으면 NULL */);

  // 규칙표 §7 '현행 격자' 검증용 — 결과 도메인만 (테스트·SHOW PLAN 출력에서 사용)
  const char *ctx_name (ctx c);
}
```

**깊이**: 인터페이스 단위는 함수 1 + 값 객체 3. 뒤에 숨는 구현은 #321 §1~§3 의 산술 사전 캐스트 격자(숫자+문자→DOUBLE, 날짜+실수/문자→BIGINT), 비교 표(문자 vs 숫자→DOUBLE, rank 상위, CHAR↔VARCHAR 무변환), 집계 규칙(SUM 문자→DOUBLE, GROUP_CONCAT→VARCHAR, MEDIAN DOUBLE→DATETIME→TIME), 함수 오버로드, collation 병합 `LANG_RT_COMMON_COLL`, ENUM 변환 표(B13·A13), NUMERIC p/s 공식 — 현행 코드에서 **옮기고 원 자리는 지운다**(P6; 옮기지 않고 복제하면 그리드가 둘이 된다).

**레버리지**: 같은 함수를 로드 어댑터(정적 행, 실행당 0회)·G1 어댑터(G 행, 실행당 1회)·키 어댑터(KEY_ELEM)·단위 테스트가 부른다. 삭제 테스트: 이 모듈을 지우면 43곳(S-01~S-43)의 늦은 바인딩 결정이 되살아나야 한다 → pass-through 가 아니다.

### 1.2 로드 도출 어댑터 (`src/query/domain_plan.hpp`, 서버 전용)

로드 시 1회, `stx_map_stream_to_xasl`(sx:212) 의 반환 직전에 `dplan_derive(thread_p, *xasl_tree, unpack_info)` 를 부른다 — 세 호출자(xcache 클론 xasl_cache.c:1133 / 비캐시 query_manager.c:1219 / PX 워커 px_scan_task.cpp:623) 공통, D-318-02. `stx_map_stream_to_filter_pred`/`_func_pred` 는 부르지 않고 §5(a) 의 거부 검사만 한다.

```cpp
// 비팩 필드 재사용 (MEM-02: 구조체 크기 불변). original_domain 포인터 자리에 다음 값 객체의 포인터를 둔다.
// 해제: XASL_UNPACK_INFO 아레나(stx_alloc_struct) — 트리와 같은 수명, 클론 풀 재사용 시 재도출 0.
struct DPLAN_NODE {            // regu / arith / agg / analytic / pos_descr 에 하나씩 (필요한 노드만)
  std::int32_t slot_id;        // 게이트 표 인덱스; -1 = 정적 (게이트 표 항목 없음)
  std::uint8_t  cls;           // K / R / S (P3; 로드 시 FETCH_ALL_CONST 의 정적 판정 = A59/A62 제거)
  dres::converter_id conv[3];  // 피연산자별 계획된 변환기 (정적이면 확정, 게이트 의존이면 CONV_GATE)
  dres::fail_policy fail[3];
  std::int32_t val_pos;        // TYPE_POS_VALUE 만; -1 그 외
  std::int32_t ref_ord;        // 같은 val_pos 를 참조하는 regu 들의 순번 (0 = 첫 참조) — §3
};
// regu_variable_node::original_domain      → (DPLAN_NODE *) 로 재해석하는 접근자 dplan_of(regu)
// arith_list_node::original_domain          → 동일
// aggregate_list_node::original_domain / original_opr_dbtype → DPLAN_NODE * / (미사용, 0)
// analytic_list_node::original_domain / original_opr_dbtype  → 동일
// qfile_tuple_value_position::original_domain → 동일
// 접근자는 domain_plan.hpp 의 inline 함수 — 필드 이름 자체는 이 PR 에서 dplan 로 개명 (원복 코드 S-38 삭제와 한 커밋).

const int REGU_VARIABLE_GATE_RESOLVED = 0x4000;  // regu->flags 새 비트 (스트림 레이아웃 불변). 컴파일이 세팅.
                                                  // arith/agg/analytic 은 자기 regu(결과 regu)의 비트로 표현 — agg 는 operands 첫 regu 의 비트.

struct DPLAN {                 // xasl_node 루트 하나에 하나 — xasl_node 에 비팩 필드 `dplan` 추가 (xasl_node 헤더는 디스크 포맷 아님)
  int n_slots;                 // 게이트 표 길이 (= slot_id 개수)
  int n_val_pos;               // 바인드 배열 길이 (= xasl->dbval_cnt)
  DPLAN_SLOT *slots;           // slot_id → 슬롯 기술 (아래)
  int n_gate_nodes;            // 게이트 의존 노드 목록 길이 (정적 계획이면 0 → G1 순회 0)
  DPLAN_GATE_NODE *gate_nodes; // 생산자 우선 순서
  DPLAN_KEY *keys;  int n_keys;// §4 키 계획
};
struct DPLAN_SLOT {            // 게이트 표 항목의 "정적 반쪽"
  dres::ctx  c;  int opcode;   // 이 슬롯을 만든 문맥 (regu 슬롯이면 ctx 없음 = 값 그대로)
  std::int32_t val_pos;        // K 슬롯: 바인드 인덱스, -1 = 파생(산술 결과·리스트 컬럼·누산기)
  std::int32_t ref_ord;        // §3
  const tp_domain *planned;    // 컴파일이 실은 도메인 (GATE 비트면 placeholder — #325 가 값을 정함)
  void *node; std::uint8_t node_kind; // 소유 노드 (regu/arith/agg/analytic/pos) — SHOW PLAN 용
};
struct DPLAN_GATE_NODE {       // 게이트 의존 노드: 안쪽 → 바깥, aptr → mainblock 순 (생산자 우선)
  std::int32_t slot_id;        // 이 노드의 결과 슬롯
  std::int32_t in_slot[3];     // 피연산자 슬롯 (-1 = 정적 피연산자, 그 도메인은 planned 에서)
  dres::ctx c; int opcode; const tp_domain *consumer_dom;
};

int dplan_derive (THREAD_ENTRY *thread_p, xasl_node *root, XASL_UNPACK_INFO *arena);   // 로드 어댑터
```

**슬롯 ID 부여**: 트리 순회 순서 고정 — `aptr_list`(재귀) → `dptr_list` → 노드 자신의 spec_list(키 regu 포함) → pred/rest → outptr_list → agg/analytic → orderby/groupby pos_descr → `scan_ptr`/`next` — 각 노드에서 regu 는 leftptr→rightptr→thirdptr 후위(안쪽이 먼저). 세 로드 경로가 같은 스트림을 같은 순서로 걷으므로 ID 가 같다(워커 unpack 트리의 slot_id == 루트 slot_id — G-06 상속 조건). `val_pos` ≠ slot_id: 한 val_pos 에 참조 regu 수만큼 슬롯(§3).

**부류 판정(K/R/S)**: `TYPE_POS_VALUE`/`TYPE_DBVAL`/상수 부분트리(모든 잎이 K) = K; `TYPE_ATTR_ID`·`TYPE_POSITION`(자기 블록) 하위 = R; 상관 `TYPE_CONSTANT`·외부 `TYPE_POSITION`·`REGU_VARIABLE_CORRELATED`·aptr 결과 = S. `T_EVALUATE_VARIABLE`(S-07)·`T_LAST_INSERT_ID` 는 K 슬롯(세션 값은 G1 이 읽어 슬롯에 넣는다, L-32) — 현행 `FETCH_NOT_CONST` 런타임 마킹은 사라진다.

### 1.3 실행 게이트 어댑터 (`src/query/domain_gate.hpp`, 서버 전용)

```cpp
struct DGATE_ENTRY {           // 게이트 표 항목 = 슬롯 ID 당 1개, XASL_STATE 소유
  const tp_domain *dom;        // 확정 도메인 (정적 슬롯은 planned 복사 — 표는 항상 완전)
  int coll_id;                 // (도메인, collation) 한 쌍 (D-322 귀결 1)
  dres::converter_id conv[3];  // G1 이 채운 변환기 (정적이면 DPLAN_NODE 값 복사)
  dres::fail_policy fail[3];
  DB_VALUE *val;               // K 슬롯의 변환된 값 (값 배열 xasl_state->gate_vals 안의 원소); 파생 슬롯은 NULL
};
struct DGATE {                 // XASL_STATE 확장 (query_executor.h:88 xasl_state 에 `DGATE gate;` 추가)
  DGATE_ENTRY *entries; int n; // dplan->n_slots
  DB_VALUE *vals;    int n_vals;   // K 슬롯 값 배열 — 슬롯 수만큼 (참조별 값 자리, D-327-10)
  THREAD_ENTRY *owner;         // 만든 스레드 (ALLOC-08/A64): 해제는 owner 만, 워커는 자기 사본을 자기가
  bool is_copy;                // PX 사본 표시
};
// vd.dbval_ptr 는 게이트 뒤에도 "원 바인드 값" 을 가리킨 채 const 로 남는다 (D-318-03, SA_MODE 별칭 M4).
// TYPE_POS_VALUE fetch 는 vd->dbval_ptr + val_pos 가 아니라 gate.entries[dplan_of(regu)->slot_id].val 을 돌려준다 (fe:4757 교체).

int  dgate_run_g1  (THREAD_ENTRY *thread_p, xasl_node *root, XASL_STATE *st);            // 실행당 1회 (결정 지점)
int  dgate_run_g2  (THREAD_ENTRY *thread_p, xasl_node *block, XASL_STATE *st);           // 블록당 1회 (변환기 적용만)
int  dgate_apply   (THREAD_ENTRY *thread_p, const DGATE_ENTRY *e, int opnd, const DB_VALUE *in, DB_VALUE *out); // 변환기 1회 호출 (#325 표 디스패치)
void dgate_free    (THREAD_ENTRY *thread_p, DGATE *g);                                    // owner 만
xasl_state *qexec_deep_copy_xasl_state (THREAD_ENTRY *, xasl_state *);   // 기존 함수 확장: vd + gate(entries·vals 깊은 복사, owner = 워커, is_copy = true)
```

**G1 이 하는 일(순서 고정)**: ① `vals` 할당 ② K 슬롯: `val_pos` 값을 `planned` 도메인으로 변환(`dgate_apply`, 실패 정책 적용; 다중 참조는 슬롯마다 따로 — 원 값 불변) ③ GATE 비트 슬롯: `dres::resolve(ctx=none)` 대신 값 도메인 그대로 + collation = 값 collation → entry ④ `gate_nodes` 를 순서대로 `dres::resolve(c, opcode, ops←in_slot entries, consumer_dom)` → entry(dom, coll, conv, fail) — 리스트 컬럼·누산기·정렬 키·비교 도메인 슬롯이 여기서 채워진다 ⑤ 정적 슬롯 entry 는 DPLAN 값 복사(표를 완전하게 — 소비자는 표만 본다, 분기 0) ⑥ 세션 변수 K 슬롯은 `session_get_variable` 로 값을 읽어 ②와 같이 처리. 정적 계획(n_gate_nodes==0, GATE 슬롯 0)이면 ③④ 는 빈 배열 순회.

**소유·해제**: `vals`·`entries` 는 `qexec_execute_query` 스택의 `xasl_state` 에 붙고 같은 함수 끝에서 `dgate_free` — 만든 스레드 = 연결 스레드. PX: `qexec_deep_copy_xasl_state` 하나(pxt:648 의 `memcpy(m_vd, m_orig_vd)` + clone 루프는 이 함수 호출로 대체, D-318-06) → 워커 사본은 워커 힙, `qexec_free_xasl_state` 가 `dgate_free` 를 포함. 워커는 결정 0(S-34/S-35 삭제): `dgate_run_g1` 은 `is_copy` 면 assert 로 거부.

### 1.4 헤더·레벨화 (PHYS-01/PHYS-05, insulation)

| 헤더 | 포함하는 것 | 포함해도 되는 곳 |
|---|---|---|
| `query/domain_resolver.hpp` | `dbtype_def.h`, `object_domain.h`(tp_domain 전방선언만), `xasl.h` 의 OPERATOR_TYPE/FUNC_CODE enum 헤더(`regu_var.hpp` 아님) | `query/*.c(pp)`, `storage/btree.c`(KEY_ELEM 어댑터), 단위 테스트. **`parser/`·`compat/`·`broker/`·`method/` 금지** — 파서 그리드와 서버 그리드는 각 한 벌(P0·P6). |
| `query/domain_plan.hpp` | `domain_resolver.hpp`, `regu_var.hpp`(접근자 inline) | `stream_to_xasl.c`, `query_executor.c`, `fetch.c`, `scan_manager.c`, `query_dump.c`, `list_file.c` |
| `query/domain_gate.hpp` | `domain_plan.hpp`, `query_executor.h`(XASL_STATE) | `query_executor.c`, `fetch.c`, `scan_manager.c`, `query_evaluator.c`, `query_aggregate.cpp`, `query_analytic.cpp`, `px_*` |

순환 금지: `domain_resolver.hpp` 는 `query_executor.h`·`scan_manager.h` 를 포함하지 않는다(레벨 1). `domain_gate.hpp` 만 XASL_STATE 를 안다(레벨 3). 컴파일 시간: 해석기 헤더는 enum·POD 만 — 포함 비용 ≈ 0.

## 2. 호출 순서

```
qexec_execute_query (qx:17456)
  xasl_state.vd.dbval_ptr = dbval_ptr (const 유지) … sys_datetime 형성        qx:17578~17595
  ★ dgate_run_g1 (thread_p, xasl, &xasl_state)     ← 유일한 결정 지점 (G-01: aptr 실행·PX clone·sq_get 전)
      실패: -494 계열/-1150/-622/-1382 → query_error (행 중간 오류 없음)
  qexec_execute_mainblock (…)
    qexec_execute_mainblock_internal (qx:16150)
      aptr_list 실행 (qx:16538~)  — 하위 블록도 같은 xasl_state → 같은 게이트 표를 읽는다
      precompute (qx:16696~16716)
      ★ dgate_run_g2 (thread_p, xasl, xasl_state)  ← 결정 0: S 부류(aptr 리스트 컬럼·precomp 결과)에 entries[].conv 적용, midxkey setdomain 조립 (§4)
      qexec_start_mainblock_iterations
        scan open / range open: dkey_make_range (§4) — 상관·조인 키는 range 마다 값 변환만 (전략 재추론 0, L-45 a·b)
  PX: px_query_executor.cpp:48 / px_query_task.cpp:123 → qexec_deep_copy_xasl_state (vd + gate)  ← G1 뒤라 워커는 변환된 값·표를 상속
  종료: dgate_free (연결 스레드)
```

SA_MODE: `dbval_ptr` 가 `parser->host_variables` 자체(qm:1441)여도 G1 은 그 배열을 읽기만 하고 `gate.vals` 에 쓴다 → 클라이언트 값 불변, 결과 캐시 키·tdes 사본은 원 값 기준.

**규칙 행이 포트를 지나는 모습(두 어댑터)**

| 행 | 로드 어댑터(`dplan_derive`) | G1 어댑터(`dgate_run_g1`) | 실행 |
|---|---|---|---|
| A8'' `abs(?) + 1` | `?` 슬롯 s0(GATE 비트, K) ; `abs` arith 는 in_slot={s0} → gate_nodes[0]=s1 ; `+ 1` arith 는 in_slot={s1, 정적 INT 리터럴} → gate_nodes[1]=s2. `resolve(ARITH, T_ABS, {planned=placeholder, is_gate_slot})` → needs_gate → conv=CONV_GATE | s0.dom = 값 타입(NUMERIC 2.5) ; s1 = resolve(ARITH,T_ABS,{NUMERIC}) → NUMERIC ; s2 = resolve(ARITH,T_ADD,{NUMERIC, INT}) → NUMERIC, conv[1]=int→numeric | fetch_peek_arith 는 entries[s2].dom·conv 만 읽음(fe:1316 탈착·4465 재확정 삭제) |
| B4 `int_col = ?` 1.5 | `?` 슬롯 s0 K planned=INTEGER(미러), 비교 노드 정적: resolve(COMPARE,=,{INT,INT}) → INT, conv=NONE ; 그러나 s0.fail=KEEP 이므로 비교 노드는 **게이트 의존**(in_slot={—, s0}) — 손실 시 비교 도메인이 바뀔 수 있어서 | dgate_apply(s0, 1.5→INT strict) 실패 → KEEP: entries[s0].dom = DOUBLE(값), val = 1.5 ; gate_nodes: resolve(COMPARE,=,{INT, DOUBLE}) → DOUBLE, conv[0]=int→double | eval_value_rel_cmp 는 conv[0] 로 int_col 행마다 변환 후 cmpval (qe:220 타입 분기·in-place coerce 삭제) → 0행 |
| C3 `? = ?` 문자 | s0·s1 GATE, 비교 노드 gate_nodes | resolve(COMPARE,=,{VARCHAR utf8_en_ci coercible, VARCHAR utf8_bin coercible}) → LANG_RT_COMMON_COLL → err -1150 또는 coll_id | 오류는 G1 에서(시점만 이동, 코드 불변 P7 ②) |
| B25 `str_col = int_col` (정적 R·R) | resolve(COMPARE,=,{VARCHAR, INT}) → DOUBLE, conv={str→double, int→double}, needs_gate=false → DPLAN_NODE 확정, slot_id=-1 | entry 복사만 | rank 판정 0 (D-317-20) |

## 3. `val_pos` 다중 참조

확인된 발생 경로 두 곳(정적): **R1** `qo_reduce_equality_terms`(query_rewrite_term.c:448~) — `t1.i = ? AND t1.i = t2.b` 에서 `?` 가 `PT_IS_CONST_INPUT_HOSTVAR` 라 축약 가능 상수로 취급되어 `parser_copy_tree` 로 복사·치환(`t2.b = ?` 또는 `CAST(? AS …)` 래핑, :873~880) → 같은 `val_pos` 를 두 regu 가 참조하고 형제 컬럼 타입이 다르면(INT vs BIGINT) 미러 도메인이 다르다. **R2** `pt_copypush_terms`(view_transform.c:4505~4506) — UNION 파생 테이블의 `v.c = ?` 를 arg1·arg2 가지에 각각 복사 → 가지 컬럼 타입(INT vs DOUBLE)이 다르면 같은 상황. `host_var_expected_domains[idx]` 는 하나(tc:8617 마지막 쓰기)지만 regu 는 노드별 `expected_domain` 을 쓰므로(xg:6452) 오늘도 regu 도메인은 참조마다 다르다.

포트 위의 답(D-318 결정 1·D-327-10 그대로): 바인드 값은 **참조(슬롯)마다** 변환 — `DPLAN_SLOT{val_pos, ref_ord}` 가 참조 순번을 갖고, `gate.vals` 는 슬롯 수만큼이라 `t1.i = ?` 는 INT 변환값, `t2.b = ?` 는 BIGINT 변환값을 각자 가진다. 실패 정책도 참조별(산술 자리 NULL 이 비교 자리를 오염시키지 않음). 원 `vd.dbval_ptr[val_pos]` 는 불변. 비용: 참조 수 × 변환 1회(실행당) — 행당 0. 해석 포트에는 나타나지 않는다(포트는 도메인만 본다) — 어댑터(로드: ref_ord 부여, G1: 슬롯별 apply) 책임. `KEYLIMIT ?`(B34)·LIKE 재작성(`PT_LIKE_LOWER_BOUND(?)`)도 같은 메커니즘으로 자연 처리.

## 4. 인덱스 키 변환 계획 (키 변환 포트 `dkey_*`, 어댑터 하나 — seam 은 열지 않고 함수로)

- **스트림**: `INDX_INFO` 에 `TP_DOMAIN *key_type` 추가, pack/unpack 은 `xts_process_indx_info`(xasl_to_stream.c:4760) / `stx_build_indx_info`(sx:4784) 의 `func_idx_col_id` 다음·`cov_list_id` offset 앞에 `OR_PACK_DOMAIN_OBJECT_TO_OID` / `or_unpack_domain` 한 항목(access-spec 레이아웃, 디스크 없음 M3). 컴파일은 `index_entryp->key_type`(루트 헤더와 같은 바이트, L-45 f)을 싣는다. 로드 시 카탈로그 접근 0.
- **계획 항목**: `DPLAN_KEY { spec; range_idx; is_key2; elem[] : { idx_dom (key_type->setdomain 원소 또는 단일 도메인), slot_id 또는 R/S 참조, cls } ; iss_pair ; mro_asc_dom }`. key1/key2 항목 분리(L-45 c). ISS: `iss_range.key1` 의 첫 원소는 `key_type->setdomain` 첫 도메인으로 시딩(L-45 e), 내림차순 bound 이동(sm:405 `scan_get_next_iss_value` 의 key1→key2)을 위해 fetch 범위 계획 쌍 `iss_pair{lo, hi}` 를 로드에서 미리 만든다(L-45 d). MRO `sort_col_dom` 은 `key_type` 오름차순 사본(`is_desc` 제거)으로 시딩(L-44, bt:22282 NULL 시딩 삭제).
- **K 키**: G1 이 `resolve(KEY_ELEM, …, {idx_dom, 값})` 로 strict-or-keep 1회 — strict 성공(`tp_value_coerce_strict`) → entry.dom=idx_dom, conv=NONE ; 실패 → entry.dom=값 도메인, conv[0]=idx_elem→값 도메인 비교 변환기(B30). 다중 컬럼: G1 이 원소 entry 로 setdomain 을 **1회** 조립해 `DGATE.midx_setdomain[range]`(XASL_STATE 소유, 해제 = dgate_free → L-45 g 누수 소멸) — `need_new_setdomain`·`prebuilt_midxkey_domains`(scan_manager.h:291·345, sm:1889~2148) 삭제.
- **S 키**(상관·조인·ISS 스텝): `dkey_make_range(thread_p, DPLAN_KEY*, DGATE*, KEY_VAL_RANGE*)` 를 range open 마다 — entry.conv 를 값에 적용할 뿐 전략 재추론 없음(L-45 a·b). `btree_compare_key` 폴백(bt:22095, S-12)은 경계 assert 자리(§5 b).
- 두 번째 어댑터가 없으므로(인덱스 종류가 하나) `dkey_*` 는 포트가 아니라 게이트 어댑터의 내부 함수 — 테스트는 `resolve(KEY_ELEM)` 과 `dkey_make_range` 를 직접 부른다.

## 5. 검증 경계

**(a) 로드 경계** — `dplan_derive` 마지막 패스: "GATE 비트 없는 `DB_TYPE_VARIABLE` 또는 `TP_DOMAIN_COLL_LEAVE`" 발견 시 `ER_QPROC_UNRESOLVED_DOMAIN`(아래) + `stx_set_xasl_errcode`. 예외 표(설계상 VARIABLE 허용, L-48 a)는 `domain_plan.cpp` 의 `dplan_load_exceptions[]` 상수 배열로 코드 옆에:

| # | 자리 | 이유 | 검사 대체 |
|---|---|---|---|
| E1 | `TYPE_REGU_VAR_LIST` 포장 노드(CUME_DIST/PERCENT_RANK) | 원소 regu 가 도메인을 갖고 포장은 값이 없음 | 원소 검사 |
| E2 | 분석 윈도우 정렬 키 pos_descr(`REGU_VARIABLE_ANALYTIC_WINDOW`) | 리스트 type_list 가 정본 | type_list 검사 |
| E3 | 집합 연산(UNION/DIFFERENCE/INTERSECTION) 결과 컬럼 pos_descr | 가지 리스트가 정본(U2 C 미러 / U3 G 게이트 표) | 가지 검사 |
| E4 | `TYPE_LIST_ID`/`TYPE_ORDERBY_NUM`/`TYPE_INST_NUM` 등 값 없는 regu | 도메인 무의미 | 건너뜀 |
| E5 | F10 `median(varchar_col)` 인자(X 행) | 실행 결정 잔존(D-317-15) | 표시만(SHOW PLAN 'X') |

필터/함수 인덱스 스트림(`stx_map_stream_to_filter_pred`/`_func_pred`): GATE 비트가 하나라도 있으면 `ER_QPROC_UNRESOLVED_DOMAIN` 로 로드 거부; `fpcache_claim`(filter_pred_cache.c:408~416)이 `stx_map_stream_to_filter_pred` 오류를 `NO_ERROR` 로 삼키는 것(S-42)을 오류 전파로 수정.

**(b) 실행 경계** — 신설 오류 코드 **`ER_QPROC_UNRESOLVED_DOMAIN = -1382`**(`error_code.h`, `ER_LAST_ERROR` → -1383), `cubrid.msg` `$set 5` `1382 Domain of XASL node is unresolved at execution (query %1$s, node %2$s, slot %3$d, domain %4$s).` 인자 = query_id 또는 xasl id 문자열, `DPLAN_SLOT.node_kind`+SHOW PLAN 위치, slot_id, 도메인 이름. 재컴파일 트리거에 넣지 않는다: db_vdb.c:2277·2174·1102, cas_execute.c:1188·1502·2376, cas_common_execute.c:364, method_callback.cpp:276, trigger_manager.c:4971 목록 불변(코드가 다르므로 자동). optdebug 는 `assert_release` 가 아니라 `assert` + 같은 코드 반환. 경계 자리: `qdata_get_valptr_type_list`(qo:6799, 리스트 컬럼 VARIABLE), `fetch_peek_dbval_slow` VARIABLE 분기 자리(fe:5225), `btree_compare_key` 폴백(bt:22095), `eval_value_rel_cmp` coercion 자리(qe:227), 집계 첫값 대기(qx:21504), `scan_dbvals_to_midxkey` 전략 재추론 자리(sm:2024). 각 자리에 perfmon 카운터(#324) 짝.

## 6. 클라이언트 경로

- `pt_set_host_variables`(pd:3072): `tp_value_cast_preserve_domain` 분기와 CHAR/VARCHAR 특례(pd:3128) 삭제 → `pr_clone_value` 만(참조 OID 검사 유지). CHAR 원 값 유지 의미는 게이트 CHAR 변환기의 손실 정책(#325, D-327-01).
- `host_var_expected_domains[]` 남는 소비자: prepare 응답 파라미터 메타(db_vdb.c:2954 `prepare_info`, db_query.c pack), PL/CSQL 보고(method_callback.cpp:657), 바인드 피크 재계획(db_vdb.c:3209 — 비용 추정 입력만), semantic_check.c:13412(대입 도메인). 삭제 소비자: pd:3110.
- `pt_make_regu_hostvar` 2단계(xg:6418~6445 값 타입 도메인)·마지막 `tp_value_cast(val, val, regu->domain)`(xg:6486~6497) 삭제 — 플랜은 값에 독립(D-318-05). 1단계 data_type → 3단계 expected_domain → 4단계 type_enum 만.
- L-30 불변식: `assert (node->info.host_var.index < parser->host_var_count + parser->auto_param_count)` 를 `pt_make_regu_hostvar` 와 `pt_set_host_variables` 에; `host_var_expected_domains` 순회는 항상 `host_var_count` 까지.
- L-31: prepare 응답은 컴파일 도메인(현행 `prepare_column_list_info_set` cas_execute.c:6811). 게이트 확정 결과 컬럼(`SELECT ?`, `? UNION ?`, `sum(?)`)은 실행 응답 `include_column_info=1`(cas_execute.c:1292~1304) 재사용 — 서버 실행 결과 `list_id->type_list` 가 게이트 표 값이므로 드라이버 변경 0.
- S6 PL/CSQL: `method_callback.cpp:608~675` 의 prepare 요청에 이미 `semantics.hvs[idx].type/precision/scale/charset` 가 있다 — 방향을 바꿔 PL 이 **선언 타입을 prepare 요청에 실어** 보내고(`hvs[idx]` 를 입력으로도 사용, wire 필드 추가 없음: 같은 구조체의 mode=in), 파서가 그것을 `host_var_expected_domains[idx]` 의 형제로 쓴다(`pt_preset_hostvar` tc:8609 앞에서 선언 타입이 있으면 expected_domain 을 선점). NULL 은 typed NULL.
- **클라이언트는 해석 포트를 컴파일하지 않는다**(PHYS-05, `parser/` 포함 금지): 파서 그리드(`pt_infer_common_type`·`pt_common_type`·`pt_coerce_node_collation`)는 그대로. 두 그리드 드리프트 방지: 단위 테스트 `dres_vs_parser_grid` — 규칙표 §2~§4 의 C 행 표(§8)를 고정 데이터로 두고 서버 `resolve()` 결과와 asis-matrix 실측(파서가 만든 답)을 대조. 파서를 서버 테스트에 링크하지 않는다.
- `hostvar_late_binding=yes` 값 치환 재컴파일(nr:3805)·`pt_is_op_hv_late_bind`(tc:20520 목록 비우기) 는 #320 마무리.

## 7. SHOW PLAN / trace

- 서버 `qdump_print_xasl`(query_dump.c) 의 regu/arith/agg 출력에 `[dplan slot=%d cls=%c conv=%u/%u fail=%s]` 를 붙이고, `qdump_print_stats_json`(query_dump.c:3175) 트레이스에 블록당 `"gate": {"slots": n, "gate_nodes": m, "resolved": [{slot, dom, coll, conv}]}` 를 추가(`SET TRACE ON` 텍스트/JSON 둘 다). 정적 계획은 `gate_nodes: 0` 이 곧 "행당 결정 0" 의 검사 가능 증거(B 안의 장점 흡수).
- 클라이언트 `SHOW PLAN`(qo_plan_dump) 은 변경 없음 — 컴파일 도메인이 이미 `?:0` 옆에 찍히지 않으므로 여기서는 손대지 않는다(범위 밖).

## 8. 테스트 표면 (인터페이스 = 테스트 표면)

- **포트 단위 테스트**(`unit_tests/query/test_domain_resolver.cpp`): 규칙표 행마다 케이스 1개 — §2 A1~A17(ARITH), §3 B1~B34(COMPARE/KEY_ELEM), §4 U0~U17·F1~F11·S1~S7·X1(ASSIGN/COMMON_VALUE/AGG/ANALYTIC/FUNC_ARG/LIST_COLUMN), §6 C1~C18(collation 필드) — 입력 = (ctx, opcode, operand[], consumer_dom), 기대 = (dom, coll, conv, fail, err). 실행 서버 없음. 데이터는 `domain-pin-asis-matrix.md` 의 셀 라벨을 그대로 케이스 이름으로.
- **어댑터 테스트**: 로드 어댑터는 트리 빌더 fake(XASL 노드를 손으로 조립하는 테스트 헬퍼 — 두 번째 "어댑터" 는 이 빌더뿐)로 slot_id 순서·gate_nodes 순서·예외 표 E1~E5·경계 (a) 거부를 검사; G1 어댑터는 DPLAN + 값 배열을 넣고 게이트 표를 검사(R1/R2 참조별 값, 실패 정책, SA 별칭 불변).
- CTP 셀 ↔ 포트 테스트: asis-matrix 17타입×6상황×5경로의 각 셀은 (ctx, operands) 한 튜플로 사상된다 — 셀 라벨을 테스트 이름으로 하여 게이트 CTP diff 가 나면 같은 이름의 포트 테스트가 먼저 깨지게 한다.

## 9. 삭제 목록

| 축 | 지점 | 도달 불가하게 만드는 것 |
|---|---|---|
| CP(컴파일 확정, 조건 자체 거짓) | S-03 S-11 S-13 S-14 S-15 S-16 S-17 S-18 S-19 S-20 S-21 S-22 S-24 S-25 S-29 S-37 | 계획 도메인 + 게이트 표가 항상 완전(entries 복사) → VARIABLE 분기 삭제, 경계 (b) |
| 로드 어댑터 | S-38(`original_domain` 5+6+3 → 필드 재해석, 원복 코드 삭제) S-33(불변식 보호) M8 `FETCH_ALL_CONST`/`FAST_PEEK`/`AGG_OPERAND`(qx:21839 워커 재도출 포함) 로드 시 cls 로 | `dplan_derive` |
| G1 어댑터 | S-01 S-02 S-04 S-05 S-06 S-07 S-09 S-10 S-23 S-26 S-27 S-28 S-36 S-39 S-40 S-41 | `dgate_run_g1` + `resolve` (gate_nodes) ; 값 변환은 gate.vals |
| G2/키 | S-12 S-30 S-31 S-32 S-34 S-35 | `dgate_run_g2`·`dkey_make_range`·`qexec_deep_copy_xasl_state` |
| KEEP(결정적화 + 경계 assert) | S-08 S-10/S-12 함수 자체 | — |
| 경계 | S-42(fpcache 삼킴 수정) S-43(#320) | §5 |
| collation 26곳(#314 §4) | fe:4479 fe:5226 fe:5239 lf:7082 qx:1362 qx:21193 qx:21249/21277/21405 qx:23137 qx:27787 sm:8231/8254/8287/8293 qx:21328/21336/21440 qx:21605 qa:1876 qa:3343 qn:59 qn:188 sm:8240/8264 fe:5273 `qdata_agg_is_plain_sum_avg` | LEAVE 0 + entries[].coll_id — 쌍 조건 두 축이 함께 삭제; `qfile_unify_types` -1509 분기·`qexec_end_one_iteration` 플래그 분기 포함 |

## 10. 트레이드오프

- **레버리지 높음**: 한 함수 뒤에 서버의 모든 값 격자·병합 규칙이 모이므로(#321 §1~§3 이 한 파일) 규칙표 개정은 한 곳 + 테스트 한 곳. 규칙표 행이 곧 테스트 케이스라 "구현 중 발견한 규칙" 이 코멘트로 새지 않는다(L-01).
- **지역성**: 늦은 바인딩 43곳의 결정이 어댑터 둘로 모이고, 행 경로는 `entries[slot].conv` 조회만 남는다(BR-06/A61 분기 제거, BR-04 불변 결정을 루프 밖으로).
- **얇아질 위험**: `resolve()` 가 `tp_infer_common_domain`·`LANG_RT_COMMON_COLL` 를 그냥 되부르는 pass-through 로 구현되면 삭제 테스트를 통과 못 한다 — 원 자리(qe:220 격자, qx:21504 집계 규칙, S-04 두 값 추론)를 **옮기고 지워야** 깊이가 생긴다. 이것이 이 안의 구현 규율이자 최대 비용(코드 이동 diff 가 크다).
- **간접 비용**: 실행당 `gate_nodes` 순회 + entries 복사(n_slots × 40B 정도). 정적 계획은 0. 행 경로는 포인터 한 단(`dplan_of(regu)->slot_id` → entries) 추가 — 캐시 라인 1개, 대신 도메인 비교·rank switch 가 사라진다.
- **헤더 규율**: 새 헤더 3개와 "parser 포함 금지" 는 사람이 지켜야 한다 → CMake 로 `parser/` 타깃에서 `query/domain_*.hpp` 포함 시 컴파일 실패하도록 include 경로 분리(PHYS-05 기계적 강제).
- **enum ctx 의 확장 압력**: 새 문맥(예: 해시 조인 키)이 생길 때 ctx 를 늘리게 되는데, 이는 규칙표 행 추가와 같은 사건이므로 허용(스펙 변경 = 코드 변경 한 곳).
- **하나뿐인 어댑터를 포트로 부르지 않는다**: 키 변환·PX 상속·collation 병합은 함수/필드로 두었다(가설 seam 을 열지 않음). 두 번째 어댑터가 정말 생기면(예: 외부 인덱스) 그때 seam 을 연다.

## 11. 렛저 대응표

| L | 이 설계에서 |
|---|---|
| L-30 | §6 불변식 assert 두 곳; `host_var_expected_domains` 순회 상한 `host_var_count` |
| L-40 | §1.2 로드 어댑터가 `stx_map_stream_to_xasl` 안 세 경로 공통; 스트림 레이아웃 불변(GATE 비트·`INDX_INFO.key_type` 만); 필터/함수 인덱스 로드 거부 §5(a) |
| L-41 | §1.2 gate_nodes 생산자 우선(안쪽→바깥, aptr→mainblock) + LIST_COLUMN/AGG/ANALYTIC ctx 로 파생 소비자(리스트 컬럼·누산기·정렬 키·MERGE/CTE 하위 XASL 이 같은 xasl_state)가 게이트 표에 |
| L-42 | §1.3 플랜 불변: 실행은 entries 만 쓰고 노드 도메인 필드에 쓰지 않음; `original_domain` 은 DPLAN_NODE 포인터로 재해석, 원복 코드 삭제 |
| L-43 | AGG/ANALYTIC ctx: 누산기 도메인은 G1 이 피연산자 도메인에서 계산(첫값 대기 qx:21504·qn:188/683 삭제); `opr_dbtype` 은 entries[].dom 의 타입 |
| L-45 | §4 (a) 전략 G1 1회 (b) K/S 분리 (c) key1/key2 항목 분리 (d) iss_pair (e) key_type->setdomain 시딩 (f) INDX_INFO.key_type 스트림 (g) midx_setdomain 은 XASL_STATE 소유·dgate_free |
| L-46 | §1.3 DGATE.owner/is_copy; 워커는 `qexec_deep_copy_xasl_state` 사본만, G1 호출 금지 assert; 값 변환은 연결 스레드 `gate.vals` 에 1회(qe:227 힙 전환 삭제) |
| L-48 | §5 예외 표 E1~E5 를 코드 옆 배열로; fpcache 삼킴 수정; 실행 경계 자리 6곳 + 새 코드 -1382 |
| L-49 | 게이트 뒤 불변식 "값 타입 = entries[].dom" 을 `dgate_run_g1` 끝의 assert 로; S-33 은 이 불변식 아래 KEEP; auto-param 넓은 도메인(L-22)은 B33 규칙(리터럴 도메인)으로 G1 이 값을 좁힌다 |
