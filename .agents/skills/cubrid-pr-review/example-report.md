# Example report

Reached from SKILL.md Step 5. A short finished report looks like this — use it as a shape anchor, not a template to fill out verbatim. The example below is about 40 lines, well under half the budget; for a typical PR this is plenty.

```markdown
# PR #6950 코드 리뷰 보고서

**PR:** [CUBRID/CUBRID#6950](https://github.com/CUBRID/CUBRID/pull/6950)
**제목:** [CBRD-26583] Re-enable OOS OID replacement in heap records
**작성자:** xmilex-git
**HEAD SHA:** `abc1234` (develop merge-base `def5678`)
**JIRA:** CBRD-26583 (Improve, Confirmed) / 연관: 없음
**TC PR:** CUBRID/cubrid-testcases#3001 (`tc/pr-6950` `aaa1111`) / cubrid-testcases-private-ex#4001 (빈 draft)
**리뷰 일시:** 2026-05-06
**리뷰 결정:** 엔진 PR Request changes / TC PR #3001 Approve

> **TL;DR** (Blocking): `heap_record_replace_oos_oids` 에러 경로에서 `pgbuf_unfix` 누락으로 페이지 핀 누수 가능. 해당 한 곳만 고치면 머지 가능.

## Summary

- **변경 요약**: heap 레코드의 OOS OID 치환 로직을 `feat/oos`에 다시 활성화
- **주요 이슈**: `heap_file.c:12345` 에러 경로 페이지 핀 누수
- **확인 필요 사항**: 없음

---

## Findings

### Blocking (must fix)
- `src/storage/heap_file.c:12345` — `er_set` 후 `goto exit` 전에 `pgbuf_unfix(thread_p, page_p)` 누락. 해당 함수 진입에서 `pgbuf_fix` 했으므로 모든 종료 경로에서 unfix 필요. 근거: 같은 함수 line 12302의 정상 종료 경로에는 unfix 존재.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result (OOS 레코드 갱신 후 OID 일치) | test_result.md T1 | 충족 |
| design 변경 1: 치환 재활성화 | 구현, 에러 경로 누수 | 부분 (Blocking 1) |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| T1 OOS 레코드 갱신 | test.md T1, #3001 | 통과 |

## Runtime Verification

- CI: build/sql/medium 통과(run 123), `cbrd_26583.sql` ok. 새로 돌린 실행 없음.
```

(Existing Comments was omitted because no unresolved top-level comments existed. `Non-blocking` and `Questions for the author` subsections are also omitted because they had no items.)

