# 도메인 계획 로드 도출

지도: [도메인·collation 사전 확정](https://github.com/xmilex-git/workspace/issues/312)
티켓: [로드 도출: DOMAIN_PLAN·피연산자 부류·참조 자리·qdump](https://github.com/xmilex-git/workspace/issues/331)

엔진 커밋: [`47ad86216`](https://github.com/xmilex-git/cubrid/commit/47ad86216a3d075498690a861eef47cb9fbf39db), `fork/dpin`에 푸시.
수용 TC는 기존 `301de3f633fb6b9d26276535e4f9d4f7ae4b0956`이며 답안·TC 변경은 없다.

## 계약과 구현 경계

ADR 0020과 D-323-01·04·05·07·09·11·13·14·15·18, D-325-01·02·09,
D-328-02·03·04를 적용한다. 인터페이스 문서의 초판 64B 제한은 **D-328-03의
80B 항목**으로 대체되었다. `fixed.operand_domain[3]`는 결과 도메인과 별도다.
`original_domain` 및 `original_opr_dbtype`의 제거는 승인된 마지막 삭제 단계까지 미룬다.

- `stx_map_stream_to_xasl`이 헤더의 `dbval_cnt`를 복원한 후 한 번 도출한다.
  캐시 클론·비캐시·PX 언팩이 같은 진입점을 사용한다. 실행 재사용 경로에는 도출 호출을 추가하지 않는다.
- XASL 하위 블록, 접근 명세, 술어의 피연산자, 산술·함수, 집계·분석, 위치 서술자를 순회한다.
  술어 자체의 스트림 구조는 바꾸지 않는다. 공유 XASL은 진입 때 표시하고 식은 피연산자부터 도출한다.
- 실행 계획과 콜드 자료는 unpack arena에 들어간다. 도출 중의 레코드와 연결 자료는 게시 전에 해제한다.
  기존 노드에는 비직렬화 포인터만 추가한다. 캐스트나 실행 플래그를 변경하지 않는다.
  unpack 복원과 `xasl_regu_alloc.cpp`의 생성 초기화 양쪽에서 포인터를 NULL로 초기화하여
  SA의 컴파일 직후 덤프도 미초기화 포인터를 읽지 않는다.
- 값의 부류는 CONST/ROW/CORR/VOLATILE이며, 현재 블록의 값 목록과 복원된 값의 동일성으로
  로컬 행 값과 외부 값을 구분한다. `FETCH_NOT_CONST` 연산자와 그 부모 식은 VOLATILE이다.
  현재 소스의 `T_CASE` 및 무조건 비상수인 컬렉션·generic·benchmark 함수도 포함한다.
- 바인드 참조는 `(val_pos, 목표 도메인, 실패 정책)`을 기준으로 중복을 제거한다.
  정렬 키와 출력의 별칭은 생산자 계획을 참조하며, 소비자 속성이 다르면 별도 항목을 유지한다.
- 고정 변환기는 서버 전용 문맥→모드 어댑터를 통해 직전 티켓의 정적 표에서 조회한다.
  산술 결과 도메인을 각 피연산자 목표로 잘못 사용하는 변환은 만들지 않는다.
  값 의존 격자 이관과 실행 게이트는 후속 티켓이다.
- 로드 예외 X-1~X-7과 경계 검사 함수는 준비하되 호출 조건은 `false`다.
  아직 컴파일러가 GATE 비트를 내보내지 않으므로 실제 계획의 게이트 슬롯은 0이어야 한다.
- 관찰은 qdump에 추가한다. 현재 소스에서 regu를 인쇄하는 함수 이름은
  `qdump_print_value`다(티켓의 `qdump_print_regu_variable`에 해당).
  `SHOW TRACE` 및 클라이언트 `SHOW PLAN` 계약은 유지한다.
  X-4의 `TYPE_INST_NUM`은 현재 `REGU_DATATYPE`에 없으며, 실제 존재하는
  `TYPE_LIST_ID`/`TYPE_ORDERBY_NUM`을 제외한다. 문서의 `TYPE_FUNCTION`은 실제 `TYPE_FUNC`다.

## 검증

### 정적 확인

- `domain_plan.h` / `domain_resolver.h`에서 도달하는 로컬 헤더 6개, 순환 0개,
  금지된 parser·compat API·broker·method 헤더 0개. 허용된 `dbtype_def.h`는 제외한다.
  재현 스크립트와 JSON: `.git_ignored_dir/scratch/312-331/check-include-graph.py`, `include-graph.json`.
- leaf 구현 헤더는 어댑터 `domain_resolver.c`만 포함한다. 계획 헤더에는 XASL·regu 완전형을 포함하지 않는다.
- `original_domain` / `original_opr_dbtype`와 기존 팩 형식은 유지한다.
  경계 (a)는 `domain_plan_check_load = false`; 실행 루프와 SHOW TRACE의 변경은 없다.
- D-323-13의 `domain_plan_acc` 이름은 기존 `original_opr_dbtype`를 최종 삭제할 때의 이름이다.
  이번에는 원 필드를 유지하고 주 집계·분석 항목의 비직렬화 포인터를 추가한다.
- 임시 도출 목록은 로드 중에만 할당·해제한다. 참조·생산자 별칭의 검색은 로드 시 선형 탐색이며,
  전체 도출 비용은 최악의 경우 제곱으로 증가할 수 있다. 이 티켓은 로드 속도 개선을 주장하지 않는다.

### 실행 확인

최종 r2 소스로 optdebug / release(RelWithDebInfo) 빌드·설치가 통과했다.
14개 변경 파일의 SHA256은 빌드 전후 manifest와 일치한다.

- 빌드 로그: `runtime/r2/{optdebug,release}-build-r2-20260923T024223.log`.
- 소스 manifest: `runtime/r2/source-r2-{before,after}-20260923T024223.sha256`.
- `SERVER_MODE` / `SA_MODE`에서 두 헤더의 단독 포함 컴파일 통과.
  실측: `sizeof(DOMAIN_PLAN_ITEM)=80`, `offsetof(fixed)=16`,
  `sizeof(RESOLVED_DOMAIN)=64`, `sizeof(DOMAIN_PLAN_ITEM_COLD)=32`, `sizeof(DOMAIN_PLAN)=96`.
  로그: `runtime/headers/header-standalone-20260922T170937Z.log`.
  r2는 헤더·레이아웃을 변경하지 않았다.
- 공개 CTP는 `TC_REF=dpin-tc`, SHA `301de3f633fb6b9d26276535e4f9d4f7ae4b0956`로 실행했다.

| 최종 범위 | 런 ID | 결과 |
|---|---|---|
| SQL 전수 | `sql-20260922T174418Z-1328054` | 17,468/17,468 OK, NOK/core 0 |
| medium | `medium-20260922T174938Z-1353990` | 975/975 OK, NOK/core 0 |

런 루트는 `/home/cubrid/ctp-run-out/workspace/`이다. SQL은 7 shards, medium은 1 shard다.
직전 티켓의 기준 런은 SQL `sql-20260922T152708Z-1166364`,
medium `medium-20260922T152643Z-1163733`이다. 양 suite 전체 case→결과 mapping의
**missing=0, extra=0, changed=0**이며, 최종 console의 crash/assert 표식과 core도 0이다.
증거는 `runtime/r2/ctp-parent-candidate-case-mapping-20260923T025414.{json,txt}`와
`runtime/r2/final-assert-marker-scan-r2-20260923T025414.txt`다.

r1도 집중 SQL 523개·SQL 전수 17,468개·medium 975개를 통과했으나,
메타데이터 관측에서 로컬 집계·분석 결과의 부류를 보완하여 최종 r2 전수 검증을 다시 수행했다.
중간 성공 런과 관측 실패의 증거를 삭제하지 않았다.

### 카운터 불변

같은 DB에서 부모와 후보를 순서대로 실행했다. 실제 parallelism=0/24,
max_parallel_workers=100을 확인했다. 81변형 × 5회, **405/405개 키와 결과 행 수,
9종 카운터가 모두 일치**한다(순차 375 + 병렬 30). 아래 합계와 최댓값은 양쪽이 같다.

| 카운터 | 405회 합계 | 최댓값 | 차이 난 측정 수 |
|---|---:|---:|---:|
| `Num_domain_resolve_fetch` | 565 | 13 | 0 |
| `Num_domain_coerce_compare` | 169,708,265 | 9,955,000 | 0 |
| `Num_domain_resolve_list` | 200,265 | 20,008 | 0 |
| `Num_domain_resolve_agg` | 440 | 6 | 0 |
| `Num_domain_key_coerce` | 109,155 | 10,374 | 0 |
| `Num_domain_px_resolve` | 200 | 8 | 0 |
| `Num_domain_restore_clone` | 1,120 | 27 | 0 |
| `Num_domain_gate_convert` | 0 | 0 | 0 |
| `Num_planned_convert` | 0 | 0 | 0 |

최종 r2 증거: `counters/r2/counter-comparison.{json,txt}`, `counters/r2/loader-provenance.txt`,
`counters/r2/assert-core-evidence.txt`. 유효 최종 실행의 core/assert/stderr 오류 0.
`counters/r2/loader-runtime-check.txt`로 부모와 후보가 각각 자기 라이브러리를 로드함을 확인했다.
config staging은 컨테이너 overlay에서만 이루어졌으며 원본 config는 불변이다.
처음 시도는 소켓 경로가 읽기 전용 mount 아래에 있어 서버 시작 단계에서 실패했으며 측정 행이 없다.
`counters/failed-attempt1/`에 보존하고 성공 근거에서 제외했다.

### 실제 로드 계획과 arena

읽기 전용 GDB 관측으로 단순 스캔·산술·조인·GROUP BY·집계·분석·상관·난수·VALUES의
10개 로드 계획을 확인했다. 최종 r2 총 71개 항목에서 CONST 15, ROW 49, CORR 5, VOLATILE 2를
관측했고 모든 계획의 `n_slots=0`, `n_gate_nodes=0`이었다.

| 계획 | 항목 수 | 새 계획 배열 요청 바이트 |
|---|---:|---:|
| 단순 스캔 | 5 | 664 |
| 산술 | 8 | 1,000 |
| 조인 | 13 | 1,560 |
| GROUP BY | 6 | 776 |
| 집계 | 5 | 656 |
| 분석 | 8 | 1,000 |
| 상관 | 10 | 1,224 |
| 난수 | 4 | 568 |
| VALUES | 6 | 800 |
| VALUES + CAST | 6 | 800 |

요청량 = `96 + n_items*(80+32) + 8*(n_const_refs+n_volatile+n_gate_nodes)`.
이는 새 계획 배열의 정확한 요청량이다. 기존 노드에 추가한 포인터 필드(각 8B),
임시 도출 레코드, arena가 확보한 여유 공간은 이 수치에 포함하지 않는다.
`stx_alloc_struct`는 부족할 때 `max(요청량, packed_size)` 버퍼와 16B 연결 노드를 확보하므로
보유 메모리 증가는 요청량과 다르다. 실제 잔여 용량과 추가 버퍼 수 전후를
`metadata/r2/gdb-arena-readonly.out`에 보존했다. GROUP BY와 분석 사례는 기존 여유 공간을
사용했고, 다른 사례는 추가 버퍼 한 개를 확보했다. 각 refill의 크기를 별도로 수집하지
않았으므로 실제 추가 확보 바이트나 RSS 증가량은 이 자료만으로 산출하지 않았다.

집계·분석 결과는 현재 블록의 값 목록 밖에 저장되기도 한다. r1 관측에서는 그 값을 읽는
`TYPE_CONSTANT`가 CORR로 분류되어 생산자와 항목을 공유하지 못했다.
`domain_local_value`가 현재 블록의 집계 누산 결과·분석 결과를 함께 식별하도록 보완했다.
외부 블록의 값은 계속 CORR다. r2에서는 집계 8→5, 분석 10→8, GROUP BY 7→6으로
항목이 줄어 같은 생산자 항목을 공유하는 것을 확인했다. 위 표는 이 최종 r2 측정이다.

첫 qdump inferior call은 로그를 출력하고 true를 반환했지만 직후 잘못된 thread 포인터로
SIGSEGV가 관측됐다. `/bench/hdd/core/core.transaction.1286337.ilhansong_data3.1790098332`와
`metadata/gdb-general.out`, `metadata/core-gdb.out`을 보존했다. 코어는 GDB 아래 SIGTRAP 상태로
남았으므로 원인을 확정하는 증거로 사용하지 않는다. 같은 SQL의 no-GDB 및 읽기 전용 GDB
실행은 정상이다. 이 실패를 소스 회귀로 단정하지 않으며, 성공한 최종 검증의 core 0과 구분한다.
r2 관측 준비 중에는 긴 UNIX 소켓 경로로 인한 시작 실패의 1,701바이트 crash-handler stack과,
잘못된 버전 확인 명령 `cubrid rel`과 실행 환경 없이 호출한 `cubrid --version`의
utility assertion도 있었다. 각각
`metadata/r2/install-optdebug/log/coredump/cub_server_20260923024615.146.coredump`와
`metadata/runtime-report.md`, `runtime/r2/r2-validation-summary-20260923T025414.txt`에 기록했다. 짧은 소켓 경로로 시작한 최종 서버의 plain/read-only
SQL은 모두 rc=0이며 이후 새 core/assert가 없었다. 소유한 서버·master·소켓을 정리했고,
기존 1523/1700 master는 유지했다.

위 상대 증거 경로의 기준은 `.git_ignored_dir/scratch/312-331/`이다.

단위 테스트는 지도 Notes의 2026-09-22 사용자 지시에 따라 실행·활성화하지 않았다.
이번 티켓은 계측 전용 예외 대상이 아니며 양 빌드, optdebug SQL 전수·medium,
카운터 불변과 최종 실행의 코어·새 assert 0을 모두 충족했다. private HA와 shell은 이번 범위에 없다.
