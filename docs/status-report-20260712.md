# Bulk Index Build 보고 — W1 봉인 완료 (2026-07-12 새벽)

## 한 줄 요약
**커밋 #2 (R2-02) 봉인·push 완료** — 그 과정에서 진짜 결함 2건(오류경로 이중 unfix, 무단 동기 flush)을 잡아 고쳤고, 기존 .30 게이트 PASS 1건이 공허 통과였음을 오진 정정으로 기록했다. W2(R3-03) 착수됨.

## 봉인 내역
- **커밋 #2 `ff95820a7`** "[bulkidx] R2-02: thread WAL/DWB flush policy" — xmilex/bulkidx/noredo-parallel push, tree 동일성 검증 완료.
- ledger: `r2-02 debug+release 1 PASS ff95820a7` + `r2-02-manifest SEALED e77b5fd9…` + amendment 016(호스트 이관+오진정정, 0444).
- 전체 이력은 WIP 브랜치(bulkidx/noredo-parallel-r202-wip: 792d7f5→a9af932→a8660e0)에 감사용 보존.

## 잡은 결함 2건 (둘 다 실코드 결함, FI/포렌식이 각각 적중)
1. **오류경로 이중 unfix** (a9af932): btree_log_page consume 계약 위반 — 9/9 콜사이트 전부, 2곳은 fix 누수 동반. 유효한 FI(post-unfix, ER_IO_WRITE)가 서버를 죽여 발견 → core 스택으로 확정 → 수정 → 동일 FI로 a~f 전항 PASS.
2. **무단 동기 flush** (a8660e0): R2-02 원 구현이 stock의 `set_dirty(FREE)`를 `flush_with_wal()` 동기 호출로 바꿔 inert 계약 위반. **DWB 포렌식**(develop/r201은 빈 슬롯 64개 byte-identical, candidate만 btree 페이지 64개 잔류)으로 적발 → 제거 → DWB 해시가 develop과 동일해짐(cand 2회 재현).

## 오진 정정 (supersede, amendment 016)
- .30의 R2-02 gate (c-ii) "DWB SHA 동일 PASS"는 양 leg 모두 campaign conf(double_write_buffer_size=0)였을 개연성 — 공허 통과. .34 공정 측정(conf 정규화+paramdump 공정성 게이트)이 대체.
- (c-i) 노이즈 밴드: develop 자기노이즈 0은 운좋은 표본, 동일 계기 실측 노이즈는 456 (r201 2-leg). Δ+333은 전량 배경 타입(MODIFY_NO_UNDO) 이내.

## 최종 게이트 (a8660e0, 전부 PASS)
| 게이트 | 결과 |
|---|---|
| (b) v0 골든 (release) | 50M행 전항 일치 + BTID plan 증거 |
| (c-i) WAL parity | notify 1,000,000 정확 동수, RVBT Δ333 ≤ 456 배경 타입 한정 |
| (c-ii) DWB | SHA-256 develop과 동일 (빈 슬롯 상태, 2회 재현) |
| (d) 정적/동적 | 9/9 콜사이트 검사 0누락 / FI a~f (문장실패·생존·롤백·재시도·공표+plan·assert 0) |
| (e)+CCI_XA | debug/release green, dblink_2pc_daemon 0 |

## 인프라 (전부 .34 로컬 전환 완료)
- .30→.34 이관: 소스(WIP 브랜치), evidence 737파일, harness. .30 stale 정리(고아 master 포함). 절차 결함 교정: raw stop→SERVER_CTL 래퍼, stop bound 1200s(정상 checkpoint 실측), teardown 순서(master→DBROOT).
- SSOT 갱신: 정량 release 기준(1,000행+/10회+ 재실행, 성능은 release 전용) 명문화.

## 지금 진행 중 (병렬)
1. **R3-03** (W2 첫 슬라이스): 비활성 marker v1 codec + recovery scaffolding — re-ground→구현→빌드+rv정합+round-trip+restoredb 동치 검증 중.
2. 하네스 영구 패치: v0 골든에 인덱스-경로(sargable+plan) 검증 상시 내장 + amendment 017.

## 사람 판단 필요
- 없음. W2 closure 옵션 (a) 기본 진행 그대로 (이의 시 회신).
