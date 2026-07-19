# Bulk Index Build 보고 #4 — R3-04 candidate 완성 직전 (2026-07-12)

## 한 줄 요약
R3-04 **구현 완료 + candidate `336d1d6a4`**(f8040a685 위 단일 커밋, 15파일 +1350/−88, unpushed). 진행 중 리뷰·검증 레인이 **추가 실결함 2건**(비적격 빌드 무보호 no-redo, marker helper 미완수정)을 더 잡아 수정했다. 잔여는 최종 동적 검증 배터리 재실행 1건 — 선례 스크립트가 evidence에 있어 기계적으로 이어갈 수 있는 상태.

## 이번 구간에서 잡은 실결함 (누적 6건째)
1. **stage3a 스모크가 architect 예언 적중**: marker helper NULL addr crash(예언된 latent HIGH) — Stage 1이 3요소 중 addr 전달을 빠뜨림 → 직접 한 줄 수정 → 동일 스모크 PASS(marker 1·서버 생존).
2. **stage6 대조군이 무보호 no-redo 적발**: populated 비적격 CREATE INDEX도 SERVER_MODE 무조건 no_redo — redo도 marker cleanup도 없는 크래시 무보호(legacy 무회귀 위반). critic 승인(R304_WIRE3_APPROVE)으로 LOADINDEX request +4B(적격 플래그, 3번째이자 마지막 wire 변경) 게이트 구현 → release -Werror가 잡은 미초기화까지 수정.
   - 참고: stage5의 "marker 2건" 경보는 PLT+본체 이중 breakpoint 계측 오류로 판명(실제 정확 1) — 오진 정정 기록.

## R3-04 구현 완성 내역 (WIP 9커밋 → 단일 candidate)
- Stage 1 배관(pgbuf policy wrapper H1/H2·wire v1+create_lsa 72B·heap S′·LOADINDEX +12B) → 2 provenance(캡처/carrier/ovfid/marker-last) → 3a deferral+tail 전송(스모크 PASS) → 3b direct write+short sysops → 3c-1 recovery 이벤트 수집+post-undo 진입(크래시 스모크 2종 PASS) → 3c-2 bounded walker(allowlist fail-closed·recovery-owned tdes·atomic cleanup) → Stage 4 squash+재봉인 4종 → wire3 수정 amend.
- 검증 완료: 빌드 2종 clean green(-Werror), F roundtrip+malformed, H1/H2·ABI 72B·S′ 산식 재봉인, 적격 marker 1·RVBT_COPYPAGE=0·골든·plan·checkdb(stage6), 크래시 스모크 2종(stage3c-1), wire 3건 외 변화 0.
- 백업: stage 이력 bulkidx/noredo-parallel-r304-stages, wire3 전 상태 backup/r304-before-wire3.

## 남은 관문 (순서 고정, 계약 봉인됨)
1. **동적 배터리 재실행**: addendum6 의무 3/4/7/8/9 — 적격/비적격 대조(release), F/X1 matrix, 크래시 매트릭스 A1-A4+OOM FI(debug). stage6의 성공 스크립트($E/r3-04/stage6-*)가 그대로 재사용 가능. (직전 executor 1회는 빌드만 하고 미실행 — 재dispatch 필요, 접근법 문제 아님.)
2. 후보 SHA 3차 정적 재증명(closure/allowlist/2PC) → V1 full matrix 27/27(release)+FI 반복 → G(f) backup proof(R3-05 연계) → architect recovery review → critic V1 판정 → **그때만 push/SEAL**.

## 거버넌스 상태
- amendments 018-023 봉인(옵션 (a)·경계 15파일·S′·G·wire3), receipt 10건($E/reviews/r3-04-*), contract-map 최신, ledger 정합.
- 봉인 체인: R2-01→R2-02→R3-03→R3-01→R3-02 (원격 f8040a685) — candidate는 그 위 단일 커밋으로 대기.

## 사람 판단 필요
- 없음. 다음 세션은 contract-map + stage8-final-verdict + stage6 스크립트만 읽고 1번부터 이어가면 된다.
