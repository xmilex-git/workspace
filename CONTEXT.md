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

**신선한 체크포인트 (fresh checkpoint)**:
온라인 FULL 백업 진입 시점에 capture한 append LSA(T) 이후에 완료되어 redo LSA(R) ≥ T를 만족하는 checkpoint다. 백업 진입 전부터 진행 중이던 checkpoint는 R이 T보다 앞설 수 있으므로 아무리 기다려도 fresh로 인정하지 않는다.
_Avoid_: "진행 중 checkpoint 대기 완료"를 fresh로 간주, 최신 checkpoint

### HTAP POC (지도: xmilex-git/workspace#30)

**CUBRID CDC 인프라**:
CUBRID에 이미 존재하는 로그 변경 추출 층 — 서버측 `cdc_*`(log_manager.c) 데몬과 클라이언트 라이브러리 `cubrid_log` C API. 이벤트를 서빙할 뿐, 소비 루프는 포함하지 않는다.
_Avoid_: CDC agent(소비자와 혼동), 복제 기능

**CUBRID Debezium 커넥터 (debezium-connector-cubrid)**:
CUBRID CDC 인프라를 JNA로 소비해 Debezium envelope로 Kafka에 내보내는 정식 Debezium 소스 커넥터. 이 프로젝트가 만드는 유일한 CDC 소비자다 (ADR 0002).
_Avoid_: cubrid-cdc-agent(자체 agent 안 — 기각됨), CDC 도구

**current-state 복제본**:
ClickHouse ReplacingMergeTree(`_version`, `_is_deleted`)에 유지되는 원본 테이블의 최신 상태 사본. 정확한 조회는 canonical `FINAL` view를 통해서만 한다.
_Avoid_: 미러, 실시간 동기 테이블(동기 복제로 오해)

**쓰기 정지 스냅샷 (write-stop snapshot)**:
대상 테이블 쓰기를 멈추고 barrier LSA를 기록한 뒤 full scan을 적재하고, CDC를 barrier 이후부터 시작하는 POC용 초기 적재 방식. online snapshot은 제품 단계 과제다.
_Avoid_: 온라인 스냅샷, 일관 스냅샷(MVCC token 기반과 혼동)
