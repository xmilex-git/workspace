# private-ex #4551 리뷰 보고서 (PR #6466 r2)

**PR:** [CUBRID/cubrid-testcases-private-ex#4551](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4551) (엔진 CUBRID/cubrid#6466)
**제목:** [CBRD-25984] Support covered index scan and key filter on function indexes
**HEAD SHA:** TC `57910d7f4` / 엔진 `d7ce3af72`(11-04 리뷰 05b46aefe 이후 MRO 1줄 수정 `scan_manager.c`)
**리뷰 일시:** 2026-11-05
**리뷰 결정:** private-ex #4551 Approve(5779594509)

> **TL;DR** (Non-blocking): `bug_bts_7459` 답안 2줄(`(covers)`, cost 3 -> 2)만 바뀐다. 단일 컬럼 함수 인덱스 `ln(나이)` 를 select·where에 쓰는 질의라 PR 목표 그대로이고 결과 행은 같다. Approve.

## Findings

없음

## TC PRs

- 바뀐 것은 plan 출력 두 줄. 결과 3행 동일. 이 케이스는 IN/ORDER BY LIMIT(MRO)가 아니라 새 헤드의 MRO 수정(d7ce3af72)에 영향받지 않는다.
- 엔진 PR에는 soheejung-cs의 새 지적 4건(자기 조인 별칭 섞인 함수식 NULL 등)이 열려 있다. 이번 요청 범위(#4551) 밖.

## Runtime Verification

- gha-ci run 41765316148 (엔진 05b46aefe, optdebug, tc 57910d7f4 = 현 head): shell 3,538 pass, `bug_bts_7459` shard 48 OK(33.7초). d7ce3af72 헤드에서는 CI가 아직 없다.
