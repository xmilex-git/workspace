# PR #6466 코드 리뷰 보고서 (3차)

**PR:** [CUBRID/cubrid#6466](https://github.com/CUBRID/cubrid/pull/6466)
**제목:** [CBRD-25984] Support covered index scan and key filter on function indexes
**작성자:** HyunukLee
**HEAD SHA:** `f1f4f21ea` (develop merge-base `4e389935d`), 1차 리뷰 `05b46aefe` 이후 커밋 6개
**JIRA:** CBRD-25984 (Improve, 본문 11-06 갱신) / 연관: CBRD-26266
**TC PR:** CUBRID/cubrid-testcases#3865 (`7763f943d`, soheejung-cs Approve) / CUBRID/cubrid-testcases-private-ex#4551 (`57910d7f4`, 11-05 Approve 끝)
**리뷰 일시:** 2026-11-06 (1차 보고서: `PR-6466-r1-report.md`)
**리뷰 결정:** 엔진 PR COMMENT(top-level + H1 inline, 11-04 CHANGES_REQUESTED 유지) / TC #3865 REQUEST_CHANGES(기존 답안 8건 재기준선, `basic_order` 인덱스 선택 질문, signed zero TC) / #4551 리뷰 없음 / soheejung-cs 스레드 2건 답글 없음

> **TL;DR** (작성자 확인 필요): 1차의 MRO 실패와 soheejung-cs 지적 7건은 모두 고쳐졌고, TLA+ 모델(mutant 13개, TLAPS 70/70)도 그 수정들을 확인했다. 남은 것은 하나다. `-0.0` 과 `0.0` 은 비교하면 같아서 B-tree 키 하나로 합쳐지는데, 함수 결과 도메인 관문이 DOUBLE 은 거르지 않는다. 그래서 `ceil(d)` 같은 인덱스에서 투영과 키 필터가 develop 과 다른 값을 낸다. `NO_COVERING_IDX` 를 줘도 같다(새 비커버링 키 필터 경로).

## Summary

- **변경 요약**: 함수 인덱스 키의 함수 결과를 예약 attr id(`FUNC_INDEX_RESULT_ATTRID`)로 읽어 커버드 스캔과 키 필터에 쓴다. 이번 라운드에서 비커버링 함수 인덱스의 키 필터 허용(0cb8b988a), 일반 인덱스 커버링(f1f4f21ea), 세션 의존 식 관문(a7185cdf4), 함수 결과 도메인·sarg 분류·자기 조인 관문(814233513), 단일 컬럼 키 검사(18e0dd3e3), MRO 수정(d7ce3af72)이 들어왔다.
- **주요 이슈**: 부호 있는 0(signed zero)이 키 하나로 합쳐져 결과가 develop 과 다르다(H1).
- **확인 필요**: 이 결함을 이 PR 에서 막을지, 기존 결함으로 기록할지. develop 의 일반 DOUBLE 컬럼 커버링에도 같은 합침이 있다.

## Findings

### Questions for the author

- `src/optimizer/query_graph.c` `qo_is_func_index_key_result_exact ()` — 함수 결과 도메인 관문(`TP_TYPE_NOT_SUPPORT_COVERING`, `allow_index_opt`)이 DOUBLE·FLOAT 를 통과시킨다. B-tree 는 `-0.0` 과 `0.0` 을 같은 키로 보고 먼저 들어온 행의 값만 남기므로(H1), 커버드 투영과 키 필터가 다른 행의 부호를 읽는다.

  ```sql
  create table t (i int, d double);
  create index ix on t (i, ceil(d));
  insert into t values (1, -0.5), (1, 0);
  select i, cast(ceil(d) as varchar(30)) from t where i = 1;                    -- develop '-0','0' / PR '-0','-0'
  select count(*) from (select i from t where i = 1 and cast(ceil(d) as varchar(30)) = '0') x;  -- develop 1 / PR 0
  select /*+ NO_COVERING_IDX */ i from t where i = 1 and cast(ceil(d) as varchar(30)) like '-%'; -- develop 1행 / PR 2행
  ```

  셋째 문장은 비커버링 스캔인데도 키 필터(`[cast(ceil(d)...) like '-%']`)가 키 값을 읽어 2행이 된다. `ceil`·`round`·`trunc` 가 -1 과 0 사이 음수에서 `-0` 을 내므로 보통 데이터에서 나온다. develop 의 일반 컬럼 `(i, d)` 커버링도 같은 두 값을 `-0` 두 번으로 돌려준다(기존 결함). 이 PR 은 같은 결함으로 들어가는 새 길(함수 결과, 비커버링 키 필터)을 연다.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| A/C 1: Q2, Q4 커버드 + 키 범위/필터 | trace `cover` 런 `cover=1 icover=1 kf=1 rsel=1`, KeyRead·KfRead | 충족 |
| A/C 2: 커버링 결과가 `NO_COVERING_IDX` 와 항상 같음 | soheejung-cs 지적 5건 재현 SQL 은 수정. `ceil(d)` signed zero 는 다름 | 부분 (Question 1) |
| A/C 3: 비커버링 키 필터 결과가 `using index none` 과 같음 | 14쌍(84행) 같음. signed zero 키 필터는 다름 | 부분 (Question 1) |
| A/C 4: MVCC 재평가·클릭 카운터·CONNECT BY·merge/hash 입력 | 모델 `heapStmt`/`listfile` 관문, trace `upd`·`hash` 런 | 충족 (모델+trace, CTP 미실행) |
| A/C 5: 함수식 안 쓰는 함수 인덱스는 develop 판정 | `NoFAsDevelop` TLC·TLAPS, trace `upd` `cover=1` | 충족 |
| A/C 6: 일반 인덱스 `(d)` 커버링 | trace `plain` `func=0 cover=1 icover=1` | 충족 |
| A/C 7: INDEX_LS + 해시·머지 assert 없음 | `index_loose` 해제(9887 `pt_uncover_func_index_scans`), mutant `loose-kept` 가 잡음 | 충족 (CTP 미실행) |
| DoD: CI 통과 | 헤드 `f1f4f21ea` 에 gha-ci 실행 없음(마지막 `/run all` 10-29) | 미충족 (기록만) |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 1차 MRO 꼴(`IN` + `ORDER BY ... LIMIT`, `FOR ORDERBY_NUM`) | #3865 `[11-1]`~`[11-4]` | 통과 |
| soheejung-cs 7건(자기 조인, FOR UPDATE·DELETE, TZ·`utf8_en_ci`, 외부 조인 ON/WHERE, 루스 스캔, 세션 시간대·언어, 일반 인덱스) | #3865 `[12-1]`~`[12-12]` | 통과 |
| 비커버링 키 필터(뷰 병합 괄호, raw 인자 옆 conjunct, UPDATE/DELETE) | #3865 `[13-1]`~`[13-7]` | 통과 |
| signed zero | 없음 | 누락 (Question 1 과 함께) |
| 0cb8b988a 이후 기존 답안 | 8건 미갱신(플랜 줄만) | 미충족 (TC Finding) |
| shell `bug_bts_7459` | #4551 (11-05 Approve) | 통과 |

- 1차에 적은 #3865 머리 주석의 `;` 는 사라졌다(`^--` 줄에 `;` 0건).
- #3865 `7763f943d` 를 head optdebug 로 돌리면 기존 답안 8건이 플랜 줄만 달라 NOK 다(`bug_bts_7088`, `cbrd_25164`, `cbrd_24795`, `cbrd_26266`, `function_based_index_select_basic_{group,join_003,order,where}`). 모두 0cb8b988a 의 비커버링 키 필터로 `sargs` -> `filtr`(`cbrd_24795` 는 `key filter:` 추가) 이고 결과 행은 같다. `function_based_index_select_basic_order` 는 고르는 인덱스도 `i_t?_a` -> `i_t?_g` 로 바뀐다. PR 본문은 "기존 TC 답안 9건" 이라 적고 있어, 이 8건 재기준선이 빠졌다.

## TLA+ Verification

TLA+ 검증: 실패 (H1 하나) — `.claude/review/PR-6466/tla/func-index-cover/` (모듈 둘)
- 속성(`FuncIdxCover`, 판정표): C1 커버링·라우팅(JIRA Q2/Q4), C2 develop 과 같은 값(PR Remarks, 리뷰 스레드 5건), C3 비커버링 키 필터, C4 heap 재평가 문장, C5 리스트 파일 커버 해제·루스, C6 일반 인덱스 커버, C7 함수식 안 쓰면 develop 판정: TLC 통과, TLAPS 증명(signed zero 를 뺀 환경). signed zero 환경에서 C2 실패(H1).
- 속성(`FuncIdxMvcc`, 동시 UPDATE·롤백·vacuum): C8 커버드 투영과 비커버링 키 필터가 스냅샷 heap 버전으로 develop 이 내는 답과 같음: TLC 통과, TLAPS 증명(갱신 횟수 전 범위).
- 결함: H1 signed zero. 코드 cfg `negzero` 실패(`Equiv`), 런타임 재현(optdebug `448482cb`·release `c1ce40fa`, develop CI debug `8ebe311e`, SA), 후보 수정 cfg `fix-negzero`(결과 관문에 FLOAT/DOUBLE 추가) 통과.
- mutant: 16개 모두 위반 검출(판정표 13: merge-base, 05b46aefe 의 sarg 분류·자기 조인·관문 순서·MRO -1, 도메인·세션 관문, 루스, 커버 해제, routable, 키 필터 exact, a7185cdf4 키 필터 금지, 18e0dd3e3 일반 인덱스 / MVCC 3: 항목 스냅샷 검사 없음, heap 최신 버전 읽기, vacuum 이 활성 스냅샷 무시) / 살아남은 mutant: 없음.
- 경계: 판정표는 입력 불리언 18개 전부 x 행 2(scale 3); MVCC 는 갱신 2(scale 3). IndInv 귀납성은 Apalache(행 2, 갱신 2 고정). TLAPS 는 safety(`Spec => []IndInv` 와 각 속성): 판정표 70/70, MVCC 689/689(tlapm efe4f2d). liveness 없음.
- trace validation: 계측 optdebug 빌드에서 판정표 수용 7건(커버+라우팅, 비커버링 키 필터, 해시 입력 커버 해제, FOR UPDATE, 외부 조인 after-term, TZ 도메인, 일반 인덱스)·거부 1건, MVCC 는 CS 서버 2세션에서 수용 2건(스냅샷 뒤 UPDATE 커밋 + 이후 vacuum, 스냅샷 뒤 UPDATE 롤백)·거부 1건.
- 최종 실행: `tools/tla/tla-check --prove` -> `RESULT: FAILED (1)`(H1 코드 cfg `negzero` 만 실패, 46개 통과), run dir `func-index-cover-20261106-120711-3766369`.
- 반례: `negzero` 하나, Hole 로 분류하고 런타임 재현함.
- 모델 밖: 키 컬럼 둘 이상이 함수 인자와 얽히는 경우, 한 질의에서 F 를 읽는 스캔 둘, 비용 모델(soheejung-cs 4476238835), 스캔 중 leaf split/merge.

## Runtime Verification

- 빌드: head `f1f4f21ea` optdebug(`libcubrid.so` `448482cb…`)·release(`c1ce40fa…`) 로컬, develop `4e389935d` CI debug tarball(`8ebe311e…`).
- signed zero: SA, head optdebug·release 같은 결과, develop 과 다름(위 SQL). 끝 공백 문자열(`lower(v)` 의 `'a'`·`'a  '`)은 키가 둘로 남아 develop 과 같음.
- 비커버링 키 필터: SA, `(i, j, sqrt(d))`·`(sqrt(d), i)`·`(sqrt(d))`·`(i, sqrt(d), j)` 300행, 질의 14쌍 `count`·`sum` 과 행이 develop 과 같음(차이 0줄, 84행). 플랜은 `[...]` 키 필터.
- CS 모드 optdebug 서버(포트 1712, 반납함): 질의 49개, assert·누수·서버 오류 없음.
- CTP: sql 전체(16 shard)는 호스트 과부하로 사용자 지시에 따라 중단(결과 없음). TC 디렉터리 8개를 head optdebug, `tc/pr-6466` `7763f943d`, 1 shard 로 실행: 675 중 666 OK, 9 NOK. 8건은 위 플랜 줄 차이(결과 행 같음), 1건 `function_based_index_function_last_insert_id` 는 인덱스를 쓰지 않는 sscan 에서 `last_insert_id ()` 세션 값 때문에 생긴 순서 의존이며 단독 실행에서 OK(1/1).
- ALTER: 함수 인자 컬럼 타입 변경(double -> int/varchar/numeric), 키 컬럼 타입 변경, 인자 컬럼 이름 변경, `abs(d)` 결과 타입 변경, `utf8_en_ci` 콜레이션 변경 뒤 결과 28개가 develop 과 같음(SA). 인덱스는 `sqrt(cast(d as double))` 로 다시 만들어지고 `(covers)` 를 탐(`r3/alt.sql`).

## Existing Comments

| 코멘트 | 상태 |
|---|---|
| greptile P1 MRO (`btree.c`) | d7ce3af72 로 수정, 작성자 답글 |
| soheejung-cs 4476238580/593/599/604/824/977 | 작성자 답글 + 수정 커밋, TC `[12-*]` |
| soheejung-cs 4476238590 일반 인덱스 커버링 | f1f4f21ea 와 본문이 (a) 로 정함, 스레드 답글 없음 |
| soheejung-cs 4476238835 커버 해제 스캔 비용 측정 요청 | 답글 없음 |
