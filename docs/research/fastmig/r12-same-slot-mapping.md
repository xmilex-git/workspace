# R12 — 11.4 이하 출발의 같은 슬롯 시스템 행 매핑 정답 출처 (#521, map #472)

기준 브랜치 끝(엔진 `~/dev/cubrid-worktree/develop`, 읽기 전용, R8과 같은 끝):
- `@10.2` = `origin/release/10.2@416bb667c`, `@11.0` = `@44ea22369`, `@11.2` = `@baf1d297d`, `@11.3` = `@8acbed10e`, `@11.4` = `@46212adcd`
- `@D` = develop `5b1867174` (map과 R4·R8이 쓴 develop 끝, code-index 색인 대상). `origin/develop`은 그 뒤 `5cd1de888`까지 나갔다(§6 새 질문 1).
- 11.1은 R8 결론 9에 따라 11.0 열이 덮는다.

용어는 cubrid-fastmig `GLOSSARY.md`를 따른다: 출발 DB, 도착 DB, 카탈로그 재생성, 마이그레이션 결함, 기존 결함.

## 1. 질문

11.4 이하에서 출발하는 같은 슬롯(same-slot) 시스템 행은 도착 레이아웃으로 바꿔야 한다. 엔진의 공식 상향 경로는 다음 네 가지를 어떻게 채우는가? 그 답으로 R8 D8 매핑을 확정한다.

1. `db_authorization.grants` 원소 3개 → 4개(`type` 추가)
2. `_db_stored_procedure.target` → `target_class` / `target_method` 분리 (`unique_name`, `pkg_name`, `is_system_generated`, `directive` 포함)
3. `_db_stored_procedure_args.sp_name` → `sp_of` 연결
4. `db_serial.att_name` → `attr_name`

## 2. 결론

1. **≤11.3 → 11.4와 ≤11.4 → develop 모두, 엔진의 공식 상향 경로는 "출발 버전 `unloaddb` → 도착 버전 `loaddb`" 하나뿐이다.** 제자리(in-place) 변환기는 없다.
   - 11.4의 `migrate.c`는 9.1→9.2 볼륨 헤더 변환기다(`V9_1_LEVEL`/`V9_2_LEVEL`, src/executables/migrate.c:48-49,432@11.4). 빌드 대상도 아니었고, develop은 이것을 지웠다(`95521a550` #7776 커밋 메시지).
   - 11.4는 디스크 레벨이 다르면 무조건 호환 불가다. 규칙 표가 비어 있다(release_string.c:105,272-275,301-308@11.4).
   - develop의 `cubrid upgradedb`(CBRD-26459 `9ee8bac8b` #7773)는 metadata version 0(11.5.0 이전에 만든 DB)을 거부한다(system_metadata_version.h:25-26,32@D, util_sa.c:5712-5714@D). 그래서 10.2..11.4 출발 DB 어느 것도 이 경로로 올릴 수 없다.
   - 따라서 "공식 경로가 쓰는 값"은 **출발 unloaddb가 내보내는 DDL**을 **도착 엔진의 DDL 실행 코드**가 해석해서 쓰는 값이다. 행 값을 그대로 복사하지 않는다.
2. 필드별 판정(상세 §4):

| 필드 | 해당 출발 | 공식 경로가 쓰는 값 | 값의 출처 | fastmig 규칙 (develop 도착 = 11.4 도착) |
|---|---|---|---|---|
| grants `type` | 10.2..11.3 | `DB_OBJECT_CLASS` = 0 | 문장 종류(GRANT … ON 클래스). 행 아님 | 원소마다 앞에 정수 0을 붙인다. 순서는 유지한다 |
| grants `grantor` | 10.2..11.3 | **클래스 owner** (DBA로 load하면 모든 grant가 owner로 모인다) | 도착 `au_compare_grantor_and_return`. 행 아님 | **결정 필요(§5 질문 A)**. 추천: DBA/owner 그룹 grantor만 owner로 바꾸고 같은 (class, owner) 원소와 cache를 OR로 합친다 |
| SP `unique_name` | 10.2..11.3 | `lower(owner.name) + "." + sp_name` | `change_sp_owner`가 owner **사용자 행**의 이름으로 만든다 | 같은 식. owner OID → `db_user.name`을 읽는다 |
| SP `target_class`/`target_method` | 10.2..11.3 | 도착 `sp_split_target_signature(target)` | 원본 `target` 문자열 | 같은 함수를 Rust로 옮겨 적용. 길이 상한은 도착별로 다르다(11.4: method 1024, develop: 4096) |
| SP `pkg_name` | 10.2..11.3 | NULL | DDL에 없음 | NULL |
| SP `is_system_generated` | 10.2..11.3 | 0 | `sp_info` 기본값 | 0 |
| SP `directive` | 10.2..11.3 | 0 (`RIGHTS_OWNER`, NOT DETERMINISTIC) | 문법 기본값(DDL에 AUTHID 없음) | 0 |
| SP `lang` | 10.2..11.3 | 1 (`SP_LANG_JAVA`) | — | 그대로(값이 같다) |
| args `sp_of` | 10.2..11.3 | 부모 SP 행 OID | `sp_add_stored_procedure_internal`이 SP 행을 만든 뒤 각 arg 행에 기록 | 부모 SP 행의 `args` 시퀀스를 뒤집어 얻는다. `sp_name`은 교차 확인에만 쓴다 |
| args `is_system_generated`/`default_value`/`is_optional` | 10.2..11.3 | 0 / NULL / 0 | ≤11.3 unloaddb가 DEFAULT를 내보내지 않는다 | 0 / NULL / 0 |
| serial `attr_name` | 10.2..11.3 | 소문자 칼럼 이름 | CREATE TABLE … AUTO_INCREMENT의 칼럼 정의 | `att_name` 값을 그대로 옮긴다(같은 위치·같은 타입) |
| 신규 builtin SP 7개 (`public.dbms_output.*`) | 10.2..11.3 | createdb가 넣는다 | `sp_builtin_install` | 도착 createdb와 같은 행 7개 + arg 행 7개를 추가한다(R8 D8에 빠져 있었다) |

3. **11.4 출발**은 위 네 필드가 이미 도착 형식이다(grants 4원소, SP 분리, `sp_of`, `attr_name` — R8 결론 6). 11.4 → develop 차이(클래스 이름 `_db_serial`·`_db_authorization`, SP의 `sql_data_access`·시각 칼럼, serial `start_val` 등)는 R4 규칙(R9~R11) 그대로다. 이 문서는 바꾸지 않는다.
4. **develop 도착과 11.4 도착(T12)의 차이**는 이 네 필드에서 두 가지뿐이다. (a) `target_method` 상한(1024 vs 4096)과 그에 따른 축약 여부, (b) 11.4 도착이면 R4의 11.4→develop 단계를 건너뛴다. grants 형식, `sp_of`, `attr_name`, `unique_name` 식, `directive` 기본값은 두 도착이 같다.

## 3. 버전별 레이아웃

| 항목 | 10.2 / 11.0 / 11.2 / 11.3 | 11.4 | develop (`@D`) |
|---|---|---|---|
| grants 원소 | 3개 `{class, grantor, cache}` (authenticate.c:131-134@10.2, :132@11.3) | 4개 `{type, class, grantor, cache}` (authenticate_grant.hpp:66-71@11.4) | 4개, 11.4와 같음 (authenticate_grant.hpp:66-71@D). 클래스 이름은 `_db_authorization` (R4) |
| grants 원소를 쓰는 곳 | `add_grant_entry (grants, class_mop, Au_user)` — grantor = 로그인 사용자 (authenticate.c:4676@10.2, :4747@11.3) | `add_grant_entry (grants, DB_OBJECT_CLASS, class_mop, grantor)`, SP는 `DB_OBJECT_PROCEDURE` (authenticate_grant.cpp:289,445,1173-1193@11.4) | 같음 (authenticate_grant.cpp:1165-1185@D) |
| `DB_OBJECT_TYPE` | 없음 | CLASS=0, TRIGGER=1, SERIAL=2, SERVER=3, SYNONYM=4, PROCEDURE=5 (dbtype_def.h:492-498@11.4) | 같은 값 (dbtype_def.h:506-512@D) |
| `_db_stored_procedure` | `sp_name, sp_type, return_type, arg_count, args, lang, target varchar(4096), owner, comment`, UNIQUE(`sp_name`) (boot_cl.c:3089-3160@11.3. 10.2·11.0·11.2와 함수 본문이 공백까지 같다) | `unique_name, sp_name, sp_type, return_type, arg_count, args, lang, pkg_name, is_system_generated, directive, target_class varchar(1024), target_method varchar(1024), owner, comment`, PK(`unique_name`) (schema_system_catalog_install.cpp:828-863@11.4, SP_ATTR_TARGET_METHOD_LEN schema_system_catalog_constants.h:95@11.4) | 11.4 + `sql_data_access`, `created_time`, `updated_time`, `target_method` varchar(4096) (install.cpp:914-951@D, constants.h:100@D) |
| `_db_stored_procedure_args` | `sp_name, index_of, arg_name, data_type, mode, comment`, INDEX(`sp_name`) (boot_cl.c:3189-3233@11.3) | `sp_of, index_of, is_system_generated, arg_name, data_type, mode, default_value varchar(255), is_optional, comment`, INDEX(`sp_of`) (install.cpp:866-896@11.4) | 같은 칼럼, `default_value` varchar(`DB_MAX_DEFAULT_EXPR_LENGTH`) (install.cpp:954-973@D) |
| `db_serial` 해당 칼럼 | `att_name string` (boot_cl.c:3324@10.2, :3321@11.0, :3376@11.2, :3367@11.3) | `attr_name string`, 같은 자리(`class_name` 다음, `cached_num` 앞) (install.cpp:970-971@11.4) | `_db_serial.attr_name` (R4 §2) |
| 이름 변경 커밋 | — | `att_name`→`attr_name` CBRD-25356 `b85c07b27` #5346, SP/grants CBRD-25184 `1ea4a86e0` #5438. 둘 다 11.3에 없다(`git merge-base --is-ancestor` 확인) | — |
| builtin SP | 없음 (`dbms_output` 문자열이 11.3 `src`에 0건) | `public.dbms_output.{enable, disable, put, put_line, new_line, get_line, get_lines}` 7개, arg 7개, owner PUBLIC, lang PL/CSQL, `is_system_generated`=1 (sp_catalog.cpp:82-267@11.4, 호출 boot_cl.c:576@11.4) | 같은 7개 (sp_catalog.cpp:87-101,283@D, boot_cl.c:1079@D) |

## 4. 근거 — 공식 경로가 실제로 쓰는 값

### 4.1 공식 경로는 unloaddb → loaddb뿐이다

- 11.4 `migrate.c`는 `check_and_fix_compat_level`에서 `db_compatibility == V9_1_LEVEL`만 다룬다(migrate.c:231-270@11.4). `main`도 `rel_disk_compatible () != V9_2_LEVEL`이면 멈춘다(:432@11.4). develop은 이 파일을 지웠고, 커밋 메시지가 "not registered as a build target"이라고 적는다(`95521a550` #7776).
- 11.4 엔진은 DB 레벨이 자기 레벨과 다르면 규칙 표를 찾고, 표가 비어 있으므로 `REL_NOT_COMPATIBLE`이다(release_string.c:272-275, 301-308@11.4). develop도 같다(release_string.c:105,274,293@D).
- develop `upgradedb`는 `current_version == 0`이면 `UPGRADEDB_MSG_NOT_UPGRADABLE`로 끝난다(util_sa.c:5712-5714@D). 버전 0은 "11.5.0 이전에 만든 DB"다(system_metadata_version.h:25-26@D).
- 따라서 공식 결과 = 출발 `unloaddb`의 schema 출력 + 도착 `loaddb -u dba`의 DDL 실행. 매뉴얼 경로는 R10 결론 7(migration.inc:545-557)을 따른다.

### 4.2 grants

출발 unloaddb가 내보내는 것 (10.2와 11.3이 같다):
- `au_export_grants`는 클래스마다 모든 사용자의 `grants`를 훑는다. 그 클래스를 가리키는 원소만 모은다(`build_class_grant_list` authenticate.c:8353-8439@11.3).
- `class_grant_loop`가 owner에서 시작하는 권한 사슬 순서로 문장을 낸다(:8548-8614@11.3). owner에서 이어지지 않는 grant는 문장이 아니라 주석 `/* … */`로만 남는다(:8650-8664@11.3).
- 문장은 `GRANT <type> ON [owner].[class] TO [user] [WITH GRANT OPTION];`이다(:8492-8516@11.3, 10.2 :7681). **grantor는 내보내지 않는다.**

도착(11.4)이 그 문장을 실행할 때 쓰는 값:
- `au_grant`는 `au_compare_grantor_and_return`로 grantor를 정한다(authenticate_grant.cpp:205@11.4). 로그인 사용자가 DBA 그룹이거나 owner 그룹이면 grantor = **클래스 owner**다(:1944-1950@11.4). 그 밖이면 로그인 사용자가 grant option을 가졌을 때 그 사용자다(:1956-1990@11.4).
- `find_grant_entry (grants, class_mop, grantor)`로 같은 (class, grantor) 원소를 찾는다. 있으면 cache에 OR하고, 없으면 `add_grant_entry (grants, DB_OBJECT_CLASS, class_mop, grantor)`로 새로 만든다(:227, 279-291@11.4). 새 원소의 cache는 0으로 시작한 뒤 덮어쓴다(:1189-1190@11.4).
- `add_grant_entry`는 `type` 자리에 `db_make_int ((int) obj_type)`를 쓴다(:1180-1181@11.4). develop도 같다(:1172-1173@D).
- loaddb는 `-u dba`로 schema를 실행한다. 그래서 공식 결과에서는 **모든 grant 원소의 grantor가 클래스 owner로 모이고**, 한 (grantee, class)에 원소가 하나다. 출발에서 grantor가 DBA나 제3 사용자(grant option 보유자)였던 정보는 사라진다.

≤11.3 원소의 실제 값:
- ≤11.3 `au_grant`는 grantor 자리에 **로그인 사용자**(`Au_user`)를 쓴다(authenticate.c:4686, 4747@11.3; 10.2 :4676). 그래서 DBA가 다른 사용자의 클래스에 GRANT한 원소는 grantor = DBA다.
- ≤11.3에는 SP·serial·synonym에 대한 grant가 없다. `add_grant_entry`의 유일한 호출이 `au_grant`(클래스)다(authenticate.c:3966,4747@11.3). 그래서 ≤11.3의 모든 원소는 `type = DB_OBJECT_CLASS(0)`이 맞다. 뷰, 파티션 하위 클래스도 CLASS다(dbtype_def.h:492 주석 "TABLE, VIEW"@11.4).

읽을 때 정리 규칙(출발·도착 공통):
- `get_grants (auth, &grants, filter=1)`는 grantor가 지워졌으면 grantor를 클래스 owner로 바꾼다. owner 원소가 이미 있으면 cache를 OR로 합치고 현재 원소를 지운다. 클래스까지 지워졌으면 원소를 지운다(authenticate.c:4018-4170@11.3, authenticate_grant.cpp:1311-@11.4, :1303,1413,1422@D).

**11.4/develop에서 grantor를 그대로 옮길 때의 결과(추론, [VERIFY] V1)**: 11.4의 `au_revoke`도 `au_compare_grantor_and_return`로 grantor를 owner로 정한 뒤 `find_grant_entry`로 찾는다. 찾지 못하면 `ER_AU_GRANT_NOT_FOUND`다(authenticate_grant.cpp:595-621@11.4). 그래서 ≤11.3에서 DBA가 준 원소(grantor = DBA, DBA ≠ owner)를 그대로 옮기면, 도착에서 DBA나 owner가 `REVOKE`를 해도 그 원소를 찾지 못한다. 11.4가 스스로는 만들지 않는 상태이므로 **마이그레이션 결함** 후보다. 이 grantor 결정 로직은 11.3에 없고 `1ea4a86e0`(#5438)으로 11.4 계열에 들어왔다(`git grep -c au_compare_grantor_and_return origin/release/11.3` = 0건).

### 4.3 `_db_stored_procedure` (target 분리, unique_name, 나머지 새 칼럼)

출발 unloaddb가 내보내는 것 (10.2와 11.3이 같은 모양이다):
- `CREATE PROCEDURE|FUNCTION <sp_name> (<args>) [RETURN <type>] AS LANGUAGE JAVA NAME '<target>' [COMMENT …];` (unload_schema.c:4339-4436@11.3, 10.2 :3279). `sp_name`은 한정자가 없다.
- DBA로 unload하면 이어서 `call [change_sp_owner]('<sp_name>', '<owner>') on class [db_root];`를 낸다(:4440-4444@11.3, 10.2 :3297).
- 인자는 `<arg_name> IN|OUT|INOUT <type> [COMMENT …]`만 낸다. DEFAULT는 없다(`emit_stored_procedure_args` :4269-4330@11.3).
- AUTHID와 DETERMINISTIC은 내보내지 않는다(위 함수 전체).

≤11.3 행의 실제 값:
- `sp_name` = `sm_downcase_name`한 이름(jsp_cl.c:928-937@11.3, :932@10.2). `target` = 사용자가 쓴 `java_method` 문자열 그대로(jsp_cl.c:1096-1097@11.3, :1087@10.2, :1076@11.0, :1096@11.2). `owner` = 만든 사용자(:1104-1105@11.3). `lang` = `SP_LANG_JAVA`(1) 고정(:1089@11.3).

도착(11.4) `jsp_create_stored_procedure`가 쓰는 값 (jsp_cl.cpp:998-1250@11.4):
- `directive` = `jsp_map_pt_to_sp_authid (auth_id)`(:1025). 문법은 AUTHID가 없으면 `PT_AUTHID_OWNER`를 넣는다(csql_grammar.y:3119-3123, 3181-3185@11.4). 함수는 DETERMINISTIC이 없으면 `PT_NOT_DETERMINISTIC`이다(:3186-3190). 따라서 `directive = SP_DIRECTIVE_RIGHTS_OWNER = 0`(sp_catalog.hpp:128-130@11.4). develop 문법 기본값도 같다(csql_grammar.y:3001,3074,3079@D).
- `unique_name` = `jsp_check_stored_procedure_name`이 `sm_user_specified_name`으로 현재 사용자 이름을 붙인 값이다(:1033-1035, 1507-1528@11.4). load는 DBA로 하므로 처음에는 `dba.<sp_name>`이다.
- `sp_name` = `unique_name`에서 한정자를 뗀 값(:1042).
- `owner` = 이름에 한정자가 없으므로 `Au_user`(= DBA)(:1117-1123).
- `target_class`/`target_method` = `sp_split_target_signature (decl, …)`(:1157-1164). Java면 `decl` = `NAME '…'` 문자열이다.
- 인자: `default_value` NULL, `is_optional` 0(:1099-1103). `is_system_generated`는 `sp_arg_info` 기본값 false다(sp_catalog.hpp:108-118@11.4).
- SP 행: `pkg_name`은 비어 있으므로 값을 만들지 않는다. 직전 `pr_clear_value`가 `PRIM_SET_NULL`을 하므로 NULL이 들어간다(sp_catalog.cpp:423-437@11.4, object_primitive.c:2081@11.4). `is_system_generated` = 0(`sp_info` 기본값 sp_catalog.hpp:170@11.4, 쓰기 sp_catalog.cpp:444-445@11.4).
- 그 다음 `change_sp_owner`가 `unique_name`을 `sm_downcase_name (owner.name) + "." + sp_name`으로, `owner`를 원래 사용자로 바꾼다(authenticate_owner.cpp:526-579@11.4; develop :574-621@D). **`unique_name`은 행 밖의 값(owner가 가리키는 `db_user` 행의 `name`)에서 나온다.**

`sp_split_target_signature` (sp_catalog.cpp:971-1031@11.4, :991-1051@D, 두 본문이 같고 상수만 다르다):
- 마지막 `(` 와 마지막 `)`를 찾는다. 없으면 class/method 둘 다 빈 문자열이다(:975-983@11.4).
- `(` 앞부분에서 공백을 모두 지우고 마지막 `.`으로 자른다. 앞이 `target_class`, 뒤가 메서드 이름이다. `.`이 없으면 둘 다 빈 문자열이다(:985-997).
- `target_method` = 메서드 이름 + `(`부터 끝까지의 원문(인자 목록 안 공백과 ` return …`이 남는다)(:998).
- 그 길이가 `SP_ATTR_TARGET_METHOD_LEN`을 넘으면 인자 타입의 `java.lang.`/`java.math.`/`java.sql.`/`cubrid.sql.` 접두와 공백을 지우고, `return` 뒤 타입도 같은 식으로 줄인다(:1000-1030). 상한은 11.4가 1024(constants.h:95@11.4), develop이 4096(constants.h:100@D)이다.
- ≤11.3 `target`은 최대 4096자다(boot_cl.c:3135@11.3). 따라서 `target_method` ≤ 4096 − len(class) − 1 < 4096이다(계산). **develop 도착에서는 축약이 일어나지 않는다.** 11.4 도착에서는 1024자를 넘는 경우만 축약하고, 축약 뒤에도 1024자를 넘을 수 있다([VERIFY] V3).
- `target_class`는 두 도착 모두 varchar(1024)다(install.cpp:847@11.4, :931@D). 1024자를 넘는 클래스 이름은 사전 검사 대상이다(§5).

### 4.4 `_db_stored_procedure_args.sp_of`

- ≤11.3: arg 행은 `sp_name` = 부모 SP의 `sp_name`(소문자)을 갖는다(jsp_cl.c:1056 → :841-842@11.3). 부모 SP 행의 `args`는 arg 행 OID들의 시퀀스다(:1040-1075@11.3). `sp_name`은 UNIQUE이므로(boot_cl.c:3094,3160@11.3) 이름으로 찾아도 하나로 정해진다.
- 11.4 공식 경로: `sp_add_stored_procedure_internal`이 arg 행을 먼저 만들고(sp_of 비움), SP 행을 만든 뒤, 각 arg 행을 다시 열어 `sp_of = SP 행 OID`를 쓴다(sp_catalog.cpp:460-506, 578-614@11.4). develop도 같다(sp_catalog.cpp:481-497, 598-636@D).
- fastmig 규칙: SP 행을 디코드해 `args` 시퀀스의 각 OID에 그 SP 행의 OID를 `sp_of`로 쓴다. 같은 슬롯을 유지하면 SP 행 OID가 바뀌지 않으므로 OID 재매핑은 없다. 카탈로그 힙을 새 페이지에 할당하는 경우는 R4 §6의 old→new 매핑을 쓴다. 어느 SP의 `args`에도 없는 arg 행(고아)은 공식 경로가 만들지 않으므로 옮기지 않는다([VERIFY] V5로 존재 여부만 센다). `sp_name`과 부모의 `sp_name`이 다르면 불일치로 보고한다.

### 4.5 `db_serial.att_name` → `attr_name`

- 값을 쓰는 곳은 같은 함수다. `do_create_serial_internal`이 `att_name`이 있을 때 그대로 넣는다(execute_statement.c:807-815@11.3 → `SERIAL_ATTR_ATT_NAME`; :820@11.4 → `SERIAL_ATTR_ATTR_NAME`; :1007@D).
- 값은 AUTO_INCREMENT 칼럼 이름을 `sm_downcase_name`한 것이다(`do_create_auto_increment_serial` execute_statement.c:1816@10.2, :1886@11.3, :1902@11.4, :2181@D). 칼럼 이름을 바꾸면 `do_update_auto_increment_serial_on_rename`이 같은 규칙으로 고친다(:832,893@10.2, :882,952@11.3, :891,961@11.4, :1084,1149@D).
- 공식 경로에서는 출발 행의 값을 옮기지 않는다. 도착이 CREATE TABLE … AUTO_INCREMENT를 실행할 때 칼럼 정의에서 다시 만든다(11.3 unloaddb는 AUTO_INCREMENT serial을 CREATE SERIAL로 내지 않는다. `where [class_name] is null and [att_name] is null` unload_schema.c:697-704@11.3. 현재값은 `ALTER SERIAL … START WITH`로만 맞춘다 :1071-1090@11.3). 결과 값은 출발 `att_name`과 같은 문자열이다(두 버전 모두 소문자 칼럼 이름).
- 칼럼 자리와 타입이 같다(`string`, `class_name` 다음, boot_cl.c:3361-3367@11.3 ↔ install.cpp:970-971@11.4). 11.2/11.3 출발이면 `db_serial` 칼럼 집합이 11.4와 이름 하나만 다르다(boot_cl.c:3281-3390@11.3 ↔ install.cpp:941-979@11.4). 그래서 11.4 도착이면 행 값은 바뀌지 않는다. 레코드 바이트가 같은지는 repr id 처리에 달렸다([VERIFY] V6).
- 같은 테이블의 `unique_name`(≤11.1에 없음)·`class_name`·`name` 처리는 R10 §2.2, develop의 `start_val`·NUMERIC 가변 길이·시각 칼럼은 R4 R10 규칙이다. 이 문서는 바꾸지 않는다.

### 4.6 builtin SP 행 (R8 D8에 빠진 항목)

- 11.4와 develop의 createdb는 시스템 클래스를 다 만든 뒤 `sp_builtin_install`로 `_db_stored_procedure` 행 7개와 `_db_stored_procedure_args` 행 7개를 넣는다(boot_cl.c:574-577@11.4, :1079@D; 정의 sp_catalog.cpp:82-267@11.4, :87-@D).
- ≤11.3에는 이 행이 없다. 공식 경로에서는 도착 createdb가 이 행을 만든다. same-slot 복사에서는 출발 힙에 이 행이 없으므로 **도착 형식의 새 행으로 추가해야 한다**(owner = PUBLIC, `unique_name = "public.dbms_output.<name>"`, `pkg_name = "DBMS_OUTPUT"`, `lang` = PL/CSQL(0), `target_class = "com.cubrid.plcsql.builtin.DBMS_OUTPUT"`, `is_system_generated` = 1, arg 행도 `is_system_generated` = 1, `enable`의 인자는 default 20000).
- 출발에 사용자가 만든 `<owner>.enable` 같은 SP가 있어도 `unique_name`이 다르므로 충돌하지 않는다. 다만 ≤11.3에서 `dbms_output.x`라는 이름은 만들 수 없었다는 점은 확인하지 않았다(§6 질문 4).

## 5. fastmig에 대한 함의

### 5.1 D8 same-slot 행 매퍼 확정안 (`catalog/src/same_slot_rows.rs`, `system_classes.rs`)

순서는 `db_user`(이름 조회용) → SP → args → grants → serial이다.

1. **grants (10.2..11.3 출발, 두 도착 공통)**
   - 원소 `(class, grantor, cache)`마다 앞에 `INTEGER 0`(DB_OBJECT_CLASS)을 붙인다. 원소 순서는 그대로 둔다.
   - grantor 처리는 결정 질문 A(아래)를 따른다. 추천안을 적용하면 같은 (class, grantor) 원소가 둘 이상 생길 수 있고, 이때 cache를 OR로 합쳐 하나만 남긴다. 이것은 `get_grants`의 정리 규칙과 공식 경로의 `find_grant_entry` + OR가 하는 일과 같다.
   - 클래스가 지워진 원소는 버리고, grantor가 지워진 원소는 owner로 바꾼다. 도착 `get_grants`가 읽을 때 하는 일을 미리 한다. R4 C 규칙으로 `_db_auth`를 다시 만들 때 정리된 원소를 입력으로 쓰기 위해서다.
   - 시스템 클래스에 걸린 원소는 R4 R9 규칙대로 버리고, 도착 createdb의 grant 집합을 넣는다. 11.4 도착이면 11.4 createdb 집합을 넣는다. 11.4 집합에는 `db_authorization`에 대한 PUBLIC EXECUTE가 있다(authenticate_context.cpp:1029@11.4).
   - 시퀀스 길이가 3n에서 4n으로 늘어 레코드가 길어진다. 같은 슬롯에 들어가지 않으면 relocation이 필요하다(R4 레코드 재인코딩 경로).
2. **SP (10.2..11.3 출발)**: 행마다 다음을 만든다.
   - `unique_name = lower(owner→db_user.name) + "." + sp_name`. 소문자 변환은 `sm_downcase_name` 규칙을 따른다. 사용자 이름은 ASCII 대문자로 저장된다(R10 결론 4).
   - `target_class`/`target_method` = 도착 버전의 `sp_split_target_signature`를 바이트 단위로 옮긴 함수. 상한 상수는 도착별로 다르다.
   - `pkg_name` NULL, `is_system_generated` 0, `directive` 0. `sp_type`·`return_type`·`arg_count`·`args`·`lang`·`owner`·`comment`는 그대로 둔다.
   - develop 도착이면 R4 R11 규칙(`sql_data_access` −1, 시각 칼럼)을 이어서 적용한다.
   - 사전 검사: `target`에 `(`나 `.`이 없으면(빈 class/method가 된다), `target_class`가 1024자를 넘으면, 11.4 도착에서 축약 뒤 `target_method`가 1024자를 넘으면 거부한다.
3. **args**: `sp_of` = 부모 SP 행 OID(§4.4). `is_system_generated` 0, `default_value` NULL, `is_optional` 0. `index_of`·`arg_name`·`data_type`·`mode`·`comment`는 그대로 둔다. `sp_name` 칼럼은 버린다.
4. **serial**: `att_name` 값을 `attr_name` 자리로 옮긴다(값은 같다). 나머지는 R10/R4 규칙이다.
5. **builtin SP 행 추가**: 도착 버전의 `sp_builtin_init` 정의와 같은 SP 7행 + arg 7행. SP 행을 넣은 뒤 그 OID로 arg 행의 `sp_of`를 채운다.
6. **11.4 출발**: 이 문서의 1~5는 해당하지 않는다. R4 규칙만 적용한다.

### 5.2 결정 질문 A — grants의 grantor (1번 세션에 올릴 것)

- 공식 경로의 결과: 모든 grant의 grantor가 클래스 owner다. (class, grantee)마다 원소가 하나다. grant 사슬 정보(누가 누구에게 grant option으로 넘겼는지)는 사라진다.
- 옵션:
  - (a) 공식 경로와 같게: 모든 원소의 grantor를 클래스 owner로 바꾸고 cache를 합친다.
  - (b) 11.4가 같은 GRANT를 직접 실행했을 때와 같게: grantor가 DBA 그룹이거나 클래스 owner 그룹이면 owner로 바꾼다. 나머지(grant option으로 grant한 제3 사용자)는 그대로 둔다. 11.4 `au_compare_grantor_and_return`의 판정을 출발 시점 그룹 정보로 적용하는 것이다.
  - (c) 그대로 둔다. §4.2의 REVOKE 불가 상태가 남는다.
- ➡️ 추천: **(b)**. 도착 엔진이 만들 수 있는 상태만 남기면서 정보 손실은 가장 적다. REVOKE가 공식 경로와 같은 결과를 낸다. (a)는 제3 사용자 grantor가 자기가 준 권한을 REVOKE하지 못하게 바꾼다.
- 어느 쪽이든 `_db_auth` 재생성(R4 C)은 결정된 grantor로 한다.

### 5.3 티켓별 할 일

- **P2a #535 (11.3·11.2 → develop)**: §5.1의 1~5와 R4 규칙을 함께 적용한다. 질문 A가 정해지기 전에는 추천안 (b)로 구현하고 주석에 티켓 번호를 남긴다.
- **T12 #534 (11.3 이하 → 11.4)**: §5.1의 1~5를 적용하되 상한 상수와 builtin 정의는 11.4 것을 쓰고, R4의 11.4→develop 단계는 건너뛴다.
- **#528, #529** (이 티켓에 막힌 티켓): 이 문서가 정답 출처다. 공식 경로 결과와 비교하는 검증기는 grantor와 `created_time`류를 제외하고 비교해야 한다. grantor는 질문 A, 시각은 load 시각에 따라 달라진다.
- **R8 D8 표 수정**: builtin SP 행 추가를 넣는다. "args `sp_name`→`sp_of`"는 "부모 SP의 `args` 시퀀스에서 얻는다"로 바꾼다.

## 6. [VERIFY] 목록

| # | 주장 | 확인 probe | 기대값 |
|---|---|---|---|
| V1 | ≤11.3에서 DBA가 준 grant(grantor=DBA≠owner)를 grantor 그대로 11.4 형식으로 옮기면 도착에서 REVOKE가 `ER_AU_GRANT_NOT_FOUND`로 실패한다 | 11.3 DB: `CREATE USER u1; CREATE USER u2;` u1으로 `CREATE TABLE t(a int)`, DBA로 `GRANT SELECT ON u1.t TO u2`. 11.3에서 `SELECT grants FROM db_authorization WHERE owner.name='U2'`로 grantor가 DBA인지 본다. 같은 grants를 type 0만 붙여 옮긴 11.4 DB에서 DBA로 `REVOKE SELECT ON u1.t FROM u2` | 11.3 grantor = DBA. 11.4 REVOKE는 실패(-ER_AU_GRANT_NOT_FOUND). 비교용으로 11.3 unloaddb → 11.4 loaddb 결과의 grantor = U1이고 REVOKE는 성공 |
| V2 | 공식 경로 결과의 grants는 (class, grantee)마다 원소 하나, grantor = owner, type = 0 | 11.3 DB(owner u1, grant option 사슬 u1→u2→u3 포함)를 11.4/develop으로 unloaddb → `loaddb -u dba` 한 뒤 `SELECT owner.name, grants FROM db_authorization`(develop은 `_db_authorization`) | 모든 원소의 2번째 자리가 U1의 OID, 1번째가 0, u3 원소의 grantor도 U1 |
| V3 | 11.4 도착에서 1024자를 넘는 `target_method`가 축약 뒤에도 1024자를 넘으면 공식 경로가 실패하거나 잘린다 | 11.3에서 `target` 길이 ~1500자(인자 타입을 사용자 패키지로)인 Java SP를 만들고 11.4로 unloaddb → loaddb | loaddb가 오류를 내거나(사전 거부 근거) `target_method`가 잘린다. 어느 쪽인지 기록 |
| V4 | SP 행 값: `unique_name = lower(owner).sp_name`, `pkg_name` NULL, `is_system_generated` 0, `directive` 0, `target_method`의 공백·` return` 꼬리 보존 | 11.3 DB에 DBA가 아닌 사용자 소유 Java 함수(`NAME 'Foo.bar(java.lang.String, int) return java.lang.String'`)와 프로시저를 넣고 11.4·develop으로 unloaddb → loaddb. `SELECT * FROM _db_stored_procedure` | 표 §2의 값과 같다. `target_class`='Foo', `target_method`='bar(java.lang.String, int) return java.lang.String' |
| V5 | 정상 DB에는 고아 arg 행(어느 SP의 `args`에도 없는 행)이 없다 | 기준 DB(T4)의 10.2·11.0·11.2·11.3 각각에서 `SELECT count(*) FROM _db_stored_procedure_args a WHERE NOT EXISTS (SELECT 1 FROM _db_stored_procedure s WHERE s.sp_name = a.sp_name)` | 0 |
| V6 | 11.2/11.3 `db_serial` 행은 11.4 도착이면 값과 레이아웃이 같다(이름만 다르다) | 11.3과 11.4에서 같은 CREATE TABLE … AUTO_INCREMENT + CREATE SERIAL을 실행한 뒤 serial 힙 레코드를 덤프해(repr id 제외) 비교. Rust probe로 힙 레코드를 읽는다 | 고정부·가변부 바이트가 같다. 다르면 repr id와 칼럼 순서를 기록 |
| V7 | `sp_builtin_install`이 만드는 7+7 행이 도착 createdb와 같다 | 11.4·develop 새 DB에서 `SELECT unique_name, sp_name, pkg_name, lang, is_system_generated, directive, target_class, target_method FROM _db_stored_procedure WHERE is_system_generated = 1`과 args 덤프. 도구 출력과 집합 비교 | 7행/7행 일치 |
| V8 | ≤11.3 arg `data_type`은 unloaddb의 타입 이름 → 도착 `pt_type_enum_to_db`로 돌아와도 같은 값이다 | V4 DB에서 각 인자 타입(INTEGER, NUMERIC, STRING, SET, CURSOR 등)의 출발 `data_type`과 도착 `data_type`을 비교 | 모두 같다. 다르면 대응표를 만든다 |

## 7. 새 질문

지금 정확히 서술할 수 있는 것:
1. **develop 끝이 움직였다.** `origin/develop`은 `5b1867174..5cd1de888` 사이에 카탈로그를 다시 바꿨다. CBRD-27302 `5a3e7a14b`는 db_root·_db_user의 trigger 저장을 없앴고, CBRD-26842 `d93145bdb`는 카탈로그 정의 코드를 합쳤다. `CNT_CATCLS_OBJECTS`도 9에서 6으로 바뀌었다(schema_system_catalog_constants.h diff). R4의 develop 규칙을 새 끝에서 다시 확인해야 한다(research). fastmig가 어느 develop 커밋을 도착으로 고정하는지도 정해야 한다.
2. **결정 질문 A (grants grantor)**: §5.2. grilling 한 줄.
3. **≤11.3 Java SP의 실행 권한 의미 변화**: 공식 경로는 모든 이전 SP를 `RIGHTS_OWNER`로 만든다(§4.3). ≤11.3 Java SP가 서버 쪽 JDBC에서 호출자 권한으로 돌았다면, 이것은 엔진 공식 경로가 이미 갖는 의미 변화이고 fastmig는 따라가기만 한다. ≤11.3의 실행 권한 모델을 확인하는 research가 필요하다. 결과는 사용자에게 고지할지 정하는 데 쓴다.

아직 흐린 것:
4. ≤11.3에서 이름이 `dbms_output.`으로 시작하는 SP를 만들 수 있었는지. 만들 수 있었다면 도착 `jsp_check_stored_procedure_name`이 그 이름을 `public.dbms_output.*`로 바꿔 builtin과 충돌한다(jsp_cl.cpp:1515-1520@11.4). 사전 검사 후보다.
5. 사용자 테이블의 OBJECT 칼럼이 `_db_stored_procedure`·`_db_stored_procedure_args` 행을 가리키는 경우(R4 §8에서도 조사하지 않음).
