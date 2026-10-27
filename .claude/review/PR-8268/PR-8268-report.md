# PR #8268 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8268](https://github.com/CUBRID/cubrid/pull/8268)
**제목:** [CBRD-27775] Use the build side to calculate the hash join partition count and create temp files without a memory buffer for lists that do not use one
**작성자:** youngjinj
**HEAD SHA:** `0b8b83377` (develop merge-base `4781495f0`)
**JIRA:** CBRD-27775 (Sub-task, Confirmed, 부모 CBRD-23836) / 연관: 없음
**TC PR:** CUBRID/cubrid-testcases#3873 (`tc/pr-8268` `7f26b3a0c`) / CUBRID/cubrid-testcases-private-ex#4561 (`tc/pr-8268` `63d9b88df`)
**리뷰 일시:** 2026-10-27
**리뷰 결정:** 엔진 PR #8268 Approve (요약 한 문단) / TC PR cubrid-testcases#3873 Approve, cubrid-testcases-private-ex#4561 Approve (본문 없음)

> **TL;DR** (Non-blocking): 파티션 수 계산, 버퍼 없는 임시 파일 생성, 두 결함 수정 모두 코드와 실행 결과가 PR 설명과 맞는다. 머지를 막거나 고칠 지적은 없다.

## Summary

- **변경 요약**: 해시 조인 파티션 수를 빌드 입력(해시 테이블을 만드는 쪽 입력) 행 수로 계산하고, `QFILE_FLAG_NO_MEMBUF` 리스트는 처음부터 메모리 버퍼 없는 임시 파일로 만든다.
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

## JIRA -> Engine PR

JIRA 첨부(`design.md`, `test.md`, `test_result.md`)는 없다(티켓 Confirmed 상태). 행은 JIRA Implementation 과 A/C 에서 가져왔다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| A/C 1: 빌드 입력이 더 큰 LEFT/RIGHT OUTER, SEMI, ANTI 는 빌드 입력 기준 파티션, 결과는 NL 과 같음 | `hjoin_check_partition` 의 join type 분기가 `hjoin_init_context` 의 build 선택과 같다. 실행(아래 R1): head 는 SPLIT 3(SEMI 2) + `memory+skip`, base 는 SPLIT 없이 `file`. 결과 행은 NL 과 같음 | 충족 |
| A/C 2: `QFILE_FLAG_NO_MEMBUF` 사용 기능은 `temp_file_memory_size_in_pages` 와 관계없이 develop 과 같은 결과 | `TEMP_FILE_MEMBUF_NONE` 분기의 `membuf`/`membuf_npages`/`membuf_last` 값이 예전 사후 보정 값과 같다. CI sql/medium/shell 통과(기본값), R2(값 0)에서 결과 같음 | 충족 |
| A/C 3: prepare 한 해시 조인을 `max_hash_list_scan_size=0` 으로 바꾼 뒤 실행 | R1: head 는 SPLIT 없이 `method: file` 로 정상 실행, base debug 는 같은 `execute` 에서 cub_server 가 `__assert_fail` 로 중단 | 충족 |
| `hjoin_try_partition` 실패 경로: `context_cnt = 0`, `px_worker_stats` 해제 | 해제하지 않으면 SINGLE 폴백 뒤 `hjoin_try_parallel_probe` 가 `px_worker_stats` 를 덮어써 누수된다. 코드로 확인, 실패 주입 실행은 없음 | 충족 |
| `max_hash_list_scan_size` 한 번만 읽기 (`manager->mem_limit`) | `hjoin_init_manager` 에서 읽고 `hjoin_check_partition`, `hjoin_scan_init`(px 워커 포함)이 재사용 | 충족 |
| 디버그 매크로 6 개와 전용 코드 제거 | 남은 출력은 예전 `#else` 경로와 글자 단위로 같다 | 충족 |
| `QFILE_NOT_USE_MEMBUF` -> `QFILE_FLAG_NO_MEMBUF` | 옛 이름 잔여 없음 | 충족 |

판정: 충족.

## TC PRs

PR 본문에 검증 표가 없고 JIRA `test.md` 도 없어, 시나리오는 JIRA A/C 로 잡았다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| A/C 1 빌드 입력 기준 파티션 | #3873 `02_hash_join_mode`(SEMI/ANTI 빌드 입력), `join_orderby_skip`(LEFT OUTER), #4561 `cbrd_25846`(RIGHT OUTER 3 -> 5) | 통과 |
| A/C 2 `temp_file_memory_size_in_pages` 무관 | TC 없음. 서버 conf 파라미터라 sql TC 로 바꿀 수 없고, 기존 회귀(기본값)로 갈음 | 통과 (기존 회귀) |
| A/C 3 prepare 뒤 `max_hash_list_scan_size=0` 실행 | 두 TC PR 어디에도 없음. 리뷰 실행 R1 로 확인했고, TC 추가는 요청하지 않는다 | 미반영 (R1 로 갈음) |

TC 파일 검토: 바뀐 케이스 3 개 모두 답지가 같이 바뀌었고, 헤더 주석에 `;` 가 없다. #3873 본문의 설명(BUILD `file+skip -> hybrid+skip`, tb 150000 -> 125000 행)과 답지가 맞는다. `join_orderby_skip` Q116-Q119 의 ORDER BY 변화(R3): 워커별 topnsort 는 그대로 돈다. SORT(limit) 가 a 를 960 행으로 줄여 해시 조인 결과는 960 행인데, head 는 빌드 입력 b(100001 행) 기준으로 파티션이 398 개라 결과 리스트가 파티션마다 페이지를 가진다. 그래서 상위 SCAN 이 병렬 스캔(워커 4 개, 각 174-371 행, `topnsort: true`)이 되고, ORDERBY 는 워커 결과 6 페이지를 합치는 정렬(`sort: true`)로 찍힌다. base 는 파티션 5 개라 직렬 스캔 + `topnsort`. 결과 행은 같고 Q116 전체 시간은 head 177 ms, base 1079 ms.

판정: 승인. A/C 3 TC 는 없지만 요청하지 않는다.

## Runtime Verification

- CI(gha-ci run 40317787721, `/run all`): 엔진 `0b8b83377` debug(optdebug), TC `tc/pr-8268` (public `7f26b3a0c`), sql 17630 / medium 975 통과. shell 3492 중 `cbrd_25846` 1건 NOK(private `2986ebfa5`, TC 수정 전).
- CI 재실행(run 40367626861, `/run rerun 40317787721`): private `63d9b88df` 로 `cbrd_25846` 1/1 통과.
- R1 (리뷰 실행, C/S 모드 `fast-cs-csql.sh`): CI debug tarball head `0b8b83377`(libcubrid.so `c5450d9a...`)와 base `4781495f0`(`2bcc65b9...`). o 2001 행 x i 200001 행. LEFT/RIGHT OUTER `100001 / 100000`, SEMI 2000, ANTI 1 로 NL 과 같다. head BUILD 12-17 ms(`memory+skip`), base 1830-3312 ms(`file`). A/C 3 은 head 정상, base 서버 중단.
- R2: head 에 `temp_file_memory_size_in_pages=0` 으로 R1 과 같은 스크립트, 결과 행 R1 과 같음.
- R3: `test_mode=yes` 로 `join_orderby_skip` 의 준비 문장과 Q116-Q119 를 head 와 base 에서 실행. 결과 행 같음, trace 는 위 TC PRs 설명과 같다.
- 증거: `.git_ignored_dir/scratch/pr8268/evidence/`.
