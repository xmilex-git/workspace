# PR-3987 post-ready comments

## CUBRID/cubrid-testcases#3987

- review event: APPROVE
- commit_id: 82e76a205d91d384ebadbf57958bc0922901a2bd
- inline comments: 없음

### top-level body

develop(309265e6d) optdebug 빌드로 sql_by_cci 를 변경된 14개 디렉터리에 돌려 봤습니다. 이 PR 헤드에서는 187건이 모두 OK 이고, merge-base 답지로는 바뀐 28개 파일이 그대로 NOK 입니다. 28개 모두 JDBC 답지와 에러 코드 순서, 문장 수, 블록별 행 수가 같고, 나머지 차이는 CCI 드라이버의 표시 형식(NUMERIC 끝자리 0, DATETIME `.0`)이었습니다.

본문의 Case 8 플랜 누락 설명은 드라이버 제약이 아니라 엔진 동작으로 고치는 것은 어떨까요? sql_by_cci 는 `cci_get_query_plan` 으로 플랜을 받는데, CCI 는 SQL 텍스트를 보내고 CAS(`fn_get_query_info`)는 그 텍스트를 바인드 값 없이 다시 컴파일해서 플랜을 읽습니다. CBRD-27583 이후에는 문자열 바인드 자리가 있는 문장을 값 없이 컴파일하면 플랜을 만들지 않고 첫 EXECUTE 에서 만들기 때문에 빈 플랜이 옵니다. csql 에서 값 없이 `;plan simple` 로 보면 변경 전 develop 은 `c4 = ?`, `vc = ?`, `id = ?` 모두 플랜을 내고, 지금 develop 은 `id = ?` 만 냅니다. 답지는 지금 그대로 맞습니다.
