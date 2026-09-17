# PR #7900 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#7900](https://github.com/CUBRID/cubrid/pull/7900)
**제목:** [CBRD-27369] Serialize concurrent UPDATE STATISTICS per class (gate + piggyback)
**작성자:** soheejung-cs
**HEAD SHA:** `f79eda483b712bd50ac70339d077a04b6bd3fee2`
**리뷰 일시:** 2026-09-14

> **TL;DR** (Blocking): 기존 CHN 가시성 및 선행 히스토그램 수집 여부 지적은 코드 근거가 있다. 두 지적은 이미 인라인에 있어 중복 게시하지 않고 가시성 근거만 기존 대화에 보완한다.

## Summary

- **변경 요약**: 클래스별 통계 갱신 직렬화, 중복 수집 생략, 옵티마이저 히스토그램 조회 잠금 제거.
- **주요 이슈**: 미커밋 CHN(행 캐시 일관성 번호)을 갱신 완료 판단에 사용하고 선행 히스토그램 생성 여부를 검사하지 않음.
- **확인 필요 사항**: 수정 후 COMMIT/ROLLBACK 및 NO HISTOGRAM/DROP HISTOGRAM 혼합 요청 회귀 시험.

## Findings

새로 게시할 독립 결함 없음. 기존 인라인 두 지적의 근거를 아래에 재검증했다.

## Existing Comments

| Thread | Revalidation |
|---|---|
| [가시성](https://github.com/CUBRID/cubrid/pull/7900#discussion_r4002304328) | 타당. `heap_scancache_start_internal:6466`은 전달받은 NULL을 그대로 저장하고 `heap_get_visible_version_internal:25606-25644`는 snapshot 없이는 가시성 검사 및 이전 버전 탐색을 생략한다. |
| [선행 옵션](https://github.com/CUBRID/cubrid/pull/7900#discussion_r4002304327) | 타당. `do_update_stats:4945-4951`은 후행 옵션과 선행 FULLSCAN 여부만 검사한다. 선행 NO HISTOGRAM/DROP HISTOGRAM도 `sm_update_statistics:5034` 경유로 bookkeeping을 바꾸므로 히스토그램 생성 없이 생략 조건을 충족한다. |
| [DDL](https://github.com/CUBRID/cubrid/pull/7900#discussion_r4002304331) | 확인 질문 유지. CHN은 통계 전용 세대가 아니지만, 실제 DDL과의 경합 순서는 잠금까지 포함해 입증되지 않았다. 별도 확정 결함으로 재게시하지 않음. |

가시성 지적의 추가 근거: `mvcc_is_mvcc_disabled_class:680-705`의 제외 대상에 `_db_class`는 없다. `catcls_update_class_stats:4626-4640`은 `old_chn + 1` 및 `UPDATE_INPLACE_NONE`으로 새 MVCC 버전을 기록한다.
선행 갱신 뒤 미커밋 CHN을 읽고 gate를 기다리면, 선행 COMMIT에서는 CHN이 같아 재수집하고 ROLLBACK에서는 복원된 CHN과 달라 생략할 수 있다. 후자는 히스토그램 갱신까지 빠진다.

## JIRA Context

CBRD-27369 캐시 본문(Updated 2026-09-11)을 확인했다. 동일 테이블의 동시 FULLSCAN 처리율 붕괴 해결이 목적이며 방향은 일치한다. 첨부 파일 자체와 10/10 실행 기록은 검증하지 않았다.

## Validation

- 현재 커밋의 diff, 변경 함수 및 heap/MVCC/카탈로그 호출 경로를 정적으로 대조했다. 빌드와 실행 재현은 수행하지 않았다.
- 조회 실패 시 `schema_manager.c:4181-4204`의 히스토그램 해제 및 `er_clear` 처리가 있어 삭제 경쟁만으로 쿼리 실패를 주장하지 않는다.
- private #4107의 답안 변경과 shell/heavy 원문을 확인했다. 기존 polling/cleanup 문제는 신규 결함에서 제외했다.
- 공개 #3461은 파일 변경 없는 draft임을 확인하고 내용 리뷰 대상에서 제외했다.
- 별도 convention sanity 검사 결과 없음. 기존 helper에서 복사된 2열 키 표현은 신규 결함이 아니므로 제외했다.
