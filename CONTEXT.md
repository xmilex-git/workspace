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
그룹바이 해시 집계 도중 선택도 휴리스틱(표본 튜플 대비 그룹 비율 초과)이 발동해 그 문장의 해시 전략을 영구히 버리고 정렬 폴백으로 전환하는 런타임 결정이다. 그때까지 누적한 그룹은 버리지 않고 테이블 전체를 partial list로 보존한 뒤 전환한다. 트레이스에는 `hash: partial`로 표시된다.
_Avoid_: 해시테이블 꽉 참, 메모리 초과, spill

**해시 축출 (hash eviction)**:
해시 메모리 예산을 초과했을 때 엔트리를 partial list로 덜어내고 해시 집계는 계속하는 동작이다. 해시 상태를 바꾸지 않으며 해시 포기와 무관하다.
_Avoid_: 해시 포기, HS_REJECT_ALL

**누산기 평탄화 (accumulator flattening)**:
해시 축출 또는 해시 포기로 그룹이 partial list로 나갈 때, 워드 누산기를 `DB_VALUE`로 눕혀 스필 포맷에 합류시키는 동작이다. 이 지점에서 반올림이 1회 발생하며, 재로드 시 seed 경로로 재시딩된다.
_Avoid_: 스필(축출·포기와 혼동), finalize(그룹 종료와 혼동)

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

**신선한 체크포인트 (fresh checkpoint)**:
온라인 FULL 백업 진입 시점에 capture한 append LSA(T) 이후에 완료되어 redo LSA(R) ≥ T를 만족하는 checkpoint다. 백업 진입 전부터 진행 중이던 checkpoint는 R이 T보다 앞설 수 있으므로 아무리 기다려도 fresh로 인정하지 않는다.
_Avoid_: "진행 중 checkpoint 대기 완료"를 fresh로 간주, 최신 checkpoint

### HTAP POC (지도: xmilex-git/workspace#30)

**CUBRID CDC 인프라**:
CUBRID에 이미 존재하는 로그 변경 추출 층 — 서버측 `cdc_*`(log_manager.c) 데몬과 클라이언트 라이브러리 `cubrid_log` C API. 이벤트를 서빙할 뿐, 소비 루프는 포함하지 않는다.
_Avoid_: CDC agent(소비자와 혼동), 복제 기능

**CUBRID Debezium 커넥터 (debezium-connector-cubrid)**:
CUBRID CDC 인프라를 소비해 Debezium envelope로 Kafka에 내보내는 정식 Debezium 소스 커넥터. 이 프로젝트가 만드는 유일한 CDC 소비자다. CDC 접근은 POC의 JNA 래핑(ADR 0002)에서 `cubrid_log` wire protocol의 순수 Java 재구현으로 전환 (ADR 0012).
_Avoid_: cubrid-cdc-agent(자체 agent 안 — 기각됨), CDC 도구

**이벤트 카운터 (event counter)**:
커넥터가 CUBRID CDC 스트림의 비-TIMER 로그 아이템에 부여하는 결정적 일련번호. per-item LSA가 없는 CUBRID CDC에서 이벤트 position의 역할을 하며 `_version`과 `source.lsn`의 재료다. 같은 이벤트는 재전송돼도 같은 번호를 받는다.
_Avoid_: LSA(배치 커서일 뿐), Kafka offset

**재시작 anchor**:
커넥터가 재시작 시 로그 추출을 재개하는 배치 경계 LSA — 아직 COMMIT되지 않은 가장 오래된 in-flight 트랜잭션의 첫 DML이 도착한 배치의 경계(없으면 마지막 배치 out_lsa). COMMIT 위치가 아니다.
_Avoid_: 마지막 커밋 위치, 마지막 처리 위치

**current-state 복제본**:
ClickHouse ReplacingMergeTree(`_version`, `_is_deleted`)에 유지되는 원본 테이블의 최신 상태 사본. 정확한 조회는 canonical `FINAL` view를 통해서만 한다.
_Avoid_: 미러, 실시간 동기 테이블(동기 복제로 오해)

**full image 병합 (cond ⊕ changed)**:
`all_in_cond=1`로 확장된 cond(전 컬럼 before-image)에 changed(바뀐 컬럼의 after 값)를 덮어써 full after-image를 만드는 커넥터측 순수 계산. 상태 저장·추가 조회·엔진 패치가 없다 (ADR 0003).
_Avoid_: full image 제공(엔진이 준다는 오해), lookback

**쓰기 정지 스냅샷 (write-stop snapshot)**:
대상 테이블 쓰기를 멈추고 barrier LSA를 기록한 뒤 full scan을 적재하고, CDC를 barrier 이후부터 시작하는 POC용 초기 적재 방식. online snapshot은 제품 단계 과제다.
_Avoid_: 온라인 스냅샷, 일관 스냅샷(MVCC token 기반과 혼동)

**트랜잭션 버퍼 (transaction buffer)**:
커넥터가 trid별로 DML을 COMMIT까지 in-memory로 모으는 버퍼 — CUBRID CDC가 log-order raw(미커밋 포함)를 주므로 커밋-순서 재조립은 커넥터 몫이다(ADR 0004, 정책 ADR 0007). 상한은 opt-in 이벤트 개수 threshold뿐이며 bytes 상한·spill은 없다.
_Avoid_: Kafka producer buffer, 큐(순서 재조립 없이 흘리는 구조로 오해)

**abandon (트랜잭션 abandon)**:
threshold/retention 초과 트랜잭션을 버퍼에서 통째로 폐기하고 metric·WARN으로 알리는 동작(ADR 0007). 다운스트림 영구 유실이며 복구 수단은 재스냅샷뿐이다 — ABORT에 의한 정상 폐기와 다르다.
_Avoid_: rollback(정상 경로와 혼동), drop(경보 없는 유실로 오해)

**barrier LSA**:
쓰기 정지 중 캡처한, 스냅샷과 스트리밍의 경계가 되는 로그 위치. 스냅샷이 담은 상태와 CDC가 이어받는 지점의 정합을 보장하는 유일한 기준점이며, 재시작 anchor의 초기값이 된다. 스냅샷 row는 모두 이 경계 "이하"의 version(이벤트 카운터 0)을 받는다.
_Avoid_: 시작 LSA(스트리밍 관점만), 체크포인트(서버 내부 개념과 혼동), DDL halt(무관한 개념)

**DDL halt (DDL 정지)**:
커넥터가 captured 테이블의 DDL 중 **halt 판정 기준**에 걸리는 것을 감지하면 재시작 anchor를 DDL 이전에 고정한 채 fail-fast로 정지하는 1.0 동작(ADR 0008). 조치 없는 재시작은 같은 DDL에서 결정론적으로 다시 멈추며, 복구는 resnapshot 단일 절차뿐이다. mid-stream CREATE TABLE은 halt 대상이 아니다(WARN+metric).
_Avoid_: schema barrier(§7.8 구 용어 — 개명됨), barrier LSA(스냅샷 경계와 혼동), DDL 지원(자동 전파로 오해)

**halt 판정 기준 (halt criterion)**:
DDL이 로그 이벤트 없이 다음 중 하나를 바꿀 때만 DDL halt가 발동한다는 4축 기준(#75) — ① 행 인코딩(컬럼 추가·삭제·변경) ② 테이블 identity(rename, owner 변경) ③ 이벤트 key identity(PK 추가·삭제) ④ 테이블의 논리적 내용(TRUNCATE, DROP/PROMOTE PARTITION). 인덱스·FK·UNIQUE 추가/삭제와 행이 파티션 사이에서만 움직이는 파티션 재편(ADD/REORG/COALESCE 등)은 네 축 어디에도 안 걸려 계속 진행한다. 판별 불가면 halt가 기본값(fail-safe).
_Avoid_: "모든 ALTER는 halt"(면제 목록 무시), 스키마 변경(4축보다 넓은 말)

**HA halt (HA 정지)**:
커넥터가 재접속 시 소스 노드가 바뀌었거나 접속 노드가 master 상태가 아님을 감지하면 fail-fast로 정지하는 1.0 동작(ADR 0010). 캡처 대상은 master 단일 노드이며, failover 후 이어읽기는 미지원 — 복구는 새 master 대상 resnapshot 단일 절차뿐이다. 노드 identity는 snapshot barrier 캡처 시점부터 offset에 stamp되며(#78/P0-5), identity 없는 anchored offset은 fail-closed로 halt한다.
_Avoid_: HA 지원(무중단 이어읽기로 오해), failover 추적(자동 전환으로 오해), DDL halt(발동 조건이 다른 별개 가드)

**CDC 대상 집합 (extraction set)**:
커넥터 설정 `table.include.list`에서 나와 세션마다 서버에 선언되는 **휘발성** 캡처 대상 목록. 구별 기준은 이름이 아니라 classoid(OID)이며 서버가 이벤트마다 `cdc_is_filtered_class()`로 강제한다. DB에는 "이 테이블이 CDC 대상"이라는 영속 표식이 남지 않는다 — Oracle의 `ADD SUPPLEMENTAL LOG DATA`나 PG의 publication과 달리 유일한 출처는 커넥터 설정이다(ADR 0011 D12). 목록을 좁혀도 supplemental log는 전 테이블에 기록된다(전달만 줄고 기록은 안 줄어든다).
_Avoid_: publication(영속 카탈로그 객체로 오해), CDC 활성 테이블(DB에 표식이 있다고 오해), supplemental log 대상(기록 범위와 혼동)

**relation 사전 (relation dictionary)**:
서버가 CDC 스트림 안에서 `(classoid, owner, table)`을 알려주는 in-band 아이템. 해당 classoid의 첫 사용 아이템보다 반드시 앞서며, 세션이 갈리면 다시 전송된다(커넥터는 영속 캐시하지 않는다). 이것이 있어 커넥터는 `_db_class`(DBA 전용)를 읽지 않고도 이벤트를 테이블로 라우팅한다(ADR 0011 D4). 범위는 extraction 대상으로 지정된 테이블뿐이며, 그래야 권한 경계와 일치한다(D5). **이벤트 카운터에서 제외된다** — 세면 재연결 시 같은 이벤트가 다른 `_version`을 받아 RMT 수렴이 깨진다(D6).
_Avoid_: schema history topic(Kafka 토픽과 혼동), 스키마 사전(컬럼·타입은 별개 — JDBC 카탈로그 뷰에서 온다), 캐시(세션 간 보존으로 오해)

### javasp 병렬 (지도: xmilex-git/workspace#87)

**병렬 안전 선언 (parallel-safe declaration)**:
SP가 병렬 워커에서 평가되어도 안전함(읽기 전용·세션 상태 비의존)을 사용자가 자기선언하는 신규 DDL 속성. 결정성과는 별개 축이며(deterministic ≠ parallel-safe — PG `PARALLEL SAFE`/Oracle `PARALLEL_ENABLE` 선례), 무검증 신뢰 + 매뉴얼 경고 책임 모델을 따른다. 기존 DETERMINISTIC 선언에 소급 적용하지 않는다.
_Avoid_: DETERMINISTIC(서브쿼리 캐시용 별개 속성), READS SQL DATA(데이터 접근 특성 컬럼과 혼동)

**중첩 직렬 강등 (nested serial demotion)**:
병렬 문맥에서 평가 중인 SP가 콜백 SQL로 재귀 호출한 SP/질의를 병렬 플랜 없이 직렬로 실행하는 정책. 호출을 거부하는 게 아니라 강등하며, 중첩 깊이 제한(15)은 그대로다.
_Avoid_: top-SP-only(거부 정책으로 오해), 중첩 금지

**실행 체인 (execution chain)**:
하나의 SP 호출에서 시작해 재귀 호출로 이어지는 논리 호출 사슬. PL 세션은 체인을 복수 보유할 수 있고(체인 포레스트), 체인 내부는 LIFO(중첩), 형제 체인끼리는 독립이다. 재귀 깊이 제한(15)과 직렬 강등 플래그는 물리 세션이 아니라 체인 기준이며, 세션 경계(helper)를 넘어 전파된다(ADR 0013).
_Avoid_: 스택(세션 단일 LIFO 시절의 구조와 혼동), 워커(체인은 스레드가 아니라 논리 사슬 — 프레임마다 스레드가 다를 수 있다)

**체인 서브컨텍스트 (chain sub-context)**:
PL 서버 `Context`에서 체인별로 분리되는 실행 상태 — JDBC 연결·inBound 큐·tranId 검사. 클래스로더·TargetMethodCache·시스템 파라미터는 세션 Context에 남아 공유된다(Java static 상태의 세션 내 단일성 보존). 체인 첫 호출 시 지연 생성, 체인 종료 시 파기.
_Avoid_: 복합 키 Context(클래스로더까지 갈라지는 폐기된 후보), 서브세션

**병렬 적격 판정 (parallel eligibility judgment)**:
"이 SP 포함 질의를 병렬로 실행해도 되는가"의 판정. SP별 검사는 병렬 안전 선언 비트 **단독**이고("비트 set ⇒ Java SP"는 선언 DDL이 강제), 질의당 1회의 환경 게이트(`pl_transaction_control==no`)가 공통 판정 유틸 진입부에서 함께 확인된다. 판정은 클라이언트측 XASL 생성 시점에 내려져 플랜 비트로 동결된다.
_Avoid_: SP 성질 검증(선언은 무검증 신뢰), DETERMINISTIC/sql_data_access 검사(판정에 비관여)

**런타임 one-way 강등 게이트 (runtime one-way demotion gate)**:
실행 시점에 조건을 재검사해 캐시된 병렬 플랜을 **그 실행에 한해 직렬로 강등만** 할 수 있는(되살릴 수는 없는) 서버측 게이트 — 기존 `px_scan.cpp:391-403` 재검사 패턴과 동형. SP 포함 병렬 플랜이 `pl_transaction_control=yes` 세션에서 캐시 히트되는 구멍의 봉인과, 강등 체인(중첩 직렬 강등)에서 실행되는 질의의 px 경로 차단(#106 — 이 조건은 SP 플래그와 독립인 OR 분기)에 쓴다.
_Avoid_: 런타임 백스톱(선언 진위 검증으로 오해 — 환경 전제 확인일 뿐), 정책 거부(에러가 아니라 강등)

**싱글스레드 콜백 경로 (single-threaded callback path)**:
병렬 워커들의 콜백 SQL을 기존 클라이언트 콜백 채널(리더 rid) 하나로 한 번에 하나씩(K=1) 통과시키는 1단계 경로. 와이어 변경이 없고 클라이언트 관점에선 오늘의 순차 콜백과 동일하다. 2단계에서도 helper 고갈 시 강등 목적지로 남는다(정확성 무영향, 속도만 손해). 구현체는 `pl_session`의 재진입 락(`acquire/release_px_single_thread_callback`)이다.
_Avoid_: 콜백 funnel(구 용어 — #106에서 개명됨), 직렬 폴백(질의 전체를 직렬 플랜으로 되돌리는 것과 혼동 — 이 경로는 콜백 구간만 직렬), 다중화(태깅 멀티플렉싱은 폐기된 후보)

**콜백 helper (callback helper)**:
병렬 워커의 콜백 SQL을 실행하기 위해 cub_server가 fork+exec로 띄우는, 클라이언트 라이브러리를 링크한 브로커 비의존 경량 프로세스. 구현 바이너리는 PL 전용이 아닌 범용 `cub_compile_engine`(서버가 스폰하는 클라이언트측 SQL 컴파일·실행 엔진). cub_master 정상 경로로 서버에 접속·등록하고, 잡은 자신이 여는 전용 잡 소켓으로 px 워커가 직접 배달하는 2채널 구조다(#104 — 클라이언트 요청 채널 long-poll은 기각). helper 연결 하나가 곧 콜백 채널 하나. 질의당 helper ≤ DOP.
_Avoid_: 미니 csql(초기 비유 — csql 바이너리 재사용은 기각됨), helper CAS(브로커 CAS 풀 차용은 폐기된 후보 — csql발 질의가 깨짐), 워커(서버 내부 px 워커 스레드와 혼동)

**가시성 재현 (visibility reproduction / join-tran)**:
콜백 helper가 별도 트랜잭션이면서 호출자의 스냅샷을 import하고 호출자 MVCCID를 가시 집합에 포함해, 동일 트랜잭션에서 실행한 것과 같은 읽기 결과를 재현하는 것(PG 병렬 워커 snapshot/XID import 선례). "동일 트랜잭션 요구"의 공식 완화형 — tran_index 공유가 아니다.
_Avoid_: 같은 MVCCID 공유(helper가 쓰기 주체가 되는 것으로 오해 — helper는 읽기 전용, 가시 집합에만 포함), 스냅샷 격리 위반(직렬↔병렬 결과 동일성이 목적)

**join-tran 핸드셰이크 (join-tran handshake)**:
서버가 콜백 잡을 helper에 디스패치하는 시점에 원자적으로 수행하는 가시성 재현 절차 — vacuum pin을 먼저 publish한 뒤 스냅샷을 복제하고(pin-먼저-복사-나중, ADR 0014), 호출자 MVCCID를 helper의 가시 집합에 넣고, attach 레지스트리에 등록한다. 잡 완료 시 역순으로 purge하며, "잡 없이 join된 helper"라는 중간 상태는 존재하지 않는다.
_Avoid_: 별도 join RPC(helper발 왕복으로 오해 — 서버측 디스패치 시점 수행이 맞다), 연결 수명 상태(잡 단위가 맞다)

**attach 레지스트리 (attach registry)**:
호출자 트랜잭션에 두는 "지금 join 중인 helper 트랜잭션 집합". 호출자 인터럽트의 helper 전파, 호출자 종료(커밋/어보트/연결단절) 시 helper 전원 인터럽트+detach 대기, 정리 훅 — 세 문제를 푸는 단일 매개체다. 락 매니저에는 "같은 편 트랜잭션" 개념이 없으므로 락 면제와는 무관하다.
_Avoid_: 락 그룹(락 호환성 예외로 오해), 세션 레지스트리(트랜잭션 단위가 맞다)
