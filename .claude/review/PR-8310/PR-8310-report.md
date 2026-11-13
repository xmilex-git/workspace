# PR #8310 Review: [CBRD-27802] Drop the first-row copy in hash GROUP BY

- PR: https://github.com/CUBRID/cubrid/pull/8310 (draft, xmilex-git, head `f3d6c353a`, base develop `3ca42d9a7`)
- JIRA: CBRD-27802
- 리뷰 결정: GitHub 게시 없음. 사용자 지시로 결과는 5번 세션(작성 세션)에 전달.

> **TL;DR** (Non-blocking) 코드에서 결함을 찾지 못했다. 다만 rebased head `f3d6c353a`는 빌드, smoke, CTP를 한 번도 거치지 않았다. TC PR 두 개도 비어 있다. ready 전환 전에 게이트와 TC가 남아 있다.

## Summary

- 판정 로직(`pt_gby_reads_row`)은 증명하지 못한 참조를 모두 KEEP으로 보낸다. LIMIT은 HAVING의 `GROUPBY_NUM()`으로 바뀌어 KEEP이 된다.
- 실행기의 세 출력 경로(hash만, partial만, 행과 partial 병합)와 병렬 워커 경로를 따라갔다. 누락, 이중 출력, 키 순서 역전이 생기는 경로는 찾지 못했다.
- 타입 키 smoke(아래 Runtime Verification)에서 fix hash, fix NO_HASH, develop hash의 결과가 모두 같았다.
- 남은 것: rebased head 게이트, TC 작성, design.md 한 줄 갱신.

## Findings

### Non-blocking (should consider)

1. **rebased head 검증 없음.** `f3d6c353a`(16:55 rebase)로 만든 install이 없다. `~/optdebug/CUBRID-gby-nft`는 `1a00ba4d2`, `~/release/CUBRID-gby-nft`는 `fbe907ff7`이다. 15:58에 시작한 sql CTP(`~/ctp-run-out/workspace/sql-20261028T065814Z-3050632`, `1a00ba4d2` install)는 timing.txt 없이 끊겼고, 끝난 CTP는 없다. gha-ci `/run`도 돌리지 않았다. 그래서 CBRD-27684(#8200, 정렬 레코드에 튜플 싣기)와 함께 동작하는지는 아무도 확인하지 않았다.
2. **TC PR이 비어 있다.** cubrid-testcases #3917과 private-ex #4603은 봇 초기 상태 그대로다. TC Merge Gate도 "no TC branch"라고 적었다. test.md의 T1-T7에 TC가 하나도 없다. 회귀가 다시 생겨도 CI가 잡지 못한다. 회귀 예: 병렬 워커만 집계했을 때 0행, `sum_acc`(word sum 누산기)가 다음 그룹으로 새는 것.
3. **design.md 4번 항목이 rebase 전 기준이다.** design.md에는 "partial 정렬 레코드가 원본 위치만 들고 있어(use_original) 엔트리마다 페이지를 fix"라고 적혀 있다. CBRD-27684 뒤에는 `qfile_build_sort_rec`이 표본을 보고 튜플을 실을지 정한다(`carry_tuple`). 그래서 페이지 재사용은 싣지 않기로 한 정렬에만 걸린다. PR 본문은 이미 그렇게 적었으니 첨부 design.md도 맞춰야 한다. Q18의 4번 항목 효과도 27684 위에서 다시 재지 않았다(PR Remarks에 밝힘).

### Questions

4. PR 본문과 design.md는 hash를 거치지 않는 행으로 "SET 값 행(`RETRY_SET_TYPE`)"을 든다. smoke의 `SELECT k, COUNT(s), SUM(v) FROM ts GROUP BY k`(s는 `SET(INT)`)는 trace가 `hash: false`였다. 사본 없는(NONE) GROUP BY가 SET 값 행을 받는 SQL이 실제로 있는가? 있으면 test.md에 넣고, 없으면 그 예를 본문에서 빼도 되지 않는가.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| ER: 결과의 행과 값이 develop/NO_HASH와 같음 | 작성자 smoke p1-p3(`1a00ba4d2`), 이번 타입 키 smoke(`1a00ba4d2` optdebug) 일치. rebased head 미검증 | 부분 (1) |
| ER: Q18 GROUPBY 단축 | develop 23.9 s -> 14.5 s(2d925cb86 base, release SF10). 27684 위 재측정 없음 | 부분 (1, 3) |
| 설계: `g_first_tuple` NONE/KEEP/OUTPUT, 스트림 모양 유지 | `xasl.h`, `xasl_to_stream.c`, `stream_to_xasl.c` 한 칸 int | 충족 |
| 설계: 클라이언트 판정 `pt_gby_reads_row`, `pt_find_group_key_expr` 분리 | 구현됨. `pt_make_result_ref` 동작 동일 | 충족 |
| 설계: 첫 행도 누산기에 넣음 | `qexec_hash_gby_agg_tuple` NONE 분기 | 충족 |
| 설계: partial만으로 그룹 출력, 키 슬롯 빌림/반환, `sum_acc` 끄기 | `qexec_gby_put_partial_group` | 충족 |
| 설계: 병합 경로에서 partial만 있는 그룹 출력(`part_taken`) | `qexec_locate_agg_hentry_in_list`, 정렬 뒤 남은 partial 루프 | 충족 |
| 설계: 빈 입력 판정에 partial list 포함 | `qexec_groupby` 빠른 종료 조건 | 충족 |
| 설계: partial 페이지 재사용 | `part_page`/`part_vpid`, 정렬 성공/실패 모두 해제 | 충족 (설명은 3) |
| 미정 항목 | design.md에 없음 | - |

연관 이슈 CBRD-27787(partial put을 워커에 분배)은 이 PR과 별개다. 그 작업이 들어오면 `part_page`를 워커마다 따로 둬야 한다(PR Remarks에 밝힘).

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| T1 많은 그룹이 표 밖으로 나감 | test.md | test.md에만 있음 |
| T2 다중/내림차순/식 키 | test.md | test.md에만 있음 |
| T3 첫 행 사본 유지 형태 | test.md | test.md에만 있음 |
| T4 NULL 키 | test.md | test.md에만 있음 |
| T5 해시 포기 뒤 행 + partial 병합 | test.md | test.md에만 있음 |
| T6 한 페이지 넘는 행 | test.md | test.md에만 있음 |
| T7 병렬 스캔 | test.md | test.md에만 있음 |

cubrid-testcases #3917, private-ex #4603: 변경 파일 없음(draft). 검토할 case/answer가 없다.

## Runtime Verification

| 출처 | build | 내용 | 결과 |
|---|---|---|---|
| 이번 리뷰 smoke (CS, port 1711, 반납) | optdebug `1a00ba4d2` vs optdebug develop `2d925cb86` | 12만 그룹, 36만 행. CHAR, `utf8_en_ci` VARCHAR(대소문자 변형 3종), ENUM+INT, NUMERIC(10,3), DATETIMETZ, BIT VARYING, 식 키, LIMIT 30, PARALLEL(4) ci 키(`hash: partial`, 행 병합 경로) | fix hash = fix NO_HASH = develop hash, 11개 블록 중 차이 0(정렬 전후 모두). assert/core 없음 |
| 작성자 smoke | optdebug `1a00ba4d2` | 29개 case x p1-p3 | develop과 같음. 22행은 DOUBLE 누산 순서 차이(develop에도 있음) |
| CTP | - | 끝난 run 없음 | 미검증 |
| gha-ci | - | `/run` 없음. license/code-style/cppcheck 통과 | 미검증 |

smoke 스크립트: `.git_ignored_dir/scratch/pr8310/smoke/run.sh <install> <tag>` (rebased head install에서 다시 돌릴 수 있음).

Not checked: rebased head(`f3d6c353a`)의 빌드, smoke, CTP. 27684와 함께 쓸 때 Q18 성능.
