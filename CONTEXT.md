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

**파티션 패스 간 리스트 인계 (cross-pass list handover)**:
파티션 스캔은 파티션마다 별도 병렬 패스를 돌고, 병렬 패스가 끝날 때 워커 리스트를 메인 리스트에 병합한다. 메인 리스트가 비어 있으면 페이지를 복사하지 않고 워커 리스트 객체를 그대로 인계받으므로, 인계받은 리스트는 닫혀 있고 튜플 디스크립터가 없다. 다음 패스가 직렬이면 메인이 그 리스트에 다시 쓰므로, 직렬 폴백 진입 지점에서 재오픈과 디스크립터 복구를 해야 한다. 대상은 결과 리스트와 집계 partial list 둘 다이며, 스캔 방식(순차·인덱스)과 무관하게 같은 규약이 적용된다.
_Avoid_: 리스트 병합(복사 경로와 이어붙이기 경로를 뭉뚱그림), swap

**TPC-H SF10 측정 자산**:
이 호스트에 현존하는 TPC-H SF10 작업 자산 — DB `tpch_sf10`(`CUBRID_DATABASES=~/databases/pr7866`), 질의 `tpch-sspq/queries/`, 측정 conf `.git_ignored_dir/conf/pr7866.conf`, 하네스 `tpch-sspq/harness/`. 적재 이력이 기록돼 있지 않으므로 온디스크 포맷이 바뀐 빌드로 재는 측정에는 재적재가 선행돼야 한다(CUBRID_SSOT §3-18).
_Avoid_: `~/databases/tpch/`·DB `tpch_sf10_q1`(2026-09-19 기준 호스트에 없음), `.vscode/TPC-H`

**신선한 체크포인트 (fresh checkpoint)**:
온라인 FULL 백업 진입 시점에 capture한 append LSA(T) 이후에 완료되어 redo LSA(R) ≥ T를 만족하는 checkpoint다. 백업 진입 전부터 진행 중이던 checkpoint는 R이 T보다 앞설 수 있으므로 아무리 기다려도 fresh로 인정하지 않는다.
_Avoid_: "진행 중 checkpoint 대기 완료"를 fresh로 간주, 최신 checkpoint

### 언네스트된 SEMI/ANTI JOIN의 조기정지와 메모이즈 (CBRD-27465)

**EXISTS 키 한도 주입 (EXISTS limit injection)**:
언네스트되지 않은 EXISTS 부질의에 재작성 단계가 LIMIT 1을 심어, 인덱스 스캔이 키 하나에서 멈추게 하는 장치다. 언네스트된 부질의는 이 단계를 거치지 않으므로 효과를 잃는다.
_Avoid_: 단건 정지(층위 불명), XASL_NEED_SINGLE_TUPLE_SCAN(도달하지 않는 별개 플래그)

**인덱스 키 한도 (index key limit)**:
인덱스 범위 스캔이 정해진 개수의 키를 읽고 스캔 자체를 끝내는 저장 층의 조기정지다. semi/anti inner에서는 첫 키가 곧 정답임이 보장될 때 — 인덱스 밖 필터가 없을 때 — 에만 1로 둘 수 있다.
_Avoid_: scan_immediately_stop(0건 전용 킬스위치), 단건 정지

**재진입 게이트 (single-fetch gate)**:
NL semi/anti inner에서 첫 통과 행 이후 조인이 같은 outer로 inner를 다시 묻지 않게 하는 조인 층의 래치다. semi join 의미 그 자체이자 anti 판정(매치 유무)의 통신 채널이며, 인덱스 읽기 양은 줄이지 않는다.
_Avoid_: 단건 정지, 조기정지(인덱스 키 한도와 혼동)

**부질의 결과 캐시 (subquery result cache)**:
언네스트되지 않은 상관 부질의의 결과를 상관값별로 기억하는 장치다. 언네스트되면 사라지며, 언네스트 후의 대응물은 메모이즈다.
_Avoid_: 메모이즈(다른 장치), 캐시(무엇의 캐시인지 불명)

**파티션 블록 반복 (partition block iteration)**:
일반 NL 조인이 파티션 inner를 도는 방식으로, inner의 파티션 하나가 바깥 루프의 블록이 되어 파티션마다 outer를 다시 스캔한다. 한 블록 안에서 inner는 늘 같은 파티션이므로 메모이즈는 블록(파티션)마다 새로 만든다.
_Avoid_: 파티션 스캔(행 단위 파티션 탐색과 뭉뚱그림)

**행 단위 파티션 탐색 (per-outer-row partition probe)**:
semi/anti inner가 파티션을 도는 방식으로, outer 행 하나 안에서 전 파티션을 훑어 첫 매치(semi) 또는 무매치(anti)를 확정하고 다음 행에서 첫 파티션으로 되감는다. 블록 반복이면 semi는 매치 파티션마다, anti는 무매치 파티션마다 outer를 중복 판정하므로 필연이다. 메모이즈는 키당 하나이며 파티션 간에 공유된다.
_Avoid_: 파티션 스캔, 파티션당 메모이즈

**매치 전용 메모이즈 (match-only memoize)**:
semi/anti inner에서 outer 키별로 "매치 있음/없음"만 기억하는 메모이즈 모드다. 값을 저장하지 않고 조인 타입도 모르며, anti의 반전은 재생 시 실행기가 맡는다.
_Avoid_: 값 메모이즈, 부질의 결과 캐시

### 임시 리스트 튜플 포맷 (지도: xmilex-git/workspace#179)

**복합 값 (composite value)**:
이 기획에서 집합, JSON 문서, 객체·외부 객체처럼 내부 구조나 참조 의미를 갖는 값을 묶어 부르는 말이다. 문자열은 길이가 가변이라는 이유만으로 이 분류에 포함하지 않는다.
_Avoid_: scratch(임시 작업 공간과 혼동), overflow(넘침 저장과 혼동), 가변 값(문자열까지 포함하는 다른 분류)

**레이아웃 디스크립터 (tuple layout descriptor)**:
리스트의 `type_list`에서 결정적으로 파생되는, 컬럼별 폭·정렬·캐시 오프셋과 리스트별 헤더 크기·비트맵 크기·상수 오프셋 접두 경계를 담은 스키마 상수 표다. 튜플 안에는 기록되지 않는다.
_Avoid_: 튜플 디스크립터(`QFILE_TUPLE_DESCRIPTOR` — 쓰기용 값 묶음과 혼동), 스키마

**상수 오프셋 접두 (constant-offset prefix)**:
튜플 안에서 첫 비캐시 컬럼 또는 이 튜플의 첫 NULL 컬럼 이전까지, 컬럼 위치가 레이아웃 디스크립터만으로 결정되는 선두 구간이다. 그 뒤 컬럼은 접두 증분 deform으로 읽는다.
_Avoid_: 고정 슬롯 구간, fixed-width 영역

**첫 비캐시 컬럼 (first non-cached column)**:
레이아웃 디스크립터가 상수 오프셋을 제공하지 않는 첫 컬럼. 첫 가변 컬럼과, 오프셋이 디스크립터 표현 상한을 넘는 첫 컬럼 중 앞선 것이다. 이후 컬럼은 모두 비캐시다.
_Avoid_: 첫 가변 컬럼(오프셋 상한 사례를 놓침), slow 컬럼

**도메인 확정 (domain resolve)**:
`DB_TYPE_VARIABLE`로 열린 컬럼의 도메인이 첫 non-NULL 값을 보고 구체 타입으로 결정되는 사건이다. 확정 전 그 컬럼의 값은 반드시 NULL이다.
_Avoid_: 레이아웃 확정과 혼용, 타입 추론

**레이아웃 확정 (layout finalize)**:
확정된 도메인 배열과 헤더 크기에서 레이아웃 디스크립터를 파생하는 순수하고 멱등한 계산이다. 도메인을 바꾼 코드가 같은 자리에서 다시 수행한다.
_Avoid_: 도메인 확정과 혼용, 스키마 컴파일

**기존 튜플 호환성 (existing-tuple compatibility)**:
리스트의 도메인이나 레이아웃이 변경된 뒤에도 이미 기록된 튜플의 값과 컬럼 경계를 올바르게 해석할 수 있는 성질이다.
_Avoid_: 레이아웃 내부 일관성(현재 도메인과의 일치만으로 기존 튜플 호환성을 보장하지 않음)

**NULL-only 컬럼**:
해당 리스트에 지금까지 기록된 모든 튜플에서 값이 NULL인 컬럼이다. 이후 non-NULL 값이 기록될 수 있는지와는 별개의 상태다.
_Avoid_: nullable 컬럼(NULL 허용 여부와 기록 이력을 혼동), 빈 리스트

**접두 증분 deform (incremental prefix deform)**:
컬럼 k를 읽을 때 마지막으로 푼 컬럼 다음부터 이어서 걷고 진행 오프셋을 deform 캐시에 남기는 읽기 방식이다. 임의 순서 접근을 O(1) 재접근으로 만든다.
_Avoid_: 임의 접근 테이블, 오프셋 테이블

**역방향 가능 리스트 (backward-capable list)**:
생성 시점에 역방향 스캔이 허용된다고 선언된 리스트로, 튜플 헤더에 `prev_len`을 포함한다. 최종 결과 리스트·merge join 입력·분석함수 group/value 리스트가 해당하며, 그 외 리스트에서의 역방향 스캔은 계약 위반이다.
_Avoid_: scrollable 리스트, 양방향 리스트

**in-place 덮어쓰기 계약 (in-place overwrite contract)**:
리스트 안의 값을 제자리에서 바꾸는 것은 이미 bound인 값을 같은 인코딩 크기의 값으로 바꿀 때만 허용된다는 규약이다. NULL을 값으로 바꾸는 것은 허용되지 않는다.
_Avoid_: 튜플 갱신, 컬럼 업데이트

**튜플 슬롯 (tuple slot)**:
현재 튜플, 그 리스트의 레이아웃 디스크립터, 그리고 deform 캐시(걸어온 컬럼 수와 진행 오프셋)를 한 덩어리로 묶어 리더에게 건네는 객체다. 새 포맷은 자기 기술적이지 않으므로 튜플 포인터 혼자서는 읽을 수 없고 슬롯이 읽기의 단위가 된다. 튜플을 바꾸는 유일한 길은 슬롯 setter이며 그때 캐시가 리셋된다.
_Avoid_: 튜플 레코드(버퍼 소유만 뜻함), 커서

**위치 접근자 / 값 접근자 / 일괄 접근자 (locate / read / bulk accessor)**:
슬롯에서 컬럼을 읽는 세 층 — 위치 접근자는 본문 포인터와 길이·NULL 여부만 돌려주고, 값 접근자는 그것을 DB_VALUE로 만들며, 일괄 접근자는 튜플 전체를 값 리스트로 한 번에 푼다. DB_VALUE를 만들지 않는 소비자(해시 키, 카운터, 비교자)만 위치 접근자를 직접 쓴다.
_Avoid_: L0/L1/L2(CPU 캐시 용어와 혼동), getter

**튜플 조립기 (tuple assembler)**:
컬럼별 소스(DB_VALUE 또는 원시 바이트)의 배열을 받아 크기 계산과 채우기 두 패스로 새 포맷 튜플 한 개를 임의 버퍼에 만드는 단일 라이터다. 모든 튜플 생성 경로가 이것을 거치므로 "같은 입력은 같은 바이트"가 구조적으로 보장된다.
_Avoid_: 튜플 디스크립터, fast writer

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

### CAS 통합 (지도: xmilex-git/workspace#112)

**커넥션 프런트 (connection front)**:
CAS 통합 아키텍처(#112)에서 브로커 마스터의 축소된 새 역할 — accept·접속 선별·IP ACL·admission control(잡큐)을 수행한 뒤 클라이언트 fd를 CAS 대신 로컬 cub_server에 핸드오프하고 데이터 경로에서 빠지는 접속 시점 전용 계층(#116 D1). 브로커 호스트 = DB 호스트가 강제되며(핸드오프는 로컬만), 질의당 왕복은 jdbc→server 1-hop이다.
_Avoid_: 브로커 제거(폐기된 초기 목적지 — 마스터는 존치한다), 프록시/중계(Linux에서 바이트를 중계하지 않는다), CAS(프로토콜 처리·SQL 실행 주체가 아니다)

**세션 객체 컨텍스트 (session object context)**:
client workspace(MOP 테이블·MOBJ heap·AREA 할당자·SM_CLASS·트리거/템플릿 상태)가 서버 편입 후 서버 스레드 문맥에서 갖는 재규정된 역할(#123). 역할은 셋으로 분해된다 — ① 컴파일러·DDL 코드가 소비하는 스키마 표현, ② 트랜잭션 스테이징(DDL의 쓰기 경로 그 자체: SM_TEMPLATE·dirty MOP·flush), ③ 네트워크 왕복 회피 캐시. 서버 편입으로 존재 이유가 사라지는 것은 ③뿐이므로 구조는 존치하고(SA 모드가 산 증거), 표현 통합(서버 카탈로그와의 이중 표현 해소)은 이 맵 밖 후속 트랙이다. 불변식: **실행 핫패스는 세션 객체 컨텍스트를 참조하지 않는다**.
_Avoid_: 카탈로그 캐시(역할 ③만 가리키는 옛 프레임 — 캐시가 아니라 표현이자 쓰기 경로), 워크스페이스 제거(폐기된 후보 — 컴파일러 재작성과 등가)

**역접속 콜백 종단 (in-server callback termination)**:
PL 실행 중 JVM(cub_pl)에서 돌아오는 `INTERNAL_JDBC` 콜백(SQL prepare/execute·OID·collection·트랜잭션 제어 등)과 PL/CSQL 컴파일 semantics 질의를 CAS로 중계하지 않고 cub_server가 자기 안에서 끝내는 구조(#120). SA_MODE의 in-process `method_dispatch()` 분기가 템플릿이며, invoke 루프에 블록된 그 서버 워커 스레드가 동기 처리한다(트랜잭션 조인 = 연결 동일성→스레드 동일성). cub_pl 프로세스·서버↔JVM 와이어는 무변경 — 재배선은 전적으로 cub_server 내부다. 핸들 캐시는 CAS 프로세스-전역 싱글턴(사실상 per-session이던 것)의 충실한 번역으로 `cubpl::session`이 소유한다.
_Avoid_: JVM 편입/JNI 직결(기각 — 순방향은 이미 직결, 크래시 격리 상실), 역접속 제거를 cub_pl 제거로 오해(존치한다), 콜백 프로토콜 변경(Java측 무변경 계약)

**reset-테이블 사전 적용 (connect-time reset-table pre-application)**:
CAS 통합 후 HA 접속-시 판정의 원칙(#121 D2) — 서버가 세션 수립 시점에 `xtran_should_connection_reset`의 타입×HA상태 테이블을 미리 적용해, 받아봤자 즉시 reset될 조합(RW×standby, SO×active, 복제지연×standby, replica 불일치, maintenance×비허용)을 드라이버가 재시도 가능한(retryable) 형태로 거절하는 것. 현행 2-pass 능력 XOR(CAS내 클라이언트 라이브러리 검사)을 대체하는 서버측 단일 진실 소스이며, 트랜잭션 경계 reset은 백스톱+치유 트리거로 축자 생존한다. 테이블에 행이 없는 조합(RO×active 등)은 수용한다.
_Avoid_: 관용 단일-pass(기각 — failover 후 구-active가 RW 세션을 받아버려 드라이버가 신-active로 못 가는 고착 회귀), 능력 XOR의 대칭 거절 승계(RO×active 거절은 미승계)

**트랙 A / 트랙 B (track A / track B)**:
CAS 통합 실행의 2대 작업 트랙(#122 D1) — **트랙 A** = 컴파일러·client 절반의 서버 편입(전역상태 세션-로컬화, RPC 접기, DDL, plcsql), **트랙 B** = 접속 프런트(핸드오프, CAS 프로토콜 화자화, HA 의미론, CAS 제거). A 선행이 원칙: 프런트가 먼저 서면 서버에 컴파일러가 없어 동작하는 중간 상태가 성립하지 않는다.
_Avoid_: 티켓 원안의 "프런트 먼저" 순서(기각), 트랙 병행 착수(A3↔A4의 병렬은 트랙 A 내부 이야기다)

**통합 브랜치 (integration branch, `cas-merge`)**:
CAS 통합 산출물이 누적되는 fork(`xmilex-git/cubrid`)의 장수 브랜치(#122 D3) — upstream `CUBRID/cubrid` develop 기준으로 절단하고 주기적 머지(리베이스 아님)로 추종하며, 스테이지 PR(`wf122/<스테이지>-<슬러그>`)의 머지 대상. 중간 스테이지는 단독 upstream 반입이 불가하므로(1-hop 없이는 사용자 가치 없음) 여기에 모아 기존 CAS 통합 upstream PR로 제출한다.
_Avoid_: develop 직행 PR 스택(기각), 리베이스 추종(공개 브랜치 이력 파괴)

**표준 smoke 스크립트 (standard smoke scripts)**:
스테이지 게이트의 smoke를 정의하는 단 2개의 누적형 스크립트(#122 D5) — **트랙 A용**: unit 하네스 내 in-process 시나리오(연결→prepare→execute→fetch→커밋; A4 이후 다중-세션 변형 추가), **트랙 B용**: JDBC 실드라이버 스크립트(접속→DML/DDL→취소→재접속; B3부터 failover 1회). 스테이지마다 새로 발명하지 않고 케이스를 누적한다. 중간 CTP는 없으며(#122 D4) 최종 게이트에서만 CTP·YCSB가 돈다.
_Avoid_: 스테이지별 일회성 테스트 스크립트, 중간 CTP sql/medium 게이트(#122 D4로 폐지된 옛 맵 문구)

**유틸리티 채널 (utility channel)**:
CAS 통합 후에도 존치하는 legacy client RPC(net_client_request 계열) 경로의 재규정된 이름(#126 D7/D8) — 관리 유틸리티(cub_admin 전부: unloaddb·compactdb·loaddb 포함)와 HA 데몬 4종만 도달할 수 있다. 격리는 코드 이동이 아니라 도달 게이트로 표현된다: 서버가 boot 등록 시 DB_CLIENT_TYPE 허용목록으로 일반/드라이버 타입을 거절하고, #118 D3의 핸드셰이크 패스워드 검증이 이 채널에도 동일 적용된다. 라이브러리 실체는 오늘의 libcubridcs 그대로(무이동·무개명).
_Avoid_: 레거시 채널 전면 소멸(#118 D4의 문자적 독해 — 소멸은 드라이버·csql 도달 경로에 한한다), 유틸 라이브러리 물리 분할(기각 — 정리 트랙감)

**thin csql (서버-렌더 텍스트 모델)**:
CAS 통합 후 csql CS 모드의 형태(#126 D1/D2) — CCI 전송으로 CAS V12를 말하는 '또 하나의 드라이버 클라이언트'이며, 값 렌더링은 psql처럼 서버가 한다: additive function code로 서버가 편입된 기존 포매터(csql_result_format)를 세션 워크스페이스 위에서 실행해 완성 텍스트를 반환하고, csql은 정렬·페이징·터미널만 담당한다. 세션 커맨드(;schema 류)도 같은 방식. 로컬 접속은 서버 입양 UNIX 소켓 직결(브로커 무의존), csql -S는 libcubridsa dlopen 그대로 존치.
_Avoid_: CCI 타입 위 포매터 재작성(기각 — ~1000줄+MONETARY 심볼 등 바이트 호환 불가 4점), csql 전용 경량 프로토콜(기각), 클라이언트측 DB_VALUE 재구성

**스캔 패스 (scan pass)**:
병렬 스캔 manager가 `open()`부터 `read()`를 거쳐 `read_finalize()`까지 한 번 도는 단위다. 파티션 테이블은 파티션마다 한 패스를 돌며(`qexec_init_next_partition`이 스캔을 재오픈), 패스가 바뀌어도 원본 XASL의 `agg_list`는 동일한 누산기를 계속 가리킨다. "스캔 블록"이 물리적 분할 단위라면 패스는 manager 수명 단위다.
_Avoid_: 스캔 블록(물리 분할과 혼동), 쿼리 실행 1회(패스는 여러 번)

**누산기 재이주 (accumulator re-homing)**:
`AGGREGATE_TYPE::accumulator.value`/`value2`의 버퍼를 한 힙에서 다른 힙으로 옮기는 동작 — 대상 힙에서 `pr_clone_value`로 복제하고 원래 힙에서 `pr_clear_value`로 해제한 뒤 대입한다. 병렬 BUILDVALUE 경로에서 워커 병합용 heap 0(malloc)과 코디네이터 private heap(lea) 사이를 오간다. 값 복사이지 소유권 표시 변경이 아니므로, 어느 쪽으로 옮겼는지를 코드가 따로 알아야 한다.
_Avoid_: 힙 전환(`db_change_private_heap` 자체와 혼동), 얕은 대입

**빌림·반납 브래킷 (borrow/return bracket)**:
CBRD-27327의 채택 수정 형태 — 패스 **시작**(`manager::open()`의 handler 생성)에서 누산기를 코디네이터 heap → heap 0으로 빌리고, 패스 **안**(`read_node`)에서 heap 0 → 코디네이터 heap으로 반납하는 대칭 규약이다. 반납을 패스 끝(`read_finalize`)에 두면 안 되는 이유는 `read_finalize`가 `manager::end()`를 통해 쿼리 최종 종료 시에도 불리기 때문이다. ADR 0015 참조.
_Avoid_: 파티션 게이트(증상 회피안 — 기각), `read_finalize` 반납(최종 teardown에서 재발)

**체크포인트-조용 레그 (checkpoint-quiet leg)**:
YCSB 게이트 레그를 측정창 안에서 체크포인트가 발화하지 않는 conf(`checkpoint_every_size`·`checkpoint_interval`을 실행 길이 위로)로 수행하는 규약이다. 서버 이벤트 로그의 체크포인트 이벤트 0회가 레그 유효 조건이며, 비교 대상이 cas-merge 자기 자신이라 #125 절대치 비교는 포기한다. 체크포인트를 끄는 것이 아니라 창 밖으로 미루는 것이다.
_Avoid_: 체크포인트 비활성화, #125 conf(축자 conf와 혼동)

**귀속 hold (attribution hold)**:
게이트에서 p99가 기준선 중앙값 대비 허용폭(현재 +10%)을 넘었을 때 자동 fail이 아니라 원인 귀속을 요구하며 판정을 보류하는 상태다. 선존 기계로 귀속되면 기록 후 통과하고, 귀속에 실패하면 fail이다.
_Avoid_: 자동 fail, 참고 지표(무시와 혼동)

### CTP 실행 도구 (컨테이너 격리 러너)

**설치본 (install)**:
`just build`가 만든 실행 가능한 CUBRID 디렉토리(`~/<mode>/CUBRID-<ver>`)다. 러너는 항상 설치본을 컨테이너에 마운트하며, 빌드 트리나 소스 체크아웃을 가리키지 않는다.
_Avoid_: 빌드(build — 빌드 트리·행위와 혼동), `--build` 옵션 이름을 개념명으로 쓰기

**시나리오 부분집합 (scenario subset)**:
사용자가 지정한 테스트케이스 하위트리들의 집합으로, "부분 실행"의 입력이다. 스위트(sql·medium·shell·ha_shell)마다 트리 루트가 다르며 한 실행의 부분집합은 한 루트 아래에 있어야 한다.
_Avoid_: 버킷(bucket — shell 카테고리 디렉토리 `_22_ha`처럼 트리의 한 계층을 가리킬 때만 쓴다), 케이스 리스트

**샤드 (shard)**:
오케스트레이터가 전체 스위트를 시간 균형으로 나눈 실행 단위로, 컨테이너 한 개와 1:1이다. 부분 실행은 샤드 1개짜리 실행이다.
_Avoid_: 노드(CircleCI 용어), 버킷, bulk(분할 입력 단위 — 샤드는 그 출력)

**캠페인 conf (campaign conf)**:
이 리포 루트의 `cubrid.conf`로, 호스트 설치본 conf의 유일한 원본이다. 호스트 `$CUBRID/conf/cubrid.conf`는 캠페인 conf와 포트 클레임의 파생물이며 직접 편집 대상이 아니다. 컨테이너 안 실행은 CTP가 자기 conf 섹션으로 덮으므로 캠페인 conf와 무관하다.
_Avoid_: 설치된 conf(파생물)를 원본처럼 부르기, 테스트 conf(CTP의 `[sql/cubrid.conf]` 섹션과 혼동)

**출처 (provenance)**:
한 CTP 실행이 정확히 무엇을 검증했는지를 사후에 판별하게 하는 기록 — 설치본, 러너 이미지, CTP 리비전, 테스트케이스 리포별 ref와 커밋. 실행 요약 첫머리와 실행 디렉토리에 항상 남긴다.
_Avoid_: 로그(실행 과정 기록과 혼동), 메타데이터

**CAS 통합 JIRA**:
CAS 통합의 목적·영향·종합 평가·제품화 판단을 정리하는 상위 이슈와, 기존 GitHub 티켓의 결정·구현·측정 근거를 기록하는 하위 이슈로 구성된다. 완료된 작업은 기존 결과를 기록하며, 기록을 분리하기 위해 재구현·재측정하지 않는다.
_Avoid_: 별도 결함 PR 시리즈, 기록 분리를 위한 재검증 작업

**CAS 통합 PoC 검토**:
CAS와 서버를 통합했을 때의 사양·운영 영향을 정리하고, 추가 최적화 후보를 실험적으로 구현·측정하여 제품화 판단의 근거를 확보하는 작업이다. OLTP 성능 개선과 CAS별 중복 자원의 공유를 통한 메모리 감소를 핵심 목적으로 삼으며, 근거와 후속 과제가 정리되면 도입 보류도 완료로 인정한다. develop 반영은 완료 조건에 포함하지 않는다.
_Avoid_: 제품 반영 완료, 성능 개선 보장

**CAS 통합 성능 선측정**:
통합 후 최적화 후보를 제품 수준의 제약·오류 처리를 모두 갖추기 전에 구현하여 성능 효과를 먼저 확인하는 PoC 단계다. 측정 효과와 적용 조건을 근거로 제품화 여부를 판단하며, 제품화에 필요한 안정성 확보는 후속 단계에서 수행한다.
_Avoid_: 제품화 완료, 가능성 조사만 수행

**CAS 종속 운영 표면**:
CAS 프로세스나 CAS 풀 슬롯을 직접 식별·제어하는 명령, 상태 출력, 로그 파일 식별 규약을 뜻한다. SQL 실행·설정·진단이라는 사용자 기능 자체와 구분한다.
_Avoid_: 운영 기능 전체, 드라이버 wire protocol

**CAS 통합 클라이언트 종류**:
접속자가 사용하는 프로토콜 계열을 구분하는 이름으로 csql·JDBC·ODBC·CCI 등을 뜻한다. 실제 애플리케이션 이름과는 다르며, CCI로 자신을 알리는 래퍼도 CCI에 속한다.
_Avoid_: 애플리케이션명, CAS 프로세스명

**세션별 상세 계측**:
선택한 접속의 요청 종류별 횟수·송수신량·서버 처리시간을 수집하는 진단 기능이다. 서버 처리시간은 클라이언트가 관측하는 왕복시간과 구분한다.
_Avoid_: 서버 전체 statdump, 클라이언트 RTT

### 도메인·collation 사전 확정 (지도: xmilex-git/workspace#312)

**공통 타입 (common type)**:
서로 다른 타입의 피연산자가 만났을 때 현행 격자(문자×숫자 → DOUBLE, 정수×NUMERIC → NUMERIC, 날짜±숫자 → 날짜 …)가 정하는 결과 타입이다. 이 캠페인은 격자를 바꾸지 않는다(D-317-03·23). "애매한 자리에 DOUBLE/VARCHAR 를 강제한다" 는 초기 안은 게이트 확정으로 대체됐다(D-317-02).
_Avoid_: 승격(promotion) 규칙과 혼용, DOUBLE/VARCHAR 폴백이 아직 있다는 서술

**변환 계획 (conversion plan)**:
"어떤 regu_var 를 어떤 domain/collation 으로 변환하는가" 의 표. 컴파일(클라이언트 파서 → XASL 생성)이 기존 도메인 필드로 XASL 에 싣고, 로드 도출이 노드마다 변환 계획 항목으로 펼친다. 실행은 이 표를 읽기만 하고 새로 결정하지 않는다.
_Avoid_: 기대 도메인(슬롯 하나의 추론 결과)과 혼용, 플랜 캐시 키, 스트림에 팩되는 별도 섹션으로 서술

**서버 게이트 (server gate)**:
XASL 블록의 mainblock 스캔이 열리기 전에 실행당 1회 도는 지점. 변환 계획을 읽어 슬롯(호스트 변수·auto-param·세션변수 읽기·PL 인자) 값을 계획 도메인으로 변환하고, 게이트 확정 슬롯의 도메인과 collation 을 바인드 값으로 정해 파생 소비자(리스트 컬럼·누산기·비교 도메인·변환기)에 전파한다. collation 축의 마지막 결정 지점이기도 하다 — 게이트 뒤에 값을 보고 collation 을 정하는 코드는 없다. 결과는 XASL_STATE 에 두고 플랜은 불변이다. 결정 지점은 컴파일과 이 게이트 두 곳뿐이며 PX 워커는 깊은 복사를 상속만 한다.
_Avoid_: execute 직전 잔여 확정(이전 캠페인 용어), 세 번째 결정 지점(PX 워커), 플랜 안의 DB_VALUE 를 바꾸는 제자리 coerce, 블록 게이트(G2 — 폐기됨, D-323-08)

**게이트 확정 슬롯 (gate-resolved slot)**:
형제가 부류를 정하지 못해 컴파일이 "게이트 확정" 으로만 표시하는 슬롯 — 형제가 전부 슬롯인 자리, 집계·분석 인자, ENUM 산술, 값 요구 함수 인자, 형제 없는 세션변수 읽기. 게이트가 실행당 1회 값 타입으로 확정한다(D-317-02·12·13). 문자 슬롯이면 collation 도 같은 자리에서 값 collation 의 병합으로 확정된다(D-322-01) — 도메인과 collation 은 게이트 표의 한 항목이다.
_Avoid_: 늦은 바인딩(행마다 결정)과 혼용, 타입만 게이트에서 정하고 collation 은 실행에 남기는 서술

**collation 병합 (collation merge)**:
문자 피연산자들의 collation 에서 하나의 공통 collation 을 고르는 규칙. 컴파일에서는 coercibility 레벨로(컬럼 > 식 > 리터럴 > 슬롯), 게이트에서는 바인드 값들의 collation 으로(같으면 그것, 한쪽만 coercible 이면 다른 쪽, 둘 다 coercible 이면 바이너리, 둘 다 비-coercible 이면 충돌 오류) 병합한다. 규칙 자체는 현행이며 이 캠페인이 바꾸는 것은 게이트 병합의 시점(행 평가 → 게이트)뿐이다.
_Avoid_: LEAVE 계약(실행이 값을 보고 정하는 현행 기법 — 제거 대상), 세션 collation 을 컴파일에 고정하는 서술(PG/MySQL 모델, 이 캠페인은 채택하지 않음)

**형제 ENFORCE (sibling enforce)**:
문자 형제(컬럼·리터럴·CAST·ENUM 컬럼)가 있는 연산자·함수의 직접 인자 슬롯에 컴파일이 형제 collation 을 고정하는 현행 규칙. 형제 미러의 collation 판이며, 중첩 식 안의 슬롯까지 내려보내지 않는다(D-322-02) — 안쪽 식은 게이트 확정 뒤 계획된 CAST 로 바깥 collation 에 맞춘다.
_Avoid_: 하향 전파(previous-campaign 용어), 형제 미러와 혼용(타입 축)

**피연산자 부류 (operand class)**:
변환 시점을 정하는 네 부류. 상수 부류(리터럴 = 컴파일 폴딩, 슬롯 = 게이트 1회) · 행 의존 부류(컬럼·컬럼 식 = 계획된 변환기로 행마다) · 상관 부류(외부 행 값·비상관 서브쿼리 결과 = 스코프 진입 시 실행 임시값으로 스코프당 1회) · 휘발 부류(세션변수·난수 등 = 도메인은 게이트 1회, 값은 행마다)(D-317-17, D-323-18). 부류는 로드 도출이 정하며 플랜 항목에만 있다.
_Avoid_: "행당 변환 0회" (목표는 행당 결정 0회), "세 부류" (휘발 부류 신설 전 서술)

**계획된 변환기 (planned converter)**:
로드 도출(컴파일 확정 자리) 또는 실행 게이트(게이트 확정 자리)가 술어·산술·키 원소마다 고정한 (목표 도메인, 피연산자별 셀 함수, 실패 정책). 실행은 타입 판정 분기 없이 이 셀 함수만 부른다. 변환 방향과 도메인은 현행 서버 표를 그대로 옮긴 것이다(D-317-16·19).
_Avoid_: 실행 시 rank 판정·타입 switch 를 거치는 변환, 셀 안에서 다시 타입을 판정하는 래퍼

**변환 모드 (conversion mode)**:
계획된 변환기 표의 첫 인덱스. 변환 실패의 정의만 다르고 성공 값은 같은 세 가지 — 대입(현행 `tp_value_cast` 명시 모드: 정수 목표 반올림·인쇄·절단 검사; 대입 자리와 CAST 노드 아래 슬롯) · 비교(현행 `tp_value_coerce_strict`: 손실이면 실패, 비교와 인덱스 키가 공유) · 피연산자(비교 모드 + NUMERIC ← 실수 허용; 산술·함수 인자·집계·공통값·리스트 컬럼)(D-325-01·02).
_Avoid_: 문맥(`DOMAIN_CTX`) 9종을 그대로 표 인덱스로 쓰는 서술, "산술은 전부 strict" 처럼 CAST 소비자 슬롯을 빠뜨리는 서술, 게이트 의존 노드 안의 사전 캐스트(날짜×실수 → BIGINT 등)를 피연산자 모드로 서술(대입 모드다, D-328-04), KEEP 뒤 행 비교 변환을 비교 모드로 서술(대입 모드 셀이다, D-328-05)

**피연산자 목표 도메인 (operand target domain)**:
도메인 해석기가 결과 도메인과 별도로 피연산자마다 내는 변환 목표. 계획된 변환기는 이 목표에 대해 조회되며, 날짜 + 정수처럼 kernel 이 이종 입력을 그대로 받는 연산에서는 결과 도메인과 다르다(D-328-03).
_Avoid_: 결과 도메인으로 피연산자 변환기를 조회하는 서술

**KEEP 판정 (keep test)**:
비교·키 자리에서 값을 형제 도메인으로 무손실 변환할 수 있는지를 비교 모드 셀(strict)로 1회 묻는 것. 실패하면 값은 원 도메인을 유지하고(keep) 해석기가 비교 도메인을 정한 뒤, 행 비교의 변환기는 대입 모드 셀로 잡힌다(D-328-05). 판정은 게이트·range open 에서만 일어나고 행 루프에는 없다.
_Avoid_: strict 변환 실패를 곧 "비교 불가" 로 서술(INT 3600 = TIME 01:00:00 은 동등이다), 행마다 판정

**값 분류 (value classification)**:
값의 내용으로 결과 타입이 갈리는 자리(MEDIAN/PERCENTILE 슬롯의 DOUBLE→DATETIME→TIME 시도, STR_TO_DATE 포맷 토큰, ADDTIME 의 존 유무)에서 게이트가 해석기를 부르기 전에 값을 한 번 보고 타입을 정하는 것. 해석기 입력은 여전히 타입뿐이다(D-328-06).
_Avoid_: 해석기에 값을 넘기는 서술, 행마다 다시 분류하는 것(휘발 값은 타입이 바뀐 행에서만)

**절단 수용 (truncation acceptance)**:
문자·비트를 짧은 길이의 도메인으로 바꿀 때 셀 함수가 절단 값과 함께 `DOMAIN_TRUNCATED` 를 돌려주고, 그 값을 받아들일지는 항목이 정하는 규칙 — 사용자 CAST 의 컬럼·세션변수·식 피연산자는 무조건 수용(현행 FORCE 캐스트), 대입·시그니처 CAST·CAST 아래 슬롯은 `allow_truncated_string` 을 따른다(D-328-02).
_Avoid_: 절단을 OVERFLOW 실패로만 서술, 사용자 CAST 를 명시 모드(설정을 보는) 캐스트로 서술

**셀 함수 (leaf)**:
변환기 표의 원소 — (원 타입, 목표 타입, 변환 모드)가 고정된 함수 하나. `tp_value_cast_internal`·`tp_value_coerce_strict` 의 안쪽 case 본문을 뽑은 것으로, 안에서 값 타입을 다시 판정하지 않고 상태(`TP_DOMAIN_STATUS`)만 돌려준다. 실패 정책은 항목을 읽은 호출자가 적용한다(D-325-03·04·07).
_Avoid_: `tp_value_cast` 를 다시 부르는 래퍼를 셀이라 부르는 것, 셀 안의 `er_set`(셀이 부르는 파서도 상태만 돌려주는 코어여야 한다, D-328-07), 셀 한 단계 아래의 타입 switch(검수 범위는 호출 경로 전체, D-328-01)

**기대 도메인 (expected domain)**:
컴파일 시 파서가 `?` 를 비교·대입 상대(컬럼 등)로부터 추론한 도메인. 변환 계획의 입력이다.
_Avoid_: 바인드 도메인(실제 값의 타입과 혼동), 호스트 변수 타입

**바인드 도메인 (bound domain)**:
execute 시 드라이버가 보낸 실제 값의 도메인. 클라이언트는 이 값을 캐스트하지 않고 그대로 보내며, 서버 게이트가 변환한다.
_Avoid_: 기대 도메인과 혼용

**형제 미러 (sibling mirror)**:
슬롯(호스트 변수·auto-param·세션변수 읽기)의 타입을 같은 식에서 타입이 알려진 형제(컬럼·리터럴·CAST 결과·PL 선언 타입)로부터 확정하는 규칙이었다. **철회(D-336-B, 2026-09-24)**: 컴파일은 슬롯 타입을 만들지 않는다 — develop 이 이미 클라이언트에서 캐스트하는 비교·대입 자리만 컴파일 도메인이고, 산술·함수 인자·공통값·집계·UNION/VALUES·TO_CHAR·세션변수 자리는 게이트 확정이다(형제 미러는 develop 의 값 의존 답을 바꾼다; `docs/research/domain-pin-slot-gate-design.md`). 용어는 이력 문서(규칙표 §7·#319·#327)를 읽을 때만 쓴다.
_Avoid_: 기대 도메인(추론 결과물)과 혼용, 타입 승격, 시그니처 CAST 뒤의 노드를 형제로 세는 것(형제는 원 노드), 게이트 확정 식을 형제로 미러하는 것(미러는 직접 슬롯 인자에만, D-327-08)

**소비자 도메인 우선 (consumer-domain precedence)**:
형제 미러의 우선순위였다 — 식 결과의 소비자(대입 대상 컬럼)가 정한 기대 도메인이 중첩 식 안의 슬롯에 먼저 닿는다(D-327-11). **형제 미러와 함께 철회(D-336-B)**: `INSERT decimal(10,5) VALUES (IFNULL(?, 0))` 의 `?` 는 게이트 슬롯이고 값(NUMERIC)이 그대로 대입되어 develop 답(12.34568)이 유지된다.
_Avoid_: 하향 전파(이전 캠페인 용어; collation 축 형제 ENFORCE 는 내려보내지 않는다 D-322-02), 노드 단위 "컬럼 > 리터럴" 순위표

**게이트 의존 노드 (gate-dependent node)**:
게이트 확정 슬롯이나 다른 게이트 의존 노드를 피연산자로 가진 식 노드(`abs(?) + 1`, `(? + ?) + 1`, `coalesce(?, ?) + 1`). 형제가 있어도 미러하지 않고, 실행 게이트(G1)가 생산자 우선 순서로 현행 격자를 실행당 1회 적용해 도메인을 게이트 표에 확정한다(D-327-08). 현행 파서의 "인자 하나라도 MAYBE 면 결과 MAYBE" 를 게이트 1회 확정으로 옮긴 것이라 답은 그대로다. 로드 도출이 그 목록을 만든다.
_Avoid_: 바깥 형제 타입으로 미러 + 계획된 CAST(collation 축의 방식, 타입 축에서는 답이 바뀐다), 행마다 격자를 다시 푸는 것

**실패 정책 (failure policy)**:
계획 항목마다 붙는, 게이트 변환이 실패했을 때의 의미 — 오류(-494) / NULL(`return_null_on_function_errors=yes` 인 산술·함수 인자 자리) / keep(비교의 strict-or-keep). 현행이 그 문맥에서 하던 대로를 게이트 시점으로 옮긴 것이다(D-327-10). 한 `?` 가 여러 자리에서 참조되면 NULL 은 참조별 계획 슬롯에만 들어가고 공유 값 배열의 원 값은 바뀌지 않는다.
_Avoid_: 게이트 실패를 일률적으로 -494 또는 NULL 로 서술, 파라미터를 대입 자리까지 적용

**문맥 없는 슬롯 (context-free slot)**:
같은 식의 형제가 전부 슬롯이라 컴파일이 타입을 정할 수 없는 자리(`SELECT ?`, `? + ?`, `? = ?`, `sum(?)`, `coalesce(?, ?)` 등). 컴파일은 "게이트 확정" 으로 표시만 하고 서버 게이트가 바인드 값의 타입으로 실행당 1회 확정한다(D-317-02).
_Avoid_: 문맥 없는 슬롯에 DOUBLE/VARCHAR 기본형을 강제하는 서술, 늦은 바인딩(행마다 결정)과 혼용

**늦은 바인딩 (late binding)**:
도메인을 `DB_TYPE_VARIABLE` 로 남겨 두고 실행 하위에서 행·값을 보고 푸는 현행 기법 전반 — fetch 의 `tp_domain_resolve_value` 확정, 산술 도메인 탈착·복원, 집계 첫 non-NULL 대기, 리스트 스캔 도메인 확정, 키 범위의 매 실행 변환 등. 이 지도의 제거 대상.
_Avoid_: HV late binding 을 파라미터 `hostvar_late_binding` 하나로 좁혀 부르기

**로드 도출 (load-time derivation)**:
XASL 스트림을 트리로 언팩한 직후, 로드된 트리의 순수 함수로 계산해 비팩 필드에 두는 것 — 슬롯 ID, 피연산자 부류, 변환기 선택, 게이트 의존 노드 목록. 결정이 아니다: 컴파일이 실은 도메인에서 기계적으로 따라 나오며, 세 로드 경로(플랜 캐시 클론·비캐시·PX 워커 언팩)가 같은 결과를 얻는다. 스트림 레이아웃을 바꾸지 않고 실행마다 다시 계산하지도 않는다(D-318-01·02).
_Avoid_: 실행 중 플랜 필드에 쓰는 것(늦은 바인딩), 계획을 스트림에 별도 섹션으로 팩하는 것

**게이트 표 (gate table)** — 코드 이름 `RESOLVED_DOMAIN`:
XASL_STATE 에 사는 실행별 항목 — 게이트 확정 슬롯과 그 파생 소비자(산술 결과·리스트 컬럼·누산기·정렬 키·비교 도메인)의 실행당 답(도메인, collation, 변환기)이 여기에만 있고 플랜에는 없다. 실행 게이트가 채운 뒤 봉인되어 실행 중 누구도 쓰지 않으며, PX 워커는 이 표를 값 배열과 함께 깊은 복사로 상속한다(D-318-03·06, D-323-08).
_Avoid_: 플랜 노드의 `domain` 필드(불변), 바인드 값 배열과 혼용, 실행 중 쓰기

**변환 계획 항목 (plan item)** — 코드 이름 `DOMAIN_PLAN`:
로드 도출이 트리의 노드(regu·산술·집계·분석·위치 서술자)마다 하나씩 만들어 플랜 쪽에 두는 불변 기록 — 피연산자 부류, 게이트 표 슬롯 번호 또는 컴파일 확정 답, 참조 자리, 변환기. 플랜 캐시 클론과 수명을 같이한다(D-323-01).
_Avoid_: 게이트 표(실행별)와 혼용, 스트림에 팩되는 것으로 서술

**실행 게이트 (execution gate, G1)**:
서버 게이트의 유일한 단계. 실행당 1회, 값 배열 형성 직후·mainblock 진입 전에 로드 도출 목록(상수 참조·휘발 항목·게이트 의존 노드·상수 키)을 전부 처리해 트리 어디에도 미확정을 남기지 않고 게이트 표를 봉인한다. 이전에 두었던 블록 게이트(G2)는 폐기됐다 — mainblock 안에서는 결정도 표 쓰기도 없다(D-323-08, D-318-08 대체).
_Avoid_: 블록 게이트·G2, 스캔 open 마다 도메인을 정하는 것, mainblock 안 도메인 결정

**실행 임시값 (execution temporary)**:
스코프(스캔·range·집계 그룹)에 진입할 때 이미 계획된 변환기를 1회 적용해 그 스코프의 기존 실행 상태에 두는 값, 그리고 상관 복합 키의 혼합 setdomain 같은 스코프 한정 파생물. 결정이 아니라 캐시이며, 플랜과 게이트 표는 그대로 읽기 전용이다(D-323-08).
_Avoid_: 게이트 표에 쓰는 것, 두 번째 결정 지점으로 서술

**참조 자리 (reference slot)**:
같은 `?`(val_pos) 를 참조하는 regu 마다 따로 두는 변환값 자리. (val_pos, 목표 도메인, 실패 정책)이 같으면 자리를 공유하고, 다르면(등식 축약·UNION 푸시다운이 다른 형제 옆에 같은 `?` 를 복사한 경우) 자리가 갈린다. 실패 정책의 NULL 은 그 자리에만 들어가고 원 바인드 값은 불변이다(D-323-03·04).
_Avoid_: val_pos 와 혼용, 바인드 값 배열을 제자리 변환하는 것

**휘발 피연산자 (volatile operand)**:
값이 실행 중 바뀌거나 부작용이 있는 연산자(세션변수 읽기·쓰기, 난수, serial, last_insert_id, row_count, guid 등)와 그것을 품은 식. 피연산자 3부류에 더한 넷째 부류로, 도메인은 실행 게이트가 1회 확정하되 값은 행마다 읽어 계획된 변환기로 맞춘다(D-323-18).
_Avoid_: 상수 부류로 오분류(값을 게이트에서 한 번 읽고 캐시하는 것), 잎이 상수라는 이유만으로 부분트리를 상수화하는 것

**로드 예외 표 (load exception table)**:
설계상 도메인이 미확정으로 남아도 되는 자리(값이 없는 포장 노드·분석 윈도우 정렬 키·집합 연산 컬럼·값 없는 특수 regu·집합 생성자·세션변수 읽기·실행 결정 잔존)의 목록. 로드 경계가 이 표 밖의 미확정만 거부한다(D-323-09).
_Avoid_: 예외를 코드 주석에만 두는 것

**경계 오류 (boundary error)**:
로드 또는 실행 중 미확정 도메인에 닿았을 때 내는 전용 오류. 조용한 재컴파일을 유발하는 기존 오류 코드를 재사용하지 않으며 재컴파일 트리거 목록에 넣지 않는다(D-318-04, D-323-09).
_Avoid_: `ER_QPROC_INVALID_XASLNODE` 재사용

### 온디스크 바이트오더 조사 (CBRD-27366)

**고정 LE 전환 (fixed little-endian)**:
온디스크 정수 표현을 플랫폼과 무관하게 little-endian 하나로 못박는 포맷 변경이다. 볼륨을 기록한 기계의 바이트오더를 따르는 host-native와 다르며, 어느 시점에도 두 바이트오더를 동시에 지원하지 않는다.
_Avoid_: native 바이트오더(host-native와 혼동), 엔디안 지원

**이중 지원 (dual-format support)**:
하나의 바이너리가 구 BE 볼륨과 신 LE 볼륨을 함께 읽는 상태로, 마이그레이션 창에서만 나타날 수 있는 과도 상태다. 설계 목표가 아니며 레코드 언패킹 hot path에 런타임 분기를 수반한다.
_Avoid_: 하위 호환, 엔디안 중립

### MVCC 레코드 헤더 조사 (CBRD-27368)

**헤더 고정화 (fixed-size MVCC header)**:
가변 8~32B인 MVCC 레코드 헤더를 플래그와 무관하게 한 크기(제안된 값은 32B)로 못박는 포맷 변경이다. 온디스크 포맷과 WAL(undo 이미지)을 동시에 바꾸므로 `disk_compatibility_level` 인상과 마이그레이션을 수반한다.
_Avoid_: 헤더 크기 계산 호이스팅(포맷 무관한 코드 변경과 혼동), 레이아웃 현대화(세 제안을 뭉뚱그림)

**vacuum 헤더 축소 (vacuum header shrink)**:
vacuum이 전역 가시 레코드의 INSID·PREV_VERSION 플래그를 끄고 페이로드를 좌측으로 옮겨 레코드 길이 자체를 줄이는 동작이다. 현행 엔진이 이미 수행하며 home 레코드를 8B 하한까지 내린다. REC_BIGONE(오버플로)은 의도적 예외로 32B에 고정된다.
_Avoid_: 플래그만 끄는 것(길이가 실제로 줄어듦), 최소 헤더 비율 상향(이미 달성된 상태를 미달성처럼 부름)

**헤더 크기 계산 호이스팅 (header-size hoisting)**:
헤더 크기를 레코드당 한 번만 구해 재사용하도록 코드를 바꾸는 최적화다. 현행은 속성 접근 매크로가 레코드당 O(속성 수)회 `or_header_size()`를 아웃오브라인 호출하며 매번 다시 계산한다. 온디스크 포맷과 무관하다.
_Avoid_: 헤더 고정화(포맷 변경을 수반함), 헤더 크기 룩업 제거(룩업 자체가 아니라 반복 호출이 대상)

**회수 공간 재사용 (reclaimed-space reuse)**:
헤더 축소로 페이지 안에 생긴 여유가 값을 갖기 위한 조건 — 이후 INSERT가 그 페이지를 다시 쓰는 것이다. OID가 물리 주소라 기존 레코드는 옮길 수 없으므로, 사후 축소는 힙 페이지 수를 줄이지 않고 이미 적재된 데이터의 풀스캔 I/O도 줄이지 않는다.
_Avoid_: 축소 가능 바이트를 곧바로 스캔량 감소로 환산, 공간 이득과 스캔 이득을 같은 지표로 취급

**OR 레이어 (OR layer)**:
`OR_GET_*`/`OR_PUT_*` 매크로와 그 위의 `or_pack_*`/`or_unpack_*` 함수군이 이루는 단일 직렬화 계층으로, 바이트오더 결정 하나가 디스크 레코드와 클라이언트-서버 와이어 프로토콜을 함께 지배한다. 반면 슬롯 페이지·볼륨·로그·btree 노드 헤더는 이 계층을 타지 않는 native 구조체다.
_Avoid_: 온디스크 포맷(디스크 전용이라는 오해를 부름), 레코드 포맷
