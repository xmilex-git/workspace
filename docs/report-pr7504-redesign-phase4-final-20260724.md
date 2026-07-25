# PR #7504 재설계 — Phase 4 완료·최종 보고 (2026-07-24)

## 최종 상태
- 브랜치 `pr-7504-redesign`, **최종 HEAD `68945f328`** (push 안 함). **논리 커밋 7개로 재구성**(백업 ref `backup/pr-7504-redesign-20260724` = 재구성 전 원 스택, 트리 동일 검증 diff 0):
  `040a12e04`(P1 barrier+protocol) → `7b957a542`(P2 6-op 경계계약) → `bebf00358`(P3 공용 packer/명시 shard state/2-core) → `6111c270b`(순수 술어) → `a30dbb88e`(clone-lifetime·수명감사 hardening — 함수 인덱스 UAR, OOM cleanup 가드, **STL bad_alloc 계약 갭을 C 슬라이스로 재설계**[try/catch 1차안은 AGENTS.md 예외 금지로 기각]) → `78fb12eec`(정책 리터럴 상수화 — 계획 §P3 명시 항목, 단독 drop 가능 배치) → `68945f328`(full-review hardening — vacuum 직접 append 복원, worker_get_fn 계약 완결, er_set/NULL check/문서화)
- **최종 provenance 13레인 PASS**: `~/dev/bkx-redesign/evidence/provenance-20260724-124847/manifest.txt` — release `2419-68945f3` + optdebug `2419-68945f3` 이중 fresh build(SHA-256 결속), 배터리 4종, compat 구→신, W0/W1/W2, restart-forward-commit, FI 2종, 2-core, 직렬 vacuum 오라클, optdebug 라이브 basic.
- **보완 레인 E1~E7 + 인덱스 매트릭스 17셀, 전부 exact-HEAD PASS**: release 원규모 E1~E7(함수 인덱스 병렬 E7 = UAR 회귀 TC, 수정 전 서버 크래시 채증) · 매트릭스 basic 11셀({normal,function,filter}×{parallel,serial} + online/overflow 비적용 실측 + **fk 3분할**: csql 비발화 / **loaddb 경유 발화(committed=1) + FK 동작** / 위반 실패+서버 생존+재시도) · FI 6셀({normal,function,filter}×{clone,prepare} 주입→깨끗한 실패→재시도 성공).
- **optdebug 레인 합성 판정**(원기록 보존, `final-chain-status.txt`): `EXT_OD_FULL=124`(E5 원규모 optdebug checkdb 1800s 초과 — CPU jiffies 진행 실측으로 행/정합성 실패 아님) + `EXT_OD_REDUCED=0`(20k/10k, E1~E7 전부 PASS) + `EXT_REL_FULL=0` → **COMPOSITE_VERDICT=0** (규모 커버리지는 release 원규모가, assert 커버리지는 optdebug 축소 레인이 담당 — 동일 코드 경로 발화 확인).

## 성능 게이트 — 재실행 중 (이력 포함)
1. 1차(블록 순서 측정): base 102.9s vs p3 115.6s **+12.3% "회귀" 오판정**.
2. 귀속 캠페인이 기각: Phase 1 바이너리(빌드 경로 무변경)조차 111.4s — 계열이 아니라 **공유 volume 상태 진화+세션 드리프트**.
3. **직전 확정(엄격 쌍별 교대, `d565aa530` 빌드, 8쌍)**: base 중앙값 109.3s vs head **101.5s = head -7.1%**(paired 평균/중앙값 약 -3.7%/-4.0%, 8쌍 중 head **5승 3패**). **회귀 없음, 개선 경향.**
4. **최종 HEAD `68945f328` 재측정 진행 중**: `get_next_vpid` 섹터-슬라이스 전환·vacuum 하이브리드가 스캔 경로를 건드렸으므로 "hot loop 밖" 주장 폐기, **A/B·B/A 순서 균형**(홀수쌍 AB/짝수쌍 BA) 8쌍으로 재실행 — 결과·승패·paired 통계는 `evidence/perf-20g-balanced/measurements.tsv`에 기록 예정. 완료 전 성능 게이트 판정 보류.
5. dev(2320) 대비: 401.4s → ~101.5s ≈ **4.0x** (재구성 픽스처 기준 참고치; 원 공표 3.41x와 같은 자릿수).
- 방법론 교훈(하네스에 명문화): 블록 순서 측정은 드리프트에 취약 → **쌍별 교대(`measure-pairs.sh`)**가 판정 표준. dev 절대치는 픽스처 재구성이라 참고용.

## 리뷰 대응 최종 라운드 (전부 해소)
| 지적 | 대응 |
|---|---|
| shard init의 미초기화 template typed-read UB | 빌드 커서 상태 12필드를 defined 초기값으로 분리(`d565aa530`), 잔여 `max_key_size`까지(`ce73548e4`) |
| clone_scan_args 부분 실패 누수 | transactional 계약 + 3개 실패 출구 전량 회수(`db5eb5922`), FI로 실증 |
| NOT_APPLICABLE 소유권 문구 불일치 | external_sort.h 규칙 6개로 정정, plan/보고서 동기화 |
| **optdebug 크래시(신규 발견)** | `log_check_system_op_is_started`는 음의 경우 내부 assert하는 단언 헬퍼 — 술어로 오용된 6곳(멱등 abort_px 분기 포함)을 신규 순수 술어 `log_is_system_op_started`로 교체(`685c22beb`). **optdebug 배터리가 잡아낸 실결함** — release에선 assert_release가 비치명이라 잠복했음 |
| 2-core SHA 결속 없음 | provenance 런에 2core 레인 편입(manifest 결속) |

## 산출물
- JIRA 첨부 후보: `~/dev/bkx-redesign/CBRD-27071-tc-bundle-v4.tar.gz` (sha256 91ae1237…) — committed-barrier 오라클, R4 레인, kill-sweep C1, kill 스코프 수정, v4 README. verification.md v2 반영 사항은 Phase 2~4 보고서 3부가 원자료(업로드는 수동 액션).
- 하네스(재사용 가능): `~/dev/bkx-redesign/harness/` — provenance-run(이중 빌드+manifest+13레인), measure-pairs(쌍별 교대), mkfixture-20g, w/fi/r4/2core/serial-vacuum 프로브, test-hooks-v2.patch(훅, 커밋 불포함).
- 픽스처: t20g 341M×2레인(runtime-dev/runtime-tip, ~41GB) — 후속 캠페인 재사용 가능.

## 구조 게이트 최종
- `external_sort.c`: `SORT_ARGS|btree_load|bt_load_|LOAD_ARGS|BT_LOAD|log_sysop_` **grep 0건**, btree_load.h include 삭제.
- `btree_load.h` 공개 표면: extern 14개→0, 타입 노출 0. `log_manager.h`: `log_get_system_op_level` 제거는 유지하되, 음의 검사용 **순수 술어 1개**(`log_is_system_op_started`)는 실결함 해소를 위해 필요함이 실증되어 추가(단언 헬퍼와 역할 분리 문서화).
- 직렬 커널: 변경이 어댑터 접합부로 한정. 레코드 직렬화 리터럴(0x8000/0x4000) 0건.

## 남은 수동/후속 항목
1. JIRA 첨부 업로드(tc-bundle v4, verification v2) — 저장소·draft PR 불가침 원칙 유지.
2. push 금지 유지 중 — 리뷰 완료 후 지시에 따라 push/squash 여부 결정.
3. splitter-balance(debug 계측 레인)는 optdebug+LANE 지정 수동 실행용으로 하네스에 존재 — 회귀 판정은 skew가 담당(전 라운드 PASS).
