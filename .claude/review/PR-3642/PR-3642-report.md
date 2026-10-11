# PR #3642 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3642](https://github.com/CUBRID/cubrid-testcases/pull/3642)
**제목:** [CBRD-27365] Revies for Reduce temp file size by changing the tuple format inside temp files
**작성자:** ssihil
**HEAD SHA:** `232905aaf` (develop merge-base `dbac2f953`)
**JIRA:** CBRD-27365 (Improve Function/Performance, Resolved; 엔진 변경 CUBRID/cubrid#7866 `453da49c8`) / 연관: CBRD-25717 (원 TC)
**TC PR:** 이 PR 자체가 TC 단독 PR (엔진 PR 없음). CI 확인용으로 CUBRID/cubrid#8102 (develop `07aec2c5c` + 빈 커밋) 의 `tc/pr-8102` (cubrid-testcases#3643 `74e799550`) 에 두 커밋을 cherry-pick, private-ex#4311 은 변경 없음
**리뷰 일시:** 2026-10-06
**리뷰 결정:** #3642 Approve (게시: review 5424024208, top-level 2줄 + 인라인 NIT 1건) / 엔진 PR 없음. 같은 원인의 shell `membuf_config` 실패는 2026-10-04 Teams 로 전달해 리뷰에서 제외

> **TL;DR** (Non-blocking): 답지 9종은 CBRD-27365 이후 gha-ci 18회 실행의 실제 trace 출력과 한 줄도 다르지 않고, `nl_baseline` 행수 변경은 빌드 측 동점 판정을 없애 재발을 막는다. 남은 것은 헤더 주석의 없는 함수명 1건뿐이다.

## Summary

- **변경 요약**: CBRD-27365 (임시 튜플 포맷 압축, `page_cnt` 감소) 로 바뀐 `cbrd_25717` 해시 조인 trace 답지 9종 갱신 + `nl_baseline` 의 `t_nla` 를 2400 행으로 늘려 빌드 측 판정을 `tuple_cnt` 에서 끝나게 함
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)
- `sql/_36_guava/cbrd_25717/cases/cbrd_25717_nl_baseline.sql:20` — 헤더가 빌드 측 판정 위치로 `hjoin_assign_build_probe` 를 가리키지만 develop 에 그런 함수가 없다. 판정은 `hjoin_init_context` (`query_hash_join.c`, JOIN_INNER 분기) 에 있다 -> 주석을 따라가는 사람이 코드를 찾지 못한다.
  ```c
  else if (outer->list_id->tuple_cnt == inner->list_id->tuple_cnt
           && outer->list_id->page_cnt < inner->list_id->page_cnt)
  ```
- PR 제목 `Revies` 오타 (`Revise`). squash 머지 시 develop 커밋 제목이 된다.

## JIRA -> TC PR

CBRD-27365 의 Specification Changes: "실행 계획 텍스트가 같은 데이터에서 달라질 수 있다 ... 해시 조인 in-memory 여부, 해시 조인 빌드 측 선택 ... 결과 집합은 동일하다."

| 항목 | PR 상태 | 판정 |
|---|---|---|
| BUILD method `hybrid` -> `memory` (+`skip`/`+file`/`+hybrid`) | 답지 8종 + `nl_baseline` 반영, 바뀐 줄은 모두 `method` 뿐 | 충족 |
| 빌드 측 선택 변경 (`nl_baseline` `t_nla` <-> `t_nlb`) | 답지 반영 + 행수 2400/2000 으로 동점 제거 | 충족 |
| 결과 집합 동일 | 결과 행 diff 없음, `nl_baseline` 4 전략 모두 `2000 / 2001000 / 4000` 유지 | 충족 |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 답지 9종 trace 갱신 | gha-ci 18회 실제 출력의 method/SCAN 서명과 PR 답지 일치 (아래) | 통과 |
| `nl_baseline` 빌드 측 고정 | `hjoin_init_context` 는 `tuple_cnt` 가 작은 쪽을 빌드로 고름 -> `t_nlb`(2000). 2400 행은 `cte_max_recursions` 기본값 2000 때문에 cross join + `limit` 으로 생성 | 통과 |

TC 파일 검토: 바뀐 케이스(`nl_baseline.sql`)는 답지가 함께 바뀌었다. 헤더의 `;` 3개는 모두 줄 중간이라 CTP 문장 분리 (`SQLParser` 는 `;` 로 끝나는 줄에서만 자름) 대상이 아니고, 답지 첫 블록에도 -493 이 없다. `overflow_dependent_list.sql` 은 첫 커밋에서 5줄 추가, 둘째 커밋에서 삭제해 순변경 0 이다. PR 본문의 "release 14/14 통과" 는 아래 CI 증거와 모순되지 않는다.

## Runtime Verification

- gha-ci 아티팩트 (`http://192.168.1.48:30080/runs/<run>/sql/shard/<NN>/artifacts/ctp_log.tgz`) 에서 2026-10-02~10-06 다른 PR 들의 실행 18건 (모두 debug=optdebug, develop `30043f492`/`15e7dc8b5`/`67bea1201` 시점, 목록 `.git_ignored_dir/scratch/pr3642/ci/methods.tsv`) 의 `cbrd_25717_*.result` 를 모아 `method` 와 `t_nla/t_nlb` SCAN 순서를 비교: 9 케이스 모두 18회 동일, PR 답지와도 동일. 병렬 split 이 파티션마다 워커별 부분 페이지를 붙이는 구조 (`qfile_append_list` 는 페이지 통째 복사) 라 `memory+hybrid` 가 흔들릴 수 있는지 봤으나 18회 중 변동 0.
- `/run sql` on CUBRID/cubrid#8102 (develop `07aec2c5c` + 빈 커밋, TC `tc/pr-8102` `74e799550` = #3642 트리와 동일): run 37415519141 verdict `pass`, sql 17487 건 실패 0. shard 09 (debug=optdebug, 엔진 `f25af887c`, `tc_sha` `74e799550`) 에서 cbrd_25717 14/14 ok. 리뷰 게시 후 #8102 를 닫았고, 봇이 #3643/#4311 을 닫고 두 저장소의 `tc/pr-8102` 를 지웠다.
- 작성자 첨부: `11.5.0.2632-e17fdab` release, cbrd_25717 14/14.
