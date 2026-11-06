---
status: accepted
date: 2026-11-06
supersedes: 0044 (trace validation이 lock·latch·PX 변경에만 붙던 조건)
---

# Trace validation은 코드가 있는 모든 TLA+ 모델의 필수 관문이다

`cubrid-tla`의 모델이 이미 있는 코드(PR head, 브랜치, develop)를 다루면, 그 sha의 계측 빌드로 기록한 실행을 trace spec이 받아들이고(`*.witness-trace-*`) 손상시킨 실행은 거부해야(`*.reject-*`) 결과가 된다. `tools/tla/tla-check`는 두 cfg가 없는 디렉터리를 실패시킨다. 예외는 구현이 아직 없는 설계 spec과 패턴 예제뿐이며, MAP.md에 `trace-exempt: <이유>` 줄로 남긴다. `cubrid-pr-review` Step 3d는 모든 엔진 PR에 trace를 요구한다(사용자 결정 2026-11-06, cubrid-tla P50, cubrid-pr-review P28).

이유:

1. **TLC와 증명은 모델만 본다.** 모델이 코드와 다르면 TLC 통과도, IndInv 귀납성도, TLAPS 증명도 틀린 모델에 대한 보장이다. 둘을 잇는 것은 refinement map과 trace뿐이다.
2. **잠금을 건드리지 않는 변경에서도 trace가 차이를 찾았다.** PR #8356(CBRD-27866, 행 단위 파티션 순회)의 IS_LOCK은 이미 잡힌 잠금의 재요청이었다. 그런데도 계측 빌드 실행 4건에서 모델 오류 3건(서브쿼리 재실행마다 새 memo, ANTI 통과 뒤 재진입, 첫 행의 이중 rewind)과 PR 설명에 없던 동작 1건(범위 밖 range 키가 모든 파티션을 엶)이 나왔고, 마지막 것은 리뷰 질문으로 게시됐다.

## Considered Options

- **lock·latch·WAL·vacuum·PX 변경에만 요구(종전)**: 기각. 어느 변경이 해당되는지가 읽는 사람의 판단에 맡겨지고, 상태기계 변경에서 나온 차이를 놓친다.
- **예외 없이 모든 디렉터리에 요구**: 기각. 구현 전 설계와 패턴 예제에는 기록할 빌드가 없다.

## Consequences

- 계측 빌드 한 번(optdebug)과 시나리오 실행이 리뷰마다 더해진다. 계측은 scratch worktree에서만 하고 커밋하지 않는다.
- trace가 없는 기존 `docs/tla` 디렉터리(CBRD-26425-atomic-latch, CBRD-27215-expr-prog-exec, CBRD-27361-page-batch-walk, CBRD-27361-runtime-filter, CBRD-27819, parallel-hash-join, parallel-scan)는 다시 돌리면 실패한다. 그 디렉터리를 다시 손대는 작업이 trace를 붙이거나, 코드가 없는 설계면 `trace-exempt`를 단다. 기록된 결과는 바꾸지 않는다.
- `examples/condvar-handoff`는 `trace-exempt: pattern example with no CUBRID code under it`을 단다.
