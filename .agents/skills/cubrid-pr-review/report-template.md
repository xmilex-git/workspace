# Report template

Reached from SKILL.md Output Format. The rules for each section are in SKILL.md (Top-of-Report Summary Rules, Findings Rules, Approval Criteria).

```markdown
# PR #<NUMBER> 코드 리뷰 보고서

**PR:** [<OWNER>/<REPO>#<NUMBER>](https://github.com/<OWNER>/<REPO>/pull/<NUMBER>)
**제목:** <PR title>
**작성자:** <author>
**HEAD SHA:** `<head_sha>` (develop merge-base `<sha>`)
**JIRA:** <CBRD-XXXXX (type, status)> / 연관: <linked issues, 없으면 없음>
**TC PR:** <CUBRID/cubrid-testcases#N (`tc/pr-<NUMBER>` sha)> / <CUBRID/cubrid-testcases-private-ex#M, 또는 PR 없음 + 변경 여부>
**리뷰 일시:** <today's date>
**리뷰 결정:** <grill에서 정한 PR별 리뷰 이벤트: 엔진 PR, TC PR 각각>

> **TL;DR** (<Verdict>): 1-3 문장으로 결론과 핵심 이슈 1-2개.

## Summary

- **변경 요약**: 한 줄로 PR이 무엇을 바꾸는지
- **주요 이슈**: 가장 중요한 1-2 항목 (없으면 "없음")
- **확인 필요 사항**: 작성자가 확인/응답해야 할 질문 (없으면 "없음")

---

## Findings

<see Findings Rules below. 발견 사항이 전혀 없으면 이 섹션 본문을 `없음` 한 줄로 대체하고 아래 세 subsection은 모두 생략한다. 일부 카테고리만 비어 있다면 채워진 카테고리만 남기고 비어 있는 subsection은 통째로 생략한다.>

### Blocking (must fix)
<버그, 메모리/동시성 안전성 위반 등 머지 전에 반드시 수정되어야 하는 항목.>

### Non-blocking (should consider)
<수정을 권하지만 머지를 막지는 않는 사항.>

### Questions for the author
<작성자에게 확인이 필요한 질문.>

## JIRA -> Engine PR
<Approval Criteria의 JIRA 기준 문장, 항목별 표, 판정 한 줄. JIRA 없으면 섹션 생략.>

## TC PRs
<Approval Criteria의 TC 기준 문장, 시나리오별 표, TC 파일 검토 한두 줄, 판정 한 줄.>

## Runtime Verification
<재사용한 CI 증거와 새로 돌린 실행(빌드 sha와 종류, 테스트케이스 ref, 결과). 새로 돌린 것이 없으면 CI 증거만.>

## Existing Comments
<PR에 달려 있고 작성자/메인테이너 답변이 없는 top-level 코멘트(`in_reply_to_id == null` 인 것 중 author/maintainer 답글이 없는 것)만 짧은 표로 정리. 없으면 섹션 생략.>
```

