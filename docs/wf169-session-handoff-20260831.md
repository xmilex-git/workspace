# wf169 세션 핸드오프 — CTP 게이트 재진입 마라톤 (2026-08-31)

> 이 문서는 2026-08-31 하루 동안 진행한 [#169 게이트 재진입](https://github.com/xmilex-git/workspace/issues/169) 세션의
> 전체 지식 이관본이다. 다음 세션(미래의 나)은 이 문서 + [#176 CTP 결함 통합 추적](https://github.com/xmilex-git/workspace/issues/176)의
> 코멘트 체인만 읽으면 이어서 달릴 수 있어야 한다.
> 맵: [#112 CAS 통합 지도](https://github.com/xmilex-git/workspace/issues/112). 사용자 규약: **CTP에서 나오는 결함은 새 티켓 만들지 말고 전부 #176 코멘트로만** (맵 Notes에도 박혀 있음).

## 0. 한 줄 요약

develop 19커밋을 cas-merge에 머지(충돌 0)하고 testcases를 최신화한 뒤, CTP를 7회 돌려
**medium 975/975 green + sql 사상 최초 전 스위트 완주(17,457 실행·크래시 0·NOK 1,660→138)**,
그 과정에서 결함 10건을 발굴해 8건 해소(제품 PR 7개 머지 + 하네스 2건), 2건(9·10)은 급소 직전까지 좁혀 놓았다.

## 1. 시작 컨텍스트

- cas-merge는 develop@95b79e7ed(08-26) 기준으로 19커밋 뒤처져 있었고(btree/btree_load 3,000줄 대변경 포함),
  로컬 ~/cubrid-testcases도 08-27자였다. 사용자 지시로 **둘 다 최신-최신으로**: `origin/develop@5ae45603f` 머지(충돌 0),
  testcases `e0643b4c9` ff. medium 스위트는 testcases 업데이트에서 무변경이라 `wf143/medium-root` 사본 그대로 유효.
- 작업 워크트리: `~/dev/worktrees/wf143-gate` (cas-merge). 설치본: `~/optdebug/CUBRID-wf143-gate`, `~/release/CUBRID-wf143-gate`.
- baseline 판별용: `~/dev/worktrees/wf176-baseline`(develop@5ae45603f detached) → `~/optdebug/CUBRID-wf176-baseline`
  (**jdbc jar는 수동 복사 필요했음** — justfile build는 jdbc 패키징 안 함).

## 2. 최종 상태 (커밋/PR)

cas-merge HEAD: **@ed284a2e3** (xmilex/cas-merge push 완료). 머지된 PR:
| PR | 결함 | 내용 |
|---|---|---|
| cubrid#239 | 1 | er_stack_clearall의 method-dispatch floor 계약 (`csc->er_dispatch_floor`, `er_stack_clear_above`) |
| cubrid#240 | 3 | online 인덱스 로더에 btid 로컬 사본 전달 (스크래치 오염 차단) |
| cubrid#241 | 4 | prm 세션 write-through(int/bool) + optimization level 3사이트 `qo_set_optimization_param` 통일 |
| cubrid#242 | 5 | `xts_debug_check`(json_table) 실스레드 + unpack 슬롯 save/restore |
| cubrid#243 | 7a | in-dispatch commit의 `pgbuf_unfix_all` sweep 생략 (`csc_in_method_dispatch`) |
| cubrid#244 | 6 | SET SYSTEM PARAMETERS 브래킷 시 클라이언트 스코프 규칙(검증+적용 양측) + 세션 시작 ansi_quotes 부트값 복원 |
| cubrid#245 | 8 | 폴드 pl_call의 미초기화 ret_value `db_make_null` |
| **cubrid#246** | 9 | **부분 수정·머지 보류** — 세션변수/method결과 OBJECT→OID 정규화 2 seam (무회귀, 표적 미해결) |

하네스 커밋(이 리포): Containerfile ko/tr langpack(2b07c3e). 이 문서 커밋 예정.
브랜치 잔재: `wf176/d1-…~d9b-…` (전부 push됨), 로컬 worktree는 wf176/d9b-method-result-oid에 체크아웃 상태.

## 3. 결함 대장 (#176 코멘트가 1차 소스 — 여기는 색인+핵심만)

1. **er-stack 불균형 SIGABRT** (plcsql): client-half `tran_commit/abort`의 `er_stack_clearall()`이 dispatch 격리 프레임까지 파괴.
   → floor 계약. 패턴: *레거시 "프로세스 경계"는 폴드에서 "깊이 floor"로 번역한다.*
2. **컨테이너 ko/tr locale 부재**: `std::locale("ko_KR.utf8")` throw→assert. 이미지에 glibc-langpack-ko/tr 추가. 제품 무변경.
3. **online 인덱스 btid 스크래치 오염**: `xbtree_load_online_index`는 입력 btid를 클래스 순회 스크래치로 씀
   (`btid_int.sys_btid = btid`). 폴드가 `&con->index_btid`를 직접 전달 → 부모 constraint가 마지막 파티션 btid로 오염
   → status→NORMAL 플러시가 "인덱스 교체"로 보고 그 파티션의 산 btree를 커밋 시 파괴 → DROP에서 미예약 섹터 assert.
   판별에 쓴 결정타: `log_btree_operations=yes`(debug)로 클래스별 btid 타임라인 + 코어에서 `P_vpid` 대조.
4. **prm lost-write 클래스**: #159가 read-through만 만들고 write 반쪽이 없었다. `prm_set_int/bool`에 세션 write-through 추가.
   optimization level은 별도로 **세션 override 슬롯**(`csc_qo_optimization_level`, qo_get이 prm보다 우선)이 정답 —
   `qo_set_optimization_param` 경유로 통일.
5. **json_table debug 왕복검증 NULL-thread SIGSEGV**: `xts_debug_check`가 pre-fold 클라이언트 관례(NULL thread→전역 슬롯).
   폴드에선 `thread_p->xasl_unpack_info_ptr` NULL deref. 실스레드 + **슬롯 save/restore**(서버 절반이 자기 unpack을 들고 있을 수 있음).
6. **SET SYSTEM PARAMETERS 스코프 3중 구멍**: ①`sysprm_generate_new_value` SERVER_MODE 분기가 client-only 파라미터를
   -840 거절 ②통과해도 `sysprm_change_parameter_values`의 서버 필터가 **성공 반환하며 silent skip** ③쓰기가 실재하면
   프로세스 prm에 세션을 넘어 잔존. → 양측에 `csc_bracket_is_active()` 분기(레거시 클라이언트 규칙), ansi_quotes는
   세션 시작 시 부트값 복원(`ux_set_default_setting`, 최초 세션이 부트값 캡처).
7. **7a**: PL 루프-내 COMMIT → 같은 스레드 `log_commit_local→lock_unlock_all→pgbuf_unfix_all`이 정지 중인 외부 실행기의
   정당한 page fix를 sweep/assert. dispatch 내부(`tm.libcas_depth>0`)에서 sweep 생략 — pre-fold client half는 자체 page fix 불가.
   **7b (미해소·잠복)**: 그 크래시 후 리커버리가 `spage_find_empty_slot_at`(slotted_page.c:1668, slot_id=3) assert로
   크래시루프 — **#166과 자리까지 동일 시그니처가 깨끗한 새 DB에서 재발** = 매체 불일치가 이 빌드의 정상 동작 중 생성됨 확정.
   WAL/flush 규율 감사가 실무 승격. 자산: `scratch/wf169/d7b-assets/`(크래시 databases+serverlog+코어 2종, 6.0G).
8. **pl_call 미초기화 ret_value**: `fetch_args_peek` 실패 경로에서 스택 쓰레기 clear → wild free. `db_make_null` 1줄.
   (sql4에서 NOK로만 보였던 것도 동일 지점의 비결정 발현 — *미초기화는 크래시와 오답 사이를 오간다*.)
9. **(미해결) 418-4 -181** `Cannot coerce object→*oid*`: OBJECT(MOP) 값이 서버-햇 실행에 도달.
   - 두 seam 정규화(세션변수 저장, method_invoke_group 결과 언팩)는 커밋했으나(PR#246) 표적 미해결.
   - 최종 스택(CTP-shape, call_stack_dump=-181): `xqmgr_prepare_and_execute_query → … → qdata_get_dbval_from_constant_regu_variable(query_opfunc.c:6668) → tp coercion`.
   - 기각된 가설: XASL 스트림 언팩(mr_data_readval_object는 **hat 기준으로 이미 정상** — db_on_server면 OID).
   - **재개 절차**: BUILD-d9b로 서버 기동(레시피는 #176 결함9 코멘트), `break tp_domain_status_er_set` 라이브 gdb로
     `select testoid1(xoo) into x from xoo`의 OBJECT 값 regu 타입/데이터 출처 특정 (마감으로 중단된 그 작업).
   - 재현 필수조건: test_mode=yes + `set system parameters 'create_table_reuseoid=no'` + loadjava
     (`SpTest6.class`는 이 리포 루트 미추적 `java/`에 있음).
10. **(미해결) i18n/tz 클러스터 ~112 NOK**: baseline 만점(877/877·1759/1759) vs merged 37/57 실패 — 폴드 회귀 확정.
    - 급소: `set system parameters 'intl_date_lang=…'` 후 `to_char(date,'Day')`가 **무조건 en_US** (it_IT→'Sunday').
      "DB 기본 로케일 착지" 가설은 오답으로 판명.
    - 정적으로는 쓰기(sysprm_set_value_internal의 FOR_SESSION 분기)·읽기(prm_get_string_value readthrough) 모두 정상으로
      보임 — 실측 발산 지점 미특정.
    - **사용자 힌트(마감 직전)**: "세션 구조체? vd(val_descr)에 timezone/i18n 정보가 있는데 지금 구조에서 똑바로 처리 안 되나?"
      → VAL_DESCR 자체(query_executor.h:75)엔 tz/i18n 필드가 없지만, 방향은: to_char의 lang은 **컴파일 시
      `lang_set_flag_from_lang`으로 XASL에 flag로 구워지고**(execute_statement.c:746, parser_support.c:10641,
      query_executor.c:12792/13323) 실행 시 세션 tz는 session_state 경유다. 다음 세션은 **컴파일 시점 flag가
      세션 값을 제대로 읽는지(어느 스레드/모자에서 굽는지) + 상수 폴딩 경로(pt_fold의 db_to_char)** 를 먼저 찍을 것.
    - tz 표본: `Africa/Juba` 기대에 `Africa/Khartoum` 출력(리전 해석 스큐) — i18n과 동근인지 별개인지 미판정.
    - 잔당: -840 6건(`require_like_escape_character` 등 — D6a의 ansi_quotes 외 파라미터 부트복원/검증기 raw-read 잔여),
      -1098×4(euckr tz)·-1042·-1207·-493×2·plcsql 2 등 롱테일 ~19건.

## 4. 런 히스토리 (7회 + medium 3회)

| 런 | 빌드 | 결과 | 비고 |
|---|---|---|---|
| medium1 | (오염) | 629 NOK | **하네스**: 기본 sql-플레이버 conf — medium은 `--ctp wf143/CTP-medium` 필수 |
| medium2 | (오염) | 975/975 | stale 16:22 바이너리 — 무효 |
| medium3 | 머지 | **975/975·core 0** | 스탬프 0d65251로 신원 확정 — 유효 |
| sql3 | (오염 13:17) | 워치독 중단 | 크래시 전부 기해결 결함(#170/171/173) 재관측 — 무효 |
| sql4 | 머지 | 워치독 중단(3코어) | 결함5 발굴 |
| sql5 | +D1~4 | 15,304 실행·223 NOK·30코어 | 결함7 발굴, 6/7 shard 완주 |
| sql6 | +D5~7a | 조기 중단(1코어) | 결함8 발굴 |
| **sql7** | +D8 | **17,457 전건 실행·코어 0·138 NOK** | 최종 상태 — 결과: `scratch/wf169/sql-out-214712/`, 분류: `scratch/wf169/sql7-noks.txt` |

## 5. 하네스/방법론 지식 (재발 방지 수칙)

1. **`--out`은 반드시 미존재 경로.** `cp -a`는 기존 `shard_N/CUBRID`가 있으면 그 *안으로* 중첩 복사한다.
   /clear 이전 세션이 같은 경로를 pre-merge 빌드로 만들어놔서 런 3개가 stale 바이너리로 돌았고,
   "설치 프리픽스 경합"이라는 유령을 2시간 쫓았다. birth time(`stat %w`)이 진범을 밝혔다.
   (orchestrator에 기존 shard workdir 가드 추가는 미착수 개선 항목.)
2. **바이너리 신원 검증은 mtime이 아니라 내용으로**: `gdb -batch -ex 'info line <함수>' lib/libcubrid.so`로
   라인넘버를 트리와 대조 (cmake install은 빌드 산출물 mtime을 보존하므로 mtime은 배신한다). 코어의 프레임 라인넘버가
   현행 트리와 어긋나면 그 코어는 다른 리비전 빌드다. 버전 스탬프는 configure 시점 것이라 항상 낡다.
3. **확증 런은 설치본이 아니라 snapshot에서**: 워커가 conf를 만지거나 재설치하는 동안 CTP가 그 설치본을 복사하면 오염된다.
   (`error_log_level=debug`는 무효값 — 워커의 conf 실험이 컨테이너 전멸을 일으킨 사례 1회.)
   또한 설치본 루트에 뒹구는 core.*는 shard 복사본에 딸려가 `--abort-on-core` 오탐을 낸다 — 런 전에 치울 것.
4. **medium-as-sql**: `--ctp scratch/wf143/CTP-medium --testcases scratch/wf143/medium-root --shards 1`.
   sql은 `--ctp scratch/wf143/CTP-sql`. `just ctp-parallel`은 `CUBRID=`, `ctp-sql-isolated`는 `BUILD=`.
5. **CTP-shape에서 에러 스택 뜨기**: CTP-copy를 복제해 `conf/sql.conf`의 `[sql/cubrid.conf]`에
   `call_stack_dump_activation_list=-XXX` 추가 후 해당 케이스만 `ctp-sql-isolated`. (#174의 방법 재확인.)
   debug 파라미터 실명: `er_log_debug=yes`, `log_btree_operations=yes` (log_btree_ops·error_log_level=debug는 무효).
6. **판별자 3종 세트**: (a) 케이스 변수 분리 2×2 프로브(파티션×online처럼), (b) baseline(순수 upstream) 동일-하네스 레그,
   (c) 격리 단독 vs 전체 스위트 (문맥 의존성 판별). 이 세션에서 각각 결함 3, 10, (6의 오진 방지)에 결정적이었다.
7. **컨테이너 코어 분석**: 이미지에 gdb 없음. 호스트 gdb + `set solib-search-path <shard>/CUBRID/lib`로 cubrid 프레임은
   풀린다(libc 프레임은 컨테이너 overlay 경로로 알아서 풀리는 경우가 많음). 워커(core-analyst)가 쓰던 "podgdb2" 방식 산출물은
   `scratch/wf169/coredump-analysis2/`.
8. **프로세스/스레드 압박**: CTP 병렬 런은 +2,300 스레드가 정상. 죽은 세션의 codex broker 트리(수일 묵은
   `app-server-broker.mjs` + codex + code-mode-host)가 ~640 스레드 잠식했었음 — SIGTERM 무시, 루트 pid에 직접 kill -9.
9. **팀 운용**: gate-builder(빌드+unit/smoke 게이트, 신뢰 높음·간헐 stale 메시지 크로스), repro-494(재현/판별, 매우 우수),
   core-analyst(산출물은 내지만 **4회 연속 무보고 idle** — 산출물 pull-검증 필수). 리드가 워커 빌드 중에 같은 트리를
   편집하면 혼합 빌드가 된다 — 편집 후 반드시 합본 재게이트를 명시 지시.

## 6. 폴드 계약 패턴 사전 (이 세션에서 확립/재확인)

- **경계 번역 패턴**: 레거시 "프로세스 분리"가 주던 격리는 폴드에서 (a) 깊이 floor(er-stack D1),
  (b) 사본 전달(btid D3, 와이어 팩 등가), (c) sweep/검사 생략(pgbuf D7a — client half가 만들 수 없는 자원이면 회수 대상도 없음),
  (d) 값 정규화(OBJECT→OID, qmgr 선례 = network_interface_cl.c:7735 패턴)로 번역된다.
- **판별축 구분**: 계약 assert는 세션 소유권(`csc_bracket_is_active`, #173), 값 **건설**(readval)은 모자(`db_on_server`) —
  mr_data_readval_object가 hat 기준인 것은 옳다. 결함 9의 잔여는 이 이분법 어딘가의 누락 지점이다.
- **세션 파라미터 대칭률**: 읽기가 세션이면 쓰기도 세션이어야 한다(D4b). SET SYSTEM PARAMETERS는 브래킷에서
  레거시 클라이언트 스코프 규칙(D6a). conf 파일 경유는 부팅 시 세션 초기화로 살고, 런타임 SET만 죽는 비대칭이
  "reuseoid는 되는데 intl은 안 되는" 미스터리의 정체였다.
- **미초기화 DB_VALUE는 에러 경로에서 터진다** (D8) — 폴드 분기 신설 시 `db_make_null` 챙길 것.

## 7. 자산 경로 (전부 `dev/workspace/.git_ignored_dir/scratch/wf169/`)

- `BUILD-d9b/` — 마지막 검증 빌드 스냅샷(= cas-merge@ed284a2e3 + PR#246 내용)
- `sql-out-214712/` + `sql7-noks.txt` — 최종 138 NOK 원본과 분류
- `d7b-assets/` — 결함 7b 크래시 DB·로그·코어 (6.0G)
- `coredump-analysis2/` — 전 코어 bt 텍스트, `repro3/6/9/9b/10/` — 워커 재현 로그·스크립트
- `d*-build_*.log`, `d*-unit_test.log`, `d*-smoke_test.log` — 게이트 로그 전종
- 워크트리: `~/dev/worktrees/wf143-gate`(d9b 체크아웃), `~/dev/worktrees/wf176-baseline`(baseline)

## 8. 다음 세션 착수 순서 (권장)

1. **결함 9 마무리**: 라이브 gdb 판별(§3-9 절차) → 근인 → 수정 → `_08_javasp` 97/97 → PR#246 보강/머지.
2. **결함 10**: 사용자 vd 힌트 축(§3-10) — `select to_char` 컴파일의 lang flag 읽기를 gdb로 찍고,
   -840 잔당 6건(escape 파라미터)도 같은 사이클에서.
3. **sql8 전 스위트** (BUILD 스냅샷·fresh out·`--abort-on-core`) → 목표: NOK ≤ 20 (롱테일 재분류).
4. **결함 7b**: d7b-assets 기반 WAL/flush 규율 감사 — 큰 덩어리, 별도 작업 단위로.
5. medium 재확인은 불필요(975/975 확정), 이후 #143(전 스위트+HA+YCSB)로.
