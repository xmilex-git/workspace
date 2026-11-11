# CBRD-28005 미리 읽기와 묶음 조회 구현 계획

결정은 `docs/tla/CBRD-28005/MAP.md`의 D1~D37, claim은 C3~C8이다. 2026-11-10에 읽기 장치를 io_uring에서 OS 힌트로 바꿨다(D34, ADR 0055). 이 문서는 단계와 완료 조건만 적는다.

- 작업 트리: `~/dev/cubrid-worktree/CBRD-28005`, 브랜치 `CBRD-28005-aio`(origin/develop `2dd94e32a`). push는 fork로만 하고, 사용자가 말할 때 한다.
- 새 소스 파일을 만들지 않는다.
- 새 경로는 파라미터로 켠다. 기본값에서는 지금 경로를 그대로 탄다. (2026-11-11에 바뀜: 읽기 힌트와 bitmap heap scan에는 켜고 끄는 파라미터를 두지 않는다. 아래 "세 이슈로 나눔" 참고)
- 단계마다: optdebug와 release 빌드, 해당 CTP, 모델이 있는 단계는 계측 빌드의 실행 기록으로 trace validation.

## 읽기 형태별로 무엇이 I/O를 한꺼번에 내게 하나

| 읽기 형태 | 수단 |
|---|---|
| 힙 풀 스캔 | 파일 순서(섹터 순서)로 읽는다. OS read-ahead가 순차 읽기로 알아본다. 힌트는 보조다 |
| 인덱스 조회가 많은 non-covering 스캔, 순서 불필요 | 전체 범위 묶음: 인덱스 단계에서 섹터 비트맵을 채우고, 힙 단계에서 표시된 페이지만 파일 순서로 읽는다(병렬). 표시가 드물면 힌트가 동시성을 준다 |
| 순서가 필요한 인덱스 스캔, LIMIT, 선택도가 낮은 조회 | OID 버퍼 크기의 묶음 + 읽기 힌트 |
| 중첩 루프 안쪽 조회 | 배치 조인 + 읽기 힌트 |

## 1단계: 읽기 힌트 (D34)

| 항목 | 코드 |
|---|---|
| 파라미터 | `system_parameter.c` `read_ahead_hint`(bool, 서버, 기본 no) |
| 힌트 | `file_io.c` `fileio_read_ahead_hint`: `posix_fadvise (POSIX_FADV_WILLNEED)` |
| 버퍼 쪽 | `page_buffer.c` `pgbuf_read_ahead (thread_p, vpids, n)`: 버퍼에 없는 페이지만, 이어진 페이지는 한 범위로 힌트. 상태를 남기지 않는다 |
| 첫 사용처 | 병렬 힙 스캔이 섹터를 잡을 때 그 섹터의 페이지(`px_scan_input_handler_heap.cpp`) |

완료 조건: 두 빌드 green, 기본값에서 sql/medium CTP가 develop과 같음, `read_ahead_hint=yes`에서 CTP 같음, 콜드 측정.

측정(2026-11-10): 병렬 힙 스캔은 힌트를 켜면 콜드에서 느려졌다(중앙값 0.55초 대 0.70초, `docs/research/async-io-read-ahead-sizing.md`). 그래서 병렬 힙 스캔의 힌트 호출은 뺐다. 힌트의 사용처는 3단계와 4단계의 흩어진 읽기다.

## 2단계: 힙 풀 스캔의 페이지 목록 순서 (C3~C5)

- 직렬 힙 풀 스캔을 페이지 목록(섹터) 순서로(D10). 인덱스 빌드, 통계, unloaddb의 힙 읽기도 같다.
- 스캔이 읽은 페이지는 unfix 때 LRU 바닥으로(D15).
- 근거 측정: CBRD-28010(체인 순서가 파일 순서와 어긋난 테이블의 콜드 직렬 스캔 7초 대 27초).

## 3단계: OID 묶음 조회 (C6, C7)

- OID 버퍼 크기의 묶음: 페이지별로 묶어 힌트하고 조회한다. 순서가 필요하면 키 순서로 내보낸다(D16, D18).
  - 병렬 인덱스 스캔 워커도 한 키의 OID들이 있는 힙 페이지를 조회 전에 알린다(`leaf_slot_walker::read_ahead_key_oids`, 2026-11-11).
  - 구현(2026-11-10, `scan_manager.c`): 조회 순서는 지금 그대로(버퍼 순서) 두고, 조회할 OID보다 64개 앞까지의 힙 페이지를 `pgbuf_read_ahead`로 알린다(`scan_index_read_ahead`). 창의 페이지가 모두 버퍼에 있으면 다음 OID들을 묻지 않고 지나가며, 그 수를 64에서 65,536까지 두 배씩 늘린다. `read_ahead_hint=yes`일 때만 동작한다.
- 전체 범위 묶음(D25~D33, D36): 계획 생성 때 정한다(D26). 스냅샷을 받은 뒤 섹터 목록을 받는다(D30, CBRD-27967과 같은 순서). 인덱스 단계는 지금의 병렬 인덱스 스캔 워커가 공유 섹터 비트맵 하나에 atomic OR로 표시한다(D36). 모든 인덱스 워커가 끝난 뒤(D33) 힙 단계 워커가 섹터를 잡아 표시된 행을 본다. 섹터 목록 밖의 OID는 버린다(D30).
- 섹터 비트맵의 상한은 새 파라미터 `index_scan_oid_bitmap_size`다(D36, 기본 16MB, 세션 변경 가능; 2026-11-11에 `max_hash_list_scan_size`에서 바꿈). 스캔을 열 때 페이지당 폭을 정한다(D37): min(슬롯 상한, 상한의 비트 수 ÷ (섹터 수 × 64)). 64의 배수로 내리지 않는다(2026-11-11 측정 뒤 바꿈). 폭 이상의 슬롯 번호는 그 페이지를 페이지 단위로 표시하고, 폭이 64에 못 미치면 전부 페이지 단위로만 표시한다. 페이지 단위로 표시된 페이지는 힙 단계가 모든 행을 읽어 인덱스 조건(키 범위, 키 필터)을 힙 행에서 다시 확인한다. 페이지 단위 표시를 위해 XASL은 인덱스 조건을 힙 행에서 평가하는 술어를 함께 가진다.
- 힙 단계는 같은 인덱스 스캔 spec의 힙 조회 반쪽(`scan_next_index_lookup_heap`이 하는 일)을 비트맵으로 구동한다. XASL의 참조는 바뀌지 않는다.
- 페이지 단위 표시의 재확인 술어는 XASL에 이미 있다: 인덱스 스캔 spec의 `where_range`(범위 조건과 키 필터를 힙 행에서 평가하는 술어, `xasl_generation.c` `pt_get_mvcc_reev_range_data`, MVCC 재평가용)를 그대로 쓴다. XASL 생성은 바꾸지 않는다.
- 구현(2026-11-10, `px_scan_*`): 병렬 인덱스 스캔의 입력 핸들러가 공유 비트맵과 단계 경계를 갖는다(`px_scan_input_handler_index`). 워커는 OID를 처리하는 자리(`leaf_slot_walker::process_oid`)에서 힙 조회 대신 표시하고, 자기 인덱스 단계가 끝나면 모든 워커의 인덱스 단계가 끝나기를 기다린 뒤 섹터를 하나씩 잡아 표시된 페이지를 읽는다(`task::bitmap_heap_phase`). 섹터에 표시가 없으면 건너뛴다. `bitmap_heap_scan=yes`(서버 파라미터, 기본 no)일 때만 동작한다.
- 첫 구현이 D26과 다른 점: 전체 범위 묶음으로 갈지는 계획 생성이 아니라 병렬 인덱스 스캔으로 올리는 자리(스캔 시작)에서 정한다. 대상은 병렬 인덱스 스캔이 된 non-covering 스캔 전부이고, 찾을 행 수 추정 기준은 아직 없다. 제외: covering, 개수만 세는 스캔, GROUP BY 생략, multi-range, index skip scan, 필터 인덱스, 함수 인덱스, prefix 인덱스, MVCC를 쓰지 않는 클래스.

## 4단계: 배치 조인 (C8)

설계(D19~D24, D28, D35)는 다음과 같았다.

- 바깥 행을 OID 버퍼가 찰 때까지(D24) 또는 저장한 바깥 행이 같은 바이트 크기에 닿을 때까지(D28) 모아 안쪽 조회를 한꺼번에 한다(D19). 조인 한 단계만 묶는다(D20).
- inner, left outer, semi, anti 조인과 파티션된 안쪽을 함께 다룬다(D21). following join과 FOR UPDATE는 행 단위로 둔다.
- 순서 모드는 계획 생성 때 정한다(D22). memoize는 묶음의 바깥 행마다 먼저 확인한다(D23).

구현한 것(D38, 서버 파라미터 `nl_join_batch`, 기본 no)은 이 설계를 줄인 것이다.

- 안쪽이 힙을 조회하는 단순 인덱스 스캔(키 하나 또는 범위 하나)인 조인 단계가, 자기에게 온 바깥 행을 값 목록의 복사본으로 쌓고 행마다 안쪽 인덱스만 먼저 읽어 OID를 모은다. 묶음이 닫히면 모은 OID의 힙 페이지를 OS에 한꺼번에 알리고(1단계의 힌트), 쌓은 행을 온 순서대로 기존 행 경로에 다시 넣는다. 행 경로는 OID를 이미 읽은 상태에서 시작한다. 결과 행과 순서는 행 단위 조인과 같다.
- 묶음은 OID 16개에서 시작해 닫힐 때마다 배로 커져 OID 버퍼 하나(D24)까지 간다. 몇 행만 읽고 멈추는 조인(LIMIT, EXISTS)이 앞질러 읽는 양을 줄이기 위해서다.
- memoize가 가진 키, NULL 조인 값, OID가 버퍼 하나보다 많은 행은 OID 없이 쌓고 행 경로가 직접 읽는다(D35의 "묶음에 걸친 행"은 만들지 않았다).
- 힌트할 것이 없던 묶음(모든 페이지가 버퍼에 있거나 한 페이지) 뒤에는 바깥 행 64개를 행 단위로 조인하고, 그런 묶음이 이어지면 배로 늘려 65,536개까지 간다. 데이터가 버퍼에 다 있을 때의 비용을 없애기 위해서다.
- 행 단위로 둔 것: semi, anti, following 조인(D21에서 줄임), 바깥이 테이블 스캔이나 리스트 스캔이 아닌 경우, 바깥에 상관 부질의나 경로식이 있는 경우, 첫 스캔이 자기 행 루프에서 하는 일이 있는 경우(instnum, if·after-join 조건, CONNECT BY, GROUP BY skip).
- 만들지 않은 것: 자유 순서 모드(D22), 단계 사이 연결(D20: 한 단계의 묶음은 윗단계의 현재 행에 대한 바깥 행이 끝나면 닫힌다).
- 같이 고친 것: 인덱스 스캔을 키 범위 중간에서 되감을 때 `is_key_partially_processed`가 남아 다음 탐색이 리프 레코드의 OID를 건너뛰던 결함(develop에도 있다, workspace #638), 되감을 때 키 범위 값을 해제하지 않던 것.

## 모델

- 전체 범위 묶음은 `BitmapScan`(단계 경계, 공유 비트맵의 atomic OR, 페이지 단위 표시의 재확인, 정확히 한 번: C6), 배치 조인은 `BatchJoin`(C8)이다. 결과는 `docs/tla/CBRD-28005/MAP.md`의 `## Result`.
- `BatchJoin`이 구현에 요구하는 것: 배치를 넘는 바깥 행은 이전 배치에서 match가 있었는지를 들고 간다(left outer의 NULL 행, semi, anti). no-match 판정은 그 행의 마지막 인덱스 항목에서만 한다. 이어 읽기는 멈춘 항목 다음부터다(파티션 처음이 아님). 순서 모드는 바깥 순서, 그다음 인덱스 순서로 내보낸다. memoize hit은 저장된 결과를 배치가 끝날 때까지 복사하거나 붙잡아 둔다(memoize가 그 사이에 저장소를 해제할 수 있다).
- D35: 배치를 넘은 바깥 행의 결과도 마지막 배치가 닫힐 때 memoize에 넣는다. D36: 섹터 비트맵은 공유 하나, atomic OR, 상한을 넘으면 페이지 단위 표시.
- 행 단위와 페이지 단위는 스캔을 열 때 한 번 정하고, 폭은 상한에서 역산하며, 폭을 넘는 슬롯 번호는 그 페이지를 페이지 단위로 표시한다(D36, D37, 사용자 확인 2026-11-10).
- `AsyncRead`와 그 실행 기록은 채택하지 않은 io_uring 대안의 기록이다. `ReadStream`, `OidBatch`는 그 장치를 전제로 쓴 부분(ring, 읽기 중 프레임)을 걷어 내고 다시 쓴다.

## 지금 상태 (2026-11-11)

- fork(`xmilex-git/cubrid`)의 브랜치 `CBRD-28005-aio`, 커밋 `4c4e04f7b`(origin/develop `e30370dc0` 위, 2026-11-11 push, PR 없음)에 있는 것: 읽기 힌트(`read_ahead_hint`, 기본 no)와 그 사용처 두 곳(직렬 인덱스 스캔의 OID 버퍼, 병렬 인덱스 스캔 워커의 키별 OID), 전체 범위 묶음(`bitmap_heap_scan`, 기본 no; 상한 `index_scan_oid_bitmap_size`, 기본 16MB).
- 빌드: optdebug와 release 모두 설치됨(`~/optdebug/CUBRID-CBRD-28005`, `~/release/CUBRID-CBRD-28005`).
- 정합성: 폭 1,362, 132, 98, 70, 0비트에서 질의 6개(범위, 데이터 필터, 키 필터 인덱스, IN 목록, LIKE, 행 출력)가 기존 경로와 같다. 삭제, 키 변경, 행 확장, 삽입 뒤와 열린 트랜잭션 옆에서도 같다(optdebug, `.git_ignored_dir/scratch/aio-bench/bitmap/`). 아래 페이지 fix 수정과 develop `e30370dc0` 위로 올린 뒤 optdebug와 release 모두 폭 1,362, 132, 98, 0에서 다시 비교해 차이 0줄이다.
- 힙 단계의 페이지 fix(2026-11-11): 행 비트로 표시된 페이지도 행을 읽기 전에 `fix_bitmap_page`로 "반납됐을 수 있는 페이지"로 fix하고 마지막 행까지 잡는다. 실행 기록을 만들던 중, 표시한 뒤 vacuum이 반납한 페이지의 행을 조회하면 기존 행 조회 코드(`heap_prepare_object_page`의 `OLD_PAGE` fix)가 optdebug에서 assert로 멈추는 것을 봤다(release는 오류를 지우고 건너뜀). 리프의 가시성 확인을 끈 계측 빌드에서만 재현했다. 스냅샷 하나로 도는 스캔은 그런 행을 표시하지 않는다.
- 행 조회가 잡은 페이지를 다시 fix하지 않게 했다(`process_bitmap_row`: 조회 동안 스캔 캐시의 `cache_last_fix_page`를 켬). 행 단위 경로의 페이지 fix가 행 수에서 페이지 수로 준다(lineitem 10%: 6,000,257 → 720,232).
- CTP(optdebug, sql과 medium 전체, 테스트케이스 develop, 커밋 `4c4e04f7b`와 같은 코드): 기본 파라미터에서 sql 17,760 통과와 2 실패(`r_outer_join.sql`, `cbrd_27762.sql`: 변경 전 기준 실행과 같은 두 건), medium 975 통과(`/home/cubrid/ctp-run-out/workspace/sql-20261110T182840Z-2201547`). `read_ahead_hint=yes`, `bitmap_heap_scan=yes`에서 sql 17,753 통과와 9 실패, medium 975 통과(`sql-20261110T184138Z-2567017`). 늘어난 7건(cbrd_27624, cbrd_26722_index, cbrd_26722_index_overflow, cbrd_27100, cbrd_27100_histogram, cbrd_27404, cbrd_27689)은 정답 파일의 trace 출력에 `bitmap: ?`이 더해진 차이뿐이다(그 토큰을 지우면 7건 모두 차이 0줄). 코어 없음.
- 실행 기록 대조: 계측 빌드의 기록 9개가 `BitmapScan`에 수락되고 변조한 기록 6개가 거부됐다(`docs/tla/CBRD-28005/MAP.md`의 Trace validation). 섹터 목록 밖 OID 버림(144건, 두 지점 모두), 표시한 뒤 보이지 않게 된 행, vacuum이 지운 행(60건), 스캔 도중 반납된 페이지(20장, 행 단위와 페이지 단위 각각)가 들어 있다. 이 넷은 리프의 가시성 확인을 끄는 주입으로 만들었다.
- 측정: `docs/research/async-io-read-ahead-sizing.md`(마지막 절이 push한 코드의 값). JIRA CBRD-28005 댓글 4778287에 성능 결과와 결론을 올렸다.
- 배치 조인(4단계, 2026-11-11): 같은 브랜치의 커밋 `e802abfa7`(`4c4e04f7b` 위, 11개 파일 +786/-6, CI 포매터 적용, 2026-11-11 push). 서버 파라미터 `nl_join_batch`(기본 no), 안쪽 인덱스 스캔의 트레이스에 `nlbatch: N`(OID를 먼저 읽은 바깥 행 수).
  - 빌드: optdebug(`libcubrid.so.11.5` sha256 `b48749be…`)와 release(`f2f33a5a…`).
  - 정합성: 조인 스모크 2벌(`.git_ignored_dir/scratch/aio-bench/nlb/q.sql` 16문장, `q2.sql` 24문장: inner, left outer, 필터, 3테이블, 파티션된 안쪽과 바깥, memoize, LIMIT으로 멈추는 부질의의 재실행, 병렬 첫 스캔, 리스트 바깥, 집합 값 컬럼, 오류, 조인 DELETE)을 `nl_join_batch` 끔과 켬으로 돌려 두 빌드 모두 차이 0줄(239줄, 261줄).
  - CTP(optdebug, sql과 medium 전체, 테스트케이스 develop): 기본 파라미터에서 sql 17,760 통과와 3 실패, medium 975 통과(`sql-20261111T021302Z-833626`). 3건(cbrd_24419, cbrd_27616, cbrd_27889)은 develop `e30370dc0` optdebug 빌드에서도 결과 파일이 같다(차이 0줄). `read_ahead_hint`, `bitmap_heap_scan`, `nl_join_batch`를 모두 켠 실행은 sql 17,727 통과와 36 실패, medium 975 통과(`sql-20261111T022403Z-950686`): 위 3건과, 정답의 trace 출력에 `nlbatch: ?` 또는 `bitmap: ?`이 더해진 차이뿐인 33건(토큰을 지우면 차이 0줄). 두 실행 모두 코어 없음.
  - CTP가 찾아 고친 것: 키 범위 중간에서 되감긴 인덱스 스캔의 키 범위 값 미해제(optdebug의 자원 추적 assert), GROUP BY skip 조인의 키 시작 표시가 앞서 읽은 바깥 행과 어긋남(첫 스캔은 묶지 않게 함), 집합 값을 바깥 값 목록에 빌려준 뒤의 이중 해제(복사로 되돌림).
  - 실행 기록 대조: 계측 빌드의 기록 9개가 `BatchJoin`에 수락되고 변조한 기록 8개가 거부됐다(`docs/tla/CBRD-28005/MAP.md`의 Trace validation).
  - 측정: Q7 콜드 NVMe 70.3 → 44.1초, SSD 116.0 → 63.1초, 핫은 같다. Q9와 Q20은 그대로다(`docs/research/async-io-read-ahead-sizing.md`의 마지막 절).
  - 사용자 결정(2026-11-11, MAP D39): 이 범위로는 부족하다. TPC-H Q9와 Q20도 빨라져야 한다. 스냅샷이 중첩 문장으로 다시 만들어지는 문장도 그대로 묶는다(C8은 스냅샷이 바뀌지 않는 문장에 대한 것). 앞서 읽은 행의 오류는 받아들인다. `nlbatch` 토큰은 둔다.
  - 다음 작업: 병렬 스캔 워커의 첫 조인 단계(Q9), 상관 부질의 안쪽 조회(Q20). 하지 않은 것: semi/anti 조인, 단계 사이 연결.
- develop 결함 하나를 찾았다: 인덱스 스캔이 한 키의 overflow OID 중간에서 되감기면 다음 탐색이 리프 레코드의 OID를 건너뛰어 세미 조인이 행을 잃는다(develop `e30370dc0` release와 optdebug에서 재현, workspace #638). 이 작업 트리에는 `BTREE_RESET_SCAN`의 한 줄 수정이 들어 있다.
- 하지 않은 것: 2단계(힙 풀 스캔의 페이지 목록 순서), 전체 범위 묶음을 계획 생성에서 고르는 일(D26)과 힙 풀 스캔과의 비용 비교, `ReadStream`과 `OidBatch` 모델 재작성, 필터·함수·prefix 인덱스에서의 전체 범위 묶음, 힌트를 켰을 때의 핫 비용을 instructions 수로 확인하는 일, 스캔 도중 스냅샷이 바뀌는 실행(행마다 SQL을 실행하는 저장 프로시저)의 기록, 페이지 단위 표시 경로(`heap_next_1page`)가 행마다 페이지를 fix하는 것을 줄이는 일, PR.
- io_uring 1단계는 구현, 두 빌드, CTP, trace validation까지 마친 뒤 대안으로 돌렸다. 패치는 `docs/tla/CBRD-28005/io_uring-alternative/`에 있다.

## 세 이슈로 나눔 (2026-11-11 저녁, MAP D40~D43)

팀 결정으로 구현을 세 이슈로 나눴다. CBRD-28005는 조사 이슈로 남는다. 이슈마다 다른 세션이 이어서 한다. 브랜치는 이슈별로 나누지 않았다.

| 이슈 | 내용 | 버전 | 끝난 것 | 남은 것 |
|---|---|---|---|---|
| CBRD-28031 | 읽기 힌트 (ADR 0055) | 11.5 예상 | 구현, 파라미터 삭제(항상 동작), JIRA 본문과 design.md, test.md | 힌트만 든 브랜치의 빌드와 게이트, 페이지가 버퍼에 다 있을 때의 비용 확인, PR |
| CBRD-28032 | bitmap heap scan (ADR 0056) | 다음 버전 예상 | 병렬 실행, trace 2단계, 모델 `BitmapScan`과 trace validation | 옵티마이저의 선택, 한 스레드 실행, 접근 명세 분리, SQL 힌트 둘, 플랜 출력, `bitmap_heap_scan` 파라미터 삭제, 기준 값 실측 |
| CBRD-28033 | 배치 조인 (ADR 0057) | 다음 버전 예상, 도입 검토 중 | 조인 한 단계, 병렬 워커의 첫 조인 단계, 모델 `BatchJoin`과 trace validation(워커 확장은 기록 없음) | 도입 결정, 깊은 단계 연결(`docs/tla/CBRD-28033/BatchChain`), 상관 부질의 조회, semi와 anti 조인, 파라미터 삭제 |

코드의 출발점:

- fork와 로컬 `CBRD-28005-aio` = `5eb88d442` (develop `e30370dc0` 위, 세 가지가 모두 들어 있음, 게이트함).
- 로컬 `CBRD-28005-aio-rebased` = `b53467cc3` (같은 내용을 develop `38c931e7d` 위로 올림, 빌드와 게이트 안 함).
- 로컬 `CBRD-28031` = `6d7bb2748` (develop `38c931e7d` + 힌트만, 8개 파일 +222/-1, 빌드와 게이트 안 함).
- 분할 패치: `.git_ignored_dir/scratch/aio-bench/split/` 의 `H.patch`(힌트), `HB.patch`(힌트 + bitmap), `HJ.patch`(힌트 + 배치 조인), `HBJ.patch`(전부). develop `38c931e7d` 기준 zero-context 패치이고 `git apply --unidiff-zero`로 적용한다. `HBJ`는 `b53467cc3`을 그대로 재현한다. `HJ`에는 bitmap 참조 두 줄이 남아 있어 손으로 빼야 하고, `HB`와 `HJ`는 컴파일해 보지 않았다.

`5eb88d442`의 게이트(optdebug, 컨테이너 CTP): 기본 lane sql 17,760 OK + 3 NOK(develop과 결과가 같은 3건), medium 975. bitmap과 배치 조인을 켠 lane sql 17,725 OK + 38 NOK(그 3건 + trace만 다른 35건), medium 975. core 없음.

이 디렉터리 전체의 `tla-check` 기록 실행과 MAP `## Result` 항목은 아직 하지 않았다(부분 실행 결과만 있다).

