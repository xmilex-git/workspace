# CUBRID Tooling

CUBRID 개발 작업에 사용하는 독립형 도구와 agent skill의 공통 언어를 정의한다.

## Language

**JIRA 이슈 본문**:
QA, 의사결정자, 개발자가 이슈의 배경, 변경 범위, 완료 조건을 판단할 수 있도록 JIRA wiki markup으로 작성하는 간결한 본문이다. 작업 성격에 맞는 공식 템플릿을 따르며 상세 구현 및 내부 검증 절차는 포함하지 않는다.
_Avoid_: 분석 보고서, 구현 명세서

**상세 분석 자료**:
호출 경로, 근본 원인, 코드 수준 구현 검토, 세부 검증 기록처럼 담당 개발자에게 필요한 기술 자료다. JIRA 이슈 본문과 구분하며 필요한 경우에만 첨부한다.
_Avoid_: JIRA 이슈 본문

**3-repo PR 동기화**:
CUBRID 엔진 PR 브랜치와 그 PR에 연결된 공개·비공개 TC 브랜치를 각 저장소의 develop 기준으로 함께 최신화하는 작업이다.
_Avoid_: TC 최신화, PR rebase

**해시 포기 (hash abandonment, HS_REJECT_ALL)**:
그룹바이 해시 집계 도중 선택도 휴리스틱(표본 튜플 대비 그룹 비율 초과)이 발동해 그 문장의 해시 전략을 영구히 버리고 정렬 폴백으로 전환하는 런타임 결정이다. 트레이스에는 `hash: partial`로 표시된다.
_Avoid_: 해시테이블 꽉 참, 메모리 초과, spill

**해시 축출 (hash eviction)**:
해시 메모리 예산을 초과했을 때 엔트리를 partial list로 덜어내고 해시 집계는 계속하는 동작이다. 해시 상태를 바꾸지 않으며 해시 포기와 무관하다.
_Avoid_: 해시 포기, HS_REJECT_ALL

**리더 잔여 직렬 (leader-serial residue)**:
병렬 폴백 정렬에서 워커 정렬이 끝난 뒤 리더 단독으로 남는 두 국면 — ② fan-in 병합(`sort_merge_worker_runs_to_one`)과 ③ 튜플당 put_fn drain(`sort_run_final_single`) — 의 시간 몫이다. IMP-032(구 IC-5)의 공략 대상.
_Avoid_: 직렬 꼬리(serial tail — 텔레메트리 지표와 혼동 금지), GROUP BY 전체 시간

**그룹 경계 정렬 분할 (group-boundary-aligned split)**:
consolidated run을 페이지 단위로 나눈 뒤(`sort_split_last_run` 그대로), 각 워커가 drain 시점에 선두의 이전 구간 연속 그룹을 건너뛰고 말미의 미완 그룹을 닫힐 때까지 초과 읽기하여, 모든 그룹이 정확히 한 워커에 통째로 귀속되게 하는 분할 규약이다. 이 규약 하에서 워커는 직렬과 동일한 순서로 동일한 튜플을 보므로 order-sensitive aggregate까지 의미가 보존된다.
_Avoid_: range partition(물리 재분배로 오해), 튜플 재분배

**귀속 프로브 (attribution probe)**:
A/B 증거가 아닌 귀속 증거를 얻기 위한 경량 측정 — 워밍업 1회 + 트레이스 1회 + perf 샘플, §6-c 블록 규율·quiet-gate 차단 미적용(bgload 기록만). 기대효과 산정과 스코프 분해 판단에만 쓰고 accept/reject 판정에는 쓰지 않는다.
_Avoid_: 텔레메트리 패스, A/B 블록

**계획시점 해시 적격 (plan-time hash-eligible)**:
XASL 생성 시 select 리스트와 HAVING절의 형태만으로 결정되는 정적 플래그로, 런타임에 해시가 실제로 유지됐는지와는 별개다. 런타임 해시 상태와 혼용하지 않는다.
_Avoid_: 런타임 해시 상태, hash: true/partial

**스트라이프 디렉터리 (stripe directory)**:
columnar 파일 메타페이지 체인에 사는 고정폭 엔트리 목록이다. 엔트리 append 1건이 undo-redo 로그 1건이며, 엔트리가 보이면 그 stripe는 flush 완료다(Citus의 3-상태 stripe 판정을 대체).
_Avoid_: 3-상태 stripe 판정, 메타 테이블 MVCC 행

**스트라이프 footer (stripe footer)**:
stripe 연속 페이지 말미에 같은 sysop으로 기록되는 chunk 스킵리스트(chunk별 min/max·오프셋·압축정보)다. 스킵 판정은 footer 1~2페이지 read로 끝난다.
_Avoid_: 메타페이지에 저장된 스킵리스트

**고정폭 raw 직렬화 (fixed-width raw serialization)**:
columnar chunk에서 디스크 고정폭 도메인(수치·날짜시간·CHAR(n)·BIT(n))을 per-value 헤더 없이 타입 자연 정렬 raw 배열로 눥히는 규약이다. NUMERIC은 예외로 PG 자연 포맷(sign+weight/dscale+base-10000 digits)의 가변폭 스트림에 눕는다(#23). NULL은 0바이트(exists 비트맵이 대변). 경계 기준은 타입 리스트가 아니라 도메인 고정폭 여부(PG `attlen>0` 등가)다. 압축은 경량 인코딩 없이 chunk 단위 코덱(NONE/LZ4/ZSTD)만 적용한다 — Citus 동일 범위.
_Avoid_: OR 전면 직렬화, dictionary/RLE/delta 인코딩(미채택)

**신선한 체크포인트 (fresh checkpoint)**:
온라인 FULL 백업 진입 시점에 capture한 append LSA(T) 이후에 완료되어 redo LSA(R) ≥ T를 만족하는 checkpoint다. 백업 진입 전부터 진행 중이던 checkpoint는 R이 T보다 앞설 수 있으므로 아무리 기다려도 fresh로 인정하지 않는다.
_Avoid_: "진행 중 checkpoint 대기 완료"를 fresh로 간주, 최신 checkpoint

**columnar 블록 실행기 (columnar block executor)**:
columnar 읽기가 scan_manager·attrinfo·fetch.c를 일절 타지 않고 qexec 분기에서 stripe→chunk→bitmap 단위로 완결되는 자체 실행 경로다. 조인에는 행을 공급하지 않고 물질화된 list로만 참여한다.
_Avoid_: S_COLUMNAR_SCAN(폐기된 설계), scan_next 심, row-at-a-time 공급

**벡터화 필터 (vectorized filter)**:
chunk의 raw 배열에 컴파일 시점 선택된 타입 특화 비교 커널을 직접 적용해 uint64 bitmap을 만드는 WHERE 처리다. NUMERIC은 PG 포맷(sign+weight/dscale+base-10000 digits) digit-aware 비교, CHAR(n)은 고정폭 memcmp, LIKE는 바이트 매처(binary collation 한정), col-op-col 포함.
_Avoid_: DB_VALUE 행 단위 eval_data_filter, tp_value_compare 루프, NUMERIC 17B two's complement 부호반전 비교(부호 유실 버그와 함께 폐기 — #23)

**columnar leaf step**:
step program(PR CUBRID/cubrid#7658)의 leaf를 대체하는 columnar 전용 스텝이다. 컴파일 시점 도메인 확정 decode_fn이 raw 배열에서 프로그램 셀로 직행한다 — case문·fetch_peek_dbval 없음.
_Avoid_: expr_k_leaf_fetch, attr cache 경유

**폴백 제로 (zero-fallback)**:
columnar 실행에서 커버리지 밖 식을 느린 경로로 우회시키지 않고 서버 컴파일 시점에 ER_COLUMNAR_UNSUPPORTED_EXPR로 거절하는 정책이다. 커버리지는 TPC-H 형태부터 시작해 확장한다.
_Avoid_: expr_k_fallback 배선, row-at-a-time 폴백 경로

**RAW_PROG (columnar raw 프로그램)**:
columnar 블록 전용의 DB_VALUE-비경유 step program이다. 셀은 16B 언태그드 union(+별도 null 표시)이며 런타임 타입 태그 없이 커널 선택이 타입을 인코딩한다. NUMERIC 셀만 step-owned 고정 scratch에 대한 포인터다. columnar 측 자체 컴파일러가 XASL regu tree에서 직접 컴파일하며 기존 EXPR_PROG·expr_compile.c와 무접촉이다(#23).
_Avoid_: EXPR_PROG 확장, DB_VALUE 셀 프로그램, per-step DB_VALUE 브리지

**fused agg transition**:
RAW_PROG가 집계 인자 평가→group hash lookup→누적까지 행당 eval 1회로 완결하는 규약이다(PG `ExecBuildAggTrans` 완전형). BUILDVALUE(그룹 없음)는 lookup이 고정 accumulator로 퇴화한 동일 프로그램 형태다(#23).
_Avoid_: per-agg dispatch 루프, program eval 후 별도 acc_kernel 2-pass

**raw hash agg**:
columnar 전용 GROUP BY 해시 집계다. group key 해싱(VARCHAR 포함, 가변 키 arena)과 accumulator를 전부 raw로 유지하고 출력 시점에만 DB_VALUE로 물질화한다. 고정 메모리 예산 초과 시 런타임 에러이며 spill/축출이 없다(#23).
_Avoid_: aggregate_hash_key(DB_VALUE 키), 행마다 outptr 물질화, partial list 축출

**파생 테이블 승격 물질화 (derived-table promotion)**:
조인에 낀 columnar 참조를 XASL 생성 시 sargable pred+필요 컬럼만의 단일 테이블 서브 XASL(aptr)로 재작성하고 본 spec을 list scan으로 바꾸는 규약이다. columnar 실행기는 항상 단일 테이블 블록만 본다. CUBRID 실행기 전반의 flat program화 이후 해제를 재검토한다.
_Avoid_: 서버 즉석 spec 변조, scan 인터페이스로의 조인 참여
