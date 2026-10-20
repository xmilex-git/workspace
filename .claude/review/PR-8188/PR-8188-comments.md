# PR #8188 post-ready comments

## CUBRID/cubrid#8188 (engine PR)

- event: APPROVE
- commit_id: 60b6acc88cdaa283324f40e809d1e46a0ba23f02
- inline: 없음

top-level body:

병렬 해시 조인 워커의 조인 조건 사본에서 `TYPE_FUNC` 분기가 원본(`src`)의 함수 노드를 복사하도록 하고, 그 뒤 사본에 생기는 상수 인자, REGEXP_* 의 `tmp_obj`, RLIKE 의 `compiled_regex` 를 `cached_entry_deleter` 에서 해제하는 변경으로 이해했습니다. CI optdebug 빌드로 JIRA 재현 질의를 돌려보니 merge-base(4adcd4090)에서는 서버가 종료되고 이 PR head 에서는 200000 이 나왔습니다. `cubrid memmon` 으로 보면 RLIKE 병렬 질의 뒤 merge-base 는 `string_regex.cpp` 할당이 질의마다 남는데 head 에서는 0 이고, REGEXP_LIKE 의 `tmp_obj` 도 head 에서 0 으로 해제되는 것을 확인했습니다. 상수 문자열 인자, 부질의 인자, JSON, REGEXP_REPLACE 같은 다른 함수 형태도 병렬 결과가 직렬 결과와 같았습니다.

확인 부탁드립니다
- cubrid-testcases-private-ex#4461 은 변경이 없어서 닫아주시면 TC Merge Gate 가 풀릴 것 같습니다.

## CUBRID/cubrid-testcases#3783 (TC PR)

- event: APPROVE 판정, 게시는 사용자 확인 대기
- commit_id: 050c15fb59c68f6e5f6b8e444ba85bfab8a0cebb
- 근거: head optdebug OK (CI 38878706095 + 로컬 CTP, result = answer), merge-base optdebug NOK (Case 1 서버 종료)
- body 초안: 병렬 해시 조인 조건의 함수 호출(ELT, REGEXP_LIKE)과 RLIKE 를 probe, 파티션 두 병렬 경로에서 직렬 결과와 비교하는 케이스로 확인했습니다. merge-base(4adcd4090) optdebug 에서는 Case 1 에서 서버가 종료되고, 엔진 PR head 에서는 answer 와 같은 결과가 나왔습니다.

## CUBRID/cubrid-testcases-private-ex#4461

- 리뷰 없음 (변경 없는 빈 draft, 닫기 요청은 엔진 PR 본문에)
