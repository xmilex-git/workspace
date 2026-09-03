# CBRD-27365 PR-2b 리드 직접 리뷰 (fork PR xmilex-git/cubrid#259, 베이스 `286b6ab8a`) — 티켓 #191 세션, 지도 #179

모델 교체 뒤 사용자가 요청한 재검토. 대상은 `git diff CBRD-27365-pr2a..CBRD-27365-pr2b` 전 파일(24파일, +1318/−869)과
`qfile_tuple_layout.{h,c}` 현재 전문. ADR 0016 §1.1, `cbrd27365-tuple-format-spec.md`, `cbrd27365-pr2b-format-swap.md`(D-199-*)
와 대조했고 `cpp-perf-rules` CHECKLIST(§18)를 적용했다. 결정 ID `D-191-*`. 수정은 모두 워크트리 `CBRD-27365-pr2b` 위에 커밋한다.

## 판정 요약

포맷 핵심(길이 워드 bit31·조건부 비트맵·`data_off=ALIGN4(hdr+bitmap)`·고정 정렬 {2,4}·가변 1B/4B 헤더·NULL 0바이트, 리더/라이터
대칭, D-199-7 `qfile_prefix_end`, D-199-3 헤더 재작성 `ALIGN4(8+b)−ALIGN4(4+b)=4`, SCRATCH 매크로 짝, in-place 계약)은 **정확**하다.
소비자 치환 35곳은 전부 `qfile_slot_read_value`/walk 로 갔고, raw 역참조가 남은 곳은 FIXED 컬럼(해시키 INT·카운터·머지 NULL 판정·정렬
레코드 raw src)만이다. 아래 결함 **1건(BUG, 잔여 -495 의 원인)** 과 **하드닝 4건** 을 수정했고, 리스크 2건은 #192 검증 항목으로 넘긴다.

## 결함·수정

| ID | 심각도 | 위치 | 내용 | 수정 |
|---|---|---|---|---|
| D-191-1 | **BUG** | `query_executor.c` `bf2df_str_compare` | 그룹 비교 뒤 `if (*s0 == '.') s0++` 가 `s0 == e0`(문자열 끝)일 때 **1바이트 경계 밖을 읽는다**. 구 포맷은 문자열 값 뒤에 `or_put_align32` 0 패딩이 있어 잠복했고, 새 포맷은 뒤에 다음 컬럼(또는 P 미니튜플이면 정렬 레코드 잔여 바이트)이 바로 온다. 그 바이트가 0x2E('.')이면 `"1"` vs `"1.1"` 이 `DB_UNK`(−2) 가 되어 비대칭·비추이적 비교 → BF→DF 순서가 깨져 `qexec_recalc_tuples_parent_pos_in_list` 레벨 언더플로(#199 D-199-15 의 `_03_adhoc_delete_update_3` −495). SELECT 는 통과하고 DELETE 서브쿼리만 실패한 이유는 정렬 레코드 버퍼의 잔여 바이트가 달랐기 때문이다. | `s0 < e0 &&` / `s1 < e1 &&` 가드. cpp-perf FP-02(비교자 대칭) 위반 사례. |
| D-191-2 | BUG(잠복) | `list_file.c` `qfile_initialize_sort_key_info` | 비교 도메인이 `DB_TYPE_VARIABLE` 이면 `types->domp[i]`(컬럼 i)로 폴백하는데 키 i 는 컬럼 `key[i].col` 이다. 레거시 코드도 같은 인덱스 오류였지만 자기 기술 포맷에선 비교 함수만 어긋났고, 새 포맷은 `key_tl.col[i]`(올바른 컬럼)의 kind 로 라우팅한 뒤 잘못된 도메인의 비교자를 부르므로 위험이 커졌다. | `types->domp[subkey->col]`. |
| D-191-3 | RISK→가드 | `qfile_tuple_layout.h` `qfile_value_body_size` | FIXED 컬럼에 폭이 다른 값, DIRECT 컬럼에 index 인코딩이 없는 타입의 값이 오면 디버그 assert 만 있고 릴리스는 그대로 써서 튜플을 오버런/오독한다(구 포맷은 값 헤더 덕에 관용). D-199-13 값 기반 확정 뒤 두 번째 값의 타입이 다른 경우가 대표 시나리오. | 릴리스에도 `ER_QPROC_INVALID_DATATYPE` + `ER_FAILED`. 컬럼당 예측 가능한 분기 1개(BR-01 무시 가능). |
| D-191-4 | NIT | `object_representation.c` unpack | wire `hdr_size` 를 `uint8_t` 로 먼저 잘라 260 이 4 로 통과. | 4/8 아니면 0 으로 두어 뒤의 검사가 잡게. |
| D-191-5 | NIT | `qfile_tuple_layout.c` `qfile_slot_overwrite_value` DIRECT 분기 | 기록 길이 검증이 FIXED/SCRATCH 분기에만 있었다. | `CAST_BUFLEN(buf.ptr-buf.buffer) != len` 검사 추가. |
| D-191-6 | DOC | `qfile_tuple_layout.{h,c}` | D-199-13 주석이 반박된 #186 전제를 근거로 인용. | "첫 bound 값에서 확정하므로 구조적으로 성립" 으로 정정. |
| D-191-7 | #191 본건 | `cursor.c` `cursor_prev_tuple` | forward-only(hdr 4) 리스트에서 assert 만 있고 릴리스는 비트맵/값 바이트를 prev_len 으로 읽어 쓰레기 오프셋으로 이동. | `ER_QPROC_INVALID_CRSOPR` + `DB_CURSOR_ERROR`. |

## 리스크(수정 안 함, #192 로 이관)

- **R1 스캔 복사본의 디스크립터 staleness**: `qfile_open_list_scan` 은 `type_list` 를 스캔에 복사한다. 리스트가 열린 스캔이 있는 상태에서
  append 되고(`qfile_reopen_list_as_append_mode` 8곳: CTE 재귀 `recursive_part->list_id`, 커버링 인덱스 리스트, 해시조인 파티션, external_sort
  origin 등) 그 append 가 미확정 컬럼을 확정(D-199-13)하면 스캔의 복사본은 VAR 레이아웃으로 FIXED 바이트를 읽는다. 구 포맷은 regu 도메인으로
  디코드해 무관했다. 확정은 첫 bound 값(대개 첫 튜플)에서 일어나므로 창은 좁다. #192 에서 8곳을 "스캔 열린 채 append + VARIABLE 컬럼" 조건으로
  점검하고, 필요하면 append-mode 재개방 시 `is_domain_resolved` 를 assert.
- **R2 px 스냅샷 리더**: 도메인 발행(`m_type_list[i].store`)이 `update_domains_on_type_list_by_val_list` 직후·조립 전에 이뤄지고 조립기의
  값 기반 확정은 같은 값 목록에서 나오므로 일치하지만, 발행 지점이 두 곳(첫 튜플 전·close)이라 조립기가 추가로 확정한 컬럼이 있으면 첫 발행에
  빠질 수 있다. 값이 있으면 by_val_list 가 먼저 확정하므로 실제로는 빈 집합. 주석으로 남긴다.

## cpp-perf-rules 관점

- 행당 경로(`qfile_slot_locate`/`read_value`/조립기)에 새로 추가된 것은 D-191-3 의 컬럼당 비교 1개(예측 가능)만. MEAS-01 근거 없이 최적화 제안 없음.
- 정렬 비교자(`qfile_compare_partial_sort_record`)의 SCRATCH 키 힙 폴백(>256B SET/JSON 키)은 비교당 malloc(ALLOC-01)이지만 해당 키 타입은 드물다 — #193 관찰 항목.
- 패딩 바이트는 디버그에서만 0 으로 채운다(릴리스 memset 회피). D-191-1 같은 과다 읽기는 이제 릴리스에서 비결정적이므로, 리더/비교자가 길이를
  넘어 읽지 않는지가 리뷰 체크 항목이 되어야 한다(FP-02 대칭 프로브 권장).

## 검증 (sonnet 워커, 설치 `~/optdebug/CUBRID-cbrd27365` optdebug, DB `cbrd27365s`@1702 매 빌드 재생성)

| 단계 | 대상 | 결과 |
|---|---|---|
| 수정 전 재현 | `286b6ab8a` 빌드 | 5줄 재현의 DELETE 가 `-495`(err 로그 `query_executor.c:17246`), count 100 유지. ORDER SIBLINGS 기준 출력 저장. |
| 1차 빌드(D-191-1·7) + 재현 | `47848e88b`·`9ea39a41a` | 증분 빌드 경고 0. DELETE 성공(100 rows), count 0; ORDER SIBLINGS 출력 수정 전과 동일; `SYS_CONNECT_BY_PATH` 1300행 정상. smoke csql/scroll PASS ×2. 격리 CTP `_03_adhoc`+`bug_4178` **31/31**, 코어 0. |
| 2차 빌드(D-191-2~6 포함) + smoke | `a2456c390` | 헤더 변경으로 101 타깃 재빌드, 경고 0. 재현 OK, smoke PASS ×2. |
| CTP sql 전수 | `a2456c390`, 7 shard, 감시 ON, ~38분 | **17,449/17,457, 코어 0, err 로그 assert/leak 0.** 실패 8 = 플랜/TRACE 텍스트 7(cbrd_24148·cbrd_23665·cbrd_25382_1/_5·cbrd_25519·cbrd_25447·join_orderby_skip: `(parallel workers…)` 줄·`hash temp(h)→(m)`·`BUILD hybrid→memory`) + agg_group_by 답안 drift(D-190-12). `_03_adhoc_delete_update_3` **해소**, 신규 실패 없음. |

운영 메모: `just port-claim` 이 빈 슬롯 1700 을 배정해 설치본 conf(1702)와 어긋났고, 워커가 1702 클레임을 수동 등록해 맞췄다(등록 뒤 `just ports` 확인).
로그는 `.git_ignored_dir/scratch/pr191/`.
