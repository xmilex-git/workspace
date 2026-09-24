# 변환 계획·서버 게이트 인터페이스 — 확정안 v4

지도 xmilex-git/workspace#312 · 티켓 #323 · 작성 2026-09-22 · 기준 엔진 `develop cad27172b`
세 후보안(`domain-pin-interface-candidates/`)을 `cpp-perf-rules` 로 대조(`domain-pin-architecture.md` §2.2)한 뒤 하나로 합쳤고, 사용자 지적 9건(축약 이름 금지·기존 코드 어휘·`qexec_execute_mainblock` 위치·xasl 트리 순회·단위 테스트 절 삭제·지워지는 resolve 코드·mainblock 진입 전 전부 확정)과 정적 설계 리뷰 R1~R9(2026-09-22, 정확성 결함 3 + 계약 보완 6)를 반영한 판이다. 인용 표기는 `domain-pin-exec-sites.md` 와 같다(`fe:` fetch.c, `qx:` query_executor.c, `qe:` query_evaluator.c, `sx:` stream_to_xasl.c, `xs:` xasl_to_stream.c, `sm:` scan_manager.c, `lf:` list_file.c, `bt:` btree.c, `qa:` query_aggregate.cpp, `qn:` query_analytic.cpp, `pxt:` px_scan_task.cpp, `pd:` parse_dbi.c, `xg:` xasl_generation.c, `mc:` method_callback.cpp, `qm:` query_manager.c).

v3 → v4 변경(리뷰 번호): R1 상관 복합 키 혼합 setdomain 계약(§5) · R2 휘발 피연산자 부류 신설(§2·§3) · R3 결과 캐시 키·partition 참조·dblink 소비자 재분류(§1.2) · R4 고정 조건 호이스팅 계약(§3.3) · R5 항목 핫/콜드 실제 분리와 크기 계약(§1.1) · R6 상관 값 스코프당 1회 변환의 실행 임시값 계약(§3.4) · R7 헤더 허용/금지 목록 재정의와 순환 검사 게이트(§1.4) · R8 PX 해제 경로 교체·깊은 복사 범위·정렬 주장 철회(§1.2) · R9 const 뷰 분리(§3.2) · 측정 판정 보류 절 신설(§13).

---

## 0. 왜 두 덩어리인가 — 기존 `xasl_node` / `xasl_state` 구분 그대로

| | 어디에 사나 | 언제 만드나 | 무엇을 담나 | 이름 |
|---|---|---|---|---|
| 플랜 쪽 | `xasl_node`(플랜 캐시 클론, 실행 간 공유, unpack arena) | 로드 때 1회(`stx_map_stream_to_xasl` 안) | "어느 노드를 어떤 도메인으로, 피연산자는 어떤 변환기로" — 트리의 순수 함수, **불변** | **`DOMAIN_PLAN`** |
| 상태 쪽 | `xasl_state`(실행당 하나, PX 워커마다 사본) | 실행 진입 때 1회(`qexec_execute_query`, `qexec_execute_mainblock` 전) | 이 실행의 답 — 변환된 바인드 값, 게이트 확정 슬롯의 도메인·collation·변환기 | **`RESOLVED_DOMAIN`**(`xasl_state->resolved`) |
| 실행 임시값 | 스캔·집계·정렬의 기존 실행 상태(`SCAN_ID`·`INDX_SCAN_ID`·`accumulator_domain`·`SORT_KEY` 등) | 스코프 진입 때(scan open·range open·그룹 시작) | 계획된 변환기를 스코프당 1회 적용한 **값**과 혼합 setdomain 같은 스코프 한정 파생물 — 결정이 아니라 캐시 | 새 이름 없음(기존 실행 상태) |

플랜에 실행별 값을 쓰면 다음 실행이 이전 값을 본다(L-42). 그래서 플랜과 상태가 나뉜다. 실행 임시값은 셋째가 아니라 기존 실행 상태의 자리이며, 도메인·변환기를 **정하지** 않고 이미 정해진 변환기를 **적용한 결과**만 둔다(R6). 이름은 코드에서 도메인 확정을 부르는 말 `resolve` 를 따른다.

```
컴파일(클라이언트)         규칙표대로 노드 도메인 전부 확정. 못 정하는 슬롯만 REGU_VARIABLE_GATE 비트.
        │                  스트림 변경: 그 비트 하나 + INDX_INFO.key_type
로드(서버, 클론당 1회)     stx_map_stream_to_xasl
                             └ stx_build_domain_plan (xasl_tree)   ← 트리 전체 순회(§2) → xasl_node->domain_plan (불변, arena)
        │                                                             상수 참조 목록·게이트 의존 목록·키 계획(원소별 strict/keep 도메인 쌍)
qexec_execute_query        vd.dbval_ptr = 바인드 값
                           ★ qexec_resolve_domains (xasl_tree, xasl_state)   ← 유일한 결정 지점. 로드 목록을 전부 처리 → 트리 어디에도 미확정 없음 → sealed
                           qexec_execute_mainblock (xasl_tree, xasl_state)   ← 여기서부터 domain_plan·resolved 는 읽기 전용 뷰(§3.2)
                             └ qexec_execute_mainblock_internal (xasl)
                                  aptr_list 마다 qexec_execute_mainblock (재귀)      qx:16538~
                                  비상관 스칼라 서브쿼리 precompute                  qx:16696~16716
                                  qexec_start_mainblock_iterations                  qx:16720
                                    scan open / range open / 그룹 시작: 계획된 변환기를 스코프당 1회 적용 → 실행 임시값(§3.4), 혼합 setdomain 스크래치(§5)
                                    행 루프: 실행 임시값·RESOLVED 뷰 읽기 + 행 의존 변환기 호출. 타입 판정 0, 고정 조건 재검사 0(§3.3)
                           qexec_clear_resolved_domains (xasl_state)
PX                         qexec_deep_copy_xasl_state / qexec_free_xasl_state 짝 하나(§1.2). 워커는 결정 0.
```

**mainblock 안에서 금지되는 것**: `domain_plan`·`resolved.table`·`resolved.vals` 쓰기, `tp_domain_resolve_value`/`tp_infer_common_domain`/`tp_domain_new`/`tp_domain_copy`/`tp_domain_cache` 호출, 값을 보고 도메인·변환기를 고르는 분기. **허용되는 것**: 읽기 전용 뷰로 읽기, 계획된 변환기 호출, 그 결과를 스코프 소유 실행 임시값에 두기, 미리 만든 원소 도메인을 스코프 소유 스크래치에 복사해 연결하기(§5).

---

## 1. 자료구조

### 1.1 `DOMAIN_PLAN` — 플랜 쪽 (`src/query/domain_plan.h`, 서버 전용)

```c
/* 계획된 변환기: 원 값 → 목표 도메인. NULL = 항등. 표의 내용은 #325 — 표 원소는 (원 타입, 목표 타입) 고정 함수여야 하고
 * 안에서 tp_value_cast_internal 류의 타입 switch 를 다시 타면 A61 해소가 아니다(#325 검수 항목). */
typedef int (*DOMAIN_CONV_FUNC) (THREAD_ENTRY * thread_p, const DB_VALUE * src, DB_VALUE * dst, const TP_DOMAIN * domain);

typedef enum { DOMAIN_FAIL_ERROR = 0, DOMAIN_FAIL_NULL = 1, DOMAIN_FAIL_KEEP = 2 } DOMAIN_FAIL_POLICY;   /* 규칙표 X1 */
typedef enum
{
  OPERAND_CONST = 1,        /* 바인드·auto-param·순수 상수 부분트리: 값·도메인 모두 실행당 1회 (qexec_resolve_domains 가 변환·캐시) */
  OPERAND_ROW = 2,          /* 컬럼·컬럼 식: 행마다 계획된 변환기 */
  OPERAND_CORRELATED = 3,   /* 바깥 행 값·비상관 서브쿼리 결과: 스코프당 1회 계획된 변환기 (§3.4) */
  OPERAND_VOLATILE = 4      /* 세션변수·난수·serial·시각 등 부작용/상태 연산자: 도메인은 실행당 1회 확정, 값은 행마다 읽고 계획된 변환기 (R2) */
} DOMAIN_OPERAND_CLASS;

/* 확정된 도메인 하나. 컴파일 확정 자리는 DOMAIN_PLAN_ITEM.fixed 에, 게이트 확정 자리는 xasl_state->resolved.table 에. 64B (D-328-03 으로 operand_domain 추가; 초판 40B). */
typedef struct resolved_domain RESOLVED_DOMAIN;
struct resolved_domain
{
  const TP_DOMAIN *domain;        /* 확정 도메인(캐시 도메인 또는 arena 도메인 — 소유 없음). 문자면 codeset·collation 포함, flag 는 NORMAL */
  DOMAIN_CONV_FUNC conv[3];       /* 피연산자별 변환기 (leftptr/rightptr/thirdptr, 비교는 lhs/rhs, 키는 원소) */
  const TP_DOMAIN *operand_domain[3]; /* 피연산자별 변환 목표 (conv[i] 는 이것에 대해 조회; domain 은 결과 도메인만). 날짜+정수처럼 목표 ≠ 결과인 격자 때문 — #328 D-328-03 */
  const TP_DOMAIN *setdomain;     /* 상수 키 range 항목만: strict-or-keep 결과로 조립한 midxkey setdomain (arena/캐시 소유) */
};

/* 항목 = 노드 하나의 계획. regu/arith/agg/analytic/pos_descr 의 original_domain 자리(8B)에 이 포인터가 들어간다.
 * 핫 필드만 여기(≤ 64B, static_assert). 덤프·게이트·경계용 콜드 필드는 domain_plan.items_cold[i] (R5). */
typedef struct domain_plan_item DOMAIN_PLAN_ITEM;
struct domain_plan_item
{
  int slot;                       /* resolved.table 인덱스. -1 = 컴파일 확정(답은 fixed) */
  int ref;                        /* 상수 참조의 값 인덱스: resolved.vals[ref]. 그 외 -1 */
  unsigned char operand_class;    /* DOMAIN_OPERAND_CLASS */
  unsigned char flags;            /* DOMAIN_PLAN_GATE 0x01 · KEY1 0x02 · KEY2 0x04 · ISS 0x08 · ALIAS 0x10 · KEEP_LAZY 0x20 · TRUNCATE_OK 0x80 (RESIDUAL 0x40 은 D-335-10 으로 삭제) (사용자 CAST 의 비슬롯 피연산자: 절단 수용 = 현행 tp_value_cast_force, D-328-02) */
  unsigned char fail[3];          /* 피연산자별 DOMAIN_FAIL_POLICY — 참조 자리의 속성이므로 표가 아니라 항목에 */
  unsigned char pad[3];
  RESOLVED_DOMAIN fixed;          /* 컴파일 확정 답(로드가 채움). 게이트 항목은 domain=NULL */
};                                /* 16 + 64 = 80B (D-328-03) */
STATIC_ASSERT (sizeof (DOMAIN_PLAN_ITEM) == 80, "D-328-03 operand target layout");

typedef struct domain_plan_item_cold DOMAIN_PLAN_ITEM_COLD;   /* 덤프·qexec_resolve_domains·경계 검사만 읽는다 */
struct domain_plan_item_cold
{
  int val_pos;                    /* 바인드 배열 인덱스, auto-param/그 외 -1 */
  short ctx;  int opcode;         /* domain_resolve 문맥·연산자 */
  const DOMAIN_PLAN_ITEM *pair;   /* ISS 내림차순 fetch 범위 짝 */
  const char *name;               /* "?:0", "arith@qx", "agg#2", "key[1].k1[0]" */
};

typedef struct domain_plan DOMAIN_PLAN;   /* xasl 트리당 1개. 루트 xasl_node->domain_plan; 모든 하위 xasl_node 도 같은 포인터 */
struct domain_plan
{
  int n_items;        DOMAIN_PLAN_ITEM *items;   DOMAIN_PLAN_ITEM_COLD *items_cold;   /* 같은 인덱스 */
  int n_slots;                                          /* resolved.table 길이 = GATE 항목 + KEEP_LAZY 항목 + 상수 키 range 항목. 정적 계획 = 0 */
  int n_refs;         int dbval_cnt;                    /* 값 배열 길이 = dbval_cnt(1차 참조) + 2차 참조 수 */
  int n_gate_nodes;   DOMAIN_PLAN_ITEM **gate_nodes;    /* 게이트 의존 노드, 생산자 우선(= §2 순회 순서) */
  int n_const_refs;   DOMAIN_PLAN_ITEM **const_refs;    /* OPERAND_CONST 참조 항목, ref 오름차순 */
  int n_volatile;     DOMAIN_PLAN_ITEM **volatile_refs; /* OPERAND_VOLATILE 항목 — 도메인 확정용(값은 행마다) */
  int n_keys;         struct domain_plan_key *keys;     /* §5 */
};
```

- **필드 재사용(구조체 크기 불변)**: `regu_variable_node::original_domain` → `DOMAIN_PLAN_ITEM *domain_plan`; `arith_list_node::original_domain` → 동일; `aggregate_list_node::original_domain` → 동일, `original_opr_dbtype`(4B) → `int domain_plan_acc`(누산기 value2 항목 인덱스); `analytic_list_node` 동일; `qfile_tuple_value_position::original_domain` → 동일. `xasl_node` 에 `DOMAIN_PLAN *domain_plan` 1개 추가(디스크 무관). 노드 크기는 불변이지만 **트리당 플랜 메모리는 늘어난다**(항목 80B + 콜드 32B × 노드 수, arena — D-328-03 뒤) — 클론 풀 상주 메모리 증가는 #324 에서 xcache 항목 크기로 잰다.
- **스트림 변경은 둘뿐**: `REGU_VARIABLE_GATE = 0x4000`(regu_var.hpp 의 다음 미사용 비트; 컴파일 세팅) + `INDX_INFO.key_type`(§5). regu/arith/pred 레이아웃은 필터·함수 인덱스 스트림(디스크)이라 불변. agg 는 `flag.dummy` → `flag.gate`, analytic 은 `flag` 의 미사용 비트.
- 부류·슬롯·변환기는 **항목에만**. `flags` 에 비팩 비트를 두지 않는다(β 안 기각).
- 항목·배열은 unpack arena(`stx_alloc_struct`)에 두어 트리와 함께 해제되고 클론 풀 재사용 시 재도출 0. `sizeof`/`offsetof` 는 구현 커밋에서 `STATIC_ASSERT` 로 고정하고 실측을 커밋 메시지에 남긴다(R5).

### 1.2 `RESOLVED_DOMAIN` 표 — 상태 쪽 (`xasl_state` 확장, query_executor.h:88)

```c
typedef struct resolved_domain_table RESOLVED_DOMAIN_TABLE;
struct resolved_domain_table
{
  const DB_VALUE *in;             /* 원 입력 배열(const). SA_MODE 는 parser->host_variables 자체 — 실행 중 어느 스레드도 쓰지 않는다 */
  DB_VALUE *vals;                 /* [n_refs] 참조별 변환값. qexec_resolve_domains 뒤 vd.dbval_ptr == vals. 소유: owner */
  RESOLVED_DOMAIN *table;         /* [n_slots] 게이트가 확정한 자리. qexec_resolve_domains 뒤 불변. 소유: owner (도메인 포인터는 빌린 참조) */
  int n_vals, n_slots;
  THREAD_ENTRY *owner;            /* 해제할 수 있는 유일한 스레드 */
  const DOMAIN_PLAN *plan;
  bool sealed;                    /* qexec_resolve_domains 끝에 true. 이후 쓰기 API 는 assert(optdebug); release 는 계약(§3.2) */
};
struct xasl_state { VAL_DESCR vd; QUERY_ID query_id; int qp_xasl_line; RESOLVED_DOMAIN_TABLE resolved; };
```

- `vals`·`table` 은 **한 번의** `db_private_alloc`(정렬 요구 없음 — `db_private_alloc` 에 정렬 인자가 없고 워커 사본은 워커 private heap 에 따로 잡히므로 false sharing 이 생기지 않는다; v3 의 "64B 정렬" 주장 철회, R8). 정적 계획(`n_slots == 0 && n_refs == dbval_cnt`)은 `table` 없이 `vals` 에 `dbval_cnt` 개 `pr_clone_value` 만.
- **`vd.dbval_ptr` 가 `vals` 로 바뀐다**(1차 참조 인덱스 = val_pos). 기존 `vd->dbval_ptr` 소비자는 **소비 목적별로** 바꾼다(R3):

| 소비자 | 위치 | 무엇을 읽어야 하나 | 변경 |
|---|---|---|---|
| `TYPE_POS_VALUE` fetch | fetch.h:72, fe:4756 | 그 참조의 변환값 | `REGU_RESOLVED_VALUE (vd, regu)` = `vals[regu->domain_plan->ref]` |
| 파티션 프루닝 `TYPE_POS_VALUE` | partition.c:1019·1020·1642·1802 | 그 참조의 변환값(참조별 `ref`; 2차 참조가 1차 값을 읽으면 안 된다) | `REGU_RESOLVED_VALUE` |
| 서브쿼리 결과 캐시 조회 키 | qx:28965~28970 `dbval_p[i] = vd.dbval_ptr[host_var_index[i]]` | **원 값** — `qmgr_process_query`(qm:1454·1659)가 게이트 전 `dbvals_p` 로 `params.vals` 를 만들어 같은 캐시를 저장·조회하므로 키가 같아야 한다(memory_hash.c:569 은 문자열/정수 해시가 다르다) | `resolved.in[host_var_index[i]]` |
| dblink 원격 바인드 | dblink_scan.c:592 | 원 값 | `resolved.in[i]` |
| PX 복사·해제 | qx:3699~3732, px_scan.cpp:1623~2114, pxt:505~540 | — | §1.2 수명 API 로 교체 |

- **PX 수명(R8)**: 생성은 `qexec_deep_copy_xasl_state`(qx:3678) 하나 — `vals` 는 `pr_clone_value`(DB_VALUE payload 깊은 복사), `table` 은 struct 복사(도메인 포인터는 캐시/arena 소유의 **빌린 참조**라 복사하지 않는다), `owner` = 워커, `sealed` 유지; 워커의 혼합 setdomain 스크래치(§5)는 워커 자신의 `INDX_SCAN_ID` 가 만들고 해제한다(복사 대상 아님). 해제는 `qexec_free_xasl_state` 하나 — **pxt:505~540 의 직접 해제 경로(`dbval_cnt` 개만 `pr_clear_value` 뒤 `db_private_free`)와 px_scan.cpp:1623·2112 의 같은 패턴은 이 함수 호출로 교체**(그대로 두면 `n_refs > dbval_cnt` 의 2차 참조 payload 와 `table` 이 새고 `owner` 계약을 우회한다). 워커는 `qexec_resolve_domains` 를 부르지 않는다(assert).

### 1.3 도메인 해석기 — 규칙표 G 행 격자 (`src/query/domain_resolver.h`, 서버 전용)

```c
typedef enum { DOMAIN_CTX_ARITH, DOMAIN_CTX_COMPARE, DOMAIN_CTX_ASSIGN, DOMAIN_CTX_COMMON_VALUE, DOMAIN_CTX_AGG,
               DOMAIN_CTX_ANALYTIC, DOMAIN_CTX_FUNC_ARG, DOMAIN_CTX_LIST_COLUMN, DOMAIN_CTX_KEY_ELEM } DOMAIN_CTX;

typedef struct domain_operand DOMAIN_OPERAND;
struct domain_operand
{
  const TP_DOMAIN *domain;        /* 계획 도메인(로드 때) 또는 값 도메인(게이트 때) */
  DB_TYPE val_type;               /* 게이트 때만; 로드 때 DB_TYPE_NULL */
  int coll_id;  int coercibility; /* 문자만; 비문자는 -1 */
  bool is_gate_slot;
};

/* 유일한 규칙 자리. 순수 함수(할당 0, er_set 0; "할당 0" = 호출자 소유 할당 0 — 결과 도메인은 tp_domain_cache 에 intern 된 캐시 도메인이어도 된다, #333 사용자 승인 2026-09-23). 현행 서버 값 격자(#321 §1~§3: 산술 사전 캐스트, 비교 표, 집계 규칙, 함수 오버로드,
 * LANG_RT_COMMON_COLL, ENUM 변환 표, NUMERIC p/s 공식)를 여기로 옮기고 원 자리는 지운다. 로드는 val_type 없이 불러 *needs_gate 로
 * 게이트 확정 자리를 판별하고, 게이트는 값 타입을 넣어 부른다. */
int domain_resolve (DOMAIN_CTX ctx, int opcode, const DOMAIN_OPERAND * operands, int n_operands,
                    const TP_DOMAIN * consumer_domain, RESOLVED_DOMAIN * result, bool * needs_gate);   /* 현행 함수 코드(-454 등). 연산자가 받지 못하는 조합은 dispatcher 의 현행 결과(오류 / 오류 없는 NULL)를 구분해 돌려준다(D-335-02) */

/* (원 타입, 목표 도메인, 문맥) → 고정 변환기. 대입 문맥은 반올림 캐스트(현행 tp_value_cast 의미), 산술·비교·키는 strict. 항등이면 NULL. */
DOMAIN_CONV_FUNC domain_lookup_converter (DB_TYPE src_type, const TP_DOMAIN * dst_domain, DOMAIN_CTX ctx);
const char *domain_converter_name (DOMAIN_CONV_FUNC f);   /* 덤프 전용 */

/* 값 부류 오버로드 자리(MEDIAN/PERCENTILE 슬롯 · STR_TO_DATE 포맷 슬롯 · ADDTIME 문자 슬롯)의 val_type 분류. 게이트에서만, domain_resolve 전에 1회.
 * 규칙은 오늘 그 함수 첫머리 그대로(DOUBLE→DATETIME→TIME 파싱 시도 / db_check_time_date_format / 존 유무). 파싱은 상태 전용 코어(D-328-07). #328 D-328-06 */
DB_TYPE domain_classify_value (DOMAIN_CTX ctx, int opcode, int arg_index, const DB_VALUE * value);
```

- **AGG/ANALYTIC 읽기(#333, 2026-09-23 사용자 승인)**: 입력 — `consumer_domain` = 집계·분석 노드의 컴파일 도메인(`agg_p->domain`, 인자 값의 소비자), `operands[0]` = 인자(`domain` = 인자 컴파일 도메인 `opr_dbtype`, 게이트가 정하는 인자만 값 도메인; `is_gate_slot` = 게이트가 정하는 인자 = 현행 `opr_dbtype == VARIABLE`). 출력 — `domain` = 함수 도메인(늦은 바인딩 갱신 뒤 `agg_p->domain`, 결과가 캐스트되는 자리), `operand_domain[0]`/`conv[0]` = 누산 도메인(`value_dom`, 인자 값이 변환되는 목표 qa:645·713 — D-328-03 계약 그대로). `value2_dom` 은 함수가 정하는 상수(STDDEV/VAR = DOUBLE, 그 외 NULL)라 해석기 출력이 아니며 로드가 `domain_plan_acc` 항목에 넣는다(§1.1). ANALYTIC 은 `domain` = `operand_domain[0]` = 함수 도메인(현행 `tp_value_coerce (&dbval, func_p->domain)`).

### 1.4 헤더 계약 (R7)

| 헤더 | 정의하는 것 | 포함해도 되는 것(허용 입력) | 포함 금지 |
|---|---|---|---|
| `query/domain_resolver.h` | `DOMAIN_CTX`·`DOMAIN_OPERAND`·`DOMAIN_CONV_FUNC`·`RESOLVED_DOMAIN`·`domain_resolve`·`domain_lookup_converter` | `compat/dbtype_def.h`(공유 값 타입 — **compat/ 전체 금지가 아니다**), `object/object_domain.h` 의 `TP_DOMAIN` 전방선언, `thread_compat.hpp` 전방선언, `xasl/` 의 `OPERATOR_TYPE`·`FUNC_CODE` enum 헤더 | `parser/*.h`, `compat/db_*.h`(클라이언트 API), `broker/`, `method/`, `query_executor.h`, `scan_manager.h`, `regu_var.hpp` |
| `query/domain_plan.h` | `DOMAIN_PLAN_ITEM(_COLD)`·`DOMAIN_PLAN`·`domain_plan_key`·`RESOLVED_DOMAIN_TABLE`·`stx_build_domain_plan` 선언 | `domain_resolver.h`, `compat/dbtype_def.h`, 전방선언 `struct regu_variable_node; struct xasl_node; struct key_range; struct xasl_unpack_info;` | `query_executor.h`, `regu_var.hpp`(완전형 불필요 — 항목 포인터는 노드 쪽 필드에서만 역참조) |
| `query/query_executor.h` | `xasl_state`(값 멤버 `RESOLVED_DOMAIN_TABLE resolved` 이므로 완전형 필요) + `qexec_resolve_domains`·`qexec_clear_resolved_domains` 선언 | `domain_plan.h` 추가 | — |
| `query/fetch.h` | inline 접근자 `REGU_RESOLVED_VALUE`·`RESOLVED`(`regu_var.hpp`·`query_executor.h` 완전형이 여기서 만난다) | 이미 둘 다 포함 | — |

레벨: `domain_resolver.h`(1) ← `domain_plan.h`(2) ← `query_executor.h`(3) ← `fetch.h`(4). 구현 게이트(PHYS-01·02·05 준수의 증거): 각 새 헤더의 **단독 포함 컴파일**(`gcc -fsyntax-only -include <h>`), include 그래프 순환 검사(cpp-perf-rules Appendix D 스크립트), CMake 로 `parser/`·`broker/`·`method/` 타깃의 include 경로에서 `query/domain_*.h` 제외. "레벨 1/3" 이라는 이름은 증거가 아니다.

---

## 2. 로드: `stx_build_domain_plan` — xasl 트리 순회

```c
/* stx_map_stream_to_xasl (sx:212) 의 반환 직전, stx_map_stream_to_filter_pred / _func_pred 의 반환 직전에 부른다 (세 로드 경로 공통).
 * 순수 함수: 같은 스트림 → 같은 items/slots/refs. 필터·함수 인덱스 스트림(is_pred_stream)은 GATE 비트가 하나라도 있으면 거부. */
int stx_build_domain_plan (THREAD_ENTRY * thread_p, xasl_node * xasl_tree, XASL_UNPACK_INFO * unpack_info, bool is_pred_stream);
```

**순회 골격 = `qexec_clear_xasl`(qx:~1100)과 같다.** xasl 은 트리이므로 노드 하나가 아니라 아래 링크를 전부 따라간다. 순회는 `qexec_execute_mainblock` 이 나중에 밟을 모든 xasl_node 를 로드 시점에 미리 밟는다 — 그래서 실행 진입 1회로 트리 전체가 확정된다. 방문 순서가 곧 슬롯 ID·참조·게이트 의존 목록의 순서다(생산자가 소비자보다 먼저).

```
stx_build_domain_plan (root)
  walk_xasl (root):
    1. aptr_list  → 각각 walk_xasl (재귀)          비상관 서브쿼리·CTE·INSERT…SELECT 소스: 소비 블록보다 먼저 실행되므로 먼저
    2. bptr_list  → walk_xasl                       BUILDLIST 하위
    3. dptr_list  → walk_xasl                       상관 서브쿼리(EXECUTE_REGU_VARIABLE_XASL 로 실행)
    4. fptr_list  → walk_xasl                       OBJFETCH
    5. connect_by_ptr → walk_xasl                   CONNECTBY
    6. proc 별 하위: BUILDLIST eptr_list · UNION/DIFFERENCE/INTERSECTION proc.union_.left/right · MERGELIST outer/inner_xasl
       · HASHJOIN outer.xasl/inner.xasl · CTE proc.cte.non_recursive_part/recursive_part · MERGE proc.merge.update_xasl/insert_xasl
    7. 이 노드 자신:
         spec_list (spec 순): indx_info.key_info.key_ranges[i].key1 → key2 (§5 키 항목) → key_filter → where_pred(데이터 필터)
                              (regu 안의 산술은 후위: leftptr → rightptr → thirdptr → 자기 자신)
         val_list / outptr_list (리스트 컬럼 항목: 하위질의·CTE·MERGE·INSERT…SELECT 의 결과 컬럼도 여기)
         after_join_pred / if_pred / instnum_pred / ordbynum_pred
         GROUP BY: g_regu_list → g_agg_list(피연산자 regu → 누산기 항목) → g_outptr_list → g_hk_sort_regu_list
         BUILDVALUE: agg_list
         orderby_list / after_iscan_list 의 pos_descr
         analytic_eval_list (피연산자 → 누산기 → 정렬 키 pos_descr)
         MERGE/UPDATE/INSERT 의 대입 regu (assign 항목, 소비자 도메인 = 컬럼)
    8. scan_ptr → walk_xasl                         다단 스캔
    9. next     → walk_xasl                         리스트 형제
```

각 regu/arith/agg/analytic/pos_descr 에 항목을 하나 만든다(이미 `domain_plan != NULL` 이면 건너뜀 — 멱등). 항목의 내용:

- **부류(R2)** — 값의 불변성과 도메인의 확정 시점을 분리한다:
  - `OPERAND_CONST`: `TYPE_POS_VALUE`(바인드), `TYPE_DBVAL`(auto-param·리터럴), 그리고 **연산자가 순수하고 자식이 전부 CONST 인** 부분트리(`abs(?)`, `? + 1`). 값·도메인 모두 `qexec_resolve_domains` 가 1회 확정·캐시.
  - `OPERAND_VOLATILE`: fetch.c 가 오늘 `FETCH_NOT_CONST` 로 표시하는 연산자 전부 — `T_EVALUATE_VARIABLE`·`T_DEFINE_VARIABLE`(fe:4023·4033), `T_LAST_INSERT_ID`(4013), `T_ROW_COUNT`(3999), `T_CURRENT_VALUE`·`T_NEXT_VALUE`(3080·3103), `T_RAND`·`T_RANDOM`·`T_DRAND`·`T_DRANDOM`(4043~4109; seed 가 상수여도 행별 수열), `T_SYS_GUID`·`T_UUID`(4169·4179), `T_INCR`·`T_DECR`(1705), `T_EXEC_STATS`·`T_TRACE_STATS`·`T_SLEEP`(4246~4317), `T_DECODE`·`T_IF`·`T_PREDICATE`(3218~3253) — 와 이들을 자식으로 갖는 부분트리. **값은 행마다 읽고**(`@v := @v + 1` 이 행마다 직전 쓰기를 본다 — `cbrd_20892.sql` 의 현행 의미 유지), **도메인은 실행당 1회**: 형제가 있으면 컴파일 미러(S4), 없으면 `qexec_resolve_domains` 가 초기값 타입으로 확정(S5). 행마다 읽은 값은 계획된 변환기로 그 도메인에 맞춘다 — 실행 중 세션변수 타입이 바뀌면(`@v := '1'` → `@v := @v + 1`) 변환 실패 정책(X1)이 적용된다. 이것은 현행(행마다 값 타입이 도메인) 과 다를 수 있는 자리이므로 **규칙표 S4/S5 에 "실행 중 타입 변경" 행을 추가해 답안 변경 판정을 받는다**(§12 D-323-18).
  - `OPERAND_ROW`: `TYPE_ATTR_ID`·자기 블록의 `TYPE_POSITION` 하위.
  - `OPERAND_CORRELATED`: 상관 `TYPE_CONSTANT`·바깥 블록의 `TYPE_POSITION`·`REGU_VARIABLE_CORRELATED`·aptr 결과·precompute 결과.
  현행 `FETCH_ALL_CONST`/`FETCH_NOT_CONST` 런타임 마킹과 `qexec_mark_aggregate_operand_expressions`(qx:21839)는 이것으로 대체된다.
- **변환기**: 피연산자 도메인이 전부 컴파일 확정이면 `domain_resolve (ctx, opcode, operands, …, &fixed, &needs_gate)` 로 `fixed` 를 채운다. `needs_gate` 면 `slot` 을 배정하고 `gate_nodes` 에 넣는다(방문 순서 = 생산자 우선).
- **참조**: `TYPE_POS_VALUE` 는 (val_pos, 목표 도메인, 실패 정책) 삼중으로 중복 제거해 `ref` 를 준다 — 첫 참조는 `ref = val_pos`, 삼중이 다른 뒤 참조는 `ref = dbval_cnt + k`(§4).
- **ALIAS**: 리스트 컬럼 pos_descr·정렬 키·누산기·BUILDVALUE 출력 regu·집합 연산 컬럼은 생산자 항목의 `slot` 을 공유하고 새 항목을 만들지 않는다(L-41).
  **구현(#337)**: 파생 소비자는 걷기가 끝난 뒤 해석 단계에서 생산자를 읽는다 — 생산자가 게이트 칸이면 그 칸(ALIAS), 아니면 그 도메인. 생산자는 이렇게 정한다.
  - 값 포인터(`TYPE_CONSTANT`)는 가리키는 값을 쓰는 레코드를 값 동일성으로 찾는다: val_list fetch(`vfetch_to`)·산술 결과·누산기·분석 결과(`value`·`out_value`)·단일 행 부질의가 `single_tuple` 에 복사하는 리스트 컬럼(쓰는 쪽이 다시 값 포인터면 그 생산자까지 따라간다). 값 포인터의 컴파일 도메인은 읽는 쪽의 것이라(INSERT…SELECT 는 대상 컬럼) 생산자의 도메인이 이긴다(F-335-07). 쓰는 레코드가 없는 값 포인터(실행 카운터)는 컴파일 도메인.
  - 리스트 위치(`TYPE_POSITION`)는 읽는 리스트의 컬럼: 스펙의 리스트 XASL 출력, GROUP BY·분석 단계는 스캔 출력(`outptr_list`). 리스트 파일은 숨은 컬럼을 담지 않으므로 건너뛰고, 정렬 키는 숨은 컬럼까지 센다. 집합 연산·CTE 리스트 컬럼은 가지 컬럼을 묶는 합성 노드이고(가지가 컴파일 확정·같은 타입이면 그 타입, 그 밖은 게이트가 `qfile_unify_types` 의미로 정한다), 재귀 CTE 가지가 자기 컬럼을 읽으면 첫 반복이 읽는 비재귀 가지 컬럼이 생산자다. 집합 연산 블록의 ORDER BY 키는 그 합성 컬럼을 읽는다. 컴파일이 확정한 위치·다중 행 VALUES 열은 자기 도메인을 유지한다. 컴파일된 위치가 같은 타입의 리터럴·바인드를 나르면 게이트는 그 값을 분류에 쓴다(D-328-06).
  - 집계 ORDER BY 키는 집계 피연산자 컬럼(CUME_DIST/PERCENT_RANK 는 X-1 포장 안의 값), MEDIAN/PERCENTILE 키는 집계 자신(값이 집계 도메인으로 캐스트된다).
  - 집계·분석: 게이트는 develop 처럼 인자가 열려 있을 때(`opr_dbtype` VARIABLE)만 함수를 인자에서 늦은 바인딩하고, 인자가 컴파일돼 있으면 컴파일 함수 도메인을 답한다(`DOMAIN_GATE_LINK.argument`) — 값 타입은 develop 이 값을 읽는 자리(SUM/AVG 누산기, MEDIAN 부류)에만 쓴다. 컴파일 확정 집계·분석의 누산기 도메인은 인자 도메인에서 해석기로 1회 도출해 항목에 싣는다(`DOMAIN_PLAN_ACCUMULATOR`, L-43). 실행은 첫 행 전에 함수·누산기·인자 도메인(distinct/정렬 리스트 파일은 그 뒤 인자 도메인으로 열린다)을 계획에서 셋업한다(`qexec_setup_aggregate_domains`, 전부 아니면 전무).
  - 파생 소비자를 읽는 실행 자리는 계획을 읽는다(`qexec_plan_domain`: 게이트 칸의 결정, 또는 로드가 생산자에서 실은 도메인 — collation 플래그가 NORMAL 일 때만; LEAVE·ENFORCE 도메인은 값의 타입을 보장하지 않는다, F-336-01). develop 의 늦은 해석 코드는 삭제 티켓까지 소스에 있지만 파생 소비자에서는 조건이 거짓이다. 값으로 정하는 자리는 다른 티켓 몫만 남는다: MySQL 호환 모드·세션변수 타입 변경·CAST 노드(#340·D-336-E·F-336-03 — `EXPRESSION`·`VOLATILE`·`CAST`), 값이 없는 문자열 위의 ADDTIME(D-335-10 이 VARCHAR 로 정하는 자리를 develop 은 값에서 정한다 — `VALUE_TYPED`, #340), 문자 컬럼·식과 세션변수 문자열의 MEDIAN/PERCENTILE 첫 값 캐스트(오류 코드 동치; #340 의 첫값 캐스케이드 삭제), fetch·비교의 슬롯 늦은 해석(#340).
  **구현(#338, collation 축)**: 컴파일이 타입을 정했지만 collation 을 값에 맡긴(LEAVE) 또는 타입을 모르는 피연산자에 ENFORCE 한 문자 항목도 게이트 칸이다 — LEAVE·ENFORCE 바인드 슬롯(auto-param 포함)은 `COLLATION_GATE` 슬롯(값 도메인 기록), 문자 식 노드(`TYPE_INARITH` 의 산술·함수·CAST, `TYPE_FUNC`)는 `GATE | COLLATION_GATE` 인 collation 게이트 노드(링크 = 문자 피연산자, 셋을 넘는 함수는 결정 없음), 컴파일된 위치(`TYPE_POSITION`)도 collation 이 열려 있으면 생산자를 읽는다. 칸 플래그 `DOMAIN_SLOT_TEXT_INEXACT` 는 없어지고, 실행(fetch S-01·S-02·S-05, 파생 소비자, 집계·분석 셋업)이 문자 결정을 읽는다. 집계·분석은 컴파일된 인자가 collation 을 값에 맡겼으면 그 인자의 결정으로 늦은 바인딩한다(D-337-02 는 NORMAL 인자에만).
  - 해석은 생산자 우선 재귀라 게이트 노드 목록의 순서도 그 해석 순서다. 칸 플래그는 결정의 원천 칸에서 상속한다.
- **키**: spec 의 key range 마다 `domain_plan_key` 를 만든다(§5).
- 끝에서 경계 (a) 검사(§6).

세 로드 경로(xcache 클론 xasl_cache.c:1133 · 비캐시 query_manager.c:1219 · PX 워커 언팩 pxt:623)가 같은 스트림을 같은 순서로 걸으므로 같은 슬롯 ID 를 얻는다.

---

## 3. 실행

### 3.1 결정은 `qexec_execute_mainblock` 진입 전 한 번

```c
/* qexec_execute_query (qx:17456), vd 형성(qx:17578~17579) 직후·qexec_execute_mainblock 전. 실행당 1회. 유일한 결정 지점.
 * 로드가 트리 전체를 순회해 만든 목록(const_refs·volatile_refs·gate_nodes·keys)을 전부 처리하므로, 반환 뒤에는 트리 어디에도
 * 미확정 도메인·미변환 상수 참조·미조립 상수 키 setdomain 이 없다. 실패 = 실행 전 오류. */
int qexec_resolve_domains (THREAD_ENTRY * thread_p, xasl_node * xasl_tree, xasl_state * xasl_state);

/* 해제 — qexec_execute_query 끝(정상·오류 모두). owner 만. */
void qexec_clear_resolved_domains (THREAD_ENTRY * thread_p, xasl_state * xasl_state);

/* 수명(기존 함수 확장) */
xasl_state *qexec_deep_copy_xasl_state (THREAD_ENTRY *, xasl_state *);   /* §1.2 범위대로 깊은 복사, owner = 호출 스레드 */
void        qexec_free_xasl_state      (THREAD_ENTRY *, xasl_state *);   /* assert (resolved.owner == thread_p); pxt:505~540·px_scan.cpp:1623·2112 대체 */
```

**하는 일(순서 고정).**
1. `assert (plan->dbval_cnt == vd.dbval_cnt && !resolved.sealed)`; `vals[n_refs]`(+`table[n_slots]`) 한 블록 할당; `resolved.in = vd.dbval_ptr; vd.dbval_ptr = vals`.
2. **상수 참조**(`const_refs`): `src = in[val_pos]`(auto-param 은 `regu->value.dbvalptr`). 변환기 = `domain_lookup_converter (값 타입, fixed.domain, ctx)` 실행당 1회 → `vals[ref]`. 실패 → `fail`: ERROR 는 즉시 반환(현행 -494 계열 코드), NULL 은 `vals[ref] = NULL`(`return_null_on_function_errors` 가 no 면 ERROR), KEEP 은 원 값 복제 + KEEP_LAZY 슬롯을 `domain_resolve (DOMAIN_CTX_COMPARE, …, {계획 도메인, 값 도메인})` 로 재확정. GATE 슬롯은 `table[slot].domain = tp_domain_resolve_value (src)`(codeset·collation 포함) + 복제.
3. **휘발 항목**(`volatile_refs`): 형제 미러가 없는 세션변수 읽기(S5)는 초기값(`session_get_variable`)의 타입으로 `table[slot].domain` 확정; 값은 캐시하지 않는다(행마다 fetch). **구현(#336, D-336-E)**: `T_EVALUATE_VARIABLE` 노드는 4 의 게이트 의존 노드로 등록되고 `qexec_resolve_gate_node` 가 그 자리에서 세션변수를 읽어 도메인을 적는다(미정의 변수는 NULL 도메인, 오류는 행 읽기에서 develop 대로). 형제 미러(S4)는 없다(D-336-B) — `@v + 1` 도 게이트 의존 노드다. fetch 는 행 값의 타입이 결정과 같을 때만 결정을 읽고, 세션변수의 타입이 실행 중 바뀌면 `resolved.volatile_changed` 로 남은 VOLATILE 노드를 develop 의 늦은 해석에 돌려 답을 develop 과 같게 둔다(표 재조회 D-325-10 은 dpin-14).
4. **게이트 의존 노드**(`gate_nodes`, 생산자 우선 — 트리 전체): 피연산자 도메인을 읽어 `domain_resolve (item->ctx, opcode, operands, n, consumer_domain, &table[slot], …)`. 산술 결과·COALESCE 류 공통 타입·누산기·리스트 컬럼이 1회. collation 은 같은 자리에서 정한다(#338): 문자 결과는 피연산자 결정의 collation 을 연산자의 실행 규칙(`LANG_RT_COMMON_COLL` 병합·첫 문자 인자·서식 인자·LANG_SYS·분기)으로 병합하고(`domain_resolve_character`, plus 결합도 같은 병합), precision 은 값이 정한다(floating, D-338-03). 병합이 실패하거나 행이 고르는 분기의 도메인이 다르면 칸은 **결정 없음**(`domain` NULL)이고 그 소비자도 결정 없음이 된다 — -1150/-622 는 develop 처럼 행 계산이 낸다(D-338-02, D-322-01 의 "시점만 게이트" 대체). 연산자가 받지 못하는 조합: develop 이 계산 때 오류(-454)를 내던 조합은 여기서 같은 오류로 실패(0행·미선택 분기도 — 규칙표 §7), 오류 없이 NULL 이던 조합은 NULL 결과만 기록(D-335-02). aptr 결과 리스트 파일의 `type_list` 는 나중에 `qdata_get_valptr_type_list` 가 이 표를 읽어 만든다.
   **구현(#335)**: 피연산자는 로드가 `gate_links[g]`(`gate_nodes` 와 평행 — 피연산자 항목·리터럴 값·AGG/ANALYTIC 컴파일 도메인)에 적어 둔다. 값을 가진 피연산자(바인드·리터럴)는 값 타입(F-335-06), 게이트 의존 생산자는 그 칸, 나머지는 컴파일 도메인; 값 부류 자리(D-328-06)는 바인드·리터럴 값으로 분류하고, 값이 없는 문자열은 타입으로 정한다(ADDTIME VARCHAR·MEDIAN/PERCENTILE DOUBLE, D-335-10, converters §3 끝). 산술 문맥의 거부만 실행 전 오류이고, 다른 문맥의 오류는 계산 때 develop 대로 나며 칸에는 "값 없음"을 기록한다. 해석기가 모르는 연산자는 `ER_QPROC_DOMAIN_UNRESOLVED`(optdebug assert). 게이트 노드 기준과 이관(S5 → dpin-10, 파생 소비자 → dpin-11)은 converters §3 끝.
5. **상수 키 range**(`keys` 중 `OPERAND_CONST`): 원소마다 strict-or-keep → `table[slot].setdomain` 1회 조립(§5). 상관 키는 여기서 할 일이 없다.
6. 불변식 검사: 모든 상수 참조에서 `DB_VALUE_DOMAIN_TYPE (vals[ref]) == TP_DOMAIN_TYPE (RESOLVED (…)->domain)` 이거나 KEEP 으로 기록됨. `resolved.sealed = true`.

정적 계획은 1 의 값 복제뿐이고 2~5 는 빈 배열이다.

**SA_MODE**: `resolved.in` 이 `parser->host_variables` 자체여도 쓰지 않으므로 클라이언트 값 불변. 결과 캐시 키(`params.vals`)·`copy_bind_value_to_tdes`·서브쿼리 결과 캐시 조회(qx:28970)는 모두 원 값(`resolved.in`) 기준.

### 3.2 읽기 전용 뷰 (R9)

```c
/* 실행용 const 뷰 — fetch.h. 반환형이 const 이므로 호출자가 값·도메인을 바꿀 수 없다. */
static inline const DB_VALUE *REGU_RESOLVED_VALUE (const VAL_DESCR * vd, const REGU_VARIABLE * regu)
  { return vd->dbval_ptr + regu->domain_plan->ref; }
static inline const RESOLVED_DOMAIN *RESOLVED (const VAL_DESCR * vd, const DOMAIN_PLAN_ITEM * item)
  { return item->slot < 0 ? &item->fixed : &vd->xasl_state->resolved.table[item->slot]; }
```

- `fetch_peek_dbval` 의 `DB_VALUE **peek_dbval` 출력은 이 PR 에서 시그니처를 바꾸지 않는다 — `TYPE_POS_VALUE` 분기가 `REGU_RESOLVED_VALUE` 의 결과를 `(DB_VALUE *)` 로 캐스트해 돌려주는 **한 곳이 문서화된 const 구멍**이다(peek 값은 원래 수정 금지 계약이며, 오늘 유일하게 수정하던 `eval_value_rel_cmp` 의 제자리 coerce 는 삭제된다). `RESOLVED_DOMAIN.domain` 은 `const TP_DOMAIN *` 이다.
- 쓰기는 `qexec_resolve_domains` 의 구현 파일 안 정적 함수들만 하고, 그 함수들은 `assert (!resolved.sealed)` 로 시작한다. optdebug 에서 assert, release 에서는 계약 — "타입으로 완전 강제" 라고 적지 않는다.

### 3.3 고정 조건은 루프 밖에서 한 번 (R4)

`RESOLVED ()` 의 `slot < 0` 과 변환기의 `conv != NULL` 은 실행 중 고정값이지만 접근자 안에서 평가하면 행마다 검사된다. 계약: **소비 루프의 준비 지점에서 한 번 읽어 그 루프의 실행 상태에 두고, 루프는 그 자리를 읽는다.** 준비 지점과 자리는 기존 코드에 이미 있다:

| 루프 | 준비 지점(1회) | 자리(기존 실행 상태) |
|---|---|---|
| 술어 평가(`eval_value_rel_cmp` 등) | `qexec_start_mainblock_iterations` → `scan_open_*_scan` | `SCAN_ID` 에 `const RESOLVED_DOMAIN *` 와 선택된 비교 kernel(변환기 있음/없음 두 함수 중 하나) |
| 집계·분석 누산 | `qexec_initialize_analytic_state` / GROUP BY 진입(qx:5506) | `aggregate_accumulator_domain.value_dom/value2_dom`(이미 실행별), 분석 `opr_dbtype` 자리 |
| 정렬·top-N | `qfile_initialize_sort_key_info`(lf:4505) | `SORT_KEY` 의 도메인·cmp 함수 |
| 인덱스 키 | scan open | `INDX_SCAN_ID` 의 키 계획 포인터·스크래치(§5) |
| 리스트 스캔 | `scan_open_list_scan` | `LLIST_SCAN_ID` |

행 경로에서 남는 분기는 변환기 호출 자체의 유무를 kernel 선택으로 가른 뒤 0 이다. "실행당 타입 추론 0회" 와 "고정 조건 재검사 0회" 는 다른 성질이며, 후자는 #324 의 branch 카운트(MEAS-06)로 확인한다.

### 3.4 상관 값은 스코프당 1회 변환 — 실행 임시값 (R6)

외부 행 N 개 × 내부 후보 M 개 루프에서 외부 값은 내부 루프 동안 고정이다. 계약: **스코프 진입(내부 scan open · range open · 그룹 시작)에서 계획된 변환기를 1회 적용해 스코프 소유 실행 임시값에 두고, 내부 루프는 그 값을 읽는다** — 호출 수 N 회(N×M 이 아님). 비상관 aptr 결과·precompute 값은 실행당 1회로 더 오래 고정된다. 이것은 결정이 아니다(변환기·도메인은 이미 표에 있다)이고 `domain_plan`·`resolved.table` 은 계속 읽기 전용이다. 자리: `SCAN_ID` 의 스캔별 값(상관 `TYPE_CONSTANT` 피연산자용 DB_VALUE 스크래치, scan open 에 할당·scan close 에 해제, 스캔 스레드 소유), 집계는 `accumulator`. 규칙표 P3 ③ 의 "스코프당 1회" 는 이 계약을 뜻한다(D-323-08).

---

## 4. 한 `?` 의 다중 참조 (탐침 실측)

재작성이 같은 `?` 를 복사하는 경로가 둘 있다: (R1) `qo_reduce_equality_terms`(query_rewrite_term.c:448~) — `t1.i = ? AND t1.i = t2.b` → 재작성 질의 `t2.b = ?:0 AND t1.i = ?:0`, 같은 `?:0` 이 INT 형제와 BIGINT 형제 옆에 CAST 없이 두 번; (R2) `pt_copypush_terms`(view_transform.c:4505~4506) — UNION 파생 테이블의 `v.c = ?` 를 양 가지에 복사(실측: UNION 공통 타입이 컬럼 쪽에 CAST 로 들어가 두 참조의 도메인은 같다). 각 사본 노드는 자기 `expected_domain` 을 가지고 `pt_make_regu_hostvar` 가 노드별로 도메인을 실으므로 **같은 val_pos 의 regu 가 다른 도메인을 갖는 것은 이미 현행**이다.

답: 참조 = (val_pos, 목표 도메인, 실패 정책) 삼중. 로드가 삼중으로 중복 제거해 `ref` 를 주고(1차 = val_pos, 2차 = dbval_cnt + k), `qexec_resolve_domains` 가 `ref` 마다 한 번 변환한다 — R1 은 두 자리, R2 는 한 자리. 실패 정책 NULL 은 그 `ref` 에만 들어가고 `resolved.in` 은 불변(D-327-10). 모든 `TYPE_POS_VALUE` 소비자(fetch·partition)는 `val_pos` 가 아니라 `ref` 로 읽는다(§1.2 표). `KEYLIMIT ?`(B34)·LIKE 재작성도 같은 메커니즘. `host_var_expected_domains[idx]` 는 prepare 메타 전용으로 남는다.

---

## 5. 인덱스 키 (L-45 a~g, R1)

- 스트림 `INDX_INFO.key_type`(TP_DOMAIN*): `xts_process_indx_info`(xs:4760) 의 `func_idx_col_id` 다음에 `OR_PACK_DOMAIN_OBJECT_TO_OID`, `stx_build_indx_info`(sx:4784) 같은 자리에 `or_unpack_domain`, `xts_sizeof_indx_info`(xs:7024) 에 크기. 컴파일(`pt_to_index_info`)은 `index_entryp->key_type` 그대로(f). access-spec 레이아웃이라 디스크 무관.
- 계획:
```c
struct domain_plan_key_elem { DOMAIN_PLAN_ITEM *item; const TP_DOMAIN *index_elem; const TP_DOMAIN *keep_elem; DOMAIN_CONV_FUNC strict_conv; };
   /* index_elem = key_type->setdomain[i](또는 단일 key_type); keep_elem = 원소 regu 의 계획 도메인(strict 실패 시 값 도메인) — 둘 다 로드가 확정 */
struct domain_plan_key
{
  KEY_RANGE *range;  int slot;            /* 상수 키: table[slot].setdomain 자리. 상관 키: -1 */
  unsigned char operand_class;            /* OPERAND_CONST(전 원소 상수) / OPERAND_CORRELATED(하나라도 상관·ISS) */
  short ncols1, ncols2;  struct domain_plan_key_elem *elems1, *elems2;   /* key1/key2 분리 (c) */
  const TP_DOMAIN *asc_key_type;          /* is_desc 0 사본 — ISS 첫 컬럼·MRO 시딩 (e) */
};
```
- **상수 키**: `qexec_resolve_domains` 5 에서 원소마다 `strict_conv` → 성공 = `index_elem`, 실패 = 값 유지 + `keep_elem`(B30·B31 현행 의미) → 혼합 setdomain 을 **arena 가 아니라 `resolved.table[slot].setdomain`** 으로 1회 조립(실행당 값이므로 상태 소유, `qexec_clear_resolved_domains` 가 해제).
- **상관·조인·ISS 키(R1)**: 원소별 성공/실패 조합은 외부 행마다 다르고 2ⁿ 이라 미리 만들 수 없다. 현행(sm:2020~2150)이 하는 일 — 성공 원소는 변환값, 실패 원소만 원 값, 그 조합으로 setdomain 을 조립해 `prebuilt_midxkey_domains[range]` 에 두고 다음 range 에서 조합이 같으면 재사용 — 을 **결정 없이** 그대로 옮긴다: `INDX_SCAN_ID` 에 range 마다 **스크래치 setdomain 체인**(원소 수만큼의 `TP_DOMAIN` 노드, scan open 에 스캔 스레드가 할당·scan close 에 해제 — `prebuilt_midxkey_domains` 의 자리와 수명을 잇되 해제 누수 (g) 는 scan close 로 닫는다)과 **직전 조합 벡터**(원소별 1비트)를 둔다. range open 마다: 원소별 `strict_conv` 호출 → 조합 벡터 → 직전과 같으면 체인 재사용, 다르면 각 노드를 `index_elem`/`keep_elem` 에서 **구조체 복사**로 다시 채우고 링크(`tp_domain_copy`·`tp_domain_cache` 호출 0, 할당 0). `btree` 비교는 이 체인을 읽는다. 어느 원소가 성공했는지는 변환기 반환값이 정하고, 도메인은 로드가 만든 둘 중 하나를 고를 뿐이다 — mainblock 안 "도메인 결정 0" 계약과 정확성(원소별 혼합 = 현행) 둘 다 지킨다. `btree_compare_key` 폴백(bt:22095~22119, S-12)은 경계 assert 로.
- ISS: 첫 컬럼 도메인 = `asc_key_type->setdomain` 첫 원소(sm:447~458 유지; `scan_get_next_iss_value` sm:612·629 의 `last_key` 값 도메인 대입 삭제); 내림차순 bound 이동은 `pair` 로 짝지은 fetch 범위 항목(d). MRO: `btree_range_opt_check_add_index_key`(bt:22282~22320)의 `tp_Null_domain` 시딩 → `asc_key_type` 으로 스캔 준비 시 1회(L-44), `has_null_domain` 루프 삭제.

---

## 6. 검증 경계

**(a) 로드** — `stx_build_domain_plan` 끝: "도메인이 `DB_TYPE_VARIABLE`/`TP_DOMAIN_COLL_LEAVE` 인데 GATE 비트도 ALIAS 도 아닌" 항목 → `ER_QPROC_DOMAIN_UNRESOLVED`(phase "load"). 예외 표는 도출 코드 바로 옆 정적 배열 `domain_plan_load_exceptions[]`:

| # | 자리 | 왜 | 처리 |
|---|---|---|---|
| X-1 | `TYPE_REGU_VAR_LIST` 포장 regu(CUME_DIST/PERCENT_RANK) | 값이 아니라 목록 | 항목 없음 |
| X-2 | `REGU_VARIABLE_ANALYTIC_WINDOW` 정렬 키 | 리스트 컬럼 도메인을 따른다 | ALIAS |
| X-3 | 집합 연산 리스트 컬럼 pos_descr | 가지가 GATE 면 공통 도메인은 표(U3/C8) | ALIAS→GATE |
| X-4 | `TYPE_LIST_ID`·`TYPE_ORDERBY_NUM`·`TYPE_INST_NUM` | 도메인 무의미 | 항목 없음 |
| X-5 | `TYPE_FUNCTION` 집합 생성자(F_SEQUENCE/F_SET…) | 컬렉션 도메인은 원소에서 | 정적(원소 ALIAS) |
| X-6 | `T_EVALUATE_VARIABLE` 세션변수 읽기 | 형제 있으면 미러(S4), 없으면 GATE(S5); 값은 VOLATILE | GATE 비트 요구 |
| X-7 | ~~F10 `median(varchar_col)`·`percentile_* … order by varchar_col` 인자~~ | **폐기(D-335-10, 2026-09-24)**: 컴파일이 DOUBLE 로 확정, 잔존 없음 | — |

필터/함수 인덱스 스트림: GATE 비트 하나라도 있으면 거부. `fpcache_claim`(filter_pred_cache.c:355~416)의 오류 삼킴(S-42)은 전파로 수정.

**#338 상태**: 코드의 예외 표(`domain_plan_load_exceptions[]`)는 X-1~X-5 뿐이다. X-11(식 결과의 `TP_DOMAIN_COLL_LEAVE`)은 collation 게이트 노드가 덮으면서 없어졌고, 경계 (a) 는 GATE·ALIAS 가 아니면서 collation 이 열린(LEAVE·ENFORCE) 문자 항목을 `COLLATION_GATE` 슬롯이 아니면 거부한다. **#337 상태**: 예외 표는 X-1~X-5 와 X-11 이었다. #336 이 두었던 X-8(값 포인터·위치를 피연산자로 가진 노드)·X-9(누산기·정렬 키·리스트 컬럼 VARIABLE)·X-10(`TYPE_FUNC` VARIABLE)은 파생 소비자가 생산자를 읽으면서 없어졌다(§2 구현(#337)). 합성 리스트 컬럼 항목은 그 읽는 쪽이 검사를 받는다.

**(b) 실행** — 신설 `ER_QPROC_DOMAIN_UNRESOLVED = -1382`(`error_code.h`, `ER_LAST_ERROR` → -1383), `msg/*/cubrid.msg $set 5`: `1382 Domain of a query node is unresolved at %1$s (query %2$s, node %3$d, domain %4$s).` 인자 = phase("load"/"execute"), `xasl->query_alias`(없으면 `qp_xasl_line`), 항목 인덱스(`items_cold[i].name`), 도메인 이름. optdebug 는 같은 자리에 `assert`. 설치 자리 6곳: `qdata_get_valptr_type_list`, `fetch_peek_dbval_slow` 옛 VARIABLE 분기, `btree_compare_key` 폴백, `eval_value_rel_cmp` coercion 자리, 집계 첫값 대기 자리, `scan_dbvals_to_midxkey` 재추론 자리 — 각각 #324 perfmon 카운터와 1:1. **재컴파일 트리거에 넣지 않는다**(db_vdb.c:2277·1102·2174·2218·2314·2390·2537, cas_execute.c:1188·1502·2376, cas_common_execute.c:364, method_callback.cpp:276, trigger_manager.c:4971 목록 불변; `ER_QPROC_INVALID_XASLNODE` 는 조용한 재컴파일이라 재사용 금지, D-318-04).

---

## 7. 이걸 하면 지워지는 기존 resolve 코드 (통째로)

**함수 자체가 사라진다**

| 함수 | 위치 | 대체 |
|---|---|---|
| `qexec_resolve_domains_for_aggregation` + `_for_parallel_heap_scan_g_agg` + `_for_parallel_heap_scan_buildvalue_proc` | qx:21504·21474·21484 (S-23·S-34) | 누산기 도메인은 `qexec_resolve_domains` 4 (DOMAIN_CTX_AGG) → `RESOLVED (…)->domain`; 첫 non-NULL 대기 없음 |
| `qexec_resolve_domains_for_group_by` | qx:21223 (S-18) | g_regu/g_agg/g_outptr/해시 키/part 리스트 도메인은 컴파일 확정 또는 ALIAS |
| `qexec_resolve_domains_on_sort_list` | qx:21176 (S-17) | pos_descr 도메인 = 생산자 항목 ALIAS |
| `resolve_domains_on_list_scan` + `resolve_domain_on_regu_operand` | sm:8216·8312 (S-20) | list scan 의 `TYPE_POSITION`/`TYPE_CONSTANT` 도메인은 컴파일 확정 |
| `qfile_update_domains_on_type_list` | lf:7041 (S-13) | 리스트 컬럼 도메인은 `qdata_get_valptr_type_list` 가 `RESOLVED (…)->domain` 으로 만든다 |
| `update_domains_on_type_list_by_val_list` (PX) | px_scan_result_handler.cpp:58 (S-37) | 워커도 같은 값을 읽는다 |
| `qdata_update_agg_interpolation_func_value_and_domain` | qa:3329 (S-26) | MEDIAN/PERCENTILE 도메인은 게이트(F7) 또는 컴파일 DOUBLE(F10, D-335-10) |
| `qexec_mark_aggregate_operand_expressions` | qx:21839, pxt:675 (M8) | `operand_class`·AGG_OPERAND 는 로드 항목 |

**함수는 남고 블록이 사라진다**

| 자리 | 지워지는 블록 |
|---|---|
| `fetch_peek_dbval_slow` fe:4625 | VARIABLE/collation 도메인 확정 블록 fe:5225~5262 (S-05·S-06, REGUVAL_LIST 첫 행 비교 포함), FAST_PEEK 차단 조건 fe:5273; `TYPE_POS_VALUE` 는 `REGU_RESOLVED_VALUE`, `FETCH_ALL_CONST`/`FETCH_NOT_CONST` 세팅 삭제(부류는 로드 항목) |
| `fetch_peek_arith` | 도메인 탈착 fe:1316 → 결과 값으로 재확정 fe:4465~4490 → 오류 시 원복 fe:4603 (S-01·S-02), oracle-empty-string VARIABLE 검사 fe:863·1330 (S-03), NVL/COALESCE/NVL2/NULLIF/LEAST/GREATEST 의 두 값 공통 타입 추론 fe:3306~3961 (S-04) |
| `eval_value_rel_cmp` qe:220~276 | rhs 상수 in-place coerce + 힙 전환 qe:227~247 (S-09·S-39), `tp_value_compare_with_error (do_coercion=1)` 호출 qe:271·276 (S-10) → 선택된 kernel(§3.3) 뒤 `cmpval` 직접 |
| `qexec_initialize_analytic_state` qx:23007 | `resolve_domain:` 블록 qx:23130~23145 (S-19) |
| `qdata_evaluate_analytic_func` qn:188~259·683~792 | 첫값 도메인 블록·`is_first_exec_time` 보간 도메인 switch (S-27·S-28); `qdata_analytic_is_plain_sum_avg`/`qdata_agg_is_plain_sum_avg` 의 VARIABLE 차단 조건 (S-29) |
| `qfile_unify_types` lf:890 | VARIABLE 채택 분기 lf:910~921 + collation -1509 분기 (S-15) |
| `qfile_initialize_sort_key_info` lf:4505 | VARIABLE 시 cmpdisk 폴백 (S-16) |
| `qexec_topn_cmpval` qx:27786 | VARIABLE 시 `tp_value_compare` 폴백 (S-11) |
| `qexec_execute_connect_by` qx:17975~18020 | 프로브 NUMERIC p/s 보정 (S-21) |
| `qdata_hash_join` hj:1015~1040 | 조인 키 공통 타입 추론 (S-22) |
| `qdata_finalize_aggregate_list` qa:1873~1879 | distinct/sort 리스트 도메인 ← type_list (S-25) |
| BUILDVALUE 출력 regu qx:1360~1380 | 도메인 ← 집계 도메인 (S-24) |
| `qexec_clear_arith_list`·`qexec_clear_regu_var`·`qexec_clear_pos_desc`·`qexec_clear_analytic_function_list`·`qexec_clear_agg_list` | `domain = original_domain` 원복 qx:1484·1519·1773·2301·2356 + FETCH_*/FAST_PEEK 클리어 qx:1533~1536 (S-38); 원본 저장 sx:5615·5861·5874·5982·6259·6844, sp:279·400·566 |
| PX 워커 | 집계 도메인 resolve px:926·2145·pxs:1977 (S-34), 루트 역전파 px:2683~2687 (S-35), 행당 누산기 폴백 px:1655·1750·1979·2000 (S-36), pxt:648~672 vd 복사, **pxt:505~540·px_scan.cpp:1623·2112 직접 해제 → `qexec_free_xasl_state`** |
| `scan_dbvals_to_midxkey` sm:1871 | strict 시도·NUMERIC/CHAR/BIT 정확 일치 검사·`need_new_setdomain`·`tp_domain_copy` 조립 sm:2010~2150 (S-30) → §5 스크래치 체인(결정·할당 0) |
| `scan_get_next_iss_value` sm:405 | `last_key` 값 도메인 대입 sm:612·629 (S-31) |
| `btree_range_opt_check_add_index_key` bt:22282~22320 | `tp_Null_domain` 시딩·`has_null_domain` 루프 (S-32) |
| `btree_compare_key` bt:22095~22119 | 비교 불가 조합의 `tp_value_compare_with_error` 폴백 (S-12) → 경계 assert |
| `qexec_generate_row_default_expr`·`qexec_execute_insert` qx:13110·13650 | `db_to_char` 결과 도메인을 포맷 값에서 결정 (S-40) → 포맷 슬롯은 게이트(F1·F2) |
| collation 쌍 조건 26곳(#314 §4) | `TP_DOMAIN_TYPE (d) == DB_TYPE_VARIABLE \|\| TP_DOMAIN_COLLATION_FLAG (d) != TP_DOMAIN_COLL_NORMAL` 조건 전부 — LEAVE 가 XASL 에서 사라지므로 두 축이 함께 |

**남는 것(결정적이 될 뿐)**: `qdata_*_dbval` 의 값 타입 dispatch(S-08), `tp_value_compare_with_error`·`btree_compare_key` 함수 본체(호출자만 줄어듦), `scan_check_user_given_keylimit_overflow` 의 NUMERIC assert(S-33, 이제 불변식이 보호), `INDX_SCAN_ID` 의 range 별 setdomain 자리(이름과 수명만 바뀜, §5).

---

## 8. 클라이언트

- `pt_set_host_variables`(pd:3072): 참조 OID 검사 + `pr_clone_value` 만. `tp_value_cast_preserve_domain` 분기·CHAR 원 값 유지 분기(pd:3128) 삭제(B7 의미는 게이트 CHAR 변환기, D-327-01). **정정(D-335-08, #335)**: 두 분기와 `do_cast_host_variables_to_expected_domain` 은 **남는다** — 바인드 캐스트는 클라이언트가 문장마다 develop 규칙으로 하고(리터럴·바인드 문장의 XASL 공유 F-335-04, 클라이언트 전용 객체 변환 F-335-05), `do_cast` 경로도 VARCHAR 원 값을 유지한다(B7). 게이트는 값을 바꾸지 않고 GATE 슬롯 도메인만 기록한다. 탐침 실측: `int_col = ?`·`i + ?` 슬롯은 오늘 `host_var_expected_domains` 가 비어 있어(DB_TYPE_NULL) 캐스트가 없었다 — 정수 미러 슬롯의 변환은 이 PR 에서 **처음 생기므로** strict-or-keep 이 규칙표 그대로여야 답이 유지된다.
- `host_var_expected_domains[]` 는 남는다: prepare 메타(db_vdb.c:2954, db_query.c:461·546·639), PL 보고(mc:657), semantic_check.c:13412, 하위 세션 공유(db_vdb.c:3350·3436), 바인드 피크(db_vdb.c:3209, 비용 추정만). 삭제 소비자는 pd:3110 하나.
- `pt_make_regu_hostvar`(xg:6391): 2단계(바인드 값 타입 → 도메인, xg:6418~6445)와 꼬리 `tp_value_cast (val, val, regu->domain)`(xg:6493~6500) 삭제. 순서 = data_type → expected_domain → type_enum → GATE 면 placeholder + `REGU_VARIABLE_GATE`. 형제 미러·소비자 도메인 우선은 첫 패스 확정 + 재평가 멱등(#319 F-3).
- 카운트 불변식(L-30): `pt_to_xasl` 끝 `assert (parser->dbval_cnt == parser->host_var_count + parser->auto_param_count)`; 서버 `qexec_resolve_domains` 1.
- 결과 컬럼 메타(L-31): prepare 응답은 컴파일 도메인. GATE 결과 컬럼(`SELECT ?`·`? UNION ?`·`sum(?)`)은 `list_id->type_list` 가 `RESOLVED (…)->domain` 으로 만들어지므로 실행 응답 `include_column_info`(cas_execute.c:1292·1637·1834) 현행 경로로 갱신 — wire 변경 0.
- PL/CSQL 선언 타입(S6): PL 서버 → `method_callback.cpp:608` prepare **요청**에 마커별 (DB_TYPE, precision, scale, codeset, collation) 배열 추가(미지정 = DB_TYPE_NULL); 파서에 `parser->host_var_decl_domains[]`(JDBC 는 NULL)를 `db_compile_statement` 전에 주입; 타입 검사는 이를 `?` 의 **형제**로 본다. 보고 경로(mc:650~675 `semantics.hvs[idx]`)는 그대로. **철회(#339, D-336-B)**: 구현하지 않는다 — PL `?` 는 사용자 `?` 와 같은 슬롯이다(develop 캐스트 자리는 기대 도메인, 나머지 GATE). 이 문단의 요청(`callback_handler::get_sql_semantics`)은 CREATE PROCEDURE 시점 컴파일에만 닿는다: 실행 때 정적 SQL 은 `callback_handler::prepare`(mc:188)로 따로 prepare 되고, 값은 `query_handler::set_host_variables` → `db_push_values` 로 JDBC 와 같은 클라이언트 캐스트 자리를 지난다. PL 컴파일러는 보고된 호스트 변수 타입을 쓰지 않는다(`ParseTreeConverter.checkAndConvertStaticSql` 의 `hostExprs.put(hostExpr, null)`). PL 이 보내는 값은 선언 타입과 다르므로(CHAR → VARCHAR, TIMESTAMP → DATETIME, NUMERIC → 값의 자릿수(p/s), NULL → 타입 없음; `DBType.getObjectDBtype`) 선언 타입을 슬롯 도메인으로 쓰면 develop 답이 바뀐다.
- `hostvar_late_binding`(name_resolution.c:3805·query_rewrite.c:501·type_checking.c:19714)·`pt_is_op_hv_late_bind`(tc:20520) 는 #320 마무리.

---

## 9. 덤프

- `qdump_print_regu_variable`(query_dump.c): regu 마다 `{plan #<n> class=CONST|ROW|CORR|VOLATILE slot=<n>|fixed ref=<n> conv=<name> fail=ERROR|NULL|KEEP gate|X}`; `qdump_print_xasl` 첫 줄 `domain plan: items=N slots=S refs=R(+k) gate_nodes=G`.
- `SET TRACE ON`/`SHOW TRACE` 출력은 **변경 없음**(트레이스 TC 불변; 관찰은 #324 perfmon 카운터). 클라이언트 `SHOW PLAN` 텍스트(`?:0`) 불변.

---

## 10. 예시 두 개

**`SELECT * FROM t WHERE int_col = ?` (B4, 바인드 1.5)**
- 컴파일: `?` INTEGER 미러(C); `int_col` regu INTEGER.
- 로드: `?` 항목 {CONST, slot 0(KEEP_LAZY), ref 0, fixed.domain INT, fail[0] KEEP}; `int_col` 항목 {ROW, slot -1, fixed.conv[0] NULL}.
- `qexec_resolve_domains`: `domain_lookup_converter (DOUBLE, INT, COMPARE)` → strict 실패 → KEEP: `vals[0] = 1.5`, `table[0] = domain_resolve (COMPARE, =, {INT, DOUBLE})` = {domain DOUBLE, conv[0] int→double}.
- scan open(§3.3): `SCAN_ID` 에 `RESOLVED (vd, ?)` 포인터와 "lhs 변환 있음" kernel 선택 1회.
- 행: kernel — `lhs = fetch (int_col)`, `conv (lhs → tmp)`, `rhs = REGU_RESOLVED_VALUE (vd, ?)`, `cmpval`. 타입 판정 0, 고정 조건 재검사 0. 답 0행(현행 유지).
- 바인드 `'1'` 이면 strict 성공: `vals[0] = 1(INT)`, `table[0]` = {INT, conv NULL} → "변환 없음" kernel → 1행.

**`SELECT abs(?) + 1 FROM t` (A8'', 바인드 2.5)**
- 컴파일: `?` GATE 비트; `abs`·`+ 1` 은 게이트 의존 노드(미러 안 함, D-327-08).
- 로드: `?` {CONST, slot 0, ref 0}; `abs` arith {CONST(순수 연산자, 자식 CONST), slot 1, ctx ARITH, opcode T_ABS}; `+` arith {CONST, slot 2, ctx ARITH, opcode T_ADD, 우측 리터럴은 컴파일 확정 INT}; `gate_nodes = [abs, +]`.
- `qexec_resolve_domains`: `table[0].domain = NUMERIC(2.5)`; `table[1] = domain_resolve (ARITH, T_ABS, {NUMERIC})` = NUMERIC; `table[2] = domain_resolve (ARITH, T_ADD, {NUMERIC, INT})` = {NUMERIC, conv[1] int→numeric}. 부분트리 전체가 CONST 이므로 값도 여기서 1회 평가해 `vals` 의 상수 자리에 캐시(현행 `FETCH_ALL_CONST` 제자리 coerce 의 대체, L-46).
- 행: `fetch_peek_arith` 는 캐시된 값을 돌려준다(fe:1316 탈착·fe:4465 재확정·fe:4603 원복 삭제). 답 3.5(현행). 같은 식이 `rand()` 를 품으면 VOLATILE 이라 캐시하지 않고 행마다 평가한다(R2).

---

## 11. cpp-perf-rules 대응 (준수 완료표가 아니라 계약과 측정 지점)

| 규칙 | 계약 | 확인 방법 |
|---|---|---|
| BR-04·A59·A62 | 부류·변환기·`FETCH_ALL_CONST`·`AGG_OPERAND`·원복은 로드 1회; 고정 조건(`slot < 0`, `conv != NULL`)은 §3.3 준비 지점에서 kernel 선택 | #324 branch 카운트(MEAS-06), 생성 코드 확인 |
| BR-06·A61 | rank 사슬·2단 디스패치 → 로드 고정 함수 포인터; #325 변환기 본문에 타입 switch 재실행 금지 | #325 검수 |
| MEM-02·MEM-05 | `DOMAIN_PLAN_ITEM` 80B(`STATIC_ASSERT`, D-328-03이 초판 64B 한도를 대체), 콜드는 `items_cold[]` | `sizeof`/`offsetof` 실측을 커밋에 |
| MEM-03·ALLOC-08·A64 | 값·표 워커 사본은 워커 private heap, `owner` assert, 해제 경로 단일화(pxt:505 교체) | 코드 감사 + ASan/optdebug |
| ALLOC-01 | 행 루프 할당 0; range open 스크래치 체인은 scan open 에 1회 | 코드 감사 |
| 규약 3(안전 > 성능) | 판별자는 항목 안(β 기각); const 뷰 + 문서화된 구멍 1곳 | — |
| PHYS-01/02/05 | §1.4 허용/금지 목록, 단독 포함 컴파일, 순환 검사 | 구현 게이트 |
| 규약 1(측정 먼저) | 노드 8B 레이아웃 변형은 접근자 뒤 구현 변형 — 측정 뒤 | §13 |

---

## 12. 결정 목록 (D-323-01~18, 제안 — #323 코멘트가 잠근 뒤 정본)

| # | 결정 |
|---|---|
| D-323-01 | 골격 = 로드 1(`stx_build_domain_plan`) + 확정 1(`qexec_resolve_domains`, `qexec_execute_mainblock` 전) + 해제 1 + 읽기 전용 뷰 2(`REGU_RESOLVED_VALUE`/`RESOLVED`); 노드 8B = arena 항목 포인터. β 의 union/비팩 flags 비트 기각 |
| D-323-02 | 규칙 자리 = `domain_resolve`/`domain_lookup_converter`(ctx·needs_gate), 로드·게이트·키가 공용; 헤더 계약 §1.4 |
| D-323-03 | `qexec_resolve_domains` 뒤 `vd.dbval_ptr = vals`(1차 참조 = val_pos), 원 입력 `resolved.in` const; **소비자별**: fetch·partition 은 `ref` 로, 서브쿼리 결과 캐시 키·dblink 는 `resolved.in`(R3) |
| D-323-04 | 참조 = (val_pos, 도메인, 정책) 삼중 중복 제거; 표 항목 없음 |
| D-323-05 | `RESOLVED_DOMAIN {domain, conv[3], setdomain}` 40B(#328 D-328-03 이 `operand_domain[3]` 을 더해 64B); 실패 정책은 항목에; 표는 GATE·KEEP_LAZY·상수 키 range 만; 컴파일 확정 답은 항목 `fixed` 인라인 → 정적 계획 표 할당 0 |
| D-323-06 | PX = `qexec_deep_copy_xasl_state`/`qexec_free_xasl_state` 짝 하나(깊은 복사 범위 §1.2, 정렬 주장 없음), `owner` assert, 워커의 `qexec_resolve_domains` 금지, pxt:505·px_scan.cpp 직접 해제 경로 교체(R8) |
| D-323-07 | 술어 노드(`comp_eval_term` 등)는 항목 없음: 변환기는 피연산자 regu 항목, 비교 도메인은 KEEP_LAZY 슬롯/양 피연산자의 fixed |
| D-323-08 | **G2·range 시점 결정 함수 없음**: 결정은 `qexec_execute_mainblock` 전 1회; mainblock 안은 읽기 전용 뷰 + 계획된 변환기 + 스코프 소유 실행 임시값(§3.4, 상관 값 스코프당 1회)과 혼합 setdomain 스크래치(§5, 결정·할당 0). 규칙표 P3 ③ "스코프당 1회" 는 §3.4 의 뜻 |
| D-323-09 | `ER_QPROC_DOMAIN_UNRESOLVED = -1382`, 예외 표 X-1~X-7 |
| D-323-10 | PL 선언 타입 = `host_var_decl_domains[]` + prepare 요청 배열 — **대체(D-336-B, #339)**: 구현하지 않음, PL `?` = 사용자 `?`(§8) |
| D-323-11 | 덤프 = qdump 만, `SHOW TRACE` 불변 |
| D-323-12 | 실패 정책 3종; 대입 반올림은 `domain_lookup_converter (…, DOMAIN_CTX_ASSIGN)` 의 변환기 선택 |
| D-323-13 | agg/analytic: `original_domain` → `domain_plan`, `original_opr_dbtype` → `int domain_plan_acc` |
| D-323-14 | 스트림 비트 `REGU_VARIABLE_GATE 0x4000` 하나; 부류는 항목에만 |
| D-323-15 | 헤더 `domain_resolver.h`(1) ← `domain_plan.h`(2) ← `query_executor.h`(3) ← `fetch.h`(4); 허용·금지 목록과 순환 검사 게이트는 §1.4 |
| D-323-16 | 노드 8B 레이아웃(항목 포인터 → 인라인 POD)은 접근자 뒤 구현 변형, #324/#316 측정 뒤 결정 |
| D-323-17 | 이름: 축약 접두 금지, `DOMAIN_PLAN`/`RESOLVED_DOMAIN`/`resolve`/`qexec_`/`scan_`/`stx_build_` 등 기존 코드 어휘; 순회 골격은 `qexec_clear_xasl` 과 동일 |
| D-323-18 | 피연산자 부류에 **VOLATILE** 신설(fetch.c 의 `FETCH_NOT_CONST` 연산자 목록): 값은 행마다, 도메인은 실행당 1회. 상수 부분트리는 "순수 연산자 + 자식 CONST" 일 때만. 실행 중 세션변수 타입 변경은 규칙표 S4/S5 에 행 추가 → 답안 변경 판정(R2) |

---

## 13. 측정 판정 보류 (MEAS)

이 문서는 정적 설계다. 속도 개선·회귀 없음의 증거는 아직 없고, 다음이 #324(계측)·#316 §4(셀)·게이트 CTP 에서 나와야 `cpp-perf-rules` MEAS 체크가 닫힌다:

- MEAS-01/02/06: 벽시계 시간과 함께 instructions, branch 수·miss 수, cache reference·miss **절대값**을 기록하고 병목을 식별한다. `Num_domain_*` 카운터 0 은 도메인 재결정이 없다는 뜻이지 추가된 간접 호출·복제 비용을 설명하지 않는다 — 삭제된 코드와 함께 카운터 증분이 사라져 0 이 된 것과, 새 경로에 재결정이 없음을 검증한 것을 구분해 적는다(정적 호출 경계 감사 + 실제 계획된 변환 호출 수 `Num_planned_convert`).
- MEAS-04/07: 같은 빌드 종류(optdebug 끼리, release 끼리)의 A/B, 워밍 뒤 5회 중앙값 + MAD. 기존 전체 스캔/PX 셀 외에 **짧은 질의·정적 계획**을 넣어 게이트 고정 비용(값 복제·표 할당 0 확인)을 본다. 상관 셀은 외부 행 수 대비 실제 변환 호출 수를 포함한다(§3.4).
- MEAS-08/CC-08: 실행 시간 차이를 소스 변경에 귀속하기 전에 hot symbol 주소·정렬 위상·바이트 변화 게이트를 수행하고 필요하면 layout control 로 분리한다. 헤더·cold 코드 삭제도 예외가 아니다.
- 플랜 메모리: xcache 항목당 arena 크기 증가(항목 80B + 콜드 32B × 노드 수, D-328-03 뒤)를 기록한다.
