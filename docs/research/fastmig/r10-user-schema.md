# R10 — 11.2 user schema 도입: 11.2 미만 출발의 이름 재작성·소유자 매핑·classname 조회 (#511, map #472)

기준: **D** = develop `5b1867174` (`~/dev/cubrid-worktree/develop`). 릴리스 선: **10.2** `416bb667c`, **11.0** `44ea22369`, **11.1** `e0e4f7a84`, **11.2** `baf1d297d`, **11.3** `8acbed10e`, **11.4** `46212adcd` (모두 `origin/release/<ver>`).
인용은 `파일:줄@선`이다. 앞선 결정은 인용만 한다: R3(클래스 레코드, `research/fastmig-r3-class-repr`), R4(카탈로그 재생성, `research/fastmig-r4-catalog-tables`), R5(최소 파일, `research/fastmig-r5-min-files`), R7(텍스트·스트림, `research/fastmig-r7-xasl-streams`).
이번 조사는 정적 판독만 했다. 서버나 SA 유틸리티는 실행하지 않았다. 런타임 확인이 필요한 항목에는 [VERIFY]를 붙였다. 길이 산술로 얻은 값에는 "(계산)"을 붙였다.

## 1. 결론

1. user schema는 CBRD-23844 `14742376f` (#3488, 2022-04-07)에서 들어왔다. 11.2·11.3·11.4에는 있고 10.2·11.0·11.1에는 없다 (`git merge-base --is-ancestor`). 디스크 호환 레벨은 10.2 `10.15f`, 11.0·11.1 `11.0f`, 11.2·11.3 `11.2f`다 (release_string.c:102@10.2, :101@11.0, :103@11.1/11.2).
2. develop의 클래스 이름은 사용자 클래스면 `소문자(owner).이름`이고 시스템 클래스면 `이름` 그대로다. 소유자를 바꿀 때 엔진이 이 규칙으로 이름을 다시 만든다: owner를 `sm_downcase_name`으로 내리고 `"%s.%s"`로 붙인다 (authenticate_access_class.cpp:158,170@D). 시스템 클래스는 건너뛴다 (:139-150@D). serial·trigger도 같은 규칙이다 (authenticate_owner.cpp:188-214, :392-398@D). SP는 11.4부터 같은 규칙을 따른다 (`SP_ATTR_UNIQUE_NAME` 첫 등장 `1ea4a86e0` #5438, CBRD-25184. 11.4에만 있다).
3. 11.2 미만에서는 같은 이름을 서로 다른 소유자가 가질 수 **없다**. 클래스 이름→OID 해시의 키가 이름 하나뿐이다 (`mht_create ("Memory hash Classname to OID"…)` locator_sr.c:277@10.2). serial은 `name`이 PK다 (boot_cl.c:3240,3360@10.2). SP는 `sp_name`이 UNIQUE다 (boot_cl.c:3058,3124@10.2). trigger는 이름으로 찾는다 (trigger_manager.c:3122@10.2). 따라서 `owner.` 접두는 단사 사상이다. 접두를 붙인 뒤 이름이 충돌하는 일은 없다.
4. 이름은 11.2 미만에서도 소문자로 저장됐다. 클래스·trigger·serial·SP 모두 `sm_downcase_name`/`intl_identifier_lower`를 거친다 (trigger_manager.c:315@10.2, execute_statement.c:1207@10.2, jsp_cl.c:932@10.2). 사용자 이름은 대문자로 저장된다 (authenticate.c:1195@10.2). 접두는 그 이름을 소문자로 바꿔 붙인다.
5. **길이**: 11.2 미만의 식별자 상한은 254B다. 렉서가 그보다 긴 이름을 잘라낸다 (csql_lexer.l:1270-1290@10.2). develop은 클래스·뷰·trigger·serial 이름이 223B 이상이면 거부한다 (parser_support.c:10987-10994@D, 매뉴얼 identifier.rst "Table 222"). 사용자 이름 상한은 두 선 모두 31B다 (`DB_MAX_USER_LENGTH 32`, dbtype_def.h:499@10.2, :556@D). 그래서 223..254B인 이름은 엔진 경로(loaddb)로도 옮길 수 없다. 도구는 사전 검사에서 거부한다. 222B 이하라면 `owner.name` ≤ 31+1+222 = 254B (계산)이므로 넘치지 않는다.
6. develop은 이름에 점(`.`)을 허용하지 않는다. 클래스·trigger·serial은 `*_without_dot` 문법 규칙으로 막는다 (`14742376f`, csql_grammar.y:20624-20646@D). 사용자는 `CREATE USER identifier_without_dot`로 막는다 (:2856@D). 11.2 미만은 `[a.b]` 같은 구분 식별자를 허용했다 (CREATE USER `identifier` grammar:2850@10.2). 점이 든 이름은 사전 검사에서 거부한다. `sm_user_specified_name`은 점이 하나뿐이라고 가정한다 (schema_manager.c:2238-2243@D의 assert).
7. **엔진 기준 경로**는 `unloaddb`(<11.2) → `loaddb -u dba --no-user-specified-name`(develop)이다 (매뉴얼 migration.inc:545-557). 이 경로에서 loaddb는 DBA로 `CREATE`하고(`dba.x`), 이어서 `change_owner`가 `owner.x`로 이름을 바꾼다. 클래스를 찾지 못하면 `[unique_name] … WHERE [class_name]=… AND [owner].[name] != …` 쿼리로 다른 소유자의 같은 이름을 찾는다 (locator_cl.c:3161-3185@D, execute_statement.c:20781@D, CBRD-24372 `f12f4b040` #3636, CBRD-26374 `19335d675` #6677). 도구가 맞춰야 할 결과는 "각 객체가 `소문자(source owner).이름`을 갖는 것"이다.
8. **이름 참조 텍스트는 다시 써야 한다.** 뷰 query spec은 뷰 소유자 권한으로 컴파일된다 (`AU_SET_USER (owner)` view_transform.c:8788@D). trigger condition/action은 trigger 소유자 권한으로 컴파일된다 (trigger_manager.c:5052@D). 이 문맥에서 한정자 없는 `[t]`는 `owner.t`로 풀린다 (`sm_user_specified_name` schema_manager.c:2214@D). 그래서 다른 소유자의 클래스나 serial을 참조하는 11.2 미만 텍스트는 develop에서 깨진다. 파티션 `pexpr` `"SELECT … FROM [t]"`는 `"[owner.t]"`가 돼야 한다 (execute_schema.c:16396@D. rename 경로가 이 형식을 가정한다, :5752-5756@D).
9. **classname ehash는 다시 만들 필요가 없다.** `BOOT_DB_PARM.classname_table`은 createdb 때 만들어지기만 한다. 이후 읽거나 쓰는 곳이 없다 (D 전체 `git grep classname_table` 3곳: boot_sr.c:128,4990,5056. 10.2는 `/* TODO - not used */` boot_sr.c:112-114@10.2). 이름→OID 조회는 부팅 때 root 클래스 힙을 훑어 `or_class_name`으로 메모리 해시를 채운다 (`locator_initialize` locator_sr.c:245-352@D). 따라서 클래스 레코드의 이름만 바꾸면 조회가 맞는다. 원본 볼륨에 이미 있는 ehash 파일은 그대로 둔다.
10. **판정**: 10.2·11.0·11.1 → develop에서는 모든 사용자 클래스 레코드를 이름 재기록 때문에 transform해야 한다 (레코드 길이가 `len(owner)+1`만큼 는다). serial·trigger·SP 행은 R4 재생성 때 `unique_name`을 채운다. 뷰·trigger·파티션 텍스트는 다시 쓴다. 사전 거부 조건은 §5에 모았다. 11.2·11.3 → develop에서 남는 것은 SP(`unique_name` 없음)와 SP 참조 텍스트뿐이다.

## 2. 이름이 사는 자리 (11.2 미만 → develop)

### 2.1 클래스 객체 (root 힙 레코드, R3 표 2.2)

| 영역 | 10.2 / 11.0 / 11.1 | develop | 처리 | 근거 |
|---|---|---|---|---|
| var idx 0 `name` (사용자 클래스) | `t` (소문자, ≤254B) | `owner.t` (전체 소문자) | **재기록**: `lower(owner이름) + "." + name` | authenticate_access_class.cpp:158-178@D; `14742376f` #3488 |
| var idx 0 `name` (시스템 클래스) | `db_class` 등 | 접두 없음 | 카탈로그 재생성(R4)으로 develop 정의를 쓴다 | :139-150@D, schema_system_catalog.cpp:40-125@D |
| 파티션 하위 클래스 `name` | `t__p__p0` | `owner.t__p__p0` | 재기록 (부모와 같은 owner) | execute_schema.c:5117@D, :3937@10.2 |
| partition 하위구조 `pname` | 접미사만 (`p0`) | 접미사만 | 그대로 | execute_schema.c:16347@D (`parts.name.original`), :5002@D |
| partition 하위구조 `pexpr` (부모만) | `SELECT <expr> FROM [t]` | `SELECT <expr> FROM [owner.t]` | **재기록** (한 토큰 치환) | execute_schema.c:14755@10.2, :16396@D |
| var idx 12 `query_spec` (뷰) | `… from [t] [t]` 한정자 없음 | 한정 이름이 `[owner.t]` 한 토큰으로 인쇄됨 | **재기록** (§4) | add_query_to_virtual_class execute_schema.c:9392-9405@D, pt_append_name parse_tree_cl.c:5823-5847@D |
| 속성 `auto_increment` 연결 | 로드 때 `"%s_ai_%s"`(class, attr)로 찾는다 | 로드 때 `set_auto_increment_serial_name(unique_name, attr)`로 찾는다 | serial 쪽 `unique_name`을 develop 식으로 맞춘다 (§2.2) | transform_cl.c:4163@10.2, :4190-4210@D |
| 제약 이름 (`pk_t_c` 등) | 클래스 이름만 들어 있다 | 기본 이름 생성도 한정자를 뺀 이름을 쓴다 | 그대로 | `sm_default_constraint_name` schema_manager.c:14300@D |
| owner OID (fixed @152, R3) | `db_user` 행 | `_db_user` 행 | R3·R4 재매핑. **이름 접두의 출처** | R3 표 2.1 |

### 2.2 카탈로그 행 (R4 재생성 대상)

| 테이블 | 10.2 / 11.0 / 11.1 | 11.2 / 11.3 | develop | 처리 |
|---|---|---|---|---|
| `_db_class` | `class_name` | `unique_name` + `class_name` (`14742376f`, 인덱스 `i__db_class_unique_name` boot_cl.c:2008@11.2) | 같음 (install.cpp:443-496@D) | 클래스 객체에서 재생성(R4). `unique_name` = §2.1 이름 |
| `_db_query_spec.spec` | 클래스 객체 query_spec 사본 | 〃 | 〃 | 재기록한 텍스트에서 재생성 |
| `_db_partition` `pname`/`pexpr` | 접미사 / 클래스 객체 사본 | 〃 | 〃 | 재생성 |
| `_db_index.index_name` | 제약 이름 | 〃 | 〃 | 그대로 |
| serial `db_serial`→`_db_serial` | `name`(PK), `class_name`, `att_name` (boot_cl.c:3244,3318,3324@10.2) | `unique_name`(PK `pk_db_serial_unique_name`) + `name` | 같음 (install.cpp:1025-1046@D) | `unique_name = lower(owner).name`, `name` 유지. `class_name`은 **한정자 없는** 클래스 이름 (execute_statement.c:994@D) |
| AUTO_INCREMENT serial | `t_ai_c` (최대 513B, `AUTO_INCREMENT_SERIAL_NAME_MAX_LENGTH` transform.h:180@10.2) | `owner.t_ai_c` | `len(t)+4+len(c) < 223`이면 `owner.t_ai_c`, 아니면 md5 형식 (transform.c:667-729@D, CBRD-26841 `217ea8c44` #7230) | develop 식으로 다시 계산한다. owner = **클래스 소유자** (`au_change_serial_owner(…, by_class_owner_change=true)` authenticate_owner.cpp:191-214@D) |
| trigger `db_trigger`→`_db_trigger` | `name` | `unique_name` + `name` | 같음 | `unique_name = lower(owner).name`. condition/action 텍스트는 §4 |
| `_db_stored_procedure` | `sp_name` (UNIQUE) | `sp_name` (11.2·11.3도 같음, boot_cl.c:3094-3098@11.3) | `unique_name`(PK, varchar(255)) + `sp_name` (install.cpp:917-941@D) | `unique_name = lower(owner).sp_name`. 11.2·11.3 출발에도 적용 |
| `_db_synonym`, `_db_server` | 없음 | `_db_synonym` 있음 (CBRD-23845 `540916ef6` #3541) | 있음 | 11.2 미만에서는 옮길 행이 없다 |
| `_db_user.name` | 대문자 | 대문자 | 대문자 | 그대로. 접두에만 소문자로 쓴다 |

### 2.3 길이·문자 규칙

| 항목 | 10.2 / 11.0 / 11.1 | develop | 근거 |
|---|---|---|---|
| 식별자 최대 | 254B (렉서가 잘라냄) | 렉서 상한 255+10, 문법 오류 ≥255 (CBRD-26891 `6ba952241` #7556) | csql_lexer.l:1016-1290@10.2, csql_lexer.l:40,1098@D |
| 클래스·뷰·trigger·serial 이름 (owner 제외) | 254B | **222B** | parser_support.c:10987@D, 매뉴얼 identifier.rst:118-144 |
| 사용자 이름 | 31B | 31B | dbtype_def.h:499@10.2, :556@D |
| `unique_name` 전체 | — | ≤ 254B (31+1+222, 계산). 버퍼 `DB_MAX_IDENTIFIER_LENGTH`=255 | locator_sr.c:304@D assert |
| 파티션 하위 클래스 전체 이름 | `< 255B` (execute_schema.c:3937-3940@10.2) | `owner.t__p__p` 전체 + NUL ≤ 223 → **≤ 222B, owner 포함** (계산) | execute_schema.c:4847,5101-5106@D (`class_name` = `entity_name.original`, `pt_set_user_specified_name` 뒤) [VERIFY] |
| SP `unique_name` | — | varchar(255) | install.cpp:917@D. `len(owner)+1+len(sp) ≤ 254B` (계산) |
| 점(`.`) | 구분 식별자로 허용 | 클래스·trigger·serial·사용자 이름 모두 금지 | csql_grammar.y:20624-20646, 2856@D |

## 3. 소유자 매핑 규칙

| 대상 | 규칙 | 근거 |
|---|---|---|
| 사용자 클래스 (DBA 소유 포함) | `lower(_db_user.name of class owner) + "." + name`. DBA 소유는 `dba.t`, PUBLIC 소유는 `public.t` | authenticate_access_class.cpp:152-170@D, 매뉴얼 user_schema.rst:52-70 |
| 시스템 클래스 (`SM_CLASSFLAG_SYSTEM`) | 접두하지 않는다. develop 카탈로그로 교체한다 (R4) | :139-150@D |
| 파티션 하위 클래스 | 부모의 owner. 엔진도 owner를 바꿀 때 하위까지 함께 바꾼다 | authenticate_owner.cpp:480-521@D |
| AUTO_INCREMENT serial | 클래스 owner. serial 행의 owner와 다르면 클래스 owner를 따른다 (엔진 loaddb 경로가 그렇게 만든다) | authenticate_access_class.cpp:119-131@D |
| 일반 serial, trigger, SP | 각 행의 `owner` | authenticate_owner.cpp:71-292, 302-423@D |
| 소유자 = 사용자 이름에 점, 또는 `INFORMATION_SCHEMA` | 거부 (§5) | csql_grammar.y:2856@D, R4 §F (develop이 시스템 사용자 `INFORMATION_SCHEMA`를 만든다) |

## 4. 이름 참조 텍스트 재작성

| 텍스트 | 컴파일 문맥 (develop) | 11.2 미만 텍스트를 그대로 두면 | 재작성 규칙 |
|---|---|---|---|
| 뷰 query spec (클래스 객체 idx 12 + `_db_query_spec.spec`) | `mq_virtual_queries`가 `AU_SET_USER (owner)` 뒤에 `mq_translate_subqueries`를 부르고, 그 안에서 `parser_parse_string`과 `pt_compile`을 한다 (view_transform.c:8788, 8399-8420@D) | 뷰 owner와 같은 owner의 클래스만 맞게 풀린다. 다른 owner의 클래스는 `ER_LC_UNKNOWN_CLASSNAME` | 시스템 클래스가 아닌 클래스 참조를 모두 `[owner.t]`로 바꾼다. develop이 새로 만든 뷰와 같은 형태다 |
| trigger condition/action (`_db_trigger.condition`, `action_definition`) | `execute_activity`가 `AU_SET_USER (trigger->owner)`를 하고 `compile_trigger_activity`를 부른다 (trigger_manager.c:5052, 4739, 4941@D) | 위와 같다 | 위와 같다. serial 참조(`s.next_value`, `serial_next_value(s)`)도 `pt_set_user_specified_name`이 한정하는 대상이므로 `owner.s`로 바꾼다 (parser_support.c:10788-10807@D) |
| 파티션 `pexpr` | `semantic_check.c:6650`에서 현재 사용자로 파싱한다. rename(execute_schema.c:5752)은 두 번째 `[` 뒤를 테이블 이름으로 본다 | 현재 사용자가 owner가 아니면 실패한다 | `FROM [t]` → `FROM [owner.t]` |
| 필터 `pred_string`, 함수 `expr_str` | `"SELECT 1 FROM [%s] WHERE %s"`로 조립한다 (execute_schema.c:15963@D) | — | G5(#486)로 제외한다 (DDL 출력). 텍스트 안에 클래스 이름이 있는지는 확인하지 않았다 |
| SP 호출 (뷰·trigger 텍스트 안) | `jsp_check_stored_procedure_name` → `sm_user_specified_name`이 현재 schema를 앞에 붙인다 (jsp_cl.cpp:1549-1570@D) | SP owner가 텍스트 owner와 다르면 실패한다 | `owner.sp`로 한정한다. 10.2~11.3 출발 모두 해당 |
| 시스템 클래스 참조 (`db_class` 등) | 접두하지 않은 이름은 시스템 클래스로 풀린다. owner를 붙이면 오류다 (parser_support.c:11015@D) | 그대로 맞다 | 바꾸지 않는다 |

loaddb 기준 경로가 내는 결과 [VERIFY]: 10.2 unloaddb는 클래스마다 `CREATE CLASS t` 바로 뒤에 `change_owner`를 출력하고, query spec은 모든 클래스를 만든 **뒤**에 출력한다 (unload_schema.c emit_schema:1055-1194@10.2). 그래서 뷰 spec을 컴파일할 때는 대상 클래스가 이미 `owner.t`다. 이때 compat 조회로 찾은 이름이 `info.name.original`에 들어간다 (name_resolution.c:7095-7101@D). 이 이름이 그대로 `[owner.t]`로 인쇄돼 저장될 것으로 본다.
trigger는 다르다. `get_activity_info`가 의미 검사 **전에** 텍스트를 인쇄한다 (execute_statement.c:7194-7196@D). 그러면 `pt_set_user_specified_name`이 붙인 DBA 접두(`dba.t2`)가 텍스트에 남을 수 있다. 그 경우 엔진 경로가 오히려 깨진 trigger를 남긴다. 따라서 도구의 기준은 엔진 텍스트의 바이트가 아니라 **의미**(각 참조가 원래 객체로 풀리는 것)로 잡는다.

## 5. 사전 거부 조건 (11.2 미만 출발)

| # | 조건 | 이유 | 근거 |
|---|---|---|---|
| P1 | 사용자 클래스·뷰·trigger·serial 이름 > 222B | develop 파서가 223B 이상 이름을 거부한다. loaddb도 실패한다 | parser_support.c:10987@D |
| P2 | 파티션 하위 클래스 `len(owner)+1+len(t)+5+len(p)` > 222B | `ER_PARTITION_TABLE_NAME_OVERFLOW` | execute_schema.c:5101-5106@D [VERIFY] |
| P3 | 이름이나 사용자 이름에 `.`가 있다 | develop 문법이 금지한다. `sm_user_specified_name`은 점이 하나라고 가정한다 | csql_grammar.y:20633@D, schema_manager.c:2240@D |
| P4 | 사용자 클래스 이름이 develop 시스템 클래스·vclass 이름과 같다. 10.2 기준 후보: `_db_authorization _db_global_tran _db_ha_apply_info _db_histogram _db_password _db_serial _db_server _db_stored_procedure_code _db_synonym _db_trigger _db_user db_histogram db_server db_synonym dual` (`dual`은 11.0·11.1에서는 이미 시스템이라 제외) | 접두 없는 이름은 시스템 클래스로 풀린다. owner를 붙여 쓰면 오류다. 그래서 그 사용자 테이블에 접근할 수 없다. 11.2 미만은 이름으로 예약하지 않았다 (`sm_is_system_class`는 플래그만 본다, schema_manager.c:2964@10.2) | schema_system_catalog.cpp:40-125@D, parser_support.c:11011-11018@D; 목록은 `#define CT(V)_*_NAME` 대조 (계산) |
| P5 | 사용자 이름 `INFORMATION_SCHEMA` | develop의 시스템 사용자와 겹친다 | R4 §F, authenticate_context.cpp:984-1008@D |
| P6 | SP `len(owner)+1+len(sp_name)` > 254B | `_db_stored_procedure.unique_name varchar(255)` | install.cpp:917@D (계산) |

## 6. classname 조회 경로 (develop)

| 단계 | 저장 위치 | 마이그레이션 영향 | 근거 |
|---|---|---|---|
| 부팅 | `boot_find_root_heap` → root 힙(`BOOT_DB_PARM.rootclass_hfid`) 전 레코드를 순회한다. `or_class_name`(var idx 0)을 키로 메모리 해시 `locator_Mht_classnames`를 채운다 | 레코드 이름을 바꾸면 자동으로 반영된다. 영속 해시가 없다 | locator_sr.c:274-330@D (10.2·11.0·11.1·11.2·11.3·11.4 모두 같은 구조, `or_class_name (&peek)` :304@10.2, :303@11.1, :307@11.4) |
| `BOOT_DB_PARM.classname_table` (EHID) | createdb 때 `xehash_create`로 빈 ehash를 만든다 | 쓰는 곳이 없으므로 원본 파일을 그대로 둔다. **numerable 파일을 새로 만들 필요가 없다** | boot_sr.c:128,4990,5056@D; boot_sr.c:112-114@10.2 |
| 클라이언트 `sm_find_class`/`locator_find_class` | 서버 메모리 해시에 이름을 묻는다 | 없음 | locator_cl.c:3147-3188@D |
| `_db_class.unique_name` 인덱스, `_db_serial` PK, `_db_stored_procedure` PK | 카탈로그 B-tree | R4 재생성과 R6 재빌드로 만든다 | install.cpp:495,941,1045@D |
| trigger 이름 조회 | `trigger_table_find`가 `db_root.triggers` 객체의 `unique_name`을 본다 | `_db_trigger` 행 재생성으로 충분하다 | trigger_manager.c:4250-4300@D |

## 7. 버전쌍별 판정 (develop 도착)

| 쌍 | 이름 관련 등급 | 해야 할 일 |
|---|---|---|
| 10.2 → develop | **transform** (모든 사용자 클래스 레코드) + 카탈로그 재생성 + 텍스트 재작성 | §2.1 이름·pexpr·query_spec 재기록. §2.2 serial·trigger·SP `unique_name`. AUTO_INCREMENT 이름은 develop 식으로 다시 계산. §4 텍스트 한정. §5 P1~P6 (P4 후보에 `dual` 포함) |
| 11.0 → develop | 위와 같음 | 위와 같다. P4 후보에서 `dual`만 빠진다 (11.0부터 시스템) |
| 11.1 → develop | 위와 같음 | 11.0과 같다 (`14742376f` 없음, 렉서·카탈로그 정의 동일) |
| 11.2 / 11.3 → develop | 클래스 이름은 **as-is** (이미 `owner.t`). SP 행만 재생성 | SP `unique_name` 생성, 텍스트 안 SP 호출 한정, P2(develop 파티션 222B 규칙은 develop 전용 `217ea8c44`이므로 11.2~11.4 원본에 223~254B 하위 클래스가 있을 수 있다), P6. AUTO_INCREMENT md5 규칙은 R4 R11(11.4)과 같다 |
| 11.4 → develop | R4 범위 그대로 | P2만 추가로 확인 [VERIFY] |

## 8. 남은 질문

### 티켓으로 쓸 수 있는 질문

1. **[task] 11.2 미만 엔진 기준 결과 실측**: T4의 10.2·11.0·11.1 기준 DB에 다음을 넣는다. 다른 owner의 테이블을 참조하는 뷰, 다른 owner의 테이블과 serial을 참조하는 trigger, 파티션 테이블, AUTO_INCREMENT 칼럼(긴 이름 1개 포함), Java SP와 그 SP를 부르는 뷰. 이 DB를 `unloaddb` → develop `loaddb -u dba --no-user-specified-name`으로 옮긴 뒤 `_db_class.unique_name`, `_db_query_spec.spec`, `_db_trigger.condition/action_definition`, `_db_partition.pexpr`, `_db_serial.unique_name/name/class_name`, `_db_stored_procedure.unique_name`을 덤프한다. §4의 [VERIFY] 두 가지를 판정한다: 뷰가 `[owner.t]`로 저장되는가, trigger에 `dba.` 접두가 남는가. 결과를 도구 출력과 비교할 기준 파일로 남긴다.
2. **[grilling] 뷰·trigger·SP 호출 텍스트 재작성 방식**: (a) Rust 토크나이저로 FROM/INTO/UPDATE/DELETE/ON 위치의 클래스 이름과 serial·SP 참조를 `[owner.x]`로 한정한다. (b) 텍스트 owner와 참조 owner가 모두 같으면 그대로 두고, 그 밖의 경우는 G5처럼 DDL 출력으로 미룬다. (c) 다른 owner를 참조하는 텍스트가 있으면 사전 거부한다. ➡️ 추천: (a). develop이 새로 만든 객체와 같은 형태가 나오고, 텍스트 안의 이름 위치는 SQL 문법의 일부라 범위가 닫혀 있다. 단 (a)가 실패하는 텍스트는 (b)로 떨어뜨린다.
3. **[task] 11.2 미만 출발 사전 검사 P1~P6 구현**: 원본 root 힙과 `db_user`/`db_serial`/`db_trigger`/`_db_stored_procedure` 행을 읽고 위반 객체 목록을 출력한다(쓰기 없음). P4 목록은 출발 버전의 시스템 클래스 플래그 집합과 develop `sm_system_class_names`의 차집합으로 계산한다.
4. **[research] 11.2 미만 시스템 클래스를 참조하던 사용자 텍스트의 의미 변화**: 10.2의 `db_user`/`db_serial`/`db_trigger`/`db_authorization`은 클래스였고, develop에서는 vclass이거나 `_db_*`로 바뀌었다. `db_password`, `db_authorizations`, `db_trig`, `_db_resolution`은 develop 목록에 없다. 이들을 참조하는 사용자 뷰·trigger가 develop에서 컴파일되는지, 칼럼이 같은지 표로 정리한다.

### 아직 흐릿한 것 (fog)

- 비ASCII 사용자 이름의 소문자화: 접두는 `sm_downcase_name`(`intl_identifier_lower`, DB 코드셋 의존)으로 만든다. Rust가 같은 결과를 내려면 코드셋별 대소문자 표가 필요할 수 있다. 실제로 비ASCII 사용자 이름을 쓰는 DB가 있는지 모른다.
- owner OID가 지워진 사용자를 가리키는 클래스(댕글링 owner)가 11.2 미만에 존재할 수 있는지 확인하지 않았다. 존재한다면 접두를 정할 수 없다.
- 필터 인덱스 `pred_string`과 함수 인덱스 `expr_str`에 클래스 이름이 들어가는지 확인하지 않았다. develop의 owner 변경 경로는 둘 다 다시 컴파일한다 (authenticate_access_class.cpp:191-232@D). G5로 DDL 출력 대상이라 이번 범위에서는 영향이 없다.
- 10.2의 `BOOT_DB_PARM`에는 `tde_keyinfo_hfid`가 없다 (boot_sr.c:107-127@10.2 vs :123-142@D). 이름 문제가 아니라 R8/R9 범위지만, 새 heap 파일이 필요한지는 아직 정하지 않았다.
- 11.2 release에는 `f12f4b040`(loaddb compat client type)이 없고, 11.3·11.4에만 있다. 11.2 원본을 다시 loaddb하는 경로는 이 지도의 대상이 아니라서 따지지 않았다.
