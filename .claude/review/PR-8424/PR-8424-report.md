# PR #8424 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8424](https://github.com/CUBRID/cubrid/pull/8424)
**제목:** [CBRD-27938] Parallel execution can fall back to serial when another thread of the same transaction is inside a system operation
**작성자:** youngjinj
**HEAD SHA:** `316431fba` (develop merge-base `f846c3634`; 기능 커밋 `02216afb6`)
**JIRA:** CBRD-27938 (Correct Error, Develop) / 연관: CBRD-27492 (원인), CBRD-27562 (근본 해소 후보)
**TC PR:** CUBRID/cubrid-testcases#4055 (`tc/pr-8424` `3b37cf6e`, 변경 없는 draft) / cubrid-testcases-private-ex#4762 (`e78d183b`, 변경 없는 draft)
**리뷰 일시:** 2026-11-06
**리뷰 결정:** 엔진 PR Approve (inline 2: Non-blocking 1 제안, Question 1 질문) / TC PR #4055, private-ex #4762 리뷰 없음 (변경 없음, 회귀 TC 부재는 코멘트하지 않음)

> **TL;DR** (Non-blocking): 병렬 실행을 끄는 sysop(system operation, 트랜잭션 단위 원자 연산) 검사를 "현재 스레드 또는 PL 세션 스레드가 연 sysop" 으로 좁힌 변경은 맞다. 교착 방지(CBRD-27492)와 sysop 상호배제는 TLA+(TLC, Apalache, TLAPS)와 계측 빌드 실행으로 확인했다. JIRA 댓글에서 합의한 조건과 구현이 다른데 PR 본문에 이유가 없고, 빈 소유자에서 `true` 를 돌려주는 구간에서 직렬 전환이 1건 남았다.

## Summary

- **변경 요약**: `is_under_system_operation ()` 이 sysop 이 열려 있을 때 `rmutex_topop` (sysop 을 감싸는 트랜잭션 단위 재진입 mutex) 소유자를 보고, 소유자가 비었거나 현재 스레드이거나 PL 세션에 등록된 스레드일 때만 병렬을 끈다.
- **주요 이슈**: 없음 (Blocking 없음)
- **확인 필요 사항**: JIRA 합의 조건을 PL 세션 조건으로 바꾼 이유 기록, 빈 소유자에서 `true` 를 돌려주는 이유

---

## Findings

### Non-blocking (should consider)
- `src/query/parallel/px_parallel.cpp:75` — JIRA 댓글(2026-11-04 제안, 2026-11-05 합의)의 조건은 "sysop 을 연 스레드가 현재 스레드이거나, 현재 스레드를 띄우고 기다리는 스레드" 다. 구현은 px 부모 조건 없이 PL 세션 조건(`is_thread_involved`)을 쓰고, PR 본문은 부모 조건을 뺀 이유를 적지 않았다. 리뷰 검증으로는 구현 쪽이 맞다. 부모 조건을 넣으면 부모가 임시 파일용 짧은 sysop 을 쥔 동안 워커가 다시 직렬로 떨어진다(TLA+ `mutant-jira-design` 이 C1 위반). 부모가 sysop 을 쥔 채 워커를 기다리는 경로가 없다는 전제(A1)는 develop 도 쓴다(`witness-late-join-develop` 교착). PL 조건은 합의안의 "기다리는 스레드" 중 저장 프로시저 호출자 경우를 덮는다. 이 이유를 PR 본문과 JIRA 에 남기기를 권한다.

### Questions for the author
- `src/query/parallel/px_parallel.cpp:67` — 클라이언트 트랜잭션에서 첫 읽기(`is_under_sysop ()`)가 sysop 을 보고 둘째 읽기가 빈 소유자를 보면, 그 사이 sysop 이 끝난 것이다. 지금은 이때 `true` 를 돌려줘 이 이슈와 같은 직렬 전환이 남는다. 계측 head 빌드 16회 실행 중 1회에서 실제로 일어났다(task 13 이 sysop 을 닫는 사이 task 2 가 판정, `empty-race` trace). 빈 소유자가 열린 sysop 을 뜻하는 경우(`lock_topop ()` 이 mutex 를 잡지 않는 시스템 트랜잭션)를 위해 `true` 를 둔 것인지, 아니면 `false` 로 해도 되는지 확인.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: 두 입력 스캔이 매번 병렬 | 다른 스레드 sysop 때문인 직렬 판정: base 15회 중 7건 -> head 16회 중 0건, 같은 상황 head 병렬 6건 | 충족 (빈 소유자 구간 1건 남음, Question 1) |
| 합의된 설계: 현재 스레드 또는 띄우고 기다리는 스레드 | PL 세션 스레드 조건으로 대체, px 부모 조건 없음, 이유 미기재 | 부분 (Non-blocking 1) |
| CBRD-27492 교착 방지 유지 | self 검사 유지, TLA+ `mutant-no-self` 교착 검출, head 교착 없음 | 충족 |

CBRD-27562 는 같은 증상의 근본 해소 후보이며 이 PR 은 TODO 로만 남긴다.

## TC PRs

두 TC PR 모두 변경 없는 draft 다. JIRA 에 `test.md` 가 없고 PR 본문에 검증 표가 없다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| JIRA Repro: `tc ANTI JOIN td` PARALLEL(4) trace 의 td 스캔 `parallel workers` 줄 | 회귀 TC 없음. 원래 TC 는 cubrid-testcases #4019 가 hint 로 이 경로를 피함. 경합 의존이라 답지로 고정하기 어려움 | 미충족 |

TC 판정: 검토할 TC 변경 없음. 회귀 TC 부재는 다른 팀 PR 이라 코멘트하지 않는다(grill 확정).

## TLA+ Verification

TLA+ 검증: 통과 — `.claude/review/PR-8424/tla/px-sysop-gate/` (`RESULT: OK`, run `px-sysop-gate-20261106-174428-885327`)
- 속성: C1 safety(다른 스레드 sysop 으로는 직렬 판정 안 함, JIRA Expected Result) TLC 통과, TLAPS 증명 / C2 liveness+교착 없음(CBRD-27492) TLC 통과(메인 cfg `RootEnds`, scale 은 교착 검사) / C3 safety(sysop 안에서 실행 중인 스레드는 하나, PR 본문 PL 조건 근거) TLC 통과, TLAPS 증명
- 결함: 없음. 빈 소유자 구간(`witness-empty-race`)은 C1 의 예외로 모델이 허용하며 계측 빌드에서 1회 관측(Question 1)
- mutant: 4개 모두 위반 검출 — `develop`(C1), `no_self`(C2 교착), `no_pl`(C3, Q 의 워커 둘이 PL 경로로 동시 재진입), `jira`(합의안, C1) / 살아남은 mutant: `empty_other`(Question 1)
- 경계: 스레드 7개(Root, Q, Root 워커 2, 손자 1, Q 워커 2), 연산 1회(Root 3회), 232만 상태; scale 스레드 8개 4230만 상태; IndInv 귀납성은 Apalache 로 `MaxOps` 전 범위; TLAPS 는 스레드 집합, task 트리, 연산 수 모두 임의(641/641), safety 만
- 환경 가정: A1 부모가 자기가 띄운 워커가 도는 중 연 sysop 을 쥔 채 기다리지 않음(develop 도 같은 가정, 없애면 head·develop·합의안 모두 교착), A3 Root 가 sysop 을 쥔 채 SP 를 부를 때 px task 가 없음, A4 `compute_parallel_degree` 는 클라이언트 트랜잭션에서만 불림
- trace validation: 수용 6건(sibling 2, self, pl, pl-reenter 152회 재진입, empty-race) + TC 본문 전체 run 의 서로 다른 세그먼트 151개 수용, 거부 2건(PL 판정 뒤집기, 형제 lock 겹침)
- 반례: 없음 (모델 오류 3건은 수정: Q 재시작 시 판정 상태 초기화, 획득 대기 상태 `acq`, trace 시작 시 Root 의 이전 판정)

## Runtime Verification

- CI(gha-ci run 42144220825, head `316431fba`, debug=optdebug 슬롯, `tc/pr-8424` = develop + init commit): build debug/release 통과, sql 17746 / medium 975 / shell 3549 모두 pass.
- fail-before / pass-after (같은 방법): `02_hash_join_mode.sql`(cubrid-testcases #4019 이전 `5c5b4a6d3`)의 setup 후 본문(157-826행)을 빌드별로 새 서버에서 반복, `test_mode=yes`, CS 모드. 판정마다 이유를 기록하는 계측 optdebug 빌드 두 개: base 게이트(`e614092a`, develop 판정으로 되돌림) 15회 -> `reason=other dec=serial` 7건(6회), head(`42beb56b`) 16회 -> `other serial` 0건, `other par` 6건, `empty serial` 1건.
- 시나리오 run (head 계측 빌드): `INSERT ... VALUES ((SELECT /*+ PARALLEL(4) */ ...))` -> Root `self -> serial`; `INSERT ... VALUES (f_cnt ())` -> SP 의 SQL 을 받은 다른 요청 스레드가 `pl -> serial`; `f_sort ()` -> 그 스레드가 Root 의 sysop 에 PL 경로로 152회 재진입, 판정 6회 모두 `pl -> serial`. 결과 행 300000 일치.
- 서버는 모두 내렸고 포트(1716) 클레임은 리뷰 종료 시 해제한다.
