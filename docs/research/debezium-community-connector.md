# Debezium 커뮤니티 커넥터 표준 조사

- 티켓: [xmilex-git/workspace#51](https://github.com/xmilex-git/workspace/issues/51) (지도 #48)
- 조사일: 2026-08-17
- 조사 기준: **1차 출처만** — debezium.io 공식 사이트 소스(`debezium/debezium.github.io`), 실제 GitHub 저장소의 `pom.xml` / CI workflow / README, `debezium/dbz` 이슈 트래커
- 소비처: #56 (standalone `debezium-connector-cubrid` 저장소 부트스트랩), #57 (JNA vs pure-Java port 결정)

조사 시점의 upstream 개발 버전은 **3.7.0-SNAPSHOT**, 최신 stable 시리즈는 **3.6**이다.
(출처: [`playbook.yml`](https://github.com/debezium/debezium.github.io/blob/develop/playbook.yml) — `page-version-current: '3.6'`, `page-version-devel: '3.7'`)

---

## 0. 요약 (TL;DR)

| 항목 | 커뮤니티 커넥터의 사실상 표준 |
|---|---|
| 코드 위치 | **debezium GitHub org 안의 standalone 저장소** (vendor org 아님) |
| 빌드 | 단일 Maven 모듈, `io.debezium:debezium-parent`를 **parent POM으로 상속** |
| core 버전 | 커넥터 버전 == core 버전 (**lock-step**), `version.debezium = ${project.version}` |
| 브랜치 | `main` + 마이너별 릴리스 브랜치(`3.5`, `3.6`…) + `candidate-<version>` |
| 배포 | Maven Central `io.debezium:debezium-connector-<db>` (jar + `-plugin.tar.gz`/`.zip`) + `quay.io/debezium/connect` 이미지에 번들 |
| 문서 | **core 저장소** `documentation/modules/ROOT/pages/connectors/<db>.adoc` + `nav.adoc` |
| 등재 절차 | `debezium/dbz` 이슈 개설 → 메인테이너(jpechane)가 debezium org에 빈 저장소 생성 → 코드 기여 → 문서 PR → `(Incubating)`으로 등재 |
| 네이티브 라이브러리 | debezium org 전체에 JNA/JNI 사용 **0건**. 네이티브 의존은 "선택적 adapter + 사용자 직접 설치" 또는 "외부 프로세스와 네트워크 통신"으로 우회 |

---

## 1. 저장소 구조와 빌드 시스템

### 1.1 커뮤니티 커넥터는 전부 debezium org의 독립 저장소다

debezium org의 공개 저장소를 열거하면 커넥터 저장소는 다음과 같다
(출처: `gh api orgs/debezium/repos`, 2026-08-17 조회):

`debezium-connector-vitess`, `-db2`, `-cassandra`, `-spanner`, `-informix`, `-ibmi`,
`-cockroachdb`, `-ingres`, `-yashandb`, `-milvus`, `-sqlite`, `-neo4j`, `-tidb`
(전부 `archived: false`, Apache-2.0). `debezium-connector-jdbc`만 `archived: true`이며
설명이 "This repository has been moved to the main debezium/debezium repository."로,
**JDBC sink는 core 저장소 안으로 흡수**되었다
(출처: <https://github.com/debezium/debezium-connector-jdbc>, core 저장소 루트에 `debezium-connector-jdbc` 모듈 존재).

즉 **vendor org에 남아 있는 공식 커뮤니티 커넥터는 없다.** Informix(IBM), Spanner(Google), YashanDB(중국 벤더), Ingres(Actian 계열) 모두 debezium org 아래에 있다.
IBM i 커넥터도 원래 외부(jhc-systems)에서 시작했지만 debezium org로 이관되었다
(README가 여전히 `https://github.com/jhc-systems/debezium-ibmi-exitpgm`을 참조:
<https://github.com/debezium/debezium-connector-ibmi/blob/main/README.md>).

### 1.2 저장소 루트 파일 구성이 사실상 고정되어 있다

vitess / informix / db2 / ibmi / yashandb의 루트를 비교하면 공통 골격이 동일하다
(출처: `gh api repos/debezium/debezium-connector-<x>/contents`):

```
.github/workflows/   .mvn/   mvnw   mvnw.cmd   pom.xml   src/
LICENSE(.txt)        README.md      dco.txt    .gitignore
```

- **Maven Wrapper(`mvnw`, `.mvn/`)를 저장소에 커밋**한다. yashandb 저장소의 초기 커밋 로그에도
  `[ci] Add Maven wrapper`(Jiri Pechanec, 2026-05-22)가 있다
  (출처: `gh api repos/debezium/debezium-connector-yashandb/commits`).
- **`dco.txt`** (Developer Certificate of Origin 전문)를 반드시 둔다. yashandb에는 Chris Cranford가
  `Add dco.txt`(2026-05-26)를 별도 커밋으로 추가했다.
- 소스 레이아웃은 표준 Maven(`src/main/java`, `src/test/java`)이며, 통합 테스트용 Docker 자산은
  `src/test/docker/...` 아래에 둔다(Informix 예:
  <https://github.com/debezium/debezium-connector-informix/blob/main/README.md> — `src/test/docker/informix-cdc-docker`).

### 1.3 parent POM 상속이 핵심 규약이다

다섯 저장소의 `pom.xml` 최상단이 모두 동일한 형태다
(출처: 각 저장소 `main` 브랜치 `pom.xml`):

```xml
<parent>
    <groupId>io.debezium</groupId>
    <artifactId>debezium-parent</artifactId>
    <version>3.7.0-SNAPSHOT</version>
</parent>
<artifactId>debezium-connector-vitess</artifactId>
<version>3.7.0-SNAPSHOT</version>
```

- `relativePath`를 지정하지 않으므로 **로컬 `~/.m2`에 설치된 core 아티팩트를 찾는다.**
  그래서 모든 README가 "먼저 `debezium/debezium`을 `mvn clean install`로 로컬 빌드하라"고 요구한다
  (출처: <https://github.com/debezium/debezium-connector-informix/blob/main/README.md>
  "Building this connector first requires the main debezium code repository to be built locally using `mvn clean install`").
- SNAPSHOT을 로컬 빌드 없이 받으려면 `central-snapshots` 저장소를 `<repositories>`에 선언한다
  — 다섯 커넥터 POM 모두 동일한 블록을 갖는다.
- **패키징은 단일 `jar` 모듈**이 기본. 예외는 ibmi로, `packaging=pom` 애그리게이터 아래
  `debezium-connector-ibmi` / `journal-parsing` / `jt400-override-ccsid` 세 모듈을 둔다
  (artifactId도 `debezium-connector-reactor-ibmi`).

### 1.4 core 의존은 `debezium-core`가 아니라 `debezium-connector-common`이다

vitess POM의 compile scope 의존은 다음과 같다
(출처: <https://github.com/debezium/debezium-connector-vitess/blob/main/pom.xml>):

- `io.debezium:debezium-connector-common`
- `io.debezium:debezium-config`
- `io.debezium:debezium-util`
- `io.debezium:debezium-connect-plugins`
- `org.apache.kafka:connect-api` (provided)
- 빌드 지원용: `debezium-ide-configs`, `debezium-checkstyle`, `debezium-assembly-descriptors`, `debezium-revapi`
- 테스트: `debezium-embedded` (+ `-tests` classifier), `junit-jupiter`, `assertj-core`, `awaitility`

이는 메인테이너의 명시적 안내와 일치한다 —
> "it's generally good practice for your connector codebase to use the common connector framework, which was previously in `debezium-core` and now lives in `debezium-connector-common`. ... It's not an explicit hard requirement, as we have some like Spanner and Cassandra that are designed differently"
> — Chris Cranford(@Naros), [debezium/dbz#1850 comment, 2026-04-23](https://github.com/debezium/dbz/issues/1850)

### 1.5 Java / Kafka 버전

core의 build parent(`io.debezium:debezium-build-parent`, 부모는 `org.jboss:jboss-parent`)가 정한다
(출처: <https://github.com/debezium/debezium/blob/main/pom.xml>):

```xml
<debezium.java.source>21</debezium.java.source>
<debezium.java.connector.target>17</debezium.java.connector.target>
<maven.compiler.release>${debezium.java.connector.target}</maven.compiler.release>
<jdk.min.version>${debezium.java.source}</jdk.min.version>
<version.kafka>4.3.0</version.kafka>
```

→ **빌드에는 JDK 21 이상이 필요하지만, 커넥터 바이트코드 타깃은 Java 17**이다.
`CONTRIBUTING.md`가 "JDK 21 or later"를 요구하는 것과, Naros가 "connectors target Java 17"이라 답한 것이 이렇게 양립한다
(출처: <https://github.com/debezium/debezium/blob/main/CONTRIBUTING.md> line 22; dbz#1850 코멘트).

### 1.6 parent POM이 강제하는 품질 게이트

`debezium-parent`가 다음 플러그인을 자동 적용한다
(출처: <https://github.com/debezium/debezium/blob/main/debezium-parent/pom.xml>):

- `formatter-maven-plugin` + Eclipse 포매터(`/eclipse/debezium-formatter.xml`) — 기본 goal은 `format`(자동 수정), CI에서는 `-Dformat.formatter.goal=validate`
- `impsort-maven-plugin` — import 정렬, CI에서는 `-Dformat.imports.goal=check`
- checkstyle (`debezium-checkstyle` 아티팩트)
- `revapi-maven-plugin` — API 호환성 검사 (parent에서는 `revapi.skip=true`가 기본)
- 빠른 빌드용 `-Dquick` 프로파일 (테스트·checkstyle·포매터·revapi 전부 skip). 모든 커넥터 README에 동일 문구로 안내됨.

---

## 2. debezium-core 버전 추적 및 호환성 정책

### 2.1 lock-step 버저닝 — 커넥터 버전 = core 버전

각 커넥터 POM의 첫 property가 예외 없이 다음과 같다
(출처: vitess/informix/spanner/db2/ibmi `pom.xml`):

```xml
<properties>
    <!-- Debezium parent -->
    <version.debezium>${project.version}</version.debezium>
```

즉 **core 버전을 별도로 pin하지 않는다.** 커넥터 자신의 버전이 곧 의존하는 core 버전이다.
따라서 "core 3.6.1을 쓰는 커넥터 2.0.0" 같은 조합은 구조적으로 존재할 수 없다.

태그 목록이 이를 뒷받침한다 — vitess/informix/spanner/db2 **네 저장소의 태그가 완전히 동일**하다
(출처: `gh api repos/debezium/debezium-connector-<x>/tags`):

```
v3.7.0.Alpha2  v3.7.0.Alpha1  v3.6.1.Final  v3.6.0.Final  v3.6.0.CR1
v3.6.0.Beta2   v3.6.0.Beta1   v3.6.0.Alpha2 v3.6.0.Alpha1 v3.5.2.Final ...
```

### 2.2 브랜치 전략

- `main` = 다음 마이너의 개발 브랜치 (현재 3.7.0-SNAPSHOT)
- 마이너 릴리스마다 **`1.4` … `3.5`, `3.6`** 형태의 유지보수 브랜치를 판다
  (vitess에는 `1.4`부터 `3.6`까지 전부 존재)
- 릴리스 시 **`candidate-<version>`** 브랜치가 생긴다
  (`candidate-3.6.1.Final`, `candidate-3.5.0.CR1` 등). 이는 Jenkins 릴리스 파이프라인이 만드는 것으로,
  `CANDIDATE_BRANCH = "candidate-$RELEASE_VERSION"`
  (출처: <https://github.com/debezium/debezium/blob/main/jenkins-jobs/pipelines/release/release-pipeline.groovy>)

### 2.3 CI가 core와의 동기화를 강제한다

커넥터 저장소의 `.github/workflows/`는 이름까지 표준화되어 있다
(vitess/informix/db2/ibmi/yashandb 공통):

| 파일 | 역할 |
|---|---|
| `maven.yml` | push 시. **core를 같은 ref로 checkout해서 먼저 빌드**한 뒤 커넥터 빌드 |
| `cross-maven.yml` | PR 시. 동명의 PR 브랜치가 `debezium/debezium`에 있으면 그 브랜치의 core로, 없으면 base 브랜치 core로 빌드 |
| `sanity-check.yml` | 커밋 메시지 prefix 검사 (`debezium/dbz#\d+` \| `DBZ-\d+` \| `[release]` \| `[ci]` \| `[docs]` …) |
| `commit-signoff-check.yml` / `contributor-check.yml` / `octocat-commit(s)-check.yml` | DCO 서명·기여자 확인 |

`maven.yml` 핵심 (출처: <https://github.com/debezium/debezium-connector-vitess/blob/main/.github/workflows/maven.yml>):

```yaml
- uses: actions/checkout@v7
  with: { repository: debezium/debezium, ref: ${{ github.ref }}, path: core }
- run: ./vitess/mvnw clean install -f core/pom.xml -pl debezium-bom,debezium-embedded,debezium-storage,debezium-connect-plugins -am -DskipTests -DskipITs ...
- run: ./vitess/mvnw clean install -f vitess/pom.xml -Passembly ...
```

`cross-maven.yml`은 여기에 더해 `debezium/dbz/.github/actions/check-dco@main` 공용 액션으로 DCO를 검사하고,
core 빌드 모듈에 `debezium-connector-common`, `debezium-config`, `debezium-util`을 추가한다.
브랜치 트리거는 `main, 1.*, 2.*, 3.*, 4.*`로 고정되어 있다.

> **#56 시사점**: `debezium-connector-cubrid`는 core를 Maven 의존으로만 잡는 게 아니라,
> **CI에서 core를 같은 브랜치로 소스 빌드**하는 구조를 그대로 복사해야 upstream 편입이 쉽다.
> 현재 fork(`xmilex-git/debezium` 브랜치 `cubrid-connector`)처럼 core 트리 안에 모듈로 두는 방식은
> upstream 관례와 반대다 — 커뮤니티 커넥터는 **반드시 분리 저장소**다(§5).

---

## 3. 릴리스와 배포

### 3.1 중앙 Jenkins 파이프라인이 core와 커넥터를 한 번에 릴리스한다

`release-pipeline.groovy`는 `DEBEZIUM_ADDITIONAL_REPOSITORIES` 파라미터를
`id#giturl#branch`(또는 `id#giturl#subdir#branch`) 형식으로 받아, 추가 저장소들을 같은 릴리스 실행에서
태깅·배포한다 (출처:
<https://github.com/debezium/debezium/blob/main/jenkins-jobs/pipelines/release/release-pipeline.groovy>):

```groovy
CANDIDATE_BRANCH = "candidate-$RELEASE_VERSION"
ADDITIONAL_REPOSITORIES = [:]
DEBEZIUM_ADDITIONAL_REPOSITORIES.split().each { item -> ... }
```

같은 파일의 `CONNECTORS_PER_VERSION` 맵은 시리즈별 릴리스 대상 커넥터 목록을 갖고 있고,
커뮤니티 커넥터가 편입된 시점이 그대로 드러난다:
`1.4`에 vitess, `2.1`에 spanner, `2.5`에 informix, `2.6`에 ibmi, `3.3`에 cockroachdb.
즉 **새 커뮤니티 커넥터는 이 맵에 등록되는 순간부터 core 릴리스 트레인에 올라탄다.**

릴리스 절차 전반은 <https://github.com/debezium/debezium/blob/main/RELEASING.md> 참조
(Jira 버전 정리 → CHANGELOG/website 릴리스 노트 → `antora.yml`/`series.yml` 갱신 → Jenkins job).

### 3.2 Maven Central이 1차 배포 채널

`io.debezium` groupId 아래 각 커넥터가 그대로 published 된다. 실제 파일 목록
(출처: <https://repo1.maven.org/maven2/io/debezium/debezium-connector-informix/3.6.0.Final/>):

```
debezium-connector-informix-3.6.0.Final.jar            (+ .asc)
debezium-connector-informix-3.6.0.Final.pom            (+ .asc)
debezium-connector-informix-3.6.0.Final-plugin.tar.gz  (+ .asc)   <- Kafka Connect 플러그인 아카이브
debezium-connector-informix-3.6.0.Final-plugin.zip     (+ .asc)
debezium-connector-informix-3.6.0.Final-sources.jar    / -javadoc.jar
debezium-connector-informix-3.6.0.Final-tests.jar      / -test-sources.jar / -test-javadoc.jar
```

- `-plugin.tar.gz` / `-plugin.zip`은 `-Passembly` 프로파일 + `debezium-assembly-descriptors`가 만든다.
  (spanner는 `assembly.descriptor = connector-distribution-with-jsr310`을 별도 지정)
- 모든 아티팩트에 GPG 서명(`.asc`)이 붙는다.
- 업로드는 `org.sonatype.central:central-publishing-maven-plugin` 사용
  (출처: <https://github.com/debezium/debezium/blob/main/pom.xml>).
- 아직 정식 릴리스가 없는 신규 커넥터도 Maven Central에 경로가 잡혀 있다
  (yashandb / ingres / cockroachdb / tidb 전부 `repo1.maven.org/maven2/io/debezium/debezium-connector-*/` HTTP 200).

### 3.3 컨테이너 이미지에 번들된다

`quay.io/debezium/connect` 이미지가 커뮤니티 커넥터를 **`debezium-additional` 채널로 내려받아 포함**한다
(출처: <https://github.com/debezium/container-images/blob/main/connect/3.6/Dockerfile>):

```dockerfile
ENV DEBEZIUM_VERSION="3.6.1.Final" ... DB2_MD5=... SPANNER_MD5=... VITESS_MD5=... INFORMIX_MD5=... IBMI_MD5=... COCKROACHDB_MD5=...
RUN ... \
    docker-maven-download debezium-additional db2 db2 "$DEBEZIUM_VERSION" "$DB2_MD5" && \
    docker-maven-download debezium-additional vitess vitess "$DEBEZIUM_VERSION" "$VITESS_MD5" && \
    docker-maven-download debezium-additional informix informix "$DEBEZIUM_VERSION" "$INFORMIX_MD5" && \
    docker-maven-download debezium-additional cockroachdb cockroachdb "$DEBEZIUM_VERSION" "$COCKROACHDB_MD5"
```

core 커넥터(mysql/postgres/…)는 `docker-maven-download debezium <name>`,
커뮤니티 커넥터는 `docker-maven-download debezium-additional <name> <name>`으로 **호출 형태만 다르고 동일 이미지에 들어간다.**
릴리스 파이프라인이 MD5까지 갱신한다.

### 3.4 웹사이트 다운로드 페이지 등재

`debezium.github.io`의 `_data/connectors.yml`에 `{id, title, artifact}`를 추가하면
릴리스 페이지의 다운로드 목록에 나온다. 2026-08 기준 목록에는 cockroachdb / yashandb / ingres / tidb까지 이미 등재되어 있다
(출처: <https://github.com/debezium/debezium.github.io/blob/develop/_data/connectors.yml>).

### 3.5 Confluent Hub는 표준 채널이 아니다

조사한 다섯 저장소 중 Confluent Hub 패키징 플러그인(`io.confluent:kafka-connect-maven-plugin`)을 선언한 것은
**spanner 하나뿐이며, 그것도 `<pluginManagement>`에만 있고 실행에 바인딩되어 있지 않다**
(출처: <https://github.com/debezium/debezium-connector-spanner/blob/main/pom.xml>).
`_data/connectors.yml`, container image, RELEASING.md 어디에도 Confluent Hub 발행 단계가 없다.
→ **1차 채널은 Maven Central 플러그인 아카이브 + quay.io 컨테이너 이미지**로 보는 것이 맞다.

---

## 4. 문서와 테스트 관례

### 4.1 사용자 문서는 커넥터 저장소가 아니라 core 저장소에 둔다

메인테이너 안내가 명시적이다:
> "all documentation is maintained in the main `debezium/debezium` repository under the `documentation` directory. You can find a `connectors` subdirectory containing an asciidoc for each connector. Ideally, you'd submit a `yashan.adoc` file that follows a similar pattern to what you see for other relational connectors and **update the `nav.adoc`** with a reference to your new connector documentation file."
> — @Naros, [debezium/dbz#1850](https://github.com/debezium/dbz/issues/1850)

실제 파일 목록 (출처: `debezium/debezium` `documentation/modules/ROOT/pages/connectors/`):
`cassandra.adoc cockroachdb.adoc db2.adoc index.adoc index-sink.adoc informix.adoc ingres.adoc jdbc.adoc mariadb.adoc mongodb.adoc mongodb-sink.adoc mysql.adoc oracle.adoc postgresql.adoc spanner.adoc sqlserver.adoc vitess.adoc yashandb.adoc`

문서는 Antora로 빌드되며, `playbook.yml`이 core 저장소의 `1.9, 2.7, 3.0…3.7, main` 브랜치를 소스로 잡는다
(출처: <https://github.com/debezium/debezium.github.io/blob/develop/playbook.yml>).
따라서 **문서는 core의 릴리스 브랜치를 따라 버전별로 자동 배포**된다.

커넥터 저장소의 `README.md`는 사용자 매뉴얼이 아니라 **빌드/테스트 개발자 가이드** 역할이다
(배지, 라이선스, "먼저 core를 빌드하라", `mvn docker:start/stop`, `-Dit.test=...`, `-Dquick`).

### 4.2 "Incubating" 라벨

`connectors/index.adoc`이 커뮤니티 커넥터를 명시적으로 구분한다
(출처: <https://github.com/debezium/debezium/blob/main/documentation/modules/ROOT/pages/connectors/index.adoc>):

```asciidoc
* xref:connectors/vitess.adoc[Vitess] (Incubating)
* xref:connectors/spanner.adoc[Spanner] (Incubating)
* xref:connectors/informix.adoc[Informix] (Incubating)
* xref:connectors/cockroachdb.adoc[CockroachDB] (Incubating)
* xref:connectors/yashandb.adoc[YashanDB] (Incubating)
* xref:connectors/ingres.adoc[Ingres] (Incubating)

[NOTE]
====
An incubating connector is one that has been released for preview purposes and is subject to changes that may not always be backward compatible.
====
```

Db2와 Cassandra는 커뮤니티 출신이지만 `(Incubating)` 표기가 빠져 있다 — **졸업 경로가 존재**함을 뜻한다.
Informix는 저장소 설명에서도 "incubating"이 빠졌고 README가 "it should be stable enough for production usage"라고 쓰지만
docs의 index에는 아직 Incubating으로 남아 있다 — 표기 갱신이 즉각적이지는 않다.

### 4.3 테스트 규약

Informix README가 가장 명시적이다
(출처: <https://github.com/debezium/debezium-connector-informix/blob/main/README.md>):

- **unit test = `*Test.java` / `Test*.java`** — 외부 서비스 불필요, 동일 JVM, 빠르고 독립적
- **integration test = `*IT.java` / `IT*.java`** — Maven이 `docker-maven-plugin`으로 DB 컨테이너를 자동 기동/정지, failsafe로 실행
- DB 컨테이너 파라미터는 POM property로 노출 (`informix.image`, `informix.db.name`, `db2.port`, `vitess.vtgate.grpc.port` …)
  → `-Ddatabase.hostname=... -Ddatabase.port=...` 시스템 프로퍼티로 IDE 디버깅 가능
- `mvn docker:start` / `mvn docker:stop` / `mvn integration-test`(컨테이너 유지) 워크플로가 표준
- `-Passembly` 프로파일은 릴리스·CI용이며, **DB 설정 조합마다 통합 테스트 전체를 반복 실행**한다
- 개별 테스트는 `-Dit.test=ConnectionIT` 또는 와일드카드 `-Dit.test=Connect*IT`

spanner만 예외적으로 JaCoCo 커버리지 게이트를 둔다(`jacoco.min.coverage`, `-P test-coverage`)
(출처: <https://github.com/debezium/debezium-connector-spanner/blob/main/pom.xml>, README).

### 4.4 기여 규약 (커넥터 저장소에도 그대로 적용)

출처: <https://github.com/debezium/debezium/blob/main/CONTRIBUTING.md>

- **DCO 필수** — 모든 커밋에 `git commit -s`. 누락 시 CI 실패. (`dco.txt` + `commit-signoff-check.yml`)
- **커밋 메시지 = `debezium/dbz#1234 <요약>`으로 시작**. 구 형식 `DBZ-1234`도 허용.
  `[release]`, `[jenkins-jobs]`, `[maven-release-plugin]`, `[ci]`는 CI 예약 prefix (수동 사용 금지).
- 토픽 브랜치 이름도 `dbz#1234` 권장.
- 포매팅은 자동화 — 빌드를 로컬에서 돌리면 자동 수정됨. CI는 `-Dformat.formatter.goal=validate -Dformat.imports.goal=check`.
- 요청 범위 밖 리팩터링/포매팅 변경 금지, upstream `main`에 rebase 후 PR.
- **PR 머지 요건: committer/steering committee의 positive vote 2개.**
  단, `[ci]`/`[docs]` 접두 또는 소규모·저위험 변경은 무투표 머지 가능
  (출처: <https://github.com/debezium/debezium.github.io/blob/develop/community/governance.asciidoc>).

### 4.5 AI 사용 정책 — CUBRID 팀이 반드시 확인해야 할 항목

출처: <https://github.com/debezium/debezium/blob/main/AI_USAGE_POLICY.md>

> "This project does not accept fully AI-generated pull requests. AI tools may be used **assistively only**."
> "Maintainers may close PRs that appear to be fully or largely AI-generated."

금지 항목에 다음이 명시되어 있다:
- 전체 PR/대형 코드 블록 작성, 구현 결정 위임, 이해하지 못한 코드 제출
- 코드 변경 제출 자동화
- **"Apply commit sign-offs to Git commits"** — AI가 DCO 서명을 대신 붙이는 것 자체가 금지

요구 항목: PR 설명에 사용한 AI 도구를 **공개(disclose)** 할 것, 모든 라인을 설명할 수 있을 것.
core 저장소 루트에 `AGENTS.md`도 있다.

> **#56 시사점**: 현재 CUBRID 커넥터 작업이 에이전트 주도로 진행되고 있다면,
> upstream 기여 단계에서는 **인간 리뷰·재작성·disclosure**를 거쳐야 한다.
> 사실상 YashanDB 사례처럼 "AI로 커밋 메시지까지 정리된 대량 커밋"을 그대로 밀어넣는 방식은 정책상 리스크가 있다.

---

## 5. 커뮤니티 커넥터로 등재되는 절차

### 5.1 실제 사례 재구성 — YashanDB (가장 최근·CUBRID와 가장 유사)

전 과정이 [debezium/dbz#1850 "Add support for a connector: YashanDB"](https://github.com/debezium/dbz/issues/1850)에 공개되어 있다.
YashanDB는 중국 상용 RDBMS이고, Oracle XStream에 해당하는 자체 CDC 인터페이스(YStream, Java 클라이언트 API)를 갖고 있다는 점에서 CUBRID와 상황이 유사하다.

타임라인:

| 날짜 | 사건 | 주체 |
|---|---|---|
| 2026-04-23 | `dbz` 이슈 개설: 사용 사례 + 구현 아이디어(JDBC 스냅샷 + YStream 증분) 기술. 라벨 `type/enhancement`, `component/yashandb` | 벤더(@OctoberWithYou) |
| 2026-04-23 | 메인테이너가 **"자체 org에 둘 것인가, debezium org로 옮길 것인가"**를 먼저 질문 | @jpechane |
| 2026-04-23 | 벤더가 **무상 기증(donate) 및 debezium org 이관** 의사 표명 | 벤더 |
| 2026-04-23 | 규약 안내: standalone repo 사용, `debezium-connector-common` 사용 권장, Java 17 타깃, parent POM 상속 시 checkstyle 자동 적용, 문서는 core 저장소 `documentation/`에 `.adoc` + `nav.adoc` 갱신. 참고 사례로 informix / vitess 제시 | @Naros |
| 2026-04-23 | `debezium/debezium-connector-yashandb` 저장소 생성 (`Initial commit`) | @jpechane |
| 2026-05-22 | `[ci] Initial CI setup`, `[ci] Add Maven wrapper` | @jpechane |
| 2026-05-11~12 | 벤더가 실제 코드 푸시. 모든 커밋이 `debezium/dbz#1850 …` prefix. 중국어 주석 영어 번역, ANTLR 생성물 git 제외, JDK 11→21 상향, DCO/contributor workflow 추가, Apache-2.0 LICENSE 추가, assembly 프로파일 추가, README 작성 | 벤더(Tlinian) |
| 2026-05-26 | `Add dco.txt` | @Naros |
| ~2026-08 | `nav.adoc` / `connectors/index.adoc` / `_data/connectors.yml`에 **YashanDB (Incubating)** 등재 | — |

Ingres도 동일 패턴이다 (출처: `gh api repos/debezium/debezium-connector-ingres/commits`):
2025-12-15 jpechane의 `Initial commit` → `dbz#1462 Add basic readme` → `Add .gitignore` → `Add basic PR checks`,
2026-01-14 기여자(Brian Hughes)의 `dbz#1462 Add initial Ingres code`, 이후 jpechane이 `Clean pom.xml` / `Remove unused Dockerfiles` 정리.

### 5.2 정리된 체크리스트

1. **`debezium/dbz`에 enhancement 이슈를 연다.** (Jira DBZ는 이관됨 — 현 트래커는
   <https://github.com/debezium/dbz/issues>. core POM의 `<issueManagement>`도 이 URL을 가리킨다.)
   내용: DB 소개, CDC 인터페이스 설명, 스냅샷/증분 전략, 유지보수 인력 약속.
2. **거버넌스 질문에 답한다** — vendor org 유지 vs debezium org 기증.
   **공식 커뮤니티 커넥터로 등재되려면 debezium org 기증이 사실상 전제**다(현존 커넥터 100%가 그렇다).
3. 메인테이너가 debezium org에 빈 저장소를 만들고 CI 골격(`Initial CI setup`, Maven wrapper, `dco.txt`, PR check workflows)을 넣어준다.
4. 기여자가 코드를 PR로 올린다 — parent POM 상속, `debezium-connector-common` 기반, Java 17 타깃,
   커밋마다 `-s` 서명 + `debezium/dbz#N` prefix.
5. **core 저장소에 문서 PR** — `documentation/modules/ROOT/pages/connectors/<db>.adoc` + `nav.adoc` + `connectors/index.adoc`에 `(Incubating)` 추가.
6. `debezium.github.io`의 `_data/connectors.yml`, `container-images/connect/<ver>/Dockerfile`,
   `release-pipeline.groovy`의 `CONNECTORS_PER_VERSION`에 등록되면 릴리스 트레인·이미지 번들에 포함된다.

### 5.3 거버넌스 배경

- Debezium은 **Commonhaus Foundation** 산하이며 Code of Conduct와 Trademark Policy를 따른다.
- 역할은 Contributor / Committer / Steering Committee 3단계.
  committer 목록은 <https://github.com/debezium/governance/blob/main/committers.yml>.
- 중대한 설계 변경은 <https://github.com/debezium/debezium-design-documents>에 proposal PR을 올려
  lazy consensus 투표(binding +1 3개, -1 0개, 최소 3일)를 거친다.
  (출처: <https://github.com/debezium/debezium.github.io/blob/develop/community/governance.asciidoc>)
- 개발 채널은 Zulip `#dev` (<https://debezium.zulipchat.com/#narrow/stream/302533-dev>).

---

## 6. 네이티브 라이브러리 정책 (#57: JNA vs pure-Java port)

### 6.1 debezium org 전체에 JNA/JNI 사용 사례가 없다

GitHub code search (2026-08-17):

| 쿼리 | 결과 |
|---|---|
| `org:debezium jna in:file filename:pom.xml` | **0** |
| `org:debezium net.java.dev.jna` | **0** |
| `org:debezium "com.sun.jna"` | **0** |
| `org:debezium System.loadLibrary` | **0** |

→ **어떤 Debezium 커넥터도 JNA/JNI로 네이티브 라이브러리를 직접 바인딩하지 않는다.**
이것이 이 조사에서 #57에 가장 직접적인 신호다.

### 6.2 네이티브가 불가피한 경우 upstream이 택한 두 가지 우회

Oracle 커넥터가 유일하게 네이티브가 얽힌 사례이며, 두 방식 모두 **JNI 바인딩을 피한다**
(출처: <https://github.com/debezium/debezium/blob/main/documentation/modules/ROOT/pages/connectors/oracle.adoc>):

**(a) 선택적 adapter + 사용자가 직접 네이티브 설치**

XStream adapter는 Oracle Instant Client의 OCI 네이티브 라이브러리를 필요로 한다.
Debezium은 이를 **배포물에 포함하지 않고**, 사용자가 직접 설치하도록 문서화한다:

> "Licensing requirements prohibit {prodname} from including these files in the Oracle connector archive. However, the required files are available for free download as part of the Oracle Instant Client."
> — `oracle.adoc`, "Obtaining the Oracle JDBC driver and XStream API files"

절차: Instant Client 다운로드 → `ojdbc11.jar`, `xstreams.jar`를 `kafka/libs`에 복사 →
`LD_LIBRARY_PATH=/path/to/instant_client/` 환경변수 설정.

그리고 **기본값은 네이티브가 필요 없는 순수 JDBC 경로(LogMiner)** 이다.
`database.connection.adapter` 프로퍼티로 `logminer`(기본) / `logminer_unbuffered` / `xstream` / `olr`를 고른다.
네이티브 경로는 기능 제약도 감수한다 (`ROWID` 미지원, `JSON` 컬럼 캡처 불가 등).

**(b) 네이티브 프로세스를 별도로 띄우고 네트워크로 통신**

OpenLogReplicator(`olr`) adapter는 C++ 애플리케이션이지만 링크하지 않고 **네트워크 엔드포인트로 붙는다**:

> "{prodname} Oracle connector is a consumer of OpenLogReplicator by **connecting to the network endpoint** provided by OpenLogReplicator and ingesting the transactions as they're batched."
> — `oracle.adoc`, "How OpenLogReplicator works"

이 adapter 역시 incubating으로 표시되고, 사용자가 직접 "download and compile OpenLogReplicator"해야 한다.

### 6.3 #57에 대한 함의

1. **pure-Java(JDBC) 경로를 기본 어댑터로 두는 것이 upstream 관례에 부합한다.**
   Oracle(LogMiner), YashanDB(스냅샷은 JDBC), Informix, Db2 모두 기본 경로는 JDBC/순수 Java다.
2. **JNA를 쓰더라도 "필수"가 아니라 "선택적 adapter"여야 한다.**
   `connection.adapter` 스타일 설정으로 분기하고, 네이티브 라이브러리는 플러그인 아카이브에 **포함하지 않고**
   사용자가 설치하도록 문서화하는 것이 Oracle XStream이 남긴 패턴이다.
3. **네이티브 라이브러리를 플러그인 아카이브에 번들하는 선례가 없다.**
   `quay.io/debezium/connect` 이미지는 `-plugin.tar.gz`를 풀어 넣을 뿐이므로,
   JNA 경로가 기본이면 컨테이너 번들이 불가능해지고 §3.3의 배포 경로에서 이탈한다.
4. 다만 upstream이 JNA를 **명시적으로 금지한 문서는 발견하지 못했다.**
   "0건 사용 + Oracle이 두 번이나 JNI를 피해 우회했다"는 정황 증거이며, 명문 규정은 아니다.
   확정이 필요하면 Zulip `#dev` 또는 `dbz` 이슈에서 직접 질의하는 것이 정확하다.

---

## 7. `debezium-connector-cubrid` 부트스트랩 체크리스트 (#56 직결)

§1~§5에서 도출한, 그대로 복사해야 할 항목:

- [ ] 저장소 루트: `pom.xml`, `README.md`, `LICENSE.txt`(Apache-2.0), `dco.txt`, `.gitignore`, `mvnw`/`mvnw.cmd`/`.mvn/`, `src/`
- [ ] `pom.xml`: parent `io.debezium:debezium-parent:<core버전>`, artifactId `debezium-connector-cubrid`,
      **version은 core와 동일**, `<version.debezium>${project.version}</version.debezium>`,
      `central-snapshots` repository 블록, `<scm>`/`<issueManagement>`(→ `https://github.com/debezium/dbz/issues`)/`<licenses>`
- [ ] 의존: `debezium-connector-common`, `debezium-config`, `debezium-util`, `debezium-connect-plugins`,
      `connect-api`(provided), 테스트에 `debezium-embedded`(+`tests` classifier)
- [ ] 빌드 지원 의존: `debezium-ide-configs`, `debezium-checkstyle`, `debezium-assembly-descriptors`, `debezium-revapi`
- [ ] `-Passembly` 프로파일로 `-plugin.tar.gz` / `-plugin.zip` 생성
- [ ] JDK 21로 빌드, `maven.compiler.release=17`
- [ ] `.github/workflows/`: `maven.yml`, `cross-maven.yml`, `sanity-check.yml`,
      `commit-signoff-check.yml`, `contributor-check.yml`, `octocat-commits-check.yml`
      (vitess/informix 것을 커넥터 이름만 바꿔 복사)
- [ ] 통합 테스트: `*IT.java` + `docker-maven-plugin`으로 CUBRID 컨테이너 자동 기동/정지, POM property로 접속 파라미터 노출
- [ ] 커밋: `git commit -s` + `debezium/dbz#<번호> <요약>` prefix (upstream 기증 전이라면 자체 티켓 번호로 시작하되, 기증 시점에 rebase 필요)
- [ ] 사용자 문서는 **core 저장소** `documentation/modules/ROOT/pages/connectors/cubrid.adoc` + `nav.adoc` + `index.adoc`에 `(Incubating)`으로 PR
- [ ] AI 사용 disclosure 준비 (§4.5)

**주의 — fork 방식과의 충돌**: 현재 작업 브랜치는 `xmilex-git/debezium`의 `cubrid-connector`로,
core 트리 안에 커넥터 모듈을 두는 형태다. upstream은 이 형태를 커뮤니티 커넥터에 쓰지 않는다
(YashanDB 기여자도 "fork the main repository, re-submit ... to the Debezium development branch"라고 제안했다가
Naros가 "we typically create a separate standalone repository"로 정정했다 — dbz#1850).
→ **#56의 standalone 저장소 분리는 선택이 아니라 upstream 편입의 전제 조건**이다.

---

## 8. 미확인/한계

- Confluent Hub 발행 여부는 저장소·문서 상 근거가 없다는 **부재 증거**로만 판단했다. Confluent Hub 카탈로그를 직접 조회하지는 않았다.
- `octocat-commits-check.yml` 등 일부 workflow의 본문은 열어보지 않았다(이름과 역할만 확인).
- JNA 금지의 명문 규정은 존재하지 않는다(§6.3-4).
- Db2/Cassandra가 `(Incubating)`을 언제·어떤 기준으로 졸업했는지 문서화된 절차는 찾지 못했다.
