# PR 8196 항목 6 — 게시용 코멘트 (cubrid-pr-review 말투)

- 대상: CUBRID/cubrid#8196, commit_id `908bdc5af67a752fd168b71cdf2c6f140520861d`
- 리뷰 이벤트: COMMENT (항목 6 범위의 지적만 담으므로 승인·변경 요청 판단은 하지 않음)
- 근거: `item6-postgres-compare.md` §3 N1-N5, Q1-Q2 (사용자 승인: "응 /cubrid-pr-review 말투로 작성해서 올려줘")
- 실질적인 Non-blocking 이라 `NIT:` 는 붙이지 않음.

---

## top-level

PostgreSQL 실행기(행 단위 반복자, 페이지 모드 가시성, hash agg spill)와 비교하면서 배치가 실제로 적용되는 범위 위주로 살펴봤습니다. head `908bdc5af` optdebug 빌드에서 40만 행 테이블로 `;plan detail` trace 를 보며 확인한 내용이고, 코드 위치가 있는 것은 인라인으로 남겼습니다.

확인 부탁드립니다:
- 페이지 배치, 해시 GROUP BY 병합, 해시 조인 런타임 필터를 끌 수 있는 파라미터나 힌트가 없는 것으로 보입니다. 현장에서 결과나 성능 문제를 진단할 때 행 경로와 비교할 수 있도록 서버 파라미터 하나로 세 입구(`scan_batch_open*`, `qexec_gby_hash_merge`, `hjoin_rtf_first_input`)를 막을 수 있게 하는 것은 어떨까요?
- 주석과 본문의 "database-reference" 가 어떤 엔진의 어느 버전인지 궁금합니다. 주석의 식별자(`PpNodeUseColumnInfo`, `InvalidateRowsByFilter`, `ExAggr`, `NumberAccum` 등)는 PostgreSQL 에는 없는 것으로 확인했습니다. TPC-H "reference 대비" 수치를 잰 엔진 설정도 함께 알려주시면 좋겠습니다.

---

## src/query/query_executor.c:11622

`spec->parts != NULL` 조건 때문에 분할 테이블은 직렬·병렬(px 워커도 이 함수로 거름) 모두 배치를 타지 않는 것으로 보입니다. 이때 `batch_why_not` 도 남지 않아서 `;plan detail` 에 아무 표시가 없습니다. 40만 행 해시 4분할 테이블에서 `sum(n) ... where n < 10` 이 heap time 386ms 였고, 같은 데이터의 일반 테이블은 배치로 47ms 였습니다. 이번 범위 밖이라면 거절 사유를 trace 에 남기고 본문의 거절 목록에도 적어 두는 것은 어떨까요?

## src/query/expr_batch.c:1509

`expr_scan_pred_has_share()` 는 필터가 공유용으로 등록한 노드 수(`n_share`)를 보는데, 등록은 읽는 쪽이 있든 없든 이뤄져서 컬럼에 산술이 들어간 필터는 모두 여기서 거절되는 것으로 보입니다. 계산값을 아무도 읽지 않는 아래 질의도 `batch: no (the filter shares computed values with other programs)` 였습니다.

```sql
select /*+ parallel(0) */ count(*) from t1 where n + 1 < 10;
```

실제로 연결된 소비자(`n_shared`)가 있을 때만 거절하도록 좁힐 수 있을지 궁금합니다.

## src/query/expr_batch.c:3155

`ALTER TABLE ... ADD COLUMN` 은 기존 레코드를 다시 쓰지 않아서, 그 뒤로는 거의 모든 페이지가 여기서 행 경로로 가는 것으로 보입니다(40만 행에서 `batch pages: 1 (row path: 1857, last: a record of another representation)`). `heap_page_collect_visible()` 의 `S_DOESNT_FIT` 도 비슷해서, 다른 세션이 1% 행만 갱신 중이어도 1856/1858 페이지가 행 경로였고, 레코드가 이동된 페이지는 서버 재시작 후에도 계속 행 경로였습니다. PostgreSQL 페이지 모드에는 이런 되돌림이 없어서 차이가 나는 부분인데, 본문의 적용 범위 설명에 이 경우들을 적어 두는 것이 좋겠습니다.

## src/query/query_executor.c:7183

칸 수를 `QEXEC_GBY_MERGE_MAX_PARTS` (64) 로 묶고 넘친 칸을 다시 나누지 않아서, 그룹이 많으면 칸 하나의 표가 `max_agg_hash_size` 를 몇십 배 넘는 것으로 보입니다. `max_agg_hash_size=32K`, 그룹 98K 에서 칸 하나가 약 0.79MB(예산의 약 24배)였고, 그룹당 약 456B 로 보면 기본 2MB 에서도 2천만 그룹이면 칸 하나가 140MB 정도가 됩니다(병렬 병합이면 워커 수만큼). develop 의 정렬은 `sort_buffer_size` 안에서 돌았고 PostgreSQL hash agg 는 넘친 파티션을 재귀로 다시 나누는데, `bytes / n_parts` 가 예산의 일정 배수를 넘으면 병합 대신 기존 정렬에 맡기는 조건을 두는 것은 어떨까요?
