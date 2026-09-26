# 도메인·collation 사전 확정 — 이전 캠페인 교훈 렛저

지도: xmilex-git/workspace#312 · 작성 2026-09-22 · 출처: 이전 캠페인(호스트 변수 도메인 사전 확정, 2026-09-15~21)의 해소 기록 전부를 읽고 **내용만** 옮겼다. 이전 티켓 번호·커밋·브랜치는 참조하지 않는다(사용자 결정: 브랜치·커밋은 버리고 경험치만).

형식: **L-nn 변경(무엇을 이렇게 바꾸면)** → **오류/상황(이런 일이 났다)** → **고려(새 지도에서 이렇게 한다 / 규칙표·아키텍처가 답해야 할 것)**.
규칙표 티켓(#317)·아키텍처 티켓(#318)·조사 티켓(#313·#314)은 이 문서를 필수 입력으로 읽고, 각 항목을 자기 산출물에서 "어디서 다뤘는지" 표시한다.

---

## A. 진행 방식·게이트 (이것부터 안 지키면 아래 전부 반복된다)

- **L-01 규칙을 먼저 잠그지 않고 구현부터** → CTP 가 규칙을 대신 정했다. 한 티켓 43커밋 중 26개(60%)가 같은 범위의 선행 커밋을 고치는 커밋(최장: 컬렉션 collation 7단), 워크트리 30개, 프런티어가 안 닫힘 → 규칙표(#317)와 탐침(#319)이 끝나기 전에는 구현 티켓을 만들지 않는다. 구현 중 발견한 새 규칙은 코멘트가 아니라 **규칙표 개정 + 사용자 승인**.
- **L-02 targeted CTP(120 디렉터리 / 3,011건)만으로 게이트** → PL/CSQL·`to_char` 로케일·collation·세션변수 디렉터리가 하나도 없어 **조용한 오답 2건과 결함 27건이 전수에서 처음** 드러났다("조용한 오답 0" 을 주장한 뒤였다) → 탐침(#319)은 처음부터 **sql 전수 + medium**. targeted 목록을 쓰는 게이트는 규칙표가 건드리는 부류(자유 문맥 슬롯·PL/CSQL·세션변수·로케일·collation·다중 행 VALUES·MERGE/CTE)의 디렉터리를 반드시 포함.
- **L-03 release 전수를 optdebug 비교 기준선으로** → optdebug 전용 assert 2계열을 못 봤고, 같은 크래시를 4번 오진했다 → 기준선은 optdebug 하나, 비교는 같은 빌드끼리, 실패 수 옆에 빌드 타입·provenance.
- **L-04 CTP 실패 목록을 `sql/` 접두 정규화 없이 비교** → 29건을 "신규 회귀" 로 오판하고 bisect 를 했다 → 목록 비교는 접두 정규화 뒤, 판정은 각 샤드 CTP 로그의 OK/NOK.
- **L-05 게이트 안 된 커밋 위에 다음 커밋** → 덩어리로만 검증 가능, 회귀 1건에 게이트 한 판 → 게이트 안 된 커밋 위에 올리지 않는다. 한 회귀에 수정 2회 실패면 멈추고 재계획. 이전 세션의 분류를 재측정 없이 믿지 않는다(31건 → 재측정하니 27/3/1).
- **L-06 하드 에러를 없애는 수정** → ENUM 비교에서 슬롯이 "문맥 없는 마커=VARCHAR" 기본값으로 떨어져 `e1 <> 3` 이 정수 3 을 문자열로 비교, 전부 불일치로 **8행 반환(정답 7행)** — 에러가 조용한 오답으로 바뀜(net-negative) → "에러 → 값" 으로 바뀌는 모든 수정은 값 A/B 로 확인. 실패 분류에 `silent`(에러 없이 값이 다름) 등급을 두고 최고 우선.
- **L-07 완주 안 된 CTP·conf 미적용 설치본** → core/timeout 으로 멈춘 run 을 통과 증거로 씀, `stored_procedure` 가 꺼진 설치본으로 PL 결함을 못 봄, 컨테이너 `pids.max` 2048 로 샤드 병렬이 죽음 → 완주하지 않은 run 은 증거가 아니다. PL 은 켜고 돌린다(CTP stock `sql.conf` 는 이미 `stored_procedure=yes`). `pids.max` 8192.
- **L-08 티켓 수락 기준을 중간에 올림** → "필드 삭제" 로 닫을 수 있던 티켓을 "불변 XASL 전면" 으로 올려 엔진 전체(checkdb·FK·컬렉션·해시 조인)에 전칭 명제를 증명하려다 닫지 못함 → 수락 기준은 본문에 고정, 상향은 새 티켓.

## B. 컴파일 규칙 — 슬롯(호스트 변수·auto-param)의 타입

- **L-10 문맥 없는 슬롯 기본을 하나로(VARCHAR 또는 NUMERIC)** → ENUM/SET/컬렉션 문맥에서 서수 비교가 조용히 깨지거나(L-06) bind 가 거부됐다(ENUM 컬럼 타입을 `?` 에 미러하면 -494, optdebug assert 97회) → 규칙표에 **ENUM/SET/컬렉션/객체** 행을 따로 둔다: 미러는 스칼라 기본형만, ENUM+숫자 = ordinal 승격, 컬렉션·객체 미러 금지. "값 타입에 따라 의미가 갈리던 동작"(ENUM `e1 + ?` 가 정수/실수/접합/날짜, `e1 < ?` 가 서수/사전식)은 PG 처럼 표현 수단을 없앤다.
- **L-11 NUMERIC 슬롯을 고정 p/s 로 캐스트** → `db_value_domain_init` 이 값 scale 을 0 으로 덮어 12.34568→12, PL/CSQL `TRUNC(0.40)`→`0.0` → 캐스트는 타입만, **값의 p/s 보존**. 새 지도의 DOUBLE 공통 타입은 이 문제를 **다른 모양**으로 옮긴다: BIGINT 범위 정수의 정밀도 손실, NUMERIC(p,s) 컬럼과의 산술 결과 표기(`4`→`4.0`, 대형 값의 DOUBLE 표기 vs NUMERIC 표기), 정수 나눗셈 절삭 → 규칙표가 **조합별 결과 타입과 표기**를 명시하고 답안 변경으로 기록.
- **L-12 정수 컬럼과의 `+`/`-` 에서 슬롯을 정수로 고정** → `i1 - ?` 에 1.1 을 바인드하면 소수부 절단(조용한 오답). 넓혀서 `/`·MOD 까지 floating 으로 하니 **정수 나눗셈 절삭 의미론**이 깨져 회귀 → 연산자별 규칙 분리: `+`/`-`/`*` 와 `/`/`DIV`/`MOD` 는 다른 행. ENUM 서수 승격 경로도 같은 규칙을 받아야 한다(한 경로만 빠져 `e1 + ?` 1.1 → 2 조용한 오답).
- **L-13 문맥 없는 `? + ?` 를 산술로 고정** → 이전에는 접합(문자열)이었고 매뉴얼 `plus_as_concat` 절과 어긋난다. `? + 1` 리터럴 상대도 같은 규칙이어야 한다(2.7 → 4 조용한 오답이 있었다) → 규칙표에 `? op ?`, `? op 리터럴`, `? op 컬럼` 행. 매뉴얼 1줄·릴리스 노트.
- **L-14 슬롯을 VARCHAR + 시스템 collation `data_type` 으로 승격** → 호스트 변수 전용 collation 경로를 우회해 -1150 "collation 충돌", `string_opfunc.c` assert(53건) → **도메인 축과 collation 축은 별개**. 슬롯 collation 은 규칙표가 따로 정한다(컴파일 클라이언트 collation 고정 / 미지정+use-site 결정 / 게이트 확정 중 하나). 비교·LIKE 의 형제 컨텍스트를 **PLUS 내부·중첩 산술·함수 인자(`rtrim(?+?, ?)`)·IN-리스트** 의 슬롯까지 하향 전파해야 한다(빠지면 "Cannot coerce host var to type numeric").
- **L-15 세션변수 읽기를 VARCHAR typed 슬롯으로** → (a) `bit(128)`·DATE 를 담은 변수 비교 -494(쓰기 `PT_DEFINE_VARIABLE` 은 타입을 기억, 읽기 `PT_EVALUATE_VARIABLE` 은 버린다), (b) `evaluate concat('a', lpad(@i, 3))` -494(SELECT 에서는 정상), (c) `to_char(@d)` 1인자는 값 도메인(DATE)을 보고 2인자는 오류 — **경로마다 다른 타입**, (d) `addtime(@v, time)` optdebug assert(release 는 문자열 결과), (e) `@a + 1` 표기 변경 → 규칙표가 세션변수 읽기 타입을 **결정**한다(저장 타입 / VARCHAR 고정 / `set` 시 타입 고정 + 재대입 오류). 저장 타입을 쓰면 플랜 캐시의 슬롯 타입이 재대입으로 stale 해지는 문제가 따라온다.
- **L-16 PL/CSQL 인자를 맨 `?` 로 두고 컴파일 기본 타입에 맡김** → NULL 바인드가 NUMERIC 계약에 -889 로 거부(8건; 주석은 "NULL 은 typed NULL" 이라 했는데 구현이 달랐다), `FIELD()` 3→0·`DECODE` ok→nok **조용한 오답**, CAS 죽음 -21019. SQL 텍스트에 `CAST(? AS T)` 를 끼워 넣는 우회는 **실패**(CAST 는 식이라 슬롯과 다르게 취급되는 자리가 많다) → prepare 시 **선언 타입 전달**(PG `param_types` 모델) 여부를 규칙표/아키텍처에서 결정. NULL 바인드는 어떤 계약에서도 typed NULL 로 수용.
- **L-17 GENERIC 함수 인자 자리를 STRING→VARCHAR / NUMBER→NUMERIC 으로 일괄 고정** → `to_char(?, ?)` 값 슬롯이 NUMERIC 으로 고정되어 datetime/timestamp 바인드가 **전 로케일 26건** -494, 포맷이 리터럴인 `to_char(?, 'YYYY-MM-DD')` 도 같음(JDBC 흔한 패턴). `from_tz(?,?)`/`new_time(?,?,?)`/`TO_DATE` 계열은 시그니처 불일치 -889/-621 → 규칙표에 **함수 시그니처별 인자 기본형** 행(오버로드가 여러 개인 함수는 포맷 리터럴·형제 인자에서 추론 or 모호 오류(PG)).
- **L-18 다중 행 `VALUES (timestamp '…'), (?)`** → 두 번째 행 `?` 가 첫 행 타입을 못 받아 리스트 컬럼 도메인이 열린 채 mainblock → optdebug abort, release "Invalid XASL tree node", develop -181 → 규칙표에 VALUES 행·열 위치 미러(첫 행 타입 → 슬롯), UNION/CASE/COALESCE 와 같은 "공통값" 부류로 묶는다.
- **L-19 `coalesce(cast(? as datetime), cast(? as datetime), ?)`** → 결과 컬럼 도메인이 **collation 플래그를 물고** 나와 클라이언트 optdebug assert / release CAS 죽음 → 비문자 결과 도메인에 collation/charset 플래그가 남지 않도록 도메인 구성 규칙 명시(도메인 캐시 정합). (#358 확인: develop `c63a3b993` 은 이 문장에서 assert·CAS 사망이 없다 — 이전 캠페인 변경의 산물. 같은 문장에서 dpin 의 게이트 결정이 NULL 상수 피연산자 때문에 develop 과 달랐다 → [#364](https://github.com/xmilex-git/workspace/issues/364).)
- **L-20 KEYLIMIT/LIMIT 상수식과 다른 호스트 변수 공존** → 슬롯 시딩이 상수 폴딩 반환값을 버려 두 번째 keylimit 값 유실(오답) → LIMIT/KEYLIMIT 식 내부 슬롯은 BIGINT, 재타이핑 반환값 사용.
- **L-21 MEDIAN/PERCENTILE 문자열 입력을 CAST 요구로 닫음** → 인자 축만 닫혔고 **정렬 키**(`percentile_cont(0.2) within group (order by varchar)`)는 `cmp_dom` 지연 결정이 남아 -494(파일에 `?` 없음) → 규칙표는 인자 축과 정렬 키 축을 둘 다 다룬다(거부+CAST vs 컴파일 확정).
- **L-22 auto-param 리터럴 슬롯의 도메인을 믿음** → `col7 = to_number('3')` 슬롯 도메인은 NUMERIC(식의 타입 체크 결과), 묶인 값은 INTEGER → 키 변환 전략이 갈려 키 인코딩이 달라짐(`ER_QPROC_INVALID_XASLNODE`) → 둘 중 하나만 참: **슬롯 값을 게이트에서 계획 도메인으로 실제 변환**하거나(D-M4 방향), 리터럴·바인드 슬롯은 값 타입이 정본. 새 지도는 전자이므로 게이트 뒤에는 "값 타입 ≠ 계획 도메인" 이 불변식 위반(assert).
- **L-23 답안 변경으로 기록해야 했던 것들**(규칙에 맞아 허용했지만 TC/매뉴얼이 따라와야 했다): bind 오류가 execute→prepare 로 앞당겨짐(-494/-181 시점 이동), `SELECT ?`/`CASE ? WHEN ?`/`ifnull(?, 1)` 기본 타입, CASE/DECODE 공통값 고정으로 분지 선택 변경, CHAR 컬럼 `= ?` 의 trailing space 의미, overflow 발생 시점 이동, 재작성 질의 텍스트의 use-site CAST 표기, `typeof` 표기 → 규칙표 결정마다 "답안 변경 항목" 열을 둔다. escape hatch 파라미터는 두지 않는다(복구 수단은 명시 CAST).
- **L-24 미실행 문장**(`WHERE 1 = 0`, `LIMIT 0`)은 클라이언트가 서버 실행을 건너뛴다 → 값 의존 컬럼 metadata 가 `(0,0)` 으로 남음 → 새 지도는 컴파일이 도메인을 정하므로 대부분 사라지지만, 게이트에서만 정해지는 잔여가 있으면 같은 구멍이 남는다 → 아키텍처에서 "게이트 잔여 0" 을 목표로 하거나 매뉴얼 문구.
- **L-25 prepared 슬롯 collation 이 `ALTER … COLLATE` / `SET NAMES … COLLATE` 뒤에도 고정** → i18n LIKE 행 1개 소실. 플랜 캐시 키에 클라이언트 collation 을 넣고 `SET NAMES` 에서 SQL-level prepared statement 를 재컴파일하는 시도가 있었다 → 규칙표: 슬롯 collation 의 확정 시점과 재컴파일 트리거(스키마 collation 변경·세션 collation 변경).

## C. 클라이언트·CAS·드라이버

- **L-30 클라이언트가 바인드 값을 기대 도메인으로 캐스트하는 분기를 추가** → `host_var_expected_domains[]` 는 사용자 `?` 만 담는데(auto-param 제외) 순회를 `host_var_count`(auto-param 포함) 만큼 해 OOB → cub_cas **SIGSEGV**(-21019/-21003/-21024, JDBC 30초 timeout 77건이 전부 이것) → 새 지도는 클라이언트 캐스트 자체를 없앤다(D-M4: 값은 그대로, 게이트가 변환). 남는 것은 **사용자 `?` 배열 vs auto-param 카운트 불변식**(PREPARE 이름 재사용·EXECUTE PREPARE 경로 포함) — assert 로 고정.
- **L-31 결과 컬럼 metadata** → 슬롯 도메인이 `(0,0)`/VARIABLE 이던 것이 구체 도메인으로 바뀌면 JDBC/CCI 가 보는 메타가 바뀐다. 이전에는 execute 응답의 `include_column_info` 경로를 재사용해 드라이버 무변경으로 해결 → 새 지도는 컴파일이 정하므로 **prepare 응답**에 확정 도메인이 실린다. CAS/JDBC/CCI 로 실측(홀더블 커서·재실행·PREPARE 이름 재사용 parity).
- **L-32 세션변수·PL/CSQL 은 클라이언트가 아니라 서버가 값을 만든다** → 클라이언트 바인드 경로만 고치면 이 둘은 빠진다 → 게이트가 다루는 "슬롯" 의 정의에 세션변수 읽기·PL/CSQL 인자·auto-param 리터럴을 명시적으로 포함/제외.

## D. 서버 게이트·실행 하위

- **L-40 잔여(게이트에서 정하는 것)를 XASL 노드 필드로 pack/unpack** → 문장 종류(SELECT/INSERT/UPDATE/DELETE/MERGE/DO)마다 루트 부착 지점 6곳, 패킹 arena 수명, 스트림 포맷 변경 → 이전 캠페인은 **unpack(load) 시점에 스트림 구조에서 도출**해 포맷·코덱을 안 바꿨다. 새 지도의 **변환 계획**은 pack 대상이 될 수밖에 없으므로(컴파일 산출) 아키텍처가 스트림 포맷·플랜 캐시·XASL 클론(xcache clone / 비캐시 / PX 워커 unpack)의 세 로드 경로 모두를 다룬다. 함수 인덱스·필터 predicate 스트림에는 게이트가 없다 → 잔여가 있으면 load 거부.
- **L-41 슬롯만 pin 하고 파생 소비자를 안 건드림** → 중간 리스트 컬럼·`TYPE_POSITION` regu·스칼라/상관 하위질의·**MERGE·CTE 하위 XASL**·INSERT SELECT 가 VARIABLE 로 남아 조용한 NULL/오류(MERGE 값 의존 소스는 develop 정상 / 캠페인은 NULL) → 게이트는 pin 직후 mainblock 전 **생산자 우선 1회 순회**로 위치 서술자·정렬/그룹 키·누산기·분석함수·하위질의·출력 식(중첩 포함)에 전파. 정적 계획은 순회 0. MERGE 하위 계획은 spec 에 생산자 XASL 이 없어 위치를 못 매핑한다(스캔 open 에서 1회가 최선). 새 지도에서는 컴파일 변환 계획이 파생 소비자까지 포함해야 게이트 순회가 필요 없다.
- **L-42 `original_domain` 복원(실행 뒤 원복)을 지움** → 플랜 캐시 클론에 실행별 설치가 남아 **다음 실행이 이전 타입을 본다** → "쓰고 복원" vs "불변 플랜 + 실행 상태(slot ID)" 모델 결정을 아키텍처가 먼저 한다. 답은 실행 상태(`XASL_STATE`)에만 두고 플랜에 쓰지 않는 것이 목표.
- **L-43 누산기·분석함수** → 누산기 초기화가 pin 을 NULL 로 덮음; 분석함수 누산기 DB_VALUE 에 타입이 없어 `max(str_to_date(s, ?)) over ()` 가 **NULL**(setval 무음 no-op), 같은 plan 을 다른 포맷으로 재실행하면 `mr_setval_date` abort; 집계·분석 `opr_dbtype` 이 인자 노드의 MAYBE 를 그대로 받음; 워커 누산기 도메인을 첫 non-NULL 값에서 잡는 폴백; 집계 첫 non-NULL 대기·분석 첫 값 블록 → 누산기 도메인은 피연산자 도메인에서 setup 시 계산, 첫 값 대기 코드 삭제, 그 자리에 경계 assert.
- **L-44 MRO/top-N 정렬 도메인을 인덱스 키 스키마에서 시딩** → `is_desc` 가 따라와 **이중 역전** 21건 → 오름차순 사본으로 시딩.
- **L-45 인덱스 키 변환** → (a) 전략(AS_IS / 값 p/s / strict / 불가)은 스캔 준비 시점에 1회 확정하고 range 생성은 소비만, 값으로 전략을 다시 고르면 계약 위반이 숨는다; (b) 바인드 불변 키(실행당 1회)와 상관/조인/skip-scan 키(range 마다 값 변환, 전략 재추론 없음)를 구분; (c) key1/key2 가 기술 캐시를 공유하면 상한이 하한 도메인으로 기록됨 → 분리; (d) **ISS 내림차순은 유일한 bound 를 key1→key2 로 옮긴다** → fetch 범위 전용 계획 쌍 필요(없으면 `ER_QPROC_INVALID_XASLNODE`); (e) ISS 첫 컬럼 도메인은 값이 아니라 인덱스 스키마(`key_type->setdomain`); (f) 인덱스 키 도메인은 루트 헤더와 같은 바이트인 `index_entryp->key_type` 을 XASL(`INDX_INFO`)에 실어 카탈로그 재계산을 피함; (g) PX 경로는 `prebuilt_midxkey_domains` 를 해제하지 않던 누수가 있었다.
- **L-46 PX 워커** → 워커→루트 도메인 역전파·샘플 3종이 있었고, 워커는 루트의 답을 pin_id 로 설치하는 3번째 결정 지점이었다. 게이트가 연결 스레드에서 평가·캐시한 연산자 슬롯 값을 **같은 트리의 aptr 를 실행한 PX 워커가 해제** → 교차 mspace free 힙 손상 abort(release 포함), `FOOTERS=0` 이라 검출이 레이아웃 의존 → **비단조 bisect** → 새 지도(D-M3)는 워커 결정 0. 게이트가 만든 값의 소유 스레드·해제 시점을 계획에 명시하고, 워커 clone 은 값이 아니라 계획을 상속.
- **L-47 collation 축** → `VARIABLE || COLL_LEAVE` 한 조건문에 타입 축과 collation 축이 섞여 있다. 타입 축을 전부 지워도 슬롯 collation 을 미지정(LEAVE)으로 두는 계약 때문에 실행 중 도메인 변경이 29회 남았다(순수 collation 디렉터리 0회, 호스트 변수 TC 에서만) → 새 지도는 게이트에서 collation 까지 확정(D-M4)하므로 LEAVE 계약 자체를 없앨지 규칙표가 정한다. 남으면 연산자 결과 2 + 리스트 컬럼 11 지점이 그대로 남는다.
- **L-48 검증 경계** → (a) load 경계 "잔여 아닌 VARIABLE 금지" 는 켤 수 없었다: `TYPE_REGU_VAR_LIST` 숨은 포장 노드·분석 윈도우 정렬 키·집합 연산 컬럼이 설계상 VARIABLE. (b) 실행 경계는 리스트 파일 컬럼 도메인(`qdata_get_valptr_type_list`)에 assert + release 오류 반환으로 설치했고 이것이 L-18 크래시를 드러냈다 → 아키텍처가 경계 (a)/(b) 의 예외 목록을 처음부터 표로 가진다. `fpcache_claim`/`filter_pred_cache` 의 오류 삼킴(load 실패에 NO_ERROR + NULL)은 고쳐야 경계가 보인다.
- **L-49 플랜 공유** → 같은 플랜을 다른 타입 리터럴로 실행해도 오답은 없었다(실행이 슬롯 도메인이 아니라 값 타입을 읽기 때문). 새 지도에서 게이트가 값을 계획 도메인으로 변환하면 **플랜 도메인을 믿는 소비자**(`scan_check_user_given_keylimit_overflow` 의 NUMERIC assert 등)가 노출된다 → 변환 뒤 값 타입 = 계획 도메인이 불변식이므로 오히려 단순해지지만, auto-param 슬롯의 도메인이 값보다 넓은 경우(L-22)를 규칙표가 먼저 좁혀야 한다.
- **L-50 부수 관측 변화** → trace 의 `Query plan:` 블록 소실, 직렬 인덱스 스캔 trace 에 `iss: true`/`loose_index_scan` stat 이 새로 생김, `-494` 가 `-495` 로 → TC diff 로 잡힌다. 트레이스·오류 코드 변경도 답안 변경 목록에 넣는다.
- **L-51 행당 비용 지점(참고, 삭제 대상 목록의 씨앗)** → fetch fast-peek 차단(`domain == VARIABLE` 검사), `eval_value_rel_cmp` 타입 분기, `tp_value_compare_with_error` 임시 강제변환, 산술 도메인 탈착·복원, REGUVAL_LIST 원본 저장, 리스트 도메인 재시도, btree 키 비교 폴백, 클론 디캐시 원복, `resolve_domains_on_list_scan` 이 `scan_next_list_scan` 안(행마다), GROUP BY/정렬 키/해시 파티션 키/분석함수 도메인 결정이 패스마다, connect-by 프로브 p/s 재조정, INSERT 기본식 `db_to_char` 포맷 도메인, COALESCE/NVL2/NULLIF/LEAST/GREATEST 가 `domain == NULL` 이면 두 값에서 공통 타입 추론, GROUP_CONCAT 기본 VARCHAR → 조사 티켓 #314 의 출발 목록.

## E. PG/기타 대조에서 확인된 것(재조사 시 출발점)

- PG 는 미확정 파라미터를 PREPARE 에서 거부하고 저장된 `param_types` 로만 Bind 값을 읽어 "값 타입에 따른 의미 분기" 가 구조적으로 불가능하다. 리터럴은 슬롯으로 올리지 않는다(auto-param 없음). 숫자 카테고리 preferred type 은 float8. unknown 리터럴은 text. collation 은 implicit/explicit/none 3단계, 충돌은 오류.
- Oracle 은 `CURSOR_SHARING=FORCE` 일 때만 리터럴을 bind 로 바꾸고 타입/길이가 다르면 child cursor 로 분리한다. 문자↔숫자 비교는 문자 쪽을 NUMBER 로 변환.
- 세 DB 모두 값을 반올림해서 인덱스를 쓰지 않는다: 의미를 지키고 인덱스를 포기(PG·Oracle)하거나, 키를 값 도메인으로 기술(CUBRID).
- `int_col = 1.5` 는 CUBRID 가 인덱스를 쓰면서 정확(strict 실패 → 원 값 유지 + 값 도메인 키 기술), PG 는 seq scan.
