# PR #4107 게시용 인라인 댓글

`shell/_06_issues/_14_1h/bug_bts_13242/cases/issue_13242.answer:3` (RIGHT)

잠금 개수 답안 변경은 `bug_bts_13242.sh`의 기대값과 맞습니다. 다만 이번 변경은 답안 두 개뿐이고, `shell_heavy/cbrd_21362`도 최종 히스토그램 상태를 검사하지 않아 잘못된 piggyback으로 수집을 생략해도 잡지 못할 것 같습니다.
엔진 #7900에서 논의 중인 두 경우를 별도 TC로 추가하는 것은 어떨까요? 선행 통계 기록 후 후행을 진입시킨 뒤 COMMIT/ROLLBACK하는 경우와, 선행 `WITH FULLSCAN, NO HISTOGRAM` / `WITH FULLSCAN, DROP HISTOGRAM`이 통계를 기록하기 전에 일반 FULLSCAN 요청을 대기시키는 경우입니다. 진입 순서를 동기화하고, 후행의 실제 수집 여부와 최종 히스토그램 상태까지 확인하면 좋겠습니다.
