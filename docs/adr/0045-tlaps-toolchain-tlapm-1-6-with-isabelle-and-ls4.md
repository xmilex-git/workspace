---
status: accepted
date: 2026-11-05
supersedes: 0044 (Consequences, the tlapm 1.4.5 line)
---

# TLAPS는 tlapm 1.6.0-pre(Isabelle2025, LS4)를 nix로 재링크해 쓴다

`tools/tla/tools.nix`는 tlaps 1.4.5(nixpkgs) 대신 tlapm 1.6.0-pre 릴리스 빌드(`tools/tla/tlapm-next.nix`)를 고정한다(사용자 결정 2026-11-05). 릴리스 바이너리는 glibc 2.38을 요구하고 이 호스트(Rocky 8)는 2.28이라, 고정된 nixpkgs의 glibc로 autoPatchelf해 쓴다.

이유:

1. **시간적 결론을 증명한다.** LS4가 있어 INV1 전제에서 `Spec => []IndInv`를 `PTL`로 맺는다(cubrid-tla P2). 1.4.5에서는 전제만 증명하고 결론은 규칙에 맡겼다.
2. **고차 보조정리를 쓴다.** Isabelle 백엔드로 `NatInduction`·`SmallestNatural` 같은 연산자 매개변수 정리를 인스턴스화한다(P21). 1.4.5에서는 스펙을 `\E x : Least(x, S)`로 바꿔 우회했다.
3. **nix 안에서 끝난다.** 소스 빌드나 수동 다운로드 없이, 해시 고정 `fetchurl`과 GC root로 재현된다.

## Considered Options

- **tlaps 1.4.5 유지**: 기각. LS4·Isabelle/TLA+ heap이 없고, nixpkgs의 Isabelle은 1.4.5의 Isabelle/TLA+ 이론과 맞지 않는다.
- **tlapm 소스 빌드(dune, Isabelle heap 빌드)**: 보류. 같은 결과를 더 큰 빌드로 얻는다.

## Consequences

- 1.6.0-pre는 롤링 pre-release다. 해시는 2026-11-05 자산을 고정하고, 상류가 자산을 바꾸면 GC root가 받아 둔 사본으로 계속 쓴다. 갱신은 `tlapm-next.nix`의 해시와 버전을 바꾸고 `just tla-selftest`와 `docs/tla` 전체를 다시 증명한 뒤에 한다.
- liveness는 공정성(`WF`/`SF`) 증명을 쓴 claim만 TLAPS로 보고하고, 나머지는 TLC 경계 안의 결과로 보고한다.
- `tla-check`는 tlapm을 실행 디렉터리의 HOME·TMPDIR로 돌린다(Isabelle이 `/tmp`와 `~/.isabelle`에 쓰지 않게).
- 1.6의 SMT 번역은 1.4.5와 다르다. 2026-11-06 회귀 비교(부하가 없는 64 CPU, 번들 Z3 4.8.9와 nixpkgs Z3 4.16 둘 다, `--stretch 6`)에서 1.4.5가 증명한 obligation 일부가 1.6에서 timeout으로 남았다: `ExprProgExec_proofs` 23:87, `PxHeapSnapshot_proofs` 118:5와 196:3. `PxHashJoin_proofs`(39개)와 `PxSortMergeQueue_proofs`는 부하가 있을 때 측정해 확정되지 않았다. 이 모듈들의 `## Result`는 1.4.5 기록으로 남고, 모듈을 다시 손대는 작업이 실패 단계를 쪼개(cubrid-tla P24) 1.6에서 다시 증명한다. 새 증명은 1.6으로 쓴다(사용자 결정 2026-11-06).
