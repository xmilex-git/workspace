# PR 8196 항목 3 — 게시용 코멘트 (cubrid-pr-review 말투)

- 대상: CUBRID/cubrid#8196, commit_id `908bdc5af67a752fd168b71cdf2c6f140520861d`
- 리뷰 이벤트: COMMENT
- 근거: `item3-cpp-perf-rules.md` (사용자 지시: "말투로 리뷰올려")
- 기존 스레드 답글 1건: `expr_batch.c:3155` (comment 4335794820, ALTER 후 되돌림) — 새 코멘트 대신 측정 수치를 답글로 붙임
- 게시 완료 2026-10-21: review 5598982727 (COMMENT, 인라인 10건 4336248796-4336248913), 답글 4336250162. grill 결정: COMMENT, 전부 게시, 런타임 필터 코멘트는 단정형

---

## top-level

성능 쪽(행마다 도는 경로, 병렬 워커 사이 공유, 할당) 위주로 살펴봤습니다. CI 의 head(908bdc5af)·develop(c966fabc6) release 빌드로 lineitem 앞 200만 행에서 같은 질의를 돌렸고, 호스트를 다른 작업과 같이 쓰고 있어서 판정은 `perf stat -e instructions:u` 명령어 수와 `perf record`·`perf c2c` 로 했습니다. 배치가 맡는 필터·집계(`l_quantity < 24`, 날짜 범위, OR, Q6, Q1 모양)는 명령어 수가 develop 의 0.29~0.31배로 본문 수치와 맞았고, 아래 인라인은 배치를 타지 않는 경로나 병렬에서 develop 보다 느려지는 부분입니다.

확인 부탁드립니다
- 본문 성능표는 CI 대응 수정과 develop 머지 전 빌드에서 잰 값이라고 되어 있는데, head 와 develop 의 release `libcubrid.so` 를 비교해 보면 행 경로 핫 함수(`heap_next_1page`, `spage_next_record`, `fetch_val_list`, `mht_get` 등) 19개가 모두 주소가 바뀌었고 9개는 32바이트 위상이 달라졌습니다. 직렬 Q3·Q7·Q9 가 1.03~1.06 으로 느린 부분은 인라인의 필터 확인 호출과 `heap_attrvalue_read` 인라이닝을 반영한 뒤 다시 재서, 중앙값 옆에 분산도 함께 적어 주시면 좋겠습니다.
- 배치가 페이지를 행 경로로 넘기면 trace 의 SCAN `heap time` 이 두 번 더해지는 것 같습니다. `qexec_batch_scan()` 이 체인 전체 시간을 더하고 그 안의 `scan_next_scan()` 도 행마다 더해서, 조건 없는 `COUNT(*)` 에서 SCAN `heap time` 이 60~90 ms 로 같은 실행의 `SELECT (time)` 37~56 ms 보다 컸습니다.
- 본문의 Q18 런타임 필터 수치(31.6 -> 25.8초)는 직렬·병렬 중 어느 쪽에서 잰 것인지 궁금합니다.

---

## src/query/query_hash_join.c:4987

`rows`·`dropped` 를 행마다 `__atomic_add_fetch` 로 올리는데, 병렬 워커가 모두 같은 `hjoin_runtime_filter` 를 쓰고(`hjoin_rtf_bind_clone()`) 이 두 필드가 매 행 읽는 `slots`·`used`·`mask`·`is_date` 와 같은 캐시 라인에 있어서, 워커끼리 그 줄을 계속 주고받는 것 같습니다. lineitem 200만 행 probe·워커 6개에서 `hjoin_rtf_pass()` 가 전체 cycles 의 19~73%, `perf c2c` load HITM 의 82~94% 였고, 병렬 질의가 develop 보다 1.45~1.89배 느렸습니다(아래처럼 IN 서브쿼리 안 해시 조인은 기본 설정에서도 1.58배). trace 표시용 값이니 워커별 지역 변수로 세고 끝날 때 `hj->rtf_rows` 에 한 번 더해야 하는 것으로 보입니다.

```sql
select count(*) from supplier x where x.s_suppkey in (select /*+ use_hash */ l.l_suppkey from lineitem l, orders o where l.l_orderkey = o.o_orderkey and o.o_totalprice > 380000);
```

## src/query/expr_batch.c:2636

필터 없이 컬럼도 읽지 않는 계획(조건 없는 `select count(*) from t`)은 여기서 받아들여지는데, `plan->repid` 는 `eb_new_col_vec()`·`eb_build_gby()` 에서만 정해져서 0 으로 남고, `eb_layout_rows()` 의 대표 검사에서 모든 청크가 행 경로로 가는 것 같습니다. ALTER 없이 만든 테이블에서도 `batch pages: 1 (row path: 901, last: a record of another representation)` 이었고(`where a > -1` 을 붙이면 902/0), 200만 행에서 명령어 수가 develop 대비 +9.1% 였습니다. 컬럼이 없으면 대표 검사를 건너뛰거나, 가시 행 수만 세는 경로로 두는 것은 어떨까요?

## src/query/query_evaluator.c:3561

컴파일러가 거절한 필터(`scan_prog_state == 2`, trace 의 `interpreted (not covered)`)도 이 조건이 참이 되어서 행마다 `eval_data_filter_ensure_prog()` 를 부르는 것 같습니다. 이전에는 `state == 1 && !signature_ok` 와 `state == 0` 일 때만 들어갔고, 배치가 되돌린 페이지를 도는 ALTER 테이블 질의에서 이 호출이 cycles 의 3.5% 였습니다.

```suggestion
      if (unlikely (pred_root->scan_prog_state == 0
		    || (pred_root->scan_prog_state == 1
			&& !expr_scan_pred_signature_ok (pred_root->scan_prog, filterp->val_descr,
							 EXPR_PROG_EXEC_STAMP (filterp->val_descr)))))
```

(suggestion 범위: 3561-3564)

## src/storage/heap_file.c:10938

이 변경 뒤로 GCC 8.5 가 `heap_attrvalue_read()` 를 `heap_attrinfo_read_dbvalues()`·`heap_attrinfo_read_dbvalues_without_oid()` 에 인라인하지 않게 된 것 같습니다(`-fdump-ipa-inline-details` 에서 develop 은 big_speedup 으로 인라인, head 는 `max-inline-insns-auto limit reached`, release 크기 0x83c -> 0x1f3). 그래서 행 경로가 컬럼마다 함수 호출을 하나 더 하게 되어, 11컬럼을 읽는 배치 밖 스캔에서 명령어 수가 develop 대비 +4.1% 였습니다. 힙 스캔·인덱스 조회·인덱스 생성이 모두 이 함수를 지나니, `heap_rec_layout_init()` 는 원래 본문으로 두고 `heap_rec_layout_init_repr()` 는 배치에서만 쓰는 것은 어떨까요?

## src/query/query_executor.c:4772

`qdata_key_sketch_add()` 가 키를 `qdata_hash_agg_hkey()` 로 해시하고 바로 아래 `mht_get()` 이 같은 키를 다시 해시해서, 표가 넘치지 않는 해시 GROUP BY 도 행마다 해시를 두 번 하는 것 같습니다. 배치가 거절한 `group by l_shipmode`(문자열 키)에서 4.4%, `group by l_orderkey` 에서 3.6% 였습니다. 해시를 한 번 구해 같이 쓰거나, 표가 처음 넘칠 때 표의 키로 스케치를 채우고 그 뒤 행부터만 더하는 것은 어떨까요?

## src/query/expr_batch.c:4217

NIT: NUMERIC SUM/AVG 가 값마다 `numeric_sum_acc_add_expr_val()` 을 불러서, Q1 모양에서 이 누산(`numeric_sum_acc_add_core` 포함)이 cycles 의 29% 였습니다. 청크 안에서는 같은 scale 끼리 int128 로 모아서(0 은 건너뛰고, 넘치면 지금처럼 행 경로) 청크당 한 번 더하는 것은 어떨까요?

## src/query/expr_batch.c:498

NIT: 가리킨 NUMERIC 셀을 행마다 `numeric_agg_expr_from_disk()`(다른 파일이라 PLT 경유 호출, 바이트마다 128비트 시프트)로 풀어서, `l_quantity < 24` 모양에서 이 함수 자체가 10.2% 였고 호출 지점까지 합치면 `eb_raw_kid()` 샘플의 절반이었습니다. 계수가 8바이트 이하면 여기서 `static inline` 으로 바로 읽는 빠른 경로를 두는 것은 어떨까요?

## src/query/expr_batch.c:3152

NIT: `heap_page_collect_visible()` 이 이미 MVCC 헤더를 읽었는데, 여기서 행마다 `OR_HEADER_SIZE` 를 두 번(`or_header_size()` 함수 호출) 다시 계산하는 것 같습니다(`l_quantity < 24` 모양 4.3%). 수집할 때 헤더 크기를 `HEAP_PAGE_ROW` 에 같이 남기는 것은 어떨까요?

## src/query/query_hash_join.c:4916

NIT: build 쪽이 2^20 행 이하면 항상 필터를 만드는데, 모든 행이 매치되는 조인(`l_suppkey = s_suppkey`, 10만 키)에서는 `dropped: 0` 이면서 `hjoin_rtf_pass()` 가 직렬 cycles 의 9.2% 였고, 그 대부분이 `slots[]`(2MB)·`used[]`(256KB) 두 배열을 따로 읽는 메모리 대기였습니다. SF10 Q9 에서도 nation(25키, dropped 0)·supplier(dropped 1.2%)에 필터가 붙었습니다. 처음 몇 천 행에서 걸러지는 비율이 낮으면 끄고, 키와 사용 표시를 한 배열에 두는 것은 어떨까요?

## src/query/expr_batch.c:3992

NIT: `eb_load_leaf_constants()` 가 청크마다 불려서 NUMERIC 리프마다 10^38 을 곱셈 루프로 만들고 int128 나눗셈(`__divti3`)을 하는 것 같습니다(Q6 모양 1.6%). 실행 동안 상수가 바뀌지 않으면 한 번만 계산하는 것은 어떨까요?

---

## 답글: comment 4335794820 (src/query/expr_batch.c:3155)

비용을 재 봤습니다. lineitem 200만 행을 복사한 뒤 `add column` 한 테이블에서 `l_quantity < 24` 필터가 23,878 페이지 중 23,875 페이지를 행 경로로 갔고, 명령어 수가 develop 대비 +10.1%(Q6 모양 +7.4%), 시간은 +14~23% 였습니다. 페이지마다 `heap_page_collect_visible()` 이 가시성을 한 번 더 판정한 뒤 행 경로가 같은 페이지를 다시 걷는 몫이라, 본문에 적는 것에 더해 같은 사유로 연속 몇 페이지 되돌아오면 그 스캔은 배치를 끄는 것은 어떨까요?
