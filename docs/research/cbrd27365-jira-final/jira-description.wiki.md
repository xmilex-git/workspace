*Description*

임시 리스트 파일(qfile)은 정렬, GROUP BY, DISTINCT, 서브쿼리 결과, 해시 조인 빌드 입력, 분석 함수 파티션, 커서 결과 등 질의 실행 중간 결과를 담는 실행기 내부 파일이다. 현재 튜플 포맷은 값마다 8바이트 헤더(flag 4B + 길이 4B)를 붙이고 모든 값을 8바이트 경계에 정렬한다. INT 하나를 저장하는 데 16바이트, VARCHAR 'abc'(4바이트 표현)에도 16바이트가 든다. 리스트가 임시 볼륨으로 넘어가는 대형 정렬과 집계에서 이 오버헤드가 임시 페이지 수와 정렬 I/O, 행 단위 헤더 해석 비용으로 그대로 나타난다.

튜플 포맷을 PostgreSQL MinimalTuple 과 같은 구조의 단일 포맷으로 교체한다. 튜플 헤더는 길이 4바이트(최상위 비트가 NULL 포함 여부)이고, NULL 이 있는 튜플만 널 비트맵을 가지며, NULL 값은 0바이트다. 고정 길이 값은 자연 정렬(최대 4바이트)로 이어 붙이고, 가변 길이 값은 정렬 없이 1바이트(127바이트 이하) 또는 4바이트 길이 헤더 뒤에 둔다. 리스트 스키마(type_list)가 실행 계획에서 상수이므로 컬럼 위치는 스키마에서 미리 계산해 두고 튜플에는 기록하지 않는다.

같은 행 (id INT = 7, name VARCHAR(20) = 'abc') 을 기존 포맷과 새 포맷으로 저장하면 다음과 같다. 위 줄은 바이트 오프셋이고, 한 칸이 4바이트다(새 포맷의 가변 값 부분만 1바이트/3바이트 칸).

{noformat}
[old format] 40 bytes -- 8B header per value, every value aligned to 8B
 0       4       8       12      16      20      24      28      32      36      40
 +-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
 |tpl len|prev   |flag   |len    |INT    |pad    |flag   |len    |03 abc |pad    |
 |= 40   |len    |BOUND  |= 4    |7      |       |BOUND  |= 4    |       |       |
 +-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
 |< tuple hdr 8B>|<-- id INT: hdr 8B + val 8B -->|<- name VARCHAR: hdr 8B + 8B ->|

[new format] 12 bytes -- 4B header, fixed value naturally aligned, varlen value with 1B length header
 0       4       8 9     12
 +-------+-------+-+-----+
 |len=12 |INT 7  |3|a b c|
 |null=0 |       | |     |
 +-------+-------+-+-----+
 |< hdr >|< id  >|<name >|
{noformat}

id 가 NULL 인 행 (NULL, 'abc') 은 기존 포맷에서 32바이트(UNBOUND 헤더 8B + 길이 0 값)이고, 새 포맷에서는 널 비트맵 1바이트가 헤더 뒤에 붙고 NULL 값은 자리를 차지하지 않는다.

{noformat}
[new format with NULL] 12 bytes -- null bit set in the length word, 1B null bitmap, NULL takes 0 bytes
 0       4 5     8 9     12
 +-------+-+-----+-+-----+
 |len=12 |b|pad  |3|a b c|
 |null=1 |m|     | |     |
 +-------+-+-----+-+-----+
 |< hdr >|bm+pad |<name >|
 bitmap = 0x02 (00000010): bit 0 (id) = 0 -> NULL, bit 1 (name) = 1 -> bound
{noformat}

가변 길이 값이 128바이트 이상이면 길이 헤더가 4바이트(최상위 비트 1)로 바뀌고, 역방향 스캔이 가능한 리스트(최종 결과 리스트, 머지 조인 입력, 분석 함수 파티션)만 헤더에 직전 튜플 길이 4바이트를 더 갖는다.

*Specification Changes*

* SQL 문법, 질의 결과, 설정 파라미터는 바뀌지 않는다. 기존 포맷은 삭제하며 두 포맷을 선택하는 파라미터는 두지 않는다.
* 임시 리스트 파일 크기가 준다. 행당 크기(계산값)와 실측 임시 페이지 수는 다음과 같다. 감소율은 컬럼 수에 비례하고 긴 가변 값에서는 작다(기존 포맷도 문자열/NUMERIC 은 압축 인코딩이라 새 포맷이 없애는 것은 값당 헤더 8B 와 8B 정렬 패딩이다).

||리스트 스키마 (질의) ||행당 크기 기존 → 신규 ||임시 페이지 수 기존 → 신규 ||
|(i INT, b BIGINT) -- 100만 행 ORDER BY b DESC |40B → 16B |정렬 데이터 페이지 19,047 → 14,041 (-26%) |
|(INT, INT) |40B → 12B |- |
|(i INT, b BIGINT, d DATE, k INT) 500만 행 -- ROW_NUMBER() OVER (ORDER BY k, i) 분석 함수 정렬 |56B → 24B |27,193 → 11,656 (-57%) |
|같은 테이블 -- GROUP BY 100만 그룹 (해시 부분 집계 → 정렬) |- |46,721 → 36,895 (-21%) |
|같은 테이블 -- ORDER BY 3키 LIMIT 4000000, 10 |- |17,280 → 9,344 (-46%) |
|(c CHAR(10), v VARCHAR(50), n NUMERIC(15,2), k INT) 200만 행 -- ORDER BY k |80B → 48B |ORDER BY 출력 리스트 4,664 → 3,678 (-21%) |
|TPC-H Q1 집계 행 (SF10) |136B → 60B |- |
|TPC-H SF10 임시 리스트 SCAN fetch 페이지 (SET TRACE) |- |Q10 46,027 → 29,322, Q13 2,218 → 1,100, Q21 13,802 → 7,125, Q08 666 → 241 |

임시 볼륨 사용량과 정렬 I/O 가 같은 비율로 감소한다. 페이지 수는 같은 호스트에서 변경 전(develop 8e355ff59)과 변경 후 release 빌드로 같은 질의를 실행해 SHOW TRACE 또는 정렬 통계로 읽은 값이다.
* 실행 계획 텍스트가 같은 데이터에서 달라질 수 있다. 실행기가 리스트 페이지 수로 내리는 결정(병렬 정렬/해시 조인 워커 수, 해시 조인 in-memory 여부, 해시 조인 빌드 측 선택)이 페이지 수 감소로 바뀌기 때문이다. SET TRACE ON 출력의 "parallel workers" 줄, "BUILD method: hybrid/memory", "hash temp(h)/(m)" 표기가 해당한다. 결과 집합은 동일하다.
* 클라이언트/서버 프로토콜의 리스트 식별자 패킷 길이가 4바이트 늘어난다. CUBRID 는 클라이언트와 서버를 같은 빌드로 함께 올리는 lockstep 업그레이드만 지원하므로 혼합 버전 방어는 두지 않는다. JDBC/CCI 드라이버와 CAS 는 튜플 바이트를 직접 보지 않아 변경이 없다.
* 부수 정정: 준비 문장에서 BIT_AND/BIT_OR/BIT_XOR 집계 누산기 도메인을 BIGINT 로 통일해 결과 타입이 일관된다. 재귀 CTE 의 비재귀부 컬럼이 호스트 변수 NULL 로 시작하는 경우 디버그 빌드에서 발생하던 서버 abort(qfile_unify_types 의 assert) 가 사라진다.

*Implementation*

리스트 스키마 type_list 를 레이아웃 디스크립터로 확장한다. 컬럼별 고정 오프셋/크기/종류(고정, 가변 직접 디코드, 가변 정렬 복사)와 리스트별 헤더 크기, 널 비트맵 크기를 스키마가 확정될 때마다 같은 자리에서 계산해 둔다. 도메인이 실행 중에 늦게 확정되는 컬럼은 첫 bound 값에서 확정하고 레이아웃을 다시 계산한다.

튜플 접근은 신설 공용 파일 src/query/qfile_tuple_layout.h/.c 의 접근자 API 로 모은다. 리더는 튜플 슬롯(튜플 + 디스크립터 + 위치 캐시)으로 컬럼 위치를 상수 오프셋 또는 접두 증분으로 찾고, 라이터는 크기 계산과 채우기 2패스의 튜플 조립기 하나로 수렴한다. 정렬 레코드의 키 본문도 같은 포맷의 미니 튜플로 만들어 비교자가 접근자를 재사용한다. 서버, SA, 클라이언트 커서(cursor.c)가 같은 코드를 쓴다.

영향 범위는 질의 실행기(list_file.c, query_executor.c, query_opfunc.c, query_hash_join.c, 병렬 실행 px_*, 집계/분석 함수, query_evaluator.c, fetch.c), 클라이언트 커서(cursor.c), 리스트 식별자 pack/unpack(object_representation.c) 이며 힙 레코드와 영속 디스크 포맷은 바뀌지 않는다.

*Acceptance Criteria*

* CTP sql 및 medium 회귀 스위트가 통과하고, TPC-H SF10 22종 질의 결과가 변경 전과 동일하다.
* 임시 리스트를 쓰는 정렬/집계 질의에서 임시 페이지 수가 변경 전보다 감소한다(예: (INT, BIGINT) 100만 행 정렬 -26%).
* 같은 호스트에서 변경 전/후 release 빌드로 TPC-H SF10(parallelism 6) 22종을 실행했을 때 행당 처리 비용(프로파일)이 동등하고 wall-clock 회귀가 측정 편차 범위를 넘지 않는다.

*Definition of done*

* Acceptance Criteria를 만족한다.
* QA 테스트를 통과한다.
