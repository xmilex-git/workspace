# PR #8155 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8155](https://github.com/CUBRID/cubrid/pull/8155)
**제목:** [CBRD-27572] Destroy the list file of a correlated subquery whose execution changes its shape
**작성자:** shparkcubrid
**HEAD SHA:** `386488ab6` (develop merge-base `bcd6c5936`)
**JIRA:** CBRD-27572 (Correct Error, Open) / 연관: CBRD-26522 (Regress 원인, #6806)
**TC PR:** CUBRID/cubrid-testcases#3743 (`tc/pr-8155` `4f8f6ee1b`, 변경 없음) + 별도 PR #3742 (브랜치 `CBRD-27572` `8478fe73c`, 실제 TC) / cubrid-testcases-private-ex#4418 (`tc/pr-8155` `2f49e4779`, 변경 없음)
**리뷰 일시:** 2026-10-14
**리뷰 결정:** 엔진 PR Approve (본문에 TC 브랜치 언급, 2026-10-14 게시 review 5511690669) / TC PR 별도 리뷰 없음

> **TL;DR** (Non-blocking): 엔진 수정은 design.md 권장안과 같고, 허용 목록이 list를 바꾸는 경로를 모두 destroy로 돌린다. 막을 결함 없음. TC가 봇 브랜치 `tc/pr-8155`가 아닌 별도 브랜치(#3742)에 있어 CI가 새 케이스를 돌리지 않았다.

## Summary

- **변경 요약**: NL inner 행마다 상관 부질의 list file을 truncate 재사용할지 노드 종류로 판정하고, BUILDVALUE와 단순 BUILDLIST 외에는 CBRD-26522 이전처럼 destroy
- **주요 이슈**: 없음 (TC 브랜치 위치만 언급)
- **확인 필요 사항**: 없음

---

## Findings

없음

검토 범위: `qexec_is_list_reusable_by_truncate`의 조건을 `xasl->list_id`를 바꾸거나 정렬하는 모든 경로와 대조했다.
- list 교체: `qexec_groupby`, `qexec_groupby_index`(`groupby_list` 필수), `qexec_execute_analytic`, 집합 연산, CTE.
- 정렬: `qexec_orderby_distinct`.
- 그대로 두어도 되는 경우: MRO(`XASL_USES_MRO`, 언제나 LIMIT이 있어 매 실행 다시 정렬), CONNECT BY(결과를 `xasl->list_id`에 추가만 함), `after_iscan_list`(처음 열 때와 같은 sort_list). 이 셋은 list 모양이 그대로라 truncate 재사용이 안전하다.
- `truncate=true` 호출 3곳 가운데 `qexec_intprt_fnc`와 px_scan `drain_slot_oids`는 행마다 `qexec_clear_all_lists` / `qexec_clear_scan_all_lists`로 destroy하므로, 재사용은 NL inner(`scan_ptr`)에서만 생긴다.

## JIRA -> Engine PR

기준: Expected Result가 Repro 조건에서 성립하고, design.md 변경이 모두 구현되고, `미정` 항목이 해결되거나 남는 이유가 명시될 것.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: Repro 첫 질의가 오류 없이 80 | R4 head: 80/80, R3 base: assert로 서버 종료 | 충족 |
| design 변경: `qexec_clear_head_lists_with_truncate`에서 노드별 판정, 대상 아니면 `qexec_clear_xasl_head` | `qexec_is_list_reusable_by_truncate` 추가, 그대로 구현 | 충족 |
| design truncate 대상: BUILDVALUE, BUILDLIST(GROUP BY·분석·ORDER BY(SKIP 제외)·DISTINCT 없음) | 조건식 design.md와 동일 | 충족 |
| 미정: 그 밖의 XASL 종류(집합 연산, CTE) | destroy로 둠, UNION 성능 측정(-3.5%) | 충족 |
| 확인 필요: LIMIT 없는 ORDER BY 정렬 생략 | ORDER BY를 대상에서 빼서 함께 막음, 비용 +8.9%(1행) 명시 | 충족 |

연관 이슈 CBRD-26522(#6806)는 원인 변경이며, 이 PR이 그 회귀를 고친다. 같은 결함을 기술한 다른 연결 이슈는 없다.

## TC PRs

기준: 시나리오는 엔진 PR 검증 표의 행과 JIRA `test.md`의 T1-T4. test.md에 있거나 TC PR(본문 또는 파일)에 언급되면 통과.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| T1 / 케이스 1 그룹 키에 바깥 컬럼 | test.md T1, #3742 Case 1 | 통과 |
| T2 / 케이스 2 HAVING에만 바깥 컬럼 | test.md T2, #3742 Case 2 | 통과 |
| T3 / 케이스 3 count(*) GROUP BY, 타입만 다름 | test.md T3, #3742 Case 3 | 통과 |
| T4 / 케이스 4 분석 함수 | test.md T4, #3742 Case 4 | 통과 |
| 케이스 5-7 DISTINCT, UNION, ORDER BY LIMIT (destroy 쪽) | #3742 Case 5-7 | 통과 |
| 케이스 8-9 일반 list, BUILDVALUE (truncate 유지) | #3742 Case 8-9 | 통과 |

- 파일 검토: 케이스 1개, 답지 1개가 짝을 이룬다. 헤더 주석의 줄 끝에 `;`가 없다. 케이스마다 j 테이블 기준 질의를 함께 두어 결과를 비교한다.
- 브랜치: TC 커밋이 봇 TC PR(`tc/pr-8155`, #3743)이 아니라 별도 브랜치 `CBRD-27572`(#3742)에 있다. gha-ci sql은 `tc_branch='tc/pr-8155'`, `tc_sha='4f8f6ee1b'`(봇 초기 커밋)로 돌았으므로 `cbrd_27572`는 CI에서 실행되지 않았다. 엔진 PR 리뷰 본문에서 언급한다.
- private-ex #4418: 변경이 없다. 시나리오가 모두 공개 TC에 있으므로 따로 리뷰할 것이 없다.
- 판정: 시나리오는 모두 충족한다. CI 증거가 없는 부분은 로컬 실행 R1/R2로 확인했다(수정 전 서버 종료, 수정 후 답지와 같음).

## Runtime Verification

- CI(run 38370007001, head `386488ab6`): debug/release 빌드, sql, medium 통과. TC 브랜치는 `tc/pr-8155` `4f8f6ee1b`(변경 없음)이므로 새 케이스는 CI에서 실행되지 않았다. shell 1건(`_37_elderberry/cbrd_23842_cdc/operate/oper03`)은 다른 PR들에서도 실패하는 CDC LSA flake이고, 이 PR은 CDC 코드를 건드리지 않는다.
- develop 변경: merge-base 이후 `src/query`에 들어온 커밋은 bc3409436(px trace 병합), 8f57aa0d7(px CTE 힌트) 두 개다. 둘 다 이 경로와 관계없다.
- 새 실행 4건: 모두 2026-10-14, `just ctp sql` 컨테이너 실행이다.
  - 빌드: CI optdebug tarball 두 개.
    - base = develop `bcd6c5936` (11.5.0.2671), libcubrid.so `eabbbeec`
    - head = `386488ab6` (11.5.0.2672), libcubrid.so `d3e563c9`
  - TC: `--testcases-as-is`, 트리는 cubrid-testcases `8478fe73c`(#3742).
  - JIRA Repro: 티켓 SQL 그대로(memoize 기본값, 첫 질의에 `no_subquery_cache` 없음)를 리뷰 전용 케이스로 돌렸다.
  - R1 base + `cbrd_27572`: NOK. Case 1 NL 질의에서 -21019 후 서버가 종료되고, 이후 문장은 모두 -677이다. 코어 1개가 남았다.
    - assert: `query_opfunc.c:578` `qdata_collect_tuple_values`: `tuple_desc_p->f_cnt < type_list->type_cnt`.
    - 경로: `qexec_end_one_iteration` <- 부질의 `qexec_execute_mainblock` <- `fetch_peek_dbval_slow` <- inner `qexec_execute_scan`.
    - 티켓의 `list_file.c:6949`와 위치는 달라도 같은 열 수 불일치다.
  - R2 head + `cbrd_27572`: OK. `.result`가 답지와 같고, 코어와 assert는 없다. release에서 만든 답지가 optdebug에서도 맞는다.
  - R3 base + Repro: 첫 질의에서 같은 assert로 서버가 종료된다(코어 1개). j 테이블 기준 질의는 80이다.
  - R4 head + Repro: 첫 질의 80, 기준 질의 80. 코어와 assert는 없다.
- 증거: `.git_ignored_dir/scratch/pr8155/evidence/`(.result, provenance, backtrace, console). 실행 디렉터리, 코어, 빌드는 확인 후 지웠다.
- 실행하지 않은 것: release 빌드(작성자 표의 release 결과는 재현하지 않았다), 최신 develop 위의 재실행(drift가 무관하다고 판단).
