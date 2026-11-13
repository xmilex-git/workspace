# PR #8398 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8398](https://github.com/CUBRID/cubrid/pull/8398)
**제목:** [CBRD-27926] GROUP_CONCAT takes seconds and about 2 GB of server memory once a group's result passes about 200 KB
**작성자:** xmilex-git
**HEAD SHA:** `ea06eca48` (develop merge-base `0661d2c12`)
**JIRA:** CBRD-27926 (Improve, Develop) / 연관: RND-2891(보고 원본), CBRD-24850(글자 수 재계산 제거, 선행), CBRD-27583(누산기 도메인)
**TC PR:** CUBRID/cubrid-testcases#4024 (`tc/pr-8398` b31e9f058) / CUBRID/cubrid-testcases-private-ex#4729 (빈 draft, 변경 파일 0)
**리뷰 일시:** 2026-11-06
**리뷰 결정:** (grill 후 기입)

> **TL;DR** (__VERDICT__): __TLDR__

## Summary

- **변경 요약**: GROUP_CONCAT 누산기를 행마다 새로 만들던 것을, 누산기 버퍼에 이어 붙이고 모자랄 때만 다음 2의 거듭제곱(상한 `group_concat_max_len + 1`)으로 키우도록 바꿈. 버퍼 크기는 집계 노드 `info.group_concat`이 기억함.
- **주요 이슈**: __ISSUES__
- **확인 필요 사항**: __QUESTIONS__

---

## Findings

__FINDINGS__

## JIRA -> Engine PR

기준: JIRA Expected Result(Acceptance Criteria)가 재현 조건에서 성립하고, `design.md`의 변경과 미정 항목이 구현되거나 PR이 이탈 사유를 밝혔는가. `design.md`/`test.md`는 아직 JIRA에 올라가지 않았고, 로컬 초안(`.git_ignored_dir/jira/CBRD-27926/`)으로 대조함.

__JIRA_TABLE__

## TC PRs

__TC_TABLE__

## TLA+ Verification

__TLA__

## Runtime Verification

__RUNTIME__

## Existing Comments

| 코멘트 | 상태 |
|---|---|
| greptile P2 (`string_opfunc.c` CHAR/BIT 분기에서 BIT가 계속 전체 복사) | 작성자가 SQL로 반박(`GROUP_CONCAT(BIT)`은 VARBIT 누산기, 300행에서 분기 0회), greptile이 철회. 해결됨 |
