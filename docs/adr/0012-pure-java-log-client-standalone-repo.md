# cubrid_log 순수 Java 포팅 + 커넥터 standalone 저장소 전환

CUBRID Debezium 커넥터의 CDC 접근 계층 아키텍처를 확정한다(지도:
xmilex-git/workspace#48, 티켓: #57). ADR 0002는 POC 도달 확실성을 위해 JNA-first를
택하며 순수 Java 포팅을 "기각이 아니라 연기"로 남겼고, 후속 리뷰 §7.6이 그 운영 부담
4종(네이티브 crash=Connect worker 사망, CUBRID 설치본 마운트·`LD_LIBRARY_PATH` 의존,
upstream 제출 난이도, CUBRID 버전↔`.so` ABI 결합)을 제품화 재검토 항목으로 승계했다.

결정: **JNA 격리·완화가 아니라 지금 순수 Java 포팅을 수행한다.** 아울러 upstream
기여를 목표로 하는 조직적 판단에 따라 **개발 거처를 fork 브랜치에서 standalone
저장소로 전환한다(ADR 0006/#56 결정 개정).**

## 배경 — 확인된 사실

- **F1 — upstream에 JNA 선례 0건** (#51 전수 조사): debezium org 전체에서
  JNA/JNI 사용 0건. 네이티브가 필요했던 유일 사례 Oracle도 두 번 다 우회(XStream은
  사용자 직접 설치 선택 어댑터, OpenLogReplicator는 별도 프로세스+네트워크). 순수
  Java wire client가 MySQL(binlog 재구현)·PG(pgjdbc replication stream)의 정석.
- **F2 — 포팅 표면은 이미 좁다**: JNA 계층은 `jna/` 패키지 598줄이며
  `CubridLogClient` facade(connect/findLsa/extract/finalizeClient + 설정 4종) 뒤에
  격리, 바깥 소비자는 Streaming/Snapshot 이벤트 소스 2개 파일뿐. 포팅 원본
  `src/api/cubrid_log.c`는 2,123줄(css 프레이밍 + OR_ 언패킹).
- **F3 — pgjdbc 유추 불성립**: PG replication이 pgjdbc에 사는 이유는 일반 쿼리와
  동일 wire protocol·소켓·인증(walsender 모드)이기 때문. CUBRID는 반대 —
  cubrid-jdbc JCI는 broker(CAS) 프로토콜, `cubrid_log`는 서버 css 포트 직결로
  코드 재사용 0줄. cubrid-jdbc는 `source/target 1.8` 빌드(커넥터는 release 17).
  MySQL도 binlog 클라이언트를 JDBC 드라이버가 아닌 별도 lib로 둔다.
- **F4 — Debezium은 Apache-2.0**: 포크·수정·배포·판매까지 허용, 카피레프트 없음.
  라이선스 리스크는 반대 방향 — `cubrid_log.c` 포팅분을 Apache-2.0로 내는 것은
  저작권자인 CUBRID의 결정 사항(사내 확인 필요, 기술 블로커 아님).
- **F5 — 기증 최종 거처는 어차피 제3의 저장소**: debezium 메인테이너가 org에 빈
  저장소+CI 골격을 만들고 코드 PR을 받는 절차(#51, YashanDB 선례). 어느 거처에서
  개발하든 "이관 1회"는 동일하며, standalone 추출 절차는 #56에서 리허설·검증 완료.
- **F6 — SNAPSHOT parent 마찰 소멸**: `io.debezium:debezium-parent`는
  `3.7.0.Alpha2`까지 Maven Central 공개 — standalone이 core 소스 빌드 없이 순수
  Maven 의존만으로 빌드된다.
- **F7 — upstream 비코드 요건**: standalone 저장소 기증(코어 트리 내 모듈은 관례
  위반 — YashanDB 선례에서 메인테이너가 정정), DCO `-s` 서명, **AI Usage Policy**
  (완전 AI 생성 PR 거부·AI DCO 서명 금지·PR에 AI 도구 disclosure 요구),
  testcontainers 통합 테스트용 공개 CUBRID 이미지, core 저장소 `.adoc` 문서.

## 결정

- **D1 — 지금 순수 Java 포팅 (JNA 격리안 기각).** upstream 기여 목표상 JNA 제거는
  필요조건(F1)이고, ADR 0002가 예정한 "실측 덤프=포팅 픽스처" 조건이 이미 성립.
  worker 프로세스 격리(C shim+IPC)는 포팅 비용의 상당분을 내면서 upstream을 못 여는
  어중간한 지점이라 기각.
- **D2 — facade 계약 동결.** 포팅은 `CubridLogClient` 공개 API를 유지한 채 `jna/`
  패키지 내부 교체로 한정. facade 위의 커넥터 티켓들(#63–#66, #69)은 포팅과 병렬
  진행 가능하고, JNA 구현은 포팅 기간 동안 파리티 오라클 역할.
- **D3 — wire client는 커넥터 내 패키지 (cubrid-jdbc 편입 기각).** F3 근거.
  프로토콜 중립 이름으로 개명(`jna` →예: `log`), 패키지 구조는 MySQL·Vitess 커넥터
  선례를 본뜬다. 기증 시점에 vendor 배포 별도 아티팩트(예: `cubrid-log-client`)로
  추출하는 선택지는 릴리스 엔지니어링 fog에 남긴다 — cubrid-jdbc 편입은 그때도
  아니다.
- **D4 — JNA 경로 완전 삭제.** 파리티 검증 완료 후 fallback adapter 없이 단일
  경로. 보존은 git 히스토리·백업 브랜치로.
- **D5 — 파리티 판정 기준**: ① 기존 단위 테스트 19/19 + E2E s01–s10 diff-check
  0 mismatch + fault test를 Java client로 전부 재통과, ② 실측 wire 덤프 기반 픽스처
  단위 테스트 신설, ③ 이후 프로토콜 변경(#62 버전 협상, #67 relation 사전)의
  클라이언트측은 **Java에만** 구현하되, C `cubrid_log`·`cdclogdump` 하네스는 독립
  교차 검증 오라클로 존치(하네스가 새 아이템을 봐야 하는 변경은 C도 병행).
- **D6 — 개발 거처 standalone 전환 (#56 결정 개정).** 1.0 개발 거처는
  `xmilex-git/debezium-connector-cubrid`(staging을 3.7 기준으로 재구성해 승격, 추후
  CUBRID org 이관·debezium org 기증은 릴리스 엔지니어링). fork
  `xmilex-git/debezium`은 개발 거처에서 해제 — upstream 추적·기증 PR 준비용 참조로
  강등, `cubrid-connector` 브랜치는 백업 보존. 근거: 커뮤니티 커넥터 관례 자체가
  standalone(F5·F7)이고, "타사 제품 포크 안에서 자사 제품을 키우지 않는다"는 조직적
  판단. F4로 법적 강제는 아님을 명기한다.
- **D7 — 버전 추종 = 최신 공개 릴리스 pin.** 지금은 `debezium-parent 3.7.0.Alpha2`,
  이후 릴리스는 버전 bump 커밋으로 추종(Central만으로 재현 가능한 고정 빌드).
  SNAPSHOT lock-step(core 소스 빌드 CI)은 기증 시점에 전환.
- **D8 — upstream 기여의 잔여 요건은 릴리스 엔지니어링으로.** F7 항목(기증 절차,
  라이선스 사내 확인, AI Usage Policy 대응, testcontainers 이미지, `.adoc` 문서)은
  이 ADR의 범위 밖 — 지도 fog에 명기.

## Consequences

- 포팅 완료 시 §7.6 부담 4종이 소멸: Connect worker에 네이티브 crash 경로 없음,
  CUBRID 설치본 마운트·`LD_LIBRARY_PATH` 불요(완전 자립 빌드), `.so` ABI 결합 해소
  (버전 호환은 #62 wire 협상으로 이관), upstream 제출의 기술 블로커 제거.
- 프로토콜 지식이 C 코드 박제에서 벗어나 Java 구현+wire 픽스처로 이중화되고,
  C 하네스가 교차 검증 오라클로 남아 두 구현이 서로를 검증한다.
- e2e 빌드 경로(`htap-poc/e2e/build-connector.sh` 등)는 standalone 산출물로 재배선
  필요. 커넥터 코드 티켓들은 standalone 전환 완료 후 새 거처에서 진행한다.
- 되돌리기: D6은 fork 브랜치가 백업으로 남아 즉시 복귀 가능. D1은 JNA 계층이
  히스토리에 있어 복원 가능하나, 이후 프로토콜 변경이 Java에만 쌓일수록 비용 증가.
