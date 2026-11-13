# TC #3985 리뷰 보고서 (PR #8364 r2)

**PR:** [CUBRID/cubrid-testcases#3985](https://github.com/CUBRID/cubrid-testcases/pull/3985) (엔진 CUBRID/cubrid#8364)
**제목:** [CBRD-27870] Revise testcase for cbrd_27361_page_order
**작성자:** soheejung-cs
**HEAD SHA:** TC `694a0e04d` / 엔진 `7d09a54cb`(11-04 리뷰 이후 커밋 없음)
**리뷰 일시:** 2026-11-05
**리뷰 결정:** TC #3985 Comment(본문 + 인라인 NIT, 5779594395)

> **TL;DR** (작성자 확인 필요): TC 내용은 맞고, Case 8이 엔진 #8364의 debug assert를 잡아낸다. 그런데 본문의 "debug 빌드에서도 같은 출력으로 통과합니다"는 CI optdebug 결과(Case 8에서 서버 core)와 다르다. 엔진 Blocking(11-04 CHANGES_REQUESTED, 답 없음)이 고쳐진 뒤 다시 돌려 Approve.

## Findings

### Non-blocking (should consider)

1. PR 본문 Remarks -- "debug 빌드에서도 같은 출력으로 통과" -> gha-ci 41623402810(052b84a2e, tc a4ad38e17)과 41770625665(7d09a54cb, tc 694a0e04d) 모두 optdebug에서 `cbrd_27361_page_order` NOK(Case 8 `expr_image_same_prog` assert core). 본문을 고치거나 엔진 수정 뒤 다시 확인해야 한다.
2. `cases/cbrd_27361_page_order.sql:20` 머리 주석 `Case 6: ... parallel scan; the trace shows ...`에 `;`가 있다. 이번 답안에는 영향이 없지만 CTP는 `;`로 문장을 나눈다. NIT.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| ODKU 숨은 컬럼(필터·집계 컬럼·인덱스/힙·조인·GROUP BY) | Case 5 | 통과 |
| 병렬 대상 소스(trace) | Case 6, greptile 반영 a4ad38e17 | 통과 |
| SELECT 목록 상관 서브쿼리 | Case 7 | 통과 |
| 집계 빠른 길(WHERE 없는 MAX·MIN, 키 범위 COUNT(*)) | Case 8 | 실패(debug core, 엔진 결함) |

## Runtime Verification

- 위 두 run의 sql failed.list. 41770625665는 skew로 보이는 `cbrd_27361_string_leaves`, `cbrd_27374_*`, `cbrd_27442`도 같이 NOK. 새로 돌린 것 없음.
- 엔진 스레드: XASL bit 29 충돌은 작성자가 "제가 옮기겠습니다, 머지 후 멘션" 답함. Blocking 스레드(4464626986)는 답 없음.
