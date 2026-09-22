# 숫자 변환 셀 추출

지도: [도메인·collation 사전 확정 지도](https://github.com/xmilex-git/workspace/issues/312)
티켓: [숫자 부류 leaf 추출](https://github.com/xmilex-git/workspace/issues/329)

상태: 구현 및 양 빌드·SQL 전수·medium·카운터 비교 완료. 기준 엔진은 `dpin`의 계측 커밋 `8764c55ba`이며 변환 동작은 develop `cad27172b`에서 이어진다.

엔진 커밋: [`7d753be46` — Extract fixed-type numeric conversion templates](https://github.com/xmilex-git/cubrid/commit/7d753be46d211b76b17b47d9fc9aaaca1e3c03d5). 빌드 버전 문자열은 커밋 전 부모 `8764c55`를 표시하며, 최종 소스 4개의 해시가 검증 시점의 `build-provenance.txt`와 같음을 확인했다.

## 구현 범위

- `object_domain.c`의 `tp_value_convert_number<SRC,DST,MODE>`가 숫자 변환식을 공유한다. `if constexpr`로 원 타입·목표 타입·모드별 코드를 정하며, 실행 중 타입 switch를 추가하지 않는다.
- 원 타입 9종(SHORT, INTEGER, BIGINT, FLOAT, DOUBLE, MONETARY, NUMERIC, CHAR, VARCHAR), 숫자 목표 7종, 모드 3종의 189개 표 항목을 `index_sequence`로 생성한다. 항등도 표에 셀을 갖는다. 지원 범위를 빠뜨리면 템플릿의 `static_assert`가 컴파일을 거부한다.
- `object/object_domain_convert.h`는 셀 선언과 숫자 영역 표를 제공한다. 전체 타입의 3차원 표·조회 함수 및 문자/날짜/ENUM 등의 고유 셀은 다음 티켓의 범위다.
- `numeric_opfunc.c`는 목표 타입 고정 하위 연산 12개와 `numeric_coerce_value_to_num<SRC>`를 제공한다. 기존 NUMERIC 진입점은 switch를 유지하면서 이 연산을 공유한다. ENUM→NUMERIC도 기존 진입점의 동작을 보존하기 위해 같은 원 타입 템플릿으로 연결한다.
- 문자→NUMERIC은 상태 전용 파서 코어 `numeric_coerce_string_to_num_status`와 기존 오류 보고 래퍼로 분리한다. 기존 CAST·strict 진입점의 오류 보고와 상태 사상은 유지한다.
- NULL·동일 타입 조기 반환·입출력 alias 처리는 기존 진입점에 남긴다. 셀 호출자는 목표 DB_VALUE 도메인을 초기화하며, 셀은 원·목표 타입을 다시 선택하지 않는다.

근거는 ADR 0022, 변환기 계약 §0b·§2.1·§2.2·§2.7·§7·§7b, D-328-01·07이다. 타입 규칙이나 성공 조건을 새로 정하는 변경은 포함하지 않는다. 실제 피호출 목록은 변환기 계약 §7-1에 기록한다.

## 검증

최신 사용자 방침에 따라 단위 테스트·단위 테스트 활성화·의도적 누락 컴파일 테스트는 제외한다.

- optdebug·release 빌드 및 설치 완료. 두 빌드 모두 `UNIT_TESTS=OFF`이며 공용 `~/CUBRID` 링크는 변경하지 않았다.
- 각 빌드의 server·client·standalone 라이브러리 모두 숫자 셀 템플릿 심볼 189개를 포함한다. 숫자 표는 1,512바이트이며 `.data.rel.ro`에 위치한다. 런타임에 표를 할당하거나 채우지 않는다.
- 셀과 명시한 NUMERIC 하위 연산 20개 함수 본문에서 금지된 DB_VALUE 타입 switch·범용 변환 래퍼 호출 0개를 확인했다. 근거: `.git_ignored_dir/scratch/312-329/static-gate.txt`, `compiled-cells.txt`, `build-provenance.txt`.
- 초기 빌드에서 공용 NUMERIC 헤더를 읽는 C 번역 단위에 C++ 선언이 노출된 오류를 수정했다. 새 선언은 `__cplusplus` 가드 안에 있으며, 통과한 양 빌드는 수정 후 소스다.

optdebug 컨테이너 CTP 결과:

| Suite | Run | OK / NOK / 전체 | 코어 |
|---|---|---|---|
| SQL | `sql-20260922T133657Z-905225` | 17467 / 0 / 17467 | 0 |
| medium | `medium-20260922T134723Z-931080` | 975 / 0 / 975 | 0 |

런 경로는 `/home/cubrid/ctp-run-out/workspace/<Run>`이다. TC는 `dpin-tc`의 `cef1327c32d3f081dd8d8633ca56515f24efd4f0`, CTP는 `db90747`, 이미지 digest는 `sha256:79a344fc7664af48cd13b4b01bc54c059dd92ac2be812f2e4d9802234e06fb7e`다. SQL은 7개 shard, medium은 1개 shard이며 기본 CTP 설정을 사용했다.

직전 계측 티켓은 사용자 예외로 전수 CTP를 실행하지 않았다. 전수 비교 기준은 [준비 티켓에서 확정한 develop nightly](https://github.com/CUBRID/cubrid/actions/runs/35619124899)의 SQL 17466/17466·medium 975/975 성공이다. 후보 TC에는 계측 판독 TC 1개가 추가되어 SQL 전체가 17467개다. 허용 답안 변경은 없고 후보 실패도 0개다.

CTP의 유효 두 런에서 새 assert·signal·raw diff도 0개다. 정규화된 OK/NOK 목록과 코어/assert 검수는 `.git_ignored_dir/scratch/312-329/ctp-evidence/` 및 `runtime-summary.txt`에 보존한다.

### 카운터 대조

기존 `dpin324` DB의 물리 복사본을 후보 optdebug로 실행해 81개 변형 × 5회 = 405개 측정 행을 확보했다. 각 `(cell, variant, rep)`의 반환 행 수와 카운터 9종은 [직전 계측 기준선](domain-pin-bench-baseline.md)과 전부 일치했다. 누락·추가 변형 0, 변경 카운터 측정 0, 변경 카운터 값 집합 0이다. 순차 375행과 병렬 30행의 stderr는 모두 비었다. 시간은 동시 작업과 실행 환경의 영향을 받으므로 이번 동작 불변 게이트의 판정에 사용하지 않는다.

| 카운터 | 후보/기준선 공통 최댓값 |
|---|---:|
| `Num_domain_resolve_fetch` | 13 |
| `Num_domain_coerce_compare` | 9955000 |
| `Num_domain_resolve_list` | 20008 |
| `Num_domain_resolve_agg` | 6 |
| `Num_domain_key_coerce` | 10381 |
| `Num_domain_px_resolve` | 8 |
| `Num_domain_restore_clone` | 27 |
| `Num_domain_gate_convert` | 0 |
| `Num_planned_convert` | 0 |

원본 TSV는 `.git_ignored_dir/scratch/312-329/bench/baseline-db-optdebug.tsv`, 비교 로그는 `logs/baseline-db-counter-compare.log`다. 새로 생성한 별도 DB에서는 인덱스를 사용하는 네 질의의 16개 셀/카운터 조합이 과거 기준선과 달랐으나, 소스·바이너리 변경 없이 기존 물리 DB 복사본에서 모두 일치했다. 따라서 새 DB의 측정은 물리 배치가 다른 비교 자료로 보존하고, 동일 DB 대조를 최종 판정에 사용한다.

벤치의 코어·새 assert는 0이며, 후보 라이브러리 해시는 CTP 설치본과 같다. 전용 DB·broker·master를 종료하고 포트 claim을 해제했다. `logs/final-provenance.log`에 바이너리·DB 파일·정리 결과를 보존한다. DB 복사본은 `baseline-db-copy/`이며, 기존 데이터 볼륨은 수정되지 않았으나 복사된 DB 헤더의 로그 경로 때문에 기존 디렉터리의 `dpin324_lgat`, `dpin324_lgar_t`, `dpin324_lginf`가 갱신되었다. 실행 종료 후 워커가 이 로그 3개를 실행 전 복사본으로 복구했으며, 복구 파일의 해시 일치는 `logs/baseline-source-restore.log`에 기록했다. 실행 중 원본 디렉터리 전체가 불변이었던 것은 아니다. 다음 동일 DB 대조는 복구된 원본 기준에서 시작하고, 복제할 때 데이터 볼륨뿐 아니라 내부 로그 경로도 함께 분리한다. 이번 실행 후 복사 데이터 볼륨과 실행 전 로그를 그대로 조합해 재시작하지 않는다.

최초 SQL 런 `sql-20260922T133016Z-881721`은 공용 `cubrid.conf`의 `[service]` 항목이 CTP DB 설정에 합쳐져 `server=demodb`가 거절되는 초기화 실패였다(실행 0개, 코어 0). 이 런은 회귀 판정에 사용하지 않는다. 재실행은 이전 CTP 검증과 같은 기본 설정을 사용하며, 소스 변경 없이 실행 설정만 바로잡는다.
