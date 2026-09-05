# client workspace → 서버 카탈로그 read-latch 대체 가능성 — 사실 조사 (#213)

- 티켓: [#213](https://github.com/xmilex-git/workspace/issues/213) (Part of #207 통합 최적화 브레인스토밍)
- 조사 대상: cas-merge tip `/home/cubrid/dev/worktrees/wf143-gate` @ 7117c8a66 (읽기 전용). 비교: upstream develop `/home/cubrid/dev/cubrid`.
- 선행 결정·실측 인용: [#113](https://github.com/xmilex-git/workspace/issues/113) (client 전역상태 인벤토리), [#115](https://github.com/xmilex-git/workspace/issues/115) (SA 모드 병합 경계), [#123](https://github.com/xmilex-git/workspace/issues/123) (워크스페이스 세션-스코프 재설계 D1~D6), [#118](https://github.com/xmilex-git/workspace/issues/118) (권한 검사 시점).
- 질문: **SQL 컴파일러가 cub_server 안에서 돌게 된 지금, 세션당 client workspace(MOP 테이블·ws 할당·SM_CLASS 스키마 캐시)를 서버 카탈로그의 read-latch 읽기로 대체할 수 있는가?**

## 요약표

| # | 항목 | 사실 (cas-merge 기준) | 근거 |
|---|---|---|---|
| 1 | 워크스페이스의 세 역할 | ①컴파일러가 소비하는 스키마 표현(SM_CLASS/SM_ATTRIBUTE/SM_CLASS_CONSTRAINT), ②DDL 트랜잭션 스테이징(SM_TEMPLATE→dirty MOP→locator_flush), ③네트워크 왕복 회피 캐시(chn 재검증). 폴드가 소멸시킨 것은 ③의 "네트워크"만이고 ①②는 그대로 살아 있다 | §1 |
| 2 | 컴파일 경로의 SM_CLASS 물질화 | 이름 해석마다 `db_find_class_with_purpose`→`au_fetch_class`→`locator_fetch_class`→`locator_lock`→`locator_fetch`(폴드에선 `enter_server()`+`xlocator_fetch` 직접 호출)→copyarea→`tf_disk_to_class`로 SM_CLASS를 세션 힙에 **역직렬화**한다. 즉 폴드 후에도 클래스 레코드는 "디스크 표현→copyarea→SM_CLASS" 3단 복제다 | name_resolution.c:7044-7058, authenticate_access_class.cpp:556-563, locator_cl.c:2284-2344, network_interface_cl.c:379-391, locator_cl.c:3331 |
| 3 | 서버가 이미 가진 것 | `heap_Classrepr` 캐시(OR_CLASSREP 1024 LRU, 해시 뮤텍스+엔트리 뮤텍스+fcnt 핀) — 속성·도메인·기본값·auto_increment·인덱스/FK/필터·함수인덱스·파티션 정보. `system_catalog.c` — HFID·페이지수·rep_dir·DISK_REPR(통계 첨부), dir_oid 잠금 규약. `partition.c` — CSECT_PARTITION_CACHE 아래 프루닝 컨텍스트+술어 XASL | §2 |
| 4 | 서버가 갖지 않은 것 (컴파일 필수) | **뷰 query_spec, 메서드/메서드파일, 트리거 캐시, 권한(auth_cache·owner), 코멘트, 클래스 이름 해석(이름→OID는 있음), 상속/해석(resolutions), 클래스 통계의 SM_CLASS 뷰, 가상 질의 파스트리 캐시** — 서버 라이브러리에 `sm_*`/`au_*`가 없고(`authenticate.h:31 #error Does not belong to server module` in develop), 서버측 query_spec 독자는 `catalog_class.c`(카탈로그 테이블 채우기용)뿐 | §2.3 표 |
| 5 | 서버 자체의 MOP-free 관례 | 클래스는 OID+HFID로, 값은 OID로(`mr_data_writeval_object`가 `WS_OID`로 정규화), 도메인은 **콘텐츠 기준**(class_mop을 품은 도메인만 세션 리스트, 나머지는 프로세스 리스트) 라우팅. XASL은 `cls_oid`+`hfid`만 담는다 | xasl_generation.c:5195-5220, object_domain.c:1894-1952, object_primitive.c:5202-5249 |
| 6 | 세션당 비용 (실측 #123 F2, develop) | SM_CLASS 콘텐츠 100~150KB(~20테이블) + MOP테이블 64KB + lea base 64KB + AREA 첫터치 350KB → **0.3~0.6MB/세션**. 폴드는 D5(AREA 프로세스 공유)·D6(MOP테이블 1024→16KB) 적용으로 고정 플로어를 128KB→80KB로 낮췄고 AREA 350KB는 세션 항에서 제외됨 (파생값, 폴드 재실측 없음) | §4 |
| 7 | 후보 (a) 읽기전용 컴파일만 catalog latch 직독 | 깨는 불변식 3개(단일 표현·chn 코히런시·DDL/컴파일 동일 객체). 컴파일러 SM_CLASS 소비점 ~300줄(parser 184·optimizer 32·execute_statement 87)+`class_->` 역참조 1,210개의 상당 부분. 서버에 **없는** 정보 8종을 먼저 서버 표현으로 신설해야 함. SA 선례 없음(SA도 워크스페이스 사용) | §5 |
| 8 | 후보 (b) 표현 통합(SM_CLASS→서버 표현) | schema_manager.c 277함수·class_object.c 156·transform_cl.c 98·schema_template.c 89·locator_cl.c 86·trigger_manager.c 129·authenticate* 100+ = **~1,000 함수, 83 파일이 schema_manager.h 포함**. #123 D1이 "이 맵 밖 규모"로 기각한 그 작업 | §5 |
| 9 | 판정 | "대체"는 단기 불가. 현실적 축은 **③ 캐시 계층의 잉여 제거**(chn 라운드트립·heap_Guesschn·재검증 3중 단락)와 **(a)의 축소판: 서버가 이미 가진 사실(HFID·rep_id·파티션·인덱스·통계)을 SM_CLASS 재물질화 없이 heap_Classrepr에서 읽는 read-through**부터. 뷰·권한·트리거·메서드는 서버 표현이 없어 (a)에서도 워크스페이스 존치 | §6 |

---

## 0. 전제 — 폴드가 바꾼 것과 안 바꾼 것

- 서버 라이브러리(`cubrid/CMakeLists.txt`)가 client 절반을 그대로 컴파일한다: `network_interface_cl.c`(:630), `class_object.c`(:656), `client_session_context.cpp`(:657), `schema_manager.c`(:670), `transform_cl.c`(:676), `work_space.c`(:680), `locator_cl.c`(:725). develop의 `cubrid/CMakeLists.txt`에는 이 셋이 0건이고, develop에서 `work_space.c`/`schema_manager.c`는 `sa/CMakeLists.txt:355,368`(SA·CS만)에 있다.
- RPC seam은 접혔지만 **직렬화 경계는 유지**: `network_interface_cl.c`의 `#if defined(CS_MODE)` 분기 수가 폴드 171 = develop 171로 동일. `locator_fetch`(:339)는 CS면 `net_client_request_recv_copyarea`, 아니면 `enter_server()`→`xlocator_fetch(thread_p, …, fetch_copyarea)`→`exit_server()`(:379-391). `enter_server`는 SERVER_MODE에서 "이미 서버 워커이므로 플래그(db_on_server)·er 스택만 바꾼다"(:142-152). 이것이 #115가 지적한 "병합의 진짜 계약은 주소공간이 아니라 직렬화 경계"의 폴드 구현이다.
- 세션 앵커: `client_session_context`(client_session_context.hpp:61)가 `ws_context ws`(:73), `tm_context tm`(:76), `sm_context sm`(:79), `tr_context tr`(:82), `authenticate_context au_context`(:70), `obt_context obt`(:95), `tp_domains`(:129, B4-D9), `method_callback_handler`(:144), `label_table`(:161)를 소유하고 `bracket_mutex`(:68)로 세션 내 client-half 작업을 직렬화한다. 소유자는 `session_state`(session.c:385-392 `csc_retire_and_delete(session->csc_p)`), 스레드는 활성화 브래킷으로만 접근(#123 D3).

## 1. 세션 워크스페이스가 폴드 경로에서 실제로 하는 일 (경로별 분류)

### 1(a) 컴파일러가 소비하는 스키마 표현

**물질화 지점.** 이름 해석 `pt_find_class`류(name_resolution.c:7036-7075): `db_find_class_with_purpose`(:7044) → `au_fetch_class(classop, &class_, fetchmode, type)`(:7058) → 반환된 `SM_CLASS*`의 `header.ch_name`(:7063), `partition`(:7068)을 파스트리에 박는다. `au_fetch_class_internal`(authenticate_access_class.cpp:533)은 "READ이고, 삭제 안 됐고, `op->object != NULL`이고, 클래스이고, `op->lock >= SCH_S_LOCK`"이면 재fetch를 건너뛰고(:556-560) 그 외엔 `fetch_class`(:366) → `locator_fetch_class(classmop, DB_FETCH_READ)`(:434) → `locator_lock(class_mop, LC_CLASS, lock, LC_FETCH_CURRENT_VERSION)`(locator_cl.c:2313) → `locator_can_skip_fetch_from_server`(:657, 정의 :6736) 게이트 → 서버 `xlocator_fetch`(locator_sr.c:2374; 클래스 레코드는 `locator_lock_and_return_object(…, oid_Root_class_oid, class_oid, class_chn, …)` :2589) → copyarea → `tf_disk_to_class(&obj->oid, recdes_p)`(locator_cl.c:3331,3363). 권한은 `check_authorization`(authenticate_access_class.cpp:597) → `SM_CLASS->auth_cache`(authenticate_cache.cpp:419,428).

**소비 지점(파일별 SM_CLASS/SM_ATTRIBUTE/SM_CLASS_CONSTRAINT/au_fetch_class/sm_*·db_get_attribute 참조 수, grep):**

| 파일 | 참조 수 | 무엇을 읽나 |
|---|---|---|
| src/parser/semantic_check.c | 57 | `au_fetch_class(…, AU_SELECT)` 5곳(:6076, :6129, :6626, :6726, :16872) — 파티션·상위클래스·권한 |
| src/parser/xasl_generation.c | 46 | `sm_get_ch_heap`(:5195,14065,22114,22909,27741), `WS_OID(class_)`→`spec->s.cls_node.cls_oid`(:5201-5220), `sm_partitioned_class_type`(:5207 외 6곳), `sm_att_id`(:20210 외 5곳) |
| src/parser/name_resolution.c | 32 | 위 물질화 + `au_fetch_class_force` 4곳(:1665, :1882, :6878, :6928), 시리얼 클래스(:10716), 파티션 부모(:11069-11087) |
| src/optimizer/query_graph.c | 31 | `sm_get_class_with_statistics(info->mop)`(:5057) → `CLASS_STATS` 첨부, `heap_num_pages`(:5088) |
| src/parser/view_transform.c | 25 | 뷰 query_spec: `mq_fetch_subqueries`(:374) → `sm_virtual_queries`(schema_manager.c:6920)가 `class_->virtual_query_cache`를 `sm_local_schema_version()`으로 검증(:6936, :7027) |
| src/parser/query_result.c | 17 | 결과 컬럼 메타(DB_QUERY_TYPE) |
| src/parser/type_checking.c / parser_support.c / show_meta.c 등 | 8/7/9 | 도메인·기본값·SHOW 메타 |
| src/query/execute_statement.c | 87 | 실행 준비: `sm_class_has_triggers`(:9636, :9853, :9864, :11020, :11277 등 트리거 관련 32건), 시리얼·기본값·savepoint |

`class_->`/`smclass->`/`cls->` 역참조 총량: parser+optimizer+query+object+compat에서 **1,210건**(grep, 과대 포함 가능).

**SM_CLASS가 담는 의미 절반(class_object.h:744-814):** `users`/`inheritance`(상속), `representations`(구표현), `method_files`/`methods`/`class_methods`(:763-769), `resolutions`(:771), `query_spec`(:781), `stats`/`histogram`(:783-784), `owner`(:786), `auth_cache`(:788), `virtual_query_cache`(:792, 파스트리), `triggers`(:793), `constraints`(:794), `comment`(:795), `fk_ref`(:796), `partition`(:797), `virtual_cache_*_schema_id`(:800-802). SM_ATTRIBUTE(class_object.h:447-470): `domain`, `class_mop`, `default_value`(SM_DEFAULT_VALUE = DB_VALUE 2개 + DB_DEFAULT_EXPR, :394-399), `on_update_default_expr`, `constraints`, `properties`, `triggers`, `auto_increment`(**MOP**, _db_serial 인스턴스 :468), `comment`.

### 1(b) DDL 쓰기 경로 (트랜잭션 스테이징)

- execute_schema.c: `smt_*`/`dbt_*` 템플릿 호출 **143건(48종)**, `sm_update_class*`/`sm_finish_class`/`sm_delete_class_mop` 12건, SM_* 참조 149건.
- schema_manager.c: `install_new_representation`(:12444) → `locator_flush_all_instances(classop, DECACHE)`(:12502) → `locator_update_class`(:12526,12576) → `classobj_install_template`(:12568); `allocate_disk_structures`(:11514) → `locator_assign_permanent_oid`(:11575) → `locator_update_class`/`locator_flush_class`(:11653-11658); `flatten_template`(:9803), `lock_supers`/`lock_subclasses`(:365-370). 플러시는 `tf_class_to_disk(object, &mflush->recdes)`(locator_cl.c:4209,4296) → `locator_force` → 서버 `xlocator_force`(locator_sr.c:7129)가 `catalog_insert/update`(:5112, :5592)·`catcls_insert/update_catalog_classes`(:5162, :5488) 및 `xcache_remove_by_oid`/`fpcache_remove_by_class`(:5674-5679, :6297-6302)를 수행.
- 즉 DDL 의미론(상속 평탄화·제약 이름 생성·해석 규칙·인덱스 할당 순서)은 전부 client 절반(SM_TEMPLATE→SM_CLASS→디스크 레코드)에 있고, 서버는 **완성된 클래스 레코드를 받아 카탈로그/캐시를 갱신**할 뿐이다. 서버측에 DDL 의미론 대응물은 없다.

### 1(c) 순수 캐시 — chn 재검증 (폴드 후 로컬 호출)

- 캐시 유효성 게이트 `locator_can_skip_fetch_from_server`(locator_cl.c:6736; 호출 :657, :1035, :1895). 락 보유 중이면 서버를 건너뛰고, 아니면 `xlocator_fetch`가 `class_chn`을 비교해 변경 시 레코드를 다시 보낸다.
- prepared 재실행: `pt_has_modified_class`(db_vdb.c:4959; 호출 :2224, :2308, :3917)가 파스트리의 `db_object_chn`(compile.c:647에서 `locator_get_cache_coherency_number` 결과 저장)을 재검사 → `DB_CLASS_MODIFIED`(db_vdb.c:5007,5017) → 재컴파일. `locator_get_cache_coherency_number`(locator_cl.c:2162)는 내부에서 `locator_lock`(:2187) → 폴드에선 락 매니저 로컬 호출.
- 폴드 후 이 경로의 "네트워크 홉"은 사라졌지만(#123 D4의 defang), **락+chn 비교+미스 시 레코드 역직렬화**는 그대로다. 서버측 `heap_Guesschn`(트랜잭션별 "클라가 캐시했을 chn" 비트맵)도 존속.

## 2. 서버측 대응물과 래치/락 규약

### 2.1 `heap_Classrepr` — OR_CLASSREP 캐시 (heap_file.c)

- 용량 `HEAP_CLASSREPR_MAXCACHE 1024`(:100), 정적 싱글턴 `heap_Classrepr`(:477), 엔트리(:308-326): `mutex`, `fcnt`(핀 카운트), `zone`, `force_decache`, `class_oid`, `OR_CLASSREP **repr`(rep_id별 배열), `max_reprid`. 해시 앵커(:339-345): `hash_mutex` + 클래스 단위 `lock_next`(로딩 중 클래스 락).
- 획득 `heap_classrepr_get(thread_p, class_oid, class_recdes, reprid, idx_incache)`(:2008): `hash_mutex` 잠금(:2025) → 엔트리 `trylock`/`lock`(:2031-2047) → 미스면 `heap_classrepr_lock_class`(:1688; 호출 :2124)로 클래스별 로딩 락 → `heap_get_class_record`(:25918)로 클래스 레코드 → `or_get_classrep(record, repid)`(object_representation_sr.c:3337) → LRU 삽입. 해제 `heap_classrepr_free`(:1602)가 `fcnt--`. 무효화 `heap_classrepr_decache`(:1527)는 `xlocator_force` 경로와 `log_manager.c:4111,5169`의 `m_modified_classes.decache_heap_repr`.
- 서버 내 소비자: `heap_classrepr_get` 호출 **33곳, 11파일**.
- **OR_CLASSREP 내용**(object_representation_sr.h:210-230): `attributes`/`shared_attrs`/`class_attrs`(OR_ATTRIBUTE: `id`,`type`,`def_order`,`location`,`classoid`,`on_update_expr`,`default_value`,`current_default_value`,`btids`,`domain`,`is_autoincrement`,`is_notnull`,`is_invisible`,`auto_increment{serial_obj OID, cached_num}` :92-132), `indexes`(OR_INDEX: `atts`,`asc_desc`,`prefix_length`,`btname`,`filter_predicate`,`func_index_info`,`fk`,`type`,`btid`,`index_status` :183-197), `id`(repid), `fixed_length`, `n_*`, `has_partition_info`. 파티션은 `or_class_get_partition_info`(:257, 호출 heap_file.c:11142) → `OR_PARTITION{class_oid, class_hfid, partition_type, rep_id, values}`(:199-206). 제약 코멘트만 `or_get_constraint_comment`(:259)로 별도.
- 서버가 class 레코드 헤더에서 직접 읽는 것: `or_class_rep_dir`, `or_class_hfid`, `or_class_tde_algorithm`(:244-246), `heap_get_class_name`(heap_file.c:9554). `or_class` (:233-242)는 `superclasses`/`subclasses` OID 배열, `statistics` OID.

### 2.2 `system_catalog.c` — 디스크 카탈로그

- `CLS_INFO{ci_hfid, ci_tot_pages, ci_tot_objects, ci_time_stamp, ci_rep_dir}`(system_catalog.h:96-103), `DISK_REPR{id, n_fixed, fixed, fixed_length, n_variable, variable}`(:63-74), `DISK_ATTR{id, location, type, val_length, value(기본값 — "default expression은 안 보관" 주석 :87), position, classoid, n_btstats, bt_stats, ndv}`(:80-93).
- 접근 규약 `catalog_start_access_with_dir_oid(thread_p, info, lock_mode)`(:5815): rep_dir OID에 대해 `lock_get_object_lock`(:5851) 확인 후 `lock_object(thread_p, dir_oid, &virtual_class_dir_oid, lock_mode, LK_UNCOND_LOCK)`(:5867-5868) — 읽기는 S_LOCK, 갱신은 X_LOCK(:5839). 페이지는 `pgbuf_fix` 14곳/`pgbuf_unfix` 54곳으로 래치. 즉 **"카탈로그 read-latch"의 실체 = dir_oid S 락 + 카탈로그 페이지 S 래치**이며, 클래스 레코드 자체(힙)는 별도 힙 페이지 래치.
- 진입점: `catalog_get_representation`(:3887), `catalog_get_class_info`(:4113), `catalog_get_cardinality`(:5278). 인트리 문서 `src/storage/docs/catalog-statistics-maintenance.md:18-22`가 모드 경계를 명시: `system_catalog.c`/`catalog_class.c`/`statistics_sr.c`는 서버·SA 코드.

### 2.3 `catalog_class.c` — 시스템 카탈로그 테이블(_db_class 등)

- 서버가 클래스 레코드 전체를 의미 단위로 언팩하는 **유일한** 코드: `catcls_get_or_value_from_class`(:1000), `…_from_attribute`(:1274), `…_from_method`(:1835), `…_from_method_file`(:2064), `…_from_resolution`(:2134), `…_from_query_spec`(:2209), `…_from_indexes`(:2270). 그러나 이것은 `_db_class/_db_attribute/_db_method/_db_query_spec…` 행을 **쓰기 위한 OR_VALUE 트리**이며, 컴파일러가 소비할 인메모리 표현(이름→도메인·query_spec 파스트리·권한 판정)이 아니다. 서버측 query_spec 독자는 grep상 `catalog_class.c`만(execute_schema.c는 client 절반).

### 2.4 `partition.c` — 서버 프루닝 컨텍스트

- `partition_load_pruning_context`(:2675) → `partition_load_context_from_cache`(:657, `csect_enter_as_reader(CSECT_PARTITION_CACHE)` :685) 미스면 `heap_get_class_partitions`(:2736; heap_file.c:11346) → `partition_load_partition_predicate`(:2863)가 `_db_partition`의 expr 스트림을 `stx_map_stream_to_func_pred`(:2890)로 언팩 → `partition_cache_pruning_context`(:2766, `csect_enter(CSECT_PARTITION_CACHE)` :612). 이것이 "서버가 MOP 없이 파티션 표현을 읽는" 완성된 선례다(단, 술어는 클라이언트가 컴파일해 스트림으로 저장한 것).

### 2.5 제공/미제공 표 — 컴파일이 필요로 하는 사실 vs 서버 보유

| 컴파일 필요 사실 | SM_CLASS 필드 | 서버 보유 | 서버 위치 |
|---|---|---|---|
| 이름→클래스 OID | `header.ch_name` | ○ | `xlocator_find_class_oid`(locator_sr.c:1033), `catcls_find_class_oid_by_class_name`(catalog_class.c:597) |
| HFID, rep_dir, repid | `header.ch_heap/ch_rep_dir`, `repid` | ○ | `or_class_hfid/or_class_rep_dir`, `CLS_INFO`, `OR_CLASSREP.id` |
| 속성 id·순서·도메인·NOT NULL·invisible | `attributes[].domain/…` | ○ | `OR_ATTRIBUTE` |
| 기본값(값), on_update expr 타입 | `default_value.value` | ○(값)/△(표현식) | `OR_DEFAULT_VALUE`, `on_update_expr`; DISK_ATTR은 표현식 미보관(:87) |
| 기본값 표현식 원문(DEFAULT SYS_DATE 등) | `default_value.default_expr` | △ | `OR_DEFAULT_VALUE.default_expr` 타입은 있음, 파스트리 아님 |
| auto_increment 시리얼 | `auto_increment`(MOP) | ○(OID) | `or_auto_increment.serial_obj` |
| 인덱스·UNIQUE·PK·FK·필터·함수인덱스 | `constraints`, `fk_ref` | ○ | `OR_INDEX{fk, filter_predicate, func_index_info}` |
| 제약/인덱스 코멘트 | `constraints[].comment` | ○ | `or_get_constraint_comment` |
| 파티션 타입·키·술어 | `partition` | ○ | `OR_PARTITION`, `partition.c` 캐시 |
| 통계(페이지수·NDV·btree 통계) | `stats`, `histogram` | ○ | `CLS_INFO`, `DISK_ATTR.bt_stats/ndv`, `xstats_get_statistics_from_server`(statistics_sr.c:516) |
| 상속(super/sub) | `inheritance`, `users` | ○(OID 배열) | `or_class.superclasses/subclasses` |
| **뷰 query_spec (SQL 텍스트→파스트리)** | `query_spec`, `virtual_query_cache` | **×** | `catcls_get_or_value_from_query_spec`는 카탈로그 행 기록용 |
| **메서드·메서드파일·loader_commands** | `methods`, `method_files` | **×** | 동일(카탈로그 행 기록용만) |
| **트리거 캐시(클래스/속성별 활성 트리거)** | `triggers`, `attributes[].triggers` | **×** | `tr_*` 전부 client 절반(trigger_manager.c 129함수), `tr_Schema_caches`는 `tr_context`(trigger_manager.h:245) |
| **권한(owner, auth_cache, _db_auth 판정)** | `owner`, `auth_cache` | **×** | develop `authenticate.h:31 #error Does not belong to server module`; 폴드에서도 `au_*`는 client 절반 |
| **클래스 코멘트, 콜레이션 id, TDE** | `comment`, `collation_id`, `tde_algorithm` | △ | TDE만 `or_class_tde_algorithm`; 코멘트·콜레이션은 레코드 안에 있으나 서버 독자 없음 |
| **resolutions(상속 이름 충돌 해석)** | `resolutions` | **×** | 카탈로그 기록용만 |
| **class_type(뷰/프록시 구분), 플래그** | `class_type`, `flags` | × | — |

## 3. 폴드의 "MOP-free 서버 의미론" 관례

- **XASL은 OID·HFID만**: `pt_to_class_spec`류가 `hfid = sm_get_ch_heap(class_)`(xasl_generation.c:5195), `cls_oid = WS_OID(class_)`(:5201) → `spec->s.cls_node.cls_oid`(:5220). 실행기는 MOP를 모른다.
- **값은 OID로 정규화**: `mr_data_writeval_object`(object_primitive.c:5202)가 `WS_OID(mop)`(:5249)를 쓴다. wf173 커밋 2d53f68f8 본문: "Produce-side sites (mr_data_readval_object etc.) keep the server (OID) convention — producing OIDs is always safe for both halves"; consume-side는 hat(db_on_server)이 아니라 **세션 소유권(`csc_bracket_is_active`)**로 판정.
- **도메인 캐시는 콘텐츠 기준 라우팅(B4-D9)**: object_domain.c:1894-1952 — `class_mop`을 품은(재귀 setdomain 포함) 도메인만 세션 리스트(`TP_SESSION_DOMAINS{domains[DB_TYPE_LAST+1], midxkey_domains[…]}` :1902-1907, 슬롯 `csc_tp_domains_slot`), MOP 없는 도메인은 프로세스 리스트 유지 — "타입 단위로 세션 리스트에 몰면 built-in 매칭 도메인이 할당 클론으로 강등되어 XASL 스트림 형태가 깨진다(게이트: vclass COUNT(*))"(:1935-1941). 해제는 `ws_final` **이후** `tp_session_domains_final`(client_session_context.cpp:260-266).
- **서버 절반이 세션 컨텍스트를 만지는 지점은 프로브 4종만**: `csc_bracket_is_active`(network_callback_sr.cpp:44,83; query_manager.c:75; session.c:2187), `csc_in_method_dispatch`(page_buffer.c:3203), `csc_has_method_callback_state`(query_executor.c:17390,17396), `csc_retire_and_delete`(session.c:390). 실행 핫패스가 세션 객체 컨텍스트를 참조하지 않는다는 #123 D1 불변식이 지켜지고 있다(assert 수준).

## 4. 현행 세션 워크스페이스 비용

- **실측(#123 F2, develop@5862371ba, gdb, ~20테이블 DML 세션)**: SM_CLASS 콘텐츠 ~100-150KB + 고정 128KB(MOP 테이블 64KB + lea base 64KB) + 첫터치 AREA 블록 ~350KB → **0.3-0.6MB/세션**. 지배항 SM_ATTRIBUTE 272B×컬럼수(그중 128B가 SM_DEFAULT_VALUE의 DB_VALUE 2개; class_object.h:394-398 확인).
- **폴드가 이미 적용한 감축(코드 확인, 재실측 없음)**:
  - D6: `ws_init`에서 SERVER_MODE이고 `initial_workspace_table_size`가 명시 설정되지 않으면 범위 하한(1024)으로 시작(work_space.c:2416-2428; 파라미터 기본 4096/하한 1024, system_parameter.c:1547-1555). `WS_MOP_TABLE_ENTRY{head, tail}`(work_space.h:449-453) 16B → **1024×16B = 16KB**(develop 64KB).
  - D5: AREA(Objlist·Value·Set·tp_Domain)는 프로세스 공유(work_space.c:162, :3931-3939; object_primitive.c:1791-1799; set_object.c:161,170; object_domain.c:668) → 350KB 첫터치가 세션 항에서 빠짐.
  - lea heap base는 여전히 `LEA_HEAP_BASE_SIZE (64U*1024U)`(lea_heap.c:208, 할당 :227) → 세션 고정 플로어 **≈16KB + 64KB = 80KB**(파생값).
  - 도메인: B4-D9로 MOP 도메인 노드만 세션 사본. `TP_SESSION_DOMAINS` 자체는 포인터 배열(수 KB 미만).
- **Teardown 일괄 해제** `csc_teardown`(client_session_context.cpp:215-268): `db_free_execution_plan` → `pt_free_label_table` → `method_callback_session_final`/`method_runtime_args_session_final` → `sm_final`(descriptors·virtual query cache) → `db_final_client_query_results` → `ws_final`(MOP 테이블·classname 캐시·resident 리스트·lea heap; work_space.c:2512-2570) → `tp_session_domains_final`. 순서 의존이 주석으로 고정되어 있다(:243-245, :260-265).
- **중복의 정체**: 클래스 하나가 (i)힙 페이지(디스크 표현) (ii)`heap_Classrepr`의 OR_CLASSREP (iii)세션마다 SM_CLASS — 3벌. (ii)와 (iii)는 속성·도메인·인덱스·파티션에서 **정보가 겹치고**, (iii)만 뷰·권한·트리거·메서드를 갖는다(§2.5).

## 5. 대체 후보 단계안

### 후보 (a) — 읽기 전용 컴파일 경로만 catalog/heap_Classrepr 직독(latch), DDL은 워크스페이스 유지

| 관점 | 사실 |
|---|---|
| 필요한 신설 | 서버에 없는 8종(§2.5 ×표: 뷰 query_spec 파스트리 캐시·메서드·트리거 캐시·권한·코멘트/콜레이션·resolutions·class_type)을 **서버 표현으로 새로 만들어야** 컴파일이 SM_CLASS 없이 완결됨. 이 중 권한은 #118 D3(서버 검증 신원)이 선결 |
| 깨는 불변식 1 — 단일 표현 | 같은 클래스를 컴파일은 OR_CLASSREP+신설 표현으로, DDL은 SM_TEMPLATE/SM_CLASS로 봄. `sm_update_class` 직후 같은 세션의 다음 문장이 컴파일에서 보는 표현은 `xlocator_force`가 `heap_classrepr_decache`를 호출한 뒤여야 일관 — 트랜잭션 내 미커밋 DDL 가시성은 현재 "자기 워크스페이스의 dirty MOP"로 얻는데(예: CREATE TABLE 후 같은 tx에서 INSERT), heap_Classrepr는 커밋 무관 프로세스 공유 캐시라 **트랜잭션-로컬 스키마 뷰**를 별도로 제공해야 함 |
| 깨는 불변식 2 — chn 코히런시 | prepared 재검증(`pt_has_modified_class`→`db_object_chn`)과 `locator_can_skip_fetch_from_server`는 MOP의 chn/lock 필드에 의존. 컴파일이 MOP를 만들지 않으면 재검증 키를 `heap_Classrepr`의 rep_id 또는 서버 xcache 무효화(`xcache_remove_by_oid`, log_manager.c:5143)로 갈아야 함 — 후자는 이미 프로세스 공유라 정합 |
| 깨는 불변식 3 — 파스트리↔MOP 결합 | 파스트리 `PT_NAME.db_object`(DB_OBJECT* = MOP)를 코드 전반이 들고 다님(name_resolution.c:1882, :6878 등). `au_fetch_class(name->info.name.db_object…)` 형태 호출이 (a)에서도 남는 한 MOP는 생성됨 → 사실상 파서 노드 타입 변경 |
| 물량(grep) | 컴파일 소비점 파일 15개, 참조 ~300건(§1(a) 표), `class_->` 역참조 1,210건 중 파서·옵티마이저 부분; view_transform.c 25건은 query_spec 서버 표현 신설 후 재작성; `sm_get_class_with_statistics`는 이미 OID 기반 `stats_get_statistics(WS_OID(classop)…)`(schema_manager.c:4127)라 가장 쉬운 축 |
| SA 선례 | **없음**. SA(csql -S, cub_sa)는 컴파일러+서버가 한 프로세스인데도 워크스페이스·MOP·`tf_disk_to_class`를 그대로 쓴다(#115 (b): "MOP→OID 변환·XASL 스트림 복제는 한 주소공간에서도 유지"). #123 D1이 이를 "존치의 산 증거"로 삼았다 |
| 얻는 것 | 세션당 SM_CLASS 콘텐츠(100~150KB/20테이블)와 역직렬화 CPU. 고정 플로어 80KB는 (a)로는 안 사라짐(DDL·label·결과셋이 워크스페이스 사용) |

### 후보 (b) — 표현 통합(SM_CLASS를 서버 표현으로 대체)

| 관점 | 사실 |
|---|---|
| 물량 | `schema_manager.h` 포함 83파일, `work_space.h` 46, `class_object.h` 44, `locator_cl.h` 51. 함수: schema_manager.c 277, class_object.c 156, trigger_manager.c 129, work_space.c 123, transform_cl.c 98, schema_template.c 89, locator_cl.c 86, object_accessor.c 62, object_template.c 45, virtual_object.c 36, authenticate* ~100 → **~1,000 함수**. execute_schema.c의 템플릿 호출 143건이 전부 새 API로 |
| 깨는 불변식 | (a)의 3개 + **DDL 스테이징 모델 자체**(SM_TEMPLATE→flatten→install_new_representation→locator_flush 순서, 상속 락 순서 lock_supers/lock_subclasses)와 트리거/권한/가상객체(vclass 인스턴스 = vmop)의 MOP 의존 전부. 클래스 레코드 포맷(`tf_class_to_disk`)은 유지 가능하나 작성자가 바뀜 |
| 서버 자산과의 관계 | #123 D1 F4 그대로: "서버는 SM_CLASS를 표현할 능력이 아예 없다 … heap_Classrepr가 shape 선례일 뿐". 신규 상태 설계 |
| SA 선례 | 없음(동일) |
| 판정 인용 | #123 D1: "'워크스페이스 제거 = 컴파일러를 서버 표현 위에 재작성'은 이 맵 밖 규모라 기각". #113: "MOP 폐쇄계(ws_Mop_table+quick_fit 힙+AREA+sm_Root_class_mop 101곳+트리거/인증 캐시)는 불가분 한 덩어리 … 티켓 분할 시 쪼개지 말 것" |

### (a)의 축소판 — "이미 서버가 가진 사실만 read-through" (본 조사에서 도출한 최소 단계)

- 대상: HFID·rep_id·파티션 타입·인덱스/BTID·통계 — `xasl_generation.c`가 `sm_get_ch_heap`/`sm_partitioned_class_type`/`sm_att_id`/`sm_get_class_with_statistics`로 읽는 것들. 이 값들은 OR_CLASSREP/OR_PARTITION/CLS_INFO에 **그대로** 있다.
- 방식: `sm_*` 접근자 뒤에서 SM_CLASS 대신 `heap_classrepr_get`(fcnt 핀, 해시/엔트리 뮤텍스)로 읽는 read-through. SM_CLASS 물질화(이름 해석+권한)는 남으므로 불변식 1~3을 깨지 않는다. 단 SM_CLASS가 이미 있으면 중복 읽기라 이득은 "SM_CLASS를 아직 fetch하지 않은 경로"에 한정 → 실효는 작다. 진짜 이득은 **chn 재검증 계층(1(c))의 서버 xcache 무효화로의 위임**과 `heap_Guesschn` 제거(#123 D4 성능 트랙 fog)이며, 이는 표현 대체 없이도 가능.

## 6. 판정(사실에서 직접 따라오는 것만)

1. "client workspace를 서버 카탈로그 read-latch로 대체"는 **현행 서버 표현의 정보 부족(§2.5 × 8종)** 때문에 단기에는 성립하지 않는다. 카탈로그 래치가 부족한 게 아니라, 래치 아래에 **컴파일러가 읽을 의미 절반이 없다**.
2. 폴드가 없앤 것은 왕복(③)의 네트워크 홉이지 캐시 계층 자체가 아니다. 남은 잉여는 (i)락+chn 비교+역직렬화 3단, (ii)`heap_Guesschn`, (iii)클래스 1개당 3벌 표현. 이 셋은 SM_CLASS를 유지한 채로도 줄일 수 있다(§5 축소판).
3. (a)를 밟으려면 **뷰 query_spec·권한·트리거의 서버 표현**이 선결이고, 그 중 권한은 #118 D3(서버 검증 신원)에 묶여 있다. (b)는 #123 D1/#113의 기각 판정을 뒤집을 새 사실이 이번 조사에서 나오지 않았다.
4. SA 모드는 "한 프로세스에서 워크스페이스를 쓰는" 선례이지 "워크스페이스 없이 컴파일하는" 선례가 아니다.

## 확인 못 한 것

- 인용된 선행 문서 `docs/research/client-global-state.md`, `sa-mode-merge-boundary.md`는 미푸시 브랜치(`research/client-global-state` 20d1c84/bfc594e, `research/sa-mode-merge-boundary` e674aee)에만 있었고 현 워크트리·리포 어디에도 없어 **이슈 #113/#115/#123 본문의 요약을 대신 인용**했다. 0.3~0.6MB·272B·128KB 수치는 #123 F2 인용값이며 폴드 tip에서 재실측하지 않았다(§4의 16KB/80KB는 코드에서 파생한 값).
- `cas-merge-final-gate-and-defect-log-1.md`에는 "B4-D9"·"도메인 캐시" 문자열이 없다(grep 0건). B4-D9의 결함 맥락은 코드 주석(object_domain.c:1894-1952, client_session_context.hpp:121-129)과 커밋 2d53f68f8(wf173) 본문에서 확인했다.
- `class_->` 1,210건은 문자열 grep이라 SM_CLASS 외 구조체(PT_NODE `class_` 변수 등) 포함 과대치. 함수 수도 `^name (` 패턴 grep이라 근사치.
- (a)에서 "트랜잭션-로컬 미커밋 DDL 가시성"을 heap_Classrepr가 어떻게 취급하는지(decache 시점이 `xlocator_force` 시점인지 커밋 시점인지) 코드 경로를 끝까지 추적하지 않았다 — log_manager.c:4111/5169의 `decache_heap_repr`가 sysop/savepoint 경계에 걸린 것만 확인.
- 빌드·실행·측정은 하지 않았다(티켓 지시).
