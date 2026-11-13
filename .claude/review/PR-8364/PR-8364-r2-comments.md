# TC 3985 comments (posted 5779594395)

event: COMMENT at 694a0e04d

본문 Remarks 의 "debug 빌드에서도 같은 출력으로 통과합니다" 가 CI 결과와 다릅니다. gha-ci 41623402810, 41770625665 의 debug 빌드에서 `cbrd_27361_page_order` 는 Case 8 에서 서버가 죽어 NOK 입니다(엔진 PR #8364 에 남긴 `expr_image_same_prog` assert).

TC 는 그 결함을 정확히 잡고 있어서 케이스와 답안은 그대로 두면 될 것 같습니다. 엔진이 고쳐진 뒤 debug 에서 통과하는 것을 확인하고 본문을 고쳐 주시면 Approve 하겠습니다.

[sql/_13_issues/_26_2h/cases/cbrd_27361_page_order.sql:20]
NIT: 머리 주석의 `;` 는 CTP 가 문장 경계로 읽습니다. 이번 답안에는 영향이 없지만 `,` 나 `.` 로 바꾸는 건 어떨까요?
