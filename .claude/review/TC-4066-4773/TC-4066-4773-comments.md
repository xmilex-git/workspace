## cubrid-testcases #4066 (Approve)

CS 쿼리를 SQL TC로 옮긴 것 확인했습니다. 기존 shell queries.tsv 54줄과 기대값이 빠짐없이 옮겨졌고, Case 14-17 JSON 결과도 [1,1,2] 입력으로 계산한 값과 같습니다.

정정 코멘트의 10건은 본문의 8건이 맞는 것으로 보입니다. 표의 JSON 불일치 행은 5줄이고 그중 base_on_only는 옮기지 않은 기존 Case 2라서, 새로 옮긴 쿼리 중 shell 기대값과 다른 것은 Case 14-17 JSON 4종 x 힌트 2개 = 8건입니다. 본문은 그대로 두셔도 될 것 같습니다.

본문의 chain Case 15-24, answer +342는 ORDERED 커밋 이후 Case 15-27, +535로 바뀌었으니 함께 고쳐 주시면 좋겠습니다.

## cubrid-testcases-private-ex #4773 (Approve)

CS 쿼리를 SQL TC로 넘기고 SA 경로만 하나의 TC로 합친 것 확인했습니다. 기존 default, hint, chain 쿼리 54줄과 힌트 조합이 그대로 유지됩니다.
