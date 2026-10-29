# R11 — 11.2 미만 시스템 클래스를 참조하는 사용자 텍스트의 develop 의미 (#519, map #472)

기준: **D** = `origin/develop` `5cd1de888`. **10.2** = `origin/release/10.2` `416bb667c`. 11.0·11.1·11.4는 `origin/release/<ver>`이다 (모두 `~/dev/cubrid-worktree/develop`).
인용 형식은 `파일:줄@선`이다. 앞선 조사는 인용만 한다: R10(`research/fastmig-r10-user-schema`), R4(`research/fastmig-r4-catalog-tables`), R7(`research/fastmig-r7-xasl-streams`), R8(`research/fastmig-r8-older-pairs`). 확정된 결정 G1(#481 pre-check)과 G7(#514)은 다시 열지 않는다. 이 문서는 사실과 판정 후보를 내고, G1과 다른 판정은 §7 새 질문으로 넘긴다.
이번 조사는 정적 판독만 했다. 서버와 DB는 쓰지 않았다. 실측이 필요한 주장에는 [VERIFY]를 붙였다. 소스에서 바로 읽지 않고 이어 붙인 결론에는 "추론"을 붙였다.

## 1. 질문

10.2(그리고 11.0·11.1)의 사용자 뷰 query spec과 trigger condition/action이 그 버전의 시스템 클래스·vclass를 참조한다. 이 텍스트는 develop에서 컴파일되는가? 칼럼과 의미는 같은가? 대상 클래스마다 develop 쪽 대응, 칼럼 차이, 판정(그대로 / 재작성 / plan pre-check 거부)을 낸다. R10의 owner 한정 재작성이 시스템 클래스 이름을 건너뛰어야 하는지도 정한다.

## 2. 결론

1. **이름 해석 규칙.** develop은 한정자 없는 이름이 develop 시스템 클래스·vclass 목록에 있으면 owner를 붙이지 않는다 (`sm_user_specified_name` schema_manager.c:2275@D, `pt_set_user_specified_name` parser_support.c:11893-11908@D). 목록에 없으면 `현재 schema.이름`으로 바꾼다. 그리고 **시스템 이름에 owner를 붙이면 오류**다: "It is not allowed to specify an owner in the system class name." (parser_support.c:11898@D). 그래서 R10 재작성은 develop 시스템 이름 목록(schema_system_catalog.cpp:40-125@D)에 있는 이름을 한정하면 안 된다. 10.2 시스템 이름 중 develop 목록에 없는 것(`db_password`, `db_authorizations`, `db_trig`)은 R10이 그대로 한정하면 `owner.db_password` 같은 없는 클래스가 된다. 따라서 **시스템 이름 사상(§5)을 R10 한정보다 먼저, 한 번의 토큰 패스에서** 적용해야 한다. 판단 기준은 "텍스트 이름이 출발 버전에서 시스템 클래스였는가"이다.
2. **이름 변경은 develop 전용이다.** `db_serial`·`db_ha_apply_info`·`db_trigger`(클래스)→`_db_*`, `db_trig`→`db_trigger`, `db_authorizations` 삭제는 1f1263217 #6443(CBRD-25862)에서 왔다. `db_user`·`db_password`·`db_authorization`→`_db_*`는 8ba543178 #6903에서 왔다. 둘 다 release/11.4의 조상이 아니다 (`git merge-base --is-ancestor`). 따라서 §4 판정의 이름 부분은 10.2뿐 아니라 **11.0~11.4 출발 전부**에 똑같이 적용된다. 10.2·11.0·11.1의 시스템 클래스 집합은 같다. 차이는 11.0이 `dual`과 `_db_class.tde_algorithm`·`db_class.tde_algorithm`을 더한 것뿐이다 (transform.h 이름 diff, boot_cl.c `boot_define_*` 칼럼 diff, 10.2↔11.0. 11.0↔11.1은 차이 0).
3. **`_db_resolution`과 `db_grant`는 10.2에서도 만들어지지 않았다.** 이름 상수만 있다 (transform.h:128@10.2, authenticate.c:111@10.2). 카탈로그 설치 목록(boot_cl.c:3958-3976@10.2)과 `au_install`(authenticate.c:8374-8378@10.2)에 없다. 그래서 이 이름을 참조하는 정상 텍스트는 있을 수 없다. 있다면 10.2에서 이미 깨진 텍스트이고, GLOSSARY의 기존 결함(pre-existing defect)이다.
4. **10.2에서 이 클래스를 읽을 수 있던 사용자.** PUBLIC에 SELECT가 있던 것은 `db_root`, `db_authorizations`, `db_user`, `db_authorization`(authenticate.c:8586-8590@10.2), `db_serial`(boot_cl.c:3402@10.2), `db_ha_apply_info`(:3644@10.2), 시스템 vclass 18개(:4087~:5361@10.2)다. `db_password`, `db_trigger`, `_db_*` 테이블에는 PUBLIC grant가 없다 (`define_trigger_classes` trigger_manager.c:7255-7361@10.2에 `au_grant`가 없다). 그래서 이 셋을 참조하는 뷰와 trigger는 DBA 그룹 소유이거나, 명시적으로 grant를 받은 owner의 것이다 (추론).
5. **develop에서 `_db_*` 테이블은 DBA와 `INFORMATION_SCHEMA`만 읽는다.** `make_authorization (Au_dba_user, {Au_information_schema_user}, AU_SELECT)` (schema_system_catalog_install.cpp:758,944@D). `_db_user`·`_db_authorization`도 같다 (authenticate_context.cpp:1015-1017@D. PUBLIC grant는 `db_root`뿐, :994@D). 뷰는 owner 권한으로 번역되고(view_transform.c:9419@D), trigger는 owner 권한으로 실행된다(trigger_manager.c:4564@D). 그래서 `_db_*`로 재작성하는 규칙은 **텍스트 owner가 DBA 그룹일 때만** 의미를 보존한다 (추론, [VERIFY] V2).
6. **판정 요약** (10.2 출발, 11.0·11.1 동일. 상세는 §4):

| 10.2 이름 (종류) | develop 대응 | 칼럼·의미 | R11 판정 | G1 현재 규칙 |
|---|---|---|---|---|
| `db_trig` (vclass) | `db_trigger` (vclass) | 10.2 칼럼 7개가 develop 11개에 모두 있다. 행 필터 의미도 같다 | **재작성** `db_trig`→`db_trigger` | 거부 |
| `db_trigger` (class) | `_db_trigger` (class). 같은 이름 `db_trigger`는 다른 vclass다 | develop vclass에는 `name`·`owner`·`condition`·`action_definition`·`status`·`priority`·`event`·`target_class`가 없다. `_db_trigger`는 10.2 칼럼을 모두 가진다 | **재작성** `db_trigger`→`_db_trigger` (owner가 DBA 그룹일 때. 10.2 PUBLIC grant 없음) | 경고 |
| `db_password` (class) | `_db_password` | `password` 유지. `created_time`·`updated_time`·`expire_time` 추가 | **재작성** `db_password`→`_db_password` (10.2에서 DBA 전용이었다) | 없음 (검사 누락) |
| `db_user` (class) | `_db_user` (class). `db_user`는 vclass | vclass: `password`·`authorization` 항상 NULL, `direct_groups`·`groups`가 이름 문자열 집합, 행이 현재 사용자·그룹으로 걸러진다, class method는 `find_user`·`login`뿐. `_db_user`: `triggers` 삭제(5a3e7a14b #7980), 나머지 같음 | owner가 DBA 그룹이고 `triggers`를 쓰지 않으면 **재작성** →`_db_user`. 아니면 **그대로 + 경고** | 경고 |
| `db_authorization` (class) | `_db_authorization`. `db_authorization`은 vclass | vclass: `owner`가 객체에서 문자열로 바뀜, 행 필터 | `db_user`와 같은 규칙 (→`_db_authorization`) | 없음 (검사 누락) |
| `db_serial` (class) | `_db_serial`. `db_serial`은 vclass | `att_name`→`attr_name`(b85c07b27 #5346, 11.4부터). vclass: `owner` 문자열, **AUTO_INCREMENT serial 행 제외**(`class_name IS NULL`) | owner가 DBA 그룹이고 `att_name`을 쓰지 않으면 **재작성** →`_db_serial`. `att_name`이 있으면 **거부**. owner가 DBA 그룹이 아니면 **그대로 + 경고** | 경고 |
| `db_authorizations` (class) | 없음 (1f1263217) | 속성 없음, method만, 인스턴스 0 | **거부** | 거부 |
| `db_root` (class) | `db_root` | `triggers` 삭제(5a3e7a14b #7980). 나머지와 class method는 같다 | `triggers`가 있으면 **거부**, 아니면 **그대로** | 없음 |
| `db_ha_apply_info` (class) | `db_ha_apply_info` (vclass, 같은 26칼럼, 필터 없음, PUBLIC SELECT) | 같다 | **그대로** | 없음 |
| `_db_auth` (class) | `_db_auth` | `class_of`→`object_type`+`object_of` (1ea4a86e0 #5438, 11.4부터) | **거부** (토큰 검사로 `class_of` 사용 여부를 가릴 수 없다) | 없음 |
| `_db_stored_procedure` | 같은 이름 | `target`→`target_class`+`target_method` (11.4부터) | **거부** | 없음 |
| `_db_stored_procedure_args` | 같은 이름 | `sp_name`→`sp_of`(OID) (11.4부터) | **거부** | 없음 |
| `db_auth` (vclass) | `db_auth` | `class_name`→`object_type`+`object_name` (11.4부터) | **그대로 + 경고** | 없음 |
| 나머지 `_db_*` 13개, vclass 15개 | 같은 이름 | develop 칼럼이 10.2 칼럼을 모두 포함한다(추가만) | **그대로** (`_db_class.is_system_class` 의미 변화는 경고, §4.4) | 없음 |
| `_db_resolution`, `db_grant` | 없음 | 10.2에도 클래스가 없었다 | 해당 없음 (기존 결함) | 없음 |

## 3. 근거: 이름 해석과 권한

| 주장 | 근거 |
|---|---|
| 한정자 없는 이름이 develop 시스템 이름이면 owner를 붙이지 않는다 | schema_manager.c:2224,2275@D (`sm_check_system_class_by_name`이면 `sm_downcase_name`만) |
| 파서도 같다. 시스템 이름에 owner가 있으면 오류다 (표의 case 5·6) | parser_support.c:11879-11908@D (오류 문자열 :11898) |
| develop 시스템 이름 목록 = 클래스 33개 + vclass 25개 + `INFORMATION_SCHEMA.*` 뷰 | schema_system_catalog.cpp:40-89 (클래스), :92-129 (vclass)@D, `sm_check_system_class_by_name` :138@D |
| 사용자가 시스템 이름으로 테이블·뷰를 만들 수 없다 (develop) | parser_support.c:11816@D |
| 10.2 시스템 클래스 이름 (테이블) | transform.h:120-145@10.2 (`CT_*`), authenticate.c:105-111@10.2 (`AU_*`), trigger_manager.c:131@10.2 (`TR_CLASS_NAME`) |
| 10.2 시스템 vclass 18개 | transform.h:148-165@10.2, 설치 목록 boot_cl.c:5398 부근 (`clist[]`)@10.2 |
| 10.2에서 실제로 만드는 테이블 | `catcls_class_install` boot_cl.c:3958-3976@10.2 (19개), `au_install` authenticate.c:8374-8378@10.2 (`db_root`·`db_user`·`db_password`·`db_authorization`·`db_authorizations`), `tr_install`→`define_trigger_classes` trigger_manager.c:7255@10.2 (`db_trigger`). `_db_resolution`·`db_grant`는 어디서도 만들지 않는다 (`git grep CT_RESOLUTION_NAME\|AU_GRANT_CLASS_NAME origin/release/10.2` = 정의, `IS_CATALOG_CLASS` 매크로 authenticate.c:160@10.2, unload_object.c:133 주석 "currently, not implemented"뿐) |
| develop 이름 상수 | schema_system_catalog_constants.h:28-84@D |
| 이름 변경 커밋과 릴리스 포함 여부 | 1f1263217 (2025-12-12, constants.h diff: `db_serial`·`db_ha_apply_info`·`db_trigger`→`_db_*`, `db_trig`→`db_trigger`, `CT_AUTHORIZATIONS_NAME` 삭제), 8ba543178 (2026-05-19, `db_user`·`db_password`·`db_authorization`→`_db_*`). 둘 다 release/11.4에 없다. release/11.2·11.3·11.4의 constants는 10.2와 같은 이름이다 |
| 10.2 PUBLIC grant | authenticate.c:8586-8590@10.2 (`db_root`, `db_authorizations`, `db_user`, `db_authorization`. 주석 "the password class cannot be read by anyone except the DBA" :8583-8584), boot_cl.c:3402 (`db_serial`), :3644 (`db_ha_apply_info`), :4087~:5361 (vclass 18개)@10.2 |
| 10.2 `db_trigger` 클래스에는 grant가 없다 | trigger_manager.c:7255-7361@10.2 (`dbt_create_class`…`dbt_finish_class`, `au_grant` 없음) |
| develop `_db_*` 테이블은 DBA·INFORMATION_SCHEMA만 읽는다 | schema_system_catalog_install.cpp:758 (`_db_trigger`), :944 (`_db_serial`)@D. `_db_user`·`_db_authorization`·`db_root`: authenticate_context.cpp:994, 1015-1017@D. R4 요약 G(11.4 시스템 클래스의 PUBLIC grant 중 develop에 없는 것은 삭제) |
| develop 시스템 vclass `db_trigger`·`db_serial`·`db_ha_apply_info`·`db_user`·`db_authorization`은 PUBLIC SELECT다 | schema_system_catalog_install.cpp:1545, 1662, 1703, 1763, 1782@D (`make_authorization (Au_dba_user, {Au_public_user}, …)`) |
| 뷰는 owner 권한으로, trigger는 owner 권한으로 컴파일·실행된다 | view_transform.c:9415-9419@D, trigger_manager.c:4564@D. 10.2도 같다 (view_transform.c:5834@10.2, trigger_manager.c:4979@10.2) |

## 4. 클래스별 상세

### 4.1 인증 클래스

| 10.2 | 10.2 칼럼 (authenticate.c@10.2) | develop | develop 칼럼 | 차이와 의미 |
|---|---|---|---|---|
| `db_root` | `triggers` sequence, `charset`, `lang`, `timezone_checksum` (:8404-8407). class method `add_user`…`change_sp_owner` (:8411-8422) | `db_root` (같은 이름, 시스템 클래스) | `charset`, `lang`, `timezone_checksum` (authenticate_context.cpp:330-332@D). class method 같음 (:336-347@D) | `triggers` 삭제: 5a3e7a14b #7980 (CBRD-27302, 2026-10-22). 그 밖은 같다 |
| `db_authorizations` | 속성 없음. class method `add_user`…`get_owner` (:8442-8452). 인스턴스를 만들지 않는다 (:8546은 `db_root` 객체 하나만 만든다) | 없음 | — | `FROM db_authorizations`는 10.2에서 늘 0행이었다. `CALL m() ON CLASS db_authorizations`는 같은 method를 가진 `db_root`로 바꿀 수 있다(추론). G1은 거부로 정했다 |
| `db_user` | `name` string, `id`, `password` (db_password 객체), `direct_groups`·`groups` set of db_user, `authorization` 객체, `triggers`, `comment` (:8468-8475). method `set_password`…, class method `add_user`, `drop_user`, `find_user`, `login` (:8477-8488) | `_db_user` (class) + `db_user` (vclass) | `_db_user`: `name` varchar(32), `id`, `password`, `direct_groups`·`groups` set of `_db_user`, `authorization`, `is_loginable`, `is_system_created`, `comment`, `created_time`, `updated_time` (authenticate_context.cpp:366-376@D). vclass: 같은 이름의 칼럼 11개, `password`·`authorization`은 `NULL`, `direct_groups`·`groups`는 이름 문자열 집합, `WHERE AUTH_CHECK_USER([u].[name])` (schema_system_catalog_install_query_spec.cpp:841-870@D, install.cpp:1731-1765@D). vclass class method는 `find_user`·`login`뿐 (install.cpp:1757-1758@D) | 10.2 텍스트가 한정자 없이 `db_user`를 쓰면 develop은 **vclass**로 푼다. `[u].[password].[password]`, `[g].[name]`(groups 원소 경로), `[u].[triggers]`, `CALL add_user(…) ON CLASS db_user`는 컴파일 실패다. `name`·`id`·`comment`만 쓰면 컴파일되지만, owner가 DBA 그룹이 아니면 행이 자기와 자기 그룹으로 줄어든다(10.2는 PUBLIC이 전체를 읽었다). `_db_user`로 바꾸면 `triggers`를 뺀 칼럼·경로·method가 10.2와 같다 |
| `db_password` | `password` (:8514). PUBLIC grant 없음 | `_db_password` | `password`, `created_time`, `updated_time`, `expire_time` (authenticate_context.cpp:415-418@D) | `db_password`는 develop 시스템 이름이 아니다. 그래서 `owner.db_password`로 풀려 없는 클래스가 된다 ([VERIFY] V6). `_db_password`로 바꾸면 칼럼 의미가 같다 |
| `db_authorization` | `owner` (db_user 객체), `grants` sequence (:8536-8537) | `_db_authorization` + vclass `db_authorization` | `_db_authorization`: `owner` (`_db_user` 객체), `grants` (authenticate_context.cpp:441-442@D). vclass: `owner` = `[a].[owner].[name]` 문자열, `grants`, `AUTH_CHECK_USER` 필터 (query_spec.cpp:874-890@D) | vclass로 풀리면 `[a].[owner].[name]` 경로가 깨진다(문자열에 경로 없음). 행도 걸러진다 |

### 4.2 trigger

| 10.2 | 10.2 칼럼 | develop | develop 칼럼 | 차이와 의미 |
|---|---|---|---|---|
| `db_trigger` (class) | `owner` db_user, `name`, `status`, `priority`, `event`, `target_class`, `target_attribute`, `target_class_attribute`, `condition_type`, `condition`, `condition_time`, `action_type`, `action_definition`, `action_time`, `comment` (trigger_manager.c:7269-7348@10.2. `TR_ATT_PROPERTIES` :147은 상수만 있고 속성으로 넣지 않는다) | `_db_trigger` (class). 이름 `db_trigger`는 develop에서 **vclass**다 | `_db_trigger`: `unique_name` + 10.2 칼럼 전부 + `created_time`, `updated_time` (install.cpp:727-760@D). vclass `db_trigger`: `trigger_name`, `owner_name`, `target_class_name`, `target_owner_name`, `target_attr_name`, `target_attr_type`, `action_type`, `action_time`, `comment`, `created_time`, `updated_time` (install.cpp:1523-1546@D) | 같은 이름이 다른 객체를 가리킨다. 10.2 칼럼 중 develop vclass에도 있는 것은 `action_type`·`action_time`·`comment` 셋뿐이다. 나머지를 쓰는 텍스트는 처음 쓸 때 실패한다. 11.4 출발도 같다(11.4의 `db_trigger`도 클래스, constants.h@11.4) |
| `db_trig` (vclass) | `trigger_name`, `target_class_name`, `target_attr_name`, `target_attr_type`, `action_type`, `action_time`, `comment` (boot_cl.c:4949-4957@10.2). 필터: DBA, owner·그룹, 대상 클래스 SELECT 권한 (:4985-4990@10.2) | `db_trigger` (vclass) | 위 11칼럼. 필터 `AUTH_CHECK_PRIVILEGE ([t].[owner].[name], [c].[class_of], 'SELECT')` (query_spec.cpp:551-580@D, 매크로 schema_system_metadata_query_spec.hpp:70-82@D) | 10.2 칼럼 7개가 모두 같은 이름·같은 식으로 있다(`CAST([t].[name] AS VARCHAR(255))`, `[c].[class_name]`). `_db_class.class_name`은 develop에서도 owner 없는 이름이다. 필터도 같은 조건(DBA / owner·그룹 / SELECT grant)이다. 그래서 이름만 바꾸면 같은 행·같은 값이 나온다 (추론, [VERIFY] V5) |

### 4.3 serial, HA

| 10.2 | 10.2 칼럼 | develop | develop 칼럼 | 차이와 의미 |
|---|---|---|---|---|
| `db_serial` (class) | `name`(PK), `owner` db_user, `current_val`, `increment_val`, `max_val`, `min_val`, `cyclic`, `started`, `class_name`, `att_name`, `cached_num`, `comment` (boot_cl.c:3244-3347@10.2) | `_db_serial` + vclass `db_serial` | `_db_serial`: `unique_name`, `name`, `owner` 객체, …, `start_val`, …, `attr_name`, … (install.cpp:909-946@D). vclass: 같은 이름 16칼럼, 단 `owner` = `[serial].[owner].[name]` 문자열, `WHERE [serial].[class_name] IS NULL` (query_spec.cpp:723-755, 필터 :750@D) | (1) `att_name`은 b85c07b27 #5346(11.4부터)에서 `attr_name`이 됐다. 이 칼럼을 쓰는 텍스트는 어느 쪽으로도 컴파일되지 않는다. (2) vclass는 AUTO_INCREMENT serial 행을 **뺀다**. 10.2 `db_serial`은 포함했다. 그래서 `class_name`·`att_name`을 보는 텍스트는 컴파일되더라도 빈 결과가 된다. (3) `[s].[owner].[name]` 경로는 vclass에서 실패한다. `_db_serial`로 바꾸면 (1)만 남는다 |
| `db_ha_apply_info` (class) | 26칼럼 (boot_cl.c:3419-3640@10.2) | `_db_ha_apply_info` + vclass `db_ha_apply_info` | 같은 26칼럼, 필터 없음, PUBLIC SELECT (install.cpp:951-1000, 1667-1703@D. query_spec.cpp:759-800@D) | 칼럼 이름·순서·행이 같다. 그대로 둬도 된다 |

### 4.4 카탈로그 테이블 `_db_*` (10.2 → develop, 같은 이름)

10.2 칼럼은 `boot_define_*` (boot_cl.c:1808-3946@10.2)에서, develop 칼럼은 `system_catalog_initializer::get_*` (install.cpp:375-1200@D)에서 뽑아 비교했다.

| 테이블 | 10.2에 있고 develop에 없는 칼럼 | develop 추가 | 판정 |
|---|---|---|---|
| `_db_class` | 없음 | `unique_name`, `tde_algorithm`(11.0), `statistics_strategy`, `flags`, `created_time`, `updated_time`, `checked_time` | 그대로. 단 **의미 변화**: develop은 `is_system_class`에 bit0만 남기고 나머지 플래그를 `flags`로 옮긴다 (catalog_class.c:1042-1045@D). 10.2 `db_class` 정의가 쓰던 `MOD([c].[is_system_class] / 8, 2)`(reuse_oid, boot_cl.c:4064@10.2) 같은 식은 develop에서 늘 0이 된다. 토큰 검사로는 찾을 수 없으므로 경고 문구에 넣는다 |
| `_db_attribute`, `_db_domain`, `_db_method`, `_db_meth_sig`, `_db_meth_arg`, `_db_meth_file`, `_db_index_key`, `_db_data_type`, `_db_collation`, `_db_charset` | 없음 | `_db_attribute.flags` 등 | 그대로 |
| `_db_query_spec` | 없음 | `invalidated_time` | 그대로 |
| `_db_index` | 없음 (`status`·`comment` 순서만 바뀜, R4) | FK·`index_type`·`options`·시각 | 그대로 |
| `_db_partition` | 없음 | `class_partition_type` | 그대로 |
| `_db_auth` | `class_of` | `object_type`, `object_of`, 시각 (1ea4a86e0, 11.4부터) | 거부 |
| `_db_stored_procedure` | `target` | `unique_name`, `pkg_name`, `is_system_generated`, `directive`, `target_class`, `target_method`, `sql_data_access`, 시각 (sp_constants.hpp:45-61@D) | 거부 |
| `_db_stored_procedure_args` | `sp_name` | `sp_of`, `is_system_generated`, `default_value`, `is_optional` (sp_constants.hpp:82-90@D) | 거부 |

`_db_*`는 10.2에서도 PUBLIC grant가 없었다(§3). 그래서 이 텍스트들은 DBA 그룹 소유다(추론).

### 4.5 시스템 vclass (같은 이름)

10.2 칼럼은 `boot_define_view_*`의 `COLUMN columns[]`(boot_cl.c:4023-5360@10.2), develop은 `get_view_*`(install.cpp:1200-1880@D)에서 뽑았다.

| vclass | 10.2 칼럼 중 develop에 없는 것 | 판정 |
|---|---|---|
| `db_class`, `db_direct_super_class`, `db_vclass`, `db_attribute`, `db_attr_setdomain_elm`, `db_method`, `db_meth_arg`, `db_meth_arg_setdomain_elm`, `db_meth_file`, `db_index`, `db_index_key`, `db_partition`, `db_stored_procedure`, `db_stored_procedure_args`, `db_collation` | 없음 (develop은 `owner_name`류, 시각, `tde_algorithm` 등을 더할 뿐) | 그대로 |
| `db_charset` | 없음 (10.2 `CT_DBCHARSET_*` 4칼럼 = develop 상수 4칼럼) | 그대로 |
| `db_auth` | `class_name` (→ `object_type`, `object_name`, 11.4부터. install.cpp@11.4 1700-1706, 11.3은 `class_name` boot_cl.c:5923@11.3) | 그대로 + 경고 |
| `db_trig` | (§4.2) | 재작성 → `db_trigger` |

값의 미세 차이: `db_class.class_type`의 기타 값이 10.2 `'UNKNOW'`(boot_cl.c:4062@10.2)에서 develop `'UNKNOWN'`(query_spec.cpp:42@D)으로 바뀌었다. 시스템 vclass의 `class_name`·`target_class_name`류는 develop에서도 owner 없는 이름이고 owner는 `*_owner_name` 칼럼에 따로 있다. 11.2 미만 DB에는 이름 중복이 없었으므로(R10 결론 3) 이름 조건으로 걸러 오던 텍스트의 결과는 같다 (추론).

### 4.6 저장 텍스트의 모양

10.2 뷰 spec은 의미 검사를 마친 트리를 `parser_print_tree_with_quotes`로 인쇄한 문자열이다 (`add_query_to_virtual_class` es_102 = execute_schema.c@10.2, R10 §2.1과 같은 경로). 그래서 `*`가 칼럼 목록으로 펼쳐지고, 이름은 `[db_user]`처럼 대괄호로 싸이며, FROM 항은 `[db_user] [db_user]`(클래스 이름 + 별칭)로 인쇄될 것이다 (추론, [VERIFY] V1). 재작성은 **FROM 항의 클래스 이름 토큰만** 바꾸고 별칭 토큰은 둔다. 그래야 `[db_user].[name]` 같은 칼럼 참조를 건드리지 않는다. 결과 예: `… from [_db_user] [db_user]`. 별칭이 develop 시스템 vclass 이름과 같아도 별칭은 클래스 이름 해석을 거치지 않는다 (추론, [VERIFY] V4). trigger 텍스트는 사용자가 쓴 그대로 저장되므로 별칭이 없을 수 있다. 이때 `db_user.name` 같은 클래스 이름 한정 칼럼 참조가 있으면 클래스 토큰만 바꾸면 깨진다. 이 경우는 재작성하지 않고 그대로 + 경고로 둔다.

## 5. fastmig에 대한 함의

1. **시스템 이름 사상 표 (`plan`·텍스트 재작성 공용)**. 출발 버전의 시스템 이름 → develop 이름. 이 표는 R10의 owner 한정보다 먼저, 같은 토큰 패스에서 쓴다. 표에 있거나 develop 시스템 목록에 있는 토큰은 owner로 한정하지 않는다.
   - 항상 바꾼다: `db_trig`→`db_trigger`, `db_password`→`_db_password`.
   - 텍스트 owner가 DBA 그룹일 때만 바꾼다: `db_trigger`→`_db_trigger`, `db_user`→`_db_user`, `db_authorization`→`_db_authorization`, `db_serial`→`_db_serial`. 사상은 동시에 한다(`db_trig`→`db_trigger`와 `db_trigger`→`_db_trigger`가 이어 붙지 않게).
   - 바꾸지 않는다: `db_root`, `db_ha_apply_info`, 같은 이름 `_db_*`·vclass.
   - 거부 토큰: `db_authorizations`, `_db_auth`, `_db_stored_procedure`, `_db_stored_procedure_args`, 그리고 `db_serial`과 함께 쓰인 `att_name`, `db_root`·`db_user`와 함께 쓰인 `triggers`.
   - 경고 토큰: 바꾸지 않고 남긴 `db_user`·`db_authorization`·`db_serial`(행 필터·문자열 칼럼), `db_auth`(`class_name` 삭제), `_db_class`(`is_system_class` bit 의미).
   - 이 표는 출발 버전 의존이다. 이름 변경이 develop 전용이므로 11.0~11.4 출발도 같은 표를 쓴다. `_db_auth`·`_db_stored_procedure*`·`db_auth` 행은 11.4 출발에는 해당하지 않는다(11.4에서 이미 새 칼럼).
2. **cubrid-fastmig `crates/plan/src/system_view_refs.rs`** (fastmig `14079bf`): 지금 `REMOVED = [db_trig, db_authorizations]`, `CHANGED = [db_user, db_trigger, db_serial]`이다. `db_password`(develop에 없는 이름)와 `db_authorization`(같은 이름, 다른 칼럼)이 빠져 있다. 10.2 출발에는 위 거부·경고 토큰도 더해야 한다. 이것은 G1 결정의 원칙(없는 이름은 거부, 칼럼이 바뀐 이름은 경고)을 그대로 따른 목록 보충이다. 재작성 도입 여부는 §7 Q1이다.
3. **R10 재작성 (G8 #517)**: 한정 대상에서 (a) develop 시스템 이름, (b) 위 사상 표의 출발 이름을 뺀다. 판단은 "그 토큰이 출발 카탈로그에서 시스템 클래스(`SM_CLASSFLAG_SYSTEM`)를 가리켰는가"로 한다. 10.2에서 사용자 클래스 이름이 develop 시스템 이름과 겹치는 경우는 R10 P4가 이미 거부한다.
4. **DBA 그룹 판정**: 텍스트 owner(뷰 클래스 owner, trigger `owner`)가 `DBA`이거나 `groups`에 DBA가 있는지를 출발 `db_user` 행에서 읽는다. owner 행은 R4/G2가 같은 슬롯으로 이미 읽는다.
5. **verify**: 재작성한 텍스트가 develop에서 컴파일되는지는 Rust가 판정할 수 없다 (R7 결론 3). 엔진 실측 티켓(아래 V1~V8)의 결과를 기준 파일로 남긴다.

## 6. [VERIFY]

| # | 주장 | 확인 probe | 기대값 |
|---|---|---|---|
| V1 | 10.2 뷰 spec은 `*`가 펼쳐지고 `[db_user] [db_user]` 꼴로 저장된다 | 10.2 install에서 `CREATE VIEW v1 AS SELECT * FROM db_user; CREATE VIEW v2 AS SELECT name FROM db_trig;` 뒤 `SELECT spec FROM _db_query_spec WHERE class_of.class_name IN ('v1','v2')` | 칼럼 목록이 펼쳐진 문자열, FROM 항이 `[db_user] [db_user]` |
| V2 | develop에서 `_db_user`를 참조하는 뷰는 DBA 소유면 전체 행을 내고, 일반 사용자 소유면 권한 오류다 | develop SA에서 DBA로 `CREATE VIEW dv AS SELECT name FROM _db_user`, 사용자 `u1`로 `CREATE VIEW u1v AS SELECT name FROM _db_user`(또는 DBA가 만든 뒤 owner 변경) 후 각각 SELECT | dv: 사용자 수만큼 행. u1v: `ER_AU_SELECT_FAILURE`류 |
| V3 | 10.2 일반 사용자는 `db_trigger`·`db_password`를 참조하는 뷰를 만들거나 쓸 수 없다 | 10.2에서 `u1`로 `CREATE VIEW x AS SELECT name FROM db_trigger`와 `… FROM db_password` | 둘 다 SELECT 권한 오류 |
| V4 | 별칭이 시스템 vclass 이름과 같아도 컴파일된다 | develop에서 `SELECT [db_user].[name] FROM [_db_user] [db_user]` | 정상 결과 |
| V5 | `db_trig`→`db_trigger` 재작성은 같은 행을 낸다 | 10.2 기준 DB(T4)에 trigger 2개(owner 다름)를 두고 각 사용자로 `SELECT trigger_name, target_class_name, target_attr_name, target_attr_type, action_type, action_time, comment FROM db_trig`. develop 이관본에서 같은 칼럼으로 `FROM db_trigger` | 사용자마다 집합 비교 차이 0 |
| V6 | develop에서 `db_password` 참조는 `owner.db_password`로 풀려 실패한다 | develop에서 DBA로 `SELECT password FROM db_password` | "Unknown class \"dba.db_password\""류 오류 |
| V7 | 10.2 trigger 생성 때 action 텍스트를 컴파일하는가 (없는 클래스 `_db_resolution` 참조 trigger가 존재할 수 있는가) | 10.2에서 `CREATE TRIGGER t AFTER INSERT ON x EXECUTE INSERT INTO _db_resolution VALUES (1)` | 생성이 실패하면 기존 결함 경로 없음. 성공하면 그런 trigger가 있을 수 있음 |
| V8 | develop `db_serial` vclass는 AUTO_INCREMENT serial을 뺀다 | develop에서 `CREATE TABLE t (a INT AUTO_INCREMENT)` 뒤 `SELECT COUNT(*) FROM db_serial WHERE class_name IS NOT NULL` vs `FROM _db_serial` | 0 vs 1 |

## 7. 새 질문

### 지금 정확히 서술할 수 있는 것

- **Q1 [grilling] G1 시스템 이름 검사를 재작성으로 바꿀 것인가.** G1은 `db_trig`를 거부하고 `db_trigger`를 경고한다. 이 조사로 (a) `db_trig`→`db_trigger`는 칼럼·필터가 같은 이름 바꾸기이고, (b) `db_trigger`(클래스) 참조는 develop vclass에 칼럼이 거의 없어 경고로 남기면 처음 쓸 때 실패하며, (c) 10.2·11.4에서 `db_trigger`·`db_password`는 DBA만 읽을 수 있어 `_db_*` 재작성의 권한 조건을 늘 만족한다는 것이 드러났다. 선택지: (1) G1 그대로(거부/경고) + 목록 보충(§5-2). (2) §5-1 사상 표로 재작성하고, 재작성할 수 없는 경우만 거부/경고. ➡️ 추천: (2). 재작성은 FROM 항의 이름 토큰 하나 바꾸기이고 G8(#517)의 토크나이저를 같이 쓴다. 11.4 출발(P1)에도 같은 규칙이 걸린다.
- **Q2 [task] `system_view_refs.rs` 목록 보충**: Q1과 무관하게 `db_password`를 REMOVED에, `db_authorization`을 CHANGED에 넣는다(11.4 출발에도 해당). 10.2 출발 지원 때 `_db_auth`·`_db_stored_procedure`·`_db_stored_procedure_args`(거부), `db_auth`·`_db_class`(경고), `db_root`·`db_user`와 `triggers`, `db_serial`과 `att_name`의 동시 출현(거부)을 버전 분기로 넣는다.
- **Q3 [task] 실측 V1~V8**: T4(#512)의 10.2 기준 DB와 develop install로 한 번에 돌린다. 결과 덤프를 Q1·G8의 근거로 쓴다.

### 아직 흐린 것

- 사용자 클래스의 **속성 도메인**이 시스템 클래스를 가리키는 경우(예: 칼럼 타입 `db_user`, `db_serial`). 이것은 텍스트가 아니라 클래스 레코드 안의 도메인 class OID다. same-slot 사상(R8 D8, G2)이 OID를 유지하므로 OID는 맞지만, `db_serial`→`_db_serial`처럼 같은 OID의 클래스 이름이 바뀌고 `db_user` 칼럼이 vclass를 뜻하게 된 뒤 이 칼럼의 경로식 텍스트가 어떻게 되는지는 보지 않았다.
- 문자열 리터럴 안의 시스템 이름(예: `WHERE class_name = 'db_trigger'`)은 토큰 재작성 대상이 아니다. develop에서는 그 이름이 다른 객체(vclass)를 가리키므로 결과가 바뀐다. 경고로 충분한지 정하지 않았다.
- 10.2에서 DBA가 일반 사용자에게 `db_trigger`·`db_password`·`_db_*` SELECT를 grant했을 수 있다(V3 반대 경우). 그런 grant가 있으면 owner가 DBA 그룹이 아닌데도 텍스트가 이 클래스를 읽는다. R4 요약 G가 develop에 없는 PUBLIC grant를 지우는 것처럼 이런 사용자 grant를 어떻게 옮기는지는 R4/G2 범위에서 정하지 않았다.
- PL/CSQL 본문은 11.4부터라 10.2 출발에는 없다. Java SP 본문 안의 SQL 문자열은 DB 밖(볼륨 밖 자산)이라 이 검사 범위 밖이다.
