# Codex heartbeat로 TPCH-SSPQ 운영 루프를 조정한다

상태: Accepted by user, 2026-07-29  
성격: Codex 플랫폼 이전 운영 ADR 및 용어집. 프로젝트의 측정·분석 규범은 GitHub
`xmilex-git/workspace/tpch-sspq/docs/adr/`의 Accepted ADR이 단일 권위다.

## 결정

### D1. 운영 토폴로지

- 오케스트레이터는 현재 Codex 태스크에 연결된 20분 heartbeat다.
- Telegram 조작은 이 Mac의 Telegram 데스크톱 앱을 Computer Use로 수행한다.
- Telegram 앱에서 목표 토픽 본문에 세션 ID가 확인되기 전에는 읽기 결과를 채택하거나 메시지를 전송하지 않는다.
- Aside REPL은 Telegram 접근성 트리 또는 토픽 식별이 실패할 때만 폴백으로 사용한다.
- Notion은 공식 커넥터를 기본 읽기·쓰기 경로로 사용한다.
- `notion_sync.js`는 공식 커넥터가 기존 특수 블록을 표현하지 못할 때만 단독 폴백으로 사용한다.

### D2. 운영 범위

현재 큐 `Q22 → Q10 → Q19 → Q5 → Q7 → Q6 → Q16 → Q12 → Q14 → Q11 → Q4 → Q13 → Q17 → Q20 → Q2`
까지 자동 운영한다.

heartbeat는 다음을 수행할 수 있다.

1. 현재 세션의 새 보고 읽기
2. 새 보고를 해당 Notion 현황판 행에 기록하고 쓰기 후 재조회 검증
3. 40분 이상 무보고이고 typing이 없을 때 상태 핑 전송
4. 분석 단계와 `🟢 Agent idle`이 현재 세션의 꼬리에서 모두 확인되면 세션 종료
5. 다음 쿼리 세션 하나 생성, 세션 ID 기록, 프롬프트 전송
6. 현황판·허브·개선 우선순위 갱신

동시에 측정 세션 둘을 운영하지 않는다.

### D3. 상태와 복구

heartbeat는 장기 프로세스가 아니라 멱등 조정자다. 매 실행에서 Telegram과 Notion을 다시 읽어
현재 상태를 재구성한다. Codex 대화 기억이나 로컬 임시 파일을 운영 상태의 단일 권위로 사용하지 않는다.

중복 방지 키는 다음 조합이다.

`query + session_id + report_timestamp + content_fingerprint`

Mac 잠자기나 앱 종료로 실행이 누락되면 다음 heartbeat에서 누락분을 한 번만 반영한다.
Telegram과 Notion이 충돌하면 자동 추측하지 않고 사용자에게 알린다.

### D4. 질문 대리답변

원격 에이전트의 질문은 아래 규범에서 답이 유일하게 결정되면 Codex가 사용자를 대신해 답하고 계속 진행한다.

1. 사용자의 최신 직접 지시
2. GitHub `tpch-sspq/docs/adr/`의 최신 Accepted ADR
3. GitHub `README.md`, `CONTEXT.md`, `docs/TEMPLATE-report-qNN.md`
4. Notion 마스터·허브·현황판
5. 현재 쿼리 실행 계획

과거 보고서는 참고자료이며 규범이 아니다. 규범이 충돌하거나 데이터 변경, 측정 계약 변경,
범위 확대 또는 복수의 합리적 선택지가 생기면 사용자에게 알리고 변경 작업을 중단한다.
대신 답한 내용과 근거 문서는 해당 쿼리 중간 로그에 남긴다.

### D5. 정지 조건

다음 조건에서는 Telegram 전송과 Notion 변경을 중단한다.

- 목표 세션 ID를 검증할 수 없음
- 동시 측정 세션 존재 가능성
- Notion 쓰기 후 재조회 검증 실패
- GitHub ADR과 실행 상태의 계약 불일치
- 규범으로 답이 유일하게 정해지지 않는 질문

정지 중 heartbeat는 읽기 전용으로 외부 상태를 확인하며 같은 블로커를 중복 보고하지 않는다.
Q2 완료 후 heartbeat를 일시정지하고 백로그는 사용자 승인 후 재개한다.

### D6. 사용자 알림

- 새 단계 보고 반영: 핵심 3~5줄
- 상태 핑 전송: 한 줄
- 쿼리 완료·다음 세션 전환: 완료 요약과 다음 대상
- 블로커·검증 실패: 즉시 보고
- 변화 없는 정상 폴링, typing 중, 40분 미만 무보고: 알림 없음

## 핵심 불변식

- GitHub Accepted ADR이 측정·분석 규범의 단일 권위다.
- ADR 0020의 `contract_revision: 2`, metadata, censoring 분리, configured-cap parity,
  이벤트 단위 표기, correctness-unverified, 결과 삭제 금지를 지킨다.
- ADR 0021에 따라 4단계의 각 문제 항목은 PG pin `5713b437...`의 대응 `file:line`을 채증한다.
- `PER_QUERY_CONNECTION_DIAG`를 단일 connection 결과라고 부르지 않는다.
- Q21은 완주 19개 complete-case Pareto 1위, 전체 최우선은 Q22 censored lower-bound로 구분한다.
- 분석 상태와 SF1 correctness 상태를 혼동하지 않는다.

## 용어집

**Heartbeat**  
현재 Codex 태스크를 주기적으로 깨워 외부 상태를 조정하는 스케줄러. 긴 `sleep` 프로세스가 아니다.

**조정자(reconciler)**  
Telegram의 실제 원격 세션과 Notion의 기록 상태를 비교해 빠진 전이만 한 번 수행하는 실행자.

**목표 세션 ID**  
현재 쿼리를 담당하는 gajae 세션의 고유 ID. 동일한 `workspace/main` 토픽 이름 대신 이것으로 대상을 식별한다.

**내용 지문(content fingerprint)**  
동일한 원격 보고를 여러 heartbeat가 중복 기록하지 않도록 정규화한 보고 내용의 해시.

**규범 질문**  
Accepted ADR과 명시된 운영 규칙을 적용하면 답이 하나로 결정되는 질문. Codex가 자동으로 답할 수 있다.

**진짜 애매한 질문**  
규범 충돌, 계약 변경, 데이터 변경, 범위 확대 또는 복수의 타당한 선택지를 포함해 사용자 판단이 필요한 질문.

**읽기 전용 정지**  
블로커가 해소될 때까지 Telegram 전송과 Notion 변경은 하지 않되 heartbeat가 외부 상태 확인은 계속하는 상태.
