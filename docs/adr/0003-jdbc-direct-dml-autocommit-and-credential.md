# JDBC direct Phase 3 — auto-commit 한정 DML direct + CAS 동일 credential 전달

Status: accepted

이슈 xmilex-git/cubrid#163 Phase 3의 목표(prepare만 CAS, holdable + UPDATE/INSERT/DELETE
포함 실행 전부 direct)를 향한 관문 결정 두 개를 고정한다.

1. **Session/transaction ownership = auto-commit 한정 DML direct.**
   logical connection 하나가 CAS tran + direct tran 두 개를 가지는 현행 구조에서,
   auto-commit은 문장 단위 커밋이라 두 tran이 경계를 공유할 필요가 없다 — 강등된
   statement(CAS tran)와 direct statement가 각자 즉시 커밋하므로 문장 수준 의미가
   동일하다. `setAutoCommit(false)`(explicit transaction)는 전부 CAS 경로 유지.
   ownership 이전(CAS statement가 direct tran에 참여)은 explicit tran의 direct 수요가
   실측으로 확인될 때 재론한다.

2. **Direct attach 인증 = CAS와 동일한 credential 전달 방식 재사용.**
   CAS의 원래 인증: JDBC→broker 접속 시 CAS가 `au_login(db_user, db_passwd)`
   (cas_execute.c:503)으로 클라이언트 측 catalog 대조 검증을 수행하고, 서버
   `xboot_register_client`(boot_sr.c:3160)는 password 검증 없이 credential의
   db_user를 정규화·등록한다(CUBRID의 신뢰 경계 = 인증된 클라이언트 계층).
   direct attach는 하드코딩된 "PUBLIC" 대신 **connection의 db_user를 attach payload로
   전달**해 동일한 xboot_register_client 경로로 등록한다. password 검증은 지금처럼
   broker 접속 시점에 CAS가 수행한 것을 이어받는다. 신규 인증 기계장치 없음.

## Considered Options

- explicit transaction까지 direct(ownership 이전): 기각(연기). CAS·server 양쪽 tran
  바인딩 재설계 + session 변수/role/schema 동기화가 필요한 대공사이며, 목표 workload
  (YCSB A/B/F)는 전부 auto-commit이다.
- CAS 발급 단기 토큰으로 direct attach 인증: 기각(연기). 더 강한 모델이지만 신규
  protocol/상태가 필요하다. cub_server가 어떤 클라이언트 타입에도 password를 직접
  검증하지 않는 기존 모델에서, localhost 제한 유지 시 credential 전달 방식이 새 구멍을
  만들지 않는다. remote direct를 여는 시점에 재론(D4, design 문서 참조).

## Consequences

- DML direct 응답에 affected-row count가 필요하고, 제약 위반 등 에러가 일상 경로가
  되므로 direct 응답의 server error message 문자열 전송 승격이 같은 슬라이스에 묶인다.
- direct attach가 user별 등록이 되므로 서버 통계/tranlist에서 실제 사용자로 보인다.
- localhost-only 전제는 유지된다. remote/TLS/토큰은 이 ADR을 supersede하는 결정 필요.
