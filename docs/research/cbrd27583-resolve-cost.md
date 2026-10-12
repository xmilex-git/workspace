# CBRD-27583 — 실행당 도메인 확정 비용과 바인드 타입 서명별 플랜

JIRA: [CBRD-27583](http://jira.cubrid.org/browse/CBRD-27583) (Refactoring, CBRD-27510 Relates) · 지도: xmilex-git/workspace 이슈(아래 "기록") · 엔진 기준: develop `be683e04c`(PR 8022 머지, 2026-10-11) 대 부모 `a9940d67a` · 워크트리 `~/dev/cubrid-worktree/CBRD-27583`(브랜치 `CBRD-27583`)

리뷰 원문: [r4214388484](https://github.com/CUBRID/cubrid/pull/8022#discussion_r4214388484)(후보 1 서명 재사용) · [r4214520510](https://github.com/CUBRID/cubrid/pull/8022#discussion_r4214520510)(후보 2 계획의 컴파일 이전) · [issuecomment-6052246514](https://github.com/CUBRID/cubrid/pull/8022#issuecomment-6052246514)(후보 3 서명별 플랜). 앞선 조사: `domain-pin-gate-alternatives.md` §3 A(후보 1 의 원형, D-371-01 로 기각됐던 것), ADR 0020 Considered Options B·D.

## 1. 결정 (2026-10-11, 사용자)

| 번호 | 결정 |
|---|---|
| D-27583-01 | 이 세션이 assignee 로서 Acceptance Criteria 전부(측정·후보별 결정·채택분 구현·CTP 전수)를 수행한다. JIRA 쓰기는 건건이 승인 뒤. |
| D-27583-02 | D-371-01(실행 간 결정 재사용 안 함, 2026-09-28)을 다시 연다. 후보 1 은 "이미 기각" 이 아니라 측정으로 판정한다. |
| D-27583-03 | 제약 여섯: (a) 결과·오류가 CBRD-27510 과 같다(CTP sql·medium 전수 동일 판정) (b) 확정 지점은 컴파일(로드 도출 포함)과 실행 전 도메인 확정 둘뿐 (c) 행을 읽는 중에 정하는 자리를 다시 두지 않는다 (d) 실행은 공유 플랜에 쓰지 않는다 — 클론은 `cache_clones_mutex` 로 한 번에 한 실행만 쓰므로 확정 끝에 클론에 적는 서명별 캐시는 공유 플랜 쓰기가 아니나, 클론은 다른 세션의 PX 워커에도 가므로(CBRD-27484) 그 내용은 세션 상태를 담지 않는 서명의 순수 함수여야 한다 (e) regu/arith/pred 노드 코덱(카탈로그 디스크 포맷)은 불변, 질의 XASL 스트림에 섹션을 더하는 것은 허용(클라이언트·서버 lockstep 은 원래 요구) (f) CAS/JDBC 와이어 프로토콜은 바꾸지 않는다. |
| D-27583-04 | 측정 계약: `domain-pin-bench-baseline.md` §6 의 방법(release, `perf stat` 사용자 공간 명령 수, 1회·N회 차, 메인 스레드, 3회 중앙값), 비교 쌍 `be683e04c` 대 `a9940d67a`, 셀은 소형 8셀(pk-1, sel-1, nobind, in-30, pkand-30, and-30, case-30, upd-31). 단계 분해는 `qexec_resolve_domains_internal` 의 고정 순서(init/alloc, 값 공유, 늦은 바인딩, 비교·원소, 상수식, 세션변수, 인덱스 키, 미룬 오류, clear)를 `perf record` 심볼별 명령 수로 나누고, 로드당 `stx_build_domain_plan` 은 따로 센다. 후보별 "없애는 몫" 은 단계를 후보에 대응시켜 계산으로 낸다(후보 1 = 늦은 바인딩·비교 결정·alloc, 후보 2 = 로드당 도출, 후보 3 = 실행당 거의 전부 − 변형 생성). 프로토타입은 채택 후보만. |
| D-27583-05 | 순서: 후보 3 을 먼저 프로토타입한다. 게이트를 통과하면 후보 1·2 는 무의미해진 사유만 적고 닫는다(실행당 타입 결정이 없어지면 후보 1 의 대상이 없고, 가변 POS 가 없어지면 후보 2 의 추론 틈이 부류째 사라진다). 후보 3 이 떨어질 때만 1·2 를 측정으로 판정한다. |
| D-27583-06 | 변형 선택은 클라이언트 라이브러리의 실행 경로(`db_vdb.c`, 바인드 피크 재계획 `do_replan_statement_with_bind_peek` 가 서 있는 자리; 호출처 3곳이 모두 sa·cs 라 CAS·csql·PL 을 덮는다). 문장마다 (서명 → xasl_id) 표를 두고 없으면 그 서명으로 컴파일한다. 서버는 캐시 키가 달라진 것만 본다. "서버가 불일치를 오류로 돌려주고 클라이언트가 재컴파일" 은 왕복 1회가 더 들고 ADR 0020 이 거부한 오류 주도 재컴파일이라 쓰지 않는다. |
| D-27583-07 | 캐시 키 = `sql_hash_text` 뒤에 서명 문자열을 붙인 SHA-1. xcache 구조는 손대지 않는다. 귀결: plandump 의 sha1/SQL_ID 와 결과 캐시 공유를 보는 TC(`cbrd_25035`, `cbrd_20149_*` 등)의 답이 바뀐다 — 티켓 Specification Changes 에 캐시 항목 수·메모리 산정과 함께 적는 사양 변경이다(D-345-04 가 `;host_var_cnt` 접미사를 철회한 사유와 같은 부류를 이번에는 받아들인다). |
| D-27583-08 | 서명의 내용(바인드마다): DB_TYPE; NULL 은 독립 부류; 문자열은 codeset·collation·CHAR/VARCHAR(precision 은 CAS 바인드가 floating(-1, `cas_execute.c:3981`)이라 제외); NUMERIC 은 precision·scale(실행 전 확정이 값의 p/s 를 그대로 기록하므로, `domain_rules.c:1592-1603`); 그 밖은 타입만. 자동 파라미터화된 리터럴도 바인드라 `'1'` 과 `1` 은 다른 변형. **서명은 가변 POS 만 담는다** — 기대 도메인이 있는 자리는 클라이언트가 캐스트하므로 바인드 타입과 무관하게 같은 컴파일이다. |
| D-27583-09 | 컴파일이 바인드 타입을 컴파일 도메인으로 쓴다(develop `pt_make_regu_hostvar` 의 값-타입 단계를 키가 있는 형태로 되살림, D-318-05 번복). 서명으로 컴파일한 문장의 로드 도출은 `DOMAIN_PLAN_LATE_BIND` 항목을 만들지 않는다(optdebug assert; 세션변수는 D-27583-13 으로 서명에 들어가므로 예외 없음). NULL 바인드는 DB_TYPE_NULL 로 컴파일해 파서 규칙이 지금 확정의 "값 없음" 길과 같은 답을 낸다. P0 위험은 "파서 타이핑 ≠ 거울 규칙" 인 모서리이고 CTP 전수와 스펙 변경 탐침 행렬로 잡는다. |
| D-27583-10 | 프로토타입은 PR 8022 의 장치(도메인 계획·확정 도메인 표·거울 규칙)를 지우지 않고 가변 경로가 닿지 않게만 만들어 P0·벤치를 먼저 통과시킨다. 무엇을 지울지는 통과 뒤 결정한다. (Q11 이 받아들여지면 generic 경로로 영구히 남는다 — §2.) |
| D-27583-11 | 서버는 실행 시작에 바인드마다(그리고 읽는 세션변수마다) 값 타입·collation 이 그 POS 의 컴파일 도메인과 같은지 비교하고, 다르면 optdebug assert·release 새 오류 `ER_QPROC_BIND_TYPE_MISMATCH`. -1383 은 "미확정" 이라 재사용하지 않는다. 제대로 된 클라이언트면 나지 않는 길이다. |
| D-27583-12 | 변형 수의 서버 상한은 두지 않는다(변형은 보통 xcache 항목이라 `max_plan_cache_entries` 정리에 맡긴다). 클라이언트의 문장별 표는 최근 8개. (Q11 로 수정 예정 — §2.) |
| D-27583-13 | 세션변수는 세션에서 **처음 SET 될 때의 타입으로 고정**한다(문자열은 codeset·collation 이 같으면 한 타입 — #366 규칙; 숫자는 DB_TYPE 정확히 같아야 함). 다른 타입의 SET 은 -1384 `ER_QPROC_SESSION_VARIABLE_TYPE`(서버 `session_define_variable` 한 곳; SET 은 `fetch.c:4382` 의 산술 `T_DEFINE_VARIABLE` 로 서버에서 실행되므로 SP 가 쓰든 응용이 쓰든 같은 길). `DROP VARIABLE` 이 타입을 지운다. `@var` 를 읽는 문장은 변형 생성 때 클라이언트가 `csession_get_variable` 로 타입을 가져와 서명에 넣는다(왕복은 변형 생성 1회). 정의 안 된 변수 읽기는 지금처럼 `ER_SES_VARIABLE_NOT_FOUND`. 귀결: `SET @a = 1; SET @a = 'x'` 가 오류가 된다(Specification Changes, 매뉴얼 `set.rst`); `SET @n = 1; SET @n = 10000000000` 도 오류. 기능 deprecate 는 별도 제안 이슈로 기록만 한다. |

다른 DB 의 세션변수(결정 13 의 근거): MySQL/MariaDB `@v` 는 동적 타입(CUBRID 의 모델); SQL Server `DECLARE @v INT`·DB2 `CREATE VARIABLE` 은 선언 타입 고정; PostgreSQL·Oracle 은 SQL 세션변수가 없다(각각 `current_setting` 문자열, SQL*Plus 클라이언트 바인드).

게이트(채택 조건): release·optdebug 빌드, optdebug CTP sql·medium 전수를 `be683e04c` 기준선과 비교(차이는 D-27583-07 의 사양 변경분만 허용), 벤치 = D-27583-04 셀 + 서명 교대 셀(같은 문장에 타입을 번갈아 바인드 — 변형 miss 비용) + 변형당 xcache 메모리. GLOSSARY("바인드 타입 서명" _Avoid_ "캐시 키의 일부")·ADR 0020 갱신과 새 ADR 은 게이트 통과 뒤(채택 시점)에 한다.

## 2. 열린 물음 — 변형 폭발 (Q11, 2026-10-11)

PostgreSQL(`~/dev/postgres` 26a3c0a45cc)의 답: 파라미터 타입은 Parse 메시지에서 고정(`postgres.c:1756`; 모르는 자리는 `UNKNOWNOID`→text, `parse_param.c:160`), precision 은 플랜에 싣지 않음(`paramtypmod = -1`, `parse_param.c:118,176`), 플랜 캐시는 백엔드 전용(`saved_plan_list`, `plancache.c:88`)이라 공유 캐시가 터질 대상이 없고 상한은 드라이버의 문장 LRU(pgjdbc 연결당 256개/5MiB), 그리고 custom(값으로 짠 것, 처음 5회, 캐시 안 함)과 generic 두 플랜을 비용으로 고른다(`choose_custom_plan`, `plancache.c:1184-1227`, `plan_cache_mode`).

CUBRID 에서 폭발의 모양: 변형 수 = 해시 텍스트당 서로 다른 (가변 POS 의 서명) 튜플 수. 차원은 타입 부류 × NULL 여부 × NUMERIC precision/scale. NUMERIC p/s 가 가장 나쁘다 — 자동 파라미터화된 리터럴(`price > 10.5` / `> 100.25`)이 p/s 마다 변형을 만든다(PG 는 typmod -1 로 피했지만 CUBRID 의 NUMERIC 산술 결과 도메인은 p/s 를 따른다). NULL 은 가변 POS k 개면 이론상 2^k. 상한 없이 가면 병적인 패턴에서 실행마다 재컴파일(수백 µs~ms)이 되어 지금 줄이려는 비용(실행당 ~10 µs)보다 100배 나쁜 꼬리가 생긴다. 서버 메모리는 `max_plan_cache_entries` 정리가 막지만 thrash 는 못 막는다.

결정(Q11, 사용자 2026-10-11):

| 번호 | 결정 |
|---|---|
| D-27583-14 | **generic 폴백.** 문장 핸들의 변형 표가 N(가설 8)개를 넘으면 그 핸들은 generic 변형 — PR 8022 의 가변 도메인 플랜 + 실행 전 도메인 확정 — 하나를 컴파일해 그 뒤 모든 서명에 쓴다. 시스템 파라미터 `plan_cache_mode` = `auto` / `force_generic`(= 오늘의 PR 8022 동작, 되돌리는 길) / `force_typed`. 게이트는 CTP 전수를 `force_typed` 로 돌려 `force_generic` 기준선과 답이 같아야 한다. N 은 프로토타입이 CTP sql 전수에서 해시 텍스트당 변형 수를 센 자료로 정한다. D-27583-10·12 는 이것으로 고친다: PR 8022 의 장치는 generic 경로로 영구히 남고, 상한은 핸들의 변형 표 N 이다. **단서(사용자):** `force_generic` 이어도 "`qexec_execute_mainblock` 진입 전에 전부 정해진다" 는 구조는 그대로다 — generic 경로가 행 시점 확정을 되살리는 일은 없다. |
| D-27583-15 | **정해 놓고 다시 cast 하는 자리를 이 PR 에서 전부 지운다.** 도메인이 이미 확정된(고정 항목이든 확정 도메인 표든) 값을 행 경로가 `tp_value_cast`·`tp_value_coerce`·`tp_value_auto_cast`·`tp_value_strict_cast` 류로 다시 변환하는 자리는 확정 변환기(`tp_value_convert`) 호출로 바꾸거나 지운다. 첫 단계는 리드의 정적 감사: 실행 경로 파일(`query_executor.c` 9, `fetch.c` 31, `arithmetic.c` 14, `string_opfunc.c` 10, `scan_manager.c` 3, `btree.c` 4, `list_file.c` 3, `query_aggregate.cpp` 5, `query_analytic.cpp` 3, `domain_resolve.c` 6, `domain_rules.c` 7 — rg 호출 수, 2026-10-11)의 호출을 "확정 뒤 재변환 / 확정 밖 문맥(함수 내부 변환 등)" 으로 분류한 표를 §5 에 둔다. |
| D-27583-16 | **NUMERIC 은 항상 precision -1(floating)로 정한다**(PostgreSQL `paramtypmod = -1` 과 같은 자리). 서명·컴파일 도메인·실행 전 확정 어디서도 NUMERIC 바인드의 값 p/s 를 기록하지 않는다 — p/s 는 값이 가지고 다니고 산술 결과 p/s 는 지금처럼 값에서 계산한다. 귀결: 서명에서 p/s 차원이 없어진다(D-27583-08 수정), `domain_rules.c:1592-1603` 의 값 p/s 기록이 없어진다. 구현 사실: `object_domain.c` 는 NUMERIC 에 `TP_FLOATING_PRECISION_VALUE` 를 다루는 자리가 없다(2026-10-11 rg) — NUMERIC floating 도메인을 `tp_domain_find_numeric`·비교·변환기가 받도록 하는 것이 구현 항목이고, 답이 p/s 에 기대던 자리(결과 컬럼 메타, 리스트 파일 컬럼 도메인, SUM 누산기 `DB_DEFAULT_NUMERIC_PRECISION` `domain_rules.c:891`)는 CTP 전수에서 드러나면 사양 물음으로 올린다. |

추가 결정(2026-10-11, 측정 뒤):

| 번호 | 결정 |
|---|---|
| D-27583-17 | **바인드 타입을 쓰는 깊이 = XASL 생성(A).** 타입 변형은 `pt_make_regu_hostvar` 에서 가변 POS 의 사용자 호스트 변수에도 값의 타입을 regu 도메인으로 넣고(자동 파라미터 가지와 같은 길, NUMERIC 은 floating), 파생 노드의 도메인은 로드 도출이 로드당 1회 정한다. 파서 타입 검사부터 다시 하는 (B)는 쓰지 않는다 — 변형마다 전체 재컴파일이 들고 파서 격자와 PR 8022 규칙이 갈리는 모서리에서 P0 가 깨진다. 변형 생성은 기존 바인드 피크 재계획 경로(파싱 없이 XASL 재생성, `do_replan_statement_with_bind_peek`)를 탄다. |
| D-27583-18 | **클라이언트 변형 표 없음(D-06 수정).** 서버 캐시가 변형 표다: 클라이언트 prepare 는 sha1 조회가 먼저이고 XASL 생성은 miss 때만이므로(`execute_statement.c:9955-9995`), 문장에는 "마지막 서명" 과 "본 서명 수(N 판정)" 만 두고 서명이 바뀌면 다시 prepare 한다(캐시 hit = 왕복 1회). 비용은 서명 교대 셀로 재고, 문제면 그때 표를 더한다. |

| D-27583-19 | **NUMERIC floating 의 실체(D-16 확정, Q14 (38, scale) 안 철회, 사용자 2026-10-11).** 엔진에는 이미 float numeric 이 있다: 값이 `data.num.header.{precision,scale}` 에 제 p/s 를 품고 도메인은 `tp_Numeric_domain`(precision `DB_DEFAULT_NUMERIC_PRECISION`, "-1 기본" — `tp_domain_resolve_value` 가 `DB_DEFAULT_PRECISION(-1)` 을 이것으로 맞춘다; 도메인 출력은 p/s 없이 `numeric`)이다(`db_make_numeric` `dbtype_function.i:1651-1657`, `float_numeric_db_value_*`, TO_NUMBER 는 항상 float numeric). 디스크·튜플 포맷은 값마다 `[size|sign][precision][scale]` 헤더를 쓰고 읽기가 헤더의 p/s 를 값에 넣으므로(`mr_data_writeval_numeric`/`readval` `object_primitive.c:8736-8846`) 리스트 파일 컬럼이 float numeric 이어도 scale 을 잃지 않는다 — 앞선 "scale 을 잃는다" 는 제 판단은 틀렸다. 따라서 NUMERIC 바인드·리터럴의 플랜 도메인은 `tp_Numeric_domain`, 서명은 `N`, 값 p/s 는 어디에도 기록하지 않는다. 정렬·GROUP BY·UNION 쪽에서 고정 p/s 를 전제하는 자리(`qfile_unify_types` 의 다른 NUMERIC 도메인 거부, `domain_resolve_list_column` 의 같은 거부)를 float numeric 으로 합치게 바꾼다 — §6 C8. 귀결: 인덱스 키 규칙에서 NUMERIC 바인드는 늘 KEEP(값 비교)이다(오늘은 p/s 가 열과 정확히 같을 때만 INDEX). |

## 3. 측정 (Acceptance Criteria 1)

레인: `.git_ignored_dir/scratch/cbrd27583/measure/`(report.md, perf 자료), 설치 `install-head-release`·`install-base-release`, DB `rev27583`(`databases/`). 결과는 측정이 끝나면 이 절에 표로 적는다.

측정 2026-10-11(Sonnet 워크플로 `wf_a34fd197-b54`, 원자료·명령은 `measure/report.md` §5). 두 설치 모두 release, 캠페인 conf 동일(`diff` 0, `max_plan_cache_entries` ≠ 0), `libcubridsa.so` sha256 head `2f849bba…` / base `657229f3…`. DB `rev27583` t30 10,000행.

### 3.1 실행당 명령 수 (`perf stat instructions:u --no-inherit`, 메인 스레드, 1회·N회 차, 3회 중앙값)

| 셀 | N | BASE `a9940d67a` | HEAD `be683e04c` | 비율 | 차 | 3회 폭(≤) |
|---|---:|---:|---:|---:|---:|---:|
| pk-1 | 20000 | 429,648 | 431,717 | 1.005 | +2,069 | 90 |
| sel-1 | 20000 | 72,679 | 73,791 | 1.015 | +1,113 | 30 |
| nobind(plain) | 20000 | 385,178 | 386,380 | 1.003 | +1,202 | 170 |
| nobind(prepared) | 20000 | 100,605 | 102,092 | 1.015 | +1,486 | — |
| in-30 | 20000 | 1,593,298 | 1,616,983 | 1.015 | +23,685 | 320 |
| pkand-30 | 20000 | 4,445,734 | 4,466,929 | 1.005 | +21,194 | 700 |
| and-30 | 2000 | 32,501,025 | 31,652,030 | 0.974 | −848,996 | 650 |
| case-30 | 20000 | 779,125 | 816,027 | 1.047 | +36,902 | 1,100 |
| upd-31 | 2000 | 2,804,840 | 2,817,417 | 1.004 | +12,577 | 440 |

차는 #345 §6.2 를 재현한다(and-30 −849k 대 −838k, upd-31 +12.6k 대 +12.7k, pkand-30 +21.2k 대 +21.6k; pk-1 −22%, in-30 −17%, case-30 +13% 안). **BASE 절대값은 #345 의 develop `e1c3db198` 과 다르다**(sel-1 +22%, in-30 +33%, case-30 −24%; `nobind` 는 이 파일이 prepare 없는 평문이라 4.5배 — prepared 변형이 #345 의 셀이다). conf(parallelism·stored_procedure)로는 설명되지 않았고, 두 develop 사이 33 커밋(#7866 튜플 포맷, #8109 등)의 이동으로 보이나 `e1c3db198` 을 다시 빌드해 확인하지는 않았다. 판정은 비율·차로 하므로 영향 없음.

### 3.2 단계 분해 (HEAD, 실행당 명령 수, gdb `stepi` 정확 계수 — 포함(inclusive), 단계끼리 겹침)

perf 표본은 이 결정적 루프에서 주기와 공진해(upd-31 두 반복 14,351 대 2,631, 정확값 5,963) 쓰지 않았다. 표본 교차 검사(`report.md` §4.3)는 큰 값에서 정확 계수와 일치한다. 인라인된 단계(`_internal`·init·late_bind·session·index_keys·deferred)는 DWARF 인라인 프레임으로 셌다.

| 단계 | pk-1 | sel-1 | nobind | in-30 | pkand-30 | and-30 | case-30 | upd-31 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `qexec_resolve_domains` 전체 | 1,695 | 612 | 1,589 | 24,887 | 18,266 | 17,884 | 80,709 | 5,963 |
| ├ `qexec_init_resolved_domains`(블록 할당 포함) | 401 | 351 | 348 | 785 | 815 | 825 | 1,258 | 589 |
| ├ `qexec_share_value`(값 공유) | 74 | 37 | 74 | 2,220 | 2,276 | 2,280 | 3,584 | 1,214 |
| ├ `qexec_resolve_late_bind_node`(늦은 바인딩) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| ├ `qexec_resolve_compare`(확정 비교) | 370 | 0 | 370 | 11,100 | 11,702 | 11,745 | 13,450 | 370 |
| ├ `qexec_resolve_comparisons_before_constant` | 0 | 0 | 0 | 0 | 0 | 0 | 15,002 | 0 |
| ├ `qexec_evaluate_constant_expression`(상수식) | 0 | 0 | 0 | 0 | 0 | 0 | 52,455 | 0 |
| ├ `qexec_resolve_session_variables` | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| ├ `qexec_resolve_index_keys`(인덱스 키) | 349 | 0 | 349 | 5,587 | 349 | 0 | 349 | 349 |
| └ `qexec_raise_deferred_errors` | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 |
| `qexec_clear_resolved_domains` | 316 | 172 | 316 | 1,824 | 1,476 | 1,352 | 9,336 | 916 |
| **확정 + clear** | **2,011** | **784** | **1,905** | **26,711** | **19,742** | **19,236** | **90,045** | **6,879** |
| HEAD 실행당 대비 | 0.47% | 1.06% | 0.49% | 1.65% | 0.44% | 0.06% | 11.0% | 0.24% |
| 측정 차 − (확정 + clear) | +58 | +329 | −703 | −3,026 | +1,452 | −868,232 | −53,143 | +5,698 |

읽기:
- 여덟 셀 어디에도 늦은 바인딩 노드·ALL/SOME 원소·PX 복사가 없다. 실행당 비용은 **확정 비교**(비교 자리 30개 × ~370–450: in-30·pkand-30·and-30 11–12k, case-30 13k+15k), **인덱스 키**(in-30 의 키 상수 30개 5.6k), **값 공유**(바인드 30개 2.2–3.6k), **블록 할당·초기화**(0.3–1.3k), **clear**(0.2–9.3k) 로 이뤄진다.
- `nobind`(가변 POS 0개)도 1,905 를 쓴다 — 고정 비교 1개 370 + 키 상수 349 + 블록 348 + clear 316 + 그 밖. **고정 자리의 확정도 실행마다 한다**는 뜻이다: 자동 파라미터 리터럴 `id = 5` 의 비교를 로드가 아니라 실행 전 확정이 결정한다.
- case-30 의 52.5k(상수식 `concat(?, '')` 30개 평가)는 develop 이 행에서 하던 일을 옮긴 것이라 순증이 아니다(측정 차 +36.9k < 확정+clear 90.0k). 순증은 비교 결정 28k + 값 공유·블록·clear.
- in-30 의 `qexec_resolve_domains_internal` self 4,742, case-30 7,853 — 항목 순회 자체의 몫.
- 로드당 `stx_build_domain_plan`(gdb, 로드 1회): pk-1 24k, sel-1 4k, nobind 25k, in-30 162k, pkand-30 166k, and-30 129k, case-30 375k, upd-31 122k. 20,000회 실행에 로드 1회(클론 재사용, 교체 없음)라 실행당 0.
- upd-31 은 차 +12.6k 중 5.7k 가 확정·clear 밖이고 위치를 찾지 못했다(보류).

### 3.3 후보별로 없애는 몫 (단계 대응, 계산)

| 몫(실행당) | pk-1 | in-30 | case-30 | 후보 1 서명 재사용 | 후보 2 계획의 컴파일 이전 | 후보 3 서명별 플랜(Q12 A) |
|---|---:|---:|---:|---|---|---|
| 확정 비교·키 규칙 결정 | 719 | 16.7k | 28.5k | 없앤다(같은 서명 재실행) | 그대로(실행마다) | 없앤다 — 단 고정 비교·고정 키도 **로드가** 정하게 옮겨야 한다(nobind 가 보여 준 몫) |
| 블록 할당·초기화·clear | 717 | 2.6k | 10.6k | 블록 재사용으로 대부분 없앤다 | 그대로 | 변환할 값이 없으면 블록이 필요 없다 → 없앤다 |
| 값 공유 | 74 | 2.2k | 3.6k | 그대로(값 의존) | 그대로 | 입력 배열을 그대로 읽으면 없앤다(ADR 0021 의 소유 모형은 변환값에만 필요) |
| 상수식 평가 | 0 | 0 | 52.5k | 그대로(값 의존; develop 도 행에서 했음) | 그대로 | 그대로 |
| 키 상수 변환 | ~349 | ~2.5k | ~349 | 그대로 | 그대로 | 타입이 열과 같으면 KEEP 이라 대부분 0 |
| 항목 순회 self | ~150 | 4.7k | 7.9k | 줄어든다(항목이 결정 없이 읽기만) | 그대로 | 가변 항목이 없으면 순회할 목록이 없다 |
| 로드당 도출 | 24k/로드 | 162k/로드 | 375k/로드 | 그대로 | 로드당 0(펼치기만) | 가변 항목이 없어 줄지만 남는다(고정 항목·변환기) |
| **남는 실행당 비용(추정)** | 2.0k | 26.7k | 90.0k | ~0.5k / ~5k / ~57k | 2.0k / 26.7k / 90.0k | ~0.4k / ~3k / ~53k(상수식) |

후보 2 는 실행당 비용을 하나도 줄이지 않는다 — 그 가치는 추론 틈·PX 정렬·캐시 산정이고, 후보 3 이 가변 POS 를 없애면 추론 틈이 부류째 사라져 남는 가치가 캐시 산정(#385)뿐이다. 후보 1 과 후보 3 은 같은 몫을 없애지만 후보 1 은 클론에 실행 간 상태를 두고 값 공유·블록을 남기며, 후보 3 은 결정 자체를 로드로 올린다. 세 후보가 모두 못 없애는 것은 상수식 평가(develop 과 같은 일)뿐이다.

## 4. 기록

- 지도 이슈: xmilex-git/workspace#429
- 앞선 측정: #377(`23a5e5561`, resolve+clear = pk-1 1.5k, in-30 25.8k, case-30 87.3k 중 51k 는 행에서 옮겨온 상수식 평가, clear 13k, 비교 11.8k), #345 §6.2(소형 8셀 비율 0.974~1.032), §6.4(플랜 메모리 +9~83%).

### 3.4 프로토타입 벤치 (`wf_4f1c52bb-3ba`, 2026-10-12; H = develop be683e04c release, G = `90d409ca3` force_generic, T = 같은 빌드 force_typed; 실행당 명령 수, 3회 중앙값, csql `-S` 의 PREPARE/EXECUTE 경로)

| 셀 | N | T 가 타입 변형 실행(gdb) | H | G | T | G−H | T−H | T−G |
|---|---:|:---:|---:|---:|---:|---:|---:|---:|
| pk-1 | 20000 | 예 | 431,674 | 432,721 | 450,024 | +1,047 | +18,350 | +17,303 |
| sel-1 | 20000 | 아니오(cannot_prepare) | 73,798 | 73,740 | 73,764 | −59 | −34 | +25 |
| nobind | 20000 | 아니오 | 386,431 | 387,098 | 387,119 | +667 | +689 | +22 |
| in-30 | 20000 | 예 | 1,616,436 | 1,618,641 | 1,734,172 | +2,205 | +117,736 | +115,531 |
| pkand-30 | 20000 | 예 | 4,466,740 | 4,469,100 | 4,330,033 | +2,360 | −136,707 | −139,067 |
| and-30 | 2000 | 예 | 31,651,908 | 31,653,579 | 31,330,179 | +1,671 | −321,729 | −323,400 |
| case-30 | 20000 | 아니오(cannot_prepare) | 815,121 | 816,975 | 817,730 | +1,854 | +2,609 | +755 |
| upd-31 | 2000 | 예 | 2,816,874 | 2,816,712 | 2,920,790 | −161 | +103,916 | +104,077 |
| same-pk | 20000 | 예 | 431,769 | 432,855 | 450,057 | +1,086 | +18,289 | +17,202 |
| alt-pk | 20000 | 예(플랜 2) | 442,567 | 444,072 | 461,093 | +1,506 | +18,526 | +17,020 |
| alt-in3 | 20000 | 예(플랜 3) | 20,578,617 | 20,578,838 | 19,833,223 | +221 | −745,394 | −745,614 |
| same-expr | 20000 | 아니오(cannot_prepare) | 105,113 | 105,352 | 105,357 | +239 | +244 | +5 |
| alt-expr | 20000 | 아니오(cannot_prepare) | 109,116 | 109,197 | 109,262 | +81 | +146 | +65 |

읽기: (1) **G = develop**(−161 ~ +2,360, ≤0.34%). (2) 타입 변형이 도는 셀에서 비교·키가 많을수록 큰 절감(and-30 −323k, alt-in3 −746k, pkand-30 −139k). (3) pk-1/same-pk/alt-pk 의 T−G ≈ +17k 는 csql SQL-level EXECUTE 경로가 실행마다 unbound 컴파일(해시 텍스트 1회) 뒤 타입 변형 재-prepare 로 해시 텍스트를 **한 번 더** 계산하기 때문(SHA1 ≈ +15k); JDBC/CCI 는 문장 노드가 유지되어 서명 strcmp 만 든다 — kept tree 경로(통계 수집 뒤)로 다시 잰다. 서명 교대 자체(alt-pk − same-pk ≈ +11k)는 세 설정이 같아 비용 0. (4) in-30 +116k·upd-31 +104k 는 원인 미상 → 진단. (5) `select ?+…`·`case ?…` 류는 `cannot_prepare`(타입 애매 출력)라 캐시 자체를 안 쓰므로 타입 변형 대상이 아니다(develop 과 같음).

### 3.5 벤치 진단 (`wf_2b3bedb6-e89`)

- **통계가 있으면 csql EXECUTE 의 T 가 실행마다 재컴파일·재생성**: `update statistics on t30` 뒤 pk-1 H 105,829 / G 105,966 / **T 789,940**, pkand-30 T 17.9M(63×). 원인: EXECUTE 노드는 저장된 PREPARE 플랜의 헤더 플래그(`HV_PRED_PLAN_UNPEEKED`)로 재컴파일을 결정하는데, G 는 첫 실행의 히스토그램 재계획이 일반 키 엔트리를 **교체**해(recompile=1) 이후 실행이 저장 XASL 빠른 경로(컴파일 0회, 106k)를 타고, T 는 타입 변형을 타입 키에 저장하므로 일반 키 엔트리의 플래그가 그대로 남아 매 실행 compile-first → 타입 재-prepare → (`hv_pred_plan_unpeeked` 가 statement 에 sticky 라) 히스토그램 재계획(recompile=1, XASL 재생성)까지 돈다. 통계 전에는 `histogram_bind_fingerprint` 가 실패해 재계획이 안 떠 T−G ≈ +17k(해시 2회)에 그쳤다. csql 은 kept tree 를 쓰지 않는다(문장마다 세션이 끝나 트리가 해제됨).
- in-30 +115k(통계 전) = 두 번째 해시 텍스트 SHA1 +65k + `pt_bind_type_signature` 의 printf 군 +59k(실행당 3회 × 30 토큰); XASL 재생성 없음. upd-31 +104k = printf 군 +97k(4회 × 31 토큰). 통계 뒤 upd-31 은 G·T 모두 실행마다 재생성(+1.48M, develop 과 같음 — UPDATE 는 EXECUTE 마다 bind-first 재컴파일).
- 수정(C5 게이트에 포함): (1) PREPARE 정보에 플랜 키 텍스트를 넣고 EXECUTE 가 서명으로 타입 변형을 `prepare_query` 1회로 바로 찾는다(`do_find_typed_plan`; 찾으면 저장 XASL 빠른 경로, 못 찾으면 기존 재컴파일 경로가 만든다); (2) `do_prepare_statement` 가 `hv_pred_plan_unpeeked` 를 매번 초기화해 타입 변형이 일반 플랜의 표시를 물려받지 않는다; (3) 서명 토큰을 snprintf 없이 만든다. JDBC/CCI 는 문장 노드가 유지되어 (1) 과 무관하고 (2)·(3) 의 이득만 본다.

## 5. 감사 — 확정 뒤 다시 cast 하는 자리 (D-27583-15, `be683e04c`, 2026-10-11 리드 정적 감사)

rg 패턴 `tp_value_cast|tp_value_cast_preserve_domain|tp_value_coerce|tp_value_coerce_strict|tp_value_auto_cast|tp_value_strict_cast|tp_value_cast_force|tp_value_cast_no_domain_select|tp_value_change_coll_and_codeset` 을 실행 경로 파일 12개에 걸어 96곳(주석 12곳 포함). 원자료 `.git_ignored_dir/scratch/cbrd27583/audit/casts-fn.txt`.

부류: **R1** 실행기 수준 재변환 — 도메인이 이미 정해진(고정 항목·확정 도메인 표·고정 내장 도메인) 자리에서 행마다 또는 실행마다 범용 cast 를 부른다 → 확정 변환기(`tp_value_convert`/항목의 `conv`) 호출로 바꾸거나, 실행당 상수면 실행 전 확정이 1회 변환한다. **R2** 함수 내부 피연산자 변환 — 피연산자 타입이 확정됐는데 함수 본문이 자기 타입 판정으로 다시 변환한다 → 피연산자 변환기를 계획해 변환된 값을 넘긴다. **G** 확정 자체(실행 전 확정 코드) — 남는다. **D** optdebug 교차 검사 — 지운다(release 에 없고, 변환기가 유일 경로가 되면 검사 대상이 없다). **O** 도메인 확정 밖(형식 문자열·저장 계층) — 남는다.

| 자리 | 함수 | 부류 | 무엇 / 고치는 길 |
|---|---|---|---|
| fetch.c:3581, 3613, 3759, 3782, 3791, 3823, 4332 | `fetch_peek_arith` | R1 | `tp_value_auto_cast(…, domain)` — `domain` 은 항목이 준 노드 도메인. 행마다 범용 대입 변환 → 항목의 피연산자 변환기. |
| fetch.c:4239, 4281, 4315 | `fetch_peek_arith` (NULLIF·공통값 `target_domain`) | R1 | 확정 도메인 표가 준 `target_domain` 으로 `tp_value_cast` → 변환기. |
| fetch.c:2218, 2234, 2268, 2285 | `fetch_peek_arith` (OCTET/BIT_LENGTH: BLOB→VarBit/Char) | R1 | 목표가 내장 고정 도메인, 피연산자 타입은 확정됨 → 변환기를 계획. |
| fetch.c:3301, 3330, 3363, 3397 | `fetch_peek_arith` (TO_DATE 류: 비문자→Char) | R1 | 같음. |
| fetch.c:3947, 3992 | `fetch_peek_arith` (LEFT/RIGHT 길이→INTEGER) | R1 | 같음. |
| fetch.c:2485, 2510, 2535, 2571, 2596, 2621, 2646 | `fetch_peek_arith` (TRIM/LPAD/RPAD 등 `INFER_COLLATION`: `tp_value_change_coll_and_codeset`) | R1 | collation 늦은 바인딩 노드가 실행 전에 collation 을 정했는데 행이 다시 바꾼다 → 확정 collation 변환기. |
| fetch.c:672 | `fetch_session_read_value` (CHAR→VARCHAR 최대 precision) | R1 | 세션변수 문장 타입 확정 뒤 재변환. D-27583-13(처음 SET 타입 고정)이면 자리 자체가 없어진다. |
| fetch.c:954 | `fetch_cast_operand` 의 폴백 `tp_value_cast(_force)` | R1 | 확정 변환기가 없을 때의 범용 cast. D-27583-09 로 모든 피연산자가 타입을 가지면 도달 불가 → assert. |
| fetch.c:6016 · scan_manager.c:1383 | `fetch_and_coerce_key_limit_lower` · `scan_fetch_and_coerce_key_limit_upper` (키 리밋→BIGINT) | R1 | 실행당 상수 → 실행 전 확정이 1회 변환(인덱스 키 상수와 같은 자리). |
| query_executor.c:3912 · 26880 | `qexec_fill_sort_limit` · `qexec_setup_topn_proc` (LIMIT/상한→INTEGER) | R1 | 실행당 상수 → 실행 전 확정 1회. |
| query_executor.c:23142, 23179, 23268 | `qexec_analytic_evaluate_offset_function` (LEAD/LAG offset→INTEGER/DOUBLE, default→노드 도메인) | R1 | 23268 은 `qexec_get_node_domain` 으로 도메인을 읽고서 `tp_value_coerce` — 전형. 셋 다 변환기. |
| query_executor.c:13056 · 13595 | `qexec_generate_row_default_expr` · `qexec_execute_insert` (기본값→속성 도메인) | R1 | 속성 도메인 고정, 기본값 식 타입은 컴파일이 안다 → 변환기 계획(삽입당 1회). |
| query_aggregate.cpp:658 | `qdata_aggregate_value_to_accumulator` (STDDEV/VARIANCE 행값→DOUBLE) | R1 | 행마다 `tp_value_coerce` → 누산기 피연산자 변환기(같은 함수의 SUM/AVG 가지는 이미 `operand_coercion` 을 쓴다). |
| query_aggregate.cpp:1359 | `qdata_evaluate_aggregate_list` (MEDIAN/PERCENTILE 행값→`agg_domain` 기본) | R1 | 행마다 → 변환기. |
| query_aggregate.cpp:2043 | `qdata_finalize_aggregate_list` (정렬 뒤 VARIANCE/STDDEV 행값) | R1 | 행마다 → 변환기. |
| query_aggregate.cpp:2251, 2330 · query_analytic.cpp:1059, 1128 | `qdata_finalize_*` (AVG·VARIANCE 결과→DOUBLE) | R1 | 그룹·파티션당 1회지만 도메인은 고정 → 변환기(작은 몫). |
| query_analytic.cpp:300 | `qdata_evaluate_analytic_func` (NTILE 버킷 수→DOUBLE) | R1 | 윈도우 상수 → 실행 전 확정 1회 또는 변환기. |
| list_file.c:7250, 7257 | `qfile_compare_with_interpolation_domain` (`subkey->cmp_dom` 으로 두 값 cast) | R1 | 비교마다 두 번 cast. 리스트 파일 쓰기에서 1회 변환하거나 비교 leaf 가 변환기 사용. |
| scan_manager.c:2453 → btree.c:19451-19463 | `scan_dbvals_to_midxkey` → `btree_coerce_key` (`tp_more_general_type` 판정 뒤 `tp_value_coerce`/`_strict`) | R1 | 인덱스 키 계획(`DOMAIN_KEY_RULE`)이 열마다 규칙을 정했는데 range open 이 다시 타입 판정 → 키 계획의 변환기. |
| arithmetic.c:2399, 2447 · 3414, 3473 · 4311 · 4736-4931 | `db_round_dbval` · `db_trunc_dbval` · `db_bit_count_dbval` · `db_width_bucket` | R2 | 함수 본문이 인자 타입을 보고 DOUBLE/NUMERIC/INTEGER 로 변환. 피연산자 변환기를 계획해 변환된 값을 넘긴다. |
| string_opfunc.c:10783, 10791 · 21828, 21833, 21861 | `db_unix_timestamp` · `get_date_time_info` (문자열→DATETIMETZ→DATETIME→TIME 캐스케이드) | R2 | 값 타입 캐스케이드 = 행 시점 판정. 피연산자 타입이 확정되면 목표 하나로 계획. |
| string_opfunc.c:11961 · 26379, 26421 · 26778 | `db_time_format` · `db_hex` · `db_ascii` | R2 | 같음. |
| string_opfunc.c:27321 · object_domain_convert.cpp:7362 | `db_value_to_enumeration_value` · `domain_enumeration_name_converter` | O | ENUM 변환기 구현 내부(이름→원소). 변환기 자체다. |
| btree.c:2124 | `btree_store_overflow_key` (리프 키 도메인과 다른 문자열 타입) | O | 저장 계층의 키 정규화(힙 속성 값 → 키 타입). 플랜 도메인이 아니다. 실제 도달 여부는 구현 때 assert 로 확인. |
| query_executor.c:25304, 25339 | `qexec_schema_get_type_desc` (정수→문자열) | O | 형식 문자열 생성. |
| domain_resolve.c:715, 718 · 1210 | `qexec_resolve_elt_branch` · `qexec_convert_list_bind` | G | 실행 전 확정 안의 1회 변환. 남는다. |
| scan_manager.c:2079-2086 · domain_resolve.c:2067-2074 · list_file.c:7155, 7218, 7244-7245 | `scan_check_key_strict` · `qexec_check_key_strict` · `qfile_check_interpolation_type` | D | optdebug 교차 검사(`tp_value_coerce_strict`·첫 값 캐스케이드와 같은지). 변환기가 유일 경로가 되면 비교 대상이 없다 → 지운다. |
| domain_rules.c:505, 741, 975, 1329, 1347, 1725, 2515 · domain_resolve.c:4204 · fetch.c:929 · btree.c:19451 | — | 주석 | 호출 아님. |

집계: R1 47곳(함수 20개), R2 24곳(함수 9개), G 3, D 7, O 5, 주석 10.

C7 구현 뒤 갱신(2026-10-12): R1 의 fetch.c 자리 전부·집계·분석·보간·SYS_CONNECT_BY_PATH·LEAD/LAG offset/default 는 변환기 경로로 바뀌었고(1~3차 커밋), TRIM 류 7곳은 플래그가 설정되지 않는 죽은 코드라 삭제, `btree_coerce_key` 단일 컬럼 가지는 도달 불가라 삭제. 재분류: 키 리밋 2·LIMIT/상한 2·NTILE 1·INSERT 기본값 2 는 플랜이 정해 둔 도메인을 다시 캐스트하는 것이 아니라 소비자(스캔·정렬·생성기)가 상수를 한 번 변환하는 첫 변환 → G. fetch.c:672 는 D-13 의 남은 부분(타입 변형의 `@var`)으로 이월. D 는 교차 검사 3 함수 삭제로 끝났고, `fetch_cast_value` 의 폴백은 "같은 타입의 정밀도·collation 조정" 과 "변환기가 없는 쌍의 오류 보고" 를 위해 cast 로 남는다(항목이 없는 노드는 미확정 오류). R2 는 함수가 값의 내용(문자열의 날짜/숫자 판정, ROUND 의 'default')으로 목표를 고르는 캐스케이드라 "정해 놓고 다시 캐스트" 가 아니며, 규칙표로 옮기면 함수별 사양을 다시 쓰는 일 → 사용자 결정 항목. R1 가운데 "실행당 상수를 실행 전 확정이 1회 변환" 으로 끝나는 것은 키 리밋 2·LIMIT/상한 2·NTILE 1·LEAD/LAG offset 2 이고, 나머지는 항목의 변환기 호출로 바뀐다. 구현 순서는 프로토타입(후보 3) 뒤 같은 브랜치에서 R1 → D → R2.

## 6. 프로토타입 구현 계획 (후보 3, 브랜치 `CBRD-27583`)

커밋 단위(각각 빌드 통과; M 표시가 CTP 게이트):

| 커밋 | 내용 | 파일 |
|---|---|---|
| C1 서명과 변형 prepare | `pt_set_host_variables` 가 가변 POS(`host_var_expected_domains[i]` 가 UNKNOWN·ENUM 또는 ENFORCE collation)의 서명 문자열을 만들어 파서에 둔다. 해시 텍스트 5곳(`contextp->sql_hash_text = alias_print`)을 helper 하나로 모아 타입 변형 컴파일이면 `;bt=<서명>` 을 붙인다. 실행 경로(`db_execute_and_keep_statement_local`)에서 서명이 문장의 마지막 서명과 다르면 바인드 피크 재계획과 같은 길(`do_replan_statement_with_bind_peek` 재사용)로 다시 prepare; 문장에 마지막 서명·본 서명 수를 둔다(D-18). 본 서명 수 > N 이면 generic(서명 없는 해시 텍스트) 하나로 고정(D-14). | `parse_dbi.c`, `execute_statement.c`, `db_vdb.c`, `parse_tree.h` |
| C6 `plan_cache_mode` | 시스템 파라미터 auto/force_generic/force_typed(`plan_cache_bind_sensitivity` 의 열거형 패턴). force_generic = 서명을 붙이지 않음(오늘 동작). N 은 상수 8(측정 뒤 조정). | `system_parameter.{c,h}` |
| C2 타입 변형의 regu 도메인 | `pt_make_regu_hostvar`: 타입 변형 컴파일이면 가변 POS 의 사용자 호스트 변수도 값의 도메인(문자열 floating precision·codeset·collation·CHAR/VARCHAR, NUMERIC 은 Q14, NULL 은 `tp_Null_domain`)을 regu 도메인으로. 로드 도출이 `LATE_BIND` 항목을 만들지 않는지 optdebug assert(서명 컴파일 플래그를 스트림 헤더 비트로 서버에 전달). NULL 도메인 POS 를 로드 도출이 "값 없음" 으로 다루는지 확인(`domain_plan.c:888,1313` 의 `DB_TYPE_NULL` 고정 항목). | `xasl_generation.c`, `domain_plan.c` |
| C4 서버 검사 | `qexec_execute_query` 가 확정 전에 POS 참조마다 값 타입(문자열은 codeset·collation 도)과 regu 도메인을 비교, 다르면 optdebug assert·release `ER_QPROC_BIND_TYPE_MISMATCH`(새 코드, ko/en 메시지). | `domain_resolve.c`, `error_code.h`, msg catalogs |
| **M1** | release·optdebug 빌드, optdebug CTP sql·medium 전수를 `force_typed` 와 `force_generic` 으로 각각 돌려 셋(기준선 `be683e04c`) 이 같아야 한다. 변형 수 분포(해시 텍스트당)를 xcache 로그로 센다 → N. | — |
| C3 고정 결정의 로드 이전 | 읽은 사실(2026-10-11): `domain_compare_side` 는 `TYPE_POS_VALUE` 쪽을 도메인이 고정이어도 무조건 `DOMAIN_SIDE_LATE_BIND` 로 돌려(`domain_plan.c:3285-3290`) 모든 비교가 실행 전 확정 목록에 들어간다 — nobind 의 370·in-30 의 11.1k 가 이것. 행은 `fixed.method` 가 LATE_BIND 가 아니면 `comparison->fixed` 를 그대로 읽으므로(`query_evaluator.c:206-227`) 로드 결정에 행 변경이 없다. **C3a**: 항목이 고정(LATE_BIND 아님, `domain_fixes_values`)인 POS 쪽을 `DOMAIN_SIDE_KNOWN`(키 = 항목 도메인 + collate)으로 돌리되 `constant/bind[side]` 는 그대로 두어, `domain_plan_add_comparison` 이 로드에서 `domain_resolve_comparison` 을 하고 상수 쪽에 변환기(`conv`)나 COLLATE 복사(`collate[side]`)가 필요할 때만 늦은 바인딩으로 남긴다("값 타입 = 계획 도메인" 은 C4 가 release 에서 검사). **C3b**: 참조 번호는 이미 첫 참조 = val_pos(`domain_assign_references:4904`)이므로 `n_refs == dbval_cnt` 이고 확정 표·비교·원소·키·노드 도메인·임시값·상수식·세션변수·LIST_BIND 가 전부 0 인 플랜은 블록을 만들지 않고 `resolved.vals` 를 입력 배열에 별칭(alias)해 값 공유 루프를 건너뛴다(C4 검사만 남김); clear 는 별칭이면 해제하지 않는다(`qexec_alloc_resolved_domains` 의 `bytes == 0` 분기가 이미 있다). | `domain_plan.c`, `domain_resolve.c` |
| C5 세션변수 고정 타입 | D-13. `session_define_variable` 의 타입 검사(-1384), DROP 해제; 타입 변형 컴파일 때 `@var` 읽기의 타입을 `csession_get_variable` 로 받아 서명·regu 도메인에; C4 검사에 `@var` 포함. | `session.c`, `fetch.c`, `xasl_generation.c`, `parse_dbi.c` |
| **M2** | M1 과 같은 게이트 + 세션변수 TC 답 변경 목록. | — |
| C7 재변환 자리 제거 | §5 R1 → D → R2. | §5 의 파일들 |
| C8 NUMERIC floating (D-19) | (a) 타입 변형의 NUMERIC 바인드와 자동 파라미터 NUMERIC 리터럴의 regu 도메인 = `tp_Numeric_domain`(float numeric), 서명 토큰 `N`(scale 없음) (b) `domain_rules.c:1590-1603` 값 도메인 = `tp_Numeric_domain`(generic 경로도 같은 답) (c) `qfile_unify_types`(`list_file.c:935-947`): 도메인이 다른 NUMERIC 컬럼 둘은 가변 문자열처럼 허용하고 `tp_Numeric_domain` 으로 합친다 (d) `domain_resolve_list_column`(`domain_rules.c:1317-1323`): NUMERIC 가지가 도메인이 달라도 `tp_Numeric_domain` (e) 정렬·GROUP BY·보간 리스트는 이미 값의 header p/s 를 읽고 `numeric_db_value_compare` 로 scale 을 맞춰 비교한다 — 변경 없음을 CTP 로 확인. | `xasl_generation.c`, `parser_support.c`, `domain_rules.c`, `list_file.c` |
| **M3** | 최종 게이트 + 벤치(8셀 + 서명 교대 셀 + 변형당 xcache 메모리) + 문서·GLOSSARY·ADR. | — |

## 7. 프로토타입 진행 기록

- 2026-10-11: C1·C2·C4·C6·C8 편집(미커밋). 첫 빌드·스모크(`wf_30133109-0a7`) 통과: generic/typed/auto 출력이 시간 줄만 다름; gdb 로 캐시 키 `?bt=<위치><토큰>` 확인(INT `0:1,` NUMERIC `0N,` CHAR `0c5.1,` NULL `0n,`). 사실: `cannot_prepare` 문장(`typeof(?)` 등 print_type_ambiguity)은 캐시를 안 쓰므로 타입 변형 대상에서 제외; csql SQL-level `EXECUTE` 는 kept tree 가 없으면 매번 새 세션에서 재컴파일(SELECT 는 unbound compile-first)하므로 타입 변형이 조회 1회를 더한다(JDBC/CCI 는 문장 노드가 유지되어 서명이 같으면 0). 해시 텍스트에는 이미 `bind_var_cnt=N` 접미사가 있다.
- 2026-10-11 M1 1차(`wf_b91aecc3-c91`): 스모크 실패 — `sum(?)`/`avg(?)`/`max(?)`/`min(?)`(인자가 바인드 그 자체)가 타입 변형에서 -1383. 원인: `domain_function_is_late_bound` 가 함수 컴파일 도메인 VARIABLE 을 늦은 바인딩으로 보지 않음(generic 은 POS 가 가변이라 가려짐). 한 줄 수정. 같은 패턴(컴파일 VARIABLE 노드 + 고정 POS 피연산자)이 다른 규칙에도 있는지는 CTP 전수가 판정. 기준선에도 있는 기존 오류: `select ? union all select ?` 에 NUMERIC·INT 혼합 → -181 (`domain_resolve_list_column`/파서가 타입이 다른 가지를 거부).
- 2026-10-12 M1 2차(`wf_5a9148e0-917`): 스모크 실패 — `sum(?)` 은 통과, 집계 `avg(?)`(plain·distinct·GROUP BY)만 typed/auto 에서 -1383(`qexec_setup_aggregate_domains` 의 고정 분기 `domain_resolve.c:4140`). 원인: AVG 는 컴파일 도메인이 DOUBLE(VARIABLE 아님)이라 늦은 바인딩 노드가 아니고, 타입 변형에서 POS 는 고정이므로 로드가 ACCUMULATOR 로 고정했지만, XASL 의 `opr_dbtype` 은 파서 노드 타입(`pt_node_to_db_type(?)` = VARIABLE)이어서 실행의 `qexec_node_operand_type` 이 VARIABLE 을 돌려 "미해결" 로 떨어짐. SUM/MAX/MIN 은 함수 도메인이 VARIABLE 이라 1차 수정의 늦은 바인딩 경로를 타서 가려졌음. 수정: `xasl_generation.c` 에 `pt_typed_bind_type (parser, node)`(타입 변형이 사용자 호스트 변수를 컴파일하는 타입: 값의 타입, 서명 클래스 밖이면 VARIABLE)을 두고 `pt_make_regu_hostvar` 의 typed_bind 판정과 집계 `opr_dbtype`(VARIABLE 이면 이 타입) 두 곳이 쓴다 — 타입 변형의 원칙("XASL 에 정해지지 않은 타입이 남지 않는다")을 `opr_dbtype` 에도 적용한 것. 분석 함수의 `opr_dbtype`(`xasl_generation.c:26071`) 은 늦은 바인딩 설정(`qexec_setup_analytic_domains`) 이 처리하여 스모크(p12) 가 통과하므로 건드리지 않음. 스모크의 잘못된 문장 m(집계와 분석 함수 혼용, 파서 거부)을 m/m2/m3(집계·분석·GROUP BY) 으로 나눔. 1차 분석에서 CTP 전수는 아직 한 번도 돌지 않음.
- 2026-10-12 C3a 설계 사실(게이트 대기 중 읽음): 비교·키·대입이 읽는 바인드 항목은 `DOMAIN_PLAN_CONSUMER_CONVERTS`(`domain_plan.c:445`)이고, C4 의 "값 타입 = 계획 도메인" 검사(`domain_resolve.c:3032`)는 이 항목을 건너뛴다 — generic 플랜에서는 클라이언트가 이런 값을 그대로 보내는 경우가 있기 때문(ORDERBY_NUM 과 비교되는 NUMERIC, `domain_bind_read_by_value` 주석). 따라서 C3a 가 고정 POS 쪽을 `DOMAIN_SIDE_KNOWN` 으로 돌리는 것은 **타입 변형 플랜에서만** 안전하고(서명이 값 타입 = regu 도메인을 보장), 그때는 C4 검사도 CONSUMER_CONVERTS 항목까지 넓혀야 한다. 서버가 플랜이 타입 변형인지 알려면 XASL 스트림 헤더 비트가 필요(C2 행의 메모와 같음). generic 플랜의 비교는 오늘 그대로 실행당 확정(비용은 generic 의 몫).
- 2026-10-12 C3a 설계(계속): 타입 변형 플랜 표시는 최상위 XASL 의 `xasl->flag` 비트(`XASL_*` 는 bit 24 까지 사용, `xasl_to_stream.c:2831` 이 스트림에 넣음) 하나로 충분. 그러나 "타입 변형이면 값 타입 = regu 도메인" 이 모든 POS 에 성립하려면 기대 도메인이 있는 위치도 같아야 한다: 클라이언트는 `pt_set_host_variables`(`parse_dbi.c:3109-3128`)에서 UNKNOWN·ENUM 을 뺀 모든 기대 도메인으로 값을 캐스트하되 **CHAR 도메인에 VARCHAR 값은 원래 값을 남기고**, NULL 은 `preserve_domain` 으로 도메인 타입을 가진 NULL 이 된다. 그래서 C4 검사는 CHAR/VARCHAR 를 같은 것으로 보고 CONSUMER_CONVERTS 항목을 건너뛴다. C3a 후보(게이트 뒤 결정, D-20 제안): 타입 변형의 서명을 캐스트 **뒤**의 값으로 모든 위치에 대해 만들고(기대 도메인 위치의 토큰은 캐스트된 타입·CHAR/VARCHAR·codeset/collation; NULL 은 `DB_VALUE_DOMAIN_TYPE` 으로 도메인 타입 토큰이라 NULL 변형이 늘지 않음), `pt_make_regu_hostvar` 가 타입 변형에서는 기대 도메인 위치도 값의 도메인(CHAR/VARCHAR 그대로, 정밀도 floating)을 regu 도메인으로 쓰면, 타입 변형 플랜의 모든 POS 가 "값 타입 = regu 도메인" 을 만족하여 C4 가 전부 검사하고 C3a 가 모든 고정 POS 쪽을 KNOWN 으로 돌릴 수 있다. generic 플랜은 그대로(기대 도메인 캐스트 + 실행당 확정).
- 2026-10-12 M1 3차(`wf_fe6d8e50-318`): 빌드 실패 — `pt_typed_bind_type` 의 전방 선언 누락(리드의 편집 실수, 선언 순서 확인 규칙).
- 2026-10-12 M1 3b(`wf_e359b970-9e6`): 스모크(82문장) 전 모드·release·기준선 모두 diff 없음. CTP: 기준선 A sql 17,510/medium 975 전부 통과; B(generic)·C(typed) 는 첫 코어에서 watchdog 중단 → 작업자가 `NO_ABORT_ON_CORE=1` 전수(B2 23건·C2 18건)와 격리 재실행(B3·C3)을 더 돌려 네 부류로 갈랐다(medium 은 B·C 모두 975/975).
  1. **optdebug assert `domain_rules.c:1617`(모든 모드, release 는 무해)**: `domain_value_domain` 의 디버그 교차검사 `domain == tp_domain_resolve_value(value)` 가 D-19 의 `tp_Numeric_domain` 과 값의 NUMERIC(p,s) 캐시 도메인을 비교 — NUMERIC 바인드·`cast(2 as numeric(10,5))` 인덱스 키마다 cub_server 다운(4 TC + 충돌 여파 17건). 수정: NUMERIC 이면 `tp_Numeric_domain` 도 허용.
  2. **결과 diff(모든 모드, release 포함) `bug_bts_10057_3`·`issue_8391_like/_04_prepare_01`**: csql 의 `EXECUTE` 는 문장을 현재 세션에서 재파싱·재컴파일하므로 prepare 시점 collation 은 XASL 캐시 적중(해시 텍스트에 세션 collation 없음 — `intl_collation` 은 `PRM_FOR_QRY_STRING` 아님, 자동 파라미터는 ` ?:N` 으로 찍힘)으로만 유지된다. 리터럴 토큰에 codeset/collation 을 넣자 세션마다 플랜이 갈려 "실행 시점 collation" 이 되었다. 수정: generic 플랜은 해시 텍스트에 아무것도 붙이지 않고(§6 C1 의 "force_generic = 오늘 동작"), 타입 변형의 리터럴 토큰은 타입(CHAR/VARCHAR)만. 사용자 바인드 문자열 토큰은 codeset 까지(아래 D-20).
  3. **typed 전용 CAS assert `type_checking.c:14554`** (`limit ?*?+?*?-?/?+5`, 정수 바인드 6개; `issue_20567_limit` 5건): `pt_evaluate_db_value_expr` BIGINT MINUS 에서 `typ1 != typ2`. 호출 경로 미확인 → 진단 워크플로가 백트레이스를 뜬다.
  4. **typed 전용 결과 diff**: (a) `cbrd_26401/invisible_plcsql` — PL/CSQL 루프의 `update t2 set c1 = r.c1 * 10 where id = r.id` 가 첫 반복의 값(300)을 모든 행에 썼다(stale 상수 의심: 바인드 값이 플랜에 구워졌거나 상수식 캐시가 실행 간에 남음). (b) `cbrd_27510/16_hash_scan_build_keys` — 첫 `execute` 뒤 `show trace` 에 Query Plan 블록이 더 찍힘: 타입 변형의 첫 실행이 새 플랜을 생성하므로(기준선은 PREPARE 의 캐시 플랜 적중) trace 에 플랜이 실린다 → 사양 변경 부류(캐시 키 변경과 같은 D-345-04 류) 후보, 통과 뒤 목록화.
- 2026-10-12 D-20(리드 결정, 사용자 확인 전): 타입 변형 서명의 문자열 토큰은 **타입·CHAR/VARCHAR·codeset** 까지이고 collation 은 뺀다. 타입 변형의 문자열 바인드 regu 도메인은 값의 codeset 에 `TP_DOMAIN_COLL_LEAVE` 를 얹어 collation 축만 실행당 확정(`DOMAIN_PLAN_LATE_BIND_COLLATION`, develop 의 LEAVE 기대 도메인과 같은 길)으로 남긴다. 이유: collation 을 키에 넣으면 `set names` 마다 변형이 갈려 prepare 시점 collation 의미(bug_bts_10057, issue_8391 의 `? like '%B'`)가 깨지고 변형 수도 는다; PG 도 파라미터 타입에 collation 을 두지 않는다(collation 은 식에서 유도). C3a 는 문자열 POS 쪽을 KNOWN 으로 돌리지 않는다(컬럼과의 비교는 기대 도메인 캐스트로 이미 고정). **아직 코드에 반영 안 함**(진단 결과 뒤 한 번에).
- 2026-10-12 진단(`wf_db03cc0f-d35`) 결과: (i) 새 결함 — `pt_bind_type_signature` 의 범위 밖 읽기: csql `EXECUTE` 노드(저장된 PREPARE 플랜을 바로 실행하는 SELECT 경로)의 파서는 `do_get_prepared_statement_info` 가 자동 파라미터를 `host_var_count` 에 합치고(`db_vdb.c:3158`) `host_var_expected_domains` 는 사용자 변수만큼이라 `expected_domains[i]` 를 넘어 읽음(MALLOC_PERTURB_ 로 결정적 재현). 수정: `db_update_bind_signature` 가 `PT_EXECUTE_PREPARE` 노드는 건너뜀(타입 변형은 재컴파일·kept tree 경로에서 고른다; csql 전용 경로, JDBC/CCI 는 EXECUTE 노드를 만들지 않음). (ii) stale 값: 순수 SQL 로도 재현 — `prepare u from 'update t30 set c1 = ? * 10 where id = ?'` 두 번 실행 시 둘 다 30; UPDATE 의 SET/WHERE 식과 DELETE WHERE 식만, SELECT/INSERT 는 정상. gdb: 실행 1 의 컴파일에서 `pt_fold_const_expr`(←`pt_fold_constants_post`) 이 바인드 값으로 `3 * 10` 을 접어 30 을 만들고(`pt_fold_const_expr` 는 `pt_value_to_db(host var)` 가 값을 주면 호스트 변수를 값으로 바꾼다, `type_checking.c:18156`), `pt_to_update_xasl` 이 상수 대입(`is_rhs_const`)의 값을 XASL 의 `assigns[a].constant` 에 굽는다(`xasl_generation.c:23224-23296`). 실행 2 는 같은 서명 키로 캐시 적중 → 구운 30. generic 은 실행 1 이 PREPARE 플랜에 적중해 값이 보이는 생성 경로를 아예 타지 않는다(옵티마이저 재작성 `query_rewrite_term.c:404` 의 `pt_semantic_type` 이 생성 중 접기를 다시 돈다; 히스토그램 재계획도 같은 경로라 develop 의 잠재 결함 후보). (iii) LIMIT assert: `pt_get_query_limit_from_limit` 이 `set_host_var` 를 강제로 켜고 기대 도메인으로 캐스트된 값들로 `?*?+?*?-?/?+5` 를 평가 → BIGINT MINUS 에서 피연산자 타입 불일치 assert; 역시 값이 보이는 생성 경로에서만. (iv) `invisible_plcsql`·`issue_20567_limit` 단일 CTP 로 확인(typed 실패, generic 통과).
- 2026-10-12 D-21(리드 결정): **타입 변형 플랜은 값의 타입으로만 컴파일하고 값은 읽지 않는다.** 구현: `pt_host_var_db_value` 가 `parser->flag.typed_bind_plan` 동안 사용자 호스트 변수를 "바인드 안 됨" 으로 답한다(접기·UPDATE 상수 굽기·LIMIT 값 peek 모두 이 한 점을 지난다; regu 도메인은 `pt_make_regu_hostvar`/`pt_typed_bind_type` 이 값 배열을 직접 읽는다). 옵티마이저의 히스토그램 선택도(`query_planner.c` 가 `host_variables[]` 를 직접 읽음)는 그대로라 타입 변형도 첫 컴파일 값으로 선택도를 본다(bind sensitivity 재계획과 호환). PG generic plan 과 같은 원칙.
- 2026-10-12 D-20 코드 반영: 사용자 문자열 토큰 `<i>c|s<codeset>,`; 타입 변형의 문자열 바인드 regu 도메인에 `TP_DOMAIN_COLL_LEAVE`.
- 2026-10-12 진단 2(`wf_77d19362-d59`, D-20/D-21 편집 이전 빌드): 가설 확정. UPDATE `u`: generic 은 PREPARE 가 해시 H0 미스로 생성(값 안 보임, `assigns[].constant` NULL, 선택 목록 항목 = TYPE_INARITH)·저장하고 실행 1·2 가 H0 에 적중해 30·40. typed 는 실행 1 의 키 H0+`?bt=0:1,1:1,` 미스 → `set_host_var=1` 로 `pt_to_update_xasl` → `mq_translate` → `pt_semantic_type` → `pt_fold_constants_post` 가 `?:0 * 10` 을 PT_VALUE 30 으로 접어 UPDATE 의 선택 목록 항목이 TYPE_DBVAL 30 으로 구워짐(`assigns[].constant` 가 아니라 선택 목록) → 실행 2 적중 → 30·30. LIMIT: generic 은 PREPARE 때만 `pt_get_query_limit_value` 를 값 없이 지나고 실행은 적중; typed 는 미스 후 `set_host_var=1` 로 평가 → assert. EXECUTE 노드 수정 뒤 `prepare g` 블록·전체 스모크가 MALLOC_PERTURB_ 1/165/255 에서 모두 정상.
- 2026-10-12 develop 결함 후보(별도 이슈로, 기준선 재현 뒤): 히스토그램 bind-peek 재계획(`do_replan_statement_with_bind_peek`, `recompile=1`)도 `set_host_var=1` 로 XASL 을 생성하므로 `update t set c1 = ? * 10 where c2 = ?`(c2 에 통계가 있어 재계획이 뜨는 경우) 의 접힌 30 이 generic 캐시 키 아래 구워지고 다음 실행(다른 값)이 그 플랜에 적중한다 — 진단 2 가 밝힌 경로와 같다. 타입 변형은 D-21 로 막히지만 force_generic 의 재계획 경로는 develop 그대로. 검증 셀: 기준선 release 에서 통계 수집 뒤 위 문장을 두 값으로 실행.
- 2026-10-12 M1 4차(`wf_793baf7e-a3e`): 스모크 실패 — D-21 의 "바인드 안 됨" 답을 `pt_value_to_db`(`parse_dbi.c:1192`) 가 `set_host_var==1` 이면 호스트 변수 인덱스 오류로 보고(UPDATE 7문장). 수정: 타입 변형 생성 중에는 그 오류를 내지 않음(평가기는 NULL 값으로 진행, PREPARE 때와 같음). `l`(LIMIT 식) 은 통과, `s2` 정상.
- 2026-10-12 M1 5차(`wf_30b1d102-540`): 스모크 전 모드 diff 없음(stale·LIMIT probe 정상). **CTP generic = 기준선**(sql 17,510/0, medium 975/0, 코어 0). typed: sql 357·medium 7 실패, 코어·assert 0, 격리 재실행에서 전부 재현. 부류: (1) 352+7 = 한 원인 — `authenticate.c` 의 내부 UPDATE(`? in d.direct_groups`)가 타입 변형으로 재계획될 때 `pt_coerce_value_internal` 이 `set_host_var==1` 이라 값을 읽으려다(D-21 게이트가 NULL) "Cannot coerce ?:1 to type (null)" → add_user/drop_user 실패 → 사용자 잔류 연쇄. 즉 D-21 을 `pt_host_var_db_value` 한 점에만 걸면 `set_host_var` 를 직접 보는 독자(코어션 등)와 어긋난다. 수정: `do_prepare_statement` 가 타입 변형 생성 동안 `set_host_var` 자체를 0 으로 두고 끝에 복원(PREPARE 와 동일한 시야); `HV_PRED_PLAN_UNPEEKED` 표시 3곳은 타입 변형을 건너뜀(옵티마이저는 값 배열을 직접 읽어 선택도를 봤으므로 peeked). (2) `order by … limit ?,?` 플랜 모양 diff 3건(cbrd_24467·cbrd_25374·join_orderby_skip) + keylimit 결과 diff 1건 — 값이 보이는 생성의 다른 얼굴로 추정, 6차에서 판정. (3) 16_hash_scan_build_keys = trace 의 Query Plan 블록 추가(사양 변경 부류).
- 2026-10-12 M1 6차(`wf_fba662bd-bd4`): generic = 기준선, 사용자 연쇄 소멸, add_user/drop_user 정상. typed 는 4건만 남음(코어·assert 0, 격리·auto 모드에서 재현): `order by … limit ?,?` 플랜 모양 3건(cbrd_24467·cbrd_25374·join_orderby_skip; SORT-LIMIT/SUBQUERY topnsort 대신 스캔 + skip order by)과 keylimit 결과(동률 행 순서) 1건 + 사양 변경 부류 1건. 원인: develop 의 csql `EXECUTE` 는 저장 플랜의 헤더 플래그(SORT_LIMIT/MRO CANDIDATE)와 바인드된 LIMIT 값으로 재컴파일을 결정하고(`db_check_limit_need_recompile` → `bind_before_compile`), 그 생성은 `pt_get_query_limit_from_limit` 이 값을 peek 해 SORT-LIMIT 플랜을 고른다. 6차의 타입 변형 생성은 값을 완전히 가려 LIMIT 도 못 봤다. 결정(D-21 보정): LIMIT peek 은 스스로 `set_host_var` 를 켜는 함수이므로 타입 변형 생성에서도 값을 본다(develop parity; JDBC 는 어차피 재컴파일 없음). `pt_host_var_db_value`/`pt_value_to_db` 의 타입 게이트는 제거(원복). 그러면 `limit ?*?+?*?-?/?+5` 평가의 혼합 타입 `assert(false)`(`type_checking.c:14552`, 기대 도메인이 다르게 캐스트된 값들의 BIGINT MINUS)가 돌아오므로 assert 만 지우고 NULL(= LIMIT 미정) 로 둔다 — develop 의 csql EXECUTE 재컴파일 경로에서도 같은 식이면 똑같이 걸리는 잠재 assert.
- 2026-10-12 **M1 7차(`wf_4a3ca854-1fe`) PASS.** 스모크 전 모드·release·기준선 diff 없음; add_user·keylimit·limit 재현 전부 정상(typed 의 bound-limit 재컴파일 플랜 = temp(sort limit), generic/기준선과 동일). CTP sql+medium: generic 17,510/0·975/0(= 기준선 A); typed 17,510/1·975/0, 코어·assert 0. 남은 1건 `_36_guava/cbrd_27510/16_hash_scan_build_keys`: `show trace` 에 Query Plan 블록 2개 추가(26줄 추가, 삭제 0) — 타입 변형의 첫 실행이 플랜을 생성하기 때문이며 **기본 auto 모드에서도 같은 diff**(기준선 optdebug 는 29/29 통과) → 사양 변경 목록에 올리고 TC 답 갱신 대상. 커밋 `8ecc4c24e` (브랜치 CBRD-27583, codestyle 적용; `cubrid-cci` 서브모듈 포인터는 제외). 6차의 4건(limit 플랜 모양·동률)은 통과.
- 사양 변경 누적 목록(게이트에서 확인된 것): (1) 타입 변형의 첫 실행이 플랜을 생성하므로 `show trace` 에 Query Plan 블록이 실린다(16_hash_scan_build_keys; auto 기본값에서도). (2) 캐시 키 텍스트에 `?bt=` 서명이 붙어 plandump/SQL_ID TC(D-345-04 류)는 M3 전수에서 확인. (3) `limit ?*?-?/?` 혼합 타입 평가의 optdebug assert 제거(release 동작 불변).
- 2026-10-12 **C3a 게이트 PASS**(`wf_043f0787-79b`, 1차): generic 17,510/0·975/0 = 기준선; typed 17,510/1(사양 변경 1건)·975/0; 스모크 122문장 전 모드 diff 없음(k1 의 `cast(...)` USING 은 csql 문법 오류로 전 모드 동일, k3 첫 실행의 VARCHAR IN 리스트 + INT 바인드 오류는 기준선에도 동일). gdb 증거: `select count(*) from t30 where id = ?` typed 플랜 `typed=true n_resolved=0 n_refs=1 n_compare_indexes=0`(generic `n_resolved=2 n_refs=2 n_compare_indexes=1`); `id = ? and c16 = ?` typed 0/0(5·5.0)… 단 `('5','v5')`·`(NULL,'v5')` 는 1 — 캐스트 뒤 같은 서명이어야 하는데 다른 플랜이 잡힌 것으로 보여 벤치(alt-pk) 에서 확인. 커밋 `90d409ca3`.
- 2026-10-12 벤치(`wf_4f1c52bb-3ba`)·진단(`wf_2b3bedb6-e89`): §3.4·§3.5.
- 2026-10-12 C5 1차(`wf_26eea740-fe9`): 규칙상 PASS. csql EXECUTE 빠른 경로 확인(실행 2~4 는 `do_find_typed_plan` 조회만, 재컴파일·재계획·생성 0; same-pk H 106,117 / G 105,898 / **T 123,881**(+18k = 서명 + 조회 왕복 + SHA1; 이전 790k)). CTP: generic·typed 모두 **58 sql TC** 가 -1386(세션 변수 타입 고정) 사양 변경 2류(292 개 새 오류 + 393 개 후속 diff, 미설명 0; 기준선과 "실패한 SET 을 뺀 재실행" 이 일치) — TZ 날짜 포맷 38건, json 호스트 변수, enum, 세션 변수 TC 등. 사용자에게 규모 보고 필요. 작업자가 찾은 typed/auto 전용 결함(csql -S 만): `(select k, ? v from hk_i …) b` 의 바인드에 NULL → "node unresolved"/assert. 원인: D-21 로 생성 중 `set_host_var=0` 이 되자 `pt_make_regu_hostvar` 의 "미바인드 NULL 값을 기대 타입으로 사전 초기화" 가 **실제 바인드된 NULL** 의 도메인을 VARIABLE 로 바꿈. 수정: 타입 변형 생성에서는 사전 초기화 안 함. -1386 메시지 문구 수정(관사 오류, 문자열은 charset 표기). TC 메모: `_36_guava/cbrd_27510/01·02` 는 같은 연결의 `cbrd_25567` 이 남긴 `@v` 에 의존해 배치에 따라 답이 달라짐(TC PR 때 정리).
- 2026-10-12 **C5 2차(`wf_7a313b92-c55`) PASS**: 스모크 149문장 전 모드·release diff 없음(hk_b4 NULL 바인드 수정 확인), c1 vs head 차이는 세션 변수 블록(-1386)뿐; CTP typed·generic 모두 sql 17,510/58·medium 975/0, 코어·assert 0, 실패 목록은 1차와 동일(2류 57 + 16_hash_scan_build_keys 1류). 커밋 `806584310`(C5 세트: -1386 고정 타입, csql EXECUTE 타입 변형 조회 `do_find_typed_plan`, unpeeked 리셋, snprintf 없는 서명, NULL 사전 초기화 수정). 사양 변경 2류 58 TC 규모는 사용자 판단 대기(NULL 이 타입을 비우는 규칙 포함).
- 2026-10-12 C7 1차 설계(게이트 대기 중 읽음, §5 R1 의 fetch.c 몫): 이미 있는 길은 `fetch_cast_operand`(fetch.c:929) — 항목의 `fixed.conv[i]`(로드가 `domain_fixed_operand` 로 찾음) 또는 늦은 바인딩 항목의 `resolved->conv[i]`(`qexec_resolve_cast_coercion`) 로 캐스트하고 없으면 범용 `tp_value_cast` 폴백. 오늘은 CAST·NVL/IFNULL/COALESCE·NVL2 만 이 길을 탄다(`casts_into_node`, `domain_cast_operand_is_variable`, `qexec_resolve_cast_coercion` 세 곳이 같은 opcode 목록을 따로 들고 있다). 설계: 규칙 하나 `domain_operand_cast_target (opcode, i, n_operands, node_domain, source_type)`(domain_rules.c, 타입 규칙의 단일 거처)이 "행이 피연산자 i 를 어느 도메인으로 캐스트하는가" 를 답하고(노드 도메인: CAST·NVL 류·CASE/DECODE/IF·NULLIF(0)·LEAST/GREATEST·CONCAT 단항·CONCAT_WS; `tp_Char_domain`: TO_DATE/TO_TIME/TO_TIMESTAMP(_TZ)/TO_DATETIME(_TZ) 의 비문자 피연산자 0, OCTET/BIT_LENGTH 의 비문자 피연산자 1(BLOB 은 `tp_VarBit_domain`); `tp_Integer_domain`: LEFT/RIGHT 길이), 세 곳이 그 규칙을 부른다. 행은 `fetch_cast_operand` 로 바꾸고(`tp_value_auto_cast` 자리는 같은 `return_null_on_function_errors` 폴백을 두른 `fetch_auto_cast_operand`), LEAST/GREATEST 는 비교 결과로 고른 피연산자 번호를 넘긴다; T_PREDICATE 는 노드 도메인이 LOGICAL=INTEGER 고정이라 캐스트 없이 바로 `db_make_int`. 폴백 `tp_value_cast` 삭제(assert + 미확정 오류)는 R1 전부 뒤 D 단계에서. TRIM 류의 `tp_value_change_coll_and_codeset` 과 SYS_CONNECT_BY_PATH(함수가 만든 문자열의 재캐스트)는 2차.
- 2026-10-12 C7 1차 편집(게이트 `wf_012af45e-db0`, 미커밋): §7 의 1차 설계대로 `domain_operand_cast_target`(domain_rules.c) 하나를 로드(`domain_fixed_operand` 의 목표)·확정(`qexec_resolve_cast_coercion`, 링크의 첫 피연산자 건너뜀을 CAST·OCTET/BIT_LENGTH 로 일반화)·행(`fetch_cast_operand`/`fetch_auto_cast_operand`)이 공유; `domain_cast_operand_is_variable` 도 같은 규칙으로 일반화(바인드 피연산자를 가진 CASE·TO_DATE·LEFT 류가 generic 플랜에서 `LATE_BIND_COERCION` 으로 실행 전 변환기를 받는다). fetch.c 의 범용 cast 25곳 → 변환기 경로(T_PREDICATE 는 캐스트 삭제, LEAST/GREATEST 는 고른 피연산자 번호). 남은 범용 cast: 672(세션 읽기), 954(`fetch_cast_operand` 폴백, D 단계), 4348(SYS_CONNECT_BY_PATH). 스모크에 c7a/c7b/c7c 프로브 19줄 추가(168줄).
- 2026-10-12 **C7 1차 게이트 PASS**(`wf_012af45e-db0`): 스모크 168문장 전 모드·release diff 없음, C7 프로브 블록은 head-release 와 동일(오류 줄 포함); CTP typed·generic 모두 17,510/58·975/0, 실패 목록 = C5 목록, 코어·assert 0. 커밋 `dc3d67d50`.
- 2026-10-12 C7 2차 편집(게이트 `wf_793915aa-a64`, 미커밋, 8파일): TRIM/LTRIM/RTRIM/LPAD/RPAD/REPLACE/TRANSLATE 의 INFER_COLLATION 블록 7곳과 플래그 삭제(죽은 코드); 집계 누산기 설정이 STDDEV/VARIANCE 의 인자→DOUBLE 변환기(IMPLICIT)와 MEDIAN/PERCENTILE 의 인자→함수 기본 도메인 변환기(ASSIGN)를 `operand_coercion[1]` 에 두고 행(658·2043 은 `qdata_coerce_to_double`, 1359 는 `tp_value_cast_with_converter`)이 쓴다; 보간 정렬 키 `SUBKEY_INFO.cmp_conv`(`cmp_dom` 과 함께 찾음) 로 비교의 두 캐스트를 `tp_value_convert` 로; SYS_CONNECT_BY_PATH 는 로드가 `tp_String_domain`→노드 도메인 변환기를 `fixed.conv[0]` 에 두고 행은 `fetch_auto_cast_value (…, DB_TYPE_VARCHAR, …)`(`fetch_cast_operand` 를 `fetch_cast_value` 위에 얹어 소스 타입을 명시). 스모크 183줄(c7d·c7s 프로브). 남은 R1: 실행당 상수(키 리밋·LIMIT/상한·LEAD/LAG/NTH_VALUE offset·NTILE)·INSERT 기본값·`btree_coerce_key`·fetch.c:672 — 3차.
- 2026-10-12 **C7 2차 게이트 PASS**(`wf_793915aa-a64`): 스모크 183문장 전 모드 diff 없음, 2차 블록 15문장 head-release 와 바이트 동일; CTP typed·generic 17,510/58·975/0, 목록 = 1차, 코어 0. 커밋 `b906eeb97`.
- 2026-10-12 C7 3차 편집(게이트 `wf_35ae5036-a9e`, 미커밋, 4파일): `btree_coerce_key` 단일 컬럼 가지 → assert + ER_FAILED; `qexec_setup_analytic_offsets`(설정, `a_regu_list` 를 `qexec_setup_analytic_domains` 에 넘김)가 LEAD/LAG/NTH_VALUE 의 offset→INTEGER/DOUBLE·default→함수 도메인 변환기(IMPLICIT)를 누산기 `operand_coercion` [1]/[2] 에 두고 행은 `qexec_analytic_convert_operand`(NULL 은 NULL, 변환기 없으면 generic coerce 폴백 — D 단계). INSERT 기본값(13056 UUID 행 생성·13595 실행당 생성)은 생성기의 첫 변환으로 G 재분류(§5 표 갱신 예정). 스모크 206줄(c7e·c7k 프로브).
- 2026-10-12 C7 3차 1차 게이트(`wf_35ae5036-a9e`) SMOKE_FAILED: LEAD/LAG/NTH_VALUE 전부 SIGSEGV — 리드의 편집 결함(`DOMAIN_OPERAND_COERCION` 은 슬롯 2개인데 `qexec_setup_analytic_offsets` 가 [1]/[2] 에 써서 범위 밖, `arith` 를 덮음; 선언을 확인하지 않고 RESOLVED_DOMAIN 의 3슬롯으로 착각). 수정: [0]=offset, [1]=default. c7k 복합 인덱스 프로브는 통과(assert 없음). 2차 게이트 `wf_6e630afa-631`.
- 2026-10-12 **C7 3차 2차 게이트 PASS**(`wf_6e630afa-631`): 스모크 206문장 전 모드 diff 없음, LEAD/LAG/NTH_VALUE·c7k 블록 head-release 와 동일, btree_coerce_key assert 미발생; CTP typed·generic 17,510/58·975/0, 목록·분류 = 2차, 코어 0. 커밋 `b158af23c`.
- 2026-10-12 D 단계 편집(미커밋, 6파일): optdebug 교차 검사 `scan_check_key_strict`·`qexec_check_key_strict`·`qfile_check_interpolation_type` 와 그것만 읽던 `SUBKEY_INFO.cmp_dom_session_read` 삭제; `fetch_cast_value` 는 항목 없는 노드의 NULL 아닌 값을 미확정 오류로(`fetch_arith_binary` 와 같은 전제), 같은 타입의 정밀도·collation 조정과 변환기 없는 쌍의 오류 보고는 cast 로 남김. 최종 게이트 `wf_6bc7076b-36d`(빌드·스모크 뒤 CTP typed/generic 과 13셀 H/G/T 벤치를 병렬; 사용자가 게이트 시간을 지적해 D 단계와 M3 를 한 번에). 변형 수 분포(N)는 측정 안 함: `plan_cache_logging` 은 키 비교마다 디버그 줄을 남겨 CTP 에 쓸 수 없다. ADR 0027 초안(proposed)·ADR 0020 보정.
- 2026-10-12 최종 게이트 1차(`wf_6bc7076b-36d`) FAIL: D 단계에 넣은 "항목 없는 노드 = 미확정 오류" 가지가 함수 인덱스 키 식(`heap_eval_function_index`, vd·항목 없음, `RIGHT(s,3)` 의 길이 캐스트)을 assert 로 떨어뜨림 — CTP typed 코어 133(289 GB, 분석 뒤 삭제), generic 도 같은 자리. 벤치 레인은 PASS(`bench/report-final.md`). 수정: 그 가지 삭제(b158af23c 와 같은 폴백), 스모크에 함수 인덱스 프로브 12줄(218줄).
- 2026-10-12 **최종 게이트 2차(`wf_7f1a17e0-3bf`) PASS**: 스모크 218줄 전 모드 diff 없음, head-release 대비 세션 변수 블록만; CTP typed·generic sql 17,510/58·medium 975/0, 실패 목록·casediffs·분류 = c7a3b, 코어 0. 커밋 `1f3e26871`. ADR 0027 accepted, ADR 0020 보정.
- 최종 벤치(`bench/report-final.md`, csql -S, 통계 있는 DB): 일반 플랜 G 는 develop H 대비 -0.3%~+0.75%. 타입 변형 T 는 G 대비 `and-30` -0.3%, `alt-in3` -3.7%, `nobind` 같음, 나머지 9셀 +1.6%~+20%(+15k~+104k). 원인: csql SQL `EXECUTE` 는 실행마다 서명 + `do_find_typed_plan` 캐시 조회(약 18k), 문자열 바인드는 D-20 으로 collation 이 실행당 확정이라 줄일 몫이 없음(`case-30` +104k). CAS/JDBC(핸들 유지, 서명 비교만) 경로는 측정 안 함 — `auto` 기본값 판단은 사용자 몫.
- 2026-10-12 **작업 종료(사용자 지시).** 브랜치를 fork 에 push(`xmilex-git/cubrid` `CBRD-27583`, `1f3e26871`), JIRA CBRD-27583 에 담당자 참고용 댓글 4776777(브랜치·구현·검증·벤치·우려 9개). 세션 변수 규칙 유지 여부, `plan_cache_mode` 기본값, 함수 내부 캐스케이드, TC 답 갱신·엔진 PR 은 담당자 몫으로 넘김. 이 세션의 CTP 실행 디렉터리 70개(15 GB)와 빈 코어 디렉터리 삭제, 최종 게이트 4개만 남김; 분석한 코어 약 294 GB 삭제.
- 2026-10-12 C7 3차 설계(읽은 사실): (1) `btree_coerce_key` 의 유일한 호출자 `scan_dbvals_to_midxkey` 는 키 계획이 원소를 변환한 뒤 MIDXKEY 값으로 부르므로 단일 컬럼 가지(`tp_more_general_type` 판정 + `tp_value_coerce`/`_strict`, btree.c:19440-19475)는 죽은 코드 → 삭제, MIDXKEY 만 남긴다. (2) LEAD/LAG/NTH_VALUE 의 offset(→INTEGER/DOUBLE, 행마다)과 default(→함수 도메인, 행마다): 분석 함수 설정(`qexec_setup_analytic_domains`, 호출자 query_executor.c:16384 가 `a_regu_list` 를 넘길 수 있다)이 `offset_idx`/`default_idx` 의 regu 값 도메인(`qexec_value_domain`)에서 변환기를 찾아 누산기 도메인의 `operand_coercion` [1]/[2] 에 두고 행이 `tp_value_convert`. (3) INSERT 기본값: 실행당 1회 생성·변환하는 종류(query_executor.c:13595, SYSDATE 류)는 그 변환이 유일한 첫 변환이라 G(남김); 행마다 만드는 UUID/SYSGUID 종류(13056)는 실행당 한 번 찾은 변환기(종류별 소스 타입 고정)로. (4) 키 리밋·LIMIT/상한·NTILE 은 실행(또는 스캔)당 1회 상수 변환이며 플랜이 정해 둔 도메인을 다시 캐스트하는 것이 아니다 → G 로 재분류(§5 표 갱신). (5) fetch.c:672(세션 변수 읽기의 CHAR→VARCHAR) 는 D-13 의 남은 부분(타입 변형의 `@var` 타입 고정)과 함께 처리.
- 2026-10-12 C7 2차 설계(읽은 사실): (1) TRIM/LPAD/RPAD 류 7곳의 `tp_value_change_coll_and_codeset` 은 `REGU_VARIABLE_INFER_COLLATION` 플래그가 걸려야 도는데 그 플래그는 `regu_var.hpp:170` 선언 외에 어디서도 설정되지 않는다(rg 전수) → 죽은 코드, 삭제. (2) STDDEV/VARIANCE 행값→DOUBLE(query_aggregate.cpp 658·2043): 분석 함수 누산기 설정(`qexec_setup_analytic_accumulator`)은 이미 `operand_coercion.conv[1]`(인자 타입→DOUBLE, IMPLICIT) 을 두지만 집계 누산기 설정(`qexec_setup_aggregate_accumulators` 3928)은 value_dom 만 둔다 → 같은 변환기를 두고 행은 `tp_value_convert`. (3) MEDIAN/PERCENTILE 행값→agg_domain(1359): 설정이 `value_dom` 을 정할 때 인자 타입(`qexec_node_operand_type`)에서 변환기를 함께 찾아 둔다. (4) 보간 정렬 비교(list_file.c 7255·7257): `cmp_dom` 을 정하는 `query_executor.c:22237` 이 `col_dom`(문자열)→`cmp_dom` 변환기를 SUBKEY_INFO 에 함께 두고 비교는 `tp_value_convert` 두 번. (5) SYS_CONNECT_BY_PATH 는 함수가 만든 문자열의 재캐스트 — 결과 문자열의 codeset/collation 생성 방식을 보고 결정. (6) 실행당 상수(키 리밋·LIMIT/상한·LEAD/LAG offset·NTH_VALUE·NTILE)·INSERT 기본값·`btree_coerce_key` 는 3차.
- 2026-10-12 C3a 구현(커밋 `90d409ca3`): (1) 타입 변형 플랜의 루트 XASL 에 `XASL_TYPED_BIND_PLAN`(bit 27; `do_mark_typed_bind_plan` 이 5개 루트에 표시, query_dump 출력) → 서버 `plan->typed`. (2) 서명이 캐스트 뒤 값으로 **모든 위치**를 덮음(기대 도메인 건너뛰기 삭제; 도메인으로 캐스트된 NULL 은 그 타입 토큰 → NULL 변형 안 늚; 도메인 없는 NULL 만 `n`). (3) `pt_make_regu_hostvar`: 타입 변형의 사용자 바인드는 기대 도메인이 있어도 값의 도메인(CHAR/VARCHAR 그대로, 캐스트된 NULL 은 기대 도메인 유지); 문자열 LEAVE 는 캐스트가 collation 을 고정하지 않는 위치에만. (4) `domain_compare_side`: 타입 변형의 고정 POS 쪽 = `DOMAIN_SIDE_KNOWN`(키 = 항목 도메인 + COLLATE; 변환이 필요하면 기존대로 실행당 1회 변환의 늦은 바인딩 비교로 남음). (5) C4 검사가 타입 변형에서는 `CONSUMER_CONVERTS` 항목까지 검사. NULL 값은 비교 메서드 앞에서 답하므로(`eval_compare_resolved`) KNOWN 쪽의 NULL 안전. 키(DOMAIN_KEY_CONSTANT)·고정 피연산자 위의 컴파일 VARIABLE 노드(`? + 1` 류)는 아직 실행당 확정 — C3 다음 단계(측정 뒤).

