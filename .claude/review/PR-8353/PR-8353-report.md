# PR #8353 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8353](https://github.com/CUBRID/cubrid/pull/8353)
**제목:** [CBRD-27862] A B-tree node search of a single-column integral index compares key images, not DB_VALUEs
**작성자:** soheejung-cs
**HEAD SHA:** `6b0ca5566` (develop merge-base `1684945ed`, 기능 커밋 `213a54448`)
**JIRA:** CBRD-27862 (Sub-task, Confirmed) / 연관: 부모 CBRD-27361
**TC PR:** CUBRID/cubrid-testcases#3969 (`tc/pr-8353` `68030a99a`) / CUBRID/cubrid-testcases-private-ex#4679 (draft, 봇 init 커밋만 있고 파일 변경 없음)
**리뷰 일시:** 2026-11-03
**리뷰 결정:** 엔진 #8353 Approve (인라인 없음) / testcases#3969 Comment (Greptile 지적 반영 요청) / private-ex#4679 리뷰 없음

> **TL;DR** (Non-blocking): 단일 컬럼 SHORT/INTEGER/BIGINT 인덱스의 노드 이진 탐색이 키 이미지를 정수로 바로 비교하는데, 이미지 위치와 비교 결과가 기존 읽기·비교 경로와 같다. 막을 결함은 없다. TC 의 범위 검사 5개가 인덱스 쪽 결과가 비면 불일치를 세지 못하는 문제는 Greptile 이 이미 지적했고 답이 없다.

## Summary

- **변경 요약**: `btree_search_nonleaf_page ()`·`btree_search_leaf_page ()` 가 같은 형·변환 없는 검색 키일 때 레코드를 DB_VALUE 로 읽지 않고 키 이미지를 `memcpy` 해 정수로 비교한다.
- **주요 이슈**: 없음 (Non-blocking 1건: 쓰이지 않는 반환값)
- **확인 필요 사항**: TC#3969 의 Greptile 지적(빈 결과의 `sum(id)` NULL)에 대한 작성자 답변

---

## Findings

### Non-blocking (should consider)

1. `src/storage/btree.c:5322` `btree_integral_search_key_init ()` 은 이미지 크기를 `int` 로 돌려주지만, 두 호출처(`btree_search_nonleaf_page ()`, `btree_search_leaf_page ()`) 모두 `(void)` 로 버리고 `integral_key.size` 를 다시 읽는다. 반환형을 `void` 로 두면 `return 0`/`return search_key->size` 와 `(void)` 캐스트가 빠진다. (보고서에만 남기고 게시하지 않음)
   ```c
   (void) btree_integral_search_key_init (btid, btid->nonleaf_key_type, key, ..., &integral_key);
   ```

## JIRA -> Engine PR

JIRA 첨부(`design.md`/`test.md`/`test_result.md`) 없음. 본문 Implementation 의 "1단계" 서술을 기준으로 본다. Acceptance Criteria 는 2단계(묶음 탐색) 기준이라 이 PR 의 행으로 두지 않는다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 단일 컬럼 SHORT/INT/BIGINT, 같은 형 검색 키에서 키 이미지 직접 비교 | `btree_integral_search_key_init ()` 이 형 일치, `DOMAIN_COMPARE_DIRECT`, `cmp->id == type`, `conv[0..1] == NULL` 일 때만 켠다 | 충족 |
| 그 밖의 키는 그대로 | 다중 컬럼(MIDXKEY)·다른 형 경계·overflow 키·`page_bounds` 탐색은 `btree_read_record_without_decompression ()` 경로 | 충족 |
| 결과 불변(스펙 변화 없음) | leaf 이미지 위치가 리더의 skip 순서(OID, unique 의 class OID, INSID, DELID)와 같음. fence 레코드도 `btree_write_record ()` 로 같은 배치. 내림차순 뒤집기는 `btree_compare_key ()` 의 `key_domain->is_desc` 처리와 같음. CI sql/medium/shell 통과 | 충족 |
| 성능 -6.5% (JOB 113 직렬) | PR 본문의 작성자 측정(release, wall time, MAD). 리뷰에서 재측정하지 않음 | 충족 (작성자 측정 인용) |

판정: 충족.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 같음: 있는/없는/경계 키, SHORT·INT·BIGINT·고유·내림차순 | #3969 Case 1 | 충족 |
| 범위·인덱스 순서 | #3969 Case 2 (`ord_idsc`, `ord_i` 는 행 출력) | 부분 (범위 5개는 아래 Greptile 지적) |
| 다른 형의 경계(NUMERIC·DOUBLE·문자열·범위 밖) | #3969 Case 3 | 충족 |
| NL 조인 안쪽 탐색 | #3969 Case 4 | 충족 |
| 한 키 5,000행(overflow OID), 삭제·갱신 표시 레코드 | #3969 데이터 준비 | 충족 |

- 새 케이스는 답안 블록 수가 문장 수와 맞고, 헤더 5행의 `;` 는 줄 중간이라 CTP 분리에 걸리지 않는다.
- `cbrd_27361_batch_rowpath.sql` 수정은 `USING INDEX NONE` 추가뿐이고 답안이 그대로다.
- 범위 검사 5개(`rng_*`)는 `count(*) || ':' || sum(id)` 를 비교한다. 인덱스 쪽이 행을 하나도 못 찾으면 `sum(id)` 가 NULL 이 되어 비교가 NULL 이 되고, 불일치로 세지지 않는다(Greptile 인라인, 답 없음).
- private-ex#4679 는 변경이 없어 리뷰 대상이 아니다(닫으면 된다).

판정: 부분 — Greptile 지적의 `coalesce (sum (id), 0)` 반영 여부를 작성자가 답해야 한다.

## Runtime Verification

- gha-ci run 41392690041: engine `6b0ca5566` debug(optdebug) 빌드, sql/medium `tc/pr-8353` `68030a99a`, shell `tc/pr-8353` `5e42de82c`. sql 17,713·medium 975·shell 3,534 건 모두 pass, `failed.list` 비어 있음.
- 같은 run sql shard 03: `cbrd_27862_integral_key_search.sql` ok (8,999 ms), `cbrd_27361_batch_rowpath.sql` ok.
- 새로 돌린 실행 없음. release 빌드에서의 CTP 와 성능 수치는 작성자 보고만 있다.

## Existing Comments

| 위치 | 작성자 | 내용 | 상태 |
|---|---|---|---|
| testcases#3969 `cbrd_27862_integral_key_search.sql:73` | greptile-apps | 범위 검사에서 빈 결과의 `sum(id)` NULL 로 누락을 놓침, `coalesce` 제안 | 답 없음 |
