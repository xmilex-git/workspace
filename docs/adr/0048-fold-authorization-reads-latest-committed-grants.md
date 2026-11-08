---
status: accepted
date: 2026-11-08
---

# 폴드 서버의 권한 검사는 최신 커밋 grant를 읽는다

CAS 폴드(CBRD-27430, PR 7837) A6에서 REVOKE는 대상 클래스를 touch해 다른 세션의 prepared statement를 재컴파일시킨다([#118](https://github.com/xmilex-git/workspace/issues/118) D2). 그 재컴파일의 권한 검사(`authenticate_cache::update`)는 SERVER_MODE에서 사용자의 그룹과 grant를 `LC_FETCH_COMMITTED_VERSION`(최신 커밋 버전, 락·스냅샷 없음)으로 읽는다(사용자 결정 2026-11-08, [A6 이식](https://github.com/xmilex-git/workspace/issues/627)).

이유:

1. **스냅샷으로 읽으면 D2가 닫히지 않는다.** TLA+ 모델(`docs/tla/CBRD-27430-A6`)이 반례 H1을 냈고 런타임에서 재현됐다: REVOKE 커밋 전에 시작한 REPEATABLE READ 트랜잭션이 커밋 뒤에 컴파일하면 스냅샷이 옛 grant를 보여 통과하고, touch가 지운 뒤에 들어간 그 plan이 다음 트랜잭션의 kept 재실행에서 그대로 돈다(smoke case 36: `kept re-execute value = 1`).
2. **클래스 락 순서가 최신 커밋 읽기를 안전하게 만든다.** 컴파일은 클래스 SCH_S를 트랜잭션 끝까지 쥐고 권한을 읽고, REVOKE의 touch는 SCH_M이 필요하다. 그래서 grantee가 읽는 동안 REVOKE는 커밋할 수 없고, REVOKE의 커밋과 락 해제 사이에는 아무도 컴파일하지 못한다. 최신 커밋 버전은 락 없이 읽어도 클래스 락이 정한 순서와 어긋나지 않는다.

## Considered Options

- **최신 커밋 grant 읽기**: 채택. develop의 기존 프리미티브(CBRD-27369). 존재 확인 경로가 committed 읽기에 S 락을 잡지 않도록(`locator_decide_operation_type`)·클라이언트가 그 락을 캐시하지 않도록(`locator_lock_and_doesexist`) 두 줄을 함께 고쳤다(H2, H3).
- **스냅샷보다 오래된 트랜잭션이 넣은 plan을 그 트랜잭션 한정으로 표시**: 기각. develop의 스냅샷 의미를 지키지만, 스냅샷 기준 판정은 RC에서 같은 트랜잭션의 Au_cache 경로를 놓쳤다(TLC 반례); 트랜잭션 시작 기준은 tdes epoch와 XASL 캐시 필드가 더 필요하다.
- **수용·문서화**: 기각. RR과 뷰·시노님 경유 RC 컴파일에 temporal gap이 남는다.

## Consequences

- 스펙 변화(폴드 한정): REPEATABLE READ 트랜잭션에서도 권한은 스냅샷이 아니라 최신 커밋 기준이다 — 커밋된 REVOKE는 진행 중 트랜잭션의 다음 컴파일부터 거부하고, 커밋된 GRANT는 허용한다. CS/SA는 바뀌지 않는다.
- 권한 캐시 갱신(트랜잭션·클래스당 1회)이 워크스페이스 스냅샷 버전을 한 번 올린다: 그 트랜잭션의 이후 인스턴스 읽기가 서버(in-process)에서 다시 가져온다.
