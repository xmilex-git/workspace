---
status: accepted
date: 2026-11-09
---

# 폴드 서버의 AREA 할당 실패는 등록된 세션 브래킷의 client 절반에서만 트랜잭션을 abort한다

CAS 폴드(CBRD-27430, PR 7837)에서 client 절반의 AREA(도메인·set·`DB_VALUE` 컨테이너·객체/스키마 템플릿·객체 목록)는 cub_server 전체가 함께 쓴다. CS 클라이언트는 AREA를 키우지 못하면 `ws_abort_transaction`으로 트랜잭션을 abort하고, 서버는 콜백이 없었다(NULL). 폴드 서버는 콜백을 설치하되 `ws_abort_transaction`이 다음 셋을 모두 만족할 때만 abort한다: 스레드가 세션 브래킷을 쥐었고(`csc_bracket_is_active`), 그 세션에 등록된 클라이언트가 있고(`tm_Tran_index != NULL_TRAN_INDEX`), client 절반에서 실행 중이다(`db_on_server == 0`, method/SP dispatch 안 포함). 나머지(브래킷 없는 스레드, 서버 boot의 공유 컨텍스트·로그아웃 뒤 은퇴, 서버 절반)는 할당만 실패시킨다(NULL + `ER_OUT_OF_VIRTUAL_MEMORY`). 콜백은 `area_mutex`를 놓은 뒤 부르고, abort 안의 재실패는 두 번째 abort를 시작하지 않는다.

사용자 결정(2026-11-08, [A8 이식](https://github.com/xmilex-git/workspace/issues/629)): client 절반의 AREA 실패는 국면(컴파일·읽기·변이)과 무관하게 develop CAS처럼 트랜잭션을 abort한다. [#128](https://github.com/xmilex-git/workspace/issues/128) D8의 "컴파일/읽기 OOM은 문장 에러, 변이 중 OOM만 abort" 국면 분리는 F4("컴파일 경로에 abort 없음")에 기댔는데, F4는 AREA 콜백을 놓쳤다: develop CAS는 컴파일 중 AREA 실패에도 abort한다. 이 ADR이 D8의 국면 분리 문언을 대체한다(D8의 "세션 존속, 서버판 번역"은 그대로).

이유:

1. 서버 절반에서 abort하면 실행 중인 executor 아래에서 트랜잭션이 끝난다. TLA+(`docs/tla/CBRD-27430-A8`, mutant `old_a8`)와 계측 빌드의 fail-before(옛 A8 gate: `mspace_free`/`ws_decache` core)가 확인했다. CS 서버도 AREA 실패에 abort하지 않았다(wire 경계와 같은 일).
2. 국면 분리는 변이 지점마다 표지가 필요하고, 빠진 지점은 반쯤 바뀐 객체 메모리를 남긴다. 국면 무관 abort는 develop과 같고 코드가 늘지 않는다.

## Considered Options

- **client 절반만, 국면 무관 abort**: 채택.
- **브래킷이면 abort (옛 A8)**: 기각(이유 1).
- **D8 문언대로 국면 분리**: 기각(이유 2, 사용자).
- **콜백 없음 (SERVER_MODE NULL)**: 기각 — D8이 이미 기각(staged 변이를 문장 단위로 되돌릴 수 없음).

## Consequences

- develop과 같은 동작: client 절반의 AREA 실패는 `ER_LK_UNILATERALLY_ABORTED`, 서버 절반은 `ER_OUT_OF_VIRTUAL_MEMORY` 문장 에러.
- client 절반 디코더의 OOM 처리 결함(`tf_disk_to_class`가 할당 실패를 확인하지 않음, develop에도 있음)은 이 결정과 별개다.
