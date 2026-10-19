# PR #4395 코드 리뷰 보고서 (3차, TC 단독, cubrid-tc-author 기준)

**PR:** [CUBRID/cubrid-testcases-private-ex#4395](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4395)
**제목:** [CBRD-24094] Add shell case for OID-ordered overflow chains with a separator directory
**작성자:** shparkcubrid / 리뷰 요청: kwonhoil, ssihil (그대로 둠, 리뷰어 추가 없음) / swi0110 Approve(6c4f418a9)
**HEAD SHA:** `dfad182c2` (직전 리뷰 `54923e2c0`, base develop `100ee8830`, MERGEABLE/CLEAN), 파일 1개 `shell/_40_guava/cbrd_24094/cases/cbrd_24094.sh` (+413)
**JIRA:** CBRD-24094 (Improve Function/Performance, Resolved) / 엔진 PR CUBRID/cubrid#7447 머지 `10a1df3e6`
**리뷰 일시:** 2026-10-14 (직전: 10-12 Comment 5488526195, 10-13 Request changes 5498617852, 작성자 수정 10-13 14:09 KST)
**리뷰 결정:** #4395 Approve 게시 (review 5511637271, 2026-10-14 09:24 KST, `dfad182c2`). top-level 본문만, 인라인 없음. 기존 스레드 답글/resolve 없음. 리뷰어 추가 없음. tc-author 규칙 차이(헤더 길이, positive control, pid/core 탐지기)와 check 9 비결정성은 게시하지 않음.

> **TL;DR** (Non-blocking): 10/13 변경 요청 두 건(check 18 `checkdb -C --check-btree`, 헤더 Check 20 번호)이 요청한 그대로 반영됐다. head `dfad182c2`가 develop optdebug에서 3/3 23줄 OK(32-33초), 수정 전 `059a7f83b`에서 check 21이 6/6 NOK다. 새 지적 없음, 승인 가능.

## Summary

- **변경 요약 (직전 리뷰 이후)**: `cbrd_24094.sh` 343행 `cubrid checkdb -C $db` -> `cubrid checkdb -C --check-btree $db`, 헤더 47행 "Check 21" -> "Check 20", 헤더 75행 check 18 설명에 `--check-btree` 추가. 3줄 변경, 그 외 동일.
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

## 직전 리뷰(10/13) 반영 확인

| # | 직전 지적 | 반영 (`dfad182c2`) | 판정 |
|---|---|---|---|
| 1 | Blocking: check 18 옵션 없는 `checkdb -C`가 entries 검사(`CHECKDB_ALL_CHECK_EXCEPT_PREV_LINK`)까지 돌아 optdebug에서 720초 초과 | 제안한 suggestion 그대로 `-C --check-btree`. 헤더 18번 설명도 맞춤. 작성자 답변에서 `util_cs.c` 동작 확인 | 해소. develop 3/3 check 18 OK, 케이스 32-33초 |
| 2 | NIT: 헤더 47행 전제 검사 번호 | "Check 20" | 해소 |

## TC PRs

시나리오 목록은 직전 리뷰와 같다. 직전 리뷰에서 Finding 1 때문에 "부분"이던 두 행만 바뀌었다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| AC DELETE/INSERT 시간 평탄화 | 성능, TC 범위 밖. JIRA 코멘트(focusedCommentId=4776859) | 제외 |
| AC 인덱스 스캔 == 순차 스캔 | 2~5, 7, 10, 12, 13, 15, 16, 22 | 통과 |
| AC 롤백 후 일치 | 9, 21 | 통과 |
| AC crash recovery 후 일치 | 18: `kill -9` -> 재기동 -> `checkdb -C --check-btree` rc 0, ts/tl idx = heap | 통과 (직전 부분) |
| AC checkdb 디렉터리 검증 | 6, 11, 14, 17, 18, 23 | 통과 |
| AC 유니크 인덱스 동작 무변화 | 17 | 통과 |
| 첨부 `_1` 로더 체인 / `_2` 런타임 성장-해체-재성장 / `_4` 키 UPDATE 이동 | 12~14 / 3~11 / 15~16 | 통과 |
| head catch-all -407 (`5be8a1730`) | 19~22. 수정 전 빌드 check 21 6/6 NOK, 전제 check 20 6/6 성립 | 통과 (직전 부분) |

판정: 통과. 승인.

TC 파일 검토 (cubrid-tc-author `shell-rules.md` 체크리스트):
- `bash -n` 통과. CTP 예약 변수(`result_file`, `case_no`, `pids` 등) 대입 없음. 시간 비교 체크 없음(rule 23). 하드코딩 경로 없음.
- 결과 줄 수 = 헤더 체크 수 = 23. 이번 변경은 실행 코드 한 줄이라 판정 구조 변화 없음.
- 헤더 길이(80줄, rule 1의 40줄 초과), 체크 1번 positive control 부재, pid/core 탐지기(rule 12) 부재는 1차 NIT 답변으로 수용했거나 이 케이스에 맞지 않아(오라클이 건수 일치 + checkdb, 서버 크래시는 다음 체크의 연결 실패로 드러남) 이번에 다시 꺼내지 않는다.

## Runtime Verification

모두 optdebug, `just ctp shell _40_guava/cbrd_24094` 컨테이너(cubridci `79a344fc`, ctp `db90747`), `--testcases-as-is` = TC worktree `pr4395` @ `dfad182c2`, `NO_ABORT_ON_CORE=1`, CTP 재시도 1회. Sonnet 워커(Workflow `wf_03ed120d-b86`)가 실행, 리드가 `.result`/provenance/backtrace를 직접 대조.
- **develop**: `fd540db0c` (11.5.0.2660-fd540db) gha-ci optdebug 아카이브. 최신 develop `8f57aa0d7`까지 13커밋 중 btree/heap/vacuum/recovery/checkdb 경로 변경 없음(`cc49a25db`의 `util_cs.c`는 tranlist/killtran/tde/flashback 로그인 메시지뿐).
- **수정 전**: `059a7f83b` (11.5.0.2313-059a7f8) 로컬 optdebug.

| 테스트케이스 | 빌드 | 결과 |
|---|---|---|
| PR head `dfad182c2` | develop x3 | 3/3 PASSED 23/23, 32-33초, core 0, 재시도 없음. check 18 `checkdb -C --check-btree` rc 0, error 0줄. `Num_distinct_key` 11 (8, 14), n_low 2400 (20) |
| PR head `dfad182c2` | 059a7f83b x3 (각 2회 실행) | check 21 6/6 NOK: `btree_mvcc_delete` -> `btree_key_find_and_insert_delete_mvccid` `btree.c:31087` assert(unknown key) core 6개. check 20 6/6 성립. check 22는 21 크래시의 연쇄 NOK. check 9는 1/6만 NOK(insert undo `btree.c:33178`, 비결정적, 직전과 같음). 실행당 34-35초 |

- 직전 리뷰의 "head + `--check-btree`" 로컬 수정 실행(develop 3/3, 059a7f83b 6/6)과 결과가 같다. 이번은 PR head 그대로의 실행이다.
- 실행하지 않은 것: release 빌드(작성자 주장 23/23, 28초), gha-ci(1차 grill에서 로컬 검증만 하기로 정함).
- 증거 보관: run dir 6개와 core 7개는 판독 후 삭제(2026-10-14). `.result`, `test_local.log`, err 로그, backtrace는 `.git_ignored_dir/scratch/pr4395/final/lane-{dev,pre}/ev-*/`, core 요약은 `scratch/pr4395/cores-analyzed.txt`.

## Existing Comments

작성자가 10/13 두 스레드(4254553824 check 18, 4254553837 헤더 번호)에 "반영했습니다"로 답했다. 미답 top-level 코멘트 없음.
