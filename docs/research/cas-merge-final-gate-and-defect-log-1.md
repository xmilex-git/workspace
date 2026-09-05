# cas-merge 최종 게이트 진행 기록 + CTP 결함 추적 1기 요약 (2026-08-30 ~ 09-02)

## 최종 게이트 티켓 본문·코멘트(원문)

Child of #112
Blocked by: #142

## Task

최종 게이트 — CTP sql/medium(신경로) → 전 스위트 + HA → YCSB C×1·A×1 release 비교 (#122 D4, 맵 게이트).

- YCSB: 하네스 `~/dev/cubrid-perftools-internal/ycsb`, 커넥션 100, 워크로드당 1회, release 빌드 — #125 베이스라인(C 130,686 / A 27,279 ops/s) 대비. #119 파생 판정 항목 포함(XASL_NODE +16B, db_on_server TLS 분기, 접속·세션 수립 경로 비용).
- 셸 CTP 스위트는 이 호스트 실행 금지 — CI로.
- 빌드·서버 기동·질의 실행·데이터 로드는 sonnet 서브에이전트 분업(맵 Notes).

근거: #122, #125


### 2026-08-30T15:34:29Z

**게이트 1차 실행 결과 (2026-08-30~31, 세션 중간 기록 — resolution 아님):**

진입 게이트 green: cas-merge@4a8adf606 fresh optdebug/release 빌드(-Werror 클린), unit 18/18, smoke 6종 전부 PASS (JDBC jar는 cubrid-jdbc 서브모듈 빌드로 설치 — cmake install에 미포함, 게이트 절차에 추가 필요).

CTP 결과 — **게이트 FAIL, blocker 5장 파생:**
- medium: 740/975 OK, 235 NOK → 근본원인 #159(create_table_reuseoid CS-wire 미반영) + #160(잔존 분류)
- sql: 6샤드 OK 11,368 / NOK 1,660, 샤드3은 #164(MERGE 병렬 group-by sort 자기-데드락)로 행→kill 마감(1,248케이스 미실행)
- 코어 933개 → #165(세션 변수 fold assert)·#166(병렬 리커버리 redo crash-loop)

YCSB(release C×1·A×1)는 **미실행 보류** — 크래시 다발 빌드의 성능 측정은 무의미, CTP green 후 재진입 시 실행 (#122 게이트 순서 준수).

전 blocker 해소 → medium/sql 전건 재실행 green → YCSB가 재진입 절차. 아티팩트: 툴링 리포 `.git_ignored_dir/scratch/wf143/` (sql-out4·medium-out4·triage·cores·manifest).


### 2026-09-01T03:27:10Z

**세션 계획 확정 (2026-09-01, 그릴링 3라운드) — 잔여 3레그(셸 CI·HA·YCSB) 실행 규약**

전제: CTP medium/sql 조건은 #169로 완결(medium 975/975, sql 17,455/17,457·코어 0, cas-merge @80491597d). 이번 세션은 잔여 레그를 아래 규약으로 실행한다.

- **D143-1 (레그 순서·병행)**: 셸 CI를 먼저 트리거(외부 비동기)해 두고 HA → YCSB 순으로 로컬 진행. #122 게이트 순서의 취지(크래시 다발 빌드의 성능 측정 방지)는 sql/medium 코어 0으로 이미 충족. 단 **YCSB 측정 시간대는 호스트 단독 실행**(HA 컨테이너와 직렬화 — 성능 잡음 차단).
- **D143-2 (셸 레그 = upstream CI)**: `CUBRID/cubrid:develop` ← `xmilex-git:cas-merge`(@80491597d) **draft PR**, 제목 `[CBRD-00000] Remove CAS: direct driver connection to multithreaded cub_server`(티켓 미발번 — 사용자 지시), 코멘트 `/run shell`로 CircleCI test_shell만 트리거(sql/medium CI는 로컬 완료라 미트리거). 권한 사실: xmilex-git은 upstream write — comment_trigger.yml의 COLLABORATOR 게이트 통과.
- **D143-3 (HA 레그 = 컨테이너 2개 + 코어 2버킷 선행)**: `cubrid-testcases-private` `HA/shell`의 `_22_ha`+`_23_ha_enhancement`를 먼저 완주하고 소요시간을 보고 확장 여부를 재판단(사용자 결정). 토폴로지는 **podman 네트워크 위 컨테이너 2개**(master=CTP 실행, slave=sshd+동일 경로 CUBRID 설치). 근거: `setup_ha_environment`(CTP init_path/make_ha_upper.sh:306)는 SSH 패스워드 인증의 슬레이브(`run_remote_script`)+양 노드 hostname 상호 해석+heartbeat UDP 왕복을 요구 — `ha_node_list`가 노드를 hostname으로 식별하므로 단일 호스트 2노드 불가, rootless podman의 호스트↔컨테이너 UDP/DNS 비대칭으로 호스트-master 안 기각. `HA.properties`는 수동 기입(QA 장비의 DeployHA.java 역할 대체). pkill 위험은 컨테이너에 격리(호스트 셸 금지 완화는 사용자 승인 있었으나 이 설계에선 불사용).
- **D143-4 (HA 드라이버)**: master 컨테이너 안 `ctp.sh shell`(scenario=코어 2버킷) — ctp-parallel 선례와 동일한 CTP 표준 집계(NOK 리포트) 확보.
- **D143-5 (YCSB = #125 프로토콜 축자)**: threads=**100**(=동시 커넥션 100, 베이스라인 실측 기록 확인), recordcount 10M, operationcount 20M, zipfian, maxexecutiontime=1200, **fresh release 빌드**(cas-merge @80491597d — A8 교훈: 증분 트리 -Werror 잠복), 서버 conf 하네스 QA 표준(data_buffer 4G 등), **DIRECT_HANDOFF=ON 단독** C×1·A×1(OFF 레그는 회귀 의심 시에만 추가 — 사용자 결정). DB는 golden `ycsb_g`(SSD, 27G 생존 확인) `copydb` 재사용, 카탈로그 불일치 시 재로드 폴백. 비교 기준: C 130,686 / A 27,279 ops/s + #119 파생 판정 항목.
- **분업**: 빌드·서버 기동·질의 실행·데이터 로드·컨테이너 내 실행은 sonnet 서브에이전트 위임(CUBRID_SSOT 위임 계약 동봉), 리드는 계획·검증.


### 2026-09-01T07:04:06Z

**스코프 분할(사용자 지시 2026-09-01)**: YCSB 레그를 #177로 이관(자족적 핸드오프 — 프로토콜/빌드/판정 기준 포함). 이 티켓 잔여 = 셸 CI(PR 7837, 진행 중) + HA `_22_ha` 통과(진행 중; HA 전 버킷은 맵 TODO로 이연). 진행 기록: 결함 3종(#176 코멘트 — standby thin-csql admission 쌍, copylogdb area-guard 크래시) 발굴·수정, cas-merge 반영(fork PR #251~#254), `just ha-provision`/`just ha-shell` 레시피 상설화.

### 2026-09-01T09:50:39Z

**_22_ha 버킷 클로즈아웃 — 최종 25/28 OK + 정당분류 3건 (d4c9c4f88, fork PR #255 머지·7837 /run shell 트리거)**

런 이력: 3차 22/28 → 4차 24/28 (e6e5d9af5: thin csql `;x` 연결상태 게이트 수정 → bug_4295·bug_xdbms2707 OK) → **5차 25/28** (d4c9c4f88: 서버측 `;database` HA 상태 렌더 수정 → bug_bts_5243 OK, activeCount=16/standbyCount=18 정확 일치). 5개 런 전체 크래시 0·코어 0.

잔여 NOK 3건 — 전건 제품 결함 아님, TC측 폴드 비호환(근거는 #176 기록 참조):
- **bug_4027**: killtran 출력에서 cub_cas 프로세스 5개 기대 — 폴드는 CAS가 서버 스레드라 구조적 0. TC 갱신 필요.
- **bug_3911** (case 12/12): `cubrid service stop` 후 브로커 미재기동 상태에서 `csql db@host` 실행 — 레거시 fat csql은 직결이라 통과, 폴드 thin csql은 브로커 경유라 실패. 복제 자체는 건강(-599/-81=0, -974 아카이브 경계 정상 통과 입증). TC에 `cubrid broker start` 1줄 필요.
- **bug_xdbms2760**: 워크로드 실측 138.4s < TC의 200s 검사창 — thin csql 고속화가 깨뜨린 타이밍 가정(insert.sh 말미 DROP이 검사 전에 실행됨). TC 보정 필요.

산출물: 커밋 e6e5d9af5·d4c9c4f88 (gate 그린: unit 18/18·smoke 14/14·타깃 체크), fork PR xmilex-git/cubrid#255 cas-merge 머지 완료, CUBRID/cubrid#7837에 /run shell 코멘트. 결함별 근인/수정/검증 기록: #176 (e6e5d9af5, d4c9c4f88, 분류 3건).

_23_* 버킷은 사용자 결정대로 보류, YCSB는 #177.

### 2026-09-01T11:10:45Z

**YCSB 레그 완결 (#177 → PASS 제안)**: cas-merge 최종 tip 내용물(d4c9c4f=7117c8a66 트리 동일) fresh release, gate-grade — C **147,013 ops/s (+12.5%)** / A **29,063 ops/s (+6.5%)** vs #125, 에러 0. READ p95/p99 악화(+16~50%)는 진단 완료: A=체크포인트 flush 버스트 1,069회와 포그라운드 100스레드의 pgbuf 래치 경합(기존 기계, 처리량 증가의 2차 효과), C=일반 경합 큐잉 — threads=1 비교에서 신버전이 처리량 +43.1%·p95 -57.6%·p99 -33.9%로 전면 우세라 코드 경로 열화 배제. 상세: #177 통합 보고서(comment 5493029973). 게이트 잔여 = 셸 CI(PR 7837)·HA 레그 판정.

## CTP 결함 추적 1기 — 운용 규약 + 코멘트 41건 원문

Part of #112

## Question

없음 — 이 티켓은 결정이 아니라 **롤링 추적 티켓**이다(사용자 지시 2026-08-31: "이후 CTP를 하면서 나오는 문제들을 여러 티켓으로 만들지 말고 새 티켓 하나로만 추적").

## 운용 규약

- 지금부터 CTP 실행([#169 게이트 재진입](https://github.com/xmilex-git/workspace/issues/169), [#143 최종 게이트](https://github.com/xmilex-git/workspace/issues/143) 포함)에서 발견되는 결함은 **전부 이 티켓의 코멘트로만** 기록한다. 결함별 새 티켓 신설 금지 (#164~#175식 티켓 분산 종료).
- 코멘트 1건 = 결함 1건: 증상(스위트/케이스/시그니처) → 근인 → 수정(PR 링크) → 게이트 재검증 결과. 기존 sql-fix 티켓들의 resolution 코멘트 수준으로.
- 수정 PR·smoke 케이스 신설 등 자산은 코멘트에서 링크로만.
- 종결 조건: CTP 게이트가 clean(잔존 NOK 전부 분류·해소)이 되어 더 추적할 결함이 없을 때. 종결 시 맵 Decisions-so-far에는 이 티켓 한 줄만 올라간다.

### 2026-08-31T10:43:50Z

**[결함 1] method_dispatch er-stack 불균형 assert — SIGABRT (sql _05_plcsql, shard 0)**

- 시그니처: `er_stack_pop()` → `cuberr::context::pop_error_stack` assert (error_context.cpp:288), 경로 `xs_callback_send` → `method_dispatch` (query_method.cpp:252). 동일 스택 코어 2/2.
- 문맥: wf169-sql3 (merged cas-merge @0d652517c, 검증된 바이너리), `_05_plcsql/_01_testspec/_04_expression/_10_relational_op` 진행 중(±925/1250). 코어 3개.
- 용의: A7 후속(PR cubrid#194 dispatch er 격리·#196 D8 콜백 이동)의 er push/pop 짝과 upstream [CBRD-27212] network context 누수 수정(4745fe9e2)의 상호작용 후보. 근인 분석 진행 중.
- 자산: bt = scratch/wf169/coredump-analysis2/shard0_core{1993,2798}.gdb.txt

### 2026-08-31T10:43:51Z

**[결함 2] 서버측 상수 폴딩 중 regexp compile → cublocale::get_locale assert — SIGABRT (sql _36_guava/cbrd_26258, shard 5)**

- 시그니처: `pt_evaluate_function` (컴파일-타임 상수 평가, 서버 문맥) → `db_string_regexp_count/instr` → `cubregex::compile` → `cublocale::get_locale` assert (locale_helper.cpp:57). 동일 계열 코어 2/2 (count와 instr 두 변형).
- 문맥: wf169-sql3, `_36_guava/cbrd_26258/inst_num_orderby_skip.sql` 즈음. 코어 6개.
- 용의: 폴드 갭 — 서버 스레드에서의 regexp 상수 폴딩이 client-side lang/locale 초기화를 전제. 머지 기인이라기보다 sql 스위트가 B-트랙 이후 이 지점까지 완주한 적이 없어 최초 노출일 가능성. 근인 분석 진행 중.
- 자산: bt = scratch/wf169/coredump-analysis2/shard5_core{1993,2482}.gdb.txt

### 2026-08-31T10:43:52Z

**[결함 3] online-index 문맥 btree 스테일 BTID/미예약 섹터 assert — SIGABRT (sql _31_cherry/issue_21506_more_online_index, shard 6)**

- 시그니처 2형: ① `xbtree_delete_index` (btree.c:5970) → `pgbuf_is_valid_page` → `disk_is_sector_reserved` debug_crash assert (disk_manager.c:4274) ② `btree_fix_root_for_insert` → `btree_fix_root_with_info` (btree.c:1898) → 동일 assert — 삭제/삽입 양쪽에서 무효 페이지의 BTID 사용.
- 문맥: wf169-sql3, `_006_using_index` 케이스들(±1855/2307). 코어 12개(재기동 연쇄 포함 추정).
- 용의: #171 계열(DROP 경로 스테일 BTID)의 merged-빌드 변형 × upstream [CBRD-24094] btree/btree_load 대변경(OID-ordered overflow chains)의 상호작용. 근인 분석 진행 중.
- 자산: bt = scratch/wf169/coredump-analysis2/shard6_core{1993,2429}.gdb.txt

### 2026-08-31T10:47:18Z

**[결함 2 근인 확정] 컨테이너 이미지 갭 — 제품 결함 아님**

- 근인: `cubregex::compile` → `cublocale::get_locale`이 `std::locale("ko_KR.utf8")`(utf8_ko_cs 콜레이션)을 생성하는데, ctp-parallel 이미지에 `glibc-langpack-ko` 부재로 생성자 throw → catch의 `assert(false)`(debug 빌드)로 SIGABRT. 검증: 호스트 `locale -a` ko_KR 2건 vs 컨테이너 0건.
- 조치: Containerfile에 `glibc-langpack-ko glibc-langpack-tr` 추가(utf8_tr_cs 대비 포함), 이미지 리빌드 중. 코드 수정 없음.
- 별건 노트(상류, 맵 밖): OS locale 부재라는 환경 입력에 대한 `assert(false)`는 er_set 강등이 더 적절해 보임(#128 D2 기준) — upstream 개선 후보로만 기록.

### 2026-08-31T11:01:17Z

**[결함 1 해소] er_stack_clearall의 dispatch-floor 계약 — PR [cubrid#239](https://github.com/xmilex-git/cubrid/pull/239) 머지 (cas-merge @89fb4a74d)**

- 근인: client-half `tran_commit`/`tran_abort`의 `er_stack_clearall()`이 폴드에선 서버 스레드 er 컨텍스트를 공유 → `method_dispatch`가 push한 격리 프레임(+그 아래 서버 프레임)까지 파괴 → 출구 `er_stack_pop()` 빈 스택 assert. 레거시 CAS의 clearall은 자기 프로세스 스택만 도달 가능했음.
- 수정: 프로세스 경계를 **depth floor**로 번역 — dispatch가 진입 시 자기 격리 프레임 깊이를 `csc->er_dispatch_floor`에 기록(중첩 re-floor/restore), clearall 4곳을 `er_stack_clear_above(floor)`로. 브래킷 밖 floor=0 == 기존 clearall(CS/SA 비트동일).
- 검증: 양 빌드 green · unit 18/18 · smoke 14/14 · fail-first(sql3에서 결정 크래시 3코어) → 수정 빌드 `ctp-sql-isolated _10_relational_op` 코어 0.

### 2026-08-31T11:01:18Z

**[결함 2 해소] 이미지에 glibc-langpack-ko/-tr 추가 — 툴링 리포 커밋, 이미지 리빌드 완료**

- ctp-parallel:local 리빌드 후 컨테이너 `locale -a`: ko_KR 2·tr_TR 2 확인. 수정 빌드+새 이미지의 `ctp-sql-isolated _36_guava/cbrd_26258` 코어 0 — regexp compile SIGABRT 소멸.
- 잔여: cbrd_26258의 orderby_skip 3케이스 NOK는 크래시와 무관한 별건 → 결함 4로 분리 추적.

### 2026-08-31T11:01:19Z

**[결함 4] 플랜 덤프 미출력 — cbrd_26258 orderby_skip 3케이스 NOK (비크래시)**

- 증상: `_36_guava/cbrd_26258/{single,join,inst_num}_orderby_skip` 3건 — answer가 기대하는 Query plan/rewritten query 블록이 result에 통째로 부재(데이터 행은 정상).
- 용의: A2(#131) 때 fog로 기록해둔 `query_Plan_dump_fp` 3종 프로세스-전역 잔존 클래스 — 플랜 덤프 경로가 세션/CAS-등가로 폴드되지 않아 클라이언트에 플랜 텍스트가 도달하지 않는 갭. 근인 분석 예정 (결함 3 귀속 판정 후).
- 자산: ctp-iso 20260831T105810Z-3630077 결과 디렉토리.

### 2026-08-31T11:07:27Z

**[결함 3 귀속 판정] 폴드 기인 확정 — 파티션 DROP 경로**

- 판별 런(`ctp-sql-isolated _31_cherry/issue_21506_more_online_index`, 62케이스):
  - **baseline develop@5ae45603f (순수 upstream)**: 62/62 PASS, core 0
  - **merged cas-merge**: 29 fail, core 13 — 결정 재현
- 결론: upstream CBRD-24094 자체 버그 아님. 폴드의 client-half DROP 경로가 서버 주소공간에서 돌 때의 결함 (stale-binary 런에서 pre-merge 폴드 빌드도 동일 크래시 → 머지 무관 선존 폴드 결함). 대표 스택: `do_drop_partitioned_class(drop_sub=1)` → 서브클래스 `sm_delete_class_mop` → `transfer_disk_structures(flat=NULL)` → `deallocate_index` → `xbtree_delete_index` → 미예약 섹터 페이지 assert.
- 다음: 근인 분석(파티션 로컬 인덱스 BTID의 이중 해제/스테일 캐시 축) — 결함 4 게이트 후 착수. 하네스 노트: justfile `build`는 jdbc jar를 패키징하지 않음 — baseline 설치본엔 `cubrid_jdbc.jar` 수동 복사 필요했음.

### 2026-08-31T11:27:12Z

**[결함 3 근인 확정] online 로더의 btid 스크래치 vs 폴드의 직접 포인터 전달**

- 실측(worker 프로브): 파티션×`WITH ONLINE` 조합만 결정 크래시(2×2 매트릭스). `log_btree_ops` 타임라인 + 코어 포렌식으로 확정 —
  - 로드 시 클래스별 btree: 부모(6721/6720)·p0(6529/6528)·p1(6593/6592)·p2(6657/6656) 각자 정상 로드.
  - 크래시 지점: DROP의 p2 dealloc이 p2 자신의 root(6657)를 fix하다 섹터 미예약 assert — 즉 p2의 btree가 **CREATE INDEX 커밋 시점에 이미 파괴**돼 있었음.
- 근인: 서버 `xbtree_load_online_index`는 입력 btid를 클래스 순회 스크래치로 사용(`btid_int.sys_btid = btid`, 클래스마다 `heap_get_btid_from_index_name`으로 덮어씀). 레거시 CS 와이어는 서버측 언팩 **사본**이 스크래치가 되고 클라이언트는 응답 btid를 버렸으나(`local_btid`), 폴드 분기는 세션 constraint의 `&con->index_btid`를 직접 전달 → 루프 종료 후 부모 in-memory BTID = 마지막 파티션 p2의 BTID. 이어지는 status→NORMAL 템플릿 플러시가 in-memory(오염 6656) vs 속성 유래(진짜 6720) 불일치를 "인덱스 교체"로 보고 **p2의 살아있는 btree를 dealloc** → 커밋 후 섹터 반환 → DROP에서 p2가 자기 btree를 지우려다 assert. 부모 ws가 6720으로 남는 것·크래시가 항상 마지막 파티션인 것 모두 정합.
- 수정: 폴드 분기에서 `BTID local_btid = *btid` 사본 전달(CS 와이어 의미론 축자 번역) — 브랜치 wf176/d3-online-btid-copy, 게이트/재현 검증 진행.
- 부수 노트: CS 분기의 lock-restore 백스톱(`curr_cls_lock != SCH_M → ws_set_lock`)은 폴드에 미이식 상태 — 주경로 아님, 후속 검토로 fog 기록.

### 2026-08-31T11:30:36Z

**[결함 4 근인 2단 확정] 세션 파라미터 lost-write 클래스 — #159의 write-through 반쪽 부재**

- D4a(옵티마이저 플랜 덤프): `set_optimization_level`의 프로세스 `prm_set` → 세션 read-through에 가려 소실. `qo_set_optimization_param` 경유(세션 override 슬롯)로 3사이트(cas_optimization.c·authenticate_grant.cpp·execute_statement.c) 통일 → subset에서 "Query plan:" 블록 0→30개 복구 확인.
- D4b(`set trace on`의 SHOW TRACE 공백): `do_set_query_trace`가 `prm_set_bool/integer_value(QUERY_TRACE*)` — 같은 클래스. **뿌리 수정**: `prm_set_integer_value`/`prm_set_bool_value`에 #159 read-through의 대칭 짝인 **세션 write-through** 추가(session 보유 시 `sprm->value`에 기록, 세션 없는 서버 내부 스레드는 기존 경로). 이 클래스의 미래 사이트까지 포섭.
- 게이트 재실행 중(D3 사본 수정과 합본). green 후 cbrd_26258 3케이스 + P1 재현으로 확증 예정.

### 2026-08-31T11:34:47Z

**[결함 3 해소] PR [cubrid#240](https://github.com/xmilex-git/cubrid/pull/240) 머지 / [결함 4 해소] PR [cubrid#241](https://github.com/xmilex-git/cubrid/pull/241) 머지 — cas-merge @ab927227b**

- 결함 3: 폴드 분기에서 online 로더에 btid 로컬 사본 전달(CS 와이어 의미론 축자 번역). 확증: `issue_21506_more_online_index` **62/62 PASS·core 0** (수정 전 29 fail·13 core).
- 결함 4: 세션 파라미터 write-through(#159 read-through의 대칭 짝) + 레벨 save/restore 3사이트 qo 세터 통일. 확증: `cbrd_26258` **3/3 PASS** (플랜 덤프+SHOW TRACE 복구).
- 게이트: 양 빌드 -Werror green · unit 18/18 · smoke 14/14 (5파일 합본).
- 현재 스코어보드: 결함 1·2·3·4 전부 해소, 미해소 0. 다음: 수정 완비 빌드로 sql 전 스위트 재실행(#169 본판정).

### 2026-08-31T11:46:49Z

**[결함 5] json_table XASL 패킹 debug 왕복검증의 NULL-thread SIGSEGV (sql4 신규, 코어 21→3의 잔여 전부)**

- 증상: 수정 완비 빌드 sql 전 스위트에서 shard 5(_36_guava 후반)·shard 6(_31_cherry json_functions/cbrd_22454) SIGSEGV — 두 코어 동일 시그니처.
- 스택: `do_prepare_select` → `xts_map_xasl_to_stream` → `xts_process(json_table)` → `xts_debug_check<json_table::column>` (xasl_to_stream.c:8024) → `stx_init_xasl_unpack_info(thread_p=NULL)` → `set_xasl_unpack_info_ptr`가 `thread_p->xasl_unpack_info_ptr` NULL deref.
- 근인: debug 빌드 전용 json_table pack/unpack 왕복검증이 pre-fold 클라이언트 관례(NULL thread → 프로세스 전역 슬롯)로 작성됨 — 폴드 서버에선 슬롯이 스레드 소유라 NULL deref. json_table 쓰는 모든 케이스가 prepare에서 즉사(이전 런들은 더 앞의 결함들로 여기 도달 못 했던 onion 표면).
- 수정: 검증 함수가 실제 스레드 엔트리를 쓰고, 스레드 슬롯을 **save/restore**(서버 절반이 자기 unpack을 들고 있을 수 있음 — dispatched 내부 문장). CS/SA는 비트동일(NULL 설정 유지). 브랜치 wf176/d5-xts-debug-thread, 게이트 진행.

### 2026-08-31T11:51:05Z

**[결함 6] SET SYSTEM PARAMETERS 'ansi_quotes=...' 류 -840 거절 — sql4 shard5 완주분 NOK 16 중 9건**

- 증상: `_10_connect_by` 계열 + `_08_javasp/case_19`에서 `set system parameters 'compat_mode=mysql'`/`'ansi_quotes=...'`가 -840(ER_PRM_CANNOT_CHANGE, "Cannot change system parameter \"ansi_quotes=default\"") → 후속 -493 연쇄. 서버 err에 동일 -840 스팸 다수.
- 프레임: `ansi_quotes`=PRM_FOR_CLIENT|**PRM_TEST_CHANGE**(USER_CHANGE 없음) → 변경 허용엔 `test_mode` 참 필요. 발화 지점(검증기 vs generate_new_value의 NOT_FOR_CLIENT 경로 vs 서버측 적용)은 미특정 — call_stack_dump=-840 재현으로 확정 예정. #159 클라이언트-파라미터 클래스 4번째 멤버 추정.
- 부수 분류(shard5 완주 leg의 나머지 NOK): -21003×2는 결함 5 크래시 연쇄(해소 예상), `issue_10938_zone` PUREDIFF×3·`418-4`(-181/-494)는 결함 6/5 해소 후 재분류.

### 2026-08-31T11:54:06Z

**[결함 5 해소] PR [cubrid#242](https://github.com/xmilex-git/cubrid/pull/242) 머지 (cas-merge @$(cd ~/dev/worktrees/wf143-gate && git rev-parse --short HEAD)) — json functions subset 63/63·core 0 확증 (수정 전 전 스위트 shard 2곳 SIGSEGV 셧다운). 스코어보드: 결함 1~5 해소, 결함 6(-840 파라미터) 미해소 1건. 전 스위트 재실행(wf169-sql5)으로 진행.**

### 2026-08-31T12:05:38Z

**[sql5 런 결과] 6/7 shard 완주·코어 0 — 크래셔는 1개 케이스로 고립, 잔여 NOK 223 전수 분류**

- 집계: 15,304 실행 / 15,081 성공 / 223 NOK. shard_1은 3,327/3,327 만점. 크래시는 shard_2 단독(96.4% 지점) — 이하 결함 7.
- **[결함 7] PL/CSQL 루프-내 COMMIT의 pgbuf_unfix_all assert + 리커버리 크래시루프**: `_13_issues/_25_2h/cbrd_26165.sql`(프로시저 안 COMMIT 4시나리오)에서 1차 assert `pgbuf_unfix_all (page_buffer.c:3211)` — dispatched PL 실행 중 트랜잭션 경계에서 스레드 잔존 page fix 검출(가설: 외부 CALL 실행기의 fix를 든 채 in-dispatch commit — D1과 동계열의 경계 규율). 이어 `recovery-redo` 스레드가 29회 반복 크래시 — **#166이 fog로 남긴 판별자 발화**(깨끗한 환경에서 리커버리 크래시루프 재현, 재조사 확정). bt 채집 중.
- 잔여 NOK 223 분류: **-840 클래스 114건**(결함 6 — 최대 가치 수정), **i18n 로케일 오적용 PUREDIFF 103건**(it_IT/zh_CN 기대에 ko 출력 — intl_date_lang 류 세션 파라미터 오착지, 결함 6과 동근 추정 → 결함 6에 병합 추적), -1098×4·기타 2건(결함 6·7 해소 후 재분류).
- 다음 사이클: 결함 6(SET SYSTEM PARAMETERS 폴드 의미론) → 결함 7(PL-COMMIT 경계 + 리커버리).

### 2026-08-31T12:09:55Z

**[결함 7 근인 2단] bt 확보 — 7a 확정·수정 착수 / 7b는 #166 재림 확정**

- **7a (1차 크래시) 확정**: `CALL` 실행 중 PL의 end_transaction 콜백 → `method_dispatch` → `db_commit_transaction` → 폴드 `log_commit_local` → `lock_unlock_all` → `pgbuf_unfix_all`이 **정지 중인 외부 실행기(fetch_peek_dbval_slow 프레임 생존)가 쥔 page fix**를 보고 assert. 레거시는 CAS발 커밋이 별도 요청 스레드라 sweep이 실행기 fix를 본 적 없음. 수정: dispatch 내부(`tm.libcas_depth>0`)에서 sweep 생략 — 클라이언트 절반은 자체 page fix가 없어 등가 번역. 브랜치 wf176/d7a-dispatch-unfix-sweep, 게이트 중.
- **7b (리커버리 크래시루프) = #166 동일 시그니처 재림**: `heap_rv_mvcc_redo_insert` → `spage_insert_for_recovery` → `spage_find_empty_slot_at` assert (**slotted_page.c:1668, slot_id=3** — #166과 자리까지 동일). 깨끗한 새 DB에서 재발 = 매체 불일치가 이 빌드의 정상 동작 중 생성됨 확정 → #166이 이관해둔 WAL/flush 규율 감사가 실무로 승격. 자산 보존: 크래시 DB·서버로그·코어 2종 → scratch/wf169/d7b-assets (6.0GB). 7a 해소로 이번 트리거는 제거되나 7b는 임의 크래시에 잠복 — 별도 사이클로 추적.

### 2026-08-31T12:14:01Z

**[결함 6 근인 확정·수정 착수] SET SYSTEM PARAMETERS의 스코프 검사 폴드 오적용 (-840 클래스)**

- repro 확정: `set system parameters 'ansi_quotes=no'` → -840, 스택 `do_set_sys_params → db_set_system_parameters → sysprm_validate...`. `compat_mode=mysql`(FOR_SERVER 겸용)는 통과 — 판별 정합.
- 근인: `sysprm_generate_new_value(check)`의 스코프 분기가 CS_MODE(클라이언트 규칙)/SERVER_MODE(서버 규칙) 컴파일 분기로 돼 있어, 폴드 client-half의 SET이 **서버 규칙**을 타며 FOR_CLIENT 전용 파라미터(`ansi_quotes` 등 test-mode 파라미터)를 `PRM_ERR_NOT_FOR_SERVER → -840`으로 거절.
- 수정(6a): 브래킷 활성 시 레거시 클라이언트 스코프 규칙 분기 적용(비브래킷 서버 경로는 기존 유지 — 원격 요청 검증 의미 불변). 브랜치 wf176/d6a-setparam-client-scope (D7a와 합본 게이트 예정).
- 6b(intl 오착지)는 워커 재현 환경의 locale 레지스트리 변수(cubrid_locales.txt 부재 시 영어 폴백)와 얽혀 미확정 — 6a 반영 후 i18n subset을 컨테이너(정상 locale 셋업)에서 재실행해 잔여를 판정.

### 2026-08-31T12:34:43Z

**[결함 6·7a 해소] PR [cubrid#243](https://github.com/xmilex-git/cubrid/pull/243)(7a)·[cubrid#244](https://github.com/xmilex-git/cubrid/pull/244)(6) 머지 — cas-merge @37d604a28**

- 7a: in-dispatch commit의 pgbuf_unfix_all sweep 생략(정지 중 외부 실행기 fix 보존). 6: SET SYSTEM PARAMETERS의 검증·적용 양측 브래킷 분기 + 세션 시작 시 ansi_quotes 부트값 복원(3중 구멍: -840 거절 / silent skip / 프로세스 잔존).
- 확증: 3-dir subset(`_25_2h`+connect_by simple+i18n it_IT) **44/44·core 0** (수정 전: 크래시+2 NOK). 게이트 green.
- 스코어보드: 결함 1~7a 해소. 미해소: **7b**(리커버리 크래시루프 = #166 재림, WAL/flush 규율 — 자산 보존, 별도 사이클). 전 스위트 6차 런 진행.

### 2026-08-31T12:39:50Z

**[결함 8] 폴드 pl_call의 미초기화 ret_value — 에러 경로 wild-free mspace abort (sql6 조기 중단 원인)**

- 증상: sql6 런이 `_08_javasp/418-4.sql`(OID 함수, 의도된 -181류 에러 케이스)에서 cub_server abort 1코어 → 워치독 중단. bt: `pl_call`(폴드 분기) → `db_value_clear(&ret_value)` → `pr_clear_value` → `db_private_free`가 코드 주소를 free.
- 근인: 폴드 `pl_call`의 `DB_VALUE ret_value`가 미초기화 — `fetch_args_peek` 실패 경로에서 `execute()`를 건너뛰고 스택 쓰레기값을 clear. sql4에서 418-4가 NOK(-181/-494)로만 보였던 것도 동일 지점의 비결정 발현(쓰레기값이 우연히 무해할 때).
- 수정: `db_make_null(&ret_value)` 1줄 (wf176/d8-plcall-init-retval, 게이트 중).

### 2026-08-31T12:47:06Z

**[결함 8 해소] PR [cubrid#245](https://github.com/xmilex-git/cubrid/pull/245) 머지 (cas-merge @ed284a2e3) — `_08_javasp` 97케이스 core 0 확증.**

**[결함 9] 418-4 기능 NOK — OID 인자 javasp 호출 -181 (#172 fog "418-4 값 정합성" 졸업)**
- answer는 `select * from xoo where xoo = testoid1(xoo)`(OBJECT 인자 Java SP) 성공을 기대, 실측 -181. 크래시 아님·단일 케이스. 전 스위트 7차 런과 병행 분석.

### 2026-08-31T12:55:50Z

**🏁 [sql7 마일스톤] 사상 최초 전 스위트 완주 — 17,457/17,457 실행, 크래시 0·코어 0, NOK 138**

- 7개 shard 전부 rc=0 완주 (shard_1은 3,327 만점). NOK 추이: 1,660(폴드 초기) → 223(sql5) → **138**.
- 138 분류:
  - **i18n/타임존 로케일 값 diff ≈112건** (banana timezone 53 · apricot i18n 43 · 기타): intl/tz 세션 파라미터가 서버-햇 포매팅에 미적용되는 결함군(결함 6b 확장) — 다음 최대 타깃.
  - **-840 잔당 6건**: `require_like_escape_character` 등 ansi_quotes 외 test-change 파라미터 — D6a 부트-복원/검증기 raw-read의 잔여 커버리지.
  - **418-4**(-181/-494): 결함 9 수정(wf176/d9 세션변수 OBJECT→OID 정규화) 게이트 중.
  - -1098×4(euckr tz)·-1042·-1207·-493×2·plcsql 2 등 롱테일 ~19건: 상위 결함군 해소 후 재분류.
- 미해소 잠복: 결함 7b(리커버리, 자산 보존).

### 2026-08-31T13:06:46Z

**[결함 10] i18n/타임존 클러스터 (~112 NOK) — 폴드 기인 확정**

- 판별: 동일 podman 하네스에서 baseline(develop@5ae45603f) `_23_apricot_qa/_03_i18n` **877/877**·`_27_banana_qa/issue_5765_timezone_support` **1759/1759** 만점 vs merged 37/57 실패. 격리 단독으로도 결정 실패(문맥 누출 아님).
- 표본: tz — `Africa/Juba` 기대에 `Africa/Khartoum` 출력(리전 해석 스큐), i18n — it_IT/zh_CN 등 전 로케일에서 요일/월명·숫자서식이 다른 로케일로 출력.
- 용의축: 폴드의 로케일/타임존 모듈 초기화 또는 관련 세션 파라미터(intl_date_lang/timezone)의 적용 경로 — 메커니즘 미확정, 단일 케이스 문장단위 재현으로 좁히기 예정 (결함 9 D9b 게이트 후).

### 2026-08-31T13:21:00Z

**[세션 마감 2026-08-31] 핸드오프: [docs/wf169-session-handoff-20260831.md](https://github.com/xmilex-git/workspace/blob/main/docs/wf169-session-handoff-20260831.md)**

- 최종 스코어: 결함 10건 발굴 / **8건 해소·머지**(PR cubrid#239·240·241·242·243·244·245 + 이미지·하네스) / 2건 좁힘(9: PR#246 부분수정 보류·gdb 판별 절차 명시, 10: merged-전용 intl/tz 회귀·사용자 vd 힌트 기록) / 잠복 1(7b, 자산 보존).
- sql 스위트: **1,660 → 138 NOK, 사상 최초 크래시-프리 전건 완주**(sql7). medium 975/975 확정.
- 다음 세션 착수 순서·자산 경로·재발 방지 수칙은 핸드오프 문서 §5~§8.

### 2026-08-31T13:21:45Z

**[결함 9 근인 확정 — 마감 직후 gdb 판별 도착] TYPE_SP regu의 결과 에지 (세 번째 seam)**

라이브 gdb 채집(worker, repro9b/):
- 발화 지점: `qdata_get_dbval_from_constant_regu_variable`에서 `regu_var_p->type = TYPE_SP`, 값 = **정상 MOP의 DB_TYPE_OBJECT**(data.p 유효 힙 포인터), 목표 = `tp_Oid_domain` → DOMAIN_INCOMPATIBLE → -181.
- 해석: SELECT 내 SP 호출은 TYPE_SP regu → `cubpl::executor::execute()` 직접 실행. 그 내부의 java 결과 언팩은 **client-half 디스패치 구간(hat OFF, bracket ON)** 에서 돌아 `VALUE_IS_CLIENT_HALF()`가 참 → MOP 생성 → 그 값이 그대로 서버-햇 qexec에 복귀. PR#246의 두 정규화(세션변수 저장·method_invoke_group 결과)와 별개의 **세 번째 에지**.
- 수정 방향(다음 세션): TYPE_SP 결과가 서버-햇으로 넘어오는 지점(qdata TYPE_SP 처리 or `executor::execute` 반환 직후)에 qmgr 선례 OBJECT→OID 정규화 — PR#246에 합류시켜 머지.
- 자산: scratch/wf169/repro9b/ (gdb 스크립트·전체 출력·트리거 로그).

### 2026-08-31T14:45:28Z

**[결함 9 해소] TYPE_SP 결과 에지(세 번째 seam) 정규화 — PR [cubrid#246](https://github.com/xmilex-git/cubrid/pull/246) 머지 (cas-merge @228e70015)**

- 근인(마감 직후 gdb 판별의 확정 구현): SELECT 내 SP 호출은 TYPE_SP regu → `cubpl::executor::execute()` 직접 실행, 그 결과 언팩이 client-half 디스패치(bracket ON, hat OFF)에서 돌아 MOP 생성 → 서버-햇 qexec의 OID 도메인 coercion이 -181. 세션변수·method결과에 이은 정규화 클래스의 세 번째 seam.
- 수정: `method_result_to_server_semantics` 헬퍼 공유 승격 + `fetch.c` TYPE_SP fetch의 `executor.execute()` 반환 직후 적용. 다른 executor 호출처는 무변경 — 폴드 `pl_call`은 client-half 소비자(MOP가 정답), 레거시 서버 콜백은 기왕 OID.
- 게이트: optdebug+release green·unit 18/18·smoke 14/14(포트 1700 클레임 격리)·`ctp-sql-isolated _08_javasp` **97/97·core 0** — 418-4 PASS 전환 확증.
- 운용 사고 기록: 게이트/repro 워커가 포트 클레임 없이 병렬 서버를 띄워 한쪽 teardown이 상대 master를 동사시킴(smoke 7 FAIL 소동의 원인, 사용자 발견) — 이후 워커 서버 기동은 `just port-claim` 선행 필수.

### 2026-09-01T01:00:21Z

**[결함 10·11 해소] 세션-유효 플랜캐시 키 + 서버-햇 SET 스코프 — PR [cubrid#247](https://github.com/xmilex-git/cubrid/pull/247) 머지 (cas-merge @53e2a8c92)**

**결함 10 (i18n/tz ~112 NOK) 근인**: `sysprm_print_parameters_for_qry_string`(플랜 캐시 키의 qry-string 성분)이 `prm->value`(프로세스 전역)를 직접 인쇄 — 폴드에서 세션 SET은 세션 스토리지로 가므로 전 세션이 동일 키 → `intl_date_lang`/`timezone`이 다른 세션끼리 캐시 별칭화, 먼저 컴파일된 플랜(요일명이 컴파일 시점 lang flag로 구워짐)이 재사용. 물증: 실패 result의 **한국어 요일명**(서버 부트 lang, LC_ALL passthrough) — "무조건 en_US"라는 종전 기술은 부정확했음. 레거시 CAS는 per-process prm이 곧 세션 유효값이라 정상. CTP만 발현한 이유: 로케일 디렉토리마다 동일 쿼리 텍스트 반복(=충돌 유발 구조); 호스트 4종 프로브(csql/JDBC × utf8/iso88591 × env strip)는 프레시 서버·유니크 텍스트라 전부 통과(판별 자산: scratch/wf169/repro10/). 수정: SERVER_MODE 프린터가 세션 read-through 값 사용.

**결함 11 (group_concat 10건 + 형제 5건) 근인**: `group_concat_max_len`은 FOR_SERVER 전용 → SET이 폴드 `sysprm_change_server_parameters`(enter_server, hat ON)로 서버 apply되는데, D6a 브래킷 분기가 hat을 안 보고 클라이언트 규칙 적용 → `!FOR_CLIENT` silent skip. 수정: 분기 조건 `csc_bracket_is_active() && !db_on_server` — 브래킷=세션 소유·hat=실행 절반(#173 이분법)의 재적용.

**게이트**: 빌드 green·unit 18/18·smoke 14/14; subset `_03_i18n` **877/877**(수정 전 37/57 실패), mysql group_concat 11/11, ext2 group_concat 5/5, banana tz **1758/1759**.

**[결함 12] tz 시퀀스 밀림 — 별건 확정 (미해소)**: `_02_sessiontimezone/_02_alter_session_timezone.sql` 1건, diff `Indian/Mayotte`→`123`(61행) — d10/d11 수정 전후 완전 동일 재현 = 이번 클래스와 무관한 선존 결함. 단일 세션 순차 SET TIME ZONE/`sessiontimezone()` 시퀀스의 결과 한 줄 밀림. sql7 138 NOK 중 1건. 후속 진단 대상.

### 2026-09-01T01:24:41Z

**[결함 13 해소] escape-char 교차 검증기의 세션-유효값 읽기 — PR [cubrid#248](https://github.com/xmilex-git/cubrid/pull/248) 머지 (cas-merge @5ba67a0d0)**

- Root cause: `sysprm_validate_escape_char_parameters`(rlec·no_backslash_escapes 동시 true 금지 규칙)가 상대 파라미터 현재값을 `PRM_GET_BOOL(prm->value)` — 프로세스 raw 값 — 로 읽음. 폴드에서 선행 `SET 'no_backslash_escapes=no'`는 세션 스토리지로 가므로 검증기는 부트 기본(yes)을 보고 합법 조합을 -840으로 거부. **결함 10(플랜캐시 키 프린터)·11(apply 스코프)에 이은 "raw 프로세스 읽기" 클래스 3호**.
- 판별 방법론 기록: 게이트 판별식 입력 3종의 gdb 실측(test_mode=true, rlec USER_CHANGE=0/TEST_CHANGE=1)이 "통과여야 함"을 증명 → CANNOT_CHANGE 생성 사이트 전수 나열로 진범 특정(자산: scratch/wf169/repro10/e_04_gdb.log, run_d13.sh). 부수 사고: 1차 프로브의 서버 SIGABRT는 gdb inferior call(`p prm_get_bool_value(...)`)이 유발한 리드 스크립트 결함 — 제품 무관, gdb 스크립트는 정적 심볼 읽기로 정정.
- 수정: `prm_get_bool_value`(세션 read-through)로 교체, CS/SA 비트동일.
- 게이트: 빌드 green·unit 18/18·smoke 14/14; subset 35/35+388/388+86/86·core 0 — -840 6건(escaping_fixes/like_rewrite/require_like_escape_character_002/_t85_04_keylimit/bug_bts_8197/like_001) 전건 개별 PASS.
- 스코어보드: sql8 잔존 13 → **7** (결함 12 tz 1 + -493×2 + PUREDIFF 4).

### 2026-09-01T01:50:59Z

**[결함 12·14·15·16 해소] 파서 깊이 한도·브래킷 intl 검증·SP 서브쿼리캐시 제외 — PR [cubrid#249](https://github.com/xmilex-git/cubrid/pull/249) 머지 (cas-merge @8cbd6ae75)**

- **결함 14** (-493 페어: bug_bts_12208·_18_between_stress): A8-D5 깊이 가드 한도 1024가 업스트림 스트레스 스위트의 합법 ~5,000-항 AND 체인을 기각. 폴드 컴파일은 드라이버 세션 std::thread(8MB, 레거시 CAS 등가 — gdb bt 실증)라 16384로 상향. subset 크래시 0으로 5K-depth 안전 실증. unit 픽스처 3곳 동반 갱신.
- **결함 15** (bts_8166 _01_to_char: 기대 -839가 0): sysprm_generate_new_value의 intl 값 검증 블록(lang name/collation/timezone)이 #if CS_MODE 전용 → 폴드 무검증. 브래킷에서 레거시 클라이언트 규칙 실행으로 확장.
- **결함 12** (tz 시퀀스 밀림): **결함 15와 동일 root cause 판정 적중** — 거부된 `SET TIME ZONE '123'`이 검증 부재로 세션 문자열을 오염(-204 후 sessiontimezone()=123). d15로 banana tz **1759/1759** 전환(직전 1758) — 별도 수정 0줄.
- **결함 16** (cbrd_25748: SUBQUERY_CACHE 트레이스 줄): 비결정적 SP 서브쿼리의 결과캐시 제외가 #if CS_MODE 전용 → 폴드에서 캐시됨(스테일 결과 위험 + 트레이스 줄). SERVER_MODE 확장 + is_deterministic 필드(비패킹) 선언/세터/기본초기화 동반. 중간 사고: 호출부만 확장한 1차 수정이 컴파일 실패 — 필드 선언 가드 누락(워커 발견), 3파일로 완결.
- 게이트: 빌드 green·unit 18/18·smoke 14/14; subset 77/77·41/41·1/1·877/877(i18n 백스톱)·1759/1759(결함12 판별자), 전부 core 0.
- **스코어보드: sql8 잔존 13 → 2** — plcsql %type 에러 전파(Has been interrupted↔Data overflow), cbrd_25486_05 grant tie 순서. 이 2건 해소 후 sql9 전건 확증.

### 2026-09-01T02:04:54Z

**[결함 17 해소] px sibling-shutdown의 PL 세션 interrupt 철회 — PR [cubrid#250](https://github.com/xmilex-git/cubrid/pull/250) 머지 (cas-merge @80491597d)**

- Root cause: 병렬 쿼리 워커의 실에러(-427 smallint overflow)가 sibling 중단 interrupt를 걸면, root executor의 정리 루프가 tran interrupt는 클리어하지만 그 루프의 매 true 반복이 logtb hook으로 **PL 세션에 재마킹한 interrupt는 아무도 안 걷는다** → 마크가 쿼리를 넘어 생존, 이후 CALL의 모든 get_session()이 ER_INTERRUPTED 보고 → -889 wrap이 "Has been interrupted" 수송. **업스트림 선존(CBRD-25184 기계) — 레거시는 wire가 서버측 er을 가려 미발현, 상류 보고 후보.**
- 판별 방법론: 1차 first-error-wins 가드(session_get_pl_session)는 empirical FAIL — 워커의 결정적 관찰("-427은 px 워커 스레드 er에만, 부모 er은 내내 빈 상태 — 가드 전제 불성립")이 진짜 지점(px 집계 루프)으로 유도. 가드는 심층 방어로 존치.
- 수정: px run_jobs의 ERROR_INTERRUPTED_FROM_WORKER_THREAD 분기에서 루프 직후 `cubpl::get_session()->clear_interrupt()` — sibling-shutdown은 내부 배관이므로 워커 정지 후 철회.
- 확증: 최소 재현이 정확한 -889 wrap("Data overflow on data type smallint") 복구, subset `_09_percent_type` **30/30·core 0** (23_normal_viewtable_percent_type_cursor PASS 전환).
- 부수: 프로브 스크립트가 server만 내리고 cub_master를 안 내리는 정리 갭 발견(포트 1701 스테일 마스터) — environ 소유 확증 후 정리, 이후 스크립트는 service stop 포함 필요.
- **스코어보드: 잔존 1** — cbrd_25486_05 grant tie 순서(결함 18 진단 착수).

### 2026-09-01T02:08:45Z

**[결함 18 중간 판정] cbrd_25486_05 grant tie 순서 — 스위트-문맥 의존 확정, sql9가 판별자**

- 판별 체인: ① 2-leg 최소 재현(merged BUILD-d17 vs baseline, 동일 하네스) — **불재현**: 양 레그 완전 동일(db_auth SELECT→ALTER 정순, grants는 클래스당 비트마스크 1엔트리 {class,4369}로 저장·전개 순서 일치) → GRANT 기록/뷰 전개 시점 결함 아님. ② `grant_revoke_redefine` 디렉토리 격리 subset — **17/17 전건 PASS·core 0** (cbrd_25486_05 포함).
- 결론: sql7/sql8 풀 스위트 문맥에서만 발산(ORDER BY 동률 행의 pre-sort 순서가 스위트 교차 상태에 의존하는 형태 — 클래스별 비일관 역전과 정합). baseline 풀 스위트는 안정 통과했으므로 폴드 기인 요소 잔존 가능성은 열림.
- 처리: #166 선례 — **sql9 재실행이 판별자**. 재발 시 전용 조사(풀 스위트 문맥의 tie 순서 — CTP-shape 플랜 대조), 무재발 시 소멸.

### 2026-09-01T02:38:41Z

**[결함 18 최종 판정] 폴드 무관 — 업스트림/하네스 잠복의 동률 정렬 불안정 (수정 대상 아님)**

판별 실험(shard 4 실행 순서 prefix 4,756케이스를 두 빌드에 동일 재생):
- leg M(merged, 결함 1~17 전부 포함): cbrd_25486_05 flip 재현(순서만으로 100% 재현), cbrd_25596은 단일-shard에선 미재현(원본 7-shard 동시실행의 리소스 경합 변수 관여 추정).
- **leg B(baseline, 순수 upstream develop@5ae45603f): 동일 prefix에서 cbrd_25486_05·cbrd_25596 둘 다, 원본 sql9와 동일한 diff로 flip.**
- 절반 prefix(2,390)는 양쪽 미재현 — 순서 의존 전제 실증.

결론: GRANT 나열 쿼리의 ORDER BY 동률 행 순서가 선행 케이스 이력(힙/슬롯 상태)에 의존하는 **업스트림 선존·하네스 레이아웃 노출** 문제. 업스트림 CI가 통과하는 것은 그들의 실행 순서에서 answer를 녹화했기 때문. cas-merge 폴드와 무관(제품 수정 없음). 값은 양쪽 모두 정확 — 순수 나열 순서 diff.

자산: d18-prefix_dirs.txt·d18-legM-{half,full}.log·d18-legB-full.log, ctp-iso 20260901T02{2347,2729,3220}Z. 상류 보고 후보(#164 CBRD 동승 목록 합류): GRANT 목록 조회의 동률 정렬 비결정성.

#169 게이트 처리(전건 통과 기준에 이 2건을 known-benign으로 인정할지)는 사용자 결정 대기.

### 2026-09-01T03:54:38Z

**wf143 HA 레그 — 폴드 행동 차이 1건 (하네스 수용책 적용, 제품 결함 아님·기록용)**

- 증상: HA shell TC의 슬레이브측 검증 질의 `csql ... hatestdb@haslave`가 'cannot connect to the broker'로 전건 NOK 예정(스모크 fbo_ha_0001에서 확정; heartbeat/copylogdb/applylogdb·복제 자체는 정상, master active·slave standby·1280행 복제 확인).
- 원인: 레거시 csql은 fat client라 `db@host`를 대상 호스트 cub_master(1523)에 직결 — 브로커 불요. B5 폴드에서 csql은 와이어 드라이버가 되어 **원격 db@host는 대상 호스트의 브로커 TCP를 경유**(B5 resolution 명시 사항). QA의 `setup_ha_environment`(CTP shell/init_path/make_ha_upper.sh)는 master에만 `cubrid broker start`를 하므로 폴드 빌드에서 슬레이브측 질의가 접속 불가.
- 수용책: 게이트용 CTP 사본의 setup_ha_environment에 `run_on_slave -c "cubrid broker start"` 1줄 추가(프로덕션 HA는 양 노드 브로커가 표준). 업스트림 기여 시 CTP에 동일 반영 필요 — 상류 보고 후보 목록 합류.
- 부수(환경): ctp-ha 컨테이너에 wget/dos2unix 추가(CTP check_local 요구, TC 실사용 없음).

### 2026-09-01T06:02:30Z

**wf143 HA 레그 — 결함 2건 발굴·수정 (커밋 cubrid 803e79237, fork PR #253 머지)**

_22_ha 1차 런의 NOK 벽(진행 40여 케이스 중 과반 NOK)의 단일 근본원인 쌍:
1. **standby의 원격 thin csql 거절**: 브로커 경유 핸드오프가 ACCESS_MODE(RW)로 DB_CLIENT_TYPE_BROKER를 합성 → #121 D2 admission이 standby에서 거절. 레거시 csql은 fat client로 standby 직결 허용(서버측 RO 강제)이었고 HA TC의 슬레이브 검증 질의가 전부 이 전제. 수정: 핸드오프에서 thin csql의 in-band 마커(db_info URL='thin_csql')를 DB_CLIENT_TYPE_CSQL로 합성 — 레거시 의미론 복원.
2. **thin csql이 거절 응답 파싱 불가**: 서버 send_error_reply는 양수 길이 에러 프레임인데 파서는 음수 길이만 에러로 인식 → 'unexpected connect reply size'. 수정: 36바이트 성공 프레임 외 전부 에러 프레임 디코드.

부수: PR-7837 리포트 지적 2건 동시 해소(css_init status 미전파, accept 할당 예외). 게이트: 증분 빌드 green·unit 18/18·smoke 14/14. HA _22_ha는 신빌드로 재프로비저닝 후 재실행 중. 하네스 레시피 상설화: `just ha-provision <INSTALL>` / `just ha-shell <BUCKET>`.

### 2026-09-01T06:10:23Z

**wf143 HA 레그 — copylogdb 결정적 크래시 근인·수정 (커밋 cubrid c6f7afb81)**

- 증상: _22_ha 런에서 cub_admin copylogdb가 6/6 동일 스택(lockfree_bitmap assert ← area_alloc ← au start ← boot_restart_client)으로 크래시. CTP 자동재기동 탓에 일부 케이스는 OK로 은폐(침묵 크래시) — 워커(ha-smoke)의 ERROR_BACKUP 스윕이 발굴.
- 근인: **A4/#123-D5 area-init 멱등 가드의 CS 수명 결함**. ws/pr/obt/classobj의 `if (X_area != NULL) return;` 가드는 세션 재사용용인데, CS 정상 shutdown 경로는 `*_area_final()`(포인터 리셋)을 부르지 않고 `area_final()`이 전 area를 해제 → 같은 프로세스의 2번째 db_restart(copylogdb sync 재접속 루프)가 dangling 가드에 걸려 해제된 area를 재사용. 업스트림은 가드가 없어 무조건 재생성이라 무해.
- 수정: 가드 4곳을 `#if defined (SERVER_MODE)`로 축소 — CS/SA는 업스트림 동형 복원, 서버는 D5 공유 유지. (set_object의 가드는 업스트림 선존+리셋 짝 있음 — 무관.)
- 워커 트리아지 정정: 1차 런의 'unexpected connect reply size' 12건은 이 크래시가 아니라 별건(직전 코멘트의 standby admission/에러 프레임 쌍, 기수정)이 원인.
- 게이트 확장: copylogdb 더블-부트 무크래시 리프로를 게이트에 추가 지시. 검증 green 후 cas-merge 반영 예정.

### 2026-09-01T08:39:52Z

**wf143 HA 레그 — thin csql 세션커맨드 '미접속' 결함 근인·수정 (커밋 cubrid e6e5d9af5)**

- 증상: _22_ha 3차 런 NOK 군집 — bug_4295/bug_xdbms2707/bug_xdbms2760 등에서 스크립트형 csql(heredoc, `-i file`)의 `;x`가 'A database has not been restarted'로 사망, 후속 검증이 unknown-class NOK로 연쇄. 미니멀 재현: 비대화식 입력의 단독 `;x` (호스트폼/auto-commit 무관). 특이점: `;commit`은 통과, `;x`만 실패.
- 근인: CMD_CHECK_CONNECT 세션커맨드가 레거시 전역 `db_Connect_status`를 게이트하는데(csql_session.c), 이 전역은 레거시 `db_restart`만 설정 — thin wire 연결은 설정하지 않아 NOT_CONNECTED로 남음. `;commit`이 통과한 이유: csql_get_session_cmd_no()의 정확일치 조기 return이 게이트를 우회(`;commit`=완전일치, `;x`=xrun의 접두일치라 게이트 경유) — 동일 근인의 비대칭 증상.
- 수정: csql_wire_connect()/csql_wire_disconnect()가 레거시 db_restart와 동일 계약으로 db_Connect_status를 CONNECTED/NOT_CONNECTED로 유지 (csql_wire.c, +6줄).
- 검증: 게이트 그린(증분빌드·unit 18/18·smoke 14/14·타깃 heredoc `select 1;`+`;x`+`;commit` 통과). _22_ha 4차 런 24/28 (3차 22/28): bug_4295·bug_xdbms2707 OK 전환, 크래시 0, 코어 0.

### 2026-09-01T08:49:37Z

**wf143 HA 레그 — _22_ha 폴드 비호환 TC 2건 판정 (제품 결함 아님·근거 확보)**

**bug_3911 (case 12/12만 NOK)**
- 증상: 슬레이브 `select * from TT` → 'Unknown class dba.tt'. 복제 지연/아카이브 캐치업 아님 — case 9~11이 copylogdb -599=0·-81=0·-974=12회(아카이브 경계 정상 통과)로 복제 건강 상태를 직접 입증.
- 근인: TC가 case 6에서 `cubrid service stop`(브로커 포함 중지) 후 case 7의 `cubrid heartbeat start`만 실행 — 브로커는 재기동되지 않음(전체 트레이스에 `broker start` 부재, teardown에서 'cubrid broker is not running' 확인). case 12의 `csql hatestdb@$masterHostName`은 폴드 thin csql에서 브로커 TCP 경유 → 'cannot connect to the broker'로 CREATE/INSERT가 조용히 실패(TC에 에러 체크 없음) → TT는 마스터에도 생성된 적 없음. 레거시 fat csql은 @host 직결이라 브로커 없이 통과했던 것.
- 판정: 폴드의 @host→브로커 라우팅 설계 차이에 기인한 TC측 결함. TC 수정 1줄(`heartbeat start` 후 `cubrid broker start`) 필요. 근거: .git_ignored_dir/scratch/wf143-final/ha/bug3911_test_local.log (단독 CTP 런, 1388줄 set -x 트레이스).

**bug_xdbms2760**
- 증상: 'Unknown class dba.abc' 마스터·슬레이브 양쪽 — drop 이후 상태.
- 근인: TC의 insert.sh는 말미에 `DROP TABLE abc` 실행. TC는 200초 모니터링 후 count(*) 검사 — 워크로드가 그때까지 진행 중이라고 가정. 폴드 thin csql은 db_restart 오버헤드가 없어 전체 워크로드(60회 csql 배치 + 30회 sleep)를 **실측 138.4초**에 완주 → 검사 시점엔 이미 drop됨. 레거시 fat csql은 60회 재기동 비용으로 200초를 초과해 통과.
- 판정: 클라이언트 고속화가 깨뜨린 TC 타이밍 가정. TC측 보정(워크로드 연장 또는 drop 제거) 필요. 근거: .git_ignored_dir/scratch/wf143-final/ha/repro2760/insert_timing.out.

**bug_4027 (재확인)**: check_status가 `cub_cas` 프로세스 5개를 killtran 출력에서 기대 — 폴드는 CAS 프로세스가 서버 스레드로 흡수되어 구조적으로 0. TC측 갱신 필요, 제품 결함 아님.

### 2026-09-01T09:49:47Z

**wf143 HA 레그 — 서버측 `;database` 렌더 결함 근인·수정 (커밋 cubrid d4c9c4f88)**

- 증상: bug_bts_5243 NOK — 9개 주소폼 × master/slave의 `;data`/`;database` 출력에서 active/standby 카운트가 0/0 (기대 16/18).
- 근인 (2중):
  1. `db_get_database_name()`: 폴드 서버의 세션 컨텍스트 `database_name`은 `db_restart`만 채우는데 wire 세션은 이를 실행하지 않음 → 빈 이름 → `csql_print_database()`가 'NOT CONNECTED' 출력.
  2. `db_get_ha_server_state()`: 비-CS 분기가 `HA_SERVER_STATE_NA` 고정 → 이름을 고쳐도 '[na]' 렌더로 active/standby 문자열 불출력.
- 수정 (src/compat/db_admin.c, +15줄): SERVER_MODE에서 ① 세션 이름이 비면 `boot_db_name()`(서버 자신의 부트 DB명) 폴백, ② `css_ha_server_state()` 직접 조회(cub_server는 server_support.c 구현 링크).
- 검증: 게이트 그린(SA/CS/SERVER 3모드 단일-TU 컴파일 + 증분빌드 + unit 18/18 + smoke 14/14 + 타깃 `;database` 출력 'db@호스트명' 확인). _22_ha 5차 런에서 bug_bts_5243 OK 전환 — **activeCount=16, standbyCount=18 정확 일치** (@127.255.255.255는 lo broadcast라 TCP connect 실패 → 레거시와 동일하게 master 1폼 무출력).

**_22_ha 최종 상태 (5차 런, d4c9c4f88): 25/28 OK + 정당분류 NOK 3 (bug_4027·bug_3911·bug_xdbms2760, 전건 TC측 폴드 비호환·근거 확보), 크래시 0, 코어 0.**

(마지막 4건 = CI test_shell 분석 → cas-merge-ci-test-shell-7837.md)
