# PR #8056 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8056](https://github.com/CUBRID/cubrid/pull/8056)
**제목:** [CBRD-27515] Reuse a hash join result when it needs no rewriting for the query result layout
**작성자:** youngjinj
**HEAD SHA:** `37cc1a838` (develop merge-base `ef2c78cda`)
**JIRA:** CBRD-27515 (Sub-task, Open) / 연관: CBRD-23836 (parent)
**TC PR:** CUBRID/cubrid-testcases#3608 (`tc/pr-8056` `1849a51a7`) / CUBRID/cubrid-testcases-private-ex#4278 (`08a46bddb`)
**리뷰 일시:** 2026-11-04
**리뷰 결정:** 엔진 PR Approve (inline 1, 비트 질문) / TC #3608 Approve / TC #4278 Approve

> **TL;DR** (Non-blocking): 결과를 바꾸는 결함은 찾지 못했습니다. gha-ci(debug) sql·medium·shell 이 헤드에서 모두 통과했고, 로컬 CS 모드 프로브 12문장도 develop 과 결과 행이 같습니다. 남은 것은 #8364 와 같은 XASL 플래그 비트를 쓰는 문제 하나입니다.

## Summary

- **변경 요약**: 해시 조인(`HASHJOIN_PROC`)이 위 결과 노드(`BUILDLIST_PROC`)의 출력 목록으로 직접 기록하고, 결과 노드는 리스트 스캔 없이 해시 조인의 `list_id`(`QFILE_LIST_ID`, 리스트 파일 식별자)를 넘겨받는다(pass through).
- **주요 이슈**: 없음
- **확인 필요 사항**: `XASL_PASS_THROUGH_WRAPPER (0x1 << 29)` 가 #8364 의 `XASL_OUTPUT_READS_SCAN` 과 같은 비트.

---

## Findings

### Questions for the author

- `src/query/xasl.h:591` — `XASL_PASS_THROUGH_WRAPPER (0x1 << 29)` 는 열려 있는 #8364(CBRD-27870)의 `XASL_OUTPUT_READS_SCAN (0x1 << 29)` 과 같은 비트다. 두 줄이 같은 자리에 들어가므로 뒤에 머지하는 쪽은 텍스트 충돌로 알 수 있지만, 해결하며 둘 다 29 로 남기면 BUILDLIST 의 pass through 표시가 BUILDVALUE 쪽 판정과 섞인다. 뒤 PR 이 `0x1 << 30` 을 쓰면 `flag`(int)에 남는 비트는 없다.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC-1.1 컬럼 순서·중복·조인 키 | TC-1-01, CI OK | 충족 |
| AC-1.2 수식(두 입력 산술, 정규식, 호스트 변수) | TC-1-02, CI OK, 로컬 SA 에서 `?` 바인드 PREPARE 3회 실행이 develop 과 같음 | 충족 |
| AC-1.3 버려지는 행의 수식은 계산 안 함 | TC-1-03 | 충족 |
| AC-1.4 상위 해시 조인 키 수식 | TC-1-04, shell TC-1-08 | 충족 |
| AC-1.5 리스트 스캔 없음(readrows 0) | 모든 sub-case 의 `temp_scans`/`pass_through` 카운트 | 충족 |
| AC-1.6 외부·SEMI·ANTI | TC-1-05, shell TC-1-06 | 충족 |
| AC-1.7 비 PARALLEL_ENABLE SP 는 직렬에서만 | TC-1-07, shell TC-1-08 (병렬 6건 no pass through) | 충족 |
| AC-2.1 / 2.2 pass through 하지 않는 질의 | TC-2-01, TC-2-02 | 충족 |
| AC-3.1 병렬·파티션 | shell TC-3-01 (1,000,000행 행 수·열 합) | 충족 |
| AC-3.2 빈 입력·UNION·파생·스칼라 서브질의 | TC-3-02, 로컬 P1~P3 | 충족 |
| AC-3.3 XASL 캐시 복제본 재실행 | TC-3-03 | 충족 |
| AC-3.4 재귀 CTE | TC-3-04, shell TC-3-01-09 | 충족 |
| AC-4.1 trace 노드 구성 | TC-4-01 | 충족 |
| 함께 고친 spawner 누락(`bound_conversion`, `compare_each`) | `xasl_spawner.cpp` 두 줄 | 충족 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| TC-1-01~05, 1-07 (pass through 하는 질의) | #3608 cases 1_01~1_07 | 통과 |
| TC-1-06, 1-08, 3-01 (병렬·파티션·SP) | #4278 `cbrd_27515.sh` | 통과 |
| TC-2-01, 2-02 (하지 않는 질의) | #3608 2_01, 2_02 | 통과 |
| TC-3-02~04, 4-01 | #3608 3_02~4_01 | 통과 |

- 12개 case 모두 answer 가 있다. pass through 여부는 develop 에서 답이 갈리는 `temp_scans`/`pass_through` 카운트로 확인해, 결과 행만으로는 develop 에서도 통과하는 TC 의 약점을 막았다.
- `cbrd_27685.answer` 의 `groups (est.)` 5줄은 TC develop 의 #4010 과 같은 내용이라 머지 충돌이 없다.

## Runtime Verification

- CI gha-ci run 41589533398 (head `37cc1a838`, debug, `tc/pr-8056` `68bfddb77` / private-ex `7a914454b`): sql 17724·medium 975·shell 3536 모두 OK.
- 로컬 CTP (CS 모드, CI debug tarball head `37cc1a838`): CI 뒤에 TC head 가 바뀌어(public 9커밋, private-ex 6커밋) 현재 head 로 다시 돌림. `just ctp sql _36_guava/cbrd_27515` (`tc/pr-8056` `1849a51a7`) 12/12 OK, `just ctp shell _40_guava/cbrd_27515` (`08a46bddb`) OK, core 0.
- 로컬 review-only CTP (CS 모드, 새 서버, CI debug tarball head `37cc1a838` vs develop `ef2c78cda`, `TC_REF=develop` + adhoc case 12문장): 결과 행 12/12 같음, 다른 줄 10줄은 모두 `pass_through` 카운트. head 에서 pass through 가 실제로 일어난 문장: 상관 파생 테이블(외부 행마다 재실행), UNION ALL, UNION, CTE 두 번 읽기, 3-way 조인 — assert·core 없음.
- 로컬 SA (같은 두 tarball): 같은 프로브에 `?` 바인드 PREPARE/EXECUTE 3회를 더한 스크립트의 출력이 develop 과 0줄 다름(시간 줄 제외)(SA 는 trace 를 켤 수 없어 pass through 여부는 CS 실행으로 봄).
- 확인하지 않은 것: release 빌드 실행(CI 는 debug 만 테스트), develop 최신 `d0a3384f9`(#8242, 조인 비용 변경) 위의 계획 변화.
