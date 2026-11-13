# PR #8436 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8436](https://github.com/CUBRID/cubrid/pull/8436)
**제목:** [CBRD-27959] Clear only the lists of the block itself after each row, not those of its next
**작성자:** soheejung-cs
**HEAD SHA:** `1e5fcd7ca` (develop merge-base `38c931e7d`)
**JIRA:** CBRD-27959 (Correct Error, Confirmed) / 연관: CBRD-26104(병렬 부질의 도입), CBRD-27823(같은 기능의 다른 결함: 큐 닫힘 뒤 job 대기, 이 PR과 무관), CBRD-27932
**TC PR:** cubrid-testcases-private-ex#4775 (`tc/pr-8436` `ecad9fab`) / cubrid-testcases#4070 (빈 draft)
**리뷰 일시:** 2026-11-11
**리뷰 결정:** 엔진 Approve(인라인 없음), TC #4775 Approve + 머리말 원인 설명 제안 코멘트 1건, #4070 리뷰 없음

> **TL;DR** (Non-blocking): 엔진 수정은 맞습니다. 행마다 부르는 `qexec_clear_all_lists` 가 블록의 `next`(집합 연산의 다음 갈래)를 더 이상 훑지 않아, 병렬로 도는 다른 갈래의 부질의 리스트를 지우던 경로가 사라집니다. develop debug 빌드에서 코어가 나는 TC가 head debug·release 에서 통과하고, TLA+ 모델은 develop 동작을 UAF로 잡고 head는 통과합니다. TC 머리말의 원인 설명만 엔진 PR과 어긋납니다.

## Summary

- **변경 요약**: `qexec_clear_all_lists ()` 가 넘겨받은 블록 하나와 그 아래(bptr·fptr 원소, dptr 목록, scan 블록)만 지우고 `next` 는 훑지 않음
- **주요 이슈**: 없음 (엔진). TC 머리말의 Issue 설명이 엔진 PR이 증상이라고 밝힌 `qmgr_free_list_temp_file` 잠금 없는 확인을 원인으로 적음
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)
- TC `shell/_06_issues/_26_2h/cbrd_27959/cases/cbrd_27959.sh` DESCRIPTION — "the code that drops one looked at the entry's list of temporary files without its lock" 는 엔진 PR 본문이 증상이라고 정리한 자리(`qmgr_free_list_temp_file`)이고, 실제 원인은 첫 갈래의 행마다 `qexec_clear_all_lists` 가 `next`(둘째 갈래)의 부질의 리스트까지 지운 것. 머리말을 엔진 PR의 원인으로 맞추는 편이 TC를 나중에 읽는 사람에게 맞음.

## JIRA -> Engine PR

JIRA 첨부(`design.md`, `test.md`) 없음. Expected Result 와 본문의 원인 후보로 판정.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: SELECT 마다 12행, 서버 생존 (debug 1세션, release 4세션 x 150) | TC 검사 2·3·4. 로컬: develop debug FAILED + 코어 1, head debug·release PASS | 충족 |
| 원인 후보(본문): `qmgr_free_list_temp_file` 의 잠금 없는 목록 확인 | PR 본문이 증상으로 정리하고 그대로 둠: 원인(다음 갈래 리스트 해제)이 사라지면 그 자리로 가지 않음. TLA+ `mutant-develop` 이 같은 이중 해제·UAF 를 재현 | 충족 |
| `NO_PARALLEL_SUBQUERY` 대조, SA 모드 무관 | TC 검사 1; TLA+ `serial-develop` 통과(직렬이면 develop 도 무해) | 충족 |

CBRD-27823(UNION 뷰 스칼라 부질의 hang)은 job 큐 닫힘 결함으로 다른 원인이며 이 PR이 해결하지 않음.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 대조(`NO_PARALLEL_SUBQUERY`) 12행 | #4775 검사 1 | 통과 |
| 한 세션 실행 12행, 서버 응답 | #4775 검사 2 | 통과 |
| 4세션 x 150번 동시 실행 매번 12행 | #4775 검사 3 | 통과 |
| 서버 pid 유지 | #4775 검사 4 | 통과 |

#4775 는 새 shell 케이스 1개, `write_ok/nok` 판정과 정리 경로를 갖춤. 본문 판정(develop debug NOK, head OK)은 로컬 실행과 일치. #4070 은 변경 없는 빈 draft.
판정: Approve (머리말 원인 설명은 Non-blocking).

## TLA+ Verification

TLA+ 검증: 통과 — `.claude/review/PR-8436/tla/px-clear-lists`
- 속성: C1 safety(갈래의 IN 검사는 그 행에 만든 리스트만 읽음, UAF 없음) TLC 통과, IndInv 귀납성 Apalache (JIRA Expected, PR Purpose) / C2 safety(이중 해제 없음) 통과 (PR Purpose) / C3 safety(행 정리 뒤 갈래의 부질의 리스트 없음) 통과 (`qexec_clear_all_lists` 주석) / C4 safety(질의 끝에 임시 파일 없음) 통과 / C5 liveness(질의 종료) 통과 / TLAPS 요청 없음
- 결함: 없음
- mutant: 5개 모두 위반 검출 (`develop` -> NoUseAfterFree, `row-keep-id` -> NoDoubleFree, `no-own-clear` -> RowClean, `trunc-no-free` -> NoLeak, `no-final` -> liveness). `serial-develop` 통과: develop 의 `next` 훑기는 갈래를 차례로 돌 때 무해
- 경계: 갈래 2, 바깥 행 2, 행당 부질의 실행 2, 임시 파일 3(재사용), 병렬/직렬; scale 갈래 3·파일 4(869,991 상태); Apalache 는 갈래 2·파일 3, 행·실행 1..3 전 범위
- trace validation: 수용 3건(병렬 2: 서로 다른 interleaving, 직렬 1), 거부 2건(첫 갈래의 행 정리가 둘째 갈래 리스트를 해제하는 develop 패턴, truncate 해제 1건 누락). 계측 빌드 1e5fcd7ca, optdebug, CS, `;trace on` 에서 `parallel workers: 2`
- 반례: head 변형 반례 없음. 병렬 run 에서 보인 다른 스레드의 해제는 backtrace 로 `qexec_execute_query -> qexec_clear_xasl` 최종 정리임을 확인(모든 갈래 종료 후)
- `RESULT: OK` (17 cfg, run `px-clear-lists-20261111-150719-1654639`)

## Runtime Verification

- CI 빌드 tarball(optdebug "debug" slot, release), testcase `tc/pr-8436` `ecad9fab`, `just ctp shell _06_issues/_26_2h/cbrd_27959`:
  - develop `38c931e7d` debug: FAILED, 코어 1개(`core.parallel-query...`) — fail-before
  - head `1e5fcd7ca` debug: PASSED 1/1 / release: PASSED 1/1 — pass-after
- gha-ci run 42949806625(11-11 `/run all`): build debug·release 통과, sql/medium/shell/cci 진행 중(리뷰 시점 결과 없음).
- 계측 optdebug 빌드(`~/optdebug/CUBRID-pr8436-tla`)로 JIRA 재현을 병렬 2회·직렬 1회 실행: 모두 12행, 코어 없음.
