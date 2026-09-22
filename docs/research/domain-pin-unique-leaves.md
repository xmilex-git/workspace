# 고유 변환 셀과 3차원 변환기 표

지도: [도메인·collation 사전 확정 지도](https://github.com/xmilex-git/workspace/issues/312)
티켓: [고유 로직 leaf 추출 및 정적 변환기 표](https://github.com/xmilex-git/workspace/issues/330)

완료 커밋: [엔진 `4c634e8db`](https://github.com/xmilex-git/cubrid/commit/4c634e8db72b8b0cc9c73a71f8d39fc677144add) · [수용 테스트 `301de3f63`](https://github.com/xmilex-git/cubrid-testcases/commit/301de3f633fb6b9d26276535e4f9d4f7ae4b0956). 각각 `fork/dpin`과 `fork/dpin-tc`에 푸시했다.

기준 엔진은 `dpin`의 `7d753be46`이다. 이 티켓은 기존 CAST/strict 변환을 공유 가능한 고정 타입 셀로 추출하고 표를 제공한다. 계획 작성·G1 게이트·행 실행 경로의 표 사용은 후속 티켓의 범위다. 결정 간 판단은 앞쪽 grilling의 현행 답 보존(D-317-03), 책임 분리(D-325), B7의 정책/항목 배치(D-327-01)를 우선했다. 숫자→TIMESTAMP*를 incompatible로 묶었던 계약 표의 설명도 실제 기존 지원 경로와 기준/후보 SQL 실측에 맞춰 정정했다. API나 변환 규칙의 변경은 아니다.

## 결정과 구현의 대응

| 확정 결정 | 구현 |
|---|---|
| D-325-03·04 / ADR 0022 | 숫자 영역은 기존 템플릿을 재사용하고, 문자·날짜·ENUM·집합·객체·JSON·LOB는 정적 함수로 추출한다. 기존 두 dispatcher의 switch는 유지하며 같은 변환 코어를 호출한다. ENUM→숫자와 문자열 출력도 본문을 공유한다. |
| D-325-05·06 | `[3][41][41]` 정적 배열. C++17 aggregate initializer로 모든 셀을 명시하며, 지원하지 않는 셀은 `tp_value_convert_incompatible`이다. 타입만 받는 조회 API를 유지한다. |
| D-327-01 / B7 | 비교에서 원 VARCHAR 값·collation을 보존하는 예외는 정책·항목의 책임이다. 이를 일반 VARCHAR→CHAR leaf의 예외나 NULL 표 항목으로 옮기지 않는다. |
| D-328-02 | 문자→문자, 문자→비트, 비트→비트 절단은 값을 보존한 `DOMAIN_TRUNCATED`다. 기존 caller가 FORCE·명시·묵시 및 `allow_truncated_string`에 따라 수용하거나 OVERFLOW+clear로 처리한다. |
| D-328-05 | COMPARE INT→TIME은 incompatible이고 ASSIGN 변환만 지원한다. KEEP 판단과 이후 실제 비교 변환을 섞지 않는다. |
| D-328-07 | 날짜·시간대의 37개 도달 함수는 상태 전용 계산 코어와 기존 오류 보고 진입점으로 분리한다. strict는 상태 코어를 호출하고 `er_clear`를 제거한다. |

날짜 파서만 분리하면 그 아래의 인코딩·시간대 연산에서 오류가 남는다. 사용자 정합성 재확인 뒤 티켓 본문에 이 직접 도달 범위를 기록했다. 오류 코드는 스택의 `date_conversion_error`에 저장하고 기존 공개 진입점만 보고한다. 변환 계산과 범위·시간대 규칙은 공유한다. 별도 오류 스택 push/pop이나 새 실패 정책은 추가하지 않았다. LOB의 중첩 문자·비트 변환에서 올라오는 절단 상태도 caller까지 전달한다. 기존 LOB caller가 중첩 변환의 실패 코드를 버리고 NULL을 반환하던 특성은 유지한다. JDBC `setClob`/`setBlob`의 `CAST(? AS CHAR(3)/BIT(4))`는 no에서 NULL, yes에서 `abc`/`a0`이며 FORCE 형태는 두 설정 모두 값을 반환한다. 이는 일반 문자·비트 leaf의 절단 수용 규칙을 바꾸는 예외가 아니라 기존 LOB caller 결과의 보존이다.

문자·비트의 같은 타입·같은 파라미터 경로는 복제하며, 문자 codeset과 precision이 같으면 복제 후 collation 라벨만 바꿀 수 있다. 타입·길이 변환이 필요하면 기존 변환 본문을 실행하여 절단 검사를 유지한다. 기존 caller의 제자리 문자열·비트·집합/VOBJ 경로는 caller에 남긴다. leaf는 원본을 바꾸지 않는다. 지원하지 않는 비트 변환의 기존 오류 보고도 caller에서 보존한다. JSON 값 내부의 숫자·문자·boolean 구분은 JSON payload 해석이며, DB_VALUE 원/목표 타입 dispatcher를 다시 호출하지 않는다.

## 정적 검증

- 표 전체는 5,043셀이다. NULL은 21개 비파라미터 타입의 동일 타입 변환 × 3모드 = 63셀뿐이다. NUMERIC·문자·비트·ENUM·집합·JSON·OBJECT/OID/VOBJ는 NULL 항등 목록에 넣지 않는다.
- client/standalone 표는 변환 775셀·incompatible 4,205셀·항등 63셀이다. 서버 표는 변환 757셀·incompatible 4,223셀·항등 63셀이다. OBJECT/OID 목표의 서버 경로는 incompatible이다.
- 중복 포인터를 제외한 표 항목은 client 469종, server 463종(NULL과 incompatible 포함)이다. 숫자 원형과 ENUM→숫자를 별도로 대조해 지원 조합 누락을 검사했다.
- 추출 블록의 셀·공통 코어·보조 함수 578개에서 금지된 DB_VALUE 타입 switch와 범용 cast/coerce 호출은 0이다. 날짜 코어 37개에는 `er_set`·`er_clear`·`er_errid`와 이전 오류 보고 래퍼 호출이 없다. 기존 strict에도 `er_clear`나 오류 보고 NUMERIC 파서 호출이 없다.
- 문자 재코딩·집합 원소 변환·JSON 처리는 계약 §7에 지정된 기존 보조 API를 사용한다. 실제 피호출 목록은 [변환기 계약 §7](domain-pin-converters.md)에 갱신했다.
- 초기화 후 NULL 수와 항등 집합의 정확한 일치, 모든 행의 41개 항목, 세 모드를 정적으로 확인했다. 표에는 실행 중 채우기나 할당이 없다.

정적 근거: `.git_ignored_dir/scratch/312-330/static-gate.txt`, `static_gate.py`. 포맷 변경은 변경 함수와 새 블록에만 적용하고 코드 토큰 동일성을 확인했다.

## 검증 기록

OptDebug·Release(`RelWithDebInfo`) 양 빌드와 설치가 통과했다. 사용자 최신 방침에 따라 두 빌드는 `UNIT_TESTS=OFF`이며 unit 실행 및 unit 대상 활성화는 제외했다. 최종 설치본은 `.git_ignored_dir/scratch/312-330/install-{optdebug,release}-r2`이다. 공용 `~/CUBRID` 링크는 변경하지 않았다. 빌드 버전은 커밋 전 부모 `7d753be`를 표시하므로, 검증한 소스 6개와 설치 라이브러리/실행 파일의 SHA256을 `r2-build-report.txt` 및 각 빌드 전후 manifest에 보존한다. 빌드 전후 여섯 소스 해시는 양쪽 모두 동일하다. Unix util의 `unittests_lf/area/snapshot/bit`는 CMake에서 무조건 빌드하는 대상이라 `UNIT_TESTS=OFF`인 새 빌드에서도 링크되지만, 해당 실행 파일과 ctest는 실행하지 않았다.

두 빌드 모두 변환 표는 `.data.rel.ro`에 있고, `nm`/`readelf` 실측 크기는 40,344바이트다. relocation 4,980개와 NULL 63개가 소스 정적 검사와 일치한다. 포인터 relocation 때문에 ELF 섹션 이름은 `.rodata`가 아닌 `.data.rel.ro`이며, 표에 대한 동적 초기화 코드는 없다.

| 검증 | 최종 런 | OK / NOK / 전체 | 코어 |
|---|---|---|---|
| SQL | `sql-20260922T152708Z-1166364` | 17468 / 0 / 17468 | 0 |
| medium | `medium-20260922T152643Z-1163733` | 975 / 0 / 975 | 0 |

최종 r2 medium은 직전 `medium-20260922T134723Z-931080`과 정규화된 사례/결과 975개가 정확히 일치한다. notRun·새 assert·signal도 0이다. 독립 비교는 `medium-r2-compare.json`에 있다. SQL은 직전 `sql-20260922T133657Z-905225`의 17,467개와 새 수용 사례 1개를 대조했다. 기존 사례의 결과 변경·누락은 0이며, 추가 1개를 포함해 전부 실제 실행·성공·core false임을 XML에서 독립 확인했다(`sql-r2-compare.json`). 허용 답안 변경은 없다. private HA와 shell은 이번 게이트에 포함하지 않았다. 첫 전수 시도 `sql-20260922T145657Z-1020149`는 오류 코드·EUC-KR 문자열 차이와 btree assertion으로 중단되었다. 기존 caller의 제자리 처리와 비트 fallback 오류 보고를 복원한 r2에서 전수를 통과했다. 실패 런을 완료 근거로 사용하지 않는다.

수용 사례는 `sql/_07_misc/domain_conversion_contract`에 추가했다. 143개 SQL 문장을 기존 설치본에서 실행한 결과를 그대로 expected로 사용한다. JDBC 바인드 `CAST(? AS CHAR(3))`의 no 오류·yes `abc`, 세션변수 CHAR 절단 양 설정, B7, DATE±소수, 순차/인덱스 INT↔TIME, 날짜 파싱 성공/실패, NUMERIC overflow KEEP, 상관 키 및 §7b 값 의존 함수 사례를 포함한다. 날짜 인코딩 범위와 유효/무효 timezone도 포함한다.

기대 답안은 baseline 런 `sql-20260922T143533Z-957657`에서 수집했다(SHA256 `694a1498df7b6ccba0446d40c9beb2d1c17fda747f3743ffaf33ef39628e4ec2`). 빈 expected로 수집한 의도적 mismatch 런이며 pass로 세지 않는다. 첫 시도에서는 CSQL용 문장 끝 주석 때문에 CTP가 SQL을 합쳐 실행한 것을 발견해, 주석을 독립 줄로 옮기고 문장당 한 줄로 정리한 뒤 다시 수집했다. 최초의 누락/합쳐진 결과는 expected로 채택하지 않았다. CSQL과 JDBC가 표시하는 오류 번호는 서로 다를 수 있으므로 이 TC의 expected는 JDBC CTP 실측값이다.


### 동일 DB 카운터 비교

이 티켓에서 새로 만든 `dpin330bench`(1,000,000행, 정수 값 1,000종, 그룹 100개) 하나를 기준/후보 설치본이 차례로 실행했다. 이전 캠페인 DB를 복사하거나 그 로그를 사용하지 않았다. 최종 r2 후보의 81개 변형 × 5회 = 405개 측정에서 반환 행 수와 9개 카운터가 모두 일치했다. 누락·추가 측정 0, 변경 측정 0, 변경 카운터 값 0이다. 순차 375행·병렬 30행이며 시간은 동작 불변 판정에 사용하지 않았다.

| 카운터 | 기준/후보 공통 최댓값 |
|---|---:|
| `Num_domain_resolve_fetch` | 13 |
| `Num_domain_coerce_compare` | 9955000 |
| `Num_domain_resolve_list` | 20008 |
| `Num_domain_resolve_agg` | 6 |
| `Num_domain_key_coerce` | 10374 |
| `Num_domain_px_resolve` | 8 |
| `Num_domain_restore_clone` | 27 |
| `Num_domain_gate_convert` | 0 |
| `Num_planned_convert` | 0 |

원본은 `.git_ignored_dir/scratch/312-330/baseline-runtime/bench-output/counters-baseline/` 및 `counters-candidate-r2-valid/`의 TSV이며, 리드의 독립 비교는 `counter-r2-compare.json`에 있다. 새 물리 DB이므로 key-coerce 최댓값은 과거 티켓의 10,381과 다른 10,374다. 이번 기준/후보는 같은 DB에서 모든 측정이 일치하므로 그 차이를 코드 회귀로 세지 않는다.

중간 설치본의 집중 런 `sql-20260922T143931Z-970292`는 1/1 통과했지만 최종 전수 게이트를 대신하지 않는다. 중간 SQL 전수 `sql-20260922T144606Z-983075`와 268개 측정에서 중단한 중간 카운터는 최종 소스 보완 후 중단했으며 완료 근거에서 제외한다. 수정 후 최종 검증은 `install-optdebug-r2`의 바이너리와 그 해시가 같은 카운터용 사본만 사용한다. 이전 `install-*-final`·`install-*-r1`은 중간 후보이며 완료 근거에서 제외한다.

벤치의 첫 최종 설치본 시작 시도는 SQL 실행 전 긴 UNIX datagram 소켓 경로에서 실패해 코어 1개를 남겼다. 파일은 `baseline-runtime/counter-candidate-final-install/log/coredump/cub_server_20260922235305.455.coredump`이며 SHA256은 `27a2bce253ab95ba66cb57d930f2ea8cca12793a3b5ddcb366390577d9587c72`이다. 이 시도는 성공 게이트에서 제외하고 코어/시작 로그를 보존한다. 짧은 소켓 경로 `scratch/312-330/ctrsock`로 실행한 최종 405개 측정의 stderr는 모두 비었고, 실행 뒤 소유 서버·broker·컨테이너·소켓·포트 claim을 정리했다. 새 DB와 증거 파일은 보존했으며 기존 1523/1700 리스너는 건드리지 않았다. 이 파일은 ELF core가 아닌 CUBRID 텍스트 스택이다. 같은 라이브러리로 심볼화한 결과 긴 소켓 경로의 `bind(EINVAL)` 오류를 보고하는 기존 `master_connector.cpp:458` 경로가 `%1$s` 인자를 주지 않아 `strlen`에서 SIGSEGV가 발생했다. SQL 수행 전의 환경 유발 실패이며, 이번 변환 경로의 회귀 근거로 분류하지 않는다. 상세는 `core-startup-triage.txt`에 보존한다.

### 첫 전수 실패의 추적

- BIT/VARBIT의 지원하지 않는 원 타입에서 기존 `db_bit_string_coerce`가 설정하던 오류가 빠졌다. JDBC 최소 재현의 숫자 default·CURRENT_TIMESTAMP default에서 기존 -425가 -495로 바뀌었으며, caller의 fallback 보고를 복원했다. CSQL의 오류 문구만 비교하면 이 차이가 보이지 않는다.
- EUC-KR 문자열의 제자리 변환 경로가 복제로 바뀌면서 공백 결과가 달라졌다. 기존 caller의 문자열/비트 steal·집합/VOBJ 재사용을 보존하고 leaf는 const 원본 계약을 지킨다.
- 추가 JDBC 경계 검사로 발견한 bound LOB 절단은 중첩 leaf의 상태 전달과 기존 caller 매핑을 복원했다. 원본은 `error-diagnostic/results/{baseline,r2}/jdbc-{error,lob}-probe.tsv`다.
- 첫 전수의 btree assertion core는 matching CTP libc/libpthread와 설치 라이브러리로 분석했다. `catcls_update_catalog_classes("dba.ta") → catcls_find_oid_by_class_name → btree_fix_root_with_info`에서 root page가 NULL인데 현재 오류 ID가 0인 상태였다. interrupted/shutdown은 false이고, 하위 page-buffer의 실패 원인은 코어만으로 확정하지 못했다. `core-ctp-triage.txt`와 ELF/텍스트 core를 보존한다.
- 정확한 부모 7d753be 소스/바이너리/CTP 설정을 검증한 15개 집중 런 `sql-20260922T151514Z-1053633`은 14 OK/1 trace NOK/core 0이었다. 같은 hash-join 디렉터리의 부모 런 `sql-20260922T151629Z-1057029`는 6 OK/2 trace NOK/core 0, 수정 전 후보 런 `sql-20260922T151736Z-1062075`는 8 OK/0 NOK/core 0이었다. isolated trace 차이를 답안 변경으로 수용하지 않으며, 이 집중 런들은 전수 게이트를 대신하지 않는다.

수정 후보의 집중 런 `sql-20260922T152453Z-1135039`는 기존 실패 15개와 수용 사례 1개를 합쳐 16/16 OK, NOK/core 0이다. 별도 JDBC 오류 최소 재현 10행 및 LOB 경계 12행도 기준과 후보 r2가 일치한다(`jdbc-r2-compare.json`).

최초 r2 카운터 실행 사본에는 기준의 `parallelism`·`max_parallel_workers` 설정이 누락되어 p0에서도 PX 카운터가 발생했다. 설정이 다른 이 405개 측정은 `counters-candidate-r2`에 보존하며 최종 비교에서 제외한다. 수정된 벤치 사본은 기준과 같은 `parallelism=0/24`, `max_parallel_workers=100`, `stored_procedure=yes`, `data_buffer_size=512M`을 사용한다. 서버 파라미터 조회로 실제 적용값까지 확인했다. 엔진 소스·바이너리는 바꾸지 않았다.

최종 r2 전수에서는 앞서 assertion을 발생시킨 사례까지 포함해 17,468개 모두 통과했고 코어·새 assertion은 0이었다. 앞선 코어의 하위 page-buffer 원인이 확정되었다거나 별도 btree 버그를 수정했다고 주장하지 않는다. 이번 티켓에서 storage/transaction 소스를 수정하지 않았으며, 이전 실패 증거와 최종 통과 결과를 구분한다.

파라미터 조회용 서버를 처음 띄운 시도에서도 긴 UNIX 소켓 경로의 같은 시작 오류가 반복되어 ASCII crash stack 8개를 남겼다(`20260923003340`~`20260923003427`, baseline/final/r2-raw/r2-valid 사본에 각 2개). 이 시작 실패들은 SQL/카운터 검증에 포함하지 않는다. 짧은 소켓 경로에서 조회한 유효 설정은 기준·수정 사본이 0/24, 첫 r2 사본은 두 단계 모두 4였다. 실패 파일을 삭제하거나 성공 런의 core 0에 섞지 않고 보존한다. 기존 설치본에서 복사된 과거 crash 로그도 신규 코어로 세지 않는다.
