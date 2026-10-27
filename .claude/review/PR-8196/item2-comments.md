# PR 8196 항목 2 게시용 코멘트

엔진 PR CUBRID/cubrid#8196, commit `908bdc5af67a752fd168b71cdf2c6f140520861d`
리뷰 이벤트: COMMENT (전체 판정은 기존 CHANGES_REQUESTED 리뷰가 맡음)

## top-level

힙 스캔이 페이지를 놓았다가 다시 잡는 자리에서 vacuum 이 그 페이지를 해제하는 경우가 없는지 위주로 살펴봤습니다. 필터 반복자·px `rows` 노드·다음 페이지로 넘어가는 자리 모두 이 스냅샷이 본 행이 남은 페이지만 놓고, 다음 페이지는 `OLD_PAGE_PREVENT_DEALLOC` 으로 잡아서 `heap_next_internal()` 과 같은 규칙을 따르는 것으로 보입니다. 행을 옮겨 페이지를 통째로 비우는 부하를 같이 걸어도 직렬 경로(직렬 체인, NL 조인 바깥 반복자)는 c966fabc6 과 같은 결과였습니다. 대신 fixed/cached scan 쪽에서 하나 걸리는 부분이 있어 인라인으로 남깁니다.

## inline: src/query/scan_manager.c:8665

필터 반복자가 페이지를 fix 한 채로 `expr_batch_run()` 을 부르는데, 원시 리프가 아닌 항은 `eb_filter()` 에서 행마다 `expr_scan_pred_eval_kid()` 로 평가되어서 필터 안의 SP 도 이 fix 아래에서 실행되는 것으로 보입니다. develop 에서는 NL 조인 바깥 스캔이 cached scan 이라 필터가 원본 페이지를 놓은 뒤에 평가되는 것으로 알고 있습니다.
아래 질의에서 SP 의 UPDATE 가 바깥 스캔이 잡고 있는 같은 페이지의 write latch 를 기다리다가, optdebug 는 latch timeout 뒤 `pgbuf_timed_sleep()` assert 로 서버가 내려가고, release 는 트랜잭션이 abort(-72) 되어 질의가 실패했습니다. c966fabc6 에서는 20000 으로 정상입니다.

```sql
create or replace function f_upd2(p int) return int as
begin if p <= 50 then update t set v = v + 100 where id = p + 1; end if; return 1; end;
-- t(id int primary key, v int, pad varchar(200)) 20000행, u(k int) + index on u(k)
select /*+ ordered use_nl no_parallel_scan */ count(*) from t a, u b
 where a.v >= 0 and f_upd2(a.id) = 1 and b.k = a.id;
```

단일 테이블은 develop 도 fixed scan 이라 같은 증상(CBRD-27591)이고, 조인 바깥 모양만 이 PR 에서 새로 생기는 것 같습니다. fixed 가 아닌 스캔이면 행별 항이 있는 필터(`plan->n_row_kids > 0`)는 반복자가 받지 않도록 하는 것은 어떨까요? `expr_batch.c` 에 달린 fallback 시 SP 재실행 코멘트도 같은 자리라 함께 정리될 것 같습니다.

## 게시 기록

2026-10-21 리뷰 5598576339 (COMMENT), 인라인 코멘트 4335923494 (`src/query/scan_manager.c:8665`, commit `908bdc5af`).
