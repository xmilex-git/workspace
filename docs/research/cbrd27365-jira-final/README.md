# CBRD-27365 종착 산출물 (#194, 2026-09-04)

- upstream PR: https://github.com/CUBRID/cubrid/pull/7866 (draft, `xmilex-git:CBRD-27365-pr3` 3388a9f04 → develop, +3769/−2795, 39파일). 본문 `pr-7866-body.md`.
- TC 봇 브랜치: `CUBRID/cubrid-testcases:tc/pr-7866` (플랜텍스트 7건·agg_group_by·신규 TC 10건 배치는 후속 티켓).
- JIRA: Summary 를 "Reduce temp file size by changing the tuple format inside temp files" 로, Description 을 `jira-description.wiki.md`(JIRA wiki 마크업, 기존/신규 포맷 ASCII 다이어그램 포함)로 교체. 첨부 `design.md`, `test.md`, `cbrd27365-tcs.zip`(신규 TC 10건 sql/answer + ScrollSmoke.java).
- 게이트: `just rebuild` 풀빌드 release/optdebug 모두 에러 0(`~/{release,optdebug}/CUBRID-cbrd27365-pr3-gate`, 11.5.0.2546-3388a9f). 경고는 전부 기존 코드(csql_grammar 충돌, CBRD-26888 `object_primitive.c:9369`, dbtype_def/tde maybe-uninitialized).
- D-193-5(병렬 페이지 임계 기본값): 이 PR 미포함 — CUBRID/cubrid#7817(CBRD-27326) 에서 처리(사용자 결정).
