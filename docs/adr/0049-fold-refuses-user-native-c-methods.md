---
status: accepted
date: 2026-11-08
---

# 폴드 서버는 사용자 정의 native C METHOD를 dynamic link 전에 거절한다

CAS 폴드(CBRD-27430, PR 7837)에서 클래스의 사용자 정의 native C METHOD(`METHOD ... FUNCTION ... FILE '<.o/.so>'`)는 cub_server 안에서 실행되지 않는다. SERVER_MODE의 `sm_dynamic_link_class`가 METHOD 파일을 펼치거나 적재하기 전에 `ER_SM_DYNAMIC_LINK_PROBLEMS`(-237)로 실패하고, method scan은 그 오류 번호를 `ER_SP_EXECUTE_ERROR`로 감싸지 않고 클라이언트까지 보낸다. 내장(static) 메서드(`db_user`의 `add_user` 등)와 Java·PL/CSQL 루틴은 영향이 없다.

사용자 결정: [CAS 통합 제품화 준비 #259](https://github.com/xmilex-git/workspace/issues/259) 축 5 "native METHOD 미지원 확정"(2026-09-14), 옛 구현 `87ddc35f7`·`13f9270b5`. 이 ADR은 [A7 이식](https://github.com/xmilex-git/workspace/issues/628)에서 같은 결정을 새 브랜치 `cas-fold-v2`에 옮기며 기록한다.

이유:

1. CS에서 native METHOD는 CAS 프로세스 안에서 돌았다. 폴드에서는 적재한 라이브러리가 서버의 스레드·정적 상태·`exit`/`abort`·힙을 함께 쓰게 되고, 로더 mutex 하나로는 그 공유가 안전해지지 않는다.
2. 사용자 METHOD가 쓰는 오류 메시지 API(`db_make_method_error`)는 SERVER_MODE에서 메시지를 남기지 않는다(엔진에 다른 호출자 없음): 지원하려면 별도 설계가 필요하다.

## Considered Options

- **dynamic link 전 거절(-237)**: 채택.
- **서버 안에서 적재·실행**: 기각(이유 1).
- **별도 프로세스에서 실행**: 이번 범위 밖(설계 없음).

## Consequences

- 스펙 변화(폴드 한정): 사용자 native C METHOD 호출은 폴드 세션에서 -237로 실패한다. CS/SA 클라이언트는 그대로 dynamic link한다.
- 최종 게이트의 QA test.md와 매뉴얼에 적는다.
