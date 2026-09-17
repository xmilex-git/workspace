# PR #4107 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4107](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4107)
**제목:** [CBRD-27369] Serialize concurrent UPDATE STATISTICS per class (gate + piggyback)
**작성자:** soheejung-cs
**HEAD SHA:** `38bac27fbfa1adf177182491df6419e89fac1cb3`
**리뷰 일시:** 2026-09-14

> **TL;DR** (작성자 확인 필요): 답안 변경은 엔진의 히스토그램 잠금 제거 및 요청 경로 변경과 일치한다. 새 piggyback 동작의 잘못된 생략을 잡는 동시성 회귀 테스트 추가가 필요하다.

## Summary

- **변경 요약**: 히스토그램 행 S 락 제거 및 BTREE_FIND_MULTI_UNIQUES 요청 추가를 답안에 반영.
- **주요 이슈**: 답안 두 개만으로는 선행 롤백과 옵션 불일치 시 후행 수집 생략을 검증하지 못함.
- **확인 필요 사항**: 진입 순서를 고정하고 최종 히스토그램 상태를 검증하는 별도 TC.

## Findings

### Questions for the author

- `shell/_06_issues/_14_1h/bug_bts_13242/cases/issue_13242.answer:3`: 변경 답안은 잠금 개수만 검사하므로 엔진 #7900의 잘못된 piggyback 회귀 검증을 추가해야 함.

## Evidence

- `bug_bts_13242.sh:75-95`의 기대 잠금 수 6/4/11/6/8/9는 새 답안과 일치한다.
- `cbrd_20145_1.sh`는 client requests 구간 숫자를 0으로 치환하여 요청 종류를 비교한다. 새 요청 행 추가는 엔진의 호출 변경과 일치한다.
- `shell_heavy/cbrd_21362/cases/cbrd_21362.sh`는 Java 종료 후 core 파일 개수로 write_ok/write_nok를 결정하며 최종 히스토그램 내용은 검사하지 않는다.
- `Test_File_Tran_Single2.java`는 일반 FULLSCAN과 무작위 COMMIT/ROLLBACK만 사용한다. NO HISTOGRAM/DROP HISTOGRAM 혼합 요청 및 probe 시점 동기화는 없다.
- 위 기존 heavy 동작을 신규 버그로 지적하지 않고, 이번 기능의 회귀 테스트가 별도로 필요하다는 근거로만 사용한다.

## Validation

현재 HEAD의 두 답안과 관련 shell/Java 원문을 정적으로 검토했다. CTP를 직접 실행하지 않았다. JIRA 첨부 테스트 실행 결과는 미검증이다.
