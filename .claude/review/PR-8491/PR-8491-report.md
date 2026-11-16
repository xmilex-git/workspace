# PR #8491 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8491](https://github.com/CUBRID/cubrid/pull/8491)
**제목:** [CBRD-28011] Show OOS reads separately in SQL trace
**작성자:** vimkim
**HEAD SHA:** `a4fec6f8e` (base `feature/oos-merge`, merge-base `67220b7e2`)
**JIRA:** CBRD-28011 (Sub-task, Develop) / 연관: CBRD-28074 (parallel `oos time` > scan `time` 가능성, R-1 후속), CBRD-26978 (부모), CBRD-26357
**TC PR:** CUBRID/cubrid-testcases#4148 (`tc/pr-8491` `ca705aa21`) / cubrid-testcases-private-ex#4850 (`tc/pr-8491`, 이 PR의 변경 없음)
**리뷰 일시:** 2026-11-16
**리뷰 결정:** 엔진 PR Approve (본문에 할당 확인 fix 질문, 이 PR 범위 밖) / TC #4148 Approve, NIT 없음 (게시 2026-11-16: 엔진 review 5914646248, TC review 5914646350)

> **TL;DR** (Non-blocking): OOS 읽기 몫이 serial, page batch, index lookup, partition, parallel heap, parallel partition, parallel UNION 경로에서 모두 scan 자신의 수치 안으로 모이고, serial과 parallel의 OOS fetch가 같다. 결함은 없고, OOS fetch에 들어가는 page 할당 확인 fix가 왜 필요한지만 이 PR 범위 밖 질문으로 남긴다.

## Summary

- **변경 요약**: `oos_read`/`oos_read_many`가 trace 중일 때 자기 fix, ioread, 시간을 thread 누적값에 더하고, scan이 자기 구간의 차이를 `(oos time, fetch, ioread)` (JSON `"oos"`)로 표시한다.
- **주요 이슈**: 없음
- **확인 필요 사항**: OOS head page를 `pgbuf_fix_if_not_deallocated`로 잡는 할당 확인이 일반 읽기에 왜 필요한지 (이 PR 범위 밖)

---

## Findings

### Questions for the author

- `src/storage/oos_file.cpp` `oos_fix_page_if_oos` (이 PR이 바꾸지 않은 코드) - OOS head page fix가 `pgbuf_fix_if_not_deallocated` -> `disk_is_page_sector_reserved` (volume의 sector 할당 여부 확인)를 거쳐 page를 2번 더 fix한다. release 빌드에서 20000바이트 값(chunk 2개) 200행을 읽으면 `oos fetch` 800 중 400이 이 확인이다. visible한 heap record가 가리키는 OOS head page가 이미 해제되어 있는 경로가 있어서 확인하는지 묻는다. 이 PR의 trace는 그 비용을 드러낼 뿐이고, 고칠 대상은 아니다.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC1: heap 읽기와 OOS 읽기의 fetch, ioread, time 구분 | text `(oos ...)`, JSON `"oos"`; 직접 실행 확인 | 충족 |
| AC2: 지표의 집계 범위와 기존 합계와의 관계 설명 | PR 본문 + 코드 주석: scan 수치의 일부, fetch에 할당 확인 fix 포함, worker 요약 줄 제외 | 충족 |
| AC3: OOS 읽는/안 읽는 조회 비교, OOS 없는 조회 통계와 결과 | TC `cbrd_28011` + 직접 실행: 큰 컬럼 안 읽는 조회, OOS 없는 테이블, 1600바이트 inline 값에서 oos 묶음 없음 | 충족 |
| 연관 CBRD-28074 (R-1) | 이 PR은 해결하지 않음, 별도 후속 | 해당 없음 |

design.md / test.md 첨부 없음 (Sub-task).

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| serial heap scan이 OOS 읽음 -> oos 표시 | #4148 `cbrd_28011.sql` | 충족 |
| 큰 컬럼 안 읽음 / OOS 없는 테이블 -> 표시 없음 | #4148 | 충족 |
| index lookup | #4148 | 충족 |
| partition별 줄 | #4148 | 충족 |
| JSON 출력 | #4148 | 충족 |
| parallel subquery / UNION 경로의 기존 답 변경 | #4148 `cbrd_26722_list.answer` (`t_wide` scan에 oos 추가) | 충족 |

- 숫자는 모두 `?`로 가려 표시 여부만 본다. 빌드 종류와 상관없이 답이 같다.
- `cbrd_28011.sql` 2번째 줄 header 주석에 `;`가 있다 (`... shows the oos group; its figures ...`). 줄 중간이라 CTP가 문장을 나누지 않았고, 답의 블록 수가 맞으며 CI에서 ok이다.
- private-ex#4850: `tc/pr-8491`에 이 PR의 변경 없음 (develop 대비 차이는 feature 브랜치 쪽 파일).
- 판정: Approve.

## TLA+ Verification

사용자 지시로 생략 (2026-11-16). 변경은 trace 계수 경로에만 있고 latch, lock 순서는 바꾸지 않는다.

## Runtime Verification

- CI gha-ci run 43016108111 (optdebug `a4fec6f8e`, `tc/pr-8491` `51f346fa5`): sql에서 `cbrd_28011` ok, `cbrd_26722_list` nok (답 미갱신). rerun 43168853861 (`tc/pr-8491` `ca705aa21`): sql pass, `cbrd_26722_list` ok. medium, shell pass.
- sql_by_cci: 두 run 모두 37 NOK. 차이는 `cbrd_26722_list`(첫 run) 하나와 `cbrd_26104`(rerun) 하나로, `cbrd_26104`는 다른 PR run 5개(43676209361 등)에서도 실패하는 flake이다. 나머지는 cci baseline.
- 직접 실행: CI tarball optdebug(`libcubrid.so` sha256 `da9b4de9...`)와 release(`96318ed1...`), CS 서버, 서버 재시작으로 buffer를 비운 뒤 실행.
  - serial heap 20000바이트 x 200행: release `heap fetch 806, ioread 405` 중 `oos fetch 800, ioread 400`; optdebug `2224/405` 중 `2200/400`.
  - parallel heap 10만 행 중 1000행 OOS: OOS fetch parallel = serial (release 4000, optdebug 11000), 빈 buffer에서 oos ioread 2000.
  - parallel partition: partition 줄 oos fetch 합 = scan 합 (release 2000+2000).
  - parallel UNION, NL inner index scan, correlated/uncorrelated subquery, 값 그대로 반환, WHERE의 `length(big)`: OOS를 읽은 scan 줄에만 표시.
  - 미실행: `gather: row by row`, parallel index scan, `use_system_malloc` 메모리 체크.
- 증거: `.git_ignored_dir/scratch/pr8491/evidence/trace*.out`.

## Existing Comments

| 작성자 | 내용 | 상태 |
|---|---|---|
| vimkim (self review) | 결함 없음, R-1 위험 | R-1은 CBRD-28074로 분리됨 |
| hornetmj | Approve | - |
