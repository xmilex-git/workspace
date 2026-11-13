# PR-8359 post-ready comments (r3, head 4166ec0ac)

## CUBRID/cubrid#8359 — event: APPROVE

### top-level
새 base(CBRD-27989 머지 뒤)에서 지난번 두 질의를 다시 돌려 보니 ROWNUM 이 develop 과 같은 1..12 로 나옵니다. 정렬하는 마지막 그룹이 다시 스트리밍되는 것도 확인했습니다.

### reply on thread 4505583216 (then resolve)
확인했습니다. CBRD-27989 가 들어간 base 에서 두 질의 모두 develop 과 같은 1..12 이고, 가드를 뺀 뒤에도 정렬하는 마지막 그룹이 스트리밍 경로로 갑니다. Case 14 도 확인했습니다.

## CUBRID/cubrid-testcases#3978 — no new review (1차 Approve 유지)
