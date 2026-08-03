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

**계획시점 해시 적격 (plan-time hash-eligible)**:
XASL 생성 시 select 리스트와 HAVING절의 형태만으로 결정되는 정적 플래그로, 런타임에 해시가 실제로 유지됐는지와는 별개다. 런타임 해시 상태와 혼용하지 않는다.
_Avoid_: 런타임 해시 상태, hash: true/partial
