# PR #8431 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8431](https://github.com/CUBRID/cubrid/pull/8431)
**제목:** [CBRD-27972] Compact a key's overflow chain only while its leaf record holds a stable object
**작성자:** shparkcubrid
**HEAD SHA:** `6cc3c42d4` (develop merge-base `953e83256`)
**JIRA:** CBRD-27972 (Correct Error, Analysis) / 연관: CBRD-27401 (Regress), CBRD-27973 (같은 TLA+ 모델의 H2, 이 PR 범위 밖)
**TC PR:** CUBRID/cubrid-testcases#4063 (`tc/pr-8431` `3d4494b8`, 변경 없는 draft) / CUBRID/cubrid-testcases-private-ex#4770 (`3ad598b2`)
**리뷰 일시:** 2026-11-09
**리뷰 결정:** 엔진 PR Approve (NIT 1건 + 비 MVCC 경로 질문 1건), private-ex#4770 Approve, cubrid-testcases#4063 없음 (TLA+ RESULT 확정 후 게시, 미게시)

> **TL;DR** (작성자 확인 필요): TLA+ 모델에서 PR의 가드가 CBRD-27972(H1)를 막는다. 수정 전 동작은 행 하나를 잃는 반례를 내고, 수정 후 변형은 통과한다. 가드의 세 조건(DELID 없음, 미커밋 삽입 아님, latch 라운드마다 재검사)과 비 MVCC 클래스 제외는 하나씩 빼면 모두 반례가 나온다. 남은 지적은 static 프로토타입 누락 1건과 비 MVCC 클래스 질문 1건이다. TLA+ 판정은 scale/liveness 미완료로 미완이다.

## Summary

- **변경 요약**: `ALTER INDEX ... COMPACT`가 키의 leaf 레코드에 안정 객체(삽입 커밋, 삭제 MVCCID 없음)가 있을 때만 그 키의 overflow 체인을 당기고, MVCC가 꺼진 클래스의 인덱스는 컴팩션하지 않는다.
- **주요 이슈**: 없음 (Non-blocking 1건: 프로토타입 블록)
- **확인 필요 사항**: MVCC가 꺼진 클래스에서 키 중간 재개가 일어날 수 있는지 (모델에서 COMPACT 없는 손실 경로, develop에도 있음)

---

## Findings

### Non-blocking (should consider)

1. `src/storage/btree.c` 정적 프로토타입 블록 (`btree_compact_fix_leaf` 선언 바로 뒤) — 새 static 함수 `btree_compact_leaf_has_stable_object`의 선언이 없다. 같은 파일의 COMPACT 도우미(`btree_ovf_compact_pull`, `btree_ovf_compact_chain`, `btree_compact_fix_leaf`)는 모두 정의 순서대로 블록에 선언돼 있다.
   ```c
   static int btree_compact_fix_leaf (THREAD_ENTRY * thread_p, BTID_INT * btid_int, DB_VALUE * key,
   				   PAGE_PTR * leaf_page, INT16 * slot, bool * found);
   /* btree_compact_leaf_has_stable_object 선언이 여기 와야 함 */
   ```

### Questions for the author

1. `xbtree_compact_overflow`의 `mvcc_is_mvcc_disabled_class` 분기 — MVCC가 꺼진 클래스(root, `db_serial`, `_db_collation`, `db_ha_apply_info`)의 기본 인덱스는 모두 PK/unique라 이 분기에 걸리는 비유니크 인덱스가 있는지 불분명하다. 모델에서는 그런 인덱스라면 COMPACT 없이도 물리 삭제로 처리된 첫 overflow 페이지가 통째로 빠진 뒤 leaf swap이 미반환 객체를 옮기는 경로가 나온다(develop에도 있는 경로, 런타임 미재현).

## JIRA -> Engine PR

기준: Expected Result가 재현 조건에서 성립하고, 수정 방향(JIRA 작성자 코멘트)의 변경이 모두 구현됐는지.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: 재현(h1_repro.sh, 재개 8초 지연)에서 인덱스 스캔이 9,974행 모두 반환 | PR head instrumented optdebug에서 9,974/9,974 (key 1 `CompactCheck stable=0`, Pull 없음, Swap은 앵커 객체만 이동). 수정 전은 JIRA의 develop `21c6e635d` 3회 모두 9,973 | 충족 |
| 수정 방향: leaf에 안정 객체가 있을 때만 컴팩션, latch 획득마다 재검사 | `xbtree_compact_overflow`가 `spage_get_record` 직후, 같은 write latch 안에서 `btree_record_process_objects (..., btree_compact_leaf_has_stable_object, ...)`를 돌리고 `!has_stable`이면 키를 건너뜀. yield 뒤 `btree_compact_fix_leaf`로 다시 잡은 라운드도 같은 경로 | 충족 |
| 수정 방향: 삭제/미커밋 객체뿐인 키는 건너뛰고 `pairs_skipped`에 집계 | `(*pairs_skipped)++`, 미완 체인의 `key_freed` 정산 후 다음 키 | 충족 |
| 수정 방향: MVCC가 꺼진 클래스의 인덱스는 컴팩션하지 않음 | `mvcc_is_mvcc_disabled_class (&btid_int.topclass_oid)`이면 즉시 반환 | 충족 |

연관 이슈: CBRD-27401(Regress)은 이 결함을 들여온 기능이다. CBRD-27973(crash 중간의 leaf swap)은 같은 모델에서 나온 별개 결함이고, 이 PR은 다루지 않는다. 판정: 충족.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| leaf 유일 객체를 미커밋 트랜잭션이 삭제한 상태의 COMPACT는 체인을 그대로 둠 | private-ex#4770 `cbrd_27972.sh` 검사 4 (수정 전 develop `953e83256`에서 NOK라고 PR 본문에 기재) | 통과 |
| 안정 leaf 키는 같은 COMPACT에서 컴팩션됨 (대조군) | 검사 5 | 통과 |
| 커밋 + vacuum 뒤 COMPACT는 컴팩션됨 | 검사 7 | 통과 |
| 기존 `cbrd_27401`(모든 체인 컴팩션 요구) 유지 | PR 본문, gha-ci shell 통과 | 통과 |

TC 파일: 헤더 주석은 셸 heredoc이라 `;` 제약 대상이 아니고, 검사마다 `write_ok`/`write_nok`가 있다. 스캔 멈춤 창 자체는 재현하지 않는다고 본문에 밝혔다(타이밍 의존 없음). cubrid-testcases#4063은 변경 없는 draft라 검토 대상이 아니다. 판정: 승인 가능.

## TLA+ Verification

TLA+ 검증: 미완 — `.claude/review/PR-8431/tla/ovf-compact-stable` (기존 `docs/tla/CBRD-24094-ovf-dir`의 `OvfDirChain`/`OvfScanResume`을 그대로 복사하고 MVCC 상태와 PR 가드를 얹은 `OvfScanStable`, 논거 추상 모델 `OvfGuard`)
- 속성: C1 safety(멈춘 스캔이 보이는 행을 정확히 한 번 반환, JIRA Expected Result) TLC 통과 / C2 safety(멈춘 사이 swap이 미반환 객체를 옮기지 않음, PR 주석) TLC 통과 + `OvfGuard` IndInv 귀납성 Apalache 통과 / C3 safety(안정 객체 검사가 C2를 지킴: DELID, 미커밋, latch마다 재검사) TLC 통과 + refinement `GuardRefined` 통과 / C4 safety(MVCC가 꺼진 클래스는 컴팩션 안 함) TLC 통과 / C5 liveness(스캔 종료) 미완(OID 4개에서 165,284 상태까지 위반 없음, 중단) / TLAPS 요청 없음
- 결함: 없음. 수정 전 동작(merge-base) mutant가 H1 반례(깊이 12)를 내고 수정 후 변형은 통과.
- mutant: 8개 모두 위반 검출(merge-base, stale-check, delid-stable, uncommitted-stable, env-vacuum-ignores-snapshot, no-class-check, resume-blocked, OvfGuard no-guard) / 살아남은 mutant: 없음
- 경계: NOid 4, NVer 1, PageCap 2 (917,557 distinct, 깊이 35); scale NOid 3 x NVer 2는 13,320,474 distinct까지 위반 없음, 중단(미완); IndInv 귀납성은 Apalache로 boolean 추상 모델 전체
- trace validation: 수용 2건(실행 A 9,974/9,974 COMPACT 건너뜀, 실행 B 9,975/9,975 정지 중 Pull 4회 후 swap은 재개 뒤), 거부 2건(가드 답 뒤집기, swap을 재개 앞으로 이동)
- 반례: 비 MVCC 클래스에서 COMPACT 없는 손실 경로 1건 — develop에도 있는 경로, PR 범위 밖, 런타임 미재현(작성자 질문으로 남김). 모델 오류 1건(비 MVCC 객체 보호 가정) 수정 후 재검사.
- 최종 `RESULT:` 줄 없음: 디렉터리 전체 실행 전 세션 종료.

## Runtime Verification

- CI: gha-ci run 42184094384 (`/run rerun 42165284791`) build debug/release, test_sql, test_medium, test_shell 모두 pass. head `6cc3c42d4`.
- 로컬: PR head + `tla-evidence-21c6e635d.patch` + `CompactCheck` 로그 1줄, optdebug (`~/optdebug/CUBRID-pr8431-instr`, libcubrid fingerprint `71764065edf7d65e`), conf `parallelism=1`, `max_parallel_workers=1`.
  - 실행 A (JIRA h1_repro.sh 그대로): 9,974/9,974. key 1 COMPACT 건너뜀, Swap은 앵커(이미 반환한 객체)만 이동.
  - 실행 B (leaf 객체를 안정으로 두고 스캔 정지 중 COMPACT 후 삭제 + vacuum 개방, 재개 20초 지연): 9,975/9,975. 정지 중 Pull 4회, 삭제된 leaf 객체의 Swap은 스캔 재개 뒤(seq 71 > Resume seq 65)에야 일어남.
- 수정 전 재현: JIRA의 develop `21c6e635d` 기록(3회 모두 1행 누락)을 재사용. `21c6e635d..953e83256`에 `btree.c` 변경 없음(git log 0건), merge-base에서 다시 돌리지는 않음.
