# TC backport PR #3948 / #4648 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3948](https://github.com/CUBRID/cubrid-testcases/pull/3948) / [CUBRID/cubrid-testcases-private-ex#4648](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4648)
**제목:** [CBRD-27759] Backport ... sql testcase for derived-input left joins / [CBRD-27772] Backport ... shell testcases for hash list scan temporary space limits
**작성자:** zionyun
**HEAD SHA:** #3948 `cb622267c` / #4648 `7784bc5af` (base `release/11.4`, 엔진 head `52d4301a2`)
**JIRA:** CBRD-27759 (엔진 backport #8291 = `46212adcd`), CBRD-27772 (Test, 엔진 backport #8289 = `90126a92d`); 둘 다 `52d4301a2`에 포함
**원본 TC:** develop `cbrd_27759`, `cbrd_27759_chain` (#3875) / private-ex#4557
**리뷰 일시:** 2026-10-30
**리뷰 결정:** #3948 Approve + inline 1 (Case 12 주석), #4648 Approve

> **TL;DR** (Non-blocking): 두 PR 모두 develop TC와의 차이가 11.4 엔진 차이만큼만 바뀌었다. sql answer는 trace 줄만, shell은 한도값(640/896)과 적재 순서만 바뀌었다. #3948의 Case 12 주석 한 곳이 11.4 코드와 맞지 않는다.

## Summary

- **변경 요약**: develop TC 두 묶음을 `release/11.4`로 옮기면서 sql answer의 trace 줄, shell의 임시 공간 한도와 probe 판정 인자를 11.4에 맞췄다.
- **주요 이슈**: `cbrd_27759.sql` Case 12 주석이 "CTE scan이라 수정 경로를 타지 않는다"고 쓰지만, 11.4의 CTE 참조 spec도 클래스가 없어 Case 11과 같은 가드에서 돌아간다.
- **확인 필요 사항**: 없음

---

## Findings

### Non-blocking (should consider)

1. `sql/_13_issues/_26_2h/cases/cbrd_27759.sql:107-108` — 주석은 Case 12가 CTE scan이라 "derived-input path"를 타지 않고 Case 11만 그 경로를 덮는다고 쓴다. 11.4의 `pt_resolve_spec_to_cte()`는 CTE 참조 spec의 `entity_name`을 NULL로 바꾼다(`node->info.spec.entity_name = NULL;`). 그래서 Case 12의 `rhs s`도 backport된 `qo_reduce_outer_joined_tables()`의 `if (!PT_SPEC_IS_ENTITY (spec)) return query;` (클래스 없는 오른쪽 입력은 조인 제거 후보에서 뺌)에서 Case 11과 똑같이 돌아간다. develop 헤더의 "Case 12: CTE right input preserves duplicate matches"는 11.4에서도 그대로 맞다. 첫 줄(11.4는 CTE를 inline view로 펼치지 않아 trace가 다르다)만 남기고 둘째 줄은 빼는 편이 맞다. PR 본문의 같은 설명도 마찬가지다.

## JIRA -> Engine PR

엔진 PR 리뷰가 아니라 TC backport 리뷰라서 생략한다. 두 엔진 backport(#8291, #8289)는 이미 `release/11.4`에 merge됐고 `52d4301a2`에 포함된다(`git merge-base --is-ancestor` 확인).

## TC PRs

develop 원본과 PR 파일을 파일별로 diff 했다(차이 줄 수 = `diff | grep -c '^[<>]'`).

| 파일 | 차이 줄 | 내용 | 판정 |
|---|---|---|---|
| `cbrd_27759.answer` | 20 | GROUPBY `readrows` 삭제, UNION `parallel workers` 줄 삭제, Case 12 plan/trace가 CTE 형태. 행 값 변화 없음 | 충족 |
| `cbrd_27759_chain.answer` | 4 | GROUPBY `readrows` 2곳 삭제. 행 값 변화 없음 | 충족 |
| `cbrd_27759.sql` | 2 | Case 12 `--` 주석 2줄 (`;` 없음) | 부분 (Finding 1) |
| `cbrd_27759_chain.sql` | 0 | - | 충족 |
| `cbrd_27772_control.sh` | 0 | - | 충족 |
| `cbrd_27772_{create,limit}.sh` | 13씩 | 한도 512/768 -> 640/896, 한도 적용을 적재 뒤 재시작으로 이동, probe에 `before`/`during` 인자 | 충족 |
| `ResourceProbe27772.java` (2벌) | 4씩 | 판정을 페이지 수 대신 인자로: `before`면 `readrows == 0`, `during`면 `readrows > 0`. 두 벌 동일(`cmp`) | 충족 |

- shell 한도 판단: probe가 에러 메시지의 페이지 수(`640 pages`/`896 pages`)와 `SCAN (hash temp(f)` 의 `readrows`로 멈춘 시점을 직접 확인한다. 그래서 한도가 의도한 구간을 벗어나면 TC가 NOK를 낸다. develop 판정(`512 && rows != 0`, `768 && rows <= 0`)과 같은 의미다.
- 재시작으로 적재 중 생긴 임시 temp volume이 지워져, develop 주석 "Fresh DB: ... must not preallocate its temp volumes"의 의도도 유지된다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 27759 non-class 오른쪽 입력 컴파일 크래시 | `cbrd_27759` Case 1-8, 13 | 충족 |
| 27759 체인 LEFT JOIN 행 누락 | `cbrd_27759_chain` Case 1-14 | 충족 |
| 27772 hash 테이블 생성 시점 한도 초과 | `cbrd_27772_create` (640, `before`) | 충족 |
| 27772 hash 채우는 중 한도 초과 | `cbrd_27772_limit` (896, `during`) | 충족 |

판정: 두 TC PR 모두 승인 가능. #3948은 Finding 1 주석만 정리 권장.

## Runtime Verification

| 실행 | 빌드 | 결과 |
|---|---|---|
| `cbrd_27759.sql` 전체, SA | 11.4.6.1963-0e7d3c1 release (수정 전) | Case 1에서 csql SIGSEGV (rc=139) -> fail-before 확인 |
| `cbrd_27759_chain.sql` 전체, SA | 같은 빌드 | Case 1이 `1 1 1` 한 행만 반환(answer는 `2 1 null` 포함 두 행) -> fail-before 확인 |
| Case 11, 12 단독, SA | 같은 빌드 | 둘 다 수정 전에도 4행(정답). 두 케이스는 회귀 확인용이지 fail-before가 아님 |
| 작성자 local | 11.4.6.1991-52d4301 release | sql 2건 OK, shell create/limit OK, 1963에서 create NOK(엉뚱한 에러)/limit NOK(core) |
| `just ctp sql` 2건, `TC_REF=refs/pull/3948/head` (`cb622267c`) | `52d4301a2` release 직접 빌드 (11.4.6.1991, `libcubrid.so` sha256 `77b788ed...`) | `cbrd_27759` OK, `cbrd_27759_chain` OK, core 0 |
| `just ctp shell` 3 dir, `TC_REF=refs/pull/4648/head` (`7784bc5af`) | 같은 빌드 | control/create/limit 각 3/3 OK, core 0. create: `-596`, `640 pages`, `file_hash_readrows=0` (2회). limit: `-596`, `896 pages`, `file_hash_readrows=126380` (2회). 두 경우 모두 이후 세션/observer 트랜잭션 유지 |

- 11.4에는 optdebug preset이 없어(`CMakePresets.json`: release/debug/coverage/profile) release로만 확인했다. assert 경로와 debug 빌드의 한도 구간은 확인하지 않았다.
- 11.4 서버는 `parallelism` 파라미터를 모른다. 그래서 install conf를 11.4 템플릿으로 되돌리고 `CTP_PIN_PARAMS=0`으로 돌렸다(첫 시도는 서버 기동 실패로 무효).
- #4648에는 CI check가 없고, #3948은 Greptile만 있다.

## Re-run on 11.4.7 (2026-11-02)

- release/11.4 head `1df4af4bc` (VERSION 11.4.7, 11.4.7.1994-1df4af4) release build, libcubrid sha256 `1a475e5c...`. Same TC heads.
- `just ctp sql` 2/2 OK, `just ctp shell` 3/3 OK, core 0. create: -596 `640 pages`, readrows 0 (2 attempts). limit: -596 `896 pages`, readrows 126380 (2 attempts).
- Posted: #3948 APPROVE 5731853743 (+ Case 12 inline), #4648 APPROVE 5731853849.
