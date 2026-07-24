# Issue #163 Phase 3 — 제품 설계 선택지 (grill 자료, 2026-07-24)

사용자 확정 전제(이슈 comment/대화 기록):
- **버전 스큐는 운영상 존재하지 않는다** — negotiation 기계장치 불요, 현행 version
  fail-fast(불일치 시 attach 거부→CAS)는 안전핀으로만 유지.
- **최종 목표**: prepare는 CAS, execute는 **holdable + UPDATE/INSERT/DELETE 포함 전부
  direct**.

각 항목: 선택지 / 성능 / 복잡도 / 호환성 / 운영 위험 / migration 비용.
결정은 grill 후 ADR로 고정한 뒤에만 구현한다.

## D1. 최종 연결 모델

| 선택지 | 성능 | 복잡도 | 호환성 | 운영 위험 | migration |
|---|---|---|---|---|---|
| (a) CAS prepare + Direct execute 유지 (현행) | 실측 +47%(2T)/+25~72%(32T fast) | 낮음 | fallback 상존 → 최고 | 이중 연결 footprint(2×tran slot, CAS process) | 없음 |
| (b) prepare 후 CAS detach | (a)와 동일(idle CAS는 hot path 밖) | 중간 — UConnection 사용처 전체 가드 + 재prepare 시 재접속 | detach 후 fallback 불가 → DML direct 완성 후에만 안전 | 재prepare/metadata 요청 시 재연결 지연 | JDBC 내부 개편 |
| (c) prepare/execute 모두 direct | prepare 왕복 절약(재사용 환경에선 미미) | 매우 높음 — 파서/권한/plan 관리 server 이전 | CUBRID client-compile 구조 전면 변경 | 대규모 신규 표면 | 사실상 신규 프로젝트 |
| (d) gateway/connection service | hop 재도입으로 이득 상쇄 | 높음 | — | 새 계층 운영 | 새 인프라 |

권고: **(a)로 DML/holdable direct까지 완성 → footprint가 실제 문제로 판명되면 (b)를
후속 증분으로**. (c)(d)는 목표 대비 비용 비대칭.

## D2. session/transaction ownership (DML direct의 관문)

현행: logical connection 하나에 server tran 2개(CAS tran + direct tran). read-only
auto-commit에선 무해했으나 **DML direct에서는 정면 충돌**: 같은 connection에서 CAS로
간 statement(강등분)와 direct statement가 다른 tran → 원자성/가시성 깨짐.

| 선택지 | 성능 | 복잡도 | 호환성 | 운영 위험 | migration |
|---|---|---|---|---|---|
| (i) auto-commit 한정 DML direct — 강등분은 CAS tran, direct분은 direct tran, 문장 단위 커밋이라 tran 경계 공유 불요. explicit tran은 전부 CAS | DML direct의 대부분 이득 확보(YCSB A/B/F 패턴) | 낮음 | 문장 단위 의미 동일 | 낮음 — 단 동일 connection 연속 문장의 가시성은 커밋 후라 보존 | 소 |
| (ii) session/tran ownership을 direct로 이전 — CAS statement도 direct tran에 참여(CAS가 direct tran index를 공유) | explicit tran까지 direct | 높음 — CAS·server 양쪽 tran 바인딩 재설계, session 변수/role/schema 동기화 | 깊은 변경 | recovery/interrupt 재설계 | 대 |
| (iii) 2PC류 tran 연동 | — | 매우 높음 | — | 높음 | 대 |

권고: **(i)를 Phase 3 범위로**, (ii)는 explicit transaction 요구가 실측으로 확인될 때.
연동 필수 항목(어느 선택지든): user/role/schema 동기화 — 현행 PoC credential
(PUBLIC 고정)은 DML 전에 반드시 D5와 함께 해소.

## D3. 정식 protocol 표면

- version: 스큐 없음 전제 → 현행 fail-fast 유지, negotiation 없음 (확정 반영).
- constants/schema SSOT: engine header + JDBC 상수 + ADR 3곳 유지 vs 단일 정의
  파일에서 생성. 권고: DML 확장 시 message 종류가 늘어나므로 **생성 없이 3곳 유지하되
  cross-repo 상수 일치 integration test 추가** (복잡도 최소).
- result cursor/page fetch: single-response 유지 vs cursor 도입. 권고: **single-response
  유지 + 초과 시 CAS 강등**(prepare 시 예상 불가면 실행 후 초과 에러 대신, 초과 감지
  시 서버가 "너무 큼" 응답 → JDBC가 CAS로 재실행). YCSB E(scan)가 요구될 때만 cursor.
- error/SQLState/warning: DML은 제약 위반 등 에러가 일상 경로 → **server errid+message
  문자열 전송 승격 + CAS 에러코드 매핑 테이블** 필요(read-only PoC의 "errid만"으론 부족).
- timeout/cancel/interrupt: DML direct에는 cancel 부재가 더 위험(장기 lock 대기).
  선택지: (1) 그대로 무효 (2) direct socket 별도 interrupt 요청 (3) queryTimeout류는
  전부 CAS 강등 유지. 권고: Phase 3 전반부 (3) 유지, DML 안정 후 (2).

## D4. 인증·보안 (DML direct의 전제조건)

현행 PoC: localhost-only + 고정 credential("PUBLIC") — SELECT-only에서도 권한 우회가
가능한 구멍이며 **DML direct 전에 반드시 해소**.

| 선택지 | 복잡도 | 비고 |
|---|---|---|
| (A) CAS가 발급한 단기 토큰을 direct attach에 제시(연결 브로커링) — server가 CAS 세션과 동일 user로 등록 | 중 | 이중 연결 모델과 자연 정합. 권고 |
| (B) direct attach에 DB 계정 재인증 | 중 | credential 이중 관리 |
| (C) localhost + OS 신뢰 유지 | 저 | 제품화 불가, PoC 연장 시에만 |

TLS/remote/audit: localhost 전제 유지 여부가 선행 결정. 권고: Phase 3는 localhost
유지(성능 PoC 목적 정합), remote/TLS는 제품 요구 확정 후.

## D5. HA/장애 복구

스큐 없음 전제와 별개로 필요한 것: failover 시 direct connection 재수립 + XASL ID
무효화 처리. 권고 범위: **prepared plan invalidation만 Phase 3에서** (XASL cache miss
에러 → JDBC가 CAS re-prepare 후 take_xasl 재시도 — 현재는 fail). topology discovery/
reconnect/in-flight retry는 altHosts 기존 메커니즘에 위임하고 direct는 연결 단위로
따라감.

## D6. SQL 범위 확장 순서 (목표: 전부 direct)

권고 증분 순서 (각 단계 독립 검증):
1. **DML direct (UPDATE/INSERT/DELETE, auto-commit)** — affected-row count 응답,
   D2(i)+D4(A) 선행. YCSB A/B/F로 게이트.
2. type 확장: BIGINT/SHORT/FLOAT/DOUBLE/CHAR → NUMERIC/DATE/TIME/TIMESTAMP.
3. holdable 대형 결과: single-response 초과 시 CAS 강등 → cursor 필요성 실측 후 결정.
4. batch execution / generated keys.
5. LOB/SET/ENUM — 수요 확인 후.

## 성능 개선 잔여 후보 (분석 보고서 연계)

- 느린 regime 코드 지점 확정 + worker pool 정책(전용 스레드/파킹 타임아웃) — 32T
  신뢰도의 관문
- client framing/copy 최적화(CPU 61%가 socket/framing) — vertical #2
- read-only fast commit(engine 공통 경로)
