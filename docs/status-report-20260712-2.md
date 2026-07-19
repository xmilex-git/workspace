# Bulk Index Build 보고 #2 — W2 완료, W3(R3-04) 착수 (2026-07-12 아침)

## 한 줄 요약
**W2 봉인 3/3 완료** (R3-03·R3-01·R3-02, 전부 게이트 PASS·push·manifest SEALED). W3 진입 게이트 통과(정적 증명 3종 + architect WATCH + critic **R304_APPROVE_ENTRY**) 후 **R3-04 activation 구현이 지금 돌고 있다** (unpushed candidate까지가 승인 경계).

## 봉인 체인 (xmilex/bulkidx/noredo-parallel)
da822ce38(R2-01) → ff95820a7(R2-02) → 9c013ef09(R3-03) → 4009b023f(R3-01) → f8040a685(R3-02) — ledger·manifest·원격 ref 전부 정합.

## W2 내역
- **R3-03**: 비활성 marker v1 codec(RVBT_BULK_BUILD_DURABLE=130) + recovery scaffolding. rv 정합·round-trip 경계·restoredb 동치 PASS. walker/recovery-tdes wrapper는 R0 rows 20-24 미증명으로 R3-04 제약으로 명시 이관(deferral-note 봉인).
- **R3-01**: bulk provenance 술어 + exact-set descriptor + versioned FORCE tail packer (+252줄, 전부 비활성, round-trip/진리표/호출자0 검증).
- **R3-02**: 서버측 v1 tail strict parser + parent-LSA/2PC helper + marker append helper (+104줄, negative rows 표, absent-tail 스모크).
- 병렬 구현(전용 worktree) → conflict-free cherry-pick 순차 merge → 커밋별 게이트(빌드/스모크/CCI_XA) → 봉인.

## W3 진입 심사
- **정적 재증명 3종 PASS** (새 SHA, R0 방법론 무약화): closure / recovery allowlist(신규 marker 포함 55행) / 2PC freeze.
- **Architect 재심사 WATCH**: 봉인 4커밋 계약 준수 확인. 단 ①R3-02 marker helper에 **latent HIGH 결함**(NULL addr → 활성화 첫 호출 시 crash — 비활성이라 현재 무해) 적발, ②복구-안전 제약 3건(cleanup 재크래시 수렴/stop-at 소싱/media_recovery 파생) 추가, ③option (a) 심볼 확장 바인딩 요구. 전부 R3-04 계약 제약으로 전환.
- **Critic R304_APPROVE_ENTRY**: 조건 12개(A-E, 1-7) + 기계 판정 술어(RVBT_COPYPAGE=0, marker cardinality, 27/27 runtime contract 등) + 금지 목록으로 착수 승인. option (a) 최종 바인딩(보스 무이의 2회 + "너 추천대로" 지시 근거). 승인 경계: **unpushed candidate까지** — push/SEAL은 candidate SHA 3차 증명 + architect recovery review + critic V1 판정 후.
- amendment 018(승인 바인딩) 봉인 진행 중, R3-05 문서 draft 완비.

## 운영 사고 1건 (복구 완료 + 규칙화)
R3-03 빌드가 `just build` 버전 인자 누락으로 공용 `CUBRID-11.5.develop` 설치본(debug/release)을 덮어씀 → 즉시 적발(봉인 게이트의 stale-바이너리 검사가 잡음), develop HEAD로 재빌드 복원, SSOT 3.2에 함정 명문화.

## 지금 돌고 있는 것
- **R3-04 activation 구현** (단일 executor, 전용 worktree, 승인 9파일 경계): 긴 sysop 제거 + no-WAL/no-DWB direct write(TDE-보존 core 경유) + flush-deferral(P1 stats 게이트 포함) + marker-last/ATTACH + selective recovery 활성화 + HIGH 결함 수정. 산출은 unpushed candidate SHA + 스모크 게이트까지.
- 완료 후 남은 관문(자동 진행): candidate SHA에서 closure/allowlist/2PC 3차 재증명 → V1 full matrix(27/27, release) + FI 반복 → architect recovery review + critic V1 판정 → 그때만 push/SEAL → R3-05 bind → W4(R4 병렬화).

## 사람 판단 필요
- 없음. (R3-04가 BLOCK으로 전환되면 즉시 보고.)
