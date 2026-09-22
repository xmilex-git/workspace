# 탐침: 규칙표 프로토타입 패치 → optdebug 셀 실측·#317 탐침 재실행·CTP sql 전수 + medium — 답안 변경 부류별 전수표

지도: xmilex-git/workspace#312 · 티켓: #319 · 작성 2026-09-22 · 기준 엔진: `develop` `cad27172b` optdebug(#316 설치본 `.git_ignored_dir/scratch/dpin/install-optdebug`) vs 프로토타입 `dpin-probe` `9486726d1`→`4a9a2ccdd`(= `cad27172b` + 패치 2커밋, CTP 는 `4a9a2ccdd`; 설치본 `.git_ignored_dir/scratch/dpin-319/install-optdebug`).
입력: 규칙표 `domain-pin-rule-table.md`(#317·#322) · 실측 `domain-pin-asis-matrix.md`(#317) · 파서 규칙 `domain-pin-rules-parser.md`(#313) · 렛저 `domain-pin-lessons.md`(A 절 L-02~L-07) · #317 인계 코멘트(#319 첫 코멘트).
스크래치: `.git_ignored_dir/scratch/dpin-319/`(`apply_patch.py` 패치 스크립트, `cells/` 규칙 셀 91개, `probe/` #317 탐침 재실행, `diff_results.py`, CTP 런 링크).

이 문서가 답하는 것: 규칙표(§2~§4)를 **컴파일 측 최소 패치**로만 적용하면(게이트·삭제 없음) (1) 규칙 셀과 #317 전수 탐침에서 어느 셀이 어떻게 바뀌는가, (2) optdebug CTP sql 전수 + medium 에서 답안이 어디서 어떻게 바뀌는가, (3) 그 변경을 규칙표 §7 예상과 대조해 **허용 후보 / 규칙표 누락 / 패치 결함 / develop 기존 / TC 결함** 으로 전수 분류하면 무엇이 남는가.

---

## 0. 한 장 요약

- **프로토타입**: 컴파일 측 슬롯 미러만(산술·COALESCE 류·UNION/VALUES·INSERT…SELECT·to_char 포맷·세션변수), 게이트·삭제 없음, 값 변환은 현행 바인드 캐스트. `dpin-probe` 2커밋(`9486726d1` → `4a9a2ccdd`, B7 철회), 버린다.
- **CTP**: sql 전수 **17355/17466(실패 111, 코어 0)**, medium **975/975**, 기준선 nightly(같은 커밋) 17466/975 → 111건 전부 분류(§4, 미분류 0). optdebug assert 신규 0.
- **§7 예상과 일치**(허용 후보): `? + 1` 문자 바인드 DOUBLE → INTEGER 표기, 공통값·UNION `x.0` → `x`, `ifnull(?, 1)` 날짜 바인드 -494(`bug_3256` 정확히), 다중 행 VALUES·`date_col UNION ?` 오류 → 값, `to_char(?, 숫자 포맷)` 문자 바인드 = 숫자 파싱 후 포맷(F1' 후보 확인), 세션변수 형제 미러.
- **규칙표를 되돌려야 하는 것 1**: B7 CHAR→VARCHAR 미러는 `char_col = ?` 리터럴 바인드를 1행 → 0행으로 바꾼다(P0 위반) → R-1.
- **규칙표 개정·재확인 10건**(§5 R-1~R-11): `? + n` 날짜 관용구 -494 가 CTP 65곳(R-9), INTEGER 미러가 넓은 바인드를 좁혀 오버플로/-494(R-2), 대입 컬럼보다 리터럴 형제가 먼저 미러돼 decimal 값 절단(R-11, silent), `return_null_on_function_errors` 미고려(R-10), `str_col ×÷ ?`·`enum_col ×÷ ?`·`to_char` TIME·U13 결과 타입·GREATEST 사슬·중첩 게이트 식 행 누락(R-3~R-8).
- **프로토타입 한계로 구현 입력이 된 것**(§5 F-1~F-6): 정수 컬럼 비교 슬롯은 오늘 클라이언트 캐스트가 없다, 바인드 캐스트는 반올림한다(게이트 K 산술은 strict), 형제는 시그니처 CAST 전 원 노드로 정의, UNION 미러는 호스트 변수 가지만, -494 시점은 prepare/bind 로 이동.
- **패치 결함**: C12 재귀 CTE 컬럼 오미러 1건(F-6), GREATEST 사슬(R-7). 그 외 111건은 규칙 귀결·한계·개선으로 설명된다.

---

## 1. 프로토타입 패치 — 무엇을 어디에 (D-319-01~08)

패치는 `dpin-probe` 브랜치 1커밋(`9486726d1`, 파일 2개 `src/parser/type_checking.c` +184 / `src/parser/semantic_check.c` +45). **버린다** — 구현(#320 이후)에 체리픽하지 않는다. 적용 스크립트 `apply_patch.py` 가 앵커 문자열 치환으로 재현한다.

| 규칙 행 | 현행(늦은 바인딩) | 패치 지점 | 무엇을 하나 |
|---|---|---|---|
| A5·A5'·A8' (`+`·`-`) | `pt_eval_expr_type` PLUS/MINUS 선처리가 한쪽 MAYBE 면 결과 MAYBE + `cannot_use_signature`(tc:9010·9070) | 그 검사 **앞**에 `pt_probe_mirror_pair(…, allow_datetime=false)` | 한쪽이 슬롯(호스트 변수 / `-?`·`PRIOR ?` 안의 호스트 변수 / 세션변수 읽기)이고 다른 쪽이 숫자 타입(SHORT~MONETARY, LOGICAL 제외)이면 슬롯을 그 타입으로 미러: 호스트 변수는 기존 "짝 미러" 관례(tc:9555 블록과 동일 — `pt_coerce_value` + `pt_xasl_type_enum_to_domain` 기본 도메인 + `pt_preset_hostvar`), 세션변수는 `pt_coerce_expression_argument` 가 CAST 로 감쌈(S4). 날짜·문자·ENUM·BIT 형제는 손대지 않음(A9·A11·A13 현행) |
| A5·A5'·A6 (`*`·`/`·`%`) | 시그니처 경로에서 `pt_get_equivalent_type_with_op` 가 MAYBE 유지 → 결과 MAYBE | 선처리 switch 에 `case PT_TIMES/PT_DIVIDE/PT_MODULUS` 신설, 같은 미러 | `/` 는 INTEGER 미러 뒤 시그니처 그대로 → 정수 절삭 유지(A6) |
| U7·U13 (COALESCE 류) | 비대칭·늦은 바인딩 → 슬롯·결과 MAYBE | `case PT_IFNULL/NVL/COALESCE/NULLIF/LEAST/GREATEST` 신설(`allow_datetime=true`), `PT_NVL2` 는 arg2/arg3 사이 | 숫자·날짜시간 형제만 미러. **문자 형제는 제외**(D-319-03: 현행이 이미 collation 축 C5 로 슬롯 VARCHAR+ENFORCE 라 결과 VARCHAR, 타입 축 변경 없음), ENUM 형제 제외(#326) |
| U2·U4 (UNION·다중 행 VALUES) | `pt_get_common_type_for_union` 이 문자 형제만 미러, 숫자×MAYBE 는 `pt_common_type` → DOUBLE, 날짜×MAYBE → MAYBE(열린 리스트 컬럼, L-18) | 문자 특례를 숫자·날짜시간 형제로 확장(`pt_probe_is_union_value_sibling`) | 슬롯 가지는 `pt_to_compatible_cast` 가 `CAST(? AS <형제 타입>)` 으로 감싼다(현행 캐스트 적용 코드 그대로). NUMERIC 형제는 그 가지의 p/s 를 cinfo 에 유지(D-319-06: 기본 (38,0) 재캐스트로 형제 컬럼 값이 바뀌는 것을 막음) |
| U16 (`INSERT … SELECT ?`) | 서브쿼리 select list 의 `?` 는 MAYBE 로 남음(VALUES 의 `?` 만 tc:8046 에서 컬럼 도메인) | `pt_coerce_insert_values` 의 `PT_IS_SUBQUERY` 분기 | select list 의 맨 호스트 변수에 대상 컬럼의 완전한 도메인을 expected_domain 으로(VALUES 경로와 동일) |
| F1·F1' (`to_char(?, '포맷 리터럴')`) | TO_CHAR 늦은 바인딩 → 값 슬롯 MAYBE | `case PT_TO_CHAR` 머리에 `pt_probe_to_char_format_type` | 포맷 리터럴 판별: `9`/`0` 포함 → NUMERIC; 날짜 토큰(YY·MM·DD·MON·DAY·DY·CC·RR) → DATETIME; 시간 토큰(HH·MI·SS·AM·PM·FF)만 → **TIME**(D-319-04: 규칙표 F1 은 DATETIME 만 적었으나 TIME 바인드 + 시간 포맷이 DATETIME 미러에서 -494 가 되므로 TIME 하위 행을 제안); 둘 다 아니면 현행(늦은 바인딩). `to_char(?, ?)`·`to_char(?)` 는 F2 대로 현행 |
| S4 (세션변수 읽기 형제 미러) | `@v` 읽기는 항상 MAYBE(tc:3945) | 위 산술·COALESCE·TO_CHAR 미러가 `PT_EVALUATE_VARIABLE` 도 슬롯으로 취급 | CAST 래핑(계획된 CAST) — 값 변환 의미는 CAST(반올림·문자 파싱)라 게이트 규칙(strict)과 다를 수 있음(D-319-01) |
| B7 (`char(n)_col = ?`) | 미러가 CHAR 기본 도메인(pd:3128 은 VARCHAR 값이면 원 값 유지) | `pt_coerce_expression_argument` 머리 | 호스트 변수 MAYBE 에 def_type CHAR 가 오면 VARCHAR 로 재귀 호출(D-317-04) |

**결정(D-319)**

- **D-319-01 값 변환은 현행 클라이언트 바인드 캐스트로 대신한다.** 게이트가 없으므로 미러된 슬롯의 값은 `pt_set_host_variables`(`tp_value_cast_preserve_domain`, 실패 -494)가 바꾸고, CAST 로 감싼 세션변수는 CAST 의미로 바뀐다. 규칙표의 손실 정책(산술 strict → -494, 비교 strict-or-keep, 대입 반올림)과 **다를 수 있는 셀은 실측으로 표에 적고**(§3), 그 차이는 "프로토타입 한계" 부류로 분류한다(구현의 게이트가 규칙대로 하면 사라지는 차이). 비용: A5 의 -494 예상이 프로토타입에서 다른 모양(값 유지 또는 반올림)으로 보일 수 있다. 되돌리기: 없음(패치는 버린다).
- **D-319-02 미러 대상은 "슬롯" 만.** 호스트 변수, `-?`/`PRIOR ?`/`CONNECT_BY_ROOT ?` 안의 호스트 변수, 세션변수 읽기(S7 의 슬롯 정의). 중첩 MAYBE 식(`(? + ?) + 1`, `abs(?) + 1`, `coalesce(?, ?) + 1`)은 손대지 않는다 — 규칙표에 "게이트 확정 식의 외부 형제 변환" 행이 없다(collation 축의 D-322-02 와 같은 자리; #323·#325 입력으로 §5 에 적음).
- **D-319-03 문자 형제는 타입 축 미러에서 제외.** `coalesce(?, 'a')`·`? + 'a'`·`str_col + ?` 는 현행 유지. 규칙표는 `str_col + ?` 행이 없고(§5 누락 후보), COALESCE 문자 형제는 이미 C5 로 확정돼 있다.
- **D-319-04 TO_CHAR 포맷 판별에 TIME 하위 행.** §1 표 참조. 규칙표 F1 개정 제안(§5).
- **D-319-05 프로토타입에 넣지 않은 C 행**: S6(PL/CSQL 선언 타입 전달 — wire 변경), U16 의 MERGE 소스 `SELECT ? v`(파생 테이블 경유 매핑), U0 의 `INSERT int_col ← ?` DATE 0행 결함(캐스트 오류 삼킴 — 게이트 자리에서 고침), B13/B14 ENUM(현행 `TO_ENUMERATION_VALUE(?)`·ENUM 기본 도메인 그대로 — 답 불변 행), B30~B34 키(현행), §5 결함 수정(D2~D7·L-19 — 게이트/구현에서 소멸하는 것이라 프로토타입에 없음; CTP 에서 나오면 "미해결(구현 소멸 예정)" 로 분류, D-317-24).
- **D-319-06 UNION NUMERIC 미러는 형제 가지의 p/s 를 유지.** `pt_update_compatible_info` 의 NUMERIC 기본 (38,0) 을 그대로 두면 `numeric(10,2)` 가지가 `CAST(… AS NUMERIC(38,0))` 으로 재캐스트되어 소수부를 잃는다(패치 작성 중 발견, 정적).
- **D-319-07 ENUM 형제는 전부 제외**(A13 G, B13/B14 현행, C6 후속 #326).
- **D-319-08 실행 순서**: 빌드 → 규칙 셀 91개(develop·프로토타입 양쪽, `csql -S`) → #317 탐침 전수 재실행(프로토타입) → 셀·탐침 diff 로 규칙 위반을 먼저 잡은 뒤 → CTP sql 전수(7 샤드) + medium. 셀에서 패치 결함이 보이면 CTP 전에 멈춘다(L-05 의 "덩어리 검증" 회피).

## 2. 절차·환경 (L-02·L-03·L-04·L-07 대응)

- 빌드: `INSTALL_PREFIX=…/dpin-319/install-optdebug WORKSPACE=~/dev/cubrid-worktree/dpin-probe just build debug` → 버전 스탬프·conf diff 는 §3.0. **optdebug 만**(L-03: 비교는 같은 빌드끼리, 기준선도 optdebug).
- 규칙 셀: `cells/gen_cells.py` → `cells.sql`(라벨 91개 = 규칙 행 ID, `PREPARE … EXECUTE USING`; 타입 값은 `SELECT … INTO :h_*` 세션 호스트 변수), `run_cells.sh <install> <tag>` 가 `csql -S` 로 실행. `parse.py`(#317) → `results-<tag>.tsv`, `diff_results.py` 로 라벨별 대조.
- #317 탐침: `probe.sql`·`probe2.sql`·`probe3.sql`·`probe_rest.sql`·`probe_slot.sql`(라벨 17,267)을 `run_resumable.py` 로 프로토타입 설치본에서 재실행 → `results_*.tsv` 를 #317 의 `results_all/rest/slot.tsv` 와 `diff_results.py` 로 대조.
- CTP: `BUILD=…/dpin-319/install-optdebug TC_REF=dpin-tc just ctp sql`(전수, 7 샤드, `_05_plcsql` 포함 — L-02·L-07) + `just ctp medium`(1 샤드). 컨테이너만, 호스트 `ctp.sh` 금지. 기준선은 #316 이 인용한 nightly run 35619124899(sql 17466/17466·medium 975/975 success) — 프로토타입의 실패 전건이 diff 다. 목록 비교는 `sql/` 접두 정규화 뒤(L-04), 판정은 샤드 CTP 로그의 `[OK]/[NOK]`. 완주 안 된 run 은 증거가 아니다(L-07).
- 실패 diff 읽기: `<run>/webconsole/…/<case>.result` vs 테스트케이스의 `.answer`.

## 3. 규칙 셀·탐침 실측 (develop optdebug vs 프로토타입 optdebug)

### 3.0 빌드

| 설치본 | 워크트리·커밋 | `cubrid_rel` | conf |
|---|---|---|---|
| develop(#316) | `dpin` `cad27172b` | `11.5.0.2600-cad2717 optdebug` | 캠페인 conf 일치 |
| 프로토타입 1차 | `dpin-probe` `9486726d1` | `11.5.0.2601-9486726 optdebug (Sep 22 2026 15:50)` | 일치(diff 없음) |
| 프로토타입 2차 | `dpin-probe` `4a9a2ccdd`(B7 철회) | (§3.3) | |

### 3.1 규칙 셀 91개 — 1차(9486726d1) 결과: 245 실행 중 81 변화

전수표: `.git_ignored_dir/scratch/dpin-319/cells/run1/cells-table.md`(라벨·바인드·양쪽 결과·diff 표시). 요지(라벨 = 규칙 행):

| 규칙 행 | 프로토타입에서 관찰된 것 | §7 예상과의 대조 |
|---|---|---|
| A5 `i + ?` | 정수 1 → 2(같음). **1.5 → 3, '1.5' → 3, DOUBLE 1.5 → 3, 1.1 → 0(`i − ?`)** — 바인드 캐스트가 반올림(`tp_value_cast_internal` DOUBLE/NUMERIC→INT ROUND). '1.0' → 2 ✓. 'abc' → -494 ✓(develop 도 서버 -494). DATE → -494 ✓(develop date+1). BIGINT 2^53+1 → **-494(오버플로)**(develop bigint 결과) | 소수·날짜·비숫자 문자 -494 예상 중 **소수만 어긋남**(반올림 = D-319-01 한계, 게이트는 strict 여야 함). BIGINT 바인드 -494 는 §7 에 없음 → 목록 추가 후보 |
| A5' `n + ?`, `d + ?`, `b + ?` | '2.5' → 4.00 numeric(develop double 4.0), DOUBLE 1.5 → 3.00 numeric, DATE → -494; `b + ?` DOUBLE 1.5 → **3 bigint**(반올림) | 표기 변경은 예상, 반올림은 한계 |
| A6 `i / ?`, `? / 2` | `i / 2.0` → 0(develop 0.5), `i / 0.5` → 1(develop 2.0), `7.0 / 2` → 3(develop 3.5), `7.5 / 2` → 4(develop 3.75) | "소수 바인드 -494" 예상이 **반올림 후 정수 절삭**으로 나타남(silent, D-319-01). DOUBLE 7.0 → 3 은 규칙대로(strict 성공 → 정수 절삭)이나 §7 에 없음 |
| A7 `i div ?` | 변화 없음 ✓ | |
| A8 `? + ?` | 변화 없음 ✓(접합·DOUBLE·date+1 그대로) | |
| A8' `? + 1`, `? − 1`, `1 + ?`, `? * 1.5` | '1.0' → 2 integer ✓(§7), 1.5 → 3(반올림), DATE → -494 ✓, 'a' → -494 ✓, `? * 1.5` '2' → 3.0 numeric | |
| A8' 중첩 `i + ? + ?` | (1, 1.5) → 4(develop 3.5): 안쪽 미러 INT 결과가 바깥 형제 → 두 슬롯 다 INT | |
| A9·A11·A13·A14 | `dt + ?`, `dt − ?`, `e + ?`, `−?`/`abs(?)` 변화 없음 ✓ | G 행 유지 확인 |
| A14 `i + -?` | 1.5 → -1(develop -0.5): `-?` 안의 슬롯도 미러(기존 관례) | 반올림 한계 |
| F8 `sum(i + ?)` | 1.5 → 7(develop 6.0), 'a' → -494 | |
| B4·B5·B6·B9·B10·B11·B13·B14·B34 | 변화 없음 ✓ | 비교 행 현행 확인. **관찰**: `i = ?` 1.5·2.5 는 양쪽 다 0행 — 정수 컬럼 비교 슬롯은 클라이언트에서 캐스트되지 않고 값 그대로 서버 비교(§5 F-1) |
| B7 `c = ?` | 셀 SQL 오류로 1차에서 미측정; #317 탐침에서 `AP.char_eq_hv_trailing`·`MISC.char_eq_trailing` '1.0' 바인드 **1행 → 0행**, `CMP.colhv.char.string` NULL → 0, `IDX.hv.char.enum` 1 → 0 | **규칙 행 B7 자체가 현행 답을 바꾼다**(VARCHAR 미러 + trailing space 구분) → 2차 패치에서 철회, D-317-04 재검토(§5) |
| U0 `INSERT int ← ?` | 변화 없음(1.5 → 2, DATE → 0행 현행) | 결함은 게이트 자리(D-319-05) |
| U2 `1 UNION ?`, `(VALUES (1), (?))` | 1.0/'1' → **1 integer**(develop 1.0 double) ✓, 'a' → -494 ✓, 1.5 → 2(CAST 반올림), typeof double → integer ✓ | §7 "`1.0`→`1`" 확인 |
| U2 `n UNION ?`(numeric(10,2)) | 1.50 ; 2.50 ; 2.50 numeric(develop 전부 double) — 형제 p/s 유지(D-319-06), 2.567 → 2.57 | 표기 변경 |
| U2 `dt UNION ?` | develop **오류**("date → *variable*") → 값 ✓(L-18 부류) | 오류 → 값 |
| U3 `? UNION ?` | 변화 없음(incompatible 오류 그대로) ✓ | |
| U4 `(VALUES (timestamp'…'), (?))`, `INSERT … VALUES (dtt'…'), (?)` | develop 항상 -494 → **값** ✓; 정수 1 → epoch timestamp(CAST 의미) | 오류 → 값(예상) |
| U6·U8·U10 | 변화 없음 ✓ | |
| U7 `coalesce(?, 1)` | 'a' → -494 ✓, '2' → 2 ✓, 2.5 → 3(반올림), NULL → 1 ✓; `ifnull(?, 1.5)` '2.25' → 2.25; `nvl(?, i)` 'x' → -494; `nvl(i, ?)` 'x' → -494(develop '1'); `nullif(?, 1)` 변화 없음; `least(?, 2)` 'a' → -494, 3.5 → 4(반올림); `greatest(?, dt)` '2024-01-05' → date, 1 → -494; `nvl2(i, ?, 1)` 'x' → -494; `case … then ? else 1` 변화 없음(현행 미러) | §7 "부류 다른 바인드 -494" 확인 |
| U13 `coalesce(cast(? as datetime), cast(? as datetime), ?)` | 문자 바인드 → **DATETIME 값**(develop 문자열) | 결과 타입 변경 — §7 에 없음 → 추가 후보 |
| U16 `INSERT t2(i) SELECT ?` | DATE → -494 시점만 이동(develop 서버 -494) | 예상 |
| U17·S1·S5 | 변화 없음 ✓ | |
| F1·F1'·F2·F3·B10 등 따옴표 포함 셀 | 1차 셀 SQL 의 따옴표 미이스케이프로 PREPARE 실패(미측정) → 2차 셀(§3.3) | |
| F4·F5·F7 | 변화 없음 ✓ | G 행 유지 |
| S4 `@v='1.0'; @v + 1` | 2 integer ✓(§7); `@v=1.5` → 3(CAST 반올림); `@v='2'; coalesce(@v, 1)` → 2 integer; `@v='2.5'; @v * 2` → 6(develop 5.0) ; `@v=date; to_char(@v,'YYYY-MM-DD')` → '2024-01-02'(develop '01/02/2024' — 문자열 저장값 통과) | 표기·값 변경 |

### 3.2 #317 탐침 17,267 라벨 재실행(프로토타입 9486726d1) — 달라진 라벨

방법: 5개 파일을 `run_resumable.py` 로 실행(크래시 재개 20/18/2/17/3회), `parse.py` → `results_*.tsv`, `diff_results.py` 로 #317 의 develop TSV 와 대조, `classify_probe.py` 가 라벨 패밀리 → 규칙 행, 변화 종류를 붙임(`probe/classified.tsv`, 요약 `probe/classified-summary.md`).

**크래시(optdebug assert)**: 프로토타입에서 난 assert 는 develop 과 **같은 목록**(D1 `coalesce(enum_col, ?)` tc:23010, D2 `group_concat(?)` NULL qx:1375, D3 `group_concat(s + ?)` op:10996, D4 `sum(?) over` qx:23654, D5 `to_char(dtt, ?)` BIGINT so:25792, D6 `? union ?` NULL / 재귀 CTE lf:913, D7 `enum IN (NULL, NULL)` df:678). 새 assert 0, 사라진 assert 0 — 전부 G 행·collation 축·ENUM 형제 결함이라 프로토타입(컴파일 미러만)이 건드리지 않는 자리다. 분류: **미해결(구현 D-317-24 대로 게이트/삭제 단계에서 소멸 확인)**.

**결과가 사라진 라벨(develop 에는 결과, 프로토타입은 바인드 시점 -494)** 366개 — 전부 "형제 부류 밖 바인드 → -494" 다:

| 패밀리 | 라벨 수 | 내용 | 규칙 |
|---|---|---|---|
| `AR.colhv.{plus,minus,mul,div}.<숫자 컬럼>.{date,time,timestamp,datetime,bit,set}` | 246 | 숫자 컬럼 산술에 날짜·비트·집합 바인드: develop 는 날짜→날짜 산술(`int_col + date` = date+1) 또는 **NULL**(bit/set, 실측 §3.6 "오류 아닌 NULL") → -494 | A5 ✓(날짜 -494 명시; bit/set 의 NULL→오류는 P7 ③ 개선이나 §7 에 없음) |
| `AR.colhv.{mul,div}.{string,char}.…` | (위에 포함) | `str_col * ?` 슬롯이 DOUBLE 로 미러됨 — 2차 타입 검사 패스에서 형제가 `CAST(str_col AS DOUBLE)`(A3 시그니처)이기 때문. `+`/`−` 는 `cannot_use_signature` 경로라 CAST 가 없어 미러 없음 | 규칙표에 `str_col ×/÷ ?` 행 없음(§5 A3' 제안) |
| `CV.coalesce.colhv.<컬럼>.<부류 밖 바인드>` | 78 | `coalesce(int_col, ?)` 에 날짜·bit·set 등 → -494(develop VARCHAR 결과) | U7 ✓ |
| `CV.union.colhv.<숫자 컬럼>.<날짜…>` | 36 | `int_col UNION ?` 날짜 바인드 → -494(develop double) | U2 ✓ |
| `SLOT.*`(ifnull_int·values_row2·plus_lit·div_lit·subq_in·insert_sel × 6 바인드) | 36 | develop `results_all.tsv` 의 SLOT 계열은 재개 아티팩트(세션변수 유실)라 대조 불가 → `results_slot.tsv`(정상 실행) 기준으로는 `subq_in` 은 양쪽 -494(현행), 나머지는 위 규칙과 같음 | — |

**값·표기가 달라진 행**(diff 1,543행 중 재개 아티팩트 790행 제외 — develop 쪽 `results_all.tsv` 가 크래시 재개 뒤 세션변수를 잃은 구간(`CV.*.enum.*`·`CV.*.set.*`·`CV.*.col.*`·`CV.*.hvhv.*`·`SLOT.*`)과 프로토타입 쪽 재개 구간의 라벨 귀속 불확실 구간은 패치가 건드리지 않는 패밀리라 제외):

| 규칙 행 | 표기·타입만 | silent 값 변경 | 값 → 오류 | 오류 → 값 | 비고 |
|---|---|---|---|---|---|
| A5·A5'·A6 숫자 컬럼 미러 | 132 (`double 2.0` → `smallint 2` 등, 컬럼 타입 표기) | 14 (`num_col * ?` ENUM 바인드 NULL → 1 — 서수 변환) | (위 246 -494) | — | bigint 바인드가 short/int 로 좁혀짐(값 1 이라 표기만) |
| A13 ENUM 컬럼 ×·÷ | 16 (`enum_col * ?` → smallint) | 2 (NULL → 1) | — | — | **패치 한계**: 2차 패스에서 `CAST(enum_col AS SMALLINT)` 형제를 미러(A13 은 G 행) |
| U2 UNION 형제 미러 | 66 + 24(MR) | 10 (`values (1),(?)` 1.5 → 2 반올림; `MR.cte.numeric` 2.50 → 3; `MR.merge_expr` '2.50' → '3') | — | 32 + 7 (`date_col UNION ?`·다중 행 VALUES timestamp: "*variable*" 오류 → 값) | |
| U7 COALESCE/IFNULL 형제 미러 | 61 + 8 | 3 + 3 (`coalesce(date_col, ?)` timestamp → date 절단; `ifnull(?, 1)` 1.5 → 2) | (위 78 -494) | — | |
| U13 COALESCE(CAST … DATETIME, ?) | — | 2 (문자/date → datetime) | — | — | 결과 타입 변경 |
| U16 INSERT…SELECT ? | — | 11 (`SLOT.insert_sel`: develop 빈 결과 → 값 — develop 쪽 아티팩트 의심) | — | 11+10 오류 시점 이동(-494 가 바인드 시점으로) | |
| A8'·A6 리터럴 형제 | 19 | 8 (`? / 2` 7.0 → 3, `? + 1` 2.5 → 3) | — | — | |
| F8 `sum(i + ?)` | — | 6 (group by 식 결과 NULL 만) | 9 **INT 오버플로 오류**(develop double 합) + 3 -494(bigint) | — | 리터럴 경로(`sum(i + 1)`)와 같은 오버플로 |
| S4 세션변수 형제 | 26 | 17 (`@v := 1.5; @v + 1` → 3; `@v := bigint; …` → int) | 2 **INT 오버플로**(`@v := 2^53; @v + 1`) | — | INTEGER 미러가 BIGINT 값을 좁힘 — §5 |
| F1+S4 `to_char(@v, 날짜 포맷)` | — | 3 ('01/02/2024' → '2024-01-02': 저장 문자열을 DATETIME 으로 파싱 후 포맷) | 4 (`@v := '1.0'` → 파싱 실패 오류; develop 은 '1.0' 통과) | — | |
| F1' `to_char(?, 숫자 포맷)` | — | 1 ('1.0' → ' 1.00' — **§7 F1' 후보 확인**) | — | — | |
| B7 CHAR 미러(철회) | — | 5 + 2(IDX) | — | — | 1행 → 0행(§3.1) |
| GREATEST 재귀 사슬 | — | — | 10 (`greatest(?, 3, 'b')` 컴파일 오류 "Cannot coerce 'b' to double") | — | **패치 한계**: 이진 미러가 사슬 전체의 공통 타입(VARCHAR)을 못 봄 |
| 패치 무관(오류 문구만) | — | — | — | — | `FN.case_when_slot_lit` character→character varying 문구, `IDX.*` 동일 오류 |

### 3.3 규칙 셀 2차(4a9a2ccdd, B7 철회 + 따옴표 수정 + 진단 셀): 265 실행 중 96 변화

전수표 `cells/cells-table.md`. 1차와 같은 결과 외에 새로 측정된 것:

| 규칙 행 | 관찰 |
|---|---|
| B7 (철회 뒤) | `c = ?` 'ab' → 1행(양쪽), VARCHAR(20) 값 → **0행(양쪽)**(실측 §3.3 의 "NULL" 은 이 셀에서 0행), 'ab   ' → 1행 — 현행 유지 확인 |
| F1 `to_char(?, 'YYYY-MM-DD')` | date/문자/datetime 바인드 → 같은 값 ✓; 정수·TIME 바인드 → -494(develop "Invalid format" 오류 → 오류 코드만 -494 로); **문자 '2024-01-02 10:00:01' → '2024-01-02'**(develop 은 문자열 통과 '2024-01-02 10:00:01') |
| F1 `to_char(?, 'YYYY-MM-DD HH24:MI:SS')` | DATE 바인드 → '2024-01-02 00:00:00'(develop "Invalid format" **오류 → 값**) |
| F1 `to_char(?, 'HH24:MI:SS')`(TIME 미러, D-319-04) | TIME·DATETIME·'10:00:01' 같은 값 ✓; 문자 '2024-01-02 10:00:01' → '10:00:01'(develop 통과) |
| F1' `to_char(?, '9,999.99')`·`'999'` | 문자 '1234.5' → '1,234.50', '1.0' → '    1.00', '12' → ' 12'(develop 문자열 통과) — **§7 F1' 후보 확인(문자 바인드 = 숫자로 파싱 후 포맷)**; DATE 바인드 → -494(develop "Invalid format") |
| F2·F3·B10·U7 문자 형제 | 변화 없음 ✓ |
| DIAG `s * ?`, `s / ?` | monetary 바인드 → double(develop monetary), DATE → -494(develop NULL); `s + ?` 변화 없음 → R-3 확인 |
| DIAG `greatest(?, 3, 'b')` | 1·'a' 바인드 → -494(develop 'b') → R-7 |
| DIAG `i in (select ? …)` DATE, `case when … then ? else ? end` SET 바인드 | 양쪽 -494 — 현행(§3.2 의 해당 라벨은 develop TSV 아티팩트였음) |

## 4. CTP sql 전수 + medium — 실패 전건 분류

런: sql `/home/cubrid/ctp-run-out/workspace/sql-20260922T071508Z-739894`(프로토타입 `4a9a2ccdd` optdebug, `TC_REF=dpin-tc` 4a7a4aed9, 7 샤드 전부 `execute end`, 코어 0) — **ALL fail=111 success=17355 total=17466**. medium `medium-20260922T072559Z-764761` — **975/975 PASSED**. 기준선 nightly 35619124899(같은 엔진 커밋 cad27172b, sql 17466/17466·medium 975/975)이므로 111건 전부가 프로토타입 diff 다. diff 전문: `.git_ignored_dir/scratch/dpin-319/ctp-sql-failures.md`(`ctp_failures.py` 가 `webconsole/**/*.result` 와 `dpin-tc` 의 `.answer` 를 대조). 미분류 0.

| # | 부류 | 건수 | 케이스(디렉터리) | 무엇이 바뀌었나 | 규칙 행 | 판정 |
|---|---|---|---|---|---|---|
| C1 | `? + 1` 에 datetime/timestamp 바인드 → -494 | **58** | `_27_banana_qa/issue_5765_timezone_support/…/_01_date_format`(26)·`_04_time_format`(26)·`_02_to_char`(6) — 13 로케일 × dt/ts × 함수 | `date_format(? + 1, ?)`·`time_format(? + 1, ?)`·`to_char(? + 1, ?, 'xx_XX')` 의 `? + 1` 이 INTEGER 미러 → datetime 바인드 -494(develop: +1일) | A8' | **규칙에 맞는 답안 변경(허용 후보)** — 단 §7 예상보다 규모가 큼(`? + 1` 을 "날짜 + n일" 로 쓰는 관용구): R-9 로 재확인 요청 |
| C2 | 숫자 형제 산술 표기(`x.0` → `x`, double → int/numeric) | 23 | `_15_host_variable/_04~_08/number_number·number_string`(cfg_null 포함 10), `_12_common/agg_group_by·distinct·order_by·union`(일부), `_07_misc/_02_prameter_bind`(3), `_12_mysql_compatibility/_08_prepare_syntax/_003_casting`, `bug_bts_4565`·`bug_bts_8743`·`bug_bts_12326`·`cbrd_20968`, `_29_CTE_recursive/04_example`·`_31_cherry/prepare_02`(CTE `x + ?`) | 결과 타입이 값 타입(DOUBLE/NUMERIC)에서 형제 타입으로 | A5·A5'·A8'·U2 | 규칙에 맞는 답안 변경(§7 "표기") — 같은 케이스 안에 C3·C5 가 섞여 있음 |
| C3 | 소수 바인드 **silent 반올림** | (C2 케이스 안 12곳) | `_07_plus/number_number` 4.2313 → 4, `_08_minus/number_number` ±1.7687 → ±2, `_12_common/agg_group_by·distinct` 3.2/4.2 → 3/4, `group_concat(i1 + ?)` '3.2,3.2' → '3,3', `_04_divide/number_number` `n1 / ?` 2.0 → 2 | 클라이언트 바인드 캐스트 반올림(D-319-01) | A5·A6 (규칙: -494) | **프로토타입 한계** — 구현 게이트는 strict(F-2). TC expected 갱신은 -494 기준으로 |
| C4 | 넓은 바인드가 INTEGER 미러로 좁혀져 오버플로 | 4 | `_06_times/number_number`(-730 곱셈 오버플로, `1.52E25` → numeric 표기), `_07_plus/number_number`(-458 덧셈 오버플로, `2.00000000023123E9` → 2000000000), `host_variables_bingding_002`(`-1 + ?` 1.79E308 → -494), `_12_common/union`(일부) | develop 은 값 타입(DOUBLE) 산술 | A5·A8' | 규칙에 맞음(P7 ①)이나 **§7 누락** → R-2 |
| C5 | 문자 컬럼 `×`·`÷`·`%` 슬롯 DOUBLE 미러: 오류 코드 -181 → -494, `return_null_on_function_errors=yes` 에서 **NULL → -494** | 6 | `_04_divide·_05_modulus·_06_times/string_string`(3), `*_cfg_null_on_errors/string_string`(3) | `s1 / ?` 문자 바인드 '2001-10-11' | A3'(R-3) | 오류 코드 이동은 P7 ②; **NULL → 오류는 규칙표 미고려(R-10)** |
| C6 | 날짜 형제 없는 산술에 날짜 바인드 → -494 | 4 | `_07_plus/date_number`·`_07_plus_cfg_null_on_errors/date_number`·`_08_minus/date_number`·`_08_minus_cfg_null_on_errors/date_number`(`? + i2`, `4 + ?`, `? - 4` 날짜 바인드; `-552` → -494) | develop: date + int = 날짜 | A5·A8' | 규칙에 맞는 답안 변경(§7 "날짜 바인드 -494") — C1 과 같은 R-9 |
| C7 | `ifnull(?, 1)` 날짜·시간 바인드 → -494 | 1 | `bug_3256` | §7 가 **정확히 예상한 케이스** | U7 | 허용 후보 |
| C8 | `1 + ?` BIT 바인드 NULL → -494 | 1 | `bug_bts_13523` | develop 은 오류 없이 NULL(실측 §3.6 결함) | A8' | 허용 후보(P7 ③) |
| C9 | 다중 행 VALUES·UNION 슬롯 **오류 → 값** | 2 | `_07_multi_values_clause/01_values`(`values(1+?),(?+2),(?+3)` -456 → 2,4,6), `06_types`(`values(timestamp'…'),(?)`·`select timestamp union select ?` -181 → 값; 같은 파일의 `values(1 + ?)` timestamp 바인드는 C1 부류 -494) | L-18 부류 | U2·U4 | 허용 후보(§7 "오류 → 값") |
| C10 | 세션변수 미러가 **재작성 질의 텍스트**를 바꿈 | 3 | `bug_bts_14877`·`cbrd_24111`(`@a := @a + t.a` → `@a := cast(@a as integer) + t.a`), `_28_features_930/_05_groupby_expression`(`group by cast((@v …`) | 값은 같고 플랜/재작성 텍스트만 | S4 | **프로토타입 한계**(계획된 변환기는 텍스트를 안 바꿈) + L-50: 구현 뒤 재확인 |
| C11 | INSERT 대입 컬럼(decimal) 안의 `IFNULL/NVL/NVL2/COALESCE/NULLIF/LEAST/GREATEST(?, 0)` → 리터럴 INT 미러가 이겨 **12.34568 → 12.00000** | 1 | `cbrd_23874` | 대입 대상 numeric(?,5) 보다 리터럴 형제 `0`(INT)이 먼저 미러됨 → 값 반올림(게이트 strict 면 -494) | U0 vs U7 | **규칙표 결함(형제 우선순위 없음, silent)** → R-11 |
| C12 | 재귀 CTE(호스트 변수 없음)의 컬럼 타입 변경 | 1 | `cbrd_20957` — 23개 CTE 문 중 `select 1 m, 1 n union all select m+1, median(m) over(partition by m)` 하나만: n 이 double(1.0 … 9.0) → int(1 … 9), 오류 없음(silent) | 재귀부의 `median(m)` 이 1차 패스에서 MAYBE 라 U2 미러가 **슬롯이 아닌 MAYBE 식**을 앵커 INT 로 미러 | — | **패치 결함**(D-319-02 위반: UNION/VALUES 미러를 호스트 변수 가지로 한정해야 함 — 구현 입력 F-6) |
| C13 | `limit 0+?, ?` → -494 | 1 | `20567_limit_1` | 진단: `@a = -14632475938453979136` 바인드만 다름 — develop 은 조용히 0행, 프로토타입은 `0 + ?` INTEGER 미러의 오버플로 -494; 'qwe' 바인드는 양쪽 오류(문구만 다름), -1·1 은 동일 | A8' | C4 와 같은 부류(R-2) — 조용한 수용 → 오류(P7 ③) |
| C14 | `insert into t1(d1) values (? + 4)` **PREPARE 가 -494**(뒤 -995 연쇄) | 3 | `_07_plus/insert_value`·`_07_plus_cfg_plus_concat_no/insert_value`·`_08_minus/insert_value` | 진단: `? + ?` 블록은 양쪽 동일. 다른 것은 `(? + 4)` DATE 컬럼 대입 하나 — `? + 4` 가 INTEGER 미러라 결과 INT → DATE 대입이 **prepare 시점 컴파일 오류**("Cannot coerce ?:0+4 to type date"); develop 은 date 바인드로 날짜 산술 | A8' | C1·C6 과 같은 R-9 부류 + 오류가 execute → prepare 로 이동(L-23) |
| C15 | `nvl(i, ?) between nvl2(s, ?, ?) and nvl(s, ?)` → -181/-494 | 1 | `cbrd_20769_exp` | 진단: 바뀐 것은 이 문장뿐 — `nvl(i, ?)` 가 INT 미러(U7)되자 BETWEEN 의 비교 격자(INT vs VARCHAR → DOUBLE, B25)가 `nvl(s, ?)` 의 '^[a]' 를 DOUBLE 로 캐스트해 -181; 'a' 바인드는 `nvl(i, ?)` -494 | U7 → B25 파급 | 규칙에 맞는 답안 변경(값 타입이 의미를 정하던 동작 제거, P7 ①) |
| C16 | `cbrd_20968`·`_12_common/select_connect_by` 등 표기·값 | (C2 에 포함) | | | | |

**등급별 집계**(silent = 오류 없이 값이 다름, L-06 최우선): silent 는 C3(반올림, 한계)·C11(규칙표 결함)·C12(패치 결함)·C10(텍스트) 뿐이고 전부 원인이 특정됐다. 오류 → 값 개선 C9 는 값 A/B 로 확인(§4.1). optdebug assert 12종은 CTP 에서 **한 건도 나오지 않았다**(코어 0) — CTP sql 에 해당 패턴 TC 가 없거나 develop 에서도 안 나는 자리(D-317-24 의 "미해결" 목록은 §3.2 탐침 기준으로 유지).

### 4.1 진단(csql 재실행) — C13·C14·C15·C12·C11·C9

여섯 케이스 파일을 양쪽 설치본의 `csql -S` 로 재실행(`diag/<case>-{develop,probe}.{out,err}`, 12회 모두 exit 0, assert 없음). 결과는 §4 표의 C9(`values(1+?),(?+2),(?+3)` 1,'2',3 → 2,4,6 — develop 은 "Data type references are incompatible")·C11(`IFNULL/NVL/NVL2/COALESCE(?, 0)` 12.34568 → 12.00000, `NULLIF(?, ?)`·`LEAST/GREATEST(?, ?, ?)` 는 슬롯뿐이라 불변)·C12·C13·C14·C15 행에 반영했다. 미분류 0.

## 5. 규칙표 개정 제안·#323/#325 입력

**규칙표 개정이 필요한 것(사용자 승인 대상 — 승인 전에는 규칙표 정본을 고치지 않는다, L-01)**

| # | 규칙 행 | 탐침 근거 | 제안 |
|---|---|---|---|
| R-1 | **B7 `char(n)_col = ?` = VARCHAR 미러(D-317-04)** | `AP.char_eq_hv_trailing`·`MISC.char_eq_trailing`('1.0' 바인드) **1행 → 0행**, `IDX.hv.char.enum` 1 → 0(§3.2) — VARCHAR 미러 + CHAR↔VARCHAR trailing space 구분 = 현행 답 변경(P0 위반, silent) | B7 를 **CHAR 미러(현행)** 로 되돌리고, "VARCHAR(20) 값 → NULL" 결함만 게이트의 CHAR 변환(pd:3128 의 "VARCHAR 값이면 원 값 유지" 의미)에서 고친다. 규칙표 B7 행·§5 "결함 소멸" 문구 수정 |
| R-2 | A5·A8'·S4 INTEGER 미러가 **넓은 바인드를 좁힌다** | `i + ?` BIGINT 2^53+1 → -494(develop bigint 결과), `@v := bigint; @v + 1` → INT 오버플로 오류, `sum(i + ?)` 문자 '1.0' → INT 오버플로(develop double 합) — §7 에 없는 답안 변경 | 유지한다면 §7 에 "정수 형제 산술의 BIGINT/실수 바인드 → 오버플로·-494" 항목 추가 + `sum(i + ?)` 는 리터럴 경로(`sum(i + 1)`)와 같은 오버플로임을 명시. 대안(폭 보존: 형제와 바인드 중 넓은 정수 타입)은 P1·P4(행당 결정 0)와 충돌하므로 권하지 않음 |
| R-3 | **A3' 행 신설**: `str_col * ?`, `str_col / ?`, `str_col % ?` | 프로토타입이 2차 타입 검사 패스에서 `CAST(str_col AS DOUBLE)`(A3 시그니처) 을 형제로 보고 DOUBLE 미러 — 날짜·bit·set 바인드 NULL → -494, monetary → double 표기(§3.2). `str_col + ?`/`- ?` 는 `cannot_use_signature` 라 형제 CAST 가 없어 현행(값 격자) | `str_col ×÷% ?` → DOUBLE(C, K 게이트 값→double), `str_col ± ?` → G(A8 과 같이 값 격자) 로 명시. D-319-03 의 "문자 형제 제외" 는 `±`·COALESCE 류에만 해당 |
| R-4 | A13 ENUM 산술 중 `*`·`/`·`%` | 2차 패스에서 `CAST(enum_col AS SMALLINT)` 형제 → SMALLINT 미러(NULL → 1, double → smallint 표기; §3.2 "패치 한계") | A13 을 `+`/`-`(G, 이름 접합 vs 서수) 와 `*`/`/`/`%`(C SMALLINT 미러 — 컴파일이 이미 서수 CAST 를 만든다) 로 나눔. 승인 전까지 프로토타입 관찰은 "패치 한계" 로 둔다 |
| R-5 | F1 `to_char(?, '<시간 포맷>')` | D-319-04: 시간 토큰만 있는 포맷에 DATETIME 미러를 하면 TIME 바인드가 -494 | F1 에 TIME 하위 행(시간 토큰만 → TIME) 추가. `to_char(@v, 날짜 포맷)` 의 비날짜 문자열(`'1.0'`) 통과 → 오류, 저장 문자열 재포맷('01/02/2024' → '2024-01-02') 을 §7 에 추가 |
| R-6 | U13 결과 타입 | `coalesce(cast(? as datetime), cast(? as datetime), ?)` 문자 바인드 결과 VARCHAR → DATETIME(§3.1) | §7 에 "U13 결과 타입 DATETIME(형제 미러)" 추가 |
| R-7 | U7 COALESCE 류 **사슬 전체의 공통 타입** | `greatest(?, 3, 'b')` 를 이진 미러로 처리하면 안쪽 `(?, 3)` INT → 바깥 `'b'` 와 DOUBLE 충돌 = 컴파일 오류(패치 한계). 규칙 U7 "알려진 형제의 공통 타입(부류 다르면 VARCHAR)" 은 사슬 전체 기준 | 규칙 문구에 "재귀식(COALESCE/LEAST/GREATEST/NULLIF 사슬)은 `recursive_type`(tc:5680)의 사슬 공통 타입을 형제로 본다" 를 명시 — #325 변환기 표 입력 |
| R-9 | **A8'·A5 의 날짜 바인드 -494 규모** | CTP C1(58 케이스: `date_format/time_format/to_char(? + 1, ?)` 13 로케일)·C6(4)·C14(3)·`06_types` — `? + n` 을 "날짜 + n일" 로 쓰는 관용구가 CTP 에만 65곳 | 규칙(D-317-01·10)대로면 허용 후보지만 사용자 재확인 요청: (a) 유지(TC 65건 expected 갱신 + 릴리스 노트 "`? + n` 날짜 바인드는 `? + INTERVAL`/명시 CAST") (b) A8' 만 예외(리터럴 정수 형제는 G 유지) — (b) 는 P1 예외라 규칙표 P1 문구 수정 필요 |
| R-10 | `return_null_on_function_errors=yes` | CTP C5: `s1 / ?` 문자 바인드가 develop NULL(파라미터로 오류 → NULL) → 바인드 시점 -494 | 규칙표에 "게이트 변환 실패는 이 파라미터의 영향을 받는가" 행 추가. 제안: 게이트(서버) 변환 실패도 함수 오류와 같이 파라미터를 따른다(현행 서버 의미 유지, P0) |
| R-11 | **형제 우선순위** | CTP C11 `INSERT … VALUES (IFNULL(?, 0))` decimal(10,5) 컬럼: 리터럴 `0`(INT) 미러가 대입 컬럼 도메인을 이겨 12.34568 → 12.00000(silent; strict 게이트면 -494) | U0(대입 대상) > 컬럼 형제 > 리터럴 형제 순으로 미러 우선순위를 규칙표 P1 에 명시; 리터럴 형제는 "식 결과가 대입/비교 대상에 쓰이면 그 대상 도메인" 으로. #313 의 tc:9748 하향 전파(노드 expected_domain 이 인자로)와 같은 방향 |
| R-8 | D-319-02 중첩 게이트 식 | `(? + ?) + 1`, `abs(?) + 1`, `coalesce(?, ?) + 1` 에 규칙 행 없음(프로토타입 미변경) | collation 축 D-322-02 와 같은 자리에 "게이트 확정 식 ⊂ 형제 있는 식 → 계획된 CAST(형제 타입)" 행 신설 여부를 #323 에서 결정 |

**#323(인터페이스)·#325(변환기 표) 입력**

- **F-1 정수 컬럼 비교 슬롯은 오늘 클라이언트에서 변환되지 않는다.** `int_col = ?` 에 1.5·2.5 → 양쪽 0행, 1.0e0 → 1행(§3.1 B4): 값이 그대로 서버로 가서 값 비교된다. 코드 경로(정적 추정): `pt_infer_common_type(=, INT, MAYBE)` 가 격자 4(숫자×MAYBE → DOUBLE)로 공통 DOUBLE 을 만들고 `PT_ARE_COMPARABLE`(숫자끼리 캐스트 없음)로 캐스트를 생략해 슬롯이 expected_domain 없이 남는다 — #313 §2.2 의 "컬럼 타입 미러(기본 도메인 + LEAVE)" 는 문자 컬럼(C1 경로)에만 맞다. 규칙표 B4 의 "strict-or-keep" 답은 같지만, **게이트가 값을 INT 로 변환하면 답이 바뀔 수 있는 자리**(1.5 → INT strict 실패 → 값 유지 규칙이 정확히 지켜져야 0행 유지). #323 클라이언트 경로 조사에서 `host_var_expected_domains` 의 실제 내용을 숫자 컬럼 비교로 확인할 것.
- **F-2 클라이언트 바인드 캐스트는 반올림한다.** `tp_value_cast_preserve_domain`(→ `tp_value_cast_internal` DOUBLE/NUMERIC/문자 → INTEGER `ROUND`, 문자 '1.5' → 2): 산술 미러 슬롯이 이 캐스트를 타면 1.5 → 2 가 **silent** 로 들어간다(§3.1 A5·A6·U7·U2). 게이트의 K 부류 산술 변환기는 `tp_value_coerce_strict` 의미(손실 → -494)여야 하고, 대입(U0)만 반올림, 비교(B4)는 strict-or-keep — 변환기 표(#325)에 손실 정책 열을 둔다(규칙표 D-317-10 의 3 정책을 함수 단위로).
- **F-3 형제는 "시그니처 캐스트 뒤" 가 아니라 "원 노드" 로 정의해야 한다.** 타입 검사가 두 번 돌면(재작성 뒤 재평가) 첫 패스가 감싼 `CAST(str_col AS DOUBLE)`·`CAST(enum_col AS SMALLINT)` 가 형제로 보여 미러가 달라진다(R-3·R-4). 구현의 컴파일 축은 미러를 첫 패스에서 확정하고 재평가에 멱등이어야 한다(#323 클라이언트 경로 불변식).
- **F-4 재개 아티팩트**: #317 의 develop TSV(`results_all.tsv`)는 크래시 재개 뒤 세션변수를 잃은 구간(`CV.*.enum.*`·`CV.*.set.*`·`SLOT.*`)의 값이 "variable not set" 오류로 남아 있다. 최종 게이트의 셀 비교는 `results_slot.tsv`·`results_rest.tsv`(정상 실행) 또는 재실행값으로 한다. `run_resumable.py` 재개 청크의 라벨 귀속(헤더 줄 수 오프셋)도 재검증 대상.
- **F-6 UNION/VALUES 미러의 대상은 호스트 변수 가지만.** 재귀 CTE 재귀부·서브쿼리 컬럼처럼 1차 패스에서 MAYBE 인 식을 형제 미러하면 답이 바뀐다(C12 `median(m) over()` double → int). 구현의 U2/U4 는 `PT_HOST_VAR` 항목(과 D-319-02 의 슬롯 정의)에만 적용하고 나머지 MAYBE 가지는 G(리스트 컬럼 게이트 표)로 둔다.
- **F-5 -494 의 위치**: 프로토타입에서 늘어난 -494 는 전부 **prepare 뒤 바인드 시점**(`pt_set_host_variables`, 줄 번호 없는 "Cannot coerce host var to type X")이다. 게이트 모델에서는 같은 오류가 서버 게이트에서 나므로 오류 코드는 같고 시점·메시지 인자(XASL id·regu 위치)만 바뀐다(D-318 경계 오류 코드) — TC expected 의 `Error:-494` 텍스트는 유지되지만 오류가 나는 **문장 순서**(prepare vs execute)는 드라이버별로 확인(L-23).

## 6. 렛저 대응표 (A 절)

| L | 이 문서에서 |
|---|---|
| L-02 | §2 CTP: sql 전수 + medium, `_05_plcsql` 포함, targeted 목록 없음 |
| L-03 | §2·§3: optdebug 설치본끼리만 비교, 기준선 nightly 는 develop CI(같은 커밋) |
| L-04 | §4: 실패 목록은 `sql/` 접두 정규화 뒤 비교, 판정은 CTP 로그 OK/NOK |
| L-05 | D-319-08: 셀·탐침에서 패치 결함을 먼저 잡고 CTP 로 |
| L-06 | §4 분류에 `silent`(오류 없이 값이 다름) 등급 최우선; 오류 → 값 전환은 값 A/B |
| L-07 | §2: 완주하지 않은 run 은 증거가 아님, PL 은 CTP stock conf(`stored_procedure=yes`)로 켜서 |
