# PR 7504 직접 코드 감사 — 소유권·실패 경로·실행 매트릭스

## 결론

- 감사 대상: base `3ffeab793`, 최종 HEAD
  `01ae27f472b8a9d79b7fa773a52800e9b3474ff7`
- 범위: 요청 항목 1, 2, 3
  1. `SORT_ARGS`와 worker scan 자원의 소유권/수명 표
  2. `clone_scan_args → worker_scan_open → get_next → worker_scan_close → clone free`
     전체 정상·실패 경로
  3. general/function/filter/online/FK/overflow × parallel/serial/failure-injection
- 기능/소유권 판정: **이 범위의 correctness blocker 없음.**
- 머지 판정: **현재는 convention blocker 1건으로 blocking.**
- 단, 최초 감사 SHA `d1b386e4d7eee93488d42ffc6c3c43c5688021b0`에는
  `std::vector` 할당 실패가 `std::bad_alloc`으로 서버 밖까지 이탈할 수 있는 blocker가
  있었다. 이를 작업 세션에 전달했고, `37915e5b7`에서 catch/OOM 변환/부분 clone 정리를
  추가했다. 그러나 CUBRID root `AGENTS.md:196`은 engine code의 C++ exception을 명시적으로
  금지한다. 즉 기능상 예외 이탈은 막았지만 merge 가능한 최종 형태는 아직 아니다.
  아래 결과는 현재 수정이 포함된 최종 HEAD를 다시 빌드하여 얻은 것이다.
- 사용자 지시대로 항목 4(ASan/UBSan)는 수행하지 않았다.

## 1. 소유권·수명 표

코드 기준점은 최종 HEAD의
`src/storage/btree_load.h:285-339`,
`src/storage/btree_load.c:1028-1268`,
`src/storage/external_sort.c:1537-1564, 1680-1744, 5004-5014,
5918-5980, 6479-6489`이다.

| 자원/필드 | clone 직후 | 실제 소유자·변경 주체 | 종료 시점/정리 | 판정 |
|---|---|---|---|---|
| `hfids`, `class_ids`, `attr_ids`, `attrs_prefix_length` | leader 포인터를 shallow copy | leader 소유, workers read-only | 동기식 `sort_listfile` 반환 뒤 outer loader가 정리 | 안전 |
| `key_type`, `btid` | shallow copy | leader 소유. scan workers는 읽기만 하고 output 전이는 worker join 뒤 수행 | outer load 수명 | 안전 |
| `fk_refcls_oid`, `fk_refcls_pk_btid`, `fk_name` | shallow copy | leader/호출자 소유, workers에서 소유권 없음 | outer load 수명 | 안전 |
| `filter_index_info`의 raw stream | shallow copy | leader 소유, workers read-only | 모든 worker join 뒤 정리 | 안전 |
| 최초 `filter` | main mapping을 가리키는 shallow copy이나 clone에서는 “필터 존재” sentinel로만 사용 | `worker_scan_open`이 raw stream 정보를 복사한 뒤 즉시 `NULL`로 만들고 worker-private mapping 생성 | worker의 `worker_scan_close`; main mapping은 outer loader가 별도 정리 | shared mutable 아님 |
| 최초 `func_index_info` 및 raw stream | shallow copy | raw stream은 read-only | 모든 worker join 뒤 outer loader 정리 | 안전 |
| `px_func_index_info` | clone 안에 값으로 포함 | 해당 clone/worker 전용. `worker_scan_open`이 원본 descriptor를 복사하고 `expr=NULL`로 초기화한 뒤 여기에 mapping | clone raw storage가 free되기 전 `worker_scan_close`가 expr 해제 | stack UAF 제거됨 |
| `func_unpack_info` | clone에서 `NULL`로 재초기화 | 해당 worker가 mapping 시 획득 | 같은 worker의 `worker_scan_close`에서 해제 후 `NULL` | 안전 |
| `hfscan_cache`, `attr_info` | clone memcpy 값은 open 전 `memset`; init flags도 open에서 관리 | 해당 worker 전용 | 같은 worker의 close helper가 flag 기반 역순 정리 | partial-open 안전 |
| `in_recdes.data` | clone에서 `{0,0,0,NULL}` | scan 중 해당 worker가 보유한 page/buffer의 borrowed view | 다음 record/page 전환 또는 worker close | worker 간 공유 없음 |
| `ftab_sets` | clone에서 `NULL`; clone 단계가 vector를 별도 생성해 shard slice 채움 | publication 전 leader, 성공 반환 뒤 해당 worker | open/get 실패 포함 같은 worker의 close에서 vector destructor+free; clone 단계 실패면 leader helper가 정리 | 단일 소유권 전이 |
| `curr_sec`, `curr_pgoffset`, `cur_class`, `cur_oid` | worker별 초기 상태 | 해당 worker만 변경 | clone free | 안전 |
| `n_oids`, `n_nulls`, `n_ovf_keys`, `sum_ovf_pages` | clone에서 0 | 해당 worker만 누적 | join 뒤 `merge_scan_stats`가 leader에 합산하고 clone free | race 없음 |
| `px_worker_index` | `0..n-1`; 원본은 `-1` | immutable discriminator | clone free | 원본/clone cleanup 정책 분리 |
| clone의 raw `SORT_ARGS` | `malloc` | sorter가 성공한 clone 배열을 인수 | 모든 worker join 및 worker-owned 자원 close 뒤 leader cleanup에서 `free` | double-free 없음 |

핵심은 clone 내부에 `FUNCTION_INDEX_INFO px_func_index_info`를 직접 두는 것이다.
worker open의 stack local을 `func_index_info`가 가리키지 않으며, get/close가 끝날 때까지
descriptor 저장소가 유지된다.

## 2. 정상·실패 경로 감사

| 절단점 | 코드의 정리 동작 | 결과 |
|---|---|---|
| clone 시작 전 | `worker_get_args[0..n)=NULL` | partial cleanup의 입력이 항상 안전 |
| `SORT_ARGS` malloc 실패 | 지금까지 생성한 vector/clone을 `bt_load_px_free_scan_clones`로 정리 | leak 없음 |
| `ftab_sets` malloc 실패 | 동일 helper가 placement-new 완료분만 destructor+free | leak/double-free 없음 |
| `file_get_all_data_sectors` 실패 | 생성된 모든 clone 정리 | leak 없음 |
| `convert/split/push_back`의 STL OOM | `37915e5b7`의 `catch (const std::bad_alloc&)`가 남은 collector와 clone을 정리하고 CUBRID OOM으로 변환 | 최초 blocker 해소 |
| worker filter/function mapping 실패 | open이 성공한 부분 mapping을 즉시 clear; sorter cleanup의 close가 다시 호출돼도 helper가 no-op 가능한 상태 | dangling/double-free 없음 |
| worker attrinfo/scancache partial-open 실패 | init flag가 실제 성공 단계만 표시; worker cleanup label이 반드시 같은 thread에서 close | thread-affine 자원 안전 |
| `get_next`/sort 실패 | `sort_listfile_execute`의 공통 cleanup이 같은 worker에서 close | mapping/cache/vector 정리 |
| 일부 worker 실패 | 모든 worker를 join한 뒤 main cleanup | 살아 있는 worker가 clone을 참조하는 동안 free되지 않음 |
| 정상 worker 완료 | close가 mapping/cache/vector를 먼저 정리 | 이후 leader가 raw clone만 free |
| 통계 merge | join 뒤, raw clone free 전 실행 | UAF/race 없음 |
| 강제 serial fallback | 원본 `SORT_ARGS`만 사용; 정상/prepare/sort 실패의 close/abort가 분리됨. open 자체 실패의 원본 cache/mapping은 outer `xbtree_load_index` error cleanup이 소유 | clone 정책과 충돌 없음 |
| `px_sort_param` 배열 할당 실패 | cleanup이 `px_sort_param != NULL`일 때만 요소 주소를 계산 | NULL 기반 wild pointer 방지 |

`px_spec` 자체는 `btree_index_sort`의 stack local이지만 `sort_listfile`은 동기 호출이고,
worker join과 callback 사용이 모두 반환 전에 끝난다. 따라서 callback table의 stack 수명도
충분하다.

## 남은 merge blocker

`src/storage/btree_load.c:1174-1246`에 새로 추가된
`try`/`catch (const std::bad_alloc &)`는 root `AGENTS.md:196`의
“engine code에서 C++ exception 금지, `er_set` + return code 사용” 규칙을 위반한다.
동일 코드베이스의 histogram sampler에 기존 catch 선례가 있더라도 명시 규칙을 뒤집지는
않으며, 이번 PR에서 위반을 확대하면 안 된다.

권장 최소 수정은 이 새 경로에서 `ftab_set/std::vector`를 쓰지 않는 것이다.

```text
BT_LOAD_FTAB_SLICE
  FILE_PARTIAL_SECTOR *items   // malloc, clone-owned
  int count
  int cursor
```

- clone마다 `n_classes`개의 slice descriptor를 `malloc + zero-init`
- 각 class의 `FILE_FTAB_COLLECTOR`를 quotient/remainder로 shard 범위 분할
- 각 shard의 범위만 `malloc + memcpy`; 총 복사량은 원 collector 크기와 동일
- 어느 malloc이든 실패하면 기존 transactional clone helper로 전부 정리하고
  `er_set(ER_OUT_OF_VIRTUAL_MEMORY)` + return
- `get_next_vpid`는 `items[cursor++]`를 소비
- worker close와 partial-clone helper는 class별 `items` 후 descriptor 배열을 정리

이 형태는 exception, placement-new, vector destructor, `ftab_set.hpp` 의존성을 한꺼번에
제거하면서 기존 CUBRID 오류 모델과 소유권 표를 코드에 직접 드러낸다.

비차단 comment hygiene:

- `src/transaction/log_recovery.c:3282`의 “CBRD-27071 ADR”은 target commit 안에서
  추적 가능한 문서 경로가 없다. 괄호를 제거하거나 안정적인 in-repo 문서/심볼을 가리켜야 한다.
- `src/storage/btree_load.h:51`의 five-line sorter-boundary 설명은
  `external_sort.h`의 상세 contract와 중복되고 “any more”라는 시간 의존 표현을 쓴다.
  짧고 영속적인 내부 타입 설명만 남기는 편이 낫다.

## 3. 최종 HEAD 실행 결과

실행 호스트는 `192.168.6.33`의 별도 checkout
`/home/cubrid/dev/pr7504-codex-direct-d1`이다. 작업 중인 로컬 checkout/서버는 사용하지
않았다.

전용 설치본:

- Release: `/home/cubrid/release/CUBRID-11.5.pr7504-final-01ae-rel`
- Debug/assert:
  `/home/cubrid/debug/CUBRID-11.5.pr7504-final-01ae-opt`
- 테스트 hook 포함 Debug:
  `/home/cubrid/debug/CUBRID-11.5.pr7504-final-01ae-fi`

각 정상 셀은 행 수, `SUM(id)`, MIN/MAX, 강제 index 조회, marker/copypage, `checkdb`를
검증했다. serial은 `parallelism=1`, `max_parallel_workers=1`을 함께 사용해 강제했다.

| 시나리오 | parallel Release | parallel Debug | serial Release/Debug |
|---|---:|---:|---:|
| general | no-redo, marker=1, copypage=9, PASS | 동일, PASS | logged, marker=0, copypage=324, PASS |
| function | no-redo, 1, 9, PASS | 동일, PASS | logged, 0, 349, PASS |
| filter | no-redo, 1, 9, PASS | 동일, PASS | logged, 0, 166, PASS |
| online | logged, 0, 471, PASS | 동일, PASS | logged, 0, 471, PASS |
| FK | no-redo, 1, 238, PASS | 동일, PASS | logged, 0, 291, PASS |
| overflow | logged, 0, 39, PASS | 동일, PASS | logged, 0, 39, PASS |

정상 매트릭스는 **Release 12/12 + Debug/assert 12/12 PASS**다.

테스트 전용 hook은 소스에 커밋하지 않고 다음 두 위치만 강제 실패시켰다.

- `BKX_FI_CLONE_FAIL`: clone 0 생성 뒤 clone 1 직전 실패
- `BKX_FI_SCAN_OPEN_FAIL`: worker-private filter/function mapping 부착 뒤 실패

| 실패주입 셀 | 결과 |
|---|---|
| clone/general | 주입 loaddb rc=3, 서버 생존, 재시도 50,000행, checkdb PASS |
| scan-open/general | rc=3, 재시도 50,000행, checkdb PASS |
| scan-open/function | rc=3, 재시도 50,000행, checkdb PASS |
| scan-open/filter | rc=3, 재시도 25,000행, checkdb PASS |
| scan-open/FK | rc=3, 재시도 50,000행, checkdb PASS |
| hook 설정/overflow | logged 경로라 hook 미도달, 10,000행, checkdb PASS |
| hook 설정/online | logged 경로라 hook 미도달, 50,000행, checkdb PASS |

실패주입은 **7/7 PASS**다. overflow/online은 병렬 no-redo worker-open 경로를 타지 않는
것이 정상이라, 주입 실패를 기대하지 않고 “hook-not-reached + 정상 정합성”을 검증했다.

원격 증거:

- `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/pr7504-direct/evidence-finalrel/`
- `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/pr7504-direct/evidence-finalopt/`
- `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/pr7504-direct/evidence-fi/`

## 문서/테스트 기대값 정정

`ALTER TABLE ... ADD FK`가 no-redo 표면 밖이라는 일반화는 틀리다. 50,000행,
loaddb `--no-logging-index`, parallel degree가 있는 조건에서 FK index build가 실제로
`committed marker=1`로 발화했다. csql이나 작은/직렬 실행에서 관찰한 비발화를 전체
제품 표면으로 일반화하면 안 된다. 최종 테스트 기대값은 경로와 parallel eligibility를
명시해야 한다.

## 변경 집합과 인수인계

최종 diff는 13 files, `+1227/-576`이며 커밋은 다음 6개다.

1. `040a12e04` protocol back-compat + rollback-safe durability barrier
2. `7b957a542` six-op sorter/loader output contract
3. `bebf00358` shared record packer + explicit shard state + 2-core
4. `6111c270b` pure system-op predicate
5. `37915e5b7` clone-lifetime function mapping + transactional OOM cleanup
6. `01ae27f47` policy literal naming

이번 실행은 소유권/오류정리와 경로 선택을 검증한 것이며 처리시간 benchmark를 다시
측정한 것은 아니다. 다만 성능 개선 경로의 활성 증거로 general/function/filter/FK의
parallel 셀은 no-redo marker=1, serial fallback은 marker=0을 각각 확인했다.

검증 후 테스트 hook을 역적용했고 remote source는 정확히 `01ae27f47`로 복구했다.
전용 DB 32개를 `cubrid deletedb`로 제거했으며 daemon이 없음을 확인했다.
`/home/cubrid/CUBRID`도 원래
`/home/cubrid/release/CUBRID-11.5.develop`로 복구했다.
