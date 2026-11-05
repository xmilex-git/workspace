---
status: accepted
date: 2026-11-05
issue: CBRD-27430 항목 "약한 클래스 락 fastpath"의 develop 단독 이식 (PoC workspace#246)
---

# 클래스 락 fastpath는 게이트 없이 항상 켜진다 — "새 엔진 경로는 default OFF" 규칙의 예외

저장소 규칙("A new engine path is env-gated default OFF unless a ticket records a feature-specific exception")의 예외를 이 ADR 이 기록한다. 약한 클래스 락의 fastpath(PoC `poc/u1-class-lock-fastpath` `b086f17ae`의 develop 이식)는 env 변수·시스템 파라미터 스위치 없이 항상 동작한다(사용자 결정 2026-11-05).

이유:

1. **락 관리자는 켜도 맞고 꺼도 맞아야 하는 경로다.** 스위치가 있으면 fastpath ON/OFF 두 락 관리자가 공존하고, 강한 락 이전·non2pl·2PC 재획득 같은 정확성 항목을 두 조합에서 모두 증명해야 한다.
2. **기본 OFF면 검증이 새 경로를 지나지 않는다.** CTP sql/medium/shell 은 기본 설정으로 돌기 때문에 꺼 둔 fastpath 는 게이트에서 한 번도 실행되지 않는다.
3. **되돌리기 수단은 PR 이다.** 사양이 바뀌는 것이 아니라 같은 락 의미론의 다른 구현이므로 단계적 도입이 줄 것이 없다.

## Considered Options

- **env 게이트 default OFF**(저장소 기본): 기각. 위 1·2.
- **hidden 시스템 파라미터**: 기각. 위 1 — 두 구현이 남는다.

## Consequences

- 정확성 증명(PoC 결과 문서 §5의 10항목)과 CTP 는 항상 fastpath 가 켜진 빌드 하나로 한다.
