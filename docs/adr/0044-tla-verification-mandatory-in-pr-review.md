---
status: accepted
date: 2026-11-05
---

# PR 리뷰에서 TLA+ 검증은 모든 엔진 PR의 필수 관문이다

`cubrid-pr-review`는 실행 문장을 바꾸는 모든 엔진 PR을 `cubrid-tla`로 검증하고(Step 3d), 검증이 실패하거나 끝나지 않으면 Approve하지 않는다(사용자 결정 2026-11-05). 면제는 실행 문장이 바뀌지 않는 diff(주석, 문서, TC, CI·빌드 스크립트, 메시지 문구)뿐이다.

이유:

1. **런타임 증거는 실행된 interleaving만 본다.** CTP와 smoke는 스케줄러가 우연히 고른 순서를 지나가고, 동시성·crash·vacuum 창은 대개 지나가지 않는다. 모델은 경계 안의 모든 순서를 본다.
2. **"작거나 뻔한 PR"이라는 판단이 구멍이다.** 면제 기준을 크기나 확신이 아닌 diff 사실로 두어야 리뷰어 판단에 따라 관문이 사라지지 않는다.
3. **모델이 코드와 떨어지지 않게 묶는다.** 대응표, 수정 전 동작 mutant, 프로토콜 변경의 trace validation이 모델을 PR head 코드에 묶는다.

## Considered Options

- **동시성 PR에만 적용**: 기각. 어떤 PR이 동시성에 닿는지가 곧 리뷰어 판단이고, 결정 표(입력 클래스)·에러 경로·상태 기계 변경도 모델로 구멍이 드러난다.
- **TLC만, TLAPS 없이**: 기각. TLC는 상수 경계 안의 사실이고, 안전성 불변식은 상수와 무관하게 증명해야 "워커 N개"류 주장을 받칠 수 있다.

## Consequences

- TLAPS는 이 호스트의 tlapm 1.4.5(nixpkgs; LS4·Isabelle 없음)로 안전성만 증명한다. liveness는 TLC 경계 안의 결과로만 보고한다.
- 리뷰 비용이 늘어난다. 모델은 `.claude/review/PR-<N>/tla/`에 남아 같은 모듈의 다음 PR이 재사용한다.
