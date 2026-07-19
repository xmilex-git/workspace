# Code review: `xmilex/bulkidx/noredo-parallel-r304-wip`

- 기준: `origin/develop` (`39bdc0a776405dac6f272210454dd7ca3bf1145e`)
- 대상: `xmilex/bulkidx/noredo-parallel-r304-wip` (`82f2d7639ebddab3311b43c6c4ac9a97c75813f9`)
- 변경 규모: 29 files, +8,091 / -968
- 리뷰 방식: Architect 2개 lane(storage, recovery) + Critic 2개 lane(client/server, contracts), read-only 정적 리뷰
- 결론: **BLOCK / REQUEST CHANGES**

성능 설계(B4 bounded bootstrap, B5 merge fusion)는 큰 폭의 개선을 만들었고 전체 방향도 합리적이다. 그러나 현재 브랜치에는 복구 시 데이터 손상, 잘못된 파일 삭제, marker 없는 no-redo index 공개, 혼합 버전 장애를 만들 수 있는 P1 문제가 남아 있다. 성능 결과와 별개로 아래 P1을 해결하기 전에는 병합하면 안 된다.

## P1 — 병합 차단

### 1. 복구 repair 페이지를 dirty로 표시하지 않음

- 위치: `src/storage/btree.c:32436-32440`
- `btree_bulk_unique_absent_repair`가 `spage_update`와 compensate log append를 수행하지만 `pgbuf_set_dirty`를 호출하지 않는다.
- 동일한 기존 변경 경로는 `src/storage/btree.c:33789-33808`에서 logging 후 dirty를 설정한다.
- 영향: 수정된 leaf가 checkpoint/eviction의 flush 대상에서 누락되어 복구 repair가 유실될 수 있다.
- 수정: write latch를 보유한 상태에서 compensate append 이후 `pgbuf_set_dirty (thread_p, leaf_page, DONT_FREE)`를 호출한다.

### 2. publication을 attach한 뒤 fallible marker append를 수행함

- 위치: `src/transaction/locator_sr.c:7550-7558`, marker allocation/packing `src/transaction/log_manager.c:3631-3652`
- FORCE top operation을 outer transaction에 attach한 다음 marker size 계산, allocation, packing을 수행한다. 이 단계 실패는 `locator_sr.c:7573`의 top-operation abort를 거치지 않고 직접 반환한다.
- 영향: 호출자가 outer transaction을 commit하면 no-redo index publication은 남지만 media recovery marker는 없는 상태가 될 수 있다.
- 수정: marker를 top operation이 아직 abort 가능한 시점에 pack/append하고, 모든 실패를 abort label로 보낸 뒤 마지막에 attach한다. 요구 순서는 `parent LSA < publication < marker < sysop attach < commit`이다.

### 3. irreversible 2PC informing 상태를 uncommitted로 분류함

- 위치: `src/transaction/log_manager.c:3625-3629`, 상태 전이 `src/transaction/log_recovery.c:2321-2340`, 분류 `:6999-7016`
- `log_is_irreversible_2pc_state`는 `TRAN_UNACTIVE_2PC_COMMIT_DECISION`만 인정하지만 analysis는 이후 상태를 `TRAN_UNACTIVE_COMMITTED_INFORMING_PARTICIPANTS`로 변경한다.
- 영향: commit이 이미 불가역인 crash point에서 bulk build를 uncommitted로 오분류하여 redo suppression/cleanup 결정을 잘못 내릴 수 있다.
- 수정: informing-participants 상태도 irreversible commit으로 처리하고 두 crash boundary를 테스트한다.

### 4. redo suppression이 파일 generation이 아니라 현재 VFID membership만 확인함

- 위치: `src/transaction/log_recovery.c:7122-7149`; cleanup identity check `:7634-7664`
- VFID가 drop 후 다른 정상 index에 재사용되면 오래된 marker가 새 파일의 redo까지 억제할 수 있다. cleanup은 나중에 identity mismatch를 보고 새 파일을 보존하므로, redo가 누락된 새 index가 살아남는다.
- 수정: suppression 자체를 `(VFID, collision-free generation, class/attr identity, LSA lifetime)`에 결합하거나 LSA 순서 기반 incarnation map을 사용한다. 모호하면 no-redo suppression을 하지 않는 fail-safe가 필요하다.

### 5. `time(NULL)`을 exact file-generation identity로 사용함

- 위치: 계약 `src/storage/btree.h:79-86`; 실제 생성 `src/storage/file_manager.c:3518`
- `FILE_HEADER.time_creation`은 초 단위라 동일 class/attribute와 재사용 VFID가 같은 초에 생성되면 generation token이 충돌한다.
- 영향: media restore cleanup이 정상 replacement index를 이전 no-redo 파일로 오인해 삭제할 수 있다.
- 수정: DB-monotonic generation 또는 UUID처럼 충돌하지 않는 persisted generation을 file header와 marker에 사용한다.

### 6. no-redo provenance를 클라이언트 입력에 의존함

- 위치: `src/base/xserver_interface.h:120-130,185-190`, `src/transaction/locator.h:59-81`; 관련 검증 `src/transaction/locator_sr.c:7301-7310,7511-7518`
- 클라이언트가 `eligible_no_redo`, BTID, create LSA, class set을 공급하며 서버는 create LSA가 transaction 범위 안인지 정도만 확인한다.
- 영향: legacy empty-tail FORCE, client/server skew 또는 잘못된 descriptor가 marker 없는 publication이나 다른 B-tree를 지칭하는 marker를 만들 수 있다.
- 수정: server transaction state에 server-issued pending-build token을 만들고 BTID, generation, expected class set과 결합한다. publication/commit은 정확히 일치하는 marker가 없으면 거부한다.

### 7. 기존 `BTREE_LOADINDEX` wire layout을 negotiation 없이 변경함

- 위치: client `src/communication/network_interface_cl.c:6718-6719,6752-6755`; server `src/communication/network_interface_sr.cpp:4767-4772,4836-4838`
- 모든 request에 `eligible_no_redo`, 모든 reply에 `LOG_LSA`를 무조건 추가했다.
- 영향: old client/new server는 짧은 request로 실패하고 new client/old server는 짧은 reply로 실패한다. no-redo를 쓰지 않는 online build도 영향받는다.
- 수정: capability bit 또는 새 opcode로 versioning한다. legacy peer에서는 `eligible_no_redo=false`와 기존 reply layout을 사용한다.

### 8. 새 WAL recovery index를 compatibility boundary 없이 추가함

- 위치: `src/storage/btree.h:53-96`, `src/transaction/recovery.h:188-191`
- `RVBT_BULK_BUILD_DURABLE=130`을 추가했지만 release/log compatibility는 그대로다.
- 영향: rolling HA upgrade, downgrade 또는 구버전 standby가 새 record를 dispatch하지 못해 recovery/startup에 실패할 수 있다.
- 수정: log-format compatibility boundary 및 cluster capability gate를 정의하고, 구버전 reader가 존재하는 동안 marker emission을 금지한다.

### 9. bulk publication에서 기존 root-class catalog cache refresh를 생략함

- 위치: 기존 completion `src/transaction/locator_cl.c:4146-4157`; 신규 경로 `:4712-4713,5420-5435`
- 기존 path는 updated root class를 `au_fetch_class`로 다시 읽지만 bulk path는 MOP 정리 후 FORCE를 끝내고 refetch하지 않는다.
- 영향: 같은 CS client session에서 즉시 수행되는 DML/DDL이 stale representation directory를 사용할 가능성이 있다. SA mode와도 동작이 달라진다.
- 수정: post-force descriptor/OID 처리와 root-class refetch를 공용 helper로 만들고 실패 시 savepoint rollback한다.

### 10. marker-bearing FORCE가 ignored per-object error를 허용함

- 위치: `src/transaction/locator_cl.c:5420-5421`, server 전달 `src/communication/network_interface_sr.cpp:1503-1504`
- process-wide ignore list를 marker descriptor와 함께 전달하므로 일부 catalog object sub-operation이 실패해도 marker와 success가 남을 수 있다.
- 영향: class set이 일부만 공개된 marker가 생성되어 publication atomicity가 깨진다.
- 수정: `has_bulk_desc`일 때 ignore list가 비어 있지 않으면 server에서 거부하고 client도 ignored error 없이 FORCE한다.

## P2 — 수정 권고

### 11. 모든 transaction completion event를 recovery 종료까지 보관

- 위치: `src/transaction/log_recovery.c:3098-3132,6757-6780`
- bulk marker가 없는 DB에서도 commit/prepare/2PC/abort마다 node를 생성한다.
- 영향: recovery memory가 transaction 수에 비례하고 allocation 실패가 restart를 막는다.
- 수정: marker가 수집된 transaction만 추적하고 completion LSA/incarnation도 함께 저장한다.

### 12. 모든 physical redo가 marker 전체를 선형 탐색

- 위치: `src/transaction/log_recovery_redo.hpp:600-604`, `src/transaction/log_recovery.c:7118-7126`
- SERVER/non-media recovery에서는 suppression이 활성화되지 않아도 매 redo record마다 marker list를 돈다.
- 영향: 반복 bulk build 이후 restart가 `O(redo records × markers)`로 악화된다.
- 수정: global `any_redo_skip_enabled` fast path와 VFID/volume 기반 active-marker index를 둔다.

### 13. B5가 worker temp-run retire 실패를 숨김

- 위치: `src/storage/external_sort.c:5867-5874`
- `file_temp_retire` 반환을 무시하고 VFID를 무조건 NULL 처리한다.
- 영향: 성공으로 보고하면서 정렬 입력 전체 크기의 temp file을 orphan할 수 있다.
- 수정: 성공한 경우에만 VFID를 비우고 실패를 정상 build error/transaction cleanup으로 전파한다.

### 14. B4가 main pool만 bounded bootstrap하고 overflow pool은 전량 선할당

- 위치: `src/storage/btree_load.c:4890-4911`
- overflow-key workload에서는 `est_ovf_pages`를 worker 시작 전에 동기 할당·포맷하여 B4 이전과 같은 buffer flood/직렬 startup이 재발할 수 있다.
- 수정: overflow pool도 작은 bootstrap 이후 기존 `NEED_OVF` refill로 확장한다.

### 15. client tail unpacker의 `owner_class_name` lifetime/NUL 계약 불완전

- 위치: `src/communication/network_interface_cl.c:822-825,917-929`
- owner name은 packed buffer 내부 포인터를 그대로 반환하며 별도 storage나 NUL append가 없다.
- 영향: 길이가 4의 배수인 이름 뒤의 `object_kind` 바이트까지 C string으로 읽거나 buffer 해제 후 dangling pointer가 된다.
- 수정: caller-owned owner buffer/capacity를 받아 정확한 길이를 복사하고 NUL을 추가한다.

## 확인된 장점

- B4는 main-page ownership을 바꾸지 않고 초기 publication 양만 제한하며 provider ledger/reconcile 구조를 보존한다.
- B5는 공통 key splitter와 원래 `cmp_fn`을 사용한 shard별 heap merge로 정렬 의미를 보존하고, worker join 뒤 input을 해제하며 seam strict-order 검사를 수행한다.
- provider state와 condition signaling은 mutex로 보호되고 error가 모든 waiter를 깨운다. 검토한 경로에서는 provider deadlock/livelock을 찾지 못했다.
- scoped durability barrier는 file-owned page 열거, ordinary safe flush, DWB drain, owning-volume fsync를 수행하고 실패 시 global barrier로 fallback한다.
- `waiter_exists` 수정은 BCB mutex 아래 queue 상태를 reconcile하며 reader/writer가 남으면 bit를 유지한다.
- marker codec은 version, exact length, capacity, class-list와 object kind를 엄격히 검사한다.
- recovery index 130은 enum/table 끝에 append되어 기존 recovery ID 순서는 바꾸지 않는다.

## 검증 요구사항

1. repair 후 checkpoint/restart로 dirty 누락 회귀를 잡는 테스트.
2. marker packing/allocation failure, marker/attach/commit 각 crash boundary.
3. 2PC commit-decision 및 informing-participants crash restore.
4. drop 후 동일 VFID 재사용, 같은 초 재생성, replacement index 보존.
5. legacy empty-tail FORCE 및 mismatched BTID/create-LSA/class-set server rejection.
6. old/new client-server 4개 조합과 old-reader/new-WAL writer/rolling HA.
7. marker-bearing FORCE partial/ignored error와 interrupt/cancel/savepoint rollback.
8. 성공 직후 동일 CS session의 DML/DDL catalog representation 확인.
9. temp retire failure injection과 overflow-key-heavy provider growth.
10. many historical markers + large redo window에서 restart CPU/memory 상한.
11. B4+B5 기존 안정성 캠페인과 overflow-key workload 성능/정합성 매트릭스.

## 최종 판단

현재 브랜치는 성능 측면에서는 매우 유망하지만 durability/recovery/protocol 경계가 아직 merge 가능한 수준이 아니다. 특히 1~8번은 데이터 손상 또는 운영 호환성 장애로 이어질 수 있으므로 모두 해결하고 crash/restore 및 mixed-version 증거를 확보한 뒤 재리뷰해야 한다.

> 이 문서는 정적 리뷰 결과다. 사용자 요청에 따라 리뷰 agent들은 build/test/lint/formatter를 실행하지 않았다. 성능 및 기존 실험 수치는 별도 캠페인 보고서의 증거를 따른다.
