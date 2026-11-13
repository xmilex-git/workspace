# PR-8436 post-ready comments (head 1e5fcd7ca)

## CUBRID/cubrid#8436 — event: APPROVE

### top-level
develop debug 빌드에서는 새 TC 가 코어를 남기고, 이 PR 빌드에서는 debug·release 모두 통과합니다. 행마다 하는 정리가 다음 갈래로 넘어가지 않으니 병렬로 도는 다른 갈래의 부질의 리스트를 건드리는 경로가 없어지는 것으로 보입니다.

## CUBRID/cubrid-testcases-private-ex#4775 (head ecad9fab) — event: APPROVE

### inline shell/_06_issues/_26_2h/cbrd_27959/cases/cbrd_27959.sh:9 (RIGHT)
DESCRIPTION 의 원인 설명이 이슈 처음의 추정(임시 파일 목록을 잠금 없이 봄)으로 남아 있는데, 엔진 PR 본문은 그것을 증상으로 정리하고 원인을 "첫 갈래의 행마다 `qexec_clear_all_lists` 가 `next`, 즉 다음 갈래의 부질의 리스트까지 지운 것"으로 적었습니다. 머리말도 그 원인으로 맞춰 두는 것은 어떨까요?
