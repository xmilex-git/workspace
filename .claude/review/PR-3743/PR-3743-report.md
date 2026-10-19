# PR #3743 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3743](https://github.com/CUBRID/cubrid-testcases/pull/3743)
**제목:** [CBRD-27572] Add a test for correlated GROUP BY/analytic subqueries in an NL join inner condition
**작성자:** shparkcubrid (브랜치 `tc/pr-8155`, 봇 TC PR)
**HEAD SHA:** `2c535bc51` (develop 분기점 `11492d2fd`, 봇 초기 커밋 `4f8f6ee1b`)
**JIRA:** CBRD-27572 (Correct Error, Open) / 연관: CBRD-26522 (Regress 원인)
**엔진 PR:** CUBRID/cubrid#8155 (`386488ab6`, 2026-10-14 Approve 게시, 보고서 `.claude/review/PR-8155/`)
**리뷰 일시:** 2026-10-14
**리뷰 결정:** TC PR #3743 Approve + 인라인 1건(TC 위치), 2026-10-14 게시 review 5512830472 / private-ex #4418 리뷰 없음(변경 없음) / 엔진 PR #8155 추가 코멘트 없음

> **TL;DR** (Non-blocking): 케이스 9개가 모두 NL inner 재실행 경로를 지나고, 수정 전 optdebug에서는 Case 1-4와 Case 6에서 서버가 종료되며, 수정 후 CI optdebug에서는 답지와 같다. 내용상 막을 결함은 없다. 이슈 타입이 Correct Error라서 QA 배치 규칙상 `sql/_13_issues/_26_2h/cases/`로 옮겨야 한다.

## Summary

- **변경 요약**: `sql/_36_guava/cbrd_27572` 1개 파일(9 케이스)과 답지 추가. NL inner 조건의 상관 부질의(GROUP BY, 분석 함수, DISTINCT, UNION, ORDER BY LIMIT, 일반 list, BUILDVALUE)를 같은 부질의를 단일 테이블 `j`에서 평가한 기준 질의와 비교
- **주요 이슈**: TC 위치 (`_36_guava` -> `_13_issues/_26_2h/cases/`)
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)
- `sql/_36_guava/cbrd_27572/cases/cbrd_27572.sql` — Correct Error 이슈의 TC가 릴리스 디렉터리(`_36_guava`)에 있다. QA 규칙(CUBRIDQA-1486)은 이슈 타입만으로 위치를 정한다: 버그 수정은 `sql/_13_issues/_26_2h/cases/cbrd_27572.sql` + `answers/cbrd_27572.answer`. 같은 이유로 QA가 #3041, #3049를 되돌려 보냈다. `_36_guava` 위치는 JIRA `test.md`(2026-10-06 작성, 규칙 확정 전)의 "TC 배치" 항목을 따른 것이다.

## JIRA -> Engine PR

엔진 PR #8155는 2026-10-14 리뷰에서 판정을 마쳤다 (보고서 `PR-8155-report.md`).

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: Repro 첫 질의 오류 없이 80 | head 80/80, base assert | 충족 |
| design 변경: 노드별 truncate 판정, 대상 외 destroy | `qexec_is_list_reusable_by_truncate` | 충족 |

## TC PRs

기준: 시나리오는 엔진 PR 검증 표의 행과 JIRA `test.md` T1-T4. test.md에 있거나 TC PR에 언급되면 통과.

| 시나리오 | 근거 | 수정 전 (bcd6c5936 optdebug) | 판정 |
|---|---|---|---|
| T1 그룹 키에 바깥 컬럼 | Case 1 | assert로 서버 종료 | 통과 |
| T2 HAVING에만 바깥 컬럼 | Case 2 | assert (JIRA 측정, a9f0755) | 통과 |
| T3 count(*) GROUP BY, 타입만 다름 | Case 3 | 다른 assert (JIRA 측정) | 통과 |
| T4 분석 함수 | Case 4 | assert (JIRA 측정) | 통과 |
| DISTINCT (destroy 쪽) | Case 5 | 87 / 1230, 수정 후와 같음 | 통과 |
| UNION (destroy 쪽) | Case 6 | assert `m_qlist_count` (`qexec_execute_query`)로 서버 종료 | 통과 |
| ORDER BY + LIMIT (destroy 쪽) | Case 7 | 27 / 435, 같음 | 통과 |
| 일반 list, BUILDVALUE (truncate 유지) | Case 8, 9 | 38 / 632, 27 / 435, 같음 | 통과 |

- 파일 검토: 케이스 1개와 답지 1개가 짝을 이룬다. 문장 31개 = 답지 블록 31개. 헤더 주석 줄 끝에 `;`가 없고 `--`도 없다. 헤더에 적힌 `qfile_update_domains_on_type_list`, `qexec_hash_gby_agg_tuple`은 develop에 있다.
- 세션 정리: `memoize_memory_limit=default` 복원(#3742 Greptile 반영), trace, 세션 변수, prepare 없음, 테이블 4개 삭제.
- 분기 대조: `qexec_is_list_reusable_by_truncate`의 분기마다 케이스가 있다 (BUILDVALUE 9, 일반 BUILDLIST 8, GROUP BY 1-3, 분석 4, ORDER BY 7, DISTINCT 5, 집합 연산 6). `XASL_SKIP_ORDERBY_LIST` 쪽은 실행 중 MRO(multi range optimization, 인덱스 다중 범위 정렬 최적화)로만 생기고 truncate와 destroy의 결과가 같아 SQL로 구별할 수 없다.
- 기준 질의 `j`: 루트 노드 부질의는 `qexec_intprt_fnc`가 행마다 destroy하므로 수정 전 경로다. 수정 전 빌드에서도 `j` 질의가 같은 값을 냈다.
- PR 본문: "수정 전 develop release에서 1번 NL 질의에서 서버 종료", 답지는 release 생성. optdebug CI에서 답지와 같아 문제 없다.
- 판정: 시나리오 모두 통과. 위치만 옮기면 된다.

## Runtime Verification

- CI: gha-ci 38499031896, sql shard 09. 엔진 `386488ab6` optdebug(debug 슬롯) + `tc/pr-8155` `2c535bc51`에서 `cbrd_27572.sql` ok (213ms). shell 실패 1건(`shell/_40_guava/cbrd_27401`)은 다른 PR 실행 38499172965, 38489708861에서도 같은 케이스가 실패하며, 이 TC PR과 관계없다.
- 이전 실행 재사용 (PR-8155 리뷰, 트리 #3742 `8478fe73c`, 이번 head와 마지막 `memoize_memory_limit` 줄만 다름): base `bcd6c5936` NOK(Case 1 abort), head `386488ab6` OK(답지와 동일).
- 새 실행 5건 (2026-10-14, `just ctp sql` 컨테이너, CI optdebug tarball, 리뷰 전용 디렉터리 `_99_review_adhoc`):
  - p1 head(`386488ab6`, libcubrid `d3e563c9`): 9 케이스 모든 select에 `--@queryplan`. 9개 NL 질의 모두 `idx-join`의 inner `iscan` (o1, `i_cx_nu`)에 부질의가 붙는다(Case 3은 inner iscan 자체에 `subqs`). 결과 값은 답지와 같다.
  - p2-p5 base(`bcd6c5936`, libcubrid `eabbbeec`), 케이스별 단독 실행: Case 5, 7, 8, 9는 수정 후와 같은 값. Case 6은 `query_executor.c:17711` `thread_p->m_qlist_count.load () == qlist_enter_count + dependent_cnt` assert로 서버 종료(코어 1개, 이 실행의 cub_server pid).
- 증거: `.git_ignored_dir/scratch/tc-author/CBRD-27572/evidence/` (p1-p5 `.result`, provenance, p3 backtrace). 실행 디렉터리, 코어, 설치본은 지웠다.
- 실행하지 않은 것: release 빌드, 최신 develop(수정이 아직 없어 수정 전과 같은 NOK가 예상됨).

## Existing Comments

| 작성자 | 위치 | 내용 | 상태 |
|---|---|---|---|
| greptile-apps (P2) | `cbrd_27572.sql:84` | Case 2-9에 실행 계획 확인이 없어 경로가 바뀌어도 통과할 수 있음 | 작성자 답글 없음. p1에서 9개 모두 같은 NL inner 계획임을 확인했다. Case 1 계획이 같은 힌트 조합의 감시 역할을 한다. 리뷰에서는 언급하지 않는다(grill Q3). |
