# CBRD-27365 #7866 리뷰 반영 (#243) — 최상위 UNION ALL fast path 의 BACKWARD 유실(P1) + `qfile_scan_prev` release 방어(P3)

- 티켓: xmilex-git/workspace #243 (지도 #179). upstream PR CUBRID/cubrid#7866 에 2026-09-10 shparkcubrid 가 남긴 인라인 리뷰 2건(`list_file.c:2427` P1, `list_file.c:5055` P3). 리뷰어 캠페인(debug 빌드, 약 2,900건 + JDBC 스크롤)에서 PR 고유 결함은 P1 하나.
- 브랜치 `CBRD-27365-pr3`(수정 전 HEAD `87433ead2`). 검증 빌드 `~/optdebug/CUBRID-cbrd27365-pr3-gate`(optdebug), `~/release/CUBRID-cbrd27365-pr3-87433ea`(release, 컴파일 게이트 — 이름은 87433ea 이지만 이번 incr 로 수정본이 설치됨).

## 1. P1 원인 확인 (리뷰어 분석과 일치)

- `qexec_execute_mainblock` UNION_PROC 분기(query_executor.c:15476)는 `ls_flag` 에 `XASL_LIST_BACKWARD_FLAG (xasl)`(TOP_MOST → `QFILE_FLAG_BACKWARD`)를 넣어 `qfile_combine_two_list` 를 부른다.
- `qfile_combine_two_list` 는 `UNION|ALL` 이고 두 입력이 result-cached 가 아니면 **fast path `qfile_union_list`** 로 간다. `qfile_union_list` 는 `flag` 를 전혀 읽지 않고 `qfile_clone_list_id (base)` 로 결과를 만들고 tail 을 `qfile_copy_tuple` 로 붙인다. 결과의 `type_list.hdr_size` 는 base(자식)의 4 그대로 → 최종 결과 리스트가 forward-only 로 클라이언트에 전달된다.
- UNION_PROC 의 자식 xasl 은 TOP_MOST 도 `XASL_LIST_BACKWARD` 도 아니어서 자식 리스트는 `hdr_size = 4`.
- 역방향 커서(`cursor_prev_tuple`, cursor.c:1581)는 `QFILE_LIST_IS_BACKWARD` 가 아니면 debug 는 assert(false) → CAS abort, release 는 `ER_QPROC_INVALID_CRSOPR`. 결과 행수가 CAS fetch 블록(100)보다 커서 서버 왕복(`db_query_seek_tuple`)이 생겨야 드러난다 → CTP(csql)·기존 smoke(30행)가 못 잡은 이유.
- #184 연구표(`docs/research/cbrd27365-backward-lists.md` §2.1 행 1)는 `qfile_combine_two_list` 를 "`flag` 인자로 상속됨" 으로 분류했다. 복사 경로(정렬·distinct·intersect·difference)는 맞지만 fast path 는 clone 이라 틀렸다 → 문서 정정.
- 영향 범위(리뷰어 실측): 최상위 `UNION ALL` 계열 5 shape(2/3 분기, 다른 테이블, 한쪽 공집합). `UNION`(distinct)/INTERSECT/EXCEPT 는 fast path 를 안 타고, ORDER BY/LIMIT/파생테이블/CTE/뷰로 감싸면 `qexec_orderby_distinct` 나 바깥 BUILDLIST 가 BACKWARD 로 재구체화하므로 정상.

## 2. 결정

- **D-243-1 본 수정 = `XASL_LIST_BACKWARD` 전파(xasl_generation)**. `parser_generate_xasl` 이 `XASL_TOP_MOST_XASL` 을 세우는 자리에서 `pt_mark_union_children_backward (xasl)` 호출: xasl 이 UNION_PROC 이면 left/right 에 `XASL_LIST_BACKWARD` 를 세우고, UNION_PROC 자식으로 재귀(중첩 UNION ALL 은 자식 clone 을 다시 위로 올리므로). `XASL_LIST_BACKWARD_FLAG (child)` 를 쓰는 모든 자식 리스트 open 지점(BUILDLIST/BUILDVALUE/groupby/orderby/analytic/hash join/px/MERGELIST/UNION 재귀)이 그대로 BACKWARD 로 열리므로 자식 종류별 분기가 없다. 선례: `ptqo_to_merge_list_proc` 의 MERGELIST 자식 마킹. option(ALL/DISTINCT)·orderby 유무로 조건을 좁히지 않았다 — 좁히면 실행기 fast path 조건과 컴파일러 조건을 두 곳에서 맞춰야 하고, 비용은 자식 리스트 튜플당 4B(최상위 UNION 일 때만).
  - 대안(기각): 실행기 `qexec_execute_mainblock` 에서 자식 실행 전에 서버 측 전파 — 가능하지만 MERGELIST 선례와 갈라지고 XASL 스트림에 이미 flag 가 실리므로 이점이 없다. 에스케이프 해치로 남긴다.
  - 참고: `XASL_LIST_BACKWARD` 는 `xasl->flag` int 로 pack/unpack 되므로 wire 변경 없음(xasl_to_stream.c:2831).
- **D-243-2 방어 게이트(list_file.c `qfile_combine_two_list`)**: fast path 조건에 `!BACKWARD(flag) || (IS_BACKWARD(lhs) && IS_BACKWARD(rhs))` 추가. 전파가 빠진 새 경로가 생겨도 손상 대신 전체 복사(정상 backward 결과)로 떨어진다. 해시조인(query_hash_join.c:1902, flag 에 BACKWARD 없음)·CTE(18426, CTE_PROC 은 TOP_MOST 아님)는 조건이 그대로 참이라 동작 불변.
- **D-243-3 debug assert**: UNION_PROC 분기에서 combine 결과를 `xasl->list_id` 로 승격하기 직전 기존 helper `qexec_assert_result_list_backward (xasl, t_list_id)` 호출. hash join(265)·px(684)·CTE(18495)에는 같은 assert 가 있었고 UNION 만 빠져 있었다 — 있었다면 debug CTP 의 모든 최상위 UNION 질의에서 잡혔을 것.
- **D-243-4 P3 = release 방어 대칭**: `qfile_scan_prev` 의 같은 페이지 후진 분기에서 `assert` 만 있던 것을 `cursor_prev_tuple` 과 같은 형태(`assert (false)` + `er_set (ER_QPROC_INVALID_CRSOPR)` + `return S_ERROR`)로. 페이지 경계 분기는 페이지 헤더 LAST_TUPLE_OFFSET 을 쓰므로 prev_len 과 무관해 그대로.
- 주석: `xasl.h` 의 `XASL_LIST_BACKWARD` 설명에 UNION_PROC clone 경우를 추가.

## 3. 재현·검증

- **D-243-5(사용자 결정)**: smoke(`ScrollSmoke.java`)는 확장하지 않는다. 재현·확인은 스크래치 `.git_ignored_dir/scratch/i243/UnionScroll.java`(리뷰어 재현 코드와 같은 형태: scroll-insensitive, `setFetchSize(100)`, 5,000행 × 2/3 분기·공집합 분기, next 전부 → afterLast → previous 전부)로만 하고, 검증 항목은 JIRA `test.md`(T14) 에 기록한다. 기존 smoke 는 회귀 확인용으로 그대로 실행.
- (검증 결과는 §4)

## 4. 검증 결과 (커밋 `05c1af29d`, upstream #7866 head)

- **재현(수정 전, optdebug 91fc19a 바이너리 — union 경로 무변경)**: 최상위 UNION ALL 600행 역방향 스크롤에서 CAS 코어. `$CUBRID/log/coredump/query_editor_cub_cas_1_20260910112232.505.coredump`: `__assert_fail` → `cursor_prev_tuple` cursor.c:1583 → `db_query_seek_tuple` db_query.c:2708. 리뷰어 스택과 동일. 증거 `.git_ignored_dir/scratch/i243/A-before-*`.
- **빌드**: `just incr debug`/`just incr release` 경고 0. `libcubridsa/cs.so` 에 `pt_mark_union_children_backward` 심볼 확인(`cubrid_rel` 배너는 증분 빌드에서 갱신되지 않음 — 표시만 stale).
- **수정 후(optdebug)**: smoke ×2 csql PASS / scroll PASS. csql 형상 6종(2분기 10,000 · 3분기 15,000 · 공집합 분기 5,000 · distinct 5,000 · ORDER BY LIMIT · 서브쿼리 혼합 200) 정확, 서버 .err assert/ERROR 0. JDBC `UnionScroll`(scroll-insensitive, fetch 100, 5,000행): 3분기 fwd/bwd 15,000/15,000 합 37,507,500 일치, 공집합 분기 5,000/5,000 합 12,502,500 일치, 예외 없음. 코어 없음.
- **CTP sql 전수**(`PR=7866 BUILD=~/optdebug/CUBRID-cbrd27365-pr3-gate SHARDS=7 just ctp sql`): **17,457/17,457 fail 0, 코어 0**. 이전 기록 17,449/17,457 의 8건은 develop 답안 기준 실패였고 이번 run 은 `tc/pr-7866`(#201 답안 정정) 기준. out `.git_ignored_dir/scratch/ctp-run-out/sql-20260910T022655Z-1327667`.
- **리뷰어 3자 비교(develop 2152dec7c / PR / PR+게이트, debug)**: develop 전부 정상(구 포맷은 항상 8B 헤더), PR 은 UNION ALL 계열 5 shape CAS 사망, 게이트만으로도 5 shape 복구. 우리 최종안은 전파+게이트라 fast path 유지.
- 리뷰 답변 2건 + `/run all` 게시(2026-09-10).
