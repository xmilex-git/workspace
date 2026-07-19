# Bulk Index Build 중간보고 (2026-07-12 새벽, .34 이관 후)

## 한 줄 요약
캠페인을 .30→.34로 완전 이관했고, R2-02 마지막 게이트에서 **진짜 결함을 잡아 수정**했다. gate (d)·(b) PASS, gate (c)는 공정 측정 확보 후 편차 귀속 실험(R2-01-only 대조)이 지금 돌고 있다 — 이것만 결론나면 커밋 #2 봉인.

## 이관 (완료)
- .30의 uncommitted R2-02 → WIP 브랜치 `bulkidx/noredo-parallel-r202-wip` commit+push → .34 pull. 봉인 브랜치는 da822ce38 그대로.
- evidence 737파일 rsync(바이트 대조), harness 동기화, .30 stale DB/tmp/고아 프로세스 정리. 이후 전 작업 .34 로컬.

## R2-02 게이트 진행
- **gate (d) 대반전**: 기존 FAIL_STOP은 주입 아티팩트(함수 진입점 강제 return → 본체 스킵)로 판명. 주입을 재설계(본체 완료·unfix 후, ER_IO_WRITE)했더니 **여전히 서버 사망** → core 분석 → **R2-02 오류 전파 경로의 실제 결함 발견**: 9/9 콜사이트 전부 consumed 포인터 이중 unfix, 2곳은 fix 누수까지. 최소 수정 커밋 `a9af932` → gate (d) 재실행 **전항 PASS** (문장 실패·서버 생존·롤백·재시도·인덱스 공표+plan 증거·assert 0) + 정적 9/0.
- **gate (b) PASS**: release 빌드, 50M행 골든 전항 일치 + BTID 인덱스 플랜 증거.
- **gate (c) 4차까지의 여정** (전부 절차 결함 교정, 기준 완화 없음):
  1. raw `cubrid server stop` 300s hang → 실측(write_bytes/checkpoint 로그)으로 정상 flush 판명, bound 1200s+wrapper 교체
  2. 고아 master 통제면 붕괴 → teardown 순서 교정
  3. **conf 불일치 발견**: candidate만 캠페인 conf(DWB=0!, parallelism=24) → 3차까지의 비교는 무효
  4. conf 정규화+paramdump 공정성 게이트 내장 → 완주: notify **100만=100만 정확 동수**, develop 자기노이즈 **0**(두 leg 완전 동일), candidate만 RVBT +333(전량 배경 타입 MODIFY_NO_UNDO)+DWB 해시 상이.

## 지금 도는 것
- **귀속 실험**: 편차가 이미 봉인된 R2-01(vacuum append main-이관 — 행동 변화가 설계상 존재)의 것인지 R2-02 마진인지. R2-01-only(da822ce38) release를 빌드해 동일 방법론 3-leg 측정 중. **candidate−r201 마진 델타가 0이면 R2-02 inert 입증 → gate (c) PASS(baseline 교정 supersede 기록) → 커밋 #2 봉인 → W2 진입.** 0이 아니면 fail-stop 후 수치 보고.

## 판단 필요 (변동 시에만 회신)
- 없음. gate (d) 처리 기준(root-cause 조건부)·release 검증 기준(1000행+/10회+)은 지시 반영 완료(SSOT 명문화). W2 closure 옵션 (a) 기본 진행 유지.
