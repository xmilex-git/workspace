# develop 성능 재측정 가이드 — CAS-server 통합 PoC

> 출처: 사용자 제공(2026-09-11, workspace 지도 #207의 develop 기준선 티켓에 첨부). 이 문서는 **절차**이며 수치는 담지 않는다. 실측 결과는 티켓 resolution 코멘트와 `cas-merge-poc-develop-baseline-2026-09.md`에 있다.

이 문서는 **기존 CAS 구조의 develop 기준선**을 새 측정 장소에서 수집하고, 메인 이슈와 S22·S25 댓글에 사용할 수치를 만드는 절차다. 이번 문서 작성에서 빌드·DB 실행·성능 측정은 하지 않았다.

## 1. 이번에 가져올 결과

| 구분 | 필수 결과 |
| --- | --- |
| 처리량 | YCSB C 3회, A 3회, 각각 20,000,000 operations의 개별 ops/s·중앙값·MAD |
| 지연시간 | 각 회차 READ p50/p99, A의 UPDATE p50/p99, 단위 µs |
| 유효성 | 성공 연산 수, 실패 수, 실제 runtime, checkpoint 수, SMT·부하 기록 |
| 메모리 | 100·1,000 연결의 S1/S2/S2post/S3/S5에서 전체 프로세스 PSS 및 서버 RSS, 상태별 3개 snapshot |
| 식별 정보 | develop 전체 SHA, 빌드·JDBC·YCSB 식별 정보, OS·CPU·NUMA·SMT·스토리지·설정 전문 |
| 비교 한계 | 같은 장소의 cas-merge/최종 조합이 없으면 develop 단독 기준선으로 보고하고 개선율은 미산출 |

성능만 먼저 측정했다면 메모리를 "미측정"으로 보고한다. 서버 RSS만으로 기존 CAS 구조 전체 메모리 측정을 완료했다고 쓰지 않는다.

## 2. 기존 결과와 비교하는 규칙

기존 PoC 기준은 cas-merge `d533969e4db6ef94d512d91f463790bab559790a`, SMT OFF, C **118,374 ops/s**, A **31,423 ops/s**(각 3회 중앙값)이다. `7117c8a66`의 C **121,228 ops/s**는 이전 cas-merge의 1회 재측정이며 develop 결과가 아니다.

다른 CPU·머신·배치에서 새로 잰 develop 값으로 위 숫자를 나누지 않는다. 새 장소에서 통합 효과를 산출하려면 develop과 비교할 cas-merge 또는 최종 조합을 **같은 머신, 동일 하네스·JDBC·데이터·설정·SMT 상태**로 다시 측정한다. SMT OFF만 같아도 머신이 다르면 직접 비교할 수 없다.

- 기존 시점 develop을 복원하는 측정과 측정일의 최신 develop 측정을 구분한다. 기존 기록의 `5862371ba`를 현재 develop SHA로 사용하지 않는다.
- 통합 브랜치가 포함한 develop과 최신 develop이 다르면 공통 기반 SHA와 추가 develop 변경을 기록한다. 그 차이가 있는 비율은 "해당 두 빌드 간 비교"이며 순수 통합 효과로 단정하지 않는다.
- 과거 조건 재현과 새 장소의 공정 A/B를 섞지 않는다. JDBC·golden DB·warmup 조건을 바꾸면 새 캠페인 식별자를 붙인다.
- 처리량 약 2배는 기존 제품화 검토 목표다. 이번 기준선 수집의 합격선이 아니며 메모리 절감률 목표를 새로 만들지 않는다.

근거: [기준선 원기록](https://github.com/xmilex-git/workspace/issues/244#issuecomment-5616399609), [SMT 재측정](https://github.com/xmilex-git/workspace/issues/244#issuecomment-5616488196), [SMT OFF 규약](https://github.com/xmilex-git/workspace/issues/244#issuecomment-5616517065).

## 3. 환경과 빌드 고정

측정은 Linux의 전용 설치·DB 사본에서 수행한다. 아래 경로는 **측정 장소에서 실제 경로로 바꿀 입력값**이다. 결과·임시 산출물은 디스크 경로를 사용하며 /tmp와 TMPDIR은 사용하지 않는다.

```bash
export TOOLING=/absolute/path/to/workspace
export ENGINE=/absolute/path/to/develop-checkout
export CUBRID=/absolute/path/to/develop-install
export YCSB_ROOT=/absolute/path/to/cubrid-perftools-internal/ycsb/ycsb
export GUIDE_DIR=/absolute/path/to/cas-server-poc
export RUNROOT="$TOOLING/.git_ignored_dir/scratch/develop-remeasure-YYYYMMDD"
export CUBRID_DATABASES="$RUNROOT/db-registry"
export PATH="$CUBRID/bin:$PATH"
export LD_LIBRARY_PATH="$CUBRID/lib"
mkdir -p "$RUNROOT" "$CUBRID_DATABASES"
```

- source는 upstream develop의 **전체 SHA**에 고정한다. 측정 중 pull/merge를 하지 않는다. dirty diff와 submodule SHA를 보존한다.
- 새 작업 트리에서 release preset의 **RelWithDebInfo** 빌드를 사용한다. Debug·sanitizer·비용 귀속 probe를 정식 처리량과 섞지 않는다.
- 양쪽 빌드의 compiler, C/C++ flags, allocator, LTO 여부, CMakeCache를 기록한다. 두 빌드에서 동일한 도구체인을 사용한다.
- 기존 PoC JDBC는 **cubrid-jdbc-11.4.0.0076.jar**였다. 가능하면 같은 파일을 양쪽에 사용하고 SHA256을 기록한다. 새 develop과 호환되지 않으면 호환 드라이버를 양쪽에서 사용하여 새 비교쌍을 만든다.
- perftools 소스에서 현재 확인한 SHA는 `99e07035fb63fb21d53a41dd30b184edca5d3c83`이다. 이것을 과거 기준선의 확정 하네스 SHA로 간주하지 않는다. 가져간 하네스의 실제 SHA·diff·jar hash를 결과에 남긴다.
- YCSB의 JDBC statement cache는 기본 활성 상태를 사용한다. cache 비활성 패치나 prepare-churn 레그를 C/A 기준선에 섞지 않는다.
- 도구 리포를 사용할 경우 해당 호스트의 cubrid-build 절차로 새 작업 트리를 빌드하고 독립 설치 위치를 확인한다. 빌드 후 아래 측정 전용 설정을 다시 적용한다.

```bash
git -C "$ENGINE" rev-parse HEAD > "$RUNROOT/engine-sha.txt"
git -C "$ENGINE" status --short > "$RUNROOT/engine-status.txt"
git -C "$ENGINE" diff > "$RUNROOT/engine.diff"
git -C "$ENGINE" submodule status > "$RUNROOT/submodules.txt"
"$CUBRID/bin/cubrid_rel" > "$RUNROOT/cubrid-rel.txt"
sha256sum "$CUBRID/bin/cub_server" "$CUBRID"/lib/libcubrid.so.* \
  "$CUBRID/jdbc/cubrid_jdbc.jar" > "$RUNROOT/install-sha256.txt"
git -C "$YCSB_ROOT" rev-parse HEAD > "$RUNROOT/ycsb-sha.txt"
git -C "$YCSB_ROOT" diff > "$RUNROOT/ycsb.diff"
java -version 2> "$RUNROOT/java-version.txt"
uname -a > "$RUNROOT/uname.txt"
cat /etc/os-release > "$RUNROOT/os-release.txt"
lscpu > "$RUNROOT/lscpu.txt"
lscpu -e > "$RUNROOT/cpu-topology.txt"
cat /proc/meminfo > "$RUNROOT/meminfo.txt"
lsblk -o NAME,TYPE,SIZE,ROTA,MOUNTPOINT > "$RUNROOT/storage.txt"
findmnt -T "$RUNROOT" > "$RUNROOT/filesystem.txt"
```

추가로 CPU governor·주파수/turbo 정책, NUMA 정책, THP, swap, 컨테이너 이미지/CPU quota/cpuset/memory limit, 가상화 여부, JVM 옵션, 프로세스 affinity, DB·로그 디스크 위치를 기록한다. 값을 새로 튜닝하기보다 두 빌드에 동일하게 고정하고 원본 값을 남긴다.

### SMT와 유휴 조건

**SMT OFF에서만 측정한다.** 원래 호스트는 SMT control=off, active=0, nproc=32, online=0-31이었다. 다른 머신은 코어 수를 32로 위장하지 말고 실제 물리 코어 수와 CPU 제한을 기록한다. 그 머신의 고정 토폴로지를 캠페인 기준으로 사용한다. SMT ON이거나 상태를 확인할 수 없으면 유효한 SMT OFF 결과로 보고하지 않는다.

```bash
cat /sys/devices/system/cpu/smt/control
cat /sys/devices/system/cpu/smt/active
cat /sys/devices/system/cpu/online
nproc
cat /proc/loadavg
```

DB 시작 전 loadavg1 < 4, 동시 benchmark·CTP·HA·빌드 부하 없음이 기존 유휴 조건이다. 5분 간격, 최대 60분 대기 후에도 충족하지 못하면 해당 시간대 측정을 미룬다. 사용 중인 타인의 프로세스를 종료하지 않는다. 시작 후 benchmark 자신의 부하로 loadavg가 높아지는 것은 무효 사유가 아니다. 전·중·후 부하, CPU steal, swap-in/out 및 다른 작업 개입을 함께 기록한다.

기존 배치는 JDBC 부하 발생기와 DB가 같은 머신에서 localhost로 접속하는 형태다. 새 측정도 동일하게 하거나, 별도 부하 발생기를 쓴다면 양 빌드에 같은 네트워크 배치를 적용하고 RTT·NIC·클라이언트 CPU를 기록한다.

## 4. DB와 브로커 설정 전문

### cubrid.conf — C/A 및 100 연결 메모리

```ini
[service]
service=server,broker,manager
server=ycsb

[common]
data_buffer_size=4G
log_buffer_size=2G
vacuum_worker_count=50
max_clients=200
data_buffer_neighbor_flush_pages=0
cubrid_port_id=1523
checkpoint_every_size=256G
checkpoint_interval=120min
```

4G/2G는 기존 buffer 조건이다. checkpoint 설정은 측정 구간의 checkpoint 영향을 배제하기 위한 조건이며, 정상 운영의 지속 부하 결과를 대신하지 않는다. **실제 레그의 checkpoint 0회를 확인**해야 한다. 로그 볼륨과 디스크 여유를 시작 전에 확인한다.

### cubrid_broker.conf — develop 전통 CAS

```ini
[broker]
MASTER_SHM_ID=30001
ADMIN_LOG_FILE=log/broker/cubrid_broker.log

[%query_editor]
SERVICE=OFF
SSL=OFF
BROKER_PORT=30000
MIN_NUM_APPL_SERVER=5
MAX_NUM_APPL_SERVER=40
APPL_SERVER_SHM_ID=30000
LOG_DIR=log/broker/sql_log
ERROR_LOG_DIR=log/broker/error_log
SQL_LOG=OFF
TIME_TO_KILL=120
SESSION_TIMEOUT=300
KEEP_CONNECTION=AUTO
CCI_DEFAULT_AUTOCOMMIT=ON

[%BROKER1]
SERVICE=ON
SSL=OFF
APPL_SERVER=CAS
BROKER_PORT=33000
MIN_NUM_APPL_SERVER=120
MAX_NUM_APPL_SERVER=120
APPL_SERVER_SHM_ID=33000
LOG_DIR=log/broker/sql_log
ERROR_LOG_DIR=log/broker/error_log
SQL_LOG=OFF
TIME_TO_KILL=120
SESSION_TIMEOUT=300
KEEP_CONNECTION=AUTO
CCI_DEFAULT_AUTOCOMMIT=ON
```

**develop에는 DIRECT_HANDOFF=ON을 넣지 않는다.** 이는 cas-merge에서 서버로 연결을 전달하는 설정이다. 비교용 통합 빌드의 BROKER1에만 DIRECT_HANDOFF=ON을 적용한다. develop에서는 실제 CAS 프로세스가 생성되고 JDBC → broker/CAS → server 경로인지 확인한다. 알 수 없는 설정이 무시되었다는 사실만으로 경로 검증을 대신하지 않는다.

1,000 연결 메모리 레그에서는 **max_clients=1100, MIN_NUM_APPL_SERVER=1100, MAX_NUM_APPL_SERVER=1100**으로 모두 바꾼다. 기존 실제 conf는 MIN도 1100이었다. 나머지는 유지한다. 이 설정의 S1에는 미리 생성한 CAS 비용이 이미 포함되므로 S1과 전체 절대량도 반드시 보고한다.

설정은 대상 DB·브로커를 중지한 상태에서 적용하고 재시작한다. 1,000 연결 측정 후 C/A를 실행할 때는 반드시 100 연결용 설정으로 되돌린다. 이 가이드는 런타임 SET SYSTEM PARAMETERS 변경을 사용하지 않는다. 불가피한 포트/SHM ID 변경은 양쪽에 일관되게 적용하고 기록한다.

명시하지 않은 기본값도 버전 사이에 달라질 수 있다. checkpoint·flush/내구성·isolation·plan cache·worker pool·vacuum 관련 유효값과 환경 변수를 저장한다. worker 수나 캐시를 한쪽만 조절하지 않는다. 설정 파일 전문과 SHA256을 각 레그에 보존한다.

## 5. 데이터 준비

기존 데이터는 golden `ycsb_g`의 **10,000,000행**이다. 측정은 golden을 직접 쓰지 않고, **매 레그마다 중지 상태에서 새 사본**을 만든다. A 실행으로 바뀐 DB를 다음 회차에 재사용하지 않는다.

기존 golden을 옮길 수 있으면 생성 버전, 볼륨·로그 페이지 크기, locale/collation, 테이블/인덱스, 통계와 파일 목록·hash를 함께 가져온다. 원래 자료만으로 page size와 통계 생성 절차의 실제값은 확정하지 못했으므로 임의로 과거 값이라 기입하지 않는다.

golden을 가져올 수 없다면 새 장소에서 한 번 적재하고 통계를 갱신한 뒤 중지하여 새 golden을 만든다. 두 빌드는 동일한 논리 데이터와 통계를 사용한다. DB 물리 포맷이 서로 호환되지 않으면 각 버전에서 같은 데이터로 생성하고 그 차이를 기록한다.

스키마:

```sql
CREATE TABLE usertable (
  YCSB_KEY VARCHAR(255) PRIMARY KEY,
  FIELD1 VARCHAR(100), FIELD2 VARCHAR(100),
  FIELD3 VARCHAR(100), FIELD4 VARCHAR(100),
  FIELD5 VARCHAR(100), FIELD6 VARCHAR(100),
  FIELD7 VARCHAR(100), FIELD8 VARCHAR(100),
  FIELD9 VARCHAR(100), FIELD10 VARCHAR(100)
);
```

적재는 아래에서 준비하는 동일 YCSB JDBC binding의 -load로 수행한다. 생성기·키 분포·field 길이는 바꾸지 않는다. 적재 후 다음을 실행하고 결과를 저장한다.

```sql
UPDATE STATISTICS ON usertable;
SELECT COUNT(*) FROM usertable;
SELECT COUNT(*) FROM usertable
 WHERE YCSB_KEY = 'user6284781860667377211';
```

행 수는 10,000,000, 두 번째 COUNT는 메모리 보유 도구에서 쓰는 키이므로 1이어야 한다. 다른 golden에 그 키가 없다면 **실제로 존재하는 한 키**로 ConnHold.java의 TEST_KEY를 변경하고 diff를 보존하여 양 빌드에 동일하게 사용한다. 없는 키를 읽거나 UPDATE 0행인 메모리 레그는 사용하지 않는다.

등록된 golden을 복제하는 예시(대상 ycsb가 없는 새 전용 등록 디렉터리와 경로에서 실행):

```bash
mkdir -p "$RUNROOT/leg-db/lob"
cubrid copydb -F "$RUNROOT/leg-db" -L "$RUNROOT/leg-db" \
  -B "$RUNROOT/leg-db/lob" ycsb_g ycsb
```

다음 레그에서는 본 캠페인의 ycsb만 중지·제거하고 복제한다. 공용 databases.txt나 기존 운영 DB를 이 예시의 대상으로 사용하지 않는다. copydb 성공, 등록된 실제 경로, 사용 바이너리를 확인한다.

## 6. YCSB 하네스와 실행

확인한 하네스는 com.yahoo.ycsb 계열이다. 다른 site.ycsb 버전으로 바꾸면 동일 baseline을 재현한 것으로 쓰지 않는다. 기본 workload는 C=READ 100%, A=READ 50%/UPDATE 50%, zipfian, readallfields=true다. **A는 기본 writeallfields=false, 즉 UPDATE당 한 필드**이다. 뒤의 메모리 보유 도구는 10필드를 UPDATE하므로 서로 다른 실험이다.

다음 내용을 $RUNROOT/cubrid.properties로 저장한다. 포트·접속 정보는 실제 배치와 일치시킨다.

```properties
jdbc.driver=cubrid.jdbc.driver
db.driver=cubrid.jdbc.driver.CUBRIDDriver
db.user=dba
db.passwd=
db.url=jdbc:cubrid:localhost:33000:ycsb:dba::
```

인증이 필요한 환경은 계정 설정을 반영하되 이슈에 암호를 올리지 않는다. 전용 시험 DB 외에 빈 암호를 적용하지 않는다.

### 사전 빌드와 classpath

원래 run.sh는 cwd의 lib 검사 때문에 매 실행 Maven 빌드를 반복하며 Java 실패를 후속 echo/tee로 가릴 수 있다. 아래는 같은 JDBC binding을 **사전 빌드 후 직접 호출**하여 실제 Java 종료 코드를 보존하는 예시다. benchmark 전에 완료한다.

```bash
cd "$YCSB_ROOT"
mvn -pl com.yahoo.ycsb:jdbc-binding -am clean package -DskipTests \
  dependency:build-classpath -DincludeScope=compile -Dmdep.outputFilterFile=true
mkdir -p lib
cp core/target/*.jar jdbc/target/*.jar jdbc/target/dependency/*.jar lib/
export YCSB_CP="$CUBRID/jdbc/cubrid_jdbc.jar:$YCSB_ROOT/lib/*"
sha256sum lib/*.jar > "$RUNROOT/ycsb-jars-sha256.txt"
```

예전 버전의 jar가 lib에 섞이지 않은 새 하네스 사본에서 준비한다. statement cache 비활성 패치가 적용되지 않았는지 확인한다. JDBC auto-commit 기본값은 true다.

새 golden 적재가 필요할 때만, 생성한 빈 usertable에 실행한다:

```bash
java -cp "$YCSB_CP" com.yahoo.ycsb.Client \
  -db com.yahoo.ycsb.db.JdbcDBClient \
  -P "$YCSB_ROOT/workloads/workloada" -P "$RUNROOT/cubrid.properties" \
  -threads 10 -p recordcount=10000000 \
  -p fieldcount=10 -p fieldlength=100 -p fieldlengthdistribution=constant \
  -load > "$RUNROOT/load.log" 2>&1
```

### 각 레그 절차

1. 이전 측정 DB·브로커 중지 → 유휴/SMT 확인 → 새 DB 사본 생성.
2. 100 연결용 conf 적용, hash 및 유효 설정 저장.
3. 서버·브로커 시작, 기존 절차와 같이 시작 후 3초 대기. 별도 SQL/JVM warmup을 넣지 않는다.
4. C 또는 A 20M 연산 실행. 실행 중 설정 변경·profiling을 하지 않는다.
5. Java 종료 코드·성공/실패 연산·histogram·서버/브로커 로그·checkpoint 및 호스트 상태 수집.
6. 대상 DB·브로커 중지. 다음 레그는 1부터 반복.

이 조건은 **별도 warmup 없는 전체 실행 구간 처리량**이다. copydb 후 OS page cache를 비우지 않는다. cold-cache/steady-state 전용 수치가 필요하면 별도 캠페인으로 양쪽의 warmup/cache 조건을 새로 맞춘다.

서버 제어는 도구 리포의 래퍼를 사용한다. 환경의 ENGINE은 명시적으로 정한 대상 checkout이며 CUBRID는 그 설치본이어야 한다.

```bash
export CUBRID_SERVER_CTL_LOGDIR="$RUNROOT/server-control"
bash "$TOOLING/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh" start ycsb
# 레그가 종료된 다음
bash "$TOOLING/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh" stop ycsb
```

브로커는 해당 시험 설치의 제어 절차로 시작·중지한다. 파이프로 출력을 캡처하는 자동화에서는 daemon의 출력 상속을 차단하는 래퍼를 사용한다. CTP는 이 측정에 필요하지 않다.

C1 예시. C2·C3은 LEG만 바꾸고 **DB 재복제부터** 반복한다. A는 WL=workloada, LEG=a1/a2/a3으로 바꾼다.

```bash
WL=workloadc
LEG=c1
OUT="$RUNROOT/develop/$LEG"
mkdir -p "$OUT"
cp "$CUBRID/conf/cubrid.conf" "$OUT/"
cp "$CUBRID/conf/cubrid_broker.conf" "$OUT/"
cat /proc/loadavg > "$OUT/loadavg-before.txt"
cat /sys/devices/system/cpu/smt/control > "$OUT/smt-before.txt"
set +e
java -cp "$YCSB_CP" com.yahoo.ycsb.Client \
  -db com.yahoo.ycsb.db.JdbcDBClient \
  -P "$YCSB_ROOT/workloads/$WL" -P "$RUNROOT/cubrid.properties" \
  -threads 100 -p recordcount=10000000 -p operationcount=20000000 \
  -p maxexecutiontime=1800 \
  -p fieldcount=10 -p fieldlength=100 -p fieldlengthdistribution=constant \
  -p requestdistribution=zipfian -p readallfields=true -p writeallfields=false \
  -p hdrhistogram.fileoutput=true -p hdrhistogram.output.path="$OUT/" \
  -s -t > "$OUT/run.log" 2>&1
YCSB_RC=$?
printf '%s\n' "$YCSB_RC" > "$OUT/java-exit-code.txt"
cat /proc/loadavg > "$OUT/loadavg-after.txt"
cat /sys/devices/system/cpu/smt/control > "$OUT/smt-after.txt"
```

maxexecutiontime=1800은 안전 상한이다. 느린 머신이 20M을 끝내지 못하면 **20M 완료 결과로 쓰지 않는다**. 상한을 늘릴 경우 새 조건으로 기록하고 비교 대상에도 동일하게 적용한다. target ops/s 제한은 사용하지 않는다.

### 유효한 레그의 조건

- Java exit=0, READ+UPDATE 총 연산=20,000,000, 실패/미발견/timeout=0, histogram 누락 없음.
- C는 READ만, A는 READ/UPDATE 실제 count와 비율을 함께 기록한다. A가 정확히 50:50 개수일 필요는 없다.
- 측정 시간창의 서버 이벤트 로그에 실제 checkpoint 시작이 0회. 로그 회전·기존 파일의 앞부분을 포함하여 단순 grep하지 말고 시작·종료 시각/offset으로 구간을 제한한다.
- crash/reconnect/비정상 종료가 없고 예상한 실행 경로·설정·SMT가 유지된다.
- OOM·swap 폭증·다른 부하 개입은 원자료에 남기고 무효 사유를 명시한다.
- 빠른 run만 선택하지 않는다. 무효 레그도 삭제하지 말고 이유와 대체 회차를 기록한다.

A/B 비교를 같은 장소에서 추가할 경우 워크로드별로 develop→candidate, candidate→develop, develop→candidate 순서처럼 실행 순서를 교차하고 매번 사본을 복원한다. 각 빌드에 유효한 C 3개, A 3개를 확보한다.

## 7. 메모리 측정 — 서버 RSS와 전체 PSS를 함께

develop은 여러 CAS 프로세스에 메모리를 나누어 보유한다. **서버만 재면 통합 버전에 불리한 비교**가 된다.

- 포함: 대상 cub_server, 해당 브로커 master/worker, 모든 대상 cub_cas와 시험 구성에서 기동한 보조 프로세스.
- 공유 master 등 공용 프로세스는 전용 환경에서 고정 포함하거나 별도 행으로 표시하여 양쪽 범위를 맞춘다.
- 제외/별도: Java 부하 발생기. 클라이언트와 DB 전체 머신 메모리를 섞지 않는다.
- PID별 /proc/PID/smaps_rollup의 Rss·Pss·Private_Clean·Private_Dirty·Swap과 cmdline/exe를 저장한다.
- 전체량은 **각 snapshot에서 대상 PID들의 PSS를 합산**한다. RSS 합은 공유 페이지를 중복 계상하므로 참고값으로만 표시한다.
- 단계별 3회 snapshot은 **10초 간격**이다. 3회 snapshot은 독립된 성능 반복 3회를 의미하지 않는다.

### 상태와 순서

| 상태 | 조건 |
| --- | --- |
| S1 | 새 사본·설정으로 서버/브로커 시작 후 10초, 사용자 연결 0 |
| S2 | N개 idle JDBC 연결이 모두 READY, 5초 후 측정 |
| S2post | idle 연결 전부 종료, 10초 후 측정 |
| S3 | 새 N개 연결마다 READ 1회·UPDATE 1회 prepare+execute, 문장/연결 유지, READY 5초 후 측정 |
| S5 | S3 연결 전부 종료, 10초 후 측정 |

S2와 S3는 같은 연결을 승격하는 방식이 아니라 **idle 연결을 닫고 prepared 연결을 새로 여는 기존 도구의 순서**다. 이 순서가 만든 allocator 잔류를 숨기지 않도록 S2post도 저장한다.

N=100, N=1000 각각 새 DB 사본에서 실행한다. 1000 레그의 CAS 수와 max_clients를 4절대로 변경하고 파일 descriptor·메모리 한도가 충분한지 확인한다. 일부 연결만 열린 결과를 N=1000으로 나누지 않는다.

함께 제공한 measurement-assets/ConnHold.java는 기존 보유 도구의 원본이다. READ는 전체 행, UPDATE는 FIELD1…FIELD10을 모두 'x'로 바꾼다. 문장 두 개와 연결을 유지하며 자동 commit을 사용한다. 기존 도구는 row count 검사를 강제하지 않으므로 5절의 키 확인이 필수다. 소스 변경 시 diff를 결과에 포함한다.

```bash
mkdir -p "$RUNROOT/classes"
javac -cp "$CUBRID/jdbc/cubrid_jdbc.jar" \
  -d "$RUNROOT/classes" "$GUIDE_DIR/measurement-assets/ConnHold.java"
```

별도 터미널에서 N=100 idle 예시를 실행한다. trigger 파일은 **아직 존재하지 않는 고유 경로**여야 한다.

```bash
java -cp "$CUBRID/jdbc/cubrid_jdbc.jar:$RUNROOT/classes" ConnHold \
  'jdbc:cubrid:localhost:33000:ycsb:dba::' dba '' 100 idle \
  "$RUNROOT/release-idle-100"
```

READY 확인 후 S2 snapshot을 3개 수집하고 다른 터미널에서 `touch "$RUNROOT/release-idle-100"`로 연결을 닫는다. DONE·정상 종료와 실제 연결 해제를 확인한 뒤 S2post를 수집한다. 그 다음 idle을 prepared로, trigger를 release-prepared-100으로 바꿔 S3→S5를 진행한다. 1000은 연결 수·trigger·설정을 모두 바꾼다.

snapshot은 관리자 권한 대신 해당 프로세스의 읽기 권한을 가진 계정에서 수집한다. 단계마다 PID 집합을 다시 확인하여 새 CAS를 빠뜨리지 않는다. 예를 들어 본 캠페인 PID 목록을 $RUNROOT/pids.txt에 한 줄씩 적고:

```bash
SNAP="$RUNROOT/memory-100/S2-1"
mkdir -p "$SNAP"
while read -r pid; do
  cat "/proc/$pid/smaps_rollup" > "$SNAP/$pid.smaps_rollup"
  tr '\0' ' ' < "/proc/$pid/cmdline" > "$SNAP/$pid.cmdline"
  readlink "/proc/$pid/exe" > "$SNAP/$pid.exe"
done < "$RUNROOT/pids.txt"
```

읽기에 실패하거나 PID가 교체된 snapshot은 완전한 총량으로 계산하지 않는다. 원본 /proc의 kB 표기는 1024-byte 단위로 취급하여 결과 표에는 KiB 또는 MiB를 명시한다.

계산식(PSS 전체와 서버 RSS 각각에 적용):

- stage 값 = 각 시점 전체 합을 먼저 계산한 다음 3개 snapshot의 중앙값.
- idle 증가/연결 = (S2−S1)/N.
- prepared 증가/연결 = (S3−S1)/N.
- 준비 단계 대비 증가 = S3−S2. 서로 다른 연결 단계와 이전 잔류가 섞이므로 prepared statement 한 개 크기로 해석하지 않는다.
- 종료 후 잔류 = S5−S1.
- 전체 절감률 = 100×(develop 전체 PSS−candidate 전체 PSS)/develop 전체 PSS. 동일 N·단계·프로세스 포함 범위의 비교에만 사용한다.

기존 서버 RSS 참고값은 100/1000 연결의 idle 421/401 kB, prepared 897/829 kB, 잔류 약 59/502 MB다. **이 값은 develop 전체 메모리도, 절감 성과도 아니다.** 종료 후 잔류량만으로 객체 leak을 단정하지 않는다.

## 8. 집계와 결과 보존

YCSB 0.4.0 기본 summary에는 p50이 없으므로 함께 제공한 HdrP50.java로 레그의 HDR 파일을 읽는다. avg를 p50으로 대신 쓰지 않는다.

```bash
javac -cp "$YCSB_ROOT/lib/*" -d "$RUNROOT/classes" \
  "$GUIDE_DIR/measurement-assets/HdrP50.java"
java -cp "$YCSB_ROOT/lib/*:$RUNROOT/classes" HdrP50 \
  "$RUNROOT/develop/c1/READ.hdr"
# A 레그는 READ.hdr와 UPDATE.hdr 모두 처리한다.
```

각 레그의 전체 histogram에서 p50/p99를 계산하고 READ/UPDATE operation count와 대조한다. 과거 결과는 p50을 HDR, p99를 YCSB summary에서 추출한 방식이므로 원본 summary p99도 함께 남긴다. 새 비교쌍의 주 지표는 같은 추출 방식을 양쪽에 적용한다. 3회 percentile의 중앙값은 "회차별 p99의 중앙값"이며 전체 60M histogram의 p99와 다르다.

- 처리량 중앙값 = median(x1,x2,x3).
- raw MAD = median(|xi−median|).
- 개선율(%) = 100×(candidate median/develop median−1), 배수 = candidate median/develop median.
- latency 변화율(%) = 100×(candidate p99/develop p99−1); 양수는 악화.
- 기존 후보 선별의 MAD clamp(max(raw MAD, median의 1%))와 p99 +10% hold는 참고 규약이다. 이번 develop 기준선에 임의의 합격선을 만들지 않는다.
- 이슈에는 개별 3개 값도 공개한다. 분산이 크면 시간대/IO/부하를 설명하고 느린 한 회차를 근거 없이 삭제하지 않는다.

perf/c2c·prepare-churn은 기준선 수집의 필수가 아니다. 필요하면 별도 새 사본·별도 레그로 수행하고 정식 C/A 수치에 포함하지 않는다.

### 가져올 디렉터리

```text
develop-remeasure-YYYYMMDD/
  engine-sha.txt, engine.diff, cubrid-rel.txt, install-sha256.txt
  ycsb-sha.txt, ycsb.diff, ycsb-jars-sha256.txt, java-version.txt
  OS/CPU/SMT/NUMA/스토리지/cgroup 및 유효 설정 기록
  golden/ 생성·적재·통계·페이지 크기·행 수·파일 manifest
  develop/c1,c2,c3,a1,a2,a3/
    run.log, *.hdr, java-exit-code.txt, cubrid*.conf
    서버·브로커 로그, checkpoint 구간 판정, CPU·SMT·부하 기록
  memory-100/, memory-1000/
    S1/S2/S2post/S3/S5 각 3 snapshot, PID 명세, 보유 도구 출력
  summary.tsv
  jira-result-comment.txt
```

## 9. 이슈 댓글에 붙일 결과 템플릿

아래 블록은 JIRA wiki markup이다. 미측정 셀은 "미측정", 비교 불가 셀은 "비교 불가(사유)"로 채운다. 숫자를 확보하지 않은 채 목표나 과거 값으로 채우지 않는다.

```text
*develop 재측정 조건*

* 측정 일시/호스트:
* develop 전체 SHA / cubrid_rel / 빌드 옵션:
* 비교 대상 SHA(없으면 develop 단독):
* JDBC 버전·SHA256 / YCSB SHA·변경:
* CPU/물리 코어/SMT/NUMA/cpuset:
* RAM/DB·로그 디스크/OS/JDK:
* 부하 발생기 배치:
* 데이터: 10,000,000행, golden 식별자/페이지 크기/locale/통계:
* 설정: 첨부 또는 아래 전문. develop 전통 CAS, DIRECT_HANDOFF 미설정.
* 워크로드: threads=100, zipfian, C READ 100%, A READ/UPDATE 50/50, 20M ops, statement cache 사용, autocommit=true, 별도 warmup 없음.
* 유효성: 오류/미발견/timeout 0, 각 레그 20M 완료, checkpoint 0, SMT OFF.
* 조건 변경 및 비교 제한:

*처리량과 지연시간*

||대상||WL||개별 ops/s 3회||중앙값||raw MAD||READ p50/p99 (µs)||UPDATE p50/p99 (µs)||
|develop|C|미측정|미측정|미측정|미측정|N/A|
|develop|A|미측정|미측정|미측정|미측정|미측정|

지연시간은 회차별 percentile의 중앙값이다. 회차별 원자료와 percentile 추출 방식은 아래에 기록한다.
비교 대상이 같은 조건에서 없으면 개선율: 미산출.

*전체 메모리와 연결별 증가*

||대상/N||측정 범위||S1||S2||S2post||S3||S5||idle/conn||prepared/conn||종료 잔류||
|develop/100|전체 PSS, KiB|미측정|미측정|미측정|미측정|미측정|미측정|미측정|미측정|
|develop/1000|전체 PSS, KiB|미측정|미측정|미측정|미측정|미측정|미측정|미측정|미측정|

서버 RSS는 별도 행으로 기록한다. 1000 연결 설정은 MIN/MAX CAS=1100이므로 S1에 미리 기동한 CAS 비용이 포함된다.
프로세스 포함 범위/클라이언트 제외 여부:
유효·무효 레그와 재측정 사유:
원자료 위치·파일 hash:
판단: develop 기준선 확보 범위, 직접 비교 가능 여부, 남은 측정.
```

메인 댓글에는 C/A 요약과 비교 한계, S22에는 위 조건·개별값·메모리 표, S25에는 동일 장소의 최종 조합이 확보된 뒤 비교와 판단을 넣는다. 상세 근거는 이슈 댓글에 작성하며 design.md/test.md로 분리하지 않는다.
