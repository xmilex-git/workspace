# PR #7998 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#7998](https://github.com/CUBRID/cubrid/pull/7998)
**제목:** [CBRD-27406] Reclaim the cached-subquery allocations left on the prepared-statement, XASL unpack, and XASL cache paths
**작성자:** youngjinj
**HEAD SHA:** `5751722c900e642f270464f940a294fccf949d39`
**리뷰 일시:** 2026-09-22

> **TL;DR** (Non-blocking): 변경된 정리 및 오류 경로는 기존 소유권 계약과 에러 전파 방식을 유지한다. 머지를 막거나 후속 수정을 요구할 코드 결함은 확인되지 않았다.

## Summary

- **변경 요약**: prepared subquery, XASL (실행 가능한 질의 계획) 언팩, XASL 캐시 경로에서 누락된 자원 회수와 할당 실패 처리를 추가
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

## JIRA Context

CBRD-27406의 2차 수정 범위인 prepared statement 실행 결과 정리, XASL 언팩 데이터의 수명 연결, prepared subquery 정보의 오류 경로 회수, XASL 캐시 수명주기 정리, 할당 실패 시 SIGSEGV 방지가 모두 구현에 반영되어 있다.
