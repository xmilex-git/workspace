# PR #8198 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8198](https://github.com/CUBRID/cubrid/pull/8198)
**제목:** [CBRD-27463] Check a foreign key's parent without locking its row
**작성자:** hgryoo
**HEAD SHA:** `fbaae2592` (develop merge-base `2d928e34b`)
**JIRA:** CBRD-27463 (Sub-task, Develop) / 연관: CBRD-26997(parent), CBRD-26664, CBRD-27464, CBRD-27941, 후속 CBRD-27654
**TC PR:** CUBRID/cubrid-testcases#4049 (`tc/pr-8198` `7c8788285`, draft) / CUBRID/cubrid-testcases-private-ex#4756 (`669c39fa4`, draft)
**리뷰 일시:** 2026-11-10
**리뷰 결정:** 엔진 PR Approve (5839310047), TC #4049 Approve (5839310265), TC #4756 Approve + 인라인 1 건 (5839310506). 발견 1, 2, 4 는 게시하지 않음. TLA+ 미완 상태의 Approve 는 사용자 결정(2026-11-10)

> **TL;DR** (작성자 확인 필요): 엔진 코드에서 머지를 막을 결함은 찾지 못했고, JIRA 대표 재현은 merge-base 에서 lock timeout, head 에서 즉시 성공으로 갈린다. 다만 리뷰 중 고친 세 커밋(c95b7ee1e 자기 참조 PK UPDATE 고아, a9f1fefef, fbaae2592)의 회귀 케이스가 두 TC PR 에 없고, TC PR 의 실행 근거는 그 앞 `39631cfe9` 에 머물러 있다. JIRA 의 "TLA+ 검증" 은 코멘트 한 줄뿐이라 산출물로 확인되지 않는다.

## Summary

- **변경 요약**: 자식 INSERT/UPDATE 의 외래 키 검사에서 부모 행 S 락을 없애고, 부모 DELETE/키 변경은 키 삭제 표시 -> 자식 수집 -> writer 대기 -> 잠금/재확인/동작의 세 단계로 자식을 처리한다. 외래 키 컬럼을 SET 하지 않는 UPDATE 는 검사를 건너뛰고, UPDATE 는 heap 을 인덱스보다 먼저 고친다.
- **주요 이슈**: TC PR 에 최근 세 수정의 회귀 케이스가 없고, isolation 케이스는 CI 가 돌리지 않아 head 에서 실행된 근거가 없다.
- **확인 필요 사항**: JIRA 코멘트가 근거로 든 TLA+ 모델(spec, cfg, `RESULT:`)의 첨부, head 기준 isolation 재실행.

---

## Findings

### Non-blocking (should consider)

1. TC PR 두 개에 리뷰 중 고친 세 커밋의 회귀 케이스가 없다. PR 본문 Verification 은 "추가 isolation TC 3 개 · SQL TC 1 개(13 case)" 통과를 적지만, 두 `tc/pr-8198` 브랜치는 2026-11-06 (`7c8788285`, `669c39fa4`) 이후 갱신이 없고 `sql/` 파일도 없다. 특히 c95b7ee1e 는 부모 없는 행 `(101, 1)` 이 커밋되던 결함이라, 되돌아와도 잡을 케이스가 없다.
2. TC PR 의 실행 근거는 `39631cfe9` 기준이고, 그 뒤 엔진에 대기 순서를 바꾸는 커밋 다섯 개(a9f1fefef 의 heap 선갱신, fbaae2592 의 슬롯 재사용 건너뛰기 포함)가 들어왔다. gha-ci 는 isolation 을 돌리지 않으므로 변경된 isolation 케이스 69 개가 head 에서 실행된 기록이 없다 (P30).
3. `shell/_40_guava/cbrd_27463/cases/cbrd_27463.sh` 헤더가 `kf_upd_nonkey` 를 "still runs the check" 라고 적지만, head 는 외래 키 컬럼을 SET 하지 않는 UPDATE 의 검사를 건너뛴다(`locator_check_foreign_key ()` 의 `locator_index_has_attr ()` 분기). 케이스의 판정(락 0 개)은 그대로 맞고, 주석만 사실과 다르다.

### Questions for the author

4. JIRA 의 TLA+ 근거: 2026-11-07 코멘트가 "리뷰 중 TLA+ 모델과 서버 재현으로 찾은 결함" 과 "모델에서만 확인" 한 잔여 구간을 적지만, JIRA 본문 · `design.md` · `test.md` 어디에도 spec, cfg, 경계, `RESULT:` 줄이 없다. 그 모델을 첨부하고, 코멘트 이후 커밋(e93eaeaf7, fbaae2592)까지 반영해 다시 돌린 결과를 남길 수 있는지.

## JIRA -> Engine PR

기준: Expected Result 가 재현 조건에서 성립, `design.md` 의 변경이 구현, 미정 항목이 해소 또는 사유 명시.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 미커밋 자식 INSERT 뒤 부모 비키 UPDATE 가 기다리지 않음 | smoke S1: merge-base 3.07 s 뒤 lock timeout, head 0.03 s 성공 | 충족 |
| 자식 INSERT 뒤 lockdb 에 부모 행 S 없음 | smoke S5: granted S_LOCK merge-base 1, head 0. 셸 `cbrd_27463` CI 통과(6c4d758f5) | 충족 |
| RESTRICT · CASCADE 고아 없음, 미커밋 자식과 겹치는 부모 DELETE | smoke S2(고아 0), S3(ER_FK_RESTRICT, 고아 0). TLA+ C1 TLC 통과 | 충족 |
| 삽입 뒤 들어온 writer 를 부모가 기다리지 않음, 슬롯 재사용 | TLA+ C4 TLC 통과, mutant 2 개 위반 검출. 작성자 6/6 -> 0/6 | 충족 |
| 자기 참조 PK UPDATE 가 ER_FK_INVALID 로 실패 | smoke S4: 두 빌드 모두 -922, 행 `(1, 1)` 유지 | 충족 (TC 없음, 1) |
| HA 복제 일치(ON UPDATE SET NULL 6 경우) | `just ctp ha_repl` review 케이스(부모 PK UPDATE 단일/다중, 비키 UPDATE, CASCADE DELETE, 자기 참조, 분할 부모 이동): master/slave 덤프 28,270 줄 차이 0 | 충족 |
| ADD FOREIGN KEY 기존 행 검증 락 유지 | `btree_check_foreign_key ()` 는 `xbtree_find_unique (S_SELECT_WITH_LOCK)` 그대로, 주석만 추가 | 충족 |
| 비용이 변경 없는 빌드와 같은 범위 | release instructions:u(Runtime 표): INSERT -10.8%, 비키 UPDATE -20.8%, 자식 없는 부모 DELETE 0%, CASCADE 2 만 +4.6% | 충족 |
| 기존 외래 키 · 락 · MVCC 회귀 통과 | 6c4d758f5 sql/medium/shell 통과. head 실행 진행 중. isolation 은 39631cfe9 기준만 | 부분 (2) |
| 미정: "32 시나리오, 외래 키 123 개, RESTRICT 변형 검증 미완" (PR 본문) | PR 이 미완이라고 명시 | 부분 |

연관 이슈: CBRD-26664 (부모 행 S 로 인한 교차 대기) 는 이 PR 이 해소한다. CBRD-27941 (TPC-C NEW-ORDER 데드락) 은 TC PR 의 케이스 2 개가 이 PR 로 해소된다고 적는다. 자식 행만 도는 교착은 CBRD-27654 로 넘겼다.

판정: 부분 (전체 회귀 head 실행 진행 중, 작성자 미완 항목).

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 부모 비키 UPDATE 무대기 · 교차 UPDATE 무교착 | #4049 `fk_parent_unlocked/` 3 개 | 통과 |
| 부모 표시 뒤 들어온 writer | #4049 `fk_parent_mark_newcomer/` 14 개 | 통과 |
| 1 단계 이전 writer · CASCADE 형제 | #4049 `fk_parent_early_writer/` 14 개 | 통과 |
| RESTRICT 선언 순서 · 자기 소유 자식 | #4049 `fk_parent_restrict_check/` 8 개 | 통과 |
| 부모 행 락 수 | #4756 `cbrd_27463` (CI 6c4d758f5 통과) | 통과 |
| 자기 참조 PK UPDATE (c95b7ee1e) | 없음 | 미충족 (1) |
| UPDATE heap 선갱신 교착 (a9f1fefef) | 없음 | 미충족 (1) |
| 되돌린 INSERT 슬롯 재사용, 세이브포인트 · 유일 키 실패 형태 (fbaae2592) | `child_insert_into_slot_of_failed_child_insert` 는 11-06 판. fbaae2592 의 6 형태는 없음 | 부분 (1) |

TC 파일: 변경 `.ctl` 69 개 중 answer 없는 6 개는 기존 케이스의 단계만 고친 것이라 기존 answer 를 쓴다. `/* ... ; */` 주석은 develop isolation 케이스 348 개가 같은 형식이라 문제없다. #4756 헤더 주석 하나가 head 동작과 다르다 (3).

판정: 부분.

## TLA+ Verification

```
TLA+ 검증: 미완 — .claude/review/PR-8198/tla/fk-parent-unlocked/
- 속성: C1 NoOrphan safety TLC 통과 / C3 NoParentRowLock safety TLC 통과 / C4 NoNewcomerWait safety TLC 통과 /
        C5 NoP1WaitHoldingChild safety TLC 통과 / C6 HeapFirst safety TLC 통과
        (출처: JIRA A/C, PR 본문 §1·§3, 39631cfe9, a9f1fefef, fbaae2592); IndInv 귀납성 미실행; TLAPS 요청 없음
- 결함: 없음
- mutant: 10 개 모두 위반 검출 (develop 의 부모 S, 항목 전 검사 x2, 표시 전 수집, 삽입 중 제외,
          2 단계 제거, heap 후갱신, seen 필터 제거, 삽입자 비교 제거) / 살아남은 mutant 없음
- 경계: writer 2, 문장 2, 슬롯 3 (scale 슬롯 4: CASCADE 23,305,032 상태, RESTRICT 11,807,188 상태), 부모 키 1
- trace validation: 수용 6 건(CASCADE 4, RESTRICT 2, 슬롯 재사용 포함), 거부 4 건 — 계측 빌드 fbaae2592+89 줄
- 반례: 2 건 모두 모델 claim 이 PR 문구보다 넓었던 것 — Remarks 가 인정한 교착으로 분류하고 claim 을 PR 문구에 맞춤
- RESULT: FAILED (1) — cfg 30 개 모두 기대대로 통과, 실패 1 건은 Apalache 귀납성 cfg 없음(미작성)
```

작성자 주장과의 관계: JIRA 에는 모델 산출물이 없어(4) 작성자 모델과 비교하지 못했다. 이 모델은 head 코드에서 새로 만들었고, 코멘트가 말한 잔여 구간(행 X 를 잡은 뒤 스탬프 전)은 C6 이 허용하는 구간과 같다. 모델 범위 밖(HA 는 Runtime 에서 확인): 자기 참조 PK UPDATE, `repl_update_lsa`, 다중 부모, REPEATABLE READ.

## Runtime Verification

| 실행 | 빌드 | 결과 |
|---|---|---|
| smoke S1-S5 (CS, 서버 1 개) | optdebug CI tarball: head `fbaae2592` (libcubrid `e0c8e5ce`), merge-base `2d928e34b` (`fa662eee`) | 위 JIRA 표. assert · core 없음 |
| perf A/B, instructions:u, `cub_server`, 3 회 중앙값 | release CI tarball: head (`b7f76103`), merge-base (`4ba95bfb`) | 자식 INSERT 2 만 1.511G -> 1.348G, 비키 UPDATE 2 만 1.163G -> 0.920G, 자식 없는 부모 DELETE 19,999 행 1.189G -> 1.187G, CASCADE 2 만 1.348G -> 1.410G, 실패 RESTRICT(자식 2 만) 130M -> 146M (head 편차 76-162M) |
| gha-ci run 42237572792 | `6c4d758f5`, `tc/pr-8198` (`7c8788285`, `669c39fa4`) | sql/medium/shell pass, sql_by_cci NOK 33 (host var · collation, 외래 키 무관) |
| gha-ci run 42764136813 | head `fbaae2592` | 빌드 통과, 테스트 진행 중 |
| HA review 케이스 (`just ctp ha_repl`, `_99_review_adhoc/pr8198_ha`) | optdebug CI tarball head `fbaae2592` | PASSED 1/1, master/slave 덤프 28,270 줄 차이 0, core 0 |
| trace 기록 6 run (CS, 서버 1 개) | 계측 optdebug fbaae2592+89 줄 (libcubrid `f31b3681`) | 고아 0, 계측 빌드에서 assert · core 없음 |
| isolation (#4049) | — | 미실행: `just ctp` 가 isolation suite 를 지원하지 않음 |

## Existing Comments

| 코멘트 | 상태 |
|---|---|
| greptile P1 "부모 키 UPDATE가 교착됩니다" (`a8f9b3782`, `locator_find_child_writer ()` 의 `del_action`) | 답글 없음. head 에서 함수가 없어지고 `locator_collect_children_of_key ()` 가 `on_update ? upd_action : del_action` 으로 고름. 해소됨 |
