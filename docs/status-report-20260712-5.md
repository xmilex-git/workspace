# Bulk Index Build 보고 #5 — 세션 마감 스냅샷 (2026-07-12)

## 한 줄 요약
R3-04 candidate `336d1d6a4`(unpushed)의 **의무 3(적격 no-redo 계약) 동적 검증 완결** — marker body 정확 1, RVBT_COPYPAGE=0, 골든 집계, `Index scan(pk_eligible)` plan, checkdb 0. 잔여는 순수 실행 작업 4항목(4/7/8/9) — 계약·판단 이슈 0, 전부 명시 FAIL(HARNESS_INCOMPLETE)로 기록됨.

## 검증 현황 (candidate 336d1d6a4)
| 의무 | 상태 |
|---|---|
| 1 wire/static (+4B exact, fail-closed) | PASS (정적) |
| 2 callsite 전수 (rebuild=false 포함) | PASS |
| 3 적격 회귀 (marker 1·COPYPAGE=0·골든·plan·checkdb) | **PASS (동적 완결)** |
| 4 비적격 복원 (populated CREATE INDEX COPYPAGE>0) | 미실행 — harness |
| 5 다른 분기 no-redo 오승인 0 | PASS (정적) |
| 6 debug+release clean rebuild (-Werror) | PASS |
| 7 F 재봉인 (tail matrix PASS / LOADINDEX malformed matrix 잔여) | 부분 |
| 8 X1 zero-tail 동적 (stage3a에서 1회 실측 있음 / 최종 candidate 재캡처 잔여) | 부분 |
| 9 크래시 매트릭스 A1-A4·C1·L1 (stage3c1에서 2종 유사 실측 / 최종 candidate 통제 실행 잔여) | 미실행 — harness |
| 10 wire 3건 외 변화 0 | PASS |

## 잔여 실행의 알려진 함정 (다음 세션용)
- gdb를 `timeout N gdb`로 감싸면 attach된 cub_server까지 SIGKILL(stage9 실패 사인) — **stage6 방식**(gdb 스크립트 내 bp+commands+detach+quit, driver는 백그라운드+폴링, $E/r3-04/stage6-*-gdb-driver.log가 성공 기록) 필수.
- 비적격 COPYPAGE 대조군은 populated ordinary CREATE INDEX(stage6-alter2.sql) — 빈 테이블 금지.
- executor가 gdb/크래시 매트릭스 실행을 회피하는 편차 반복 — 다음 세션은 harness 셸 스크립트를 먼저 파일로 완성해 두고 "실행만" 시키는 형태가 확실.

## 이어가기 (순서)
1. 의무 4/7/8/9 실행 (위 함정 참조, 스크립트 선례: stage6-*, stage3a-*, stage3c1-*) → contract-map 동적 완결.
2. 후보 SHA 3차 정적 재증명(closure/allowlist/2PC) → V1 full matrix 27/27(release)+FI 반복 → G(f) backup proof → architect recovery review → critic V1 → push/SEAL → R3-05 bind → W4(R4).

## 거버넌스
- candidate `336d1d6a4` (f8040a685 위 단일 커밋, unpushed), 백업: bulkidx/noredo-parallel-r304-stages, backup/r304-before-wire3.
- amendments 016-023·receipt 11건·contract-map·stage10-verdict 전부 봉인. 사람 판단 필요 항목 0.
