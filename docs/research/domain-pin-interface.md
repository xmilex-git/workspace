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
- **#355 상태**: 항목은 `int slot; int ref; unsigned short flags; unsigned char operand_class; unsigned char fail; int cell; RESOLVED_DOMAIN fixed; const DOMAIN_COMPARE_PLAN **compares;` 80B 다 — `fail[3]` 은 [0] 만 읽혀 하나로(D-355-05), `cell` 은 실행 상태 노드 칸 번호(1부터, 0 = 칸 없음, D-355-01), `compares` 는 FIELD·NULLIF·LEAST·GREATEST 의 비교 기록(`RESOLVED_DOMAIN.setdomain` 자리, D-355-04). `flags` 에 `DOMAIN_PLAN_OPEN 0x400`(컴파일 도메인이 열린 노드; 위치는 regu)·`DOMAIN_PLAN_OPEN_POSITION 0x800`(위치의 값 서술자)가 있고 적재가 발행 때 붙인다(D-355-06·09). regu 플래그 `REGU_VARIABLE_OPEN 0x8000` 은 적재가 정한다(인라인 빠른 경로, D-355-03). 필드 재사용은 끝났다: `original_domain`·`original_opr_dbtype` 은 없고 그 자리는 `domain_plan`(·`domain_plan_acc`)이다.
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
  - 값 포인터(`TYPE_CONSTANT`)는 가리키는 값을 쓰는 레코드를 값 동일성으로 찾는다: val_list fetch(`vfetch_to`)·산술 결과·누산기·분석 결과(`value`·`out_value`)·단일 행 부질의가 `single_tuple` 에 복사하는 리스트 컬럼(쓰는 쪽이 다시 값 포인터면 그 생산자까지 따라간다). 값 포인터의 컴파일 도메인은 읽는 쪽의 것이라(INSERT…SELECT 는 대상 컬럼) 생산자의 도메인이 이긴다(F-335-07). 쓰는 레코드가 없는 값 포인터(실행 카운터)는 컴파일 도메인. GROUP_CONCAT 누산기를 식 안에서 읽는 값 포인터는 예외다: 게이트가 정하는 함수 도메인은 인자를 따르지만(CHAR 바인드면 CHAR, develop 의 `qexec_resolve_domains_for_aggregation` 그대로) 누산기 값은 컴파일된 문자열 타입에 함수 도메인의 codeset·collation 을 얹은 것이라(`qdata_group_concat_first_value`), 그 값 포인터는 ALIAS 가 아니라 집계 노드 하나를 링크로 갖는 collation 게이트 노드다(`domain_character_result` 의 GROUP_CONCAT 분기, #340). 출력 열은 실행이 첫 fetch 전에 함수 도메인으로 다시 타입을 주므로(BUILDVALUE `qexec_end_one_iteration`, GROUP BY 셋업) 그 리스트와 스칼라 부분질의 값은 함수 도메인이고, 출력 열 항목은 집계 노드를 공유한다. 비상관 스칼라 부분질의를 스캔 전에 미리 실행하는 regu(`precomp_owner_regu`)와 집계 PERCENTILE 의 비율 regu(`info.percentile.percentile_reguvar`)도 걷는다 — 실행이 그 실행의 vd 로 fetch 한다(#340). 분석 함수의 비율 regu·보간 결과를 읽는 임시 regu·파티션 식은 vd 없이 fetch 되어 게이트 상태를 읽지 않는다.
  - 리스트 위치(`TYPE_POSITION`)는 읽는 리스트의 컬럼: 스펙의 리스트 XASL 출력, GROUP BY·분석 단계는 스캔 출력(`outptr_list`). 리스트 파일은 숨은 컬럼을 담지 않으므로 건너뛰고, 정렬 키는 숨은 컬럼까지 센다. 집합 연산·CTE 리스트 컬럼은 가지 컬럼을 묶는 합성 노드이고(가지가 컴파일 확정·같은 타입이면 그 타입, 그 밖은 게이트가 `qfile_unify_types` 의미로 정한다), 재귀 CTE 가지가 자기 컬럼을 읽으면 첫 반복이 읽는 비재귀 가지 컬럼이 생산자다. 집합 연산 블록의 ORDER BY 키는 그 합성 컬럼을 읽는다. 컴파일이 확정한 위치·다중 행 VALUES 열은 자기 도메인을 유지한다. 컴파일된 위치가 같은 타입의 리터럴·바인드를 나르면 게이트는 그 값을 분류에 쓴다(D-328-06).
  - 집계 ORDER BY 키는 집계 피연산자 컬럼(CUME_DIST/PERCENT_RANK 는 X-1 포장 안의 값), MEDIAN/PERCENTILE 키는 집계 자신(값이 집계 도메인으로 캐스트된다).
  - 집계·분석: 게이트는 develop 처럼 인자가 열려 있을 때(`opr_dbtype` VARIABLE)만 함수를 인자에서 늦은 바인딩하고, 인자가 컴파일돼 있으면 컴파일 함수 도메인을 답한다(`DOMAIN_GATE_LINK.argument`) — 값 타입은 develop 이 값을 읽는 자리(SUM/AVG 누산기, MEDIAN 부류)에만 쓴다. 컴파일 확정 집계·분석의 누산기 도메인은 인자 도메인에서 해석기로 1회 도출해 항목에 싣는다(`DOMAIN_PLAN_ACCUMULATOR`, L-43). 실행은 첫 행 전에 함수·누산기·인자 도메인(distinct/정렬 리스트 파일은 그 뒤 인자 도메인으로 열린다)을 계획에서 셋업한다(`qexec_setup_aggregate_domains`) — **#341(D-341-04)**: 집계마다 필수이고 전부 아니면 전무는 없다(GROUPBY_NUM·BIT/문자 열 MEDIAN·분류 못한 값 포함), 계획 답이 없는 집계는 경계 (b). PX 워커는 상속한 결정으로 자기 클론을 첫 행 전에 셋업한다(`qexec_setup_parallel_aggregates`). 첫 값에 남는 것(`qexec_aggregate_first_values`)은 문자 열·식 MEDIAN/PERCENTILE 의 DOUBLE 캐스트 확인(첫 실패 값 -1118, 뒤 값 -181)과 게이트가 분류하지 못한 리터럴·바인드의 -1118(분류 없이), 세션변수 읽기 값의 분류 확인(`qexec_interpolation_class_holds`, D-341-08), 행이 정하는 집계(세션변수 읽기가 결정을 벗어났거나 시작 때 값이 없던 것, 미결정 문자열 — 셈)뿐이다. MEDIAN/PERCENTILE 의 행 값은 함수 도메인으로 1회 변환된다(D-341-05); 리스트는 셋업이 정한 도메인(인자와 함수가 같은 타입이면 인자 도메인, 아니면 함수 도메인)으로 처음부터 열린다(#341 후속, D-341-10 개정). 게이트가 정하지 못한 문자열 식 위의 MEDIAN 도 셋업에서 DOUBLE 이다(D-335-10). 누산기를 읽는 BUILDVALUE 출력 열은 셋업에서 계획의 함수 도메인을 받는다(S-24, D-341-09 개정; 행이 정하는 집계만 결정이 날 때). 집계만 먹는 식의 AGG_OPERAND 표시는 로드가 한다(D-341-07).
  - 파생 소비자를 읽는 실행 자리는 계획을 읽는다(`qexec_plan_domain`: 게이트 칸의 결정, 또는 로드가 생산자에서 실은 도메인 — collation 플래그가 NORMAL 일 때만; LEAVE·ENFORCE 도메인은 값의 타입을 보장하지 않는다, F-336-01). develop 의 늦은 해석 코드는 삭제 티켓까지 소스에 있지만 파생 소비자에서는 조건이 거짓이다. 값으로 정하는 자리는 다른 티켓 몫만 남는다: MySQL 호환 모드·세션변수 타입 변경·CAST 노드(#340·D-336-E·F-336-03 — `EXPRESSION`·`VOLATILE`·`CAST`), 값이 없는 문자열 위의 ADDTIME(D-335-10 이 VARCHAR 로 정하는 자리를 develop 은 값에서 정한다 — `VALUE_TYPED`, #340), 문자 컬럼·식과 세션변수 문자열의 MEDIAN/PERCENTILE 첫 값 캐스트(오류 코드 동치; #340 의 첫값 캐스케이드 삭제), fetch·비교의 슬롯 늦은 해석(#340). **#340 상태**: 칸 플래그는 `DOMAIN_SLOT_VOLATILE` 하나만 남는다. MySQL 호환 모드의 식 결과는 결정을 읽고(날짜 helper 가 결과 버퍼의 타입을 따르는데, 그 버퍼는 첫 행부터 결정 타입을 든다), CAST 노드의 결정은 컴파일 목표이며 목표가 VARIABLE 인 집합 연산 포장은 값 없음이다. 값이 없는 문자열 위의 ADDTIME 은 바인드·세션변수 읽기의 값을 게이트가 분류한다(D-335-10). fetch 의 슬롯·파생 소비자 읽기(S-05·S-06)는 결정을 읽는다. 남은 값 판정은 넷이고 각각 셈이 있다: 세션변수 읽기가 결정을 벗어난 뒤의 결정(D-336-E, 아래 §3.1 3단계), 게이트가 정하지 못한 문자열(D-338-02, #343), 비교(S-09)가 제자리 coerce 한 바인드 값(#352), 게이트 상태가 없는 해시 조인 워커 vd(F-334-01, #352). MEDIAN/PERCENTILE 첫 값 캐스케이드는 #341 이다. **#352 상태**: 뒤의 둘이 없어졌다 — 비교의 상수 쪽은 G1 이 자기 값으로 1회 변환하거나 복사하고(공유 값은 그대로, S-09 삭제), 해시 조인 워커 vd 는 `qexec_deep_copy_xasl_state` 로 게이트 상태를 상속한다(F-334-01). 비교는 전부 계획을 읽는다(§3.3, D-352-01~03); develop 의 값 비교는 지도 예외(D-336-E, D-338-02, 술어 스트림 S-42, set/list 비교 내부 — 뒤 셋은 #343)에만 남고, 그 밖은 `eval_value_rel_cmp` 의 경계 (b) 다. **#341 상태**: 리스트 파일은 열 때 계획 도메인으로 타입을 받고(`qdata_get_valptr_type_list` + vd, D-341-02), 첫 튜플이 타입을 주는 열은 세션변수 읽기 위 결정(D-336-E)·게이트가 정하지 못한 문자열(D-338-02)뿐이다(셈). 가지 도메인이 다른 집합 연산·CTE 열은 게이트가 실행 전에 거부한다(#341 후속, 사용자 결정 D-341-14). NULL 피연산자 위 LEAD/LAG 는 NULL 만 담는다 — 기본값이 함수의 NULL·열린 도메인으로 바뀌지 못해 develop 처럼 오류다(#341 후속). 값 없는 결정의 소비자는 NULL 도메인이다(생산자가 NULL 만 낸다, D-341-01). 정렬 키·GROUP BY 위치·리스트 스캔 위치·해시 조인 키·집계·분석은 계획을 읽는다; MEDIAN/PERCENTILE 첫 값 캐스케이드는 없어졌다(위 집계·분석 항). 계획 답이 없는 소비자는 경계 (b) 다. 진단 전수(23770a1e7)에서 list/agg 셈은 D-336-E 43줄뿐이다. **#343 상태**: 게이트가 정하지 못한 문자열(D-338-02)이 없어졌다 — 병합되지 않는 collation 은 값 없음(행이 develop 시점에 오류), 행이 고르는 분기는 ELT 의 게이트 인덱스가 고른 가지 또는 가지 collation 병합(D-343-01, 행은 고른 값을 변환 — `fetch_convert_to_branch_decision`), 문자 함수의 링크는 피연산자 수만큼(`DOMAIN_GATE_LINK` 가변 배열). 남은 값 판정은 세션변수 읽기(D-336-E) 하나와 vd 없이 fetch 되는 regu(→ dpin-17b)이고, 그 밖의 행 읽기 자리(fetch S-02·S-05, 리스트·정렬·그룹·집계·분석·키·비교의 D-338-02 가지)는 경계 (b) 다(`DOMAIN_REASON_UNDECIDED` 삭제). PX 는 행이 타입을 주는 자리가 없다(S-35~S-37 삭제).
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
3. **휘발 항목**(`volatile_refs`): 형제 미러가 없는 세션변수 읽기(S5)는 초기값(`session_get_variable`)의 타입으로 `table[slot].domain` 확정; 값은 캐시하지 않는다(행마다 fetch). **구현(#336, D-336-E)**: `T_EVALUATE_VARIABLE` 노드는 4 의 게이트 의존 노드로 등록되고 `qexec_resolve_gate_node` 가 그 자리에서 세션변수를 읽어 도메인을 적는다(미정의 변수는 NULL 도메인, 오류는 행 읽기에서 develop 대로). 형제 미러(S4)는 없다(D-336-B) — `@v + 1` 도 게이트 의존 노드다. fetch 는 행 값의 타입이 결정과 같을 때만 결정을 읽고, 세션변수의 타입이 실행 중 바뀌면 `resolved.volatile_changed` 로 남은 VOLATILE 노드를 develop 의 늦은 해석에 돌려 답을 develop 과 같게 둔다(표 재조회 D-325-10 은 dpin-14). **#340**: 전역 `volatile_changed` 는 읽기별 마스크로 바뀌었다. 칸마다 그 결정이 기대는 세션변수 읽기의 집합을 든다(`slot_volatile_reads`: 읽기 i 는 비트 i, 63 번째 뒤 읽기는 마지막 비트를 함께 쓴다). 읽기가 결정과 다른 도메인의 값(문자면 precision·codeset·collation 까지, D-338-06)을 보면 그 비트를 `resolved.changed_reads` 에 켜고, 그 비트에 기대는 결정만 뒤의 첫 계산에서 develop 의 늦은 해석을 받는다(`Num_domain_resolve_fetch` 로 센다). ADDTIME 왼쪽·STR_TO_DATE 포맷처럼 내용으로 분류하는 노드는 타입이 같아도 부류가 바뀌면 같은 표시를 한다. PX 워커는 `changed_reads` 를 상속한다. 표 재조회(D-325-10)는 쓰지 않는다: 게이트 도메인으로의 변환은 develop 과 다른 답을 내므로 D-336-A·E 가 대체했다. **#366(dpin-17h, 사용자 결정 U1~U4 — D-336-E·D-340-05·D-341-08·D-362-04 대체)**: 위의 행 시점 늦은 해석과 `changed_reads` 는 없다.
   - 로드가 문장(XASL 트리)의 세션변수 읽기(`T_EVALUATE_VARIABLE`)와 대입(`T_DEFINE_VARIABLE`)을 이름으로 묶어 문장이 **읽는** 변수만 `plan->session_variables` 에 둔다(`DOMAIN_SESSION_VARIABLE`: 이름·읽기 게이트 노드·대입 값 항목, D-366-01). 대입만 하는 변수는 대상이 아니다(U1).
   - G1 은 7단계 뒤 **7b 단계**에서 변수마다 문장 타입을 정한다(`qexec_resolve_session_variables`, D-366-02·03). 문장 타입 = 실행 시작 때 값의 타입 + 대입식의 계획 도메인이다. 열이 행에서 NULL 이어도 열의 타입이고, 명시적 NULL·미정의 시작만 타입이 없다(U2). 문자열은 codeset·collation 이 같으면 한 타입이고 대입하는 변수의 결정은 가변 길이 VARCHAR(최대 precision)다(U4). 다른 타입은 실행 전 `ER_QPROC_SESSION_VARIABLE_TYPE`(-1384, U3, D-366-04).
   - 읽기의 결정과 그 위의 게이트 의존 노드·비교 자리·원소 비교가 이 타입으로 정해진다. 대입식이 읽기에 기대면(`@n := ifnull (@n, 0) + 1`) 타입이 바뀔 때 다시 정한다 — 고정점이고, 변수의 타입은 두 번 넘게 바뀌지 않는다. 4·5 단계는 이 결정들을 건너뛰고, 8단계(키)는 7b 뒤다.
   - 행의 읽기(`fetch_session_read_value`)는 값이 결정 타입인지만 본다. 대입하는 변수의 CHAR 값은 VARCHAR 결정으로 변환하고, 그 밖의 타입(게이트가 보지 못한 쓰기 — 저장 프로시저)은 같은 -1384 다(D-366-05).
   - 내용으로 분류하는 자리(MEDIAN/PERCENTILE·ADDTIME 왼쪽·STR_TO_DATE 포맷)의 부류는 실행 시작 때 값의 것이고(시작 값이 없으면 D-335-10 정적 규칙) 행은 다시 분류하지 않는다. 맞지 않는 내용은 그 연산의 변환 오류다(D-366-06).
4. **게이트 의존 노드**(`gate_nodes`, 생산자 우선 — 트리 전체): 피연산자 도메인을 읽어 `domain_resolve (item->ctx, opcode, operands, n, consumer_domain, &table[slot], …)`. 산술 결과·COALESCE 류 공통 타입·누산기·리스트 컬럼이 1회. collation 은 같은 자리에서 정한다(#338): 문자 결과는 피연산자 결정의 collation 을 연산자의 실행 규칙(`LANG_RT_COMMON_COLL` 병합·첫 문자 인자·서식 인자·LANG_SYS·분기)으로 병합하고(`domain_resolve_character`, plus 결합도 같은 병합), precision 은 값이 정한다(floating, D-338-03). 병합이 실패하거나 행이 고르는 분기의 도메인이 다르면 칸은 **결정 없음**(`domain` NULL)이고 그 소비자도 결정 없음이 된다 — -1150/-622 는 develop 처럼 행 계산이 낸다(D-338-02, D-322-01 의 "시점만 게이트" 대체). 연산자가 받지 못하는 조합: develop 이 계산 때 오류(-454)를 내던 조합은 여기서 같은 오류로 실패(0행·미선택 분기도 — 규칙표 §7), 오류 없이 NULL 이던 조합은 NULL 결과만 기록(D-335-02). aptr 결과 리스트 파일의 `type_list` 는 나중에 `qdata_get_valptr_type_list` 가 이 표를 읽어 만든다.
   **구현(#335)**: 피연산자는 로드가 `gate_links[g]`(`gate_nodes` 와 평행 — 피연산자 항목·리터럴 값·AGG/ANALYTIC 컴파일 도메인)에 적어 둔다. 값을 가진 피연산자(바인드·리터럴)는 값 타입(F-335-06), 게이트 의존 생산자는 그 칸, 나머지는 컴파일 도메인; 값 부류 자리(D-328-06)는 바인드·리터럴 값으로 분류하고, 값이 없는 문자열은 타입으로 정한다(ADDTIME VARCHAR·MEDIAN/PERCENTILE DOUBLE, D-335-10, converters §3 끝). 산술 문맥의 거부만 실행 전 오류이고, 다른 문맥의 오류는 계산 때 develop 대로 나며 칸에는 "값 없음"을 기록한다. 해석기가 모르는 연산자는 `ER_QPROC_DOMAIN_UNRESOLVED`(optdebug assert). 게이트 노드 기준과 이관(S5 → dpin-10, 파생 소비자 → dpin-11)은 converters §3 끝.
   **#364(dpin-17g)**: 공통값 노드(NVL·NVL2·IFNULL·COALESCE·NULLIF·LEAST·GREATEST)는 develop 의 값 접기(S-04)처럼 피연산자 **값의** 도메인을 접는다. 피연산자가 상수 부분트리(7단계가 평가하는 `CAST(? AS T)`, 그 안의 게이트 의존 노드)면 그 노드는 4단계가 아니라 7단계에서 정한다(`DOMAIN_GATE_LINK.after_constants`, 로드가 표시). 평가된 값의 도메인을 읽으므로 타입 없는 NULL 은 접기에서 빠지고, 평가를 행에 맡긴 피연산자는 계획 도메인이다(D-352-05 — #367 에서 없어짐: 모든 상수가 7단계에서 값을 갖는다). 상수 노드는 자기 평가 직전에, 행을 읽는 노드는 마지막 상수 뒤에 정한다. 그 결정을 읽는 게이트 의존 노드(생산자 우선)와 비교 자리도 기다린다. 행이 주는 피연산자는 계획 도메인이다 — develop 은 노드 타입을 첫 비NULL 결과 행의 값으로 붙박았다(S-01, D-340-01 이 없앤 것).
   **#367(dpin-17i, 사용자 결정 (가) — D-352-05 대체)**: 7단계의 상수 부분트리 계산 오류는 그 자리에서 실행의 오류다(`qexec_evaluate_constant`, D-367-01). 게이트 뒤에는 값이 없는 상수가 없다(있으면 경계 (b)). 같은 규칙으로 술어 항·ALL/SOME 의 상수 쪽 변환 실패는 -181(`qexec_resolve_compare`·`qexec_resolve_positions`, D-367-02 — 항 밖 기록인 FIELD·NULLIF·LEAST·GREATEST·LIMIT 는 develop 대로 순위로 답한다), 인덱스 키 상수의 무효 키 타입은 -181(`qexec_resolve_key_constant`, D-367-03 — 앞 컬럼이 NULL 이어도), MEDIAN/PERCENTILE 값 인자의 분류 실패는 -1118(`qexec_resolve_gate_node_over`, D-367-04)이다. 모두 행과 무관하게 실행 전이다. **가지 가드(D-367-07, 사용자 결정 "develop 답 유지")**: develop 의 평가가 상수 조건으로 고르는 가지는 가드다 — CASE·IF·DECODE 의 상수 조건, 도메인이 정해진 COALESCE·NVL·IFNULL·NVL2 의 상수 첫 피연산자(열린 도메인은 develop 의 `fetch_peek_arith` 가 모든 피연산자를 읽어 도메인을 추론한다), AND/OR 의 상수 앞 항, 블록의 상수 if_pred(그 아래 fptr·행 번호·출력·scan_ptr), 최상위 블록의 상수 LIMIT(블록 전체). 로드가 가드를 `plan->guards` 에 두고 항목(`items_cold.guard`)·항(`DOMAIN_COMPARE_PLAN.guard`)·인덱스 스캔(`domain_plan_index.guard`)에 가장 안쪽 가드를 적는다. G1 은 가드 아래의 실패를 적어 두고(`resolved.failures`, 상수는 `DOMAIN_VALUE_FAILED`) 그 상수를 읽는 결정은 건너뛴다. G1 끝(`qexec_raise_reached_failures`)에서 가드를 바깥부터 develop 대로 평가해(`eval_pred`·첫 피연산자 fetch·`qexec_check_limit_clause`) 행이 닿는 첫 실패만 낸다. 닿지 않는 상수는 행도 닿지 않는다. 닿는다면 fetch 가 계산해 develop 의 오류를 낸다. 한 노드가 서로 감싸지 않는 두 가드 아래에서 만나면 계획은 가드를 두지 않는다(모든 실패가 게이트 오류).
5. **상수 키 range**(`keys` 중 `OPERAND_CONST`): 원소마다 strict-or-keep → `table[slot].setdomain` 1회 조립(§5). 상관 키는 여기서 할 일이 없다.
6. 불변식 검사: 모든 상수 참조에서 `DB_VALUE_DOMAIN_TYPE (vals[ref]) == TP_DOMAIN_TYPE (RESOLVED (…)->domain)` 이거나 KEEP 으로 기록됨. `resolved.sealed = true`.

정적 계획은 1 의 값 복제뿐이고 2~5 는 빈 배열이다.

**#371(dpin-18d, 같은 결정을 덜 일해서)**: 1 의 바인드 값은 복제가 아니라 공유 사본이다(`qexec_share_value`/`pr_share_value`: DB_VALUE 는 자기 것, 버퍼는 바인드의 것; 컬렉션은 복제). 2·4·5·7b·8 의 값 도메인은 임시 `TP_DOMAIN` 없이 캐시에서 찾는다(`domain_value_domain`, `domain_character_domain`). 5 는 변환할 것이 없는 리터럴·상수 부분트리 쪽을 복사하지 않고(행이 그 값을 비교한다) 바인드 쪽은 공유 사본이다; 7 은 노드 자신의 문자열을 옮긴다. 8 은 키가 모두 컬럼의 것이면 비교표를 만들지 않고(스택의 (컬럼, 키) 쌍 16개, 넘치면 힙), 키 상수 값을 공유하며, 리터럴 키 원소는 로드가 고정한다(NULL·COLLATE·STRICT 변환·비인덱스 타입은 게이트에 남는다; 클라이언트의 auto-parameterize 로 서버에 오는 `id = 5` 는 바인드다). 실행당 남는 것은 바인드·사이트·키마다의 결정 자체(~0.15 µs)와 블록 할당·clear 의 고정비(~1 µs)다(§13).

**#372(dpin-18e, 한 실행 안에서 되풀이하지 않는다)**: 2 는 상수 참조의 바인드 위치를 로드가 정렬된 `const_refs` 옆에 채운 `DOMAIN_PLAN.const_ref_pos` 에서 읽고, 값 도메인을 참조마다 한 번 구해 그 참조의 GATE·COLLATION_GATE 슬롯 전부에 쓴다(항목마다 cold 레코드를 읽지 않는다; 한 참조의 항목은 모두 한 위치를 읽는다). 5 의 비교 자리는 상수 쪽이 바인드인지 로드가 적어 둔다(`DOMAIN_COMPARE_PLAN.bind[2]`, optdebug 는 cold 레코드와 같은지 확인). 8 에서 한 range 의 key2 CONSTANT 원소가 key1 과 같은 컬럼·같은 바인드 참조(COLLATE 없음)면 key1 의 결정을 쓴다(`domain_plan_key_elem.shared` — `qexec_resolve_key_constant` 는 값·컬럼·복합 여부·가드에만 달려 두 결정이 같았다; `Num_domain_gate_convert` 는 원소마다 그대로 센다). 단일 컬럼 키의 결정은 도메인만 든다(range 는 자기 fetch 의 값을 읽는다). 결정은 여전히 실행마다다(D-371-01, D-372-07). `in (?×30)` 실행당 명령 develop 대비 +40.1k → +31.2k(§13).

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
| 술어 평가(`eval_value_rel_cmp` 등) | 로드(`domain_publish_compares`) 또는 G1 5·7단계 — **개정(D-352-02, #352)**: 술어는 스캔 밖(after_join_pred·if_pred·having·instnum·connect-by·해시 조인 워커)에서도 평가되어 `SCAN_ID` 에 두지 않는다(F-352-05) | 비교 항의 비교 기록(`comp_eval_term.domain_compare`, 스트림에 싣지 않는 포인터)이 kernel(DIRECT·CONVERT·COLLATIONS·OBJECT)과 변환기를 든다; 게이트가 정하는 항은 `resolved.compares[site]`. IN/SOME/ALL 은 `alsm_eval_term.domain_compare`: 리스트 열·스칼라 = 비교 기록, 상수 집합 = 원소 위치별 결정과 G1 의 자기 값(`resolved.elements`), 행이 계산하는 컬렉션 = 원소 키 표(`DOMAIN_ELEMENT_TABLE`, D-352-03·07). **#354**: 술어 항 밖의 비교도 같은 비교 기록이다 — FIELD·NULLIF·LEAST·GREATEST 노드(`ARITH_TYPE.domain_compare`), LIMIT row count 대 INT 0(`xasl_node.limit_compare`), 머지 열 쌍(`mergelist_proc_node.merge_compares`), PX instnum 은 항 자신의 기록(`eval_compare_values_planned`). 키를 데이터만 아는 비교(컬렉션 원소·JSON 스칼라·파티션 경계·해시 그룹 키·두 ORDERBY_NUM 항의 상한·스트림의 비리터럴 쪽)는 키 쌍 표(`domain_compare_by_keys`, D-354-01)를 두 값의 키로 읽는다. **#371 D3**: 결정된 기록은 커널의 연산자별 leaf 표(`DOMAIN_COMPARE.leaves`, DIRECT 만)를 들고, 항의 행은 현재 연산자의 leaf 하나를 부른다(`eval_compare_term` → `eval_leaf_direct<op>`: 두 쪽 값 선택·NULL 규칙·`cmpval`·결과 읽기; 커널 switch·연산자 switch 없음, 다른 커널은 `eval_value_rel_cmp`). 연산자는 로드가 아니라 행이 읽는다(`qexec_eval_instnum_pred` 가 `inst_num () <= n` 을 `<` 로 바꿔 평가한다). `DOMAIN_COMPARE` 는 행이 읽는 필드를 앞 64B 에 모은 80B 다(R2-15, static_assert) |
| 집계·분석 누산 | `qexec_initialize_analytic_state` / GROUP BY 진입(qx:5506) — **#341**: 집계는 mainblock 스캔 전 셋업(`qexec_setup_aggregate_domains`), PX 워커는 `write_initialize` 에서 | `aggregate_accumulator_domain.value_dom/value2_dom`(이미 실행별), 분석 `opr_dbtype` 자리 |
| 정렬·top-N | `qfile_initialize_sort_key_info`(lf:4505) | `SORT_KEY` 의 도메인·cmp 함수 |
| 인덱스 키 | scan open | `INDX_SCAN_ID` 의 키 계획 포인터·스크래치(§5) |
| 리스트 스캔 | `scan_open_list_scan` | `LLIST_SCAN_ID` |

행 경로에서 남는 분기는 변환기 호출 자체의 유무를 kernel 선택으로 가른 뒤 0 이다. "실행당 타입 추론 0회" 와 "고정 조건 재검사 0회" 는 다른 성질이며, 후자는 #324 의 branch 카운트(MEAS-06)로 확인한다.

**#372(dpin-18e)**: 행이 읽는 실행 상태 접근자(`RESOLVED_CELL`·`RESOLVED_GATE_NODE`)는 실행 동안 바뀌지 않는 것(그 실행의 항목인지, 봉인됐는지)을 행마다 검사하지 않고 assert 한다(D-372-02). 집계 루프는 함수의 도메인·피연산자 타입을 그것을 쓰는 경로에서만 읽는다(D-372-01). 산술 노드(`T_ADD`·`T_SUB`·`T_MUL`·`T_DIV`)의 사전 캐스트가 두 피연산자를 모두 바꾸지 않으면 fetch 가 타입 연산자를 바로 부르고(`fetch_arith_binary` 인라인, D-372-04·08), 바꾸는 계획·스코프의 보유 변환·계획 없는 노드(경계 (b))만 out-of-line `fetch_arith_binary_precast` 로 간다(보유값 배열과 그것이 부르는 stack protector 가 빠른 경로의 프레임에서 빠진다). 해시 GROUP BY 키 비교는 두 키 값이 collation 없는 한 타입이면 `tp_value_compare_with_error` 를 바로 부른다(`domain_compare_by_keys` 의 첫 답, D-372-08). 분석 함수 루프는 빠른 경로를 먼저 본다(D-372-03). 남는 행 비용은 게이트 결정을 실행 상태에서 읽는 것이다(바인드 값의 칸, 산술 노드의 결정, 집계 피연산자 타입 — `SUM(c_int * ?) … GROUP BY` 행당 +116 명령, §13); 계획은 실행이 쓰지 않으므로(ADR 0020) develop 처럼 노드에 적어 두고 읽을 수 없다.

### 3.4 상관 값은 스코프당 1회 변환 — 실행 임시값 (R6)

외부 행 N 개 × 내부 후보 M 개 루프에서 외부 값은 내부 루프 동안 고정이다. 계약: **스코프 진입(내부 scan open · range open · 그룹 시작)에서 계획된 변환기를 1회 적용해 스코프 소유 실행 임시값에 두고, 내부 루프는 그 값을 읽는다** — 호출 수 N 회(N×M 이 아님). 비상관 aptr 결과·precompute 값은 실행당 1회로 더 오래 고정된다. 이것은 결정이 아니다(변환기·도메인은 이미 표에 있다)이고 `domain_plan`·`resolved.table` 은 계속 읽기 전용이다. 자리: `SCAN_ID` 의 스캔별 값(상관 `TYPE_CONSTANT` 피연산자용 DB_VALUE 스크래치, scan open 에 할당·scan close 에 해제, 스캔 스레드 소유), 집계는 `accumulator`. 규칙표 P3 ③ 의 "스코프당 1회" 는 이 계약을 뜻한다(D-323-08).

**구현(#368 C5, D-368-01·07 — 위 자리를 대체한다)**: 바꾼 값은 스캔이 아니라 실행 상태가 붙잡는다. `resolved.held[n_held]` 의 한 칸(`DOMAIN_HELD_VALUE`)은 값·epoch·변환기·목표 도메인·실패를 든다. 상수 피연산자도 같은 장치다(P3 ①, D-368-07).
- **스코프**: 상수(리터럴·바인드·상수 부분트리)의 스코프는 실행 전체다(`DOMAIN_SCOPE_EXECUTION`). 상관 값의 스코프는 그 값을 읽는 블록이고, 블록의 값 목록이 스코프 번호를 든다(`VAL_LIST.domain_scope`, 0 = 없음).
- **진입**: 그 값 목록을 채우는 스캔의 시작·재시작(`scan_start_scan`·`scan_reset_scan_block` — 외부 행마다 도는 내부 스캔)과 블록의 실행 시작(`qexec_execute_mainblock` — 상관 부분질의)이다. 진입마다 스코프의 epoch 가 오른다(`qexec_enter_domain_scope`).
- **읽기**: epoch 안의 첫 읽기가 계획된 변환기로 바꾸고 뒤의 읽기는 그 값을 쓴다(`qexec_held_value`; `Num_planned_convert` 는 바꿀 때 한 번 센다). 변환이 실패하면 붙잡지 않는다. 행이 다시 바꿔 develop 의 결과(오류, `return_null_on_function_errors` 면 NULL, 또는 순위)를 낸다. NULL 은 바꾸지 않는다.
- **붙잡는 자리(로드가 정한다)**: 비교 항의 한쪽(`DOMAIN_COMPARE_PLAN.held`), 산술 피연산자, SUM/AVG 가 더하는 값(계획 항목의 `held`)이다. 결정이 바꿀 수 있는 쪽과 사전 캐스트가 바꿀 수 있는 피연산자만 붙잡는다. 로드는 걷는 자리를 둘러싼 블록 목록으로 상관 값을 가린다. 바깥 블록의 값이어야 이 블록의 스캔 동안 고정이다. 두 스코프에서 만난 항·노드는 붙잡지 않는다.
- **PX**: 워커 복사본은 바꾼 값 없이, 실행 스코프만 들어간 상태로 시작한다. 블록 스코프는 워커 자신의 스캔이 연다.
- 플랜(`domain_plan`)은 그대로 읽기 전용이다(P5).
- 셀 `f1-correlated`(INT 외부 100행 × BIGINT 내부 1000·2000행, 상관 부분질의): 외부 값 변환이 100·100·100 이다. 리뷰 측정은 N×M(100,000·200,000·200,000)이었다.
- **#371 D4**: 행의 읽기는 값의 epoch 와 스코프의 epoch 비교 한 번과 그 epoch 의 첫 읽기가 남긴 포인터다(`qexec_held_value` 인라인; 소유자·변환기·목표는 optdebug assert, 첫 읽기 `qexec_convert_held_value` 는 종전대로 검사·변환). 진입은 바꾸지 않는다 — 스코프는 외부 행마다 두 번 들어가고(블록 실행·스캔 시작) 내부 스캔은 외부 행이 있기 전에 들어간다. SUM/AVG 가 더하는 값의 held 인덱스는 셋업이 고정한다(`aggregate_accumulator_domain.held`; 행은 `held != 0 && curr_cnt >= 1` 두 분기).

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
- **#342 상태**: 구현은 위 스케치와 다섯 군데가 다르다. (1) `INDX_INFO.key_type` 은 `or_pack_domain` 으로 싣는다 — B-tree 루트 헤더는 OBJECT 키를 OBJECT 로 두고(키 값은 OID) 스캔 open 이 둘을 정확 일치로 맞추므로 OBJECT→OID 팩을 쓰지 않는다(F-342-02: 단일 컬럼 OBJECT 인덱스 — DROP TABLE·DROP USER 가 읽는 권한 카탈로그 `_db_auth(object_of)`·`(grantee)` — 에서 드러났다). 컴파일은 통계의 `key_type`(루트 헤더 사본)을, 없으면 인덱스를 만든 도메인(`sm_constraint_key_domain`)을 싣고, 스캔 open 에서 다르면 경계 (b). (2) 계획은 인덱스 스캔마다 `domain_plan_index` 하나다: range 마다 key1·key2 와 ISS fetch 범위(`bounds[2n+1]`), 원소 규칙 INDEX·STRICT·KEEP(로드 고정)·CONSTANT·DECIDED(게이트). 상수와 게이트가 도메인을 정하는 원소는 G1 8단계 `qexec_resolve_index_keys` 가 실행당 1회 정해 `resolved.indexes[site]` 에 둔다(상수는 1회 변환하거나 유지해 `Num_domain_gate_convert` 로 세고, 상수만인 혼합 bound 의 도메인도 그때 1회) — 스케치의 `resolved.table[slot].setdomain` 대신이다. 서버의 객체 값은 OID 이고 그 값 도메인은 OBJECT 라(`tp_domain_resolve_value`) OID 값은 OBJECT 결정 도메인에 든다(F-342-04). (3) 단일 컬럼 키(B30)는 변환하지 않는다(F-342-01, #321 §4.2): converters §4 의 스캔 준비 1회 strict 는 FLOAT·DOUBLE 값의 INT·BIGINT 인덱스 검색에서 정밀도 끝에서 develop 답과 갈라진다. 대신 B-tree 비교가 키 비교 표(`DOMAIN_KEY_COMPARES`, 로드 또는 G1)를 읽는다 — `btree_compare_key` 의 비교 불가 폴백(S-12)은 스캔 경로에서 표를 읽고 표에 없는 쌍이 경계 (b) 다(D-325-01: 비교와 키는 같은 COMPARE 모드); 계획 밖 B-tree 검색은 develop 폴백 그대로. (4) 스크래치 체인의 조합 벡터는 원소별 1비트가 아니라 컬럼별 선택 3가지다(인덱스 컬럼·계획의 다른 도메인·값 — 마지막은 지도 예외 D-336-E·D-338-02 이고 재사용하지 않는다). (5) 병렬 인덱스 스캔은 승격(`scan_try_promote_parallel_index_scan`) 이 직렬 스캔을 닫은 뒤에도 리더의 키 계획 저장소를 쓰고(키 range 와 워커 비교가 읽는다), 병렬 스캔의 close 가 워커 뒤에 놓는다(F-342-03). 비교 kernel 은 `domain_resolver.c` 의 `domain_compare_values` 로 옮겨 술어와 B-tree 가 함께 쓴다(D-342-07).
- **#371 D1·W3**: 스캔 open 이 검색 키 비교기를 한 번 고른다(`scan_key_state.search_compare` → `BTID_INT.search_compare`, PX 워커의 `BTID_INT` 도 같은 선택): 키 비교표가 비면 DIRECT(단일 컬럼: 컬럼의 `cmpval`)·MIDXKEY_PLAIN(복합: 원소 콜백 없는 `pr_midxkey_compare_planned`), 아니면 PLANNED(= 종전 `btree_compare_key_with`). 빈 표 ⇔ 모든 값이 컬럼의 타입·콜레이션이다(`domain_resolve_key_compares` 는 다른 키 쌍마다 항목을 만든다) — 원소 규칙으로는 판정할 수 없다(단일 컬럼은 어떤 타입이든 INDEX, 복합 STRICT 는 range 에서 실패하면 kept). optdebug 는 종전 검사로 같은 답을 확인한다. 범위의 정렬·중복 제거(`scan_key_compare`)도 표가 없으면 `tp_value_compare`. 단일 컬럼 키 스캔은 표가 없으면 키 저장소(스크래치 체인·strict 변환값)가 없다(W3: 단일 컬럼 키는 STRICT 가 없다).

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

**#354 상태**: 필터/함수 인덱스 스트림과 파티션 식은 로드(`domain_plan_stream_compares`)가 비교 기록을 만든다. 리터럴끼리의 비교는 리터럴로 정하고, 그 밖은 키 쌍 표를 읽는다(kernel KEYS). 카탈로그는 컬럼 타입을 바꾸는 ALTER 뒤에도 옛 타입으로 컴파일한 스트림을 두므로, 스트림 도메인은 값을 설명하지 않을 수 있다(D-354-06). `DOMAIN_REASON_PRED_STREAM` 은 없고, 기록 없는 항은 경계 (b) 다. **#343 상태**: 필터/함수 인덱스 스트림은 언팩이 GATE regu 를 보면 로드를 거부한다(`stx_index_stream_rejected`, -1383 "load"), `fpcache_claim` 은 언팩 오류를 돌려준다(S-42). 경계 (a) 는 #336·#337 이 켰고 그대로다. **#338 상태**: 코드의 예외 표(`domain_plan_load_exceptions[]`)는 X-1~X-5 뿐이다. X-11(식 결과의 `TP_DOMAIN_COLL_LEAVE`)은 collation 게이트 노드가 덮으면서 없어졌고, 경계 (a) 는 GATE·ALIAS 가 아니면서 collation 이 열린(LEAVE·ENFORCE) 문자 항목을 `COLLATION_GATE` 슬롯이 아니면 거부한다. **#337 상태**: 예외 표는 X-1~X-5 와 X-11 이었다. #336 이 두었던 X-8(값 포인터·위치를 피연산자로 가진 노드)·X-9(누산기·정렬 키·리스트 컬럼 VARIABLE)·X-10(`TYPE_FUNC` VARIABLE)은 파생 소비자가 생산자를 읽으면서 없어졌다(§2 구현(#337)). 합성 리스트 컬럼 항목은 그 읽는 쪽이 검사를 받는다.

**(b) 실행** — 신설 `ER_QPROC_DOMAIN_UNRESOLVED = -1383`(`error_code.h`, `ER_LAST_ERROR` → -1384), `msg/*/cubrid.msg $set 5`: `1383 Domain of a query node is unresolved at %1$s (query %2$s, node %3$d, domain %4$s).` 인자 = phase("load"/"execute"), `xasl->query_alias`(없으면 `qp_xasl_line`), 항목 인덱스(`items_cold[i].name`), 도메인 이름. optdebug 는 같은 자리에 `assert`. 설치 자리 6곳: `qdata_get_valptr_type_list`, `fetch_peek_dbval_slow` 옛 VARIABLE 분기, `btree_compare_key` 폴백, `eval_value_rel_cmp` coercion 자리, 집계 첫값 대기 자리, `scan_dbvals_to_midxkey` 재추론 자리 — 각각 #324 perfmon 카운터와 1:1. **재컴파일 트리거에 넣지 않는다**(db_vdb.c:2277·1102·2174·2218·2314·2390·2537, cas_execute.c:1188·1502·2376, cas_common_execute.c:364, method_callback.cpp:276, trigger_manager.c:4971 목록 불변; `ER_QPROC_INVALID_XASLNODE` 는 조용한 재컴파일이라 재사용 금지, D-318-04).

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
- `hostvar_late_binding`(name_resolution.c:3805·query_rewrite.c:501·type_checking.c:19714)·`pt_is_op_hv_late_bind`(tc:20520) 는 #320 마무리. (`hostvar_late_binding` 은 #344 D-344-01 로 유지 — 감사표 S-43)

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
- 게이트(§3.3, D-352-01/02 로 개정): 비교 항의 기록이 게이트 칸이면 G1 5단계가 양쪽 키(`int_col` 의 INT, `?` 값의 DOUBLE)로 결정 1회 — "lhs 변환 있음" kernel, 상수 `?` 는 게이트의 자기 값(변환 없으면 복사).
- 행: kernel — `lhs = fetch (int_col)`, `conv (lhs → tmp)`, `rhs = REGU_RESOLVED_VALUE (vd, ?)`, `cmpval`. 타입 판정 0, 고정 조건 재검사 0. 답 0행(현행 유지).
- 바인드 `'1'` 이면 strict 성공: `vals[0] = 1(INT)`, `table[0]` = {INT, conv NULL} → "변환 없음" kernel → 1행.

**`SELECT abs(?) + 1 FROM t` (A8'', 바인드 2.5)**
- 컴파일: `?` GATE 비트; `abs`·`+ 1` 은 게이트 의존 노드(미러 안 함, D-327-08).
- 로드: `?` {CONST, slot 0, ref 0}; `abs` arith {CONST(순수 연산자, 자식 CONST), slot 1, ctx ARITH, opcode T_ABS}; `+` arith {CONST, slot 2, ctx ARITH, opcode T_ADD, 우측 리터럴은 컴파일 확정 INT}; `gate_nodes = [abs, +]`.
- `qexec_resolve_domains`: `table[0].domain = NUMERIC(2.5)`; `table[1] = domain_resolve (ARITH, T_ABS, {NUMERIC})` = NUMERIC; `table[2] = domain_resolve (ARITH, T_ADD, {NUMERIC, INT})` = {NUMERIC, conv[1] int→numeric}. 부분트리 전체가 CONST 이므로 값도 여기서 1회 평가해 `vals` 의 상수 자리에 캐시(현행 `FETCH_ALL_CONST` 제자리 coerce 의 대체, L-46).
- 행: `fetch_peek_arith` 는 캐시된 값을 돌려준다(fe:1316 탈착·fe:4465 재확정·fe:4603 원복 삭제). 답 3.5(현행). 같은 식이 `rand()` 를 품으면 VOLATILE 이라 캐시하지 않고 행마다 평가한다(R2).
- 평가 오류(#367): `cast(concat(?, '') as int) + 1` 에 `'abc'` 면 7단계 평가가 -181 을 낸다 — 행이 0개여도, 그 식이 행이 고르지 않는 CASE 가지에 있어도 실행 전이다(D-367-01). `case when ? = 0 then 0 else cast(concat(?, '') as int) + 1 end` 처럼 상수 조건의 가지 아래면 G1 끝에서 그 가드가 닿을 때만 낸다(D-367-07).

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
| BR-06·A61·CC-05 (#371) | 비교 항의 행 = 결정된 기록의 연산자별 leaf 1 호출(`eval_leaf_direct<op>`, perfmon·er_*·thread entry 없음); B-tree 검색 키 비교 = 스캔이 고른 비교기(`search_compare`); 보유값 읽기 = epoch 비교 1회 | and-30 M1/develop 0.97(C11 1.03); f2-in-k1024 비교 함수 self 샘플 develop 347 / C11 532 / D1 250; NL 조인 100×200 의 보유값 out-of-line 읽기 20,000 → 100 |
| ALLOC-01·03·04 (#371) | G1 은 임시 `TP_DOMAIN` 을 만들지 않고(`domain_value_domain`), 바꾸지 않는 값을 복사하지 않는다(공유 사본·이동); 같은 타입 키의 비교표 없음; 단일 컬럼 키 저장소 없음 | B-2 K=64 실행당 `tp_domain_new` 128→0, `mspace_malloc` 773→453; case-30 C11/develop 1.24 → M1 1.06 |
| MEM-02·05 (#371, R2-15) | `DOMAIN_COMPARE` hot/cold: 행 필드(leaves·cmp·conv·target·value·collation·kernel·coercion) 앞 64B, 80B; `DOMAIN_HELD_VALUE` epoch·converted·scope 앞 | `static_assert (sizeof, offsetof)` |
| BR-04·A59 (#372) | 행의 게이트 상태 접근자는 실행 불변(소유 실행·봉인)을 assert 하고 검사하지 않는다; 상수 참조의 바인드 위치·비교 자리의 바인드 쪽 표시는 로드가 고정한다(`const_ref_pos`, `DOMAIN_COMPARE_PLAN.bind`) | `in (?×30)` 실행당 명령 develop 대비 +40.1k → +31.2k (`6ad7627a5` → `ad62d1446`, 정확 계수 `312-372/pmu4`) |
| CC-05·A60·BR-08 (#372) | 변환 없는 사전 캐스트 = 타입 연산자 직접 호출(인라인), 사전 캐스트는 out of line; 해시 GROUP BY 키 비교는 한 타입이면 `tp_value_compare_with_error` 직접 | `SUM(c_int * ?) … GROUP BY` 실행당 −53.4M(develop 대비 1.053 → 1.036), top-N −25~28M, `SUM(?), AVG(?), MEDIAN(c_int + ?)` −29~31M (`ad62d1446` → `399b21df2`) |
| PRIORITY 1 (#372) | 한 range 의 key2 가 key1 과 같은 바인드·컬럼이면 key1 의 결정을 쓴다 — 같은 결정을 두 번 하지 않는다 | 결정·변환 카운터 불변(원소마다 셈, `t372-c2o` = `t372-o`) |

---

## 12. 결정 목록 (D-323-01~18 — #323 이 잠갔다; 뒤 티켓의 개정은 각 결정의 본문 절에 적었다)

| # | 결정 |
|---|---|
| D-323-01 | 골격 = 로드 1(`stx_build_domain_plan`) + 확정 1(`qexec_resolve_domains`, `qexec_execute_mainblock` 전) + 해제 1 + 읽기 전용 뷰 2(`REGU_RESOLVED_VALUE`/`RESOLVED`); 노드 8B = arena 항목 포인터. β 의 union/비팩 flags 비트 기각 |
| D-323-02 | 규칙 자리 = `domain_resolve`/`domain_lookup_converter`(ctx·needs_gate), 로드·게이트·키가 공용; 헤더 계약 §1.4 |
| D-323-03 | `qexec_resolve_domains` 뒤 `vd.dbval_ptr = vals`(1차 참조 = val_pos), 원 입력 `resolved.in` const; **소비자별**: fetch·partition 은 `ref` 로, 서브쿼리 결과 캐시 키·dblink 는 `resolved.in`(R3) |
| D-323-04 | 참조 = (val_pos, 도메인, 정책) 삼중 중복 제거; 표 항목 없음 |
| D-323-05 | `RESOLVED_DOMAIN {domain, conv[3], setdomain}` 40B(#328 D-328-03 이 `operand_domain[3]` 을 더해 64B); 실패 정책은 항목에; 표는 GATE·KEEP_LAZY·상수 키 range 만; 컴파일 확정 답은 항목 `fixed` 인라인 → 정적 계획 표 할당 0 |
| D-323-06 | PX = `qexec_deep_copy_xasl_state`/`qexec_free_xasl_state` 짝 하나(깊은 복사 범위 §1.2, 정렬 주장 없음), `owner` assert, 워커의 `qexec_resolve_domains` 금지, pxt:505·px_scan.cpp 직접 해제 경로 교체(R8) |
| D-323-07 | 술어 노드(`comp_eval_term` 등)는 항목 없음: 변환기는 피연산자 regu 항목, 비교 도메인은 KEEP_LAZY 슬롯/양 피연산자의 fixed — **개정(D-352-01, #352)**: 비교 항마다 비교 기록 하나를 항의 비직렬 포인터에 건다(로드의 결정, 또는 G1 이 채우는 게이트 칸); IN/SOME/ALL 은 원소 비교 기록(D-352-03) |
| D-323-08 | **G2·range 시점 결정 함수 없음**: 결정은 `qexec_execute_mainblock` 전 1회; mainblock 안은 읽기 전용 뷰 + 계획된 변환기 + 스코프 소유 실행 임시값(§3.4, 상관 값 스코프당 1회)과 혼합 setdomain 스크래치(§5, 결정·할당 0). 규칙표 P3 ③ "스코프당 1회" 는 §3.4 의 뜻 |
| D-323-09 | `ER_QPROC_DOMAIN_UNRESOLVED = -1383`, 예외 표 X-1~X-7 |
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
- **#371 실측(2026-09-28, dpin-18d)**: 판정 셀은 바인드 1·30개 OLTP 8개(`312-371/gen-probes-small.py`: pk-1·sel-1·nobind·in-30·pkand-30·and-30·case-30·upd-31; 사용자: 1000 바인드 셀은 판정에 쓰지 않는다). 방법: csql -S 를 namespace 에서 세 빌드 같은 런(`tools/fast-gate/fast-sa.sh`, 201회 중앙값, 부하 1 이하; 부하 20 이상의 런은 비율이 ±30% 흔들려 버린다 — MEAS-04), gdb 카운팅 브레이크포인트(R=1 vs R=2 의 차 = 실행당 호출 수, `312-371/count-calls.sh`; `@plt` 는 2회, `pr_clone_value` 는 3회로 센다), perf 는 overlay 경로 때문에 심볼이 안 풀려 `addr2line` 으로 오프라인 해석(`312-371/symbolize.py`) 또는 chroot 보고(`312-perf-gate/perf2/chroot-report.sh`). 결과(M2 `aa3b203ea`, release, develop 대비 중앙값 비율): pk-1 1.01 · sel-1 1.10(+1 µs) · nobind 1.13(+2 µs) · in-30 1.06(+13 µs) · pkand-30 1.01 · and-30 0.99 · case-30 1.05(+4 µs) · upd-31 1.03 (같은 런의 C11: 1.01 · 1.20 · 1.13 · 1.06 · 1.00 · 0.99 · 1.04 · 0.99); 리뷰 셀 f2-in 256/1024/4096 = 1.03/1.10/1.09, f2-lit 1.04, b2-case 64/128/256/512 = 1.09/1.06/1.07/1.06 (C11 1.07/1.13/1.13/1.06). csql 타이머는 1 µs 눈금이라 10~17 µs 문장(sel-1·nobind)의 6~10% 는 눈금이다. 남은 격차는 바인드·사이트당 게이트 결정 자체(in-30: 실행당 ~4.7 µs / 30 바인드; `id in (?x30)` 의 비교 사이트 30개는 MVCC 재평가용 `where_range` 항)와 실행당 고정비 ~1 µs(블록 할당·memset·clear). D-371-01(실행 간 결정 재사용 금지) 아래의 남은 후보는 같은 실행 안의 동일 (키,키) 결정 공유(≈0.5 µs)뿐이다. 근거 `312-371/m1/measure`·`312-371/small`.
- **#372 실측(2026-09-28, dpin-18e)**: 커밋마다의 효과는 정확 계수로 판정했다(csql -S 프로세스 전체를 `perf stat` 두 이벤트로, 1회/N회 차; 부하 98 에서도 같은 코드면 ±0.1%, 작은 탐침은 실행당 ±1~2k). 복사한 설치본은 실행 파일의 DT_RPATH 가 원래 빌드 경로를 가리켜 LD_LIBRARY_PATH 보다 먼저 그 경로의 **최신** 라이브러리를 읽는다 — 이전 커밋과의 A/B 는 잡의 mount namespace 에서 복사본의 lib 를 그 경로에 bind 하고 로드된 라이브러리 해시를 잡마다 적는다(`312-372/pmu4/perf-stat-sa3.sh`·`pmu-sa3.sh`·`check-lib.py`; 이 확인 전의 "① 효과 없음" 은 같은 빌드를 두 번 잰 것이었다). 이 호스트(Xeon Silver 4216, Cascade Lake)에서는 같은 소스의 시간이 기본 빌드와 `-falign-functions=64` 쌍 사이에서 5~15% 움직인다(top-N H= 1.100 → 0.949, `SUM(?), AVG(?)` L 1.053 → 1.014, pk-1 1.076 → 1.018): 기본 빌드에서만 넘는 셀은 배치 몫으로 적고 통과로 본다(사용자 2026-09-28). JCC 결함 분기 패딩(`-Wa,-mbranches-within-32B-boundaries`)은 MySQL·PostgreSQL·MariaDB·배포판의 release 기본값이 아니어서 쓰지 않는다 — 측정 빌드에도(사용자 2026-09-28); front-end 계수에서도 dpin 과 develop 의 legacy decoder 비율이 같았다(`312-372/pmu4/fe-*`). 결과(`399b21df2`, release, develop 대비 — 명령 수 · 기본 빌드 시간 · 정렬 쌍 시간): `SUM(c_int * ?) … GROUP BY` H= 1.036 · 1.111 · 1.103, 같은 문장 리터럴 1.083 · 1.050(시간만), case-30 1.03 · 1.098 · 1.068, in-30 1.026 · 1.064 · 1.053, nobind 1.018 · +1.0 µs · +1.0 µs; 넘는 네 셀(GROUP BY H=·L, case-30, in-30)은 #345 가 최종 헤드에서 다시 재고 정한다(D-372-09). 0.2~0.5 ms JDBC 셀(P5)은 다른 세션 부하(최대 98)로 판정하지 못했다.
- **#345 최종 측정(2026-09-28, D-345-02 — 닫음)**: 시간 대신 명령 수 비율로 판정했다(사용자 "명령 수 비율로만 측정하자"). 대상은 PR 머리 `c3b4dad4b`(카운터 삭제 뒤)와 develop `e1c3db198` 의 release 다. 벤치 셀 81 변형, 소형 8셀, P5 18 변형이 모두 develop 대비 +5% 이내다. 가장 큰 값은 P4-group H= 1.035·case-30 1.032·P5-eq 1.028·in-30 1.024 이고, H≠ 는 0.57~0.96 이다. 실행 1회가 작은 셀은 csql 메인 스레드만 센다(`perf stat --no-inherit`). 프로세스 전체를 세면 데몬 스레드 작업이 1회/N회 차에 ±15~45k 섞인다. 플랜 메모리는 로드 합 +50.3%(단순 조회 +9~10%, 2,000 바인드 INSERT +82.8%)다. MEAS-04/07 시간 A/B 는 하지 않는다. 표는 `domain-pin-bench-baseline.md` §6 이다.
- **#345 upstream shell 수정(2026-09-28, D-345-04~07)**: PR CUBRID/cubrid#8022 의 shell CI(debug)가 develop 이 통과하는 11 케이스를 실패했다. 캠페인 탓 7건은 엔진에서 고쳤다(`4abc28ea1`). ① 게이트의 -181 문구는 develop 이 오류를 내던 자리의 타입 순서를 따른다(D-345-05). 키 범위 항(where_range)은 상수 먼저다(로드가 `DOMAIN_COMPARE_PLAN.key_range` 를 표시한다). 무효 키 타입은 단일 컬럼 키면 값 먼저, 복합 키면 컬럼 먼저다. ② 출력 목록의 바인드는 공유 계획에서 다른 타입이 오면 G1 이 develop 의 튜플 캐스트(`tp_value_auto_cast`)로 한 번 바꾼다(`DOMAIN_PLAN_LIST_BIND`, `qexec_convert_list_bind`, D-345-06 — 규칙표 B33). 캐스트가 거부하면 그대로 두어 develop 처럼 행에서 오류가 난다. ③ 같은 precision 의 BIT 도 develop 처럼 coerce 한다(DBLink BIT(1) 값은 바이트 단위라 8비트를 든다, D-345-07). ④ 캐시 키 접미사 `;host_var_cnt=` 를 없앴다(D-345-04, 사용자 결정 (가), ADR 0021 정정 5). 나머지 4건은 승인된 명세 변경이라 private-ex `tc/pr-8022` 의 TC 를 고쳤다: `cbrd_25749`(PL 호출 5 → 4, #341 S-23), `bug_xdbms_sus18`(#367 (가) -834). `cbrd_20149_*` 3건은 plandump 의 메모리 줄이다(스트림의 인덱스 키 도메인 8바이트, 클론마다 `XASL_NODE` +16바이트로 10 KB·반올림 경계를 넘음). 게이트 E: optdebug·release sql 17482/17482 · medium 975/975, SA 128 IDENTICAL. PR CI 둘째 런 36406721542 는 sql·medium·shell 모두 통과했다.
