---
status: accepted
date: 2026-10-12
issue: CBRD-27583 (PR 8022 follow-up; CBRD-27510 relates)
amends: ADR 0020 (two resolve points)
---

# 플랜 캐시는 바인드 타입 서명마다 타입 변형 플랜을 두고, 문장 핸들이 서명 8개를 넘기면 일반 플랜으로 고정한다

PR 8022 의 플랜은 타입을 모르는 바인드를 가변 도메인으로 컴파일하고, 실행마다 실행 전 도메인 확정(`qexec_resolve_domains`)이 그 바인드에서 갈라지는 노드·비교·키를 다시 정했다. CBRD-27583 은 그 실행당 비용을 없애려고 **바인드 타입 서명마다 따로 컴파일한 타입 변형 플랜**을 캐시에 두기로 했다(후보 3, 사용자 결정 2026-10-11). 타입 변형 플랜은 바인드의 값 타입을 컴파일 도메인으로 쓰므로 가변 위치가 남지 않고, 로드가 비교를 확정한다. PR 8022 의 가변 도메인 플랜은 **일반 플랜**으로 남아 서명이 너무 많은 문장과 `plan_cache_mode=force_generic` 이 쓴다. 두 플랜 모두 "`qexec_execute_mainblock` 진입 전에 전부 정해진다" 는 ADR 0020 의 구조를 지킨다.

- **바인드 타입 서명**(`pt_bind_type_signature`)은 클라이언트가 기대 도메인으로 캐스트한 **뒤**의 값으로 모든 위치를 적는다. 위치마다 DB 타입 하나이고, 문자열은 CHAR/VARCHAR 와 codeset 까지 적고 collation 은 적지 않는다(D-20). NUMERIC 은 precision·scale 없이 `N` 하나다(float numeric `tp_Numeric_domain`, D-16·D-19). 도메인 없는 NULL 은 `n`, 도메인으로 캐스트된 NULL 은 그 도메인의 토큰이다. 자동 파라미터화된 리터럴은 타입만 적는다.
- **캐시 키**: 타입 변형은 `alias_print` + `?bt=` + 리터럴 토큰 + 사용자 바인드 토큰의 SHA-1 이다. 일반 플랜은 develop 의 키를 그대로 쓴다. 클라이언트에는 변형 표가 없다. 문장 핸들은 마지막 서명과 본 서명 수만 들고, 서명이 바뀌면 서버 캐시를 다시 조회한다(D-18).
- **`plan_cache_mode`** = `auto`(기본) / `force_generic`(PR 8022 동작, 되돌리는 길) / `force_typed`. `auto` 에서 한 문장 핸들이 서명 `PLAN_CACHE_TYPED_VARIANTS_MAX`(8)개를 넘기면 그 핸들은 일반 플랜으로 고정한다(PostgreSQL 의 custom/generic 선택과 같은 자리, D-14).
- **타입 변형은 값의 타입만 보고 값은 보지 않는다**(D-21). `do_prepare_statement` 가 타입 변형을 생성하는 동안 `parser->flag.set_host_var` 를 0 으로 두어, 바인드 값이 상수 접기·코어션·UPDATE 상수로 플랜에 구워지지 않는다. 예외는 LIMIT 값 peek 하나다(develop 의 bound-limit 재컴파일과 같은 답). 옵티마이저의 선택도는 값 배열을 직접 읽는다.
- **서버**: 타입 변형의 루트 XASL 에 `XASL_TYPED_BIND_PLAN` 이 붙고, 로드는 고정 POS 쪽을 `DOMAIN_SIDE_KNOWN` 으로 확정한다. 실행 시작의 검사가 모든 POS 참조의 값 타입을 컴파일 도메인과 비교해 다르면 `ER_QPROC_BIND_TYPE_MISMATCH`(-1385)다.
- **세션 변수는 처음 SET 된 값의 타입을 지킨다**. 다른 타입(문자열은 다른 codeset 도)의 SET 은 `ER_SES_VARIABLE_TYPE_FIXED`(-1386)이고, NULL 은 타입을 주지도 받지도 않으며, `DROP VARIABLE` 이 타입을 지운다(D-13).
- **정해 놓고 다시 캐스트하지 않는다**(D-15). 행이 피연산자를 캐스트하는 도메인은 규칙 하나 `domain_operand_cast_target` 이 답한다. 그 변환기는 로드(`domain_fixed_operand`)나 실행 전 확정(`qexec_resolve_cast_coercion`)이 찾고, 행은 `fetch_cast_value` 로 그것을 부른다. 집계·분석 함수·보간 정렬 키·LEAD/LAG 의 offset 과 default 는 설정 단계가 변환기를 찾는다.

## Considered Options

- **후보 1, 같은 서명의 확정 결과를 실행 사이에 재사용**: 닫음. 타입 변형에는 실행당 타입 결정이 없어 재사용할 대상이 없다.
- **후보 2, 도메인 계획 도출을 컴파일로 옮김**: 닫음. 타입 변형에는 가변 POS 가 없어 로드와 컴파일의 추론 차이가 생기지 않는다.
- **클라이언트의 서명별 xasl_id 표**(D-06 초안): 기각(D-18). 서버 캐시 조회가 이미 그 표이고, 표는 핸들마다 메모리와 무효화 규칙을 더한다.
- **서명에 collation 을 넣음**: 기각(D-20). `SET NAMES` 마다 변형이 갈려 prepare 시점 collation 의미(`bug_bts_10057`, `issue_8391`)가 깨진다. PostgreSQL 도 파라미터 타입에 collation 을 두지 않는다.
- **서명에 NUMERIC precision·scale 을 넣음**: 기각(D-16). 리터럴 `10.5` 와 `100.25` 가 다른 변형이 되어 변형 수가 폭발한다.
- **서버가 타입 불일치를 오류로 돌려주고 클라이언트가 재컴파일**: 기각(D-06). 왕복이 하나 늘고, ADR 0020 이 거부한 오류 주도 재컴파일이다.
- **변형 수 상한 없음**: 기각(D-14). 병적인 바인드 패턴에서 실행마다 재컴파일하는 꼬리가 생긴다.

## Consequences

- 사양 변경 1: 타입 변형의 첫 실행은 플랜을 생성하므로 `show trace` 에 Query Plan 블록이 실린다(CTP `_36_guava/cbrd_27510/16_hash_scan_build_keys`, `auto` 에서도).
- 사양 변경 2: 세션 변수에 다른 타입을 SET 하면 오류다. CTP sql 58건의 답이 바뀌고(타임존 날짜 포맷 38, json 호스트 변수, enum, 세션 변수 TC 등), 매뉴얼 `set.rst` 에 적는다. `_36_guava/cbrd_27510/01·02` 는 같은 연결의 앞 TC 가 남긴 `@v` 에 기대므로 TC 를 고친다.
- 사양 변경 3: 타입 변형의 캐시 키 텍스트에 `?bt=` 서명이 붙는다(plandump, SQL_ID).
- 남은 비용: 타입 변형에서도 인덱스 키 상수(`DOMAIN_KEY_CONSTANT`)와 고정 POS 위의 컴파일 VARIABLE 노드(`? + 1`)는 실행당 확정이다. 확정할 것이 없는 플랜이 블록을 건너뛰는 최적화(C3b)는 하지 않았다.
- 측정(2026-10-12, `csql -S` 의 PREPARE/EXECUTE, release, `perf stat instructions:u` 실행당 3회 중앙값, 통계가 있는 DB): 일반 플랜은 develop 대비 -0.3%~+0.75% 다. 타입 변형은 일반 플랜 대비 비교가 많은 문장에서만 줄었다(`and-30` -0.3%, `alt-in3` -3.7%). 바인드 없는 `nobind` 는 같고, 나머지 9셀은 +1.6%~+20%(+15k~+104k)다. csql 의 SQL `EXECUTE` 는 실행마다 서명을 만들고 서버 캐시를 한 번 더 조회한다(`do_find_typed_plan`, 약 18k). 문자열 바인드가 많은 문장(`case-30`, 바인드 60개)은 collation 이 여전히 실행당 확정이라(D-20) 줄일 것이 없다. 핸들을 유지하는 CAS/JDBC 경로는 서명 비교만 하고 조회가 없지만 측정하지 않았다. 원자료 `.git_ignored_dir/scratch/cbrd27583/bench/report-final.md`.
- 측정하지 않은 것: N=8 은 가설이다. `plan_cache_logging` 은 키 비교마다 디버그 줄을 남겨 CTP 전수의 변형 분포를 세는 데 쓸 수 없었다.
- 함수 안의 값 판정 캐스케이드(ROUND·TRUNC 의 문자열 인자, WIDTH_BUCKET, UNIX_TIMESTAMP, HEX·ASCII)는 값의 내용으로 목표를 고르는 함수 고유 규칙이라 그대로다.
