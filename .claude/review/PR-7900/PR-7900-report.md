# PR #7900 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#7900](https://github.com/CUBRID/cubrid/pull/7900)
**제목:** [CBRD-27369] Fix the deadlock storm of concurrent UPDATE STATISTICS on one table
**작성자:** soheejung-cs
**HEAD SHA:** `a88844c7d1424f85a1f4905245005b53de6b306b`
**리뷰 일시:** 2026-09-22

> **TL;DR** (Non-blocking): 동시 수집의 S-to-X 잠금 승급 (공유 잠금에서 배타 잠금으로 전환)을 없애도록 인덱스 조회 단계에서 X 잠금을 선취하는 저장과 옵티마이저의 잠금 없는 커밋 읽기는 JIRA 의도와 일치하며, 현재 HEAD에서 머지를 막을 정확성 결함은 확인하지 못했다. 다만 내부 전용으로 보이는 새 `db_*` 두 함수가 public 헤더에 노출됐지만 Windows export 목록에는 없어 API 경계를 정리할 필요가 있다.

## Summary

- **변경 요약**: `_db_histogram` (히스토그램 카탈로그) 존재 확인과 옵티마이저 읽기를 잠금 없는 최신 커밋 읽기로 바꾸고, 저장과 삭제는 인덱스 조회 시점부터 X 잠금을 획득하도록 변경
- **주요 이슈**: 새 `db_*` 두 함수의 public 선언과 Windows export 목록 불일치
- **확인 필요 사항**: 두 함수의 public API 노출 의도와 현재 `Check TC PRs` 실패 상태

---

## Findings

### Non-blocking (should consider)
- `src/compat/dbi.h:184-187`, `src/compat/dbi_compat.h:246-249` - `dbi_compat.h`는 `cubrid/CMakeLists.txt:795-798`에서 설치용 `dbi.h`로 배포되지만 `win/cubridcs/cubridcs.def:672`와 `win/cubridsa/cubridsa.def:372`에는 `db_find_multi_unique_committed`와 `db_find_multi_unique_for_update` export가 없어 Windows 외부 호출은 링크되지 않으므로, public API가 의도라면 export를 추가하고 내부 전용이면 선언을 내부 헤더로 옮겨야 한다.

## JIRA Context

CBRD-27369의 핵심 목표는 동시 `UPDATE STATISTICS`의 `_db_histogram` S-to-X 승급 데드락을 없애고 옵티마이저가 미커밋 히스토그램 작성 트랜잭션에 막히지 않게 하는 것이다. 현재 구현은 존재 확인과 옵티마이저 읽기를 잠금 없는 커밋 읽기로, 저장과 삭제를 인덱스 조회 단계부터 X 잠금을 선취하는 경로로 분리해 이 목표와 일치한다.
