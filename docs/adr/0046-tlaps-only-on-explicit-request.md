---
status: accepted
date: 2026-11-06
supersedes: 0044 (Considered Options, "TLC만, TLAPS 없이"의 기각)
---

# TLAPS 증명은 사용자가 명시적으로 요청할 때만 한다

`cubrid-tla`, `grill-with-tla`, `cubrid-pr-review`의 TLA+ 관문은 TLC(main, scale, mutant, witness)와 IndInv 귀납성 검사(Apalache, TLC)로 닫는다. TLAPS 증명은 사용자가 자기 메시지로 증명을 요청할 때("TLAPS", "증명해줘", "명확히 검증해줘")만 쓰고, 그때 `tools/tla/tla-check --prove`로 돌린다(사용자 결정 2026-11-06, cubrid-tla P48). 일반적인 "TLA+로 검증", 스킬·티켓·리뷰 단계의 지시는 요청이 아니다.

이유:

1. **비용이 결과에 비해 크다.** tla-check 실행 124건에서 tlapm은 26 214 s, TLC cfg 전부는 22 866 s를 썼다. parallel-hash-join 하나는 증명 모듈 7개에 11 371 s가 걸렸고, 스킬 규칙 47개 중 19개가 증명을 통과시키기 위한 것이었다.
2. **결함은 TLC가 찾았다.** PITFALLS에 기록된 코드 결함(parallel scan H1/H2, CBRD-27739 원인 A, hole E, CBRD-24094 H2)은 모두 TLC 반례나 deadlock에서 나왔다. TLAPS가 한 일은 IndInv 보강이었고, 그것은 귀납성 cfg가 먼저 찾는다(P6, P42).
3. **Apalache가 상수 문제의 대부분을 덮는다.** `--cinit`으로 정수 상수를 열어 두면 IndInv 귀납성을 정수 상수 전 범위에서 수 초에 확인한다. 남는 차이는 역할 집합 크기(워커 수)를 고정한다는 것뿐이다.

## Considered Options

- **TLAPS를 모든 모델의 필수 관문으로 유지(ADR 0044)**: 기각. 위의 비용과 결과.
- **TLAPS 폐지**: 기각. "워커 몇 개든"이 핵심인 설계는 요청 시 증명할 수 있어야 한다.

## Consequences

- `tla-check`는 기본으로 증명 모듈을 건너뛰고(`skip: TLAPS` 줄), 증명 모듈을 요구하지 않는다. `--prove`일 때만 증명하고 증명 모듈을 요구한다. `just tla-selftest`는 툴체인 검사이므로 `--prove`로 돈다.
- 보고서의 TLAPS 칸은 요청이 없으면 `요청 없음`이고, safety는 "TLC 경계 안 + Apalache 귀납성(역할 집합 크기 고정)"으로 말한다.
- 증명이 빠지면 TLC 귀납성 cfg는 증명을 받치지 않는다. IndInv 귀납성은 Apalache cfg로 확인하고, TLC 귀납성 cfg(실측 최대 1 319 s)는 Apalache가 IndInv의 타입을 다루지 못할 때만 쓴다(cubrid-tla P42, P45).
- 기존 `docs/tla` 디렉터리의 증명 모듈은 그대로 두고, `--prove`로 다시 돌릴 수 있다.
