# PR #4511 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4511](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4511)
**제목:** [CBRD-27071] Add shell testcase for loaddb --no-logging-index builds
**작성자:** xmilex-git
**HEAD SHA:** `5ac2690` (private-ex develop `c9c2bb42c` 대비 26 커밋 뒤, 충돌 없음)
**JIRA:** CBRD-27071 (Improve, Resolved) / 연관: CBRD-27298 (Develop, 엔진 PR #8119 승인·미머지), CBRD-27592 (머지), CBRD-27516 (머지)
**TC PR:** TC 전용 PR. 엔진 PR #7504는 2026-08-05 develop `1aa79a03b`로 머지됨
**리뷰 일시:** 2026-10-26
**리뷰 결정:** shapes 18 수정(`4c18f6ad0`) 후 squash 머지 `88bec5cd8` (2026-10-26). #8119 쪽 restore 5번은 #8119가 대응.

> **TL;DR** (Blocking): 최신 develop `4781495f0` optdebug에서 `cbrd_27071_shapes` 18번 검사가 2회 모두 NOK. `log_btree_operations=yes`가 남긴 디버그 로그가 `error_log_size`(기본 512M)를 넘겨 `.err`가 순환되고, `px_builds`가 새 `.err`만 세어 0을 읽음. 나머지 54개 검사와 build, crash, restore는 통과.

## Summary

- **변경 요약**: `shell/_40_guava/cbrd_27071/` 아래 셸 TC 4개(build 19, shapes 22, crash 6, restore 8 = 55 검사)를 추가
- **주요 이슈**: shapes 18 로그 순환 NOK (Blocking), #8119(CBRD-27298)가 머지되면 restore 5번 `level1_replay_refused`의 기대가 뒤집힘
- **확인 필요 사항**: #8119와의 머지 순서, test.md T12 제외 근거

---

## Findings

### Blocking (must fix)
- `cbrd_27071_shapes.sh` `change_db_parameter "log_btree_operations=yes"` (case 1 직후) -> 이후 모든 빌드가 행마다 `DEBUG_BTREE: load sort found oid / load new object / load added object`를 남김(약 231만 줄, 546,406,560 bytes). 기본 `error_log_size` 512M를 넘는 지점이 dup_last 빌드 도중이라 `.err`가 `.err.bak`으로 넘어가고, `px_builds` (`grep -c "DEBUG_BTREE: px construct" ${dbname}_latest.err`)가 0을 읽어 `$2 == $1 + 1`이 깨짐. 상태 줄 `17 0 52 52 0 30001 1`, 나머지 조건은 모두 충족. 로그 양이 512M 근처라 빌드마다 통과/실패가 갈림(작성자 run `0b3a295b2`는 통과).

### Non-blocking (should consider)
- `cbrd_27071_restore.sh` 5번 검사 — 레벨0 -> loaddb -> 레벨1 체인의 복원 거부를 기대함. #8119 본문 "동작 변화" 표는 같은 체인을 "거부 -> 통과"로 바꿈. #8119 머지 후 이 검사는 NOK. DESCRIPTION의 "A full backup taken after loaddb forces a checkpoint" 문장도 #8119가 강제 체크포인트를 지우면서 틀린 설명이 됨.

### Questions for the author
- test.md T12(splitter 키 순서 편중, 400만 행 ordered/random 시간 비율)를 뺀 근거가 "CBRD-27592 3M행 TC와 중복"인데, 그 TC는 시간 비율을 재지 않음. test.md 결함 (d)는 이 PR로 잡히지 않음.
- test.md T7은 "빌드 도중 kill -9"인데 crash 1-2번은 "빌드 완료, 커밋 전" kill. 부분 빌드된 shard 파일의 undo 경로는 다루지 않음.

## JIRA -> TC

| 시나리오 (test.md) | TC 근거 | 판정 |
|---|---|---|
| T0 hidden 옵션 | build 14 | 충족 |
| T1 발화 | build 1, 2 (t는 checkdb 대신 인덱스 = 풀 스캔 비교) | 충족 |
| T2 compat | build 3, 13 | 충족 |
| T3/T4 옵션 없음, csql | build 4, 5 (+ online 6) | 충족 |
| T5 SA | build 7 | 충족 |
| T6 강등 | build 8-10, 15 | 충족 |
| T7 빌드 도중 kill | crash 1-2 (커밋 전 kill) | 부분 |
| T8 완료 후 kill | crash 3-5 | 충족 |
| T9 이후 백업 복원 | restore 2 (checkdb 없음) | 충족 |
| T10 이전 백업 거부 en/ko | restore 3-6 | 충족 |
| T11 시점 복원 | restore 7 | 충족 |
| T12 splitter 성능 회귀 | 없음 (본문에서 제외 명시) | 미충족 |
| CBRD-27592 중복 PK 3위치 / CBRD-27516 DESC FK | shapes 16-20 | 충족 |

## Runtime Verification

- 로컬: optdebug develop `4781495f0` (11.5.0.2747-4781495, libcubrid.so sha256 `c500b5c0…`), TC `2f67b5a5e` (private-ex develop `c9c2bb42c` + PR head `5ac2690` merge), `just ctp shell _40_guava/cbrd_27071`, run `shell-20261026T085122Z-4191029`. build 19/19 OK (65 s), crash 6/6 (26 s), restore 8/8 (52 s), shapes 21 OK / 1 NOK (18번, 재시도 동일), core 0개.
- CI: draft PR CUBRID/cubrid#8272 (빈 커밋, develop `4781495f0`), `tc/pr-8272` `cee2dba0d` (PR 파일과 diff 동일), 1차 run 40294979779(TC `5ac2690`): cbrd_27071 55/55 OK, 무관 실패 `_enhance_1006`. 2차 run 40310328192(TC `4c18f6ad0`): 55/55 OK, 무관 실패 `_enhance_10010` -> `/run rerun` 40315975030 pass.
