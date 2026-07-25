# PR #7504 병렬 인덱스 빌드 get-side 자원 수명 전수 감사 (완료조건 1·2)

- 대상: 브랜치 `pr-7504-redesign`, 감사 기준 콘텐츠 `d1b386e4d`(= 재구성 후 `be34061b6` 시점 콘텐츠), 수정 반영 최종 HEAD `3f1e215cd`
- 방법: architect 독립 감사(agent://15-LifetimeAudit, 26.6KB 원문) + 본 세션의 HIGH finding 직접 재검증(external_sort.c:1570-1633, 4915-4930 실독)
- 결론: **get-side clone 체인에서 dangling/double-free/공유 동시쓰기/leak 부재를 라인 단위로 입증.** 감사가 찾아낸 신규 결함 3건(HIGH 1, LOW 2)은 최종 HEAD에 수정 반영 완료.

## 1. 소유권 표 (요지 — 전체 표는 agent://15-LifetimeAudit §A)

### SORT_ARGS 포인터/핸들 필드 (btree_load.h:286-338 정의 순서 전수)

| 필드 | owner | 할당 스레드 | 수명 | 이전 지점 | 성공 정리 | 부분-실패 정리 |
|---|---|---|---|---|---|---|
| `hfids`/`class_ids`/`attr_ids`/`attrs_prefix_length`/`key_type`/`btid`/`fk_*`/`filter_index_info` | 공유-읽기전용(호출자/리더 스택) | 리더 | xbtree_load_index 프레임 전체 | 없음(clone은 memcpy로 포인터만 공유) | 아무도 해제 안 함 | 어떤 clone 경로도 해제 없음 → double-free 부재 |
| `in_recdes.data` | 비소유(PEEK, heap 페이지 내부) | — | 페이지는 hfscan_cache가 관리 | 없음 | scancache_end가 페이지 회수 | 에러 반환 후 미참조 |
| `hfscan_cache`/`attr_info` (embedded 핸들) | 각 인스턴스 | 여는 스레드(워커 자신) | scan_open memset+start ~ scan_close end | 없음 | close가 `*_inited` 플래그 가드로 end | start 4개 실패점마다 플래그가 진행도 반영; `heap_attrinfo_end` 멱등(heap_file.c:10105-10130) |
| `filter` | 원본=리더 소유 / **clone=자기 소유** | 원본 리더, clone 워커 | clone: scan_open 매핑~scan_close `db_private_free_and_init` | memcpy 직후 공유되나 **open의 최초 실패점 이전에 무조건 NULL 절연** | close의 clear_pred_and_unpack | open 실패 시 open 내부 clear → 이후 close 재호출도 NULL nop |
| `func_index_info` | 원본=리더 스택 참조 / clone=자기 `px_func_index_info` 참조 | — | clone: open~close(expr clear) | open에서 절연 후 재지정 | close가 expr만 clear(스트림은 공유 읽기전용) | stx 실패 시 출력 미기록 → clear nop |
| `px_func_index_info` (blocker 수정의 저장소) | clone 인라인(POD+expr) | 워커 | **clone malloc 블록과 동일 수명** — 스택 로컬 참조 부재 확인 | 없음 | expr은 위 경로 | open 재진입 시 재초기화 |
| `func_unpack_info` | **clone 전용 소유**(원본 항상 NULL) | 워커 | open 성공~close free+NULL | 없음 | close | stx 실패 시 자체 정리 후 미기록 → 이중해제 없음 |
| `ftab_sets` | clone 소유(원본 NULL — 최종 HEAD에서 명시 초기화) | 리더(clone_scan_args) | malloc+placement_new ~ close `~vector()+free` 또는 실패 시 free_scan_clones | clone_scan_args 성공 반환 시 sorter로 | close | 두 해제 경로 상호배타(실패=free_scan_clones 내부만, close=인수 후만) |
| 통계(`n_oids`/`n_nulls`/`n_ovf_keys`/`sum_ovf_pages`) | 값 | — | merge_scan_stats가 리더에 가산 | 값 병합 | — | 최종 HEAD에서 clone 리셋 명시(감사 LOW#2 수정) |
| `cur_oid`/`curr_sec`/`curr_pgoffset` | 값(스캔 커서) | — | clone 리셋; 자기 clone만 갱신 | — | — | 공유쓰기 없음 |

### SORT_PX_OUTPUT_SPEC 콜백 자원 (external_sort.h:246-283)

| 자원 | owner | 수명/이전 | 실패 정리 |
|---|---|---|---|
| `get_arg`(원본) | xbtree_load_index 스택 | sorter는 절대 해제 안 함(px 슬롯 get_arg 선제 NULL, external_sort.c:5126-5140) | 리더 error 라벨이 내부 자원만 정리 |
| `worker_get_args[i]`(clone) | 성공 반환 후 sorter | malloc(clone_scan_args)~free_and_init(external_sort.c:5003-5006) | clone_scan_args 실패 시 free_scan_clones가 전량 파괴+슬롯 NULL → sorter cleanup nop |
| 원 스트림(pred/func) | 호출자 | 전 구간 | N 워커 병행 **읽기**만(stx는 스레드로컬 unpack 컨텍스트) |
| `collector.partsect_ftab` | clone_scan_args 로컬 | 성공 즉시 해제; **실패 시 피호출자 자체 해제**(file_manager.c:12620-12640) | leak 부재 |

## 2. 호출체인 실패엣지 전수 감사 (agent://15-LifetimeAudit §B)

체인: `clone_scan_args → worker_scan_open → get_next_parallel → worker_scan_close → free clones/merge_scan_stats`

- **clone_scan_args** 3개 실패엣지(clone malloc/ftab 수집/ftab_sets malloc): 전부 free_scan_clones로 트랜잭셔널 — 안전.
- **scan_open** 2개 실패엣지(매핑/scancache start): 리더 포인터는 **모든 실패점 이전에 절연** → 리더 자원 이중해제 불가; 매핑 실패는 open 내부 clear, start 실패는 플래그 가드로 close에 이연 — 안전.
- **sorter 호출부**: 워커 경로는 close 무조건 호출(1737, open의 정확한 거울·멱등); 단일 경로는 close 미호출이지만 xbtree_load_index error 라벨이 회수 — 안전. `sort_copy_sort_param` 실패 자체 정리·워커 get_arg 선제 NULL로 **원본 스택 SORT_ARGS가 free되는 경로 부재 입증**.
- **get_next_parallel** 전 return 엣지(11개): 페이지 latch는 scancache가 회수, dbvalue는 에러 전 clear, 쓰기는 전부 자기 clone 필드 — leak/공유쓰기 부재.
- **merge_scan_stats**: SORT_WAIT 이후·clone free 이전 메인 단독 — 수명 가정 성립.
- 종합: (a) memcpy 원본 포인터 double-free **부재**, (b) open 실패 후 close 호출 여부와 무관하게 안전, (c) 공유 원본 필드 동시쓰기 **부재**, (d) merge 수명 가정 성립.

## 3. 감사가 찾은 신규 결함과 조치 (최종 HEAD `78fb12eec` 반영)

| # | 심각도 | 내용 | 조치 |
|---|---|---|---|
| 1 | **HIGH** | `sort_listfile` cleanup: `px_sort_param` malloc 실패 엣지에서 `&NULL[i]`(i≥1)가 피호출자 NULL 가드(4918)를 통과해 4923 역참조 크래시. 본 세션이 external_sort.c:1570-1633·4915-4930 실독으로 재검증(px_worker_manager는 동 엣지에서 선예약 non-NULL 확인) | `if (px_sort_param != NULL)` 가드 — hardening 커밋(`37915e5b7`)에 폴드 |
| 2 | LOW | clone 리셋 목록에 `n_oids`/`n_nulls` 누락 — 리더 0 불변식에 잠재 결합(향후 리더 선스캔 도입 시 n_shards배 중복집계) | clone 리셋 2줄 추가 — 동 커밋 |
| 3 | LOW | 원본 SORT_ARGS의 `ftab_sets`/`curr_sec`/`curr_pgoffset` 미초기화 — 안전성이 px_worker_index 가드 하나에 의존 | 리더 초기화 3줄 추가 — 동 커밋 |
| 4 | **BLOCK**(Codex 감사가 INFO→blocker로 승격, 타당) | `clone_scan_args`의 transactional 계약이 STL OOM에 불성립: `ftab_set::convert`(resize)/`split`(vector ctor+push_back)/clone `push_back`이 `std::bad_alloc`을 던지는데 catch 부재 → 서버 terminate + partial clone/collector 미회수(ftab_set.hpp:89-123 실독 확인) | 1차 try/catch 안은 **AGENTS.md:196(엔진 코드 예외 금지) 위반으로 기각**(Codex 컨벤션 지적; histogram의 기존 catch는 선례 아닌 선행 위반). 최종안: clone의 `std::vector<ftab_set>*`를 순수 C `BT_LOAD_SECTOR_SLICE` per-class 배열(malloc-checked, 몫/나머지 분할, memcpy 슬라이스)로 교체 — catch 자체가 불필요해지고 loader의 ftab_set/STL 의존까지 제거, `get_next_vpid`는 슬라이스 커서 소비. hardening 커밋(`a30dbb88e`)에 폴드 |

## 4. 잔여 수용 리스크
- 단일 경로의 close-without-open 비대칭(external_sort.c:1537-1541): 현재 안전(error 라벨 회수)하나 지역 불변식 의존 — 선택 개선안으로 기록만.

## 5. 매트릭스 전제 정정 (Codex 실측 교차검증)
- "ALTER ADD FK는 no-redo 표면 밖" 일반화는 **오류** — csql 경유에만 성립. **loaddb `--no-logging-index -i` 경유 ALTER ADD FK는 병렬 설정에서 no-redo 발화**(본 세션 독립 재현: committed=1 pending=1, v10 바이너리). idx-matrix fk 셀을 3분할(csql 비발화 / loaddb 발화+FK 동작 / 위반 데이터 실패+서버 생존+재시도)로 정정, 최종 HEAD 배터리에 편입.
