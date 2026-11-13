# PR #8318 post-ready comments

## CUBRID/cubrid#8318 (engine) — event: APPROVE, commit `72ad4e886` — 게시 완료 (review 5707280420)

top-level:

develop 빌드에서 2 로 나오던 JIRA 재현 1, 2 가 이 PR 빌드에서 3 으로 나오는 것을 확인했습니다. PR 표에 없는 INT 유니크 = FLOAT 비교(16777216, 16777217)도 develop 1 -> 이 PR 2 로 함께 고쳐지고, BIGINT 유니크 = NUMERIC(20,0) 에 2^53, 2^53+1 을 넣은 경우는 두 빌드 모두 조인을 제거하면서 정답 2 를 냅니다(optdebug, SA 모드).

`src/parser/parse_tree_cl.c:19441`:

목록에 없는 변환은 여기서 같은 형만 통과하는데, 값이 그대로 보존되는 DATE -> DATETIME(자동 생성 `cast(u.dte as datetime)`)과 FLOAT -> DOUBLE 도 여기서 막힙니다. `u.dte = o.kdt`, `u.f = o.kd` 는 develop 에서 조인을 제거하고 정답 2 를 냈는데, 이 PR 에서는 조인을 유지합니다(결과는 2 로 같음). 본문의 "정답이 맞으면서 새로 막히는 경우는 `u.d || ''` 하나" 와 달라서, 두 변환을 허용하거나 본문을 고치는 것은 어떨까요?

`src/optimizer/rewriter/query_rewrite_select.c:34`:

NIT: 세 함수 정의가 `qo_collect_name_with_eq_const` 앞에 있으니 프로토타입도 그 앞으로 옮기면 정의 순서와 맞을 것 같습니다.

## CUBRID/cubrid-testcases#3930 (TC) — event: APPROVE at a5fc0dd91 — 게시 완료 (review 5707296423)

grill 에서 정한 Request changes 사유(`.omc/state/last-tool-error.json`)는 작성자가 `a5fc0dd91` 에서 이미 지웠다. 같은 커밋이 `cbrd_27794.queryPlan` 으로 플랜 출력을 추가해 Case 9~13 의 조인 제거도 answer 로 고정한다. 코멘트 없이 승인(새 answer 의 로컬 CTP 결과 확인 후).

## CUBRID/cubrid-testcases-private-ex#4621 — 리뷰 없음 (빈 draft)

## 기존 코멘트

greptile P1(NUMERIC 반올림)은 `ed25c892e` 에서 반영됨. 답글은 작성자 몫이라 다시 올리지 않는다.
