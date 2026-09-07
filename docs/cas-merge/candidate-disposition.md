# 최적화 후보의 최종 판정과 구현 순서

상태: **사용자 결정 완료**. 기존 채택안에 동의했고, JDBC와 후속 보류 항목도 구현 대상으로 승격했다. 단일 현재 계획을 유지한다. 우선순위는 구현 순서이며 낮은 순위가 선택 사항이라는 뜻은 아니다. 채택은 후속 노력의 구현·검증 대상으로 삼는다는 뜻이며 지금 구현을 완료했다는 뜻이 아니다.

## 구현 순서

1. 공유 준비 객체와 native XASL, 실행 상태 분리. SQL/metadata/재계획 입력을 세션마다 계속 복제하지 않는 것까지 포함한다.
2. 공유 스키마와 내부 복사·할당·버퍼 중복 축소. 1순위의 완료를 막지 않도록 분리한다.
3. JDBC·PL 프로토콜, 실행 스레드 모델, 공유 권한·trigger/TLS 설정, 클래스 IS 락 경로도 이어서 구현한다. 각 의존관계에 따라 단계를 나눈다.

## 전체 판정

| ID | 최종 판정 | 포함하는 범위와 경계 |
|---|---|---|
| P1 | 채택·1순위 | 공유 준비 객체 / 세션 핸들 / 실행 상태 |
| P2 | 채택·1순위 | 공유 SQL 원문·정규형의 소유권. 원문과 정규형을 같은 문자열로 취급하지 않음 |
| P3 | 채택·1순위 | 불변 준비 metadata 공유. 임시 변환 metadata를 retained 절감으로 계산하지 않음 |
| P4 | 채택·1순위 | 세션별 retained parser/PT tree에 의존하지 않는 준비 결과. 현 mutable PT tree의 직접 공유는 불채택 |
| P5 | 채택·1순위 | bind-sensitive replan 입력과 mutable fingerprint 분리. 여러 plan variants는 미도입(D8) |
| P6 | 채택·1순위 | 불변 native plan+실행별 state, 내부 stream 경계 제거. 실제 외부/디스크 codec은 유지 |
| P7 | 필수 검증·1순위 | key/handle/parser/metadata/plan/state의 live·peak·retained 회계와 YCSB |
| S1 | 구조 경계 유지 | 사용자·미커밋 상태는 session-local. 컨텍스트 전체 공유나 bracket 무조건 삭제는 불채택 |
| S2 | 채택·2순위 | MOP table lazy/grow, committed name 정보 공유는 S3과 함께. MOP 자체 공유는 불채택 |
| S3 | 채택·2순위 | committed immutable schema descriptor와 transaction-local overlay 분리 |
| S4 | 현행 유지+2순위 확장 후보 | 이미 공유된 MOP-free domain 유지. OID/generation domain 확대는 S3 수명 설계 아래 검증 |
| S5 | 채택·후속 구현 | process 공통 권한 판정 cache의 신설. 1순위의 권한 검증·invalidation과 별개로 공유 판정 cache도 구현 |
| S6 | 채택·후속 구현 | trigger 정의의 추가 공유. 실행/deferred/미커밋 상태는 세션별 유지 |
| S7 | 채택·2순위, 범위 제한 | 불변 view 정의·schema metadata 공유. MOP에 bound된 현 mutable view parse tree 직접 공유는 불채택 |
| S8 | 채택·2순위 | default parameter+session delta, 작은 변수 저장의 allocation 정리. 세션 변수 값 공유는 불채택 |
| S9 | 현행 유지+2순위 | process AREA 유지, workspace heap lazy와 공유 객체 allocator 정리. AREA를 세션별 slab으로 일괄 전환하는 안은 불채택 |
| S10 | 채택·2순위, 범위 제한 | full class materialization 전에 좁은 server metadata read-through. heap_Guesschn의 불필요한 내부 의존 제거·축소도 구현 대상으로 삼되 utility/unknown-CHN 경로의 대체·존치 구분을 선행 |
| T1 | 채택·2순위 | 동기 실행 입력의 wrapper clone 축소. OBJECT 정규화와 history/result-cache 보유용 복사는 별도 |
| T2 | 채택·2순위 | 결과 첫 페이지의 ownership move/pin으로 중간 사본 제거. generated-key/autocommit 수명 보존 |
| T3 | 채택·2순위 | native result view와 cursor 상태 분리 |
| T4 | 채택·1순위 접점/2순위 정리 | native 준비·실행 API에 필요한 client/server scope 정리부터. 무조건 모든 error/allocator scope 제거는 불채택 |
| T5 | 채택·2순위 낮은 우선도 | 같은-process PL callback의 typed 호출. JVM 응답 wire는 유지 |
| T6 | 채택·2순위 낮은 우선도 | PL row 중간 구조체/vector 복사 정리. payload ownership 보존, 기본 YCSB 효과 미주장 |
| T7 | 채택·JDBC/PL 구현 | JVM prepare/execute/fetch 프로토콜 결합. 별도 PL 검증 필요 |
| T8 | 채택·2순위 낮은 우선도 | 기존 wire를 유지하는 SET 원소 nocopy 소비 검토 |
| R1 | 채택·후속 구현 | 접속당 스레드를 요청 worker pool로 전환. 준비 객체 공유의 선결조건으로 두지 않음 |
| R2 | 채택·2순위 | 로그 buffer lazy/활성 생산자별 보유. 로그 파일 구조·출력 정책 재설계는 포함하지 않음 |
| R3 | 채택·2순위 | 작은 초기 출력 buffer와 bounded growth/reuse/trim |
| R4 | 채택·후속 구현 | 공유 TLS config generation. 비-TLS YCSB로 효과를 판단하지 않음 |
| R5 | 채택·2순위 | server 최소 config와 legacy SHM 자료형 분리 |
| R6 | 채택·2순위, 범위 제한 | CAS slot의 obsolete 상태 축소. 새 관측·동기화 정책은 기존 운영 정책 작업과 조정 후 확정 |
| R7 | 채택·2순위 | request body/argv scratch allocation 축소 |
| R8 | 채택·2순위 | server 활성 경로와 legacy adapter 분리. 외부 driver 동작·function 계약은 유지 |
| R9 | 채택·2순위 | hint 불변 정의와 parse별 scratch 분리 |

“read latch 하나로 workspace 전체를 치환”, “mutable 전체 handle/PT/XASL graph를 그대로 공유”, “CHN만 확인하고 실행 중 schema 보호 lock 제거”는 위 채택안과 구분해 불채택한다. 각각 스키마 의미·세션 상태·실행 중 DDL 배제를 대체하지 못한다.

클래스 IS 락 경합 축소, read-only commit 빈 해시 작업 제거, TLS 접근 비용 정리도 후속 구현 대상으로 채택한다. fastpath와 retention은 목표를 달성하는 설계 선택지이며 상충하는 방법을 무조건 동시에 구현한다는 뜻은 아니다. cpp-perf-rules 재브레인스토밍에서 구체 기법·측정·게이트를 다듬는다. 약한 메모리 모델·DDL 기아·pin/회수 안전성을 보존한다.

## 단일 현재 계획 — 확정

기존 first-bind/bind-sensitive 재계획 정책을 보존한다. 여러 세션이 같은 key를 다른 plan으로 교체할 때의 성능 간섭·compile churn은 YCSB 측정 항목이다. 바인드별 여러 reusable plan을 저장하는 cache와 영구 generic fallback은 신설하지 않는다. 유효성·수명 때문에 old/new generation이 잠시 공존하는 것은 허용한다.

## JDBC 구현 범위

외부 JDBC 드라이버의 connection-local statement cache·server handle·eviction/reprepare·결과 metadata 연동과 PL 내부 JDBC의 왕복 축소를 구분해 다룬다. 기존 CAS V12 외부 wire 계약은 유지한다. 외부 드라이버 소스 변경은 실제 연동에 필요한 지점에 적용하며 의미 없는 변경을 의무화하지 않는다. PL 내부 protocol 결합은 C++/Java 양단의 별도 구현이다.

상세 코드와 검증 범위: [외부 JDBC·PL 내부 JDBC 조사](optimization-audit/jdbc-scope.md).

## 후속 노력으로 넘길 상세

전체 XASL mutable write inventory, 공유 compiler artifact 표현, dependency producer 전수 연결, 코드 단계·API와 gate의 상세는 채택 후보의 구현을 위한 후속 설계다. 이 지도에서 최적화 구현을 시작한 것으로 취급하지 않는다.
