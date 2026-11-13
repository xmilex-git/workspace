# PR #3987 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3987](https://github.com/CUBRID/cubrid-testcases/pull/3987)
**제목:** [CBRD-27583] Re-baseline cci answers for bind-type-keyed XASL (cubrid#8213)
**작성자:** kiho-um
**HEAD SHA:** `82e76a205` (develop merge-base `fe236250e`, behind 0)
**JIRA:** CBRD-27583 / 엔진 PR cubrid#8213 (MERGED 10-28, 52193efa9)
**TC PR:** TC 전용 PR (sql_by_cci `.answer_cci` 25개 갱신 + 3개 신규, `.sql`/`.answer` 변경 없음)
**리뷰 일시:** 2026-11-02
**리뷰 결정:** TC PR #3987 Approve (본문에 플랜 누락 원인 정정 제안 1건, NIT 2는 미게시)

> **TL;DR** (Non-blocking): 28개 CCI 답지는 develop(309265e6d) optdebug 빌드의 sql_by_cci 출력과 187/187 일치하고, merge-base 답지로는 바로 이 28건만 NOK입니다. 본문이 Case 8 플랜 누락을 "CTP 드라이버 제약"으로 추정한 것은 틀렸고, CBRD-27583 사양 9/11(값 없는 PREPARE는 플랜 없음)의 결과입니다.

## Summary

- **변경 요약**: CBRD-27583 이후 CCI 경로 답지 25개를 재기준하고, `.answer_cci`가 없던 3개(cbrd_27583/04, /10, cbrd_27644)를 추가
- **주요 이슈**: PR 본문의 플랜 누락 원인 설명 (답지 자체는 맞음)
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)

1. PR 본문 "참고로 ... CTP 드라이버 쪽 제약으로 추정" 문단 -> 원인이 엔진입니다. sql_by_cci는 `cci_get_query_plan`으로 플랜을 받는데, CCI(`qe_get_query_info`)는 SQL 텍스트를 보내고 CAS(`fn_get_query_info`)는 그 텍스트를 바인드 값 없이 다시 컴파일한 뒤 `ER_UCI_TOO_FEW_HOST_VARS`를 무시하고 플랜 파일을 읽습니다. CBRD-27583 이후 문자열 바인드 자리가 있는 문장은 값 없는 컴파일에서 플랜을 만들지 않으므로(ADR 0028 사양 9/11) 빈 플랜이 옵니다.
   근거 (SA csql, `;plan simple`, 값 없이 실행):
   ```
   pre-8213 2d925cb86 : c4 = ? / vc = ? / id = ?  -> 세 문장 모두 Query plan 출력
   develop 309265e6d  : c4 = ? / vc = ?          -> 플랜 없음,  id = ? -> 플랜 출력
   ```
   "바인드 직후 `--@queryplan`" 조합은 저장소 전체에서 이 한 곳뿐인 것도 맞습니다. 그래서 다른 CCI 답지에는 같은 차이가 없습니다.
2. NIT: `issue_9024_loose_index_scan/answers/_05_groupby_expression.answer_cci`가 갱신 후 `.answer`와 바이트 단위로 같습니다(diff 0줄). CTP는 `.answer_cci`가 없으면 `.answer`를 쓰므로 이 파일을 지워도 됩니다.

## TC PRs

시나리오 = PR #3811 JDBC 재기준과 같은 원인의 CCI 답지 차이.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 28개 파일이 엔진 출력과 일치 | head 82e76a205: 187/187 OK (14 dirs) | 충족 |
| 바꾼 파일이 실제로 깨져 있던 것 | merge-base fe236250e: NOK 28 = 변경 파일 28개 그대로 | 충족 |
| 차이가 JDBC 답지와 같은 원인 | 28개 모두 JDBC `.answer`와 `Error:` 코드 순서, 문장 수, 블록별 행 수가 같음; 블록 행 수 차이는 10번 Case 8 플랜 블록 1개뿐 | 충족 |
| 남은 차이는 표시 형식뿐 | NUMERIC `1.00`->`1.0` (`trimnumeric`), DATETIME `.0` 유무, NULL 타입 열의 `1.5000000000000000`, BIT `AB`->`4142` (CCI는 문자 바이트를 바인드) | 충족 |

파일 검토: `.sql` 변경 없음(헤더 `;` 해당 없음), 신규 3개 모두 짝 `.sql`/`.answer`가 develop에 있음. 판정: Approve.

## Runtime Verification

| 실행 | 빌드 | 테스트케이스 ref | 결과 |
|---|---|---|---|
| head | develop 309265e6d optdebug (#8213 포함) | 82e76a205 | 187 OK / 0 NOK, 코어 0 (`sql_by_cci-20261102T105421Z-1403890`) |
| merge-base | 같음 | fe236250e | 159 OK / 28 NOK (= 변경 28개), 코어 0 (`sql_by_cci-20261102T105542Z-1409925`) |
| 참고: #8317 머지 후 | CBRD-27679 cubrid#8317 head 20e8d5bc1 optdebug | 82e76a205 | 115 OK / 72 NOK, 전부 표시 형식. 이 PR 파일 20개 + TC #3929가 이미 갱신하는 52개 (`sql_by_cci-20261102T105733Z-1416736`) |

develop 309265e6d 이후 develop 커밋 5개(#8309 등)는 이 14개 디렉터리를 돌리지 않았습니다. release 빌드는 돌리지 않았습니다(답지 표시 비교라 assert와 무관).
