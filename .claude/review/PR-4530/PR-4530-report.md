# PR #4530 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4530](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4530)
**제목:** [CBRD-27365] Supplement the DBLink string-bind testcase
**작성자:** zionyun
**HEAD SHA:** `6481ac008131` (TC 전용 PR, 엔진 수정 CUBRID/cubrid#8120 `80f9b5f85` 은 develop 에 머지됨)
**JIRA:** CBRD-27365 / 연관: CUBRID/cubrid#8120, private-ex#4334 (머지된 원 TC)
**TC PR:** private-ex#4530 (이 PR, `shell/_06_issues/_26_2h/cbrd_27365`) / cubrid-testcases 변경 없음
**리뷰 일시:** 2026-10-26
**리뷰 결정:** #4530 Approve (review 5647900349, 2026-10-26)

> **TL;DR** (Non-blocking): case 5(빈 문자열)는 수정 전 빌드에서 NOK, 수정 후 빌드에서 OK 로 갈리고, NOK 진단이 result 파일에 남는다. bagus-kim 의 REPLACE ... SELECT case 6 제안은 case 1 과 같은 바인딩 경로라 확인 범위를 늘리지 않는다.

## Summary

- **변경 요약**: 빈 문자열 바인딩 case 5 추가, NOK 시 비교 쿼리와 덤프를 `write_nok <file>` 로 result 파일에 붙임, 헤더 주석의 `;` 제거
- **주요 이슈**: 없음 (기존 스레드의 `cat /dev/null` 제안은 미반영, 작성자 답글 없음)
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)
- bagus-kim 코멘트 6408967162 (REPLACE ... SELECT 를 case 6 으로 추가) — REPLACE 는 INSERT 와 같은 바인딩 코드를 탄다. `qexec_execute_remote_dml_sink` (원격 DML 을 행마다 바인딩해 보내는 sink) 는 두 종류를 한 분기에서 처리한다:
  ```c
  case DBLINK_DML_INSERT:
  case DBLINK_DML_REPLACE:
    ... qexec_collect_remote_insert_vals (s_id, xasl_state, insert, val_no)
    ... dblink_dml_execute_row (thread_p, &dblink_state, insert->vals, val_no, &row_affected)
  ```
  다른 곳은 `dblink_build_insert_sql` 이 붙이는 문장 앞부분(`REPLACE INTO`) 하나다. 수정 전 `fbaee9282` 도 같다. 그래서 case 6 은 case 1 이 보는 `dblink_bind_dbval_to_param` 경로를 한 번 더 지난다. 헤더 17행 "Every DBLink path ... is checked" 는 #4334 의 문장이고, REPLACE 가 case 1 과 같은 경로라는 한 줄을 헤더에 적는 편이 테이블과 case 추가보다 작다.

## JIRA -> Engine PR

엔진 PR #8120 은 이미 머지되어 이 리뷰의 판정 대상이 아니다. TC 가 #8120 의 영향 경로를 덮는지만 아래 표에서 본다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 원격 INSERT ... SELECT, 뒤에 문자열 컬럼 | case 1 | 통과 |
| 원격 REPLACE ... SELECT | case 1 과 같은 sink, 같은 바인딩 (위 Findings) | 통과 |
| 원격 DELETE ... IN (로컬 서브쿼리), 뒤에 NULL 튜플 헤더 | case 2 | 통과 |
| 상관 DBLink 서브쿼리 키 | case 3 | 통과 |
| NUL 바이트를 품은 문자열 | case 4 | 통과 |
| 빈 문자열 (이 PR 추가) | case 5 | 통과 |

TC 파일 검토: shell case 라 answer 파일이 없고 `write_ok`/`write_nok` 로 판정한다. 헤더는 `:<<'END'` heredoc 이라 CTP 문장 분리 대상이 아니며 `;` 도 제거됐다. PR 본문의 "case 5 fail->pass 재현" 은 아래 실행과 맞다.

## Runtime Verification

CI optdebug 아카이브 빌드 두 개에서 `just ctp shell _06_issues/_26_2h/cbrd_27365`, `TC_REF=refs/pull/4530/head` (`6481ac008131`), 코어 0개:

| 빌드 | case 1-5 | 비고 |
|---|---|---|
| 11.5.0.2653-fbaee92 (#8120 직전 develop) | NOK x5 | case 5 원격 값 `hex(name)='050451515151515151'` (기대값 빈 문자열) |
| 11.5.0.2725-a96dbce (#8120 포함 develop) | OK x5 | |

수정 전 실행의 result 파일에 각 case 의 비교 쿼리 결과와 원격 덤프가 붙어 있다 (변경 2 확인). 실행 디렉터리 `ctp-run-out/workspace/shell-20261026T054617Z-{3741151,3740698}`. gha-ci 실행은 아직 없다.

## Existing Comments

| 코멘트 | 내용 | 상태 |
|---|---|---|
| bagus-kim 4374169048/4374177104 (line 64) | 추가 로그 없이 `check_pass` 를 부르면 `cat "$@"` 가 stdin 을 기다려 멈춤, `cat /dev/null "$@"` 제안 | head 미반영, 작성자 답글 없음 |
| bagus-kim 6408967162 | REPLACE ... SELECT case 6 제안 | 답글 없음 (위 Findings) |
