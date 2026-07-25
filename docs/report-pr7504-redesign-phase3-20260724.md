# PR #7504 재설계 — Phase 3 완료 보고 (2026-07-24)

- 커밋: `3bc1e13c8` (스택: 1583d80d5 → 8f6d95a6c → db75893e6 → 50aba692f → **3bc1e13c8**, push 안 함)
- provenance: `~/dev/bkx-redesign/evidence/provenance-20260724-002741/manifest.txt` — fresh build `11.5.0.2417-3bc1e13`, **전 레인 PASS** (r4, R1~R4 replay, 옵션 매트릭스, crash sweep, splitter-skew, compat 구→신, W0/W1/W2 clean abort, restart-forward-commit)

## 수행 내용

1. **record packer 공용화**: `btree_write_record`의 packing 로직을 `btree_write_record_internal`(overflow-key 저장 callback 주입)로 추출, bulk loader의 복제 직렬화기와 `0x8000`/`0x4000` 리터럴 재정의 삭제(grep 0건). 바이트 레이아웃 불변을 opcode 단위 정적 대조로 확인. 기존 `btree_write_record` 시그니처·호출처 7곳 무변경.
2. **shard 상태 명시화**: `memcpy` clone 제거 → `bt_load_init_shard_load_args`가 LOAD_ARGS 34필드 전부를 3그룹(shard-불변/per-shard/호출자 공급)으로 명시 할당. 향후 필드 추가가 memcpy에 무검토 편승할 수 없는 구조. (BT_LOAD_SHARED/STATE 구조체 분리는 ~150+ 접근처 churn 대비 이득 없어 기각 — 근거 기록)
3. **free_and_init 관례 통일** + 정책 상수화(`BT_LOAD_SPAN_LOW_WATERMARK_DIVISOR=4`, `BT_LOAD_VACUUM_ITEMS_INITIAL_CAPACITY=16`; 보고서의 `<<16`은 실코드에 부재 확인).
4. **2-core 게이트**: `compute_parallel_degree`의 공통 `<=2코어` early-return에서 INDEX_BUILD 제외(JIRA degree≥2 요구). 타 타입(SCAN/HASH_JOIN/SORT/SUBQUERY) 동작 불변.
   - **신규 tc-2core 레인 실증**: `system_core_count`가 `sched_getaffinity` 기반임을 확인(resources.cpp:92) → `taskset -c 0,1` 서버에서 no-redo 발화 committed barrier=1, 스캔 정합 50000 — PASS.
5. **BT_LOAD_PAGE_SINK: 명시적 기각** — `new_page_fn`+`btree_log_page` 조합이 이미 양 모드가 공유하는 page-sink이며(호출처 ~15곳 모드 무분기), 래핑은 간접화만 추가하고 제거할 중복이 없음.

## 구조 게이트 현황 (누적)
- `external_sort.c`: `SORT_ARGS|btree_load|bt_load_|LOAD_ARGS|BT_LOAD` grep **0건**, `#include "btree_load.h"` 삭제 — sorter의 B-tree 의존 0 달성.
- legacy serial kernel: 직렬 경로 변경은 어댑터 접합부(prepare NOT_APPLICABLE, put_fn, packer 위임)로 한정.
- churn 참고치: develop 대비 24파일 +4,844/-1,122 (원 PR 21파일 +4,120/-944). 재설계는 원 PR 위 적층이라 총량은 늘었으나, **핵심 두 파일의 구조**가 바뀜 — external_sort.c는 원 PR 대비 -455/+… 로 순축소(현재 develop 대비 +1,294, 원 PR은 +1,163이었으나 B-tree 결합 0), btree_load.c가 경계 구현을 흡수. squash 후 최종 diff 정리는 Phase 4 이후 리뷰 대응에서.

## Phase 4 (진행 중 착수)
1. optdebug 풀빌드 + CS 라이브 스모크(assert/tracker leak 0) + FI 프로브(prepare 중간 실패 주입 → transactional rollback 실증, 직렬 abort vacuum 오라클) + splitter-balance(debug 계측, LANE=ordered).
2. 성능 캠페인: 20GB t20g 재구성 픽스처, dev(2320) / PR-base(2412-3ffeab7) / 재설계(2417-3bc1e13) 3-레인 cold 교대, warmup 1+유효 3 — **수용 게이트 = base vs 재설계 상대 델타 회귀 없음**.
