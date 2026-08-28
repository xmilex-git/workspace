# 병렬 BUILDVALUE 누산기의 힙 소유권은 패스 시작에서 빌리고 패스 안에서 반납한다

병렬 스칼라 집계(`RESULT_TYPE::BUILDVALUE_OPT`)에서 원본 XASL 누산기
(`AGGREGATE_TYPE::accumulator.value` / `value2`)의 버퍼 소유권을, 병렬 스캔 패스가
몇 번 반복되든 성립하는 불변식으로 재정의한다. 워커 병합이 도는 동안 누산기 버퍼는
항상 heap 0(malloc)에 있어야 하고, 코디네이터 heap으로의 이주는 패스마다 반납으로만
일어난다. 파티션 스캔에서 병렬 BUILDVALUE를 끄는 게이트 방식은 채택하지 않는다.

CBRD-27327: 해시 파티션 테이블에 `MIN(varchar)` / `MAX(varchar)`를 수행하면
`munmap_chunk(): invalid pointer`로 서버가 abort 한다.

## 문제

두 지점이 서로 다른 할당자를 가정한다.

- 워커 병합 `finalize_node` (`px_scan_result_handler.cpp:2506`)은 private heap을 0으로
  바꾼 뒤 병합한다. heap 0에서 `db_private_alloc/free`는 `malloc/free`다. 워커 heap은
  태스크 종료와 함께 사라지므로 결과를 살리기 위한 의도적 선택이다.
- 코디네이터 `read_node` (`px_scan_result_handler.cpp:1228-1240`)은 그 값을 코디네이터의
  private heap으로 옮긴다. 최종 teardown `qexec_clear_agg_list`
  (`query_executor.c:2298-2317`)가 코디네이터 heap으로 해제하기 때문이다.

`read()`가 한 번만 돌면 규약이 성립한다. 그러나 파티션 프루닝
(`qexec_init_next_partition`, `query_executor.c:8915`)이 파티션마다 스캔을 재오픈하고,
`manager::reset()` (`px_scan.cpp:2036`)이 result handler를 재생성하되 `m_orig_agg_list`는
같은 원본 누산기를 가리킨다. 그래서 2번째 패스의 `read_node`가 코디네이터 lea heap
포인터를 heap 0에서 `free()` 한다.

세 result type 중 BUILDVALUE_OPT만 취약한 구조적 이유: 나머지 둘은 `read_finalize()`에서
패스 산출물을 전부 파괴하지만(`px_scan_result_handler.cpp:164-224`),
`result_handler<BUILDVALUE_OPT>::read_finalize()` (`px_scan_result_handler.cpp:1365-1367`)는
빈 함수라 재이주된 포인터가 태그 변경 없이 다음 패스로 넘어간다.

## Considered Options

- **파티션 스펙에서 병렬 BUILDVALUE 게이트**(`spec->parts != NULL`): 기각.
  `BUILDVALUE_OPT`는 세 스캔 타입 모두에 인스턴스화돼 있어(`px_scan.cpp:2186/2189/2192`)
  게이트를 세 군데에 달아야 하고, 병렬 집계의 주 대상인 대형 파티션 테이블에서 최적화를
  통째로 잃는다. 증상 회피이지 원인 수정이 아니다.
- **`read_finalize()`에서 heap 0으로 되돌리기**(패스 끝 반납): 기각.
  `read_finalize`는 `manager::reset()` (`px_scan.cpp:2041`)뿐 아니라 `manager::end()`
  (`px_scan.cpp:2158`)에서도 불리고, `end()`는 `scan_end_scan` 즉 쿼리 최종 종료 시에도
  실행된다. 여기서 되돌리면 마지막 패스 뒤 누산기가 malloc 상태로 남아 최종 teardown이
  같은 방식으로 터진다. 되돌리기는 패스 끝이 아니라 **패스 시작**에 걸어야 한다.
- **워커 병합을 코디네이터 heap에서 수행**: 기각. lea private heap은 스레드 안전하지 않고,
  코디네이터는 `read_initialize` 등에서 자기 heap을 동시에 쓸 수 있다. 기존 설계가 heap 0을
  고른 이유가 정확히 이것이다.
- **집계 완료 시점(`qexec_end_buildvalueblock_iterations`, `query_executor.c:15279`)에서
  단 한 번 이주**: 기각하지 않았으나 채택도 안 함. 불변식은 가장 깨끗하지만
  `query_executor.c`와 XASL 플래그를 건드리는 교차 모듈 변경이 되고, 직렬 경로에서는
  이주가 오히려 유해하므로 조건 플래그가 필수다. 잔여 위험 창은 채택안과 동일하다.

## Decision

패스 시작에 빌리고(borrow) 패스 안에서 반납한다(return).

- **빌림**: `manager::next()`의 `if (!m_task_started)` 블록 안, `start_tasks()` 바로 앞에서
  코디네이터 heap → heap 0으로 재이주한다.

  처음에는 `manager::open()`(handler 생성 직후)에 두려 했으나 **기각**했다. `open()`은 패스당
  한 번이 아니다 — `scan_open_*` 경로로 한 번, 이어서 `scan_next_scan_block`
  (`scan_manager.c:4888`) → `scan_reset_scan_block_parallel_heap_scan` (`px_scan.cpp:189`)
  → `manager::reset()` → `open()` 으로 또 한 번 불릴 수 있다. 그 사이에 `read()`가 없으므로
  빌림이 두 번 일어나고, 두 번째 빌림은 이미 heap 0에 있는 malloc 버퍼를 코디네이터 heap으로
  해제한다 — 고치려던 것과 똑같은 오해제를 반대 방향으로 만든다.

  `m_task_started`는 `open()`에서만 false가 되고(`px_scan.cpp:1808`) `start_tasks()`에서만
  true가 된다(`px_scan.cpp:1832`). 즉 "이 패스에서 워커가 아직 안 떴다"를 이미 정확히
  표현하는 기존 상태다. 여기에 빌림을 걸면 `open()`이 몇 번 불리든 빌림은 패스당 한 번이고,
  같은 `next()` 호출 안에서 `read()`가 반드시 뒤따르므로 반납과 1:1로 짝지어진다. 새 상태
  변수를 만들지 않고 짝을 보장하는 방법이다. 이 시점에는 워커가 아직 없으므로 경합도 없다.
- **반납**: 기존 `read_node`의 재이주를 그대로 둔다. 단일 패스 동작은 현행과 비트 동일하다.

불변식 한 줄: **워커가 도는 동안 누산기는 항상 heap 0, 워커가 없는 동안 항상 코디네이터 heap.**
빌림은 워커가 생기기 직전, 반납은 워커가 모두 끝난 직후에 일어난다.

구현은 기존 구조에 방향 인자를 태우는 것으로 끝낸다. 새 클래스·새 멤버·새 상태 플래그를
만들지 않는다.

- `read_node<F>`에 `bool to_heap0`를 추가한다. 이 함수의 분기는 이미 전부 방향 무관이고
  (조기 `return S_SUCCESS`, COUNT의 bigint 설정), 방향에 의존하는 것은 세 군데 반복되는
  clone/clear 블록뿐이다.
- 그 블록을 파일 정적 헬퍼 하나로 합친다. 3벌이 1벌이 되므로 순 증가분은 거의 없다.
- `read()` 안의 함수별 `switch`를 `read_nodes (thread_p, to_heap0)`로 추출해 반납·빌림이
  같은 분기표를 쓰게 한다. 빌림 대상이 반납 대상과 어긋날 여지가 구조적으로 사라진다.
- `result_handler<BUILDVALUE_OPT>` 생성자에 `THREAD_ENTRY *`를 추가하고 거기서
  `read_nodes (thread_p, true)`를 호출한다. 생성자는 패스마다 정확히 한 번, `open()` 안에서,
  코디네이터 스레드로, 워커 기동 전에 실행되므로 별도 훅이 필요 없다.
- `read_finalize()`는 빈 함수 그대로 둔다. 미반납 상태를 되돌리는 fallback은 넣지 않는다
  (아래 잔여 위험 참조).

## Consequences

- 파티션 테이블에서 병렬 스칼라 집계가 유지된다. HEAP/LIST/INDEX 세 스캔 타입이
  `result_handler<BUILDVALUE_OPT>` 단일 인스턴스(`px_scan_result_handler.cpp:2667`)를
  공유하므로 한 번의 수정으로 셋 다 덮인다.
- 불변식이 "패스 횟수와 무관"하게 서술되므로, 정적 독해로 배제하지 못한 재진입 경로
  (CONNECT BY, 재귀 CTE의 buildvalue 블록 재실행)까지 자동으로 덮인다.
- 비용은 집계 노드당 값 1개를 패스마다 2회 복사하는 것이다. 행당이 아니라 패스당이므로
  무시할 수 있다.
- 빌림과 반납의 함수별 적용 대상이 어긋나면 새 누수/오해제가 생긴다. 예를 들어 MEDIAN·
  PERCENTILE 계열의 `value2`는 GROUP_CONCAT 구분자 메타데이터라 `read_node`가 재이주하지
  않으므로, 빌림도 같은 규칙으로 제외해야 한다. 두 쪽이 같은 술어를 공유하도록 강제한다.
- 빌린 뒤 `read()`가 실행되지 않는 경로는 **닫아야 했다**. 처음에 이 창을 "선재 위험"으로 보고
  Q6에서 방치하기로 했으나, 외부 리뷰(Codex)가 이 판단이 틀렸음을 지적했고 검증 결과 맞았다.
  수정 전에는 패스 N≥2 시작 시점에 누산기가 코디네이터 heap에 있었으므로 `start_tasks()` 실패 시
  teardown이 코디네이터 heap에서 해제해 **정상**이었다. 빌림이 그것을 heap 0으로 옮겨놓고 실패로
  빠지면 오해제가 된다 — 즉 선재 창이 아니라 이 변경이 **새로 만든** 실패 경로다. `start_tasks()`는
  워커를 일부 push한 뒤에도 실패할 수 있으므로(`px_scan.cpp:1819`), 인터럽트를 세우고
  `release_workers()`로 드레인한 뒤(내부에서 `wait_workers()`를 먼저 부른다) 빌림을 되돌린다.
- 남는 잔여 위험은 `rehome_agg_list`의 리스트 순회가 clone 실패 시 원자적이지 않다는 것이다.
  노드 3에서 실패하면 노드 1·2는 이미 옮겨진 상태로 남는다. 롤백에도 할당이 필요하므로 OOM
  상황에서 신뢰할 수 있는 복구가 불가능하다. 반납 방향은 수정 전에도 동일하게 비원자적이었다.
- **인터럽트 경로의 두 번째 결함도 같은 계약으로 해결한다.**
  `clear_agg_accumulators_on_0_heap_id` (`px_scan_result_handler.cpp:1145`)는 모든 집계의
  `value`·`value2`를 조건 없이 heap 0에서 해제했다. 그러나 GROUP_CONCAT의 `value2`는 병합 결과가
  아니라 XASL 스트림에서 복원된 구분자다. `or_unpack_value`가 `or_get_value(..., copy=true)`를
  부르므로(`object_representation.c:4926`) 자기 버퍼를 소유하고, XASL 클론을 쓰면
  `clear_value2_at_clone_decache`가 켜져(`stream_to_xasl.c:6016-6019`) **실행 단위 teardown이
  의도적으로 건너뛴다**(`qexec_clear_agg_list`, `query_executor.c:2302-2318`). 매 실행 해제하면
  다른 힙의 버퍼를 해제할 뿐 아니라 캐시된 플랜에 댕글링 구분자를 남긴다.

  방향 인자를 `bool`에서 3값 enum(`BORROW`/`RESTORE`/`DISCARD`)으로 넓혀, 인터럽트 경로가 같은
  함수별 분기표를 타고 `DISCARD` 하도록 했다. 병합이 실제로 할당한 것만 해제되므로 GROUP_CONCAT의
  `value2`는 손대지 않고 STDDEV/VARIANCE의 `value2`(합제곱)는 정상 해제된다. 블랭킷 해제 함수는
  삭제했다. `DISCARD`는 clone을 하지 않으므로 에러 경로에서 할당이 없다는 이점도 있다.

  MEDIAN/PERCENTILE은 **해당하지 않는다.** 구분자 피연산자가 없어 XASL에 두 번째 값이 패킹되지
  않으므로 `accumulator.value2`가 NULL이고, 애초에 누산기 병합이 아니라 list_id 전달 경로다.
  처음에 이들도 해당한다고 적었던 것은 오독이었다 — `rehome_node`의 기존 주석이 세 함수를 한
  분기로 묶으면서 GROUP_CONCAT의 구분자 설명을 MEDIAN 쪽에 얹어 놓은 것이 원인이다.

- **워커 클론 쪽에도 같은 결함이 하나 더 있었다.** `write_finalize()`의 인터럽트 정리 블록이
  워커 자신의 XASL 클론(`cur_agg_p`)의 `accumulator.value`·`value2`를 조건 없이 해제했다.
  GROUP_CONCAT의 `value2`는 클론과 함께 넘어온 구분자지 워커가 할당한 것이 아니므로, 워커의
  할당자에 남의 포인터를 넘겨 `mspace_free`에서 abort 한다. 두 해제 모두 애초에 불필요하다 —
  `task::finalize`가 `write_finalize` 직후(`px_scan_task.cpp:465` → `:502`) 같은 클론에 대해
  `qexec_clear_xasl`을 부르고, 그 경로가 클론 decache 플래그를 지킨다. 두 해제를 제거했다.

  이 결함은 코디네이터 쪽 수정(위 항목)으로는 고쳐지지 않는다. 재이주 계약은 `m_orig_agg_list`만
  다루고 이쪽은 워커 클론이기 때문이다. **처음 수정에서 놓쳤고, 인터럽트 경로 재현 실험에서
  드러났다.**

### 증거 수준

세 수정의 근거가 서로 다르므로 구분해 둔다.

- 파티션 재진입 힙 소유권: 코어 덤프 2종(코디네이터 `read_node`, 워커 `finalize_node` — 데이터에
  따라 어느 쪽이 먼저 터지는지 갈린다) + 동일 베이스 음성 대조군 + 20종 집계 3-arm 스윕.
- 워커 클론 구분자 해제: 코어 덤프 + 동일 트리거 A/B. 트리거는
  `select group_concat(s order by s separator '-|-') from tp where id / (id - 2500) > 0` —
  스캔 도중 0으로 나누기가 워커 인터럽트를 세운다.
- 코디네이터 구분자 해제: `clear_value2_at_clone_decache` 계약 위반이라는 코드 논증 + 인터럽트와
  정상 실행을 5라운드 번갈아 돌려 캐시된 플랜의 구분자가 매번 온전함을 확인한 실측. 단독 크래시
  재현은 얻지 못했다 — 세 번째 결함이 먼저 서버를 죽여 재실행 자체가 불가능했고, 그것을 고친 뒤에야
  이 실험이 가능해졌다.
