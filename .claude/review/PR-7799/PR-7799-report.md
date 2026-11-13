# PR #7799 코드 리뷰 보고서 (2차, 재리뷰)

**PR:** [CUBRID/cubrid#7799](https://github.com/CUBRID/cubrid/pull/7799)
**제목:** [CBRD-27187] 조인이 있는 GROUP BY 문장에서 group-by-skip 인덱스 스캔 플랜이 후보가 되지 않는 문제 개선
**작성자:** Hamkua
**HEAD SHA:** `732b35743` (1차 리뷰 `84097c475` 이후: develop 머지 `d18cc84df`, `b1f8c2869`, `732b35743`)
**JIRA:** CBRD-27187 / 관련 CBRD-27820 (jihyekim-0, Confirmed)
**TC PR:** CUBRID/cubrid-testcases#3358 (`a086a35b8`) / cubrid-testcases-private-ex#3995 (draft, `f5bf20c89`, 10-29 이후 sync 없음)
**리뷰 일시:** 2026-11-02 (1차 2026-10-29, review 5694652183 / 5694652401)
**리뷰 결정:** (grill 후 기입)

> **TL;DR** (Non-blocking): 1차 리뷰 이후 엔진 변경은 ROWNUM 검사 한 블록이고, `qo_top_plan_new()` 의 검사와 같다. 1차의 두 요청 (develop sync, TPC-H AC3) 은 작성자가 답했다. 남은 것은 private-ex `tc/pr-7799` 의 `20448_01_6.answer` 한 파일이다. sync 뒤 엔진은 develop 답을 내므로 이 파일 변경은 버려야 shell 이 OK 가 된다.

## Summary

- **증분 변경**: `qo_plan_is_groupby_skip_candidate()` 가 `QO_TC_TOTALLY_AFTER_JOIN` 항 (WHERE 의 ROWNUM, instnum 조건) 이 있으면 후보를 내지 않는다. jihyekim-0 의 리뷰 (ROWNUM 이 있는 조인에서 범위 없는 인덱스 스캔이 뽑혀 결과 행이 바뀜) 를 반영했고, 리뷰어가 수정을 확인했다.
- **CI (gha-ci 41039004849, `732b35743`)**: sql, medium pass. shell 14 NOK 중 13건은 같은 시기 #8277/#8286/#8273 run 에도 있는 공통 실패다. 이 PR 만의 NOK 는 `20448_01` 하나다.
- **확인 필요 사항**: CBRD-27820 Remarks 한 줄 (jihyekim-0 요청, 아직 미반영)

---

## Findings

### Non-blocking (should consider)
- private-ex `tc/pr-7799` (`f5bf20c89`) 의 `20448_01_6.answer` 는 `group by t2.k1 order by t1.i1 limit 2` 의 둘째 행 `i1` 을 2 -> 5 로 바꾼다. `d18cc84df` 이후 CI 두 번 (41009381732, 41039004849) 모두 엔진 출력은 `2` 로, develop 답과 같다. `i1` 은 GROUP BY 에 없는 컬럼이라 값은 SQL 이 정하지 않는다. 그래서 #3995 는 이 파일을 develop 답으로 되돌리면 (빈 PR) 된다. 1차 리뷰의 `20158_table_schema2` 와 같은 경우다.

### Existing (다른 리뷰어가 제기, 재게시 안 함)
- CBRD-27820: LEFT JOIN 의 ON 절에 보존 쪽 `col = 상수` 가 있으면 `qo_plan_compute_iscan_sort_list` 가 그 키 컬럼을 고정값으로 보고 건너뛴다. develop 은 조인 GROUP BY 를 늘 정렬해서 ORDER BY 에서만 드러났다. 이 PR 뒤에는 skip GROUP BY 가 선택돼 그룹이 쪼개진다 (jihyekim-0 의 6행 결과). 27820 담당자가 27820 에서 고치겠다고 했고, 이 PR 에는 Remarks 한 줄만 요청했다. 아직 본문에 없다.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC1 조인 GROUP BY 에서 인덱스 플랜이 후보, skip GROUP BY | TC Case 1-3, 1차 adhoc | 충족 |
| AC2 순서 비보존 조인은 정렬, outer join 결과 동일 | TC Case 3-7, 새 Case 8 (ROWNUM) | 충족 (27820 ON 절 상수는 별도 이슈) |
| AC3 TPC-H SF10 Q01~Q22 | 작성자 10-30 코멘트: release, 5회 교대 실행, 22개 결과 동일, 플랜 변화는 Q13 (customer 스캔이 PK 인덱스로, 여전히 hash join + 정렬), wall 중앙값 7.02 -> 6.92 초 | 충족 |
| ROWNUM 검사가 `qo_top_plan_new()` 와 같음 | 두 함수 모두 `planner->term[]` 에서 `QO_TC_TOTALLY_AFTER_JOIN` 을 찾는다. CONNECT BY 검사는 후보가 애초에 생기지 않아 `732b35743` 에서 뺐다 | 충족 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 1차 Case 1-7 | #3358 | 통과 |
| ROWNUM 이 있으면 정렬 유지, 힌트 유무 같음 | #3358 Case 8 (`a086a35b8`), sscan + `temp(group by)` | 통과 |

- #3358: `20158_table_schema2` 변경이 빠졌다 (develop 답 사용). 본문에 Case 6-8 추가. 헤더 주석 `;` 0개. CI sql pass.
- #3995: 위 Finding. 변경을 되돌리면 PR 이 빈다.

## Runtime Verification

- 새 빌드 없음. gha-ci 41039004849 (`732b35743`, debug=optdebug, TC `tc/pr-7799` sql `a086a35b8` / shell `f5bf20c89`): sql, medium pass, shell 14 NOK.
- shell NOK 판정: 다른 PR run 의 `failed.list` 와 겹침 비교. 13건은 41081555524 (#8277), 41081563199 (#8286) 에도 있다. `20448_01` 은 7799 의 두 run 에만 있다. shard 15 `ctp_log.tgz` 의 diff: 출력 `2`, 답 `5`.
- 증거: `.git_ignored_dir/scratch/pr7799r2/`.
