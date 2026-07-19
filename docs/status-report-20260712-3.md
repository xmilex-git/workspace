# Bulk Index Build 보고 #3 — R3-04 심층 진행 (2026-07-12)

## 한 줄 요약
W1·W2 봉인 위에서 **R3-04(activation) 계약을 5회의 architect/critic 왕복으로 완결**(19바인딩 — 이 과정에서 실결함 4건·경계 누락 3건 적발)하고, 구현을 4단계로 분해해 **stage 1/2/3a/3b + 3c 일부까지 착지**(WIP 5커밋, unpushed). 적격 ALTER에서 **marker 실기록·서버 생존·비적격 legacy 무변** 스모크 PASS. 잔여 = recovery walker 본체 + 통합 검증(Stage 4) — 명확한 단일 이어가기 지점.

## R3-04 계약 완결 과정 (리뷰 레인이 잡아낸 것들)
| 회차 | 적발 | 해소 |
|---|---|---|
| arch 재심사 | marker helper latent HIGH(NULL addr → 활성화 즉시 crash) + 복구제약 3건 누락 + option (a) 미바인딩 | 17조건 계약 |
| critic addendum1 | 경계 11파일도 불충분(서버 handoff 부재) | 13파일+request-local API 설계 |
| arch handoff 설계 | **wire-format byte-incompatible**(R3-01 packer vs R3-02 validator — 활성화 시 100% fail-closed) | 조건 F |
| 조건 S fail-stop | stack 69.7KB 실측 불가 | heap 설계(S′) — critic이 OOM er_set 자동설정 오류까지 교정 |
| provenance fail-stop | marker ovfid/create_lsa 공급 경로 미규정 | 하이브리드(ovfid=root header 서버소스, create_lsa=build 캡처+wire+12B) 조건 G |
| pgbuf fail-stop | 조건 E의 SKIP core가 경계 밖 | +2(15파일)+H1/H2 |
- amendments 018-022 전부 봉인, receipt 7건 영속화($E/reviews/r3-04-*).

## R3-04 구현 진행 (bulkidx/noredo-parallel-r304-wip, unpushed)
| Stage | 커밋 | 내용 | 검증 |
|---|---|---|---|
| 1 배관 | 27c218903 (+219) | pgbuf policy wrapper(H1/H2), marker helper 부분수정, wire v1+create_lsa(72B ABI), heap 저장소(S′), LOADINDEX +12B | 빌드 2종 green, F roundtrip+malformed PASS, H1/H2 정적 |
| 2 provenance | 333e45f5a (+99) | create_lsa 캡처/carrier, ovfid root-header 조회, marker-last+ATTACH | 빌드 green, wire 재PASS |
| 3a deferral | 930917d6d (+349) | flush-deferral window+P1 stats gate+단일 FORCE+tail 전송 + **marker NULL-addr 최종수정** | **적격: marker 정확 1·서버 생존 / 비적격: tail 0 / 재시작 복구 PASS** |
| 3b direct write | af57fea5b (+46) | bulk no-redo SKIP/SKIP write+fsync, short sysops | 빌드 green (런타임 계약검증 Stage 4 이월) |
| 3c 일부 | 074806d16 (+29) | candidate 분류 강화(정상/media 구분) | 빌드 green — **walker 본체 미구현** |

주목: stage 3a 스모크가 architect의 latent HIGH 예언 지점(NULL addr crash)을 정확히 실증 → 즉시 수정 → 동일 스모크 PASS. 리뷰→FI→수정 루프가 세 번째로 적중.

## 남은 것 (이어가기 지점 — 단일)
1. **Stage 3c 완성**: log_recovery.c에 analysis 이벤트 수집 + post-undo selective 호출 + rows20-24 형상 walker(descending parent-exclusive·recovery-owned tdes·bounded CLR·allowlist fail-closed·catalog absence 후 ovfid→main destroy·재크래시 수렴) — R3-04 최고 난도 구간.
2. **Stage 4**: 통합 검증(RVBT_COPYPAGE=0·크래시 쌍·checkdb·재봉인 4종·OOM FI) → 5커밋 squash → 단일 unpushed candidate.
3. 이후 관문(계약 고정): 후보 SHA 3차 정적 재증명 → V1 full matrix 27/27(release)+FI 반복 → G(f) backup proof(R3-05 연계) → architect recovery review → critic V1 판정 → 그때만 push/SEAL.

## 사람 판단 필요
- 없음. 전 결정이 receipt로 봉인되어 다음 세션이 계약만 읽고 이어갈 수 있음. contract-map: $E/r3-04/contract-map.tsv.
