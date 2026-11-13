# PR #4724 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4724](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4724)
**제목:** [CBRD-26722] Add shell_perf testcase for Expand parallel heap scan to parallel scan (index, heap, list)
**작성자:** ssihil
**HEAD SHA:** `3459b70ce` (develop merge-base `35d06d19f`)
**JIRA:** CBRD-26722 / 엔진 PR CUBRID/cubrid#7062 (2026-05-27 merge, `0c6088ab3`)
**TC PR:** 기능 TC는 이미 merge됨: cubrid-testcases#3686 (sql), private-ex#4363 (shell). 이 PR은 TC만 바꾸는 후속 PR (shell_perf 파일 1개, +446)
**리뷰 일시:** 2026-11-04
**리뷰 결정:** private-ex#4724 Approve + inline 질문 1개 (검사 8·9), 엔진 PR 리뷰 없음 (merge됨)

> **TL;DR** (Non-blocking): 비율 검사 2-7은 trace의 워커 수와 5회 값 일치를 함께 보므로 시간만으로는 통과할 수 없고, 스크립트는 최신 develop release에서 10줄의 판정을 모두 의도대로 냅니다. 남는 것은 절대 시간 검사 8·9 하나입니다. 수정 전 빌드에서도 통과하고 장비가 바뀌면 판정 기준이 무너지므로, 남길지 작성자에게 묻습니다.

## Summary

- **변경 요약**: 10,000,000행에서 heap/list/index 병렬 스캔이 직렬보다 빠른지(검사 2-7), heap 경로가 수정 전 수준을 유지하는지(검사 8·9) 재는 shell_perf TC를 추가합니다.
- **주요 이슈**: 검사 8·9 (절대 시간 기준값)의 판별력
- **확인 필요 사항**: 검사 8·9를 상시 회귀 감시로 남길지, Definition of done 3번의 답은 PR 본문 측정으로 두고 뺄지

---

## Findings

### Questions for the author

1. `cbrd_26722.sh:192-197, 439-440` -- 검사 8·9는 절대 시간을 `base_*_at_fix x factor x 1.25`와 비교합니다. 그래서 이 이슈의 수정 여부를 가르지 못하고, 다른 장비에서는 판정 기준 자체가 성립하지 않습니다.
   - 수정 전 2215에서도 둘 다 OK입니다. PR 본문 표를 보면 병렬 2.007s, 직렬 3.45s로 한계 2.51s / 12.13s 안에 듭니다.
   - 최신 2780의 병렬 1.676s를 기준으로 하면, 약 50% 느려져도 한계 2.51s 안에 들어 통과합니다.
   - 이 호스트(bbc3328 release)의 heap 직렬 합은 3.93s입니다. 한계 12.13s이므로 직렬이 3배 느려져도 검사 9는 OK를 냅니다.
   - Definition of done 3번의 답은 PR 본문의 7회 x 3대 측정입니다(+0.5% t=0.51, +2.0% t=1.81). 검사로는 장비에 묶인 상수 두 개와 재측정 절차만 남습니다.

## JIRA -> Engine PR

엔진 PR #7062는 2026-05-27에 merge됐고 기능 TC(#3686, #4363)도 merge됐습니다. 이 PR은 TC만 바꾸므로 엔진 PR 판정은 이번 범위에 들지 않습니다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| AC: heap 대량 스캔이 병렬에서 더 빠름 (selectivity 0.01) | 검사 2 (비율), 3 (`heap` 워커 >= 2, 5회 값 일치) | 충족 |
| AC: list(temp) 스캔이 병렬에서 더 빠름 | 검사 4, 5 (안쪽 heap은 `no_parallel_scan`으로 고정, `no_push_pred`) | 충족 |
| AC: index 범위 스캔이 병렬에서 더 빠름 (0.05) | 검사 6, 7 (covering, `using index i_col1`) | 충족 |
| DoD 3: 수정 후 heap 경로 성능 회귀 없음 | PR 본문 측정 2215/2216/2780 7회 x 3대. 검사 8·9는 Q1 | 충족 (측정), 검사는 Q1 |
| 결과/계획/매개변수 | cubrid-testcases#3686, private-ex#4363 (merge됨) | 충족 |

파일 검토:
- 판정 줄 10개가 `write_ok`/`write_nok` 호출 10개와 맞습니다.
- 메시지에 glob 문자가 없습니다.
- 모든 종료 경로가 `do_cleanup` -> `finish`로 끝납니다.
- core는 `find $init_path $CUBRID ${cur_path} -name "core*" -type f`로 셉니다.
- 엔진 trace 형식 `(parallel workers: %d, %s time:`(`px_scan_trace_handler.cpp:355-356`)이 `workers_of`의 grep과 일치합니다.
- 수정 전 빌드에서 NOK 5개(2·4·5·6·7)는 작성자가 실행한 결과입니다.

판정: 승인 가능. Q1은 머지를 막지 않습니다.

## Runtime Verification

| 빌드 | 종류 | TC ref | 결과 |
|---|---|---|---|
| 11.5.0.2817-bbc3328 (develop, 2026-11-04) | release | `3459b70ce` (`just ctp shell_perf _40_guava/cbrd_26722`, 공유 32코어 호스트) | 9 OK / 1 NOK (검사 2: heap 2.30배, 2.86배 필요), core 0 |

- 측정값: heap 직렬 3.93s / 병렬 1.71s (워커 8), list 37.38s / 21.44s (1.74배, 워커 8), index 1.017s / 0.151s (6.74배, 워커 8).
- 검사 2의 NOK는 공유 호스트에서 잰 비율입니다. 이 호스트의 비율은 방향만 보여 줄 뿐 임계값을 정하지 않으므로 finding이 아닙니다. 성능 장비 값(4.12배 이상)은 작성자가 잰 것입니다.
- 러너가 `parallelism=4`를 고정한 상태에서도 `PARALLEL(8)` 힌트로 워커 8이 나왔습니다. 즉 힌트가 매개변수보다 우선합니다.
- 수정 전 빌드(2215)는 직접 돌리지 않았습니다. 작성자의 결과를 인용했습니다.
