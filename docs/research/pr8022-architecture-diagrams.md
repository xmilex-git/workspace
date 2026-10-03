# PR #8022 구성도 — 기존(develop) 동작과 변경된 구조를 층별로 나란히

기준: [CUBRID/cubrid#8022](https://github.com/CUBRID/cubrid/pull/8022) HEAD `23a5e5561`(2026-10-03), 워크트리 `~/dev/cubrid-worktree/dpin`.
근거: ADR 0019~0024(2026-10-03 판), `domain-pin-architecture.md` §1, `pr8022-domain-state-guide.md`, `domain-pin-audit.md`(S-01~S-43), `domain-pin-exec-sites.md` §0. 함수·필드 이름은 전부 위 HEAD 의 코드에서 확인했다(`tools/code-index`). 용어는 `CONTEXT.md` 용어집("도메인·collation 사전 확정" 절)을 따른다.

읽는 순서: 1층(누가 언제 확정하나) → 2층(한 문장의 수명) → 3층(자료구조) → 4층(실행 전 도메인 확정의 내부) → 5층(행 경로 다섯 자리) → 6층(변환기·도메인 해석기 모듈) → 7층(미확정 도메인 오류). 층마다 **기존**(develop) 그림 하나, **변경**(PR 8022) 그림 하나다.

한 줄 요약: develop 은 **행 시점 확정** — "도메인을 실행 중에 행을 보고 정하고, 플랜 노드에 써 두었다가 끝나면 되돌린다". PR 8022 는 "컴파일과 **실행 전 도메인 확정** 두 곳에서만 확정하고, 확정은 실행 상태(`XASL_STATE`)에만 두며, 행은 읽기만 한다".

---

## 1층 — 큰 그림: 도메인은 누가, 언제 확정하나

### 기존 (develop)

```mermaid
flowchart LR
  subgraph C["클라이언트 컴파일"]
    C1["파서: 형제(컬럼·리터럴·CAST)가 있으면 도메인 확정<br/>없으면 DB_TYPE_VARIABLE"]
    C2["pt_make_regu_hostvar<br/>바인드 값이 이미 있으면 값 타입을 도메인으로 (플랜이 값에 종속)"]
    C3["pt_set_host_variables<br/>바인드 값을 기대 도메인으로 캐스트"]
  end
  subgraph L["서버 로드"]
    L1["stx_map_stream_to_xasl<br/>노드마다 original_domain = domain 보관"]
  end
  subgraph E["서버 실행 — 행 시점 확정 (43곳)"]
    E1["fetch: VARIABLE regu 도메인 ← 값 도메인"]
    E2["비교: 타입 다르면 상수를 제자리 coerce"]
    E3["리스트 파일: 첫 튜플로 컬럼 타입"]
    E4["집계: 첫 non-NULL 값으로 누산기 타입"]
    E5["인덱스 키: range 마다 strict coerce 시도"]
    E6["PX 워커: 각자 확정 후 루트로 역전파"]
  end
  subgraph X["실행 종료"]
    X1["qexec_clear_*: domain = original_domain 복원<br/>(클론을 다음 실행이 재사용하므로)"]
  end
  C --> L --> E --> X
```

### 변경 (PR 8022)

```mermaid
flowchart LR
  subgraph C["클라이언트 컴파일 = 확정 지점 1"]
    C1["파서: develop 과 같은 도메인<br/>기대 도메인이 없는 POS 는 가변 도메인 (tp_Variable_domain)"]
    C2["pt_make_regu_hostvar<br/>값 타입 → 도메인 단계 삭제 (플랜은 값에 종속되지 않음)"]
    C3["pt_set_host_variables 캐스트는 develop 그대로"]
  end
  subgraph L["서버 로드 도출 (확정 아님)"]
    L1["stx_build_domain_plan<br/>도메인 계획 DOMAIN_PLAN 을 1회 도출, 읽기 전용<br/>스트림 레이아웃 불변"]
  end
  subgraph G["실행 전 도메인 확정 = 확정 지점 2"]
    RS1["qexec_resolve_domains<br/>가변 도메인을 바인드 도메인으로 실행당 1회 확정<br/>결과는 확정 도메인 표 (XASL_STATE.resolved_domain) 에만"]
  end
  subgraph E["서버 실행 — 행은 읽기만"]
    E1["확정 읽기 + 확정 변환기 호출<br/>플랜 노드에 쓰지 않음"]
    E2["PX 워커: qexec_deep_copy_xasl_state 로 상속만"]
  end
  subgraph X["실행 종료"]
    X1["qexec_clear_resolved_domains<br/>실행 상태 해제 — 플랜 노드는 건드린 적이 없어 복원 없음"]
  end
  C --> L --> G --> E --> X
```

---

## 2층 — 한 문장의 수명

예시 문장: `SELECT sum(? + ?) FROM t WHERE c_str = ?`
- `? + ?` : 형제가 전부 POS 라 컴파일이 타입을 못 정하는 자리(문맥 없는 POS — 가변 POS)
- `c_str = ?` : 형제 `c_str` 이 기대 도메인을 주는 자리(고정 도메인, 클라이언트가 캐스트)

### 기존 (develop)

```mermaid
sequenceDiagram
  participant CL as 클라이언트 (파서/CAS)
  participant LD as 서버 로드 (stream_to_xasl)
  participant EX as qexec_execute_query
  participant ROW as 행 처리 (fetch/eval/agg)
  participant PX as PX 워커
  CL->>CL: 컴파일: ? + ? 의 두 ? 와 산술 결과, sum 은 DB_TYPE_VARIABLE
  CL->>CL: c_str = ? 의 ? 는 c_str 도메인, pt_set_host_variables 가 값을 캐스트
  CL->>LD: XASL 스트림 + 바인드 값
  LD->>LD: 노드마다 original_domain = domain
  LD->>EX: XASL 트리 (xcache 클론, 여러 실행이 공유)
  EX->>ROW: vd.dbval_ptr = 바인드 배열 그대로
  loop 행마다
    ROW->>ROW: fetch_peek_dbval_slow: VARIABLE regu->domain ← 값 도메인
    ROW->>ROW: fetch_peek_arith: 결과 값으로 arith->domain 재확정
    ROW->>ROW: 첫 non-NULL 값에서 qexec_resolve_domains_for_aggregation (sum 누산기 타입)
  end
  EX->>PX: 워커 클론 (복사 경로 둘)
  PX->>PX: 워커가 본 첫 값으로 집계 도메인 각자 확정
  PX-->>EX: opr_dbtype 역전파
  EX->>EX: qexec_clear_*: domain = original_domain 복원
```

### 변경 (PR 8022)

```mermaid
sequenceDiagram
  participant CL as 클라이언트 (파서/CAS)
  participant LD as 서버 로드 (stream_to_xasl)
  participant EX as qexec_execute_query
  participant G as qexec_resolve_domains (실행 전 도메인 확정)
  participant ROW as 행 처리
  participant PX as PX 워커
  CL->>CL: 컴파일: ? + ? 의 두 ? 와 산술 결과, sum 은 tp_Variable_domain (가변 도메인)
  CL->>CL: c_str = ? 는 develop 과 동일 (기대 도메인 + 클라이언트 캐스트)
  CL->>LD: XASL 스트림 + 바인드 값 (스트림 레이아웃 불변)
  LD->>LD: stx_build_domain_plan: 도메인 계획 도출, 노드는 plan_item 포인터만 받음
  LD->>EX: XASL 트리 + 불변 도메인 계획
  EX->>G: vd 형성 직후, mainblock 전, 실행당 1회
  G->>G: 값 배열 소유 (vals), 두 가변 POS 의 도메인 ← 바인드 도메인
  G->>G: 늦은 바인딩 노드 생산자 순: ? + ? 결과 → sum 누산기 (domain_resolve 타입 규칙)
  G-->>EX: 확정 도메인 표 (XASL_STATE.resolved_domain) 채움 (실패는 실행 전 오류)
  EX->>ROW: qexec_execute_mainblock
  loop 행마다
    ROW->>ROW: item->fixed 또는 qexec_late_bind_domain 으로 확정 읽기
    ROW->>ROW: 확정 변환기 (tp_value_convert) 로 피연산자 변환, 누산
  end
  EX->>PX: qexec_deep_copy_xasl_state (확정 도메인 표 깊은 복사, 경로 하나)
  PX->>PX: 확정 0, 역전파 0 — 상속한 확정으로 행 처리
  EX->>EX: qexec_clear_resolved_domains
```

---

## 3층 — 자료구조: 플랜 노드와 실행 상태

### 기존 (develop)

```mermaid
flowchart TB
  subgraph CLONE["XASL 클론 (xcache — 여러 실행이 공유하는데 실행이 쓴다)"]
    R["REGU_VARIABLE<br/>domain ← 실행이 덮어씀<br/>original_domain ← 로드가 보관<br/>flags: FETCH_ALL_CONST 등 실행 중 기록"]
    A["ARITH_TYPE<br/>domain / original_domain"]
    AG["AGGREGATE_TYPE / ANALYTIC_TYPE<br/>domain / original_domain<br/>opr_dbtype / original_opr_dbtype"]
    P["QFILE_TUPLE_VALUE_POSITION<br/>dom / original_domain"]
  end
  subgraph ST["XASL_STATE (실행당)"]
    VD["VAL_DESCR vd<br/>dbval_ptr = 바인드 배열 그대로 (const 캐스트)<br/>SA_MODE 에서는 클라이언트 parser->host_variables 자체"]
  end
  ROW["행 처리"] -- "값을 보고 domain 에 쓴다" --> R
  ROW -- "첫 non-NULL 값으로 쓴다" --> AG
  ROW -- "첫 튜플로 쓴다" --> P
  CLR["qexec_clear_* (실행 종료)"] -- "domain = original_domain" --> R
  CLR --> A
  CLR --> AG
  CLR --> P
```

### 변경 (PR 8022)

```mermaid
flowchart TB
  subgraph CLONE["XASL 클론 (불변 — 실행이 쓰지 않는다)"]
    R["REGU_VARIABLE<br/>domain = 컴파일 도메인 (그대로)<br/>plan_item → DOMAIN_PLAN_ITEM (스트림에 없음)"]
    A["ARITH_TYPE<br/>plan_item"]
    AG["AGGREGATE_TYPE / ANALYTIC_TYPE<br/>plan_item (original_* 필드 삭제)"]
    IX["INDX_INFO<br/>key_type (새 스트림 항목, 디스크 포맷 아님)<br/>key_plan → domain_plan_index"]
    ROOT["XASL_NODE 루트<br/>domain_plan → DOMAIN_PLAN"]
  end
  subgraph PLAN["도메인 계획 DOMAIN_PLAN — unpack arena, 로드 도출 1회, 읽기 전용"]
    IT["items[]: 도메인 계획 항목 DOMAIN_PLAN_ITEM<br/>fixed: 고정 도메인의 답 + 확정 변환기<br/>resolved_index / ref / node_domain_index / flags"]
    LB["late_bind_nodes[]<br/>실행 전 확정이 정할 늦은 바인딩 노드, 생산자 우선 순서"]
    CP["compares[] / element_comparisons[]<br/>확정 비교 계획"]
    KI["indexes[]: domain_plan_index<br/>bound 마다 컬럼 규칙 INDEX / STRICT / KEEP / CONSTANT / LATE_BIND"]
    CE["constant_expressions[] / session_variables[] / constant_branches[]"]
  end
  subgraph ST["XASL_STATE (실행당, 만든 스레드가 해제)"]
    VD["VAL_DESCR vd<br/>dbval_ptr → resolved_domain.vals"]
    RD["확정 도메인 표 resolved_domain: RESOLVED_DOMAIN_TABLE<br/>in = 원 바인드 (빌림, 불변) / vals = 실행용 값<br/>domains[] compares[] elements[] indexes[]<br/>frozen / owner / plan"]
    DE["실행 도메인 domain_execution: DOMAIN_EXECUTION_STATE<br/>node_domains[] operand_types[] interpolation_list_domains[]<br/>temporaries[] (실행 임시값: 상관 scope 변환 캐시)"]
  end
  R --> IT
  A --> IT
  AG --> IT
  IX --> KI
  ROOT --> PLAN
  IT -- "resolved_index" --> RD
  IT -- "node_domain_index" --> DE
  IT -- "ref" --> VD
```

핵심 차이: develop 은 "노드 필드 = 실행 상태" 라서 공유 클론에 쓰고 되돌려야 했다. PR 은 노드에 **불변 도메인 계획 포인터**만 두고, 실행별 답은 `XASL_STATE` 두 멤버(확정 도메인 표 · 실행 도메인)에 둔다. 같은 번호(`resolved_index`, `ref`, `node_domain_index`)로 세 배열을 찾는다.

---

## 4층 — 실행 전 도메인 확정의 내부

### 기존 (develop) — 실행 전 확정 단계가 없고, 같은 확정이 실행 하위에 흩어져 있다(행 시점 확정)

```mermaid
flowchart TB
  Q["qexec_execute_query<br/>vd.dbval_ptr = 바인드 배열"] --> M["qexec_execute_mainblock"]
  M --> F["행당: fetch_peek_dbval_slow / fetch_peek_arith<br/>VARIABLE 도메인 ← 값 도메인 (탈착 → 재확정 → 오류면 원복)"]
  M --> CMP["행당: eval_value_rel_cmp<br/>값 타입 분기 + 상수 제자리 coerce + 힙 전환"]
  M --> LF["첫 튜플: qfile_update_domains_on_type_list<br/>리스트 컬럼 ← outptr regu 도메인 (미해결이면 다음 튜플 재시도)"]
  M --> AGG["첫 non-NULL 값까지 행당: qexec_resolve_domains_for_aggregation<br/>누산기 타입, MEDIAN 은 DOUBLE → DATETIME → TIME 시도 캐스트"]
  M --> PASS["패스당: qexec_resolve_domains_on_sort_list / _for_group_by<br/>analytic resolve_domain 블록 / resolve_domains_on_list_scan"]
  M --> KEY["range 당: scan_dbvals_to_midxkey<br/>strict coerce 실패 → 값 도메인 setdomain 을 prebuilt_midxkey_domains 에 캐시"]
  M --> PXW["워커별: 집계 각자 확정 → 루트 역전파"]
  F & CMP & LF & AGG & PASS & KEY & PXW --> END["qexec_clear_*: original_domain 복원"]
```

### 변경 (PR 8022) — `qexec_resolve_domains` 한 곳, 단계 순서 고정(단계는 함수 이름으로 부른다)

```mermaid
flowchart TB
  Q["qexec_execute_query<br/>vd 형성 직후"] --> G0["qexec_resolve_domains (실행당 1회)"]
  G0 --> S1["qexec_init_resolved_domains<br/>값·확정 블록 1개 할당, in 보존, vd.dbval_ptr → vals"]
  S1 --> S2["qexec_share_value<br/>POS 참조마다 값 공유, 가변 POS 의 도메인 ← 바인드 도메인"]
  S2 --> S4["qexec_resolve_late_bind_node (생산자 우선)<br/>늦은 바인딩 노드 → domain_resolve 타입 규칙<br/>(산술 결과 → 누산기 → 정렬 키 순)"]
  S4 --> S5["qexec_resolve_compare / qexec_resolve_elements<br/>확정 비교·IN/ALL/SOME 원소<br/>상수 쪽은 1회 변환해 자기 값 자리에"]
  S5 --> S6["frozen = true<br/>이제부터 값·확정을 읽어도 된다"]
  S6 --> S7["qexec_evaluate_constant_expression<br/>상수식 1회 평가, 그 값을 기다리던 노드·비교 확정"]
  S7 --> S7b["qexec_resolve_session_variables<br/>세션변수 문장 타입, 다른 타입 대입 → ER_QPROC_SESSION_VARIABLE_TYPE (-1384)"]
  S7b --> S8["qexec_resolve_index_keys<br/>인덱스 키 CONSTANT 원소 변환 또는 원형 유지, 키 비교 표"]
  S8 --> SE["qexec_raise_deferred_errors<br/>상수 가지 아래 미룬 상수 오류: 상수 조건상 도달 가능하면 실행 전 오류"]
  SE --> M["qexec_execute_mainblock<br/>행 처리는 읽기만"]
  M --> END["qexec_clear_resolved_domains"]
```

대응표 — 실행 전 확정의 단계(함수)가 develop 의 어느 행 시점 확정 자리를 대체했나:

| 실행 전 확정의 단계 | develop 에서 같은 확정을 하던 자리 (감사표 ID) |
|---|---|
| `qexec_share_value` — 가변 POS 의 도메인 ← 바인드 도메인 | `fetch_peek_dbval_slow` S-05, REGUVAL_LIST S-06 |
| `qexec_resolve_late_bind_node` — 늦은 바인딩 노드 | `fetch_peek_arith` S-01~S-04, 집계 첫값 S-23·S-26~S-28, 리스트·정렬·GROUP BY S-13~S-20, 해시 조인 키 S-22 |
| `qexec_resolve_compare` / `qexec_resolve_elements` — 확정 비교 | `eval_value_rel_cmp` S-09·S-10, top-N S-11 |
| `qexec_evaluate_constant_expression` — 상수식 | `FETCH_ALL_CONST` 제자리 coerce + 힙 전환 S-09·S-39 |
| `qexec_resolve_session_variables` — 세션변수 문장 타입 | `T_EVALUATE_VARIABLE` 저장값 타입 S-07 |
| `qexec_resolve_index_keys` — 인덱스 키 | `scan_dbvals_to_midxkey` S-30, ISS S-31, MRO S-32, `btree_compare_key` 폴백 S-12 |
| (PX 상속 `qexec_copy_resolved_domains`) | 워커 확정·역전파 S-34~S-37 |
| (복원 삭제) | `qexec_clear_*` + `original_domain` S-38 |

---

## 5층 — 행 경로 다섯 자리

### 5-a 산술 fetch

**기존 (develop)**

```mermaid
flowchart LR
  V["피연산자 값 fetch"] --> D{"regu->domain 이<br/>VARIABLE?"}
  D -- "예" --> W["regu->domain ← 값 도메인<br/>(fetch_peek_dbval_slow)"]
  D -- "아니오" --> N["그대로"]
  W --> AR["fetch_peek_arith<br/>arith->domain 탈착 (NULL)"]
  N --> AR
  AR --> OP["qdata_add_dbval 등<br/>값 타입 dispatch 로 피연산자 교차 캐스트"]
  OP --> RF["결과 값으로 arith->domain 재확정"]
  RF --> ERR{"오류?"}
  ERR -- "예" --> RS["arith->domain 원복"]
```

**변경 (PR 8022)**

```mermaid
flowchart LR
  V["피연산자 값 (vals[ref])"] --> I["arith->plan_item (도메인 계획 항목)"]
  I --> D{"item.resolved_index<br/>있음?"}
  D -- "아니오: 고정 도메인" --> FX["item->fixed<br/>domain + conv[] + operand_domain[]"]
  D -- "예: 실행 전 확정" --> LB["qexec_late_bind_domain<br/>resolved_domain.domains[idx]"]
  FX --> AB["fetch_arith_binary<br/>확정 변환기로 피연산자 변환 (tp_value_convert)"]
  LB --> AB
  AB --> OP["qdata_add_dbval 등<br/>한 타입 안의 연산만 (교차 캐스트 없음)"]
  OP --> R["결과 — 노드 도메인에 쓰지 않음"]
  OP -. "확정 없는 값이 오면" .-> B["assert + ER_QPROC_DOMAIN_UNRESOLVED (-1383)"]
```

### 5-b 비교

**기존 (develop)**

```mermaid
flowchart LR
  L["lhs 값"] --> C["eval_value_rel_cmp"]
  R["rhs 값"] --> C
  C --> T{"두 값 타입이<br/>같은가?"}
  T -- "아니오, rhs 가 상수" --> CO["tp_value_coerce 제자리<br/>숫자·문자 → DOUBLE, 문자 → 날짜 …<br/>클론 공유 상수면 힙 전환"]
  T -- "아니오" --> CW["tp_value_compare_with_error (do_coercion=1)<br/>행마다 임시 변환"]
  T -- "예" --> CV["cmpval"]
  CO --> CV
  CW --> CV
```

**변경 (PR 8022)**

```mermaid
flowchart LR
  P["확정 비교 계획 DOMAIN_COMPARE_PLAN (로드 도출)"] --> M{"fixed.method"}
  M -- "DIRECT / CONVERT / COLLATIONS …" --> FC["로드가 확정한 DOMAIN_COMPARE"]
  M -- "LATE_BIND" --> GC["qexec_resolve_compare 가 채운<br/>resolved_domain.compares[compare_index]"]
  G["실행 전 확정: 상수 쪽은 1회 변환해 value[side] 에"] -.-> GC
  FC --> E["eval_compare_term (행)"]
  GC --> E
  E --> OF{"operator_functions<br/>있음?"}
  OF -- "예 (DIRECT)" --> DF["비교 연산자 함수 직접 호출"]
  OF -- "아니오" --> CV["conv[side] 로 변환 → cmp->cmpval"]
```

### 5-c 집계와 리스트 파일

**기존 (develop)**

```mermaid
flowchart TB
  S["스캔 시작"] --> R1["행 1: 값이 NULL → 미해결, 다음 행에서 재시도"]
  R1 --> R2["행 k: 첫 non-NULL 값<br/>qexec_resolve_domains_for_aggregation<br/>agg->domain, opr_dbtype, 누산기 도메인 확정"]
  R2 --> L1["리스트 파일: 첫 튜플에서<br/>qfile_update_domains_on_type_list"]
  L1 --> U["집합연산·CTE: qfile_unify_types<br/>한쪽 리스트가 VARIABLE 이면 상대 도메인 채택"]
  R2 -. "행이 하나도 없으면" .-> NO["도메인 미확정으로 종료<br/>결과 타입이 데이터에 따라 달라짐"]
```

**변경 (PR 8022)**

```mermaid
flowchart TB
  G["실행 전 확정: 집계 결과·누산기 도메인 확정<br/>(확정 도메인 표, 행 0개여도 같은 타입)"] --> SU["첫 행 전: qexec_setup_aggregate_domains<br/>블록의 모든 집계 셋업 (전부 아니면 전무)"]
  SU --> OC["SUM/AVG: DOMAIN_OPERAND_COERCION<br/>피연산자 확정 변환기를 셋업 때 고정"]
  SU --> LF["리스트 파일: qdata_get_valptr_type_list<br/>열 때 계획 도메인으로 타입 확정 (첫 튜플 대기 없음)"]
  LF --> U["집합연산·CTE 가지 타입 불일치<br/>→ 실행 전 ER_QPROC_INCOMPATIBLE_TYPES (-456)"]
  SU --> ROW["행: 누산만 (도메인 확정 0)"]
```

### 5-d 인덱스 키

**기존 (develop)**

```mermaid
flowchart TB
  O["range 생성 (scan_get_index_oidset)<br/>상관·조인 키는 외부 행마다 반복"] --> MK["scan_dbvals_to_midxkey"]
  MK --> SC{"tp_value_coerce_strict<br/>인덱스 컬럼 도메인으로"}
  SC -- "성공" --> IDX["인덱스 도메인 키"]
  SC -- "실패 / NUMERIC·CHAR 비정확 일치" --> ND["need_new_setdomain<br/>값 도메인으로 setdomain 생성<br/>prebuilt_midxkey_domains[range] 에 캐시"]
  IDX --> BT["btree_compare_key"]
  ND --> BT
  BT --> FB{"비교 불가 조합?"}
  FB -- "예" --> TV["tp_value_compare_with_error 폴백 (키당)"]
```

**변경 (PR 8022)**

```mermaid
flowchart TB
  L["로드 도출: INDX_INFO.key_type → domain_plan_index<br/>bound 의 컬럼마다 rule: INDEX / STRICT / KEEP / CONSTANT / LATE_BIND"] --> G["qexec_resolve_index_keys (실행 전 확정)<br/>CONSTANT 원소 1회 변환 또는 원형 유지<br/>LATE_BIND 원소의 규칙 확정, 키 비교 표"]
  G --> SO["스캔 open: BTID_INT.search_keys / search_compare 선택<br/>OWN = cmpval 직접, OTHER = 타입 쌍 비교 표"]
  SO --> RO["range open: scan_key_column<br/>컬럼마다 계획 규칙 적용 — 값 변환만, 재추론 0"]
  RO --> BT["btree_compare_key → domain_search_key_compare"]
  BT -. "표에 없는 쌍" .-> B["assert + -1383"]
```

### 5-e PX 워커

**기존 (develop)**

```mermaid
flowchart LR
  ROOT["루트 XASL_STATE"] --> C1["qexec_deep_copy_xasl_state<br/>(px_query_task)"]
  ROOT --> C2["px_scan_task: memcpy(m_vd) + clone 루프<br/>같은 복사를 따로 구현 (경로 둘)"]
  C1 --> W["워커 클론"]
  C2 --> W
  W --> WR["워커가 본 첫 값으로 집계 도메인 확정<br/>update_domains_on_type_list_by_val_list (atomic store)"]
  WR -- "opr_dbtype 역전파" --> ROOT
```

**변경 (PR 8022)**

```mermaid
flowchart LR
  ROOT["루트 XASL_STATE<br/>확정 도메인 표 채워짐 (실행 전 확정 뒤)"] --> C["qexec_deep_copy_xasl_state (경로 하나)<br/>→ qexec_copy_resolved_domains"]
  C --> W["워커 XASL_STATE<br/>domains / compares 복사, vals 는 워커 소유 clone<br/>plan · in 은 빌린 포인터, 실행 임시값은 빈 캐시"]
  W --> WR["워커 행 처리: 확정 0, 역전파 0"]
  W --> F["qexec_free_xasl_state<br/>워커가 자기 사본을 자기가 해제"]
```

---

## 6층 — 변환기와 도메인 해석기 모듈 (ADR 0022·0023·0024)

### 기존 (develop) — 같은 규칙이 여러 코드에 따로 산다

```mermaid
flowchart TB
  subgraph OD["object_domain.c"]
    A["tp_value_cast_internal<br/>목표 타입 switch → 원 타입 switch (수천 줄)"]
    B["tp_value_coerce_strict<br/>별도 switch 로 같은 쌍을 다시 구현"]
  end
  subgraph EXE["실행 하위 (fetch / qdata / qexec / scan / btree)"]
    C["qdata_*_dbval: 값 타입 dispatch 로 교차 캐스트"]
    D["tp_value_compare_with_error: 비교 변환 순서"]
    E["scan_dbvals_to_midxkey: 키 strict 시도"]
    F["산술·공통값·집계·collation 타입 규칙이 fetch/qexec 에 흩어짐"]
  end
```

### 변경 (PR 8022) — 변환기 한 벌, 도메인 해석기 한 모듈

```mermaid
flowchart TB
  subgraph CONV["object_domain_convert.cpp — 변환기"]
    FIND["tp_value_find_converter(src, target, mode)<br/>변환 모드: ASSIGN / IMPLICIT / COMPARE / OPERAND"]
    LEAF["쌍마다 이름 있는 변환기<br/>tp_value_convert_char_to_date 등<br/>숫자 쌍은 tp_value_convert_number 템플릿 한 벌"]
    FIND --> LEAF
  end
  CAST["tp_value_cast_internal (클라이언트 캐스트도 여기)"] --> FIND
  STRICT["tp_value_coerce_strict"] --> FIND
  subgraph RULES["domain_rules.c — 서버 도메인 해석기 (query/ 전용)"]
    RES["domain_resolve(ctx, opcode, operands)<br/>산술·공통값·집계·collation 병합 타입 규칙"]
    CMPR["domain_resolve_comparison<br/>모든 비교 확정 = 타입 쌍 비교 표의 칸"]
    KEYC["domain_search_key_compare<br/>B-tree 검색 키 비교"]
  end
  LOAD["로드 도출: stx_build_domain_plan"] --> RES
  LOAD --> CMPR
  GATE["실행 전 도메인 확정: qexec_resolve_domains"] --> RES
  GATE --> CMPR
  RES --> FIND
  CMPR --> FIND
  ROW["행 처리"] -- "항목에 고정된 포인터만 호출<br/>tp_value_convert" --> LEAF
```

요점: 로드 도출·실행 전 확정만 `tp_value_find_converter` 를 조회하고, 행 루프는 도메인 계획 항목에 고정된 함수 포인터(확정 변환기)를 부른다. 클라이언트 캐스트와 실행 전 확정이 **같은 변환기**를 부르므로 규칙이 두 벌이 되지 않는다.

---

## 7층 — 미확정 도메인 오류: 확정 없이 행에 도달하면

| 자리 | 기존 (develop) | 변경 (PR 8022) |
|---|---|---|
| 로드: 필터·함수 인덱스 스트림에 가변 POS 가 있으면 | 그대로 로드, `fpcache_claim` 이 오류를 삼킴 | `stx_index_stream_rejected` 로 로드 거부(-1383), 오류 전파 |
| 행: 확정 없는 가변 도메인을 만나면 | 값에서 도메인을 정해 계속(행 시점 확정) | optdebug `assert` + release `ER_QPROC_DOMAIN_UNRESOLVED`(-1383). 재컴파일 트리거에 넣지 않아 위반이 숨지 않음 |
| 세션변수: 문장 안에서 다른 타입 대입 | 읽기마다 저장값 타입 | 실행 전 확정(`qexec_resolve_session_variables`)이 실행 전 `ER_QPROC_SESSION_VARIABLE_TYPE`(-1384) |
| 집합연산·CTE 가지 타입 불일치 | 두 가지 모두 행이 있을 때만 -456, 한쪽이 비면 다른 쪽 타입 채택 | 실행 전 확정이 -456 |

---

## 용어 메모

- 이 문서의 용어는 `CONTEXT.md` 용어집을 따른다: **실행 전 도메인 확정**(`qexec_resolve_domains`), **가변 POS**·**문맥 없는 POS**, **고정/가변 도메인**, **로드 도출**, **도메인 계획**(`DOMAIN_PLAN`)·**도메인 계획 항목**(`DOMAIN_PLAN_ITEM`), **확정 도메인 표**(`XASL_STATE.resolved_domain`), **실행 도메인**(`XASL_STATE.domain_execution`), **실행 임시값**, **늦은 바인딩 노드**, **확정 변환기**·**변환기**·**변환 모드**, **확정 비교**·**비교 연산자 함수**·**검색 키 비교기**, **상수 오류**·**상수 가지**, **세션변수 문장 타입**, **미확정 도메인 오류**, develop 기법은 **행 시점 확정**. 2026-09-29 이전 기록의 옛 이름(게이트·G1·G2·슬롯·게이트 표·게이트 의존 노드·계획된 변환기·셀 함수·leaf·경계 (a)/(b))은 용어집 각 항목의 _Avoid_ 줄에 대응이 있다.
- 컴파일은 가변 도메인 자리에 도메인 자체를 `tp_Variable_domain` 으로 두고(`pt_make_regu_hostvar`), 로드 도출이 `REGU_VARIABLE_VARIABLE_DOMAIN`(0x8000, 스트림에 없음)과 `DOMAIN_PLAN_LATE_BIND` 항목 플래그를 도출한다. 클라이언트 캐스트(`pt_set_host_variables`)는 develop 그대로다(ADR 0021).
- mainblock 안에서 다시 확정하는 단계는 없다. 상관 값의 scope 변환은 실행 임시값(`domain_execution.temporaries[]`)이 첫 사용 때 1회 변환하는 것으로 대신한다(ADR 0020).
