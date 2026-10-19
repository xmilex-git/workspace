# PR #8176 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8176](https://github.com/CUBRID/cubrid/pull/8176)
**제목:** [CBRD-27582] Keep bound host variable values out of cached UPDATE/DELETE/MERGE XASL
**작성자:** shparkcubrid
**HEAD SHA:** `d3c1a2245` (develop merge-base `4adcd4090`)
**JIRA:** CBRD-27582 (Correct Error, Open, Minor) / 연관: 없음 (design.md, test.md 첨부 없음)
**TC PR:** CUBRID/cubrid-testcases#3771 (`tc/pr-8176` `09251e10e`) / cubrid-testcases-private-ex#4450 (`tc/pr-8176` `4790c7988`, 변경 없는 빈 draft)
**리뷰 일시:** 2026-10-16
**리뷰 결정:** 엔진 PR Approve(본문에 Finding 1, 2026-10-16 게시 review 5542918887) / TC #3771 Approve(위치 이동과 JDBC+통계 케이스는 참고 inline 2건, review 5542919022) / private-ex #4450 리뷰 없음

> **TL;DR** (Non-blocking): 엔진 수정은 맞고, TC가 merge-base에서 FAIL, head에서 PASS한다. 다만 develop에는 ALTER 없이 재현되는 경로가 하나 더 있다. 통계가 있는 테이블에 JDBC 바인드로 `UPDATE ... SET n = 10 + ? WHERE id = ?`를 실행하면 첫 값이 계속 저장된다(#7476 회귀). 이번 수정이 이 경로도 고치지만, PR 설명의 "회귀 아님"과 TC 범위에는 빠져 있다.

## Summary

- **변경 요약**: `pt_translate_dml_query_unbound()`를 추가해 UPDATE/DELETE/MERGE XASL 생성기 4곳의 `mq_translate()`를 `set_host_var = 0`(호스트 변수 값을 아직 모르는 것으로 취급)으로 실행
- **주요 이슈**: 엔진 코드 결함 없음. PR 본문의 영향 범위와 회귀 판단이 실제와 다름. TC #3771의 위치와 JDBC+통계 케이스는 참고로 남김
- **확인 필요 사항**: PR 본문과 JIRA에 #7476 경로를 반영할지

---

## Findings

### Non-blocking (should consider)

1. PR 본문의 "회귀 아님"과 "ALTER 없이는 ... 드러나지 않았습니다"는 develop에서 맞지 않는다. ALTER 없이도 재현된다. 검증 표의 "JDBC 단독 (ALTER는 다른 연결)" 행은 통계 없는 조건이라 이 경로를 밟지 않는다.
   - 재현: `update statistics on rj with fullscan`(히스토그램은 기본 수집)을 한 뒤 JDBC 바인드로 `update rj set n = 10 + ? where id = ?`를 (1,1), (7,2), (5,3) 순서로 실행.
   - 결과: merge-base는 n = 11, 11, 11, head는 11, 17, 15. 통계가 없는 같은 실행과 SQL-level PREPARE/EXECUTE는 두 빌드 모두 정상.
   - 원인: `db_execute_and_keep_statement_local`의 bind-peeking(바인드 값 없이 고른 `HV_PRED_PLAN_UNPEEKED` 플랜을 첫 실행에서 실제 값으로 다시 고르는 것)이 `set_host_var = 1`인 채로 `do_replan_statement_with_bind_peek` -> `do_prepare_statement`를 부른다. 같은 상수 접기가 일어나고, 결과가 `?` 텍스트 키로 캐시 엔트리를 덮어쓴다.
   - 이 경로는 #7476(CBRD-26959, 2026-08-14)이 넣었고 release/11.4에는 없다.
   - 영향: "PREPARE 뒤 ALTER"라는 드문 조건이 없어도, 통계가 있는 테이블에 대한 평범한 JDBC UPDATE/DELETE가 첫 실행 값으로 굳는다. 이번 diff가 이것도 고치므로 코드 변경은 필요 없다. 바로잡을 것은 PR 본문과 JIRA의 회귀 판단·영향 범위다.

## JIRA -> Engine PR

기준: JIRA 재현 조건에서 Expected Result가 성립하는지, 수정안이 구현됐는지 본다. design.md/test.md가 없으므로 담당자 원인 분석 코멘트(2026-10-15)를 수정안으로 본다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: d 02/01 -> 02/02 -> 02/05, n 11 -> 17 | TC case 1, 2. merge-base NOK(02/01 x3, 11 -> 11), head OK | 충족 |
| 수정안: XASL 생성기의 재번역을 `set_host_var = 0`으로 | `pt_translate_dml_query_unbound`, 4곳 교체 | 충족 |
| 추가 영향 범위(WHERE, MERGE UPDATE/INSERT, 다른 세션) | TC case 3-7, A/B 확인 | 충족 |

연관 이슈: JIRA 링크가 없다. CBRD-26959(#7476)는 ALTER 없는 경로를 만든 이슈이므로 링크와 원인 기록이 필요하다(Finding 1).

## TC PRs

기준: 시나리오는 엔진 PR 검증 표의 행이다(test.md 없음). TC PR 본문이나 변경 파일에 나오면 통과로 본다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 이슈 재현: SET d = DATE + ?, n = 10 + ? | #3771 case 1, 2 | 통과 |
| DELETE / UPDATE `WHERE n = 10 + ?` | case 3, 4 | 통과 |
| MERGE UPDATE `SET n = 50 + ?` | case 5 | 통과 |
| MERGE INSERT `VALUES (k, 10 + ?)` | case 6 | 통과 |
| 오염 뒤 다른 문장이 같은 텍스트 실행 | case 7(같은 연결에서 새 PREPARE) | 통과 |
| JDBC 단독(통계 있음) | 없음. develop에서 실패하는 경로(Finding 1) | 미충족(참고로 남김) |
| `max_plan_cache_entries=0` / `hostvar_peeking=yes` | 수정 뒤 회귀 점검(PR 표에 develop 결과 없음) | 해당 없음(회귀 점검) |
| `UPDATE ... ORDER BY id LIMIT ?`, `DELETE ... LIKE ? \|\| '%'` | 수정 뒤 회귀 점검(PR 표에 develop 결과 없음) | 해당 없음(회귀 점검) |

TC 파일 검토:
- case와 answer가 짝을 이루고, header에 `;`가 없다. 본문의 "develop FAIL / 수정 PASS" 주장은 A/B 실행과 일치한다(merge-base diff에서 7케이스 모두 첫 값).
- 위치: Correct Error 이슈의 TC는 `sql/_13_issues/_26_2h/cases/cbrd_27582.sql` + `answers/cbrd_27582.answer`에 둔다(QA 규칙 CUBRIDQA-1486). 지금은 `_36_guava/cbrd_27582/`에 있어 참고로 남긴다.
- JDBC+통계 케이스가 없다. `$int` 바인드로 리뷰용 r8176 J 형태를 넣으면 develop과 수정 빌드가 갈린다. 참고로 남긴다.
- private-ex #4450은 변경이 없다. TC Merge Gate 안내대로 닫으면 되고, 따로 리뷰할 것이 없다.

판정: #3771 승인. 위치 이동과 JDBC+통계 케이스는 참고 사항이다.

## Runtime Verification

- CI(gha-ci): build release/debug pass.
  - 38699337205는 TC init `ea4132f`로 돌아 새 케이스가 없다. medium/shell은 pass, sql은 2건 fail(cbrd_27596, cbrd_27624). 두 건은 merge-base에 들어 있는 #8145의 trace 출력 변경을 develop answer가 아직 반영하지 않은 것으로, 이 PR과 무관하다.
  - 38841030448 sql(TC `09251e10e`, 새 케이스 포함): 전체 pass. shard 09가 head `d3c1a2245` optdebug로 `cbrd_27582` ok(99ms).
- 빌드는 CI optdebug tarball을 썼다.
  - head: 11.5.0.2684-d3c1a22, libcubrid.so sha256 `73e757d9`
  - merge-base: 11.5.0.2683-4adcd40, `4a60dfc5`
- TC #3771(`PR=8176`, tc `09251e10e`): merge-base NOK(7케이스 모두 첫 값 고정), head OK. run `sql-20261016T024630Z-4032898` / `-4032899`.
- 리뷰용 r8176(TC_REF develop `6609d991b`, `--testcases-as-is`, ALTER 없음):
  - A/B/C(SQL-level PREPARE): 두 빌드 모두 정상
  - J(JDBC 바인드 + 통계): merge-base 11, 11, 11 / head 11, 17, 15
  - J0(JDBC 바인드, 통계 없음): 두 빌드 모두 정상
- csql -C로 SQL-level, ALTER 없는 probe(A, A2, B, C, D, E)를 돌렸다. 두 빌드 결과가 같고 모두 기대값이다.
