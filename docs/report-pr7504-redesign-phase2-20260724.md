# PR #7504 재설계 — Phase 1 재검토 대응 + Phase 2 완료 보고 (2026-07-23~24)

- 브랜치 `pr-7504-redesign`, 커밋 스택 (push 안 함):
  - `1583d80d5` Phase 1 (프로토콜 + barrier postpone/2-rcvindex)
  - `8f6d95a6c` Phase 1 재검토 대응 (UB-free guard, scope_exit, 주석 다이어트)
  - `db75893e6` Phase 2 (6-op 경계 계약)
  - `50aba692f` Phase 2 주기리뷰 대응 (transactional prepare, 직렬 vacuum notify, 완전 불투명화)
- 증거: `~/dev/bkx-redesign/evidence/` (provenance manifest 2개 포함), 계획: `docs/plan-20260723-pr7504-redesign.md`, ADR: `~/dev/bulk_index_build/docs/adr/0001-bulk-build-barrier-commit-time-postpone.md`

## 1. Phase 1 재검토(Blocking 2) 대응 — 전부 해소

| 지적 | 대응 (커밋 `8f6d95a6c` + provenance 런) |
|---|---|
| tail guard의 one-past-end 포인터 UB | 순수 정수 오프셋 비교로 교체: `DB_ALIGN((size_t)(ptr-request), INT_ALIGNMENT) + OR_INT_SIZE <= reqlen`. 경계 밖 포인터를 생성 자체를 안 함 |
| 검증 provenance (커밋↔바이너리 결속 불가) | **provenance-run.sh 신설**: 커밋 HEAD에서 fresh build → manifest.txt(HEAD sha, clean status, cubrid_rel, cub_server/cubrid/libcubrid SHA-256, 하네스 트리 combined hash, 훅 패치 hash, 전 명령 rc) → 핵심 배터리 재실행. db75893e6에서 1회 완주(전 레인 PASS), 50aba692f에서 재실행 |
| (non-blocking) media flag 수동 reset 5곳 | 기존 `scope_exit.hpp`로 set 지점 1곳에 묶음 — early-return 누락 위험 제거 |
| (non-blocking) 주석 과다(~66줄) | 소스는 불변식만("pending action → committed marker → media replay refuse"), crash-window/supersede 논증은 ADR로 이관. log_recovery.c 주석 -40줄 |
| (non-blocking) barrier 주석의 attach 오서술 | 정정: no-redo 경로엔 open sysop이 없어 postpone이 outer tran에 직접 등록됨 |
| (non-blocking) "흔적 없음" 용어 | "committed 증거 없음"으로 교정(pending DURABLE 레코드는 로그에 남고 스킵됨) |
| (non-blocking) plan/README 구식 서술 | plan을 2-rcvindex·clean-abort-or-refuse 결론으로 갱신, tc-bundle README v4 헤더/오라클 서술 갱신(raw server 유지 사유 명시) |
| exact-old-request 경계 | 구(2320) 클라이언트 실요청이 그 케이스 — provenance 런의 compat 레인이 매회 검증 |

## 2. Phase 2 — sorter/loader 경계 접기 (커밋 `db75893e6` + `50aba692f`)

### 계약 (external_sort.h 선언, btree_load.c 구현)
- **`SORT_PX_OUTPUT_OPS` 6-op**: `prepare`(3상태·transactional) / `service`(리더 페이지 공급) / `end_shard`(워커 마감) / `finish`(tree finalize만, 소유권 전이는 마지막 한 단계) / `abort_px`(멱등 회수) / `decode_key`(COPY 복원). consume은 legacy `SORT_PUT_FUNC` 그대로(레코드당 간접호출 1회 불변).
- **`SORT_PX_OUTPUT_SPEC`**(주기리뷰 대응에서 추가): ops + output_applicable + key_type + worker scan open/close + input sector 추정 + scan args clone + scan 통계 merge — get측 결합까지 전부 불투명화. `external_sort.c`에서 `SORT_ARGS|btree_load|bt_load_|LOAD_ARGS|BT_LOAD` **grep 0건**, `#include "btree_load.h"` 자체 삭제.
- 소유권 규칙 구현(정정 2026-07-24, 주기리뷰 반영): **ERROR는 transactional**(반환 전 파일·sysop·provider·shard 전량 자체 회수, attach는 READY 직전 — 주기리뷰 Blocking 2 해소); **NOT_APPLICABLE은 직렬 출력 대상(미부착 sysop 안의 새 파일)을 의도적으로 열어둔 채 반환**하고 직렬 put 실패 시 `abort_px`(n≤0 형태)가 회수 — 두 콜사이트의 중복 파일생성 로직을 단일화. `clone_scan_args`도 transactional(부분 실패 시 생성분 전량 자체 파괴).
- `btree_load.h`의 bt_load_* extern 14개·LOAD_ARGS/BT_LOAD_PROVIDER 타입 노출 제거(파일-로컬화), `log_manager.h`의 `log_get_system_op_level` 원복.

### 실행 중 잡은 결함 (fail-before-fix 증거 보존)
1. **직렬 폴백 파일생성 누락**(내 통합 검증에서 검출): N1 csql 직렬 빌드가 "fetching deallocated pageid -1"로 즉사 → prepare NOT_APPLICABLE에 sysop+create 복원. 재현→수정→PASS.
2. **직렬 분기 vacuum UNDO notify 누락**(주기리뷰 Blocking 1): 병렬 분기와 동일한 `vacuum_log_add_dropped_file(UNDO)` 추가.
3. **prepare 중간 attach**(주기리뷰 Blocking 2): provider/shard 실패 시 부분 파일이 outer tran에 붙는 문제 → attach를 전 자원 성공 후로 이동, 실패 경로는 sysop_abort로 전량 회수. provider 페이지 선할당의 nested sysop 합성 안전성 정적 확인.

### 검증 (모두 실측)
- 배터리(R1~R4 replay, 옵션 매트릭스, crash sweep, splitter-skew): 리뷰수정 빌드에서 **전 레인 PASS**.
- provenance 런(fresh build + manifest + r4 + 배터리 + compat 구→신 + W0/W1/W2 crash-window + restart-forward-commit): db75893e6에서 완주 PASS, 50aba692f 재실행분은 이 보고서 하단 갱신.
- 구조 게이트: grep 0건 (executor 보고 + 독립 재확인).

## 3. 주기리뷰(db75893e6) 대응 요약

- Blocking 3건: 위 결함 2·3 + get측 의존 제거(SORT_PX_OUTPUT_SPEC) — **전부 50aba692f에서 해소**.
- Non-blocking 7건: 시점 의존 주석 4곳 현재형 서술로 재작성, 끊긴 심볼명 복구, `SORT_PX_MIN_SHARDS`(공유 상수)·`BT_LOAD_EST_MIN_RESERVE_PAGES`/`BT_LOAD_EST_RESERVE_DIVISOR` 명명 — 반영 완료.
- 증거 공백 지적 중 잔여(Phase 3~4로 편성): exact-HEAD **optdebug** 풀빌드+FI(provider/shard 실패 주입, 직렬 abort vacuum 오라클), splitter-balance(debug 계측 필요), 2-core 레인, Phase 4 성능 비교. — Phase 4 배터리에 명시 편성됨.

## 4. 운영 기록
- 배터리 실행 중 병행 인터랙티브 conf/데몬 조작이 플레이크 2건을 만들었음(tc-p2b precondition 실패) → **원칙 추가: 배터리 모니터 실행 중 트리·conf·데몬 병행 조작 금지**(provenance-run.sh 헤더에 명문화).
- crash-window 훅은 `crash-window-hooks.patch`(sha256 manifest 기록)로 관리 — 커밋 트리에 절대 포함 안 됨.

## 5. 다음: Phase 3
LOAD_ARGS clone→SHARED/STATE 분리, record packer 공용화(0x8000/0x4000 제거), free_and_init·잔여 상수화, BT_LOAD_PAGE_SINK 실측 판단, px_parallel 2-core 게이트. 이후 Phase 4(성능 상대델타 + optdebug/FI 배터리).

---
### Provenance (50aba692f) 결과 — 완주 PASS
- manifest: `~/dev/bkx-redesign/evidence/provenance-20260723-235511/manifest.txt`
- HEAD 50aba692f, fresh build `11.5.0.2416-50aba69` (cub_server/cubrid/libcubrid SHA-256 기록), 하네스 combined hash 기록
- r4(abort-class) rc=0 / tc 배터리 4종 전 PASS(R1~R4·옵션 매트릭스·crash sweep·splitter-skew) / compat 구(2320)→신: 빌드 성공+인덱스 존재+committed 불변(logged 경로) / crash-window W0·W1·W2 전부 clean abort(부재+행 보존+checkdb 0) / restart-forward-commit 인덱스 생존
- 직전 1회 실패(PROV2)는 제품 무관: provenance 스크립트가 r4용 databases.txt를 덮어써 잔존 볼륨과 충돌 — 런별 고유 TAG로 수정(스크립트에 사고 주석 명문화)
- 참고: Phase 2 순수 diff(1583d80d5..50aba692f)는 4파일 +376/-217 — sorter의 B-tree 의존 grep 0건 달성
