# PR-3642 post-ready comments

## CUBRID/cubrid-testcases#3642

- event: APPROVE (조건: CUBRID/cubrid#8102 `/run sql` 에서 cbrd_25717 14건 통과, 나머지 실패는 develop 기존 실패뿐)
- commit_id: 232905aafccc0cde4d40d4a5d6dc508112675c97

### top-level body

CUBRID/cubrid#8102 의 tc/pr-8102 에 이 커밋들을 올려 /run sql 로 확인했고 cbrd_25717 14건 모두 통과했습니다.
NIT: 제목의 `Revies` 는 `Revise` 오타인 것 같습니다.

### inline 1: sql/_36_guava/cbrd_25717/cases/cbrd_25717_nl_baseline.sql:20 (RIGHT)

NIT: develop 에는 `hjoin_assign_build_probe` 가 없고, 빌드 측 선택은 `hjoin_init_context` 에 있는 것 같습니다.
```suggestion
 *       only falls back to page_cnt when the counts tie (hjoin_init_context); with both
```
