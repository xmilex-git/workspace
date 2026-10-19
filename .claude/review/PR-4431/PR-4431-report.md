# PR #4431 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4431](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4431)
**제목:** [CBRD-27401] Re-add the ALTER INDEX ... COMPACT shell case without --check-btree-entries (07:57Z 에 바뀐 제목)
**작성자:** shparkcubrid
**HEAD SHA:** `8cf9e1e56` (`d38cd7395` + develop merge, 07:57Z; 케이스 파일 blob `6091197be` 는 두 head 가 같음)
**JIRA:** CBRD-27401 (Improve Function/Performance, Resolved; 엔진 CUBRID/cubrid#7899, merge `0c310e25c`) / 연관: CBRD-24094 (오버플로 디렉터리 포맷)
**TC PR:** 이 PR 자체. #4394 로 머지된 shell 케이스 `shell/_40_guava/cbrd_27401` 가 CI 시간 초과로 #4430 에서 revert 된 뒤의 재제출
**리뷰 일시:** 2026-10-14
**리뷰 결정:** #4431 Comment (본문 + 인라인 suggestion 1)

> **TL;DR** (Non-blocking): 시간 초과 해소는 확인했다 (gha-ci `/run shell` 에서 19/19 OK 42초, 로컬 develop optdebug 19/19 OK x3 각 84초). 다만 entries 검사 (`--check-btree-entries`, 힙 행과 인덱스 객체를 하나씩 맞춰 보는 검사) 를 빼면서 vacuum 이 놓친 인덱스 객체를 아무 검사도 못 잡게 되므로 O(n) 대체 검사를 제안한다.

## Summary

- **변경 요약**: check 5 (`checkdb -C`), check 19 (`checkdb -S`) 에서 entries 검사만 빼고 나머지 5개 검사를 명시
- **주요 이슈**: 헤더의 "키별 count 가 인덱스-힙 일치를 이미 검사" 주장이 사실보다 강함 (JIRA AC 2)
- **확인 필요 사항**: 없음

---

## Findings

### Resolved before posting

1. 브랜치 base (작성자가 07:57Z 에 develop merge `8cf9e1e56` + 제목/본문 수정으로 해소, 지금 `MERGEABLE`) -- PR base `21811efe3` 은 #4430 (`6030b1e28`, 이 케이스 revert, 05:20Z) 이전이다. develop 에는 `shell/_40_guava/cbrd_27401` 가 없어 GitHub 이 `mergeable: false`, `mergeable_state: dirty` (modify/delete 충돌) 를 보인다. develop 으로 rebase 해서 커밋이 파일 전체를 다시 추가하게 하고, 제목/본문도 "revert 된 케이스를 entries 검사 없이 다시 넣는다" 로 바꿔야 한다. 나머지 내용은 머지됐던 `2483c0803` 과 같다 (diff 로 확인) -> 리뷰 범위는 이번 delta.

### Non-blocking (should consider)

2. `cbrd_27401.sh:76-80, 417-421` -- entries 검사를 빼면 vacuum 이 놓친 인덱스 객체를 잡는 검사가 없어진다.
   - entries 검사 2단계 (인덱스 -> 힙) 는 `isid.check_not_vacuumed = true` 로 돌고, vacuum 이 지웠어야 할 객체를 `ER_INDEX_FOUND_NOT_VACUUMED` 로 보고한다 (`locator_check_btree_entries`).
   - 키별 count 는 MVCC (다중 버전 동시성 제어) 스냅샷에 보이는 객체만 센다. 삭제가 커밋되고 힙 레코드는 지워졌는데 인덱스 객체만 남으면 idx/heap 양쪽에서 빠져 같아진다.
   - `--check-btree` 에 남는 `btree_ovf_dir_check` (CBRD-24094 디렉터리 검사) 는 디렉터리 엔트리와 separator (디렉터리가 페이지를 고르는 기준 OID) 순서만 보고, 객체는 의도적으로 비교하지 않는다.
   - check 16 이 바로 vacuum 과 COMPACT 를 경합시키는 단계다 (라운드마다 150행 삭제 + 50ms 대기). JIRA AC 2 도 "`--check-btree-entries` 정합" 을 명시한다.
   - 제안: check 19 앞에서 `server stop -> vacuumdb -S -> server start` 후 `SHOW INDEX CAPACITY` 의 `Total_value` (MVCC 필터 없는 물리 객체 수, `btree_get_subtree_capacity`) = 34000 을 함께 판정. 비용 O(n), 프로브로 1-2초.
   - 프로브 (develop optdebug): `vacuumdb` 뒤 28000, kill -9 복구 뒤 28000, 경합 직후 34274 (vacuum 대기 객체 274개, count 는 이때도 34000) -> 강제 vacuum 뒤 34000.
   - 제안을 적용한 케이스: 19/19 OK x3, `total_value=34000` x3, 코어 0.

## JIRA -> TC

| 항목 | TC 상태 | 판정 |
|---|---|---|
| AC 2 전후 count, `--check-btree` rc=0, `--check-btree-entries` 정합 | count 와 `--check-btree` 는 유지, entries 는 check 5/19 에서 제외 | 부분 (2) |
| AC 4 kill -9 복구 후 checkdb rc=0 | check 5 (entries 제외). 복구 시점에는 vacuum 대기 객체가 없어 count 로 충분 (프로브 28000) | 충족 |
| 그 외 AC | 이번 delta 와 무관, #4394 리뷰 판정 그대로 | - |

TC 파일 검토 (tc-author shell 규칙, delta 만): 새 옵션 5개는 기본 checkdb 비트 (`CHECKDB_ALL_CHECK_EXCEPT_PREV_LINK`) 에서 `CHECKDB_LC_CHECK_ALLENTRIES_OF_ALLBTREES` 하나만 뺀 것과 같다 (`server_interface.h`, `util_cs.c`). O(n^2) 설명도 맞다: `btree_keyoid_checkscan_check` 는 힙 행마다 그 키의 처음부터 `btree_keyval_search` 를 다시 돈다. 시간 검사 없음, 결과 줄 수 변화 없음 (19).

판정: 머지 가능 ((1) 은 작성자가 07:57Z develop merge 로 해소, 지금 MERGEABLE). (2) 는 회귀 검출력 문제로 머지를 막지 않는다.

## Runtime Verification

로컬 컨테이너 CTP (`just ctp shell <dir>`, `--testcases-as-is`, gha-ci optdebug 아카이브 develop `3d3e40b6e`, 5개 동시 실행):

| 실행 | TC | 결과 | 시간 |
|---|---|---|---|
| PR head x3 | `d38cd7395` | 19/19 OK x3 | 83.7 / 84.8 / 84.1초 |
| 프로브 (리뷰 전용, 커밋 안 함) | `d38cd7395` + `Total_value`, 시간 측정 줄 | 26/26 OK, 값은 Finding 2 | 85초 (checkdb -C 0초, -S 1초, 경합 50초) |
| 제안 적용본 x3 (리뷰 전용, 커밋 안 함) | `d38cd7395` + Finding 2 의 check 19 | 19/19 OK x3, `total_value=34000` x3 | 63.1 / 62.9 / 63.4초 (3개 동시) |
| 수정 전 (#4394 머지본) | `21811efe3` (= `2483c0803`) | NOK timeout, CTP 재실행 포함 2회 모두. check 5 의 `checkdb -C` (entries 포함) 가 약 700초 동안 끝나지 않아 시간 제한에 걸림 -> 5-19 NOK, 코어 0 | 727초 x2 (로컬 shell 시간 제한 720초) |

- 로컬 CTP 의 shell 케이스 시간 제한은 `shell_runtime.conf` 의 `testcase_timeout_in_secs=720` 이다 (CI 는 1200초). PR 버전의 두 checkdb 는 각 0.1초, 0.3초였다 (`cubrid_utility.log`).
- gha-ci: CI 전용 draft PR CUBRID/cubrid#8163 (develop `3d3e40b6e` + 빈 커밋 `b44ab8631`), `tc/pr-8163` `e4f5426fb` (PR head 의 케이스 그대로, `split.meta` 의 `tc_sha` 로 확인), `/run shell` run 38522391016. shard 00 에서 19/19 OK, 42.1초 (`feedback.log`), shard 00 46/46 OK. 머지 뒤 이 케이스는 CI 30회 중 13회 1200초 초과, 단독 재실행 907초였다. 나머지 shard 는 이 케이스와 무관해 기다리지 않았다.
- 증거: `.git_ignored_dir/scratch/pr4431/runtime/`.

## 참고 (PR 범위 밖)

- `btree_keyoid_checkscan_check` 는 CBRD-24094 이후 체인이 OID 정렬 + 디렉터리 구조인데도 행마다 키를 선형으로 훑는다. 그래서 중복이 수십만인 키가 있는 운영 DB 에서는 기본 `checkdb` 가 사실상 끝나지 않는다. 이 PR 이전부터 있던 문제다. JIRA 등록 여부는 별도 결정.
