# CAS 통합 부록: 비교 기준·운영 정책·검증·파일 목록

[본문으로 돌아가기](develop-vs-cas-merge-briefing.md) · [코드 해설](develop-vs-cas-merge-code-walkthrough.md)

코드 비교와 기존 측정은 2026-09-05 작성 당시의 기록이다. HA 검증 범위는 2026-09-06 사용자 합의로 갱신했다. 열린 정책을 제품 약속으로 확정하지 않으며, 검증 수치는 커밋별 기존 결과다.

## 1. 코드 비교 기준과 읽는 방법

본문은 공개 PR의 **`31702ac4a31cd2b1237812d5150a8cff9076d209`**를 기준으로 한다. develop 비교점은 **`e374c7a24c46449c3f79e9413a6f4ff3d23b16c2`**다. 2026-09-05 조회 당시 공개 PR head와 대조했다. 이후 브랜치가 움직여도 이 문서의 설명 범위는 이 커밋 쌍이다.

로컬 `cas-merge` 이름은 공개 PR보다 뒤처져 있었다. 요청된 `git diff origin/develop...cas-merge --stat`만 그대로 쓰면 이전 통합본을 설명하게 된다. 부록에는 실제 비교 명령과 전체 변경 파일 목록을 고정한다.

**변경 파일 목록은 편입 코드 전체 목록과 다르다.** CMake가 기존 client 소스를 SERVER_MODE 타깃에 새로 넣으면 그 파일의 diff가 0이어도 서버의 동작 범위가 달라진다. 따라서 빌드 소스 목록과 함수 내부의 조건부 컴파일을 함께 읽어야 한다.

아래 경로와 심볼은 부록의 고정 커밋 코드 링크에서 찾을 수 있다. 부록은 파일 누락 점검용이고, 본문은 변경의 이유와 리뷰 단위를 설명한다.

## 2. 운영 호환: 확정한 원칙과 아직 결정하지 않은 것

다음 표의 '현재 관찰'은 그대로 제품 규격으로 채택했다는 뜻이 아니다. 최종 정책은 [폴드가 바꾼 운영 표면의 호환 정책 결정 — driver_session 표기·broker status·sql_log·thin csql·EXECUTE PRINT·접속 에러코드·SHARD](https://github.com/xmilex-git/workspace/issues/209)에서 정한다. 자료 작성 시 해당 티켓은 열려 있다.

| 표면 | 현재 관찰·구현 방향 | 남은 결정 |
|---|---|---|
| 일반 드라이버 wire | V12 유지, 서버가 CAS 화자 | 다른 드라이버별 회귀 검증 범위 |
| killtran·tranlist·접속 상태 | 프로그램명이 driver_session으로 보임 | 레거시 cub_cas/csql 표기를 보존할지 |
| broker status | CAS 행이 없음 | 세션 행 대체 또는 축소 형식 확정 |
| SQL·slow·DDL 로그 | 서버가 생산, 포맷 보존 방향 | 파일명·경로·per-CAS 기대 TC 정리 |
| broker add/drop/restart·changer | CAS 풀 조작 및 실행 파라미터 변경 거부 | 거부 메시지 또는 cas_* 라우팅 |
| thin csql plan·histogram·메시지 | 무출력·미지원·텍스트 차이 보고 | 복원할 기능과 의도된 비호환 분리 |
| EXECUTE PRINT | client stdout 출력 누락 보고 | 출력 전달 규약 |
| block_ddl/block_nowhere | 미적용 의심 CI 결과 | 제품 수정 범위 |
| 접속 에러 | JDBC/CCI/csql 코드·텍스트 차이 | 레거시 코드 번역 범위 |
| SHARD | 미지원 선언 | 관련 TC 전체 제외 범위 |
| Windows | 별도 CAS/중계 경로 잔류 | Linux 1-hop 성과로 Windows를 대표하지 않음 |
| query replace | 서버에 링크됐지만 초기화되지 않아 inert | 세션 상태·공유 세그먼트·명령/카운터 호환 |
| 원격 thin csql 특권 옵션 | read-only/sysadm/skip-vacuum 로컬 전용 제한 | 전용 타입·메타데이터 확장 여부 |
| cub_manager·CDC 연결 | CI에서 실패·크래시 보고 | 제품 경로 확인과 재현 후 수정 |

query replace는 develop 머지로 새로 들어온 중요한 예다. `query_replace.c`를 서버 타깃에 링크해야 빌드는 되지만 `qr_init`이 실행되지 않아 기능이 활성화되지는 않는다. 활성화하려면 CAS 단일 스레드를 가정한 정적 상태와 `remap_argv`의 세션 분리를 먼저 해결해야 한다. [develop → cas-merge 머지 — 충돌 4파일 해소 + 양 빌드·unit/smoke green + PR 7837 갱신](https://github.com/xmilex-git/workspace/issues/208).

## 3. 검증 결과와 한계

이번 문서 작업에서는 빌드·CTP·벤치마크를 새로 실행하지 않았다. 아래는 이슈의 기존 검증 기록이며 **서로 다른 커밋의 결과를 모은 것**이다.

| 검증 | 대상·기준 | 기록된 결과 | 의미 |
|---|---|---:|---|
| fresh optdebug + release | develop 머지 31702ac4a | 양 빌드 성공 | 최신 비교 커밋 컴파일 검증 |
| server compile unit | 같은 머지 게이트 | 18/18 | 지정 unit 바이너리 결과 |
| in-process smoke | 같은 머지 게이트 | 14/14 | 핵심 경로 회귀 |
| thin/csql/JDBC/gate smoke | 같은 머지 게이트 | 4종 SUCCESS | 전체 CTP를 대체하지 않음 |
| medium CTP | cas-merge 80491597d 시점 게이트 기록 | 975/975 | 머지 전 스위트 결과 |
| SQL CTP | 같은 최종 SQL 게이트 | 17,455/17,457, core 0 | 2건은 baseline 동률 정렬 known-benign으로 수용 |
| HA _22_ha | 선행 최종 게이트 | 25/28 | 잔여 3건 TC 비호환 분류 |
| HA 나머지 버킷 | 후속 티켓 | 14버킷 미완 | HA 전체 green 아님 |
| upstream test_shell | 7117c8a66, CircleCI 151311 | OK 2,704 / NOK 372 / skip 29 | 머지 전 실패 분석 |
| 같은 shell CI | 배정 3,222 | 미실행 105 / core 18 | 타임아웃 노드의 업로드 누락 OK 22건도 별도 존재 |

shell 집계 3,105와 미실행 105의 합이 3,222보다 12 작다고 숫자를 임의 보정하면 안 된다. 원 분석은 timeout 노드의 별도 실행·업로드 누락을 설명하며 배정량과 집계량의 집합 정의가 다르다. 이 자료는 원 기록의 집계를 그대로 싣는다. 전체 결과를 단순 합산해 새로운 통과율을 만들지 않는다.

근거: [머지 게이트 기록](https://github.com/xmilex-git/workspace/issues/208), [medium/sql CTP 재실행 + 잔존 NOK 최종 분류](https://github.com/xmilex-git/workspace/issues/169), [CI 실패 전수 분석](../research/cas-merge-ci-test-shell-7837.md), [HA 논의용 검증 — 발견 결함 해소와 미검증 범위 기록](https://github.com/xmilex-git/workspace/issues/219).

### HA 검증의 종료 범위 — 2026-09-06 합의

사용자는 이번 HA 티켓의 목적을 **개발자 논의에 필요한 검증 근거 확보**로 한정하고, 현재 실행 결과를 수거한 뒤 조기 종료하기로 확정했다. 핵심 HA 동작과 발견 결함의 수정·재검증 근거를 제시하며, 미실행 범위는 향후 병합 전 검증 목록으로 남긴다. 이 합의는 HA 전수 통과나 병합·배포 승인이 아니다.

HA 하네스 권한·복제 로그 정리 문제를 수정했고, 600개 연결 테스트의 호환 설정을 [비공개 TC 초안 PR](https://github.com/CUBRID/cubrid-testcases-private/pull/1644)에 반영했다. 부하 검증에서 검출한 드라이버 엔트리의 private LRU 상태 초기화 누락은 [수정 커밋](https://github.com/xmilex-git/cubrid/commit/cd6ab1b085300df69c28105f918075d6ffce1612)으로 cas-merge에 통합했다. 이 커밋은 본문 코드 비교점 이후의 수정이다.

최종 수거 결과, 출처, 미검증 목록과 결정 D1·D2는 [HA 논의용 검증 기록](ha-discussion-validation.md)에 둔다.

### 성능: 처리량 개선과 꼬리 지연을 함께 제시

release·100 connections·10M rows·20M operations·C/A 각 1회 기준이다. 기준 측정은 develop 5862371ba, 통합 측정 설치본은 d4c9c4f88이다. 공개 PR 머지 커밋에서 재측정한 결과가 아니다.

| 지표 | 기존 | 통합 | 변화 |
|---|---:|---:|---:|
| YCSB C 처리량, ops/s | 130,686 | 147,013 | +12.5% |
| YCSB A 처리량, ops/s | 27,279 | 29,063 | +6.5% |
| C READ p99, µs | 1,707 | 2,119 | +24.1% |
| A READ p99, µs | 8,071 | 11,279 | +39.7% |
| A UPDATE p99, µs | 29,231 | 23,679 | −19.0% |
| 오류 | 0 | 0 | 양쪽 기록 기준 |

기존 분석은 A의 꼬리 악화를 체크포인트 flush와 foreground 래치 경합, C를 일반 경합 큐잉으로 귀속했다. 단일 스레드 비교에서 통합 경로가 개선된 것도 근거로 삼았다. 이 해석이 지연 수치 악화 자체를 없애지는 않는다. 처리량과 꼬리를 같이 보고하며, 접속 churn·다른 워크로드·다른 동시성으로 일반화하지 않는다. [최종 게이트 YCSB 레그 — cas-merge 최종 tip release 비교](https://github.com/xmilex-git/workspace/issues/177).

## 4. 미결과 추가 최적화의 경계

CI shell 검증과 운영 정책은 별도 열린 티켓에 남는다. HA 전수 검증은 사용자 합의로 이번 HA 논의용 검증의 완료 조건에서 제외했고, 향후 병합 전 검증 목록으로 보존한다. shell 분석의 PRODUCT 표시는 로그 기반 1차 분류인 경우가 많다. 코어·PL isolation 대기·CDC 접속 실패를 'TC만 바꾸면 됨'으로 묶지 않는다. 발견 결함은 [CTP/CI 결함 통합 추적 (2기) — 결함 19번부터 단일 티켓](https://github.com/xmilex-git/workspace/issues/210)에 모은다.

추가 최적화는 다음 후보의 **조사 결과**까지 있으며 채택·우선순위 결정은 아직 남는다.

| 후보 | 이미 확인한 사실 | 다음 판단에 필요한 것 |
|---|---|---|
| prepared descriptor 공유 | 핸들은 세션별, xcache는 이미 공유 | 컴파일 비용 분해·키/권한/DDL 무효화 계약 |
| workspace→catalog 직접 읽기 | MOP는 캐시 외에도 DDL·의미 표현 역할 | 누락된 서버 표현·수명·락 계약 |
| XASL stream 제거 | prepared 클론 풀 히트는 unpack 생략 | clone miss 비율·비-prepared 비용·소유권 |
| PL 왕복 감소 | 서버측 재호출은 이미 in-process | JVM PREPARE/EXECUTE/FETCH 병합·프로토콜 변경 |
| TLS·할당·기존 락 비용 | TLS 비용 일부 실측, 기존 락·malloc 비용 관찰 | 효과를 귀속할 별도 측정과 회귀 조건 |

각 조사: [prepared](../research/cas-merge-opt-shared-prepared-statement.md), [workspace](../research/cas-merge-opt-workspace-to-catalog-latch.md), [XASL](../research/cas-merge-opt-xasl-no-stream.md), [PL](../research/cas-merge-opt-pl-inprocess-call.md).

cpp-perf-rules 관점의 재브레인스토밍과 구현은 이 문서가 대신하지 않는다. 후보 구현은 이 지도의 범위 밖이다.

## 5. 리뷰를 위한 PR 분할 제안 — 미확정

리뷰 묶음은 다음 순서가 이해하기 쉽다. 이는 기존 커밋을 그대로 cherry-pick하면 각 PR이 독립 빌드된다는 보장이 아니다. 최종 코드의 교차 의존을 보존하도록 분할을 다시 검증해야 한다.

| 순서 | 리뷰 묶음 | 먼저 합의할 계약 | 필요한 검증 |
|---|---|---|---|
| 1 | 빌드 편입·파서 TLS·컨텍스트 골격 | 상태 소유자와 모드별 컴파일 | 양 빌드·동시 파스 |
| 2 | 워크스페이스·메모리·RPC native seam | MOP/OID·힙·브래킷 수명 | 다중 세션·teardown·오류 경로 |
| 3 | DDL 권한·세션 파라미터·PL | 인증·무효화·중첩 호출 | GRANT/REVOKE·PL caught-error |
| 4 | 연결 입양·CAS 화자·HA·취소 | fd·슬롯·토큰·reset | JDBC/SSL/altHosts·부하 접속 |
| 5 | thin csql·유틸 도달성·운영 표면 | 로컬/원격·지원 명령·로그 | csql·CDC·관리·HA TC |
| 6 | CAS 제거·회귀 수정·최종 게이트 | 제품 비호환과 TC 갱신의 구분 | shell/HA 포함 전체 게이트 |

기존 S0/A1–A8/B1–B5는 구현 경로의 근거로 연결하되, 설명용 묶음과 반입 가능한 PR 단위를 혼동하지 않는다. 선존 엔진 결함의 상류 기여는 독립 재현·수정이 가능한지 별도로 검토한다. [마이그레이션 단계 분할 + 게이트 매핑](https://github.com/xmilex-git/workspace/issues/122).

사용자 검토에서는 이 순서가 동료 개발자 논의에 적합한지, 더 깊이 설명할 모듈이 무엇인지 확인한다. 운영 호환 정책은 담당 티켓의 결정을 기다려 갱신한다.

## 부록 A. 전체 변경 파일과 고정 코드 링크

비교: **231파일, +18,120/−2,614줄**. 아래 링크는 모두 공개 PR의 고정 커밋을 가리킨다. M=수정, A=추가.

```bash
git diff e374c7a24c46449c3f79e9413a6f4ff3d23b16c2...31702ac4a31cd2b1237812d5150a8cff9076d209 --stat
git diff e374c7a24c46449c3f79e9413a6f4ff3d23b16c2...31702ac4a31cd2b1237812d5150a8cff9076d209 --name-status
```

### 루트 빌드 (1)

- M [CMakeLists.txt](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/CMakeLists.txt)

### broker (1)

- M [broker/CMakeLists.txt](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/broker/CMakeLists.txt)

### cmake (1)

- A [cmake/patch_parser_tls.cmake](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/cmake/patch_parser_tls.cmake)

### cs (1)

- M [cs/CMakeLists.txt](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/cs/CMakeLists.txt)

### cubrid (1)

- M [cubrid/CMakeLists.txt](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/cubrid/CMakeLists.txt)

### src/base (18)

- M [src/base/area_alloc.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/area_alloc.c)
- M [src/base/ddl_log.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/ddl_log.c)
- M [src/base/error_context.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/error_context.cpp)
- M [src/base/error_context.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/error_context.hpp)
- M [src/base/error_manager.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/error_manager.c)
- M [src/base/error_manager.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/error_manager.h)
- M [src/base/intl_support.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/intl_support.c)
- M [src/base/intl_support.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/intl_support.h)
- M [src/base/language_support.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/language_support.c)
- M [src/base/language_support.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/language_support.h)
- M [src/base/memory_alloc.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/memory_alloc.c)
- M [src/base/perf_monitor.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/perf_monitor.c)
- M [src/base/perf_monitor.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/perf_monitor.h)
- M [src/base/system_parameter.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/system_parameter.c)
- M [src/base/system_parameter.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/system_parameter.h)
- M [src/base/unicode_support.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/unicode_support.c)
- M [src/base/unicode_support.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/unicode_support.h)
- M [src/base/xserver_interface.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/base/xserver_interface.h)

### src/broker (33)

- M [src/broker/broker.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker.c)
- M [src/broker/broker_acl.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker_acl.c)
- M [src/broker/broker_admin_pub.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker_admin_pub.c)
- M [src/broker/broker_config.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker_config.c)
- M [src/broker/broker_config.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker_config.h)
- A [src/broker/broker_direct.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker_direct.cpp)
- A [src/broker/broker_direct.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker_direct.h)
- M [src/broker/broker_monitor.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker_monitor.c)
- M [src/broker/broker_shm.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/broker_shm.h)
- M [src/broker/cas.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas.c)
- M [src/broker/cas_cgw.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_cgw.c)
- M [src/broker/cas_common_execute.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_common_execute.c)
- M [src/broker/cas_common_main.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_common_main.c)
- M [src/broker/cas_common_vars.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_common_vars.c)
- M [src/broker/cas_common_vars.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_common_vars.h)
- A [src/broker/cas_conn_helpers.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_conn_helpers.c)
- A [src/broker/cas_csql.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_csql.cpp)
- M [src/broker/cas_db_inc.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_db_inc.h)
- A [src/broker/cas_dispatch.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_dispatch.c)
- A [src/broker/cas_dispatch.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_dispatch.h)
- M [src/broker/cas_execute.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_execute.c)
- M [src/broker/cas_execute.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_execute.h)
- M [src/broker/cas_function.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_function.c)
- M [src/broker/cas_function.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_function.h)
- M [src/broker/cas_handle.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_handle.c)
- M [src/broker/cas_log.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_log.c)
- M [src/broker/cas_meta.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_meta.c)
- M [src/broker/cas_network.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_network.c)
- M [src/broker/cas_optimization.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_optimization.c)
- M [src/broker/cas_protocol.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_protocol.h)
- A [src/broker/cas_server_support.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_server_support.cpp)
- M [src/broker/cas_ssl.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_ssl.c)
- M [src/broker/cas_ssl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_ssl.h)

### src/communication (8)

- M [src/communication/network_callback_cl.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_callback_cl.cpp)
- M [src/communication/network_callback_sr.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_callback_sr.cpp)
- M [src/communication/network_cl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_cl.h)
- M [src/communication/network_histogram.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_histogram.hpp)
- M [src/communication/network_interface_cl.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_interface_cl.c)
- M [src/communication/network_interface_cl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_interface_cl.h)
- M [src/communication/network_interface_sr.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_interface_sr.cpp)
- M [src/communication/network_sr.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_sr.c)

### src/compat (11)

- M [src/compat/db.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/db.h)
- M [src/compat/db_admin.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/db_admin.c)
- M [src/compat/db_macro.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/db_macro.c)
- M [src/compat/db_query.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/db_query.c)
- M [src/compat/db_query.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/db_query.h)
- M [src/compat/db_vdb.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/db_vdb.c)
- M [src/compat/dbi.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/dbi.h)
- M [src/compat/dbi_compat.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/dbi_compat.h)
- M [src/compat/dbtype_def.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/dbtype_def.h)
- M [src/compat/dbtype_function.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/dbtype_function.c)
- M [src/compat/dbtype_function.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/dbtype_function.h)

### src/connection (10)

- A [src/connection/adoption.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/adoption.cpp)
- A [src/connection/adoption.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/adoption.hpp)
- M [src/connection/connection_cl.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/connection_cl.cpp)
- M [src/connection/connection_cl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/connection_cl.h)
- M [src/connection/connection_defs.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/connection_defs.h)
- M [src/connection/connection_less.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/connection_less.cpp)
- A [src/connection/driver_session.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/driver_session.cpp)
- A [src/connection/driver_session.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/driver_session.hpp)
- M [src/connection/server_support.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/server_support.c)
- M [src/connection/server_support.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/server_support.h)

### src/executables (9)

- M [src/executables/csql.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/csql.c)
- M [src/executables/csql.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/csql.h)
- M [src/executables/csql_result.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/csql_result.c)
- M [src/executables/csql_result_format.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/csql_result_format.c)
- M [src/executables/csql_session.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/csql_session.c)
- M [src/executables/csql_support.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/csql_support.c)
- A [src/executables/csql_wire.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/csql_wire.c)
- A [src/executables/csql_wire.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/csql_wire.h)
- M [src/executables/server.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/executables/server.c)

### src/method (12)

- M [src/method/method_callback.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_callback.cpp)
- M [src/method/method_callback.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_callback.hpp)
- M [src/method/method_oid_handler.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_oid_handler.hpp)
- M [src/method/method_query_handler.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_query_handler.hpp)
- M [src/method/method_query_result.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_query_result.hpp)
- M [src/method/method_query_util.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_query_util.cpp)
- M [src/method/method_query_util.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_query_util.hpp)
- M [src/method/method_schema_info.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_schema_info.hpp)
- M [src/method/method_struct_query.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_struct_query.cpp)
- M [src/method/method_struct_query.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_struct_query.hpp)
- M [src/method/method_struct_value.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/method_struct_value.cpp)
- M [src/method/query_method.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/method/query_method.cpp)

### src/object (39)

- M [src/object/authenticate.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/authenticate.c)
- M [src/object/authenticate.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/authenticate.h)
- M [src/object/authenticate_cache.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/authenticate_cache.cpp)
- M [src/object/authenticate_grant.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/authenticate_grant.cpp)
- M [src/object/class_description.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/class_description.hpp)
- M [src/object/class_object.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/class_object.c)
- M [src/object/class_object.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/class_object.h)
- A [src/object/client_session_context.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/client_session_context.cpp)
- A [src/object/client_session_context.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/client_session_context.hpp)
- M [src/object/deduplicate_key.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/deduplicate_key.c)
- M [src/object/deduplicate_key.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/deduplicate_key.h)
- M [src/object/msgcat_help.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/msgcat_help.hpp)
- M [src/object/object_accessor.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_accessor.c)
- M [src/object/object_accessor.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_accessor.h)
- M [src/object/object_description.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_description.hpp)
- M [src/object/object_domain.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_domain.c)
- M [src/object/object_domain.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_domain.h)
- M [src/object/object_fetch.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_fetch.h)
- M [src/object/object_primitive.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_primitive.c)
- M [src/object/object_print.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_print.h)
- M [src/object/object_print_util.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_print_util.hpp)
- M [src/object/object_printer.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_printer.cpp)
- M [src/object/object_printer.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_printer.hpp)
- M [src/object/object_template.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_template.c)
- M [src/object/object_template.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/object_template.h)
- M [src/object/quick_fit.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/quick_fit.c)
- M [src/object/schema_manager.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/schema_manager.c)
- M [src/object/schema_manager.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/schema_manager.h)
- M [src/object/schema_template.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/schema_template.h)
- M [src/object/set_object.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/set_object.c)
- M [src/object/set_object.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/set_object.h)
- M [src/object/transform_cl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/transform_cl.h)
- M [src/object/trigger_description.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/trigger_description.cpp)
- M [src/object/trigger_description.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/trigger_description.hpp)
- M [src/object/trigger_manager.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/trigger_manager.c)
- M [src/object/trigger_manager.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/trigger_manager.h)
- M [src/object/virtual_object.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/virtual_object.h)
- M [src/object/work_space.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/work_space.c)
- M [src/object/work_space.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/work_space.h)

### src/optimizer (5)

- M [src/optimizer/optimizer.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/optimizer/optimizer.h)
- M [src/optimizer/query_graph.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/optimizer/query_graph.c)
- M [src/optimizer/query_graph.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/optimizer/query_graph.h)
- M [src/optimizer/query_planner.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/optimizer/query_planner.c)
- M [src/optimizer/query_planner.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/optimizer/query_planner.h)

### src/parser (22)

- M [src/parser/csql_grammar.y](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/csql_grammar.y)
- M [src/parser/csql_grammar_scan.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/csql_grammar_scan.h)
- M [src/parser/csql_lexer.l](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/csql_lexer.l)
- A [src/parser/csql_parser_tls.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/csql_parser_tls.h)
- M [src/parser/double_byte_support.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/double_byte_support.c)
- M [src/parser/keyword.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/keyword.c)
- M [src/parser/method_transform.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/method_transform.c)
- M [src/parser/name_resolution.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/name_resolution.c)
- M [src/parser/parse_evaluate.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/parse_evaluate.c)
- M [src/parser/parse_tree.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/parse_tree.c)
- M [src/parser/parse_tree.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/parse_tree.h)
- M [src/parser/parse_tree_cl.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/parse_tree_cl.c)
- M [src/parser/parser.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/parser.h)
- M [src/parser/parser_support.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/parser_support.c)
- M [src/parser/parser_support.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/parser_support.h)
- M [src/parser/scanner_support.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/scanner_support.c)
- M [src/parser/show_meta.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/show_meta.c)
- M [src/parser/show_meta.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/show_meta.h)
- M [src/parser/view_transform.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/view_transform.c)
- M [src/parser/xasl_generation.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/xasl_generation.c)
- M [src/parser/xasl_generation.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/xasl_generation.h)
- M [src/parser/xasl_regu_alloc.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/parser/xasl_regu_alloc.hpp)

### src/query (19)

- M [src/query/cursor.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/cursor.c)
- M [src/query/execute_schema.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/execute_schema.c)
- M [src/query/execute_schema.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/execute_schema.h)
- M [src/query/execute_statement.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/execute_statement.c)
- M [src/query/execute_statement.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/execute_statement.h)
- M [src/query/fetch.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/fetch.c)
- M [src/query/parallel/px_query_execute/px_query_executor.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/parallel/px_query_execute/px_query_executor.cpp)
- M [src/query/parallel/px_scan/px_scan_instnum.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/parallel/px_scan/px_scan_instnum.cpp)
- M [src/query/parallel/px_scan/px_scan_instnum.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/parallel/px_scan/px_scan_instnum.hpp)
- M [src/query/query_cl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/query_cl.h)
- M [src/query/query_executor.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/query_executor.c)
- M [src/query/query_hash_join.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/query_hash_join.c)
- M [src/query/query_manager.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/query_manager.c)
- M [src/query/show_scan.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/show_scan.c)
- M [src/query/string_opfunc.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/string_opfunc.c)
- M [src/query/string_opfunc.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/string_opfunc.h)
- M [src/query/xasl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/xasl.h)
- M [src/query/xasl_to_stream.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/xasl_to_stream.c)
- M [src/query/xasl_to_stream.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/xasl_to_stream.h)

### src/session (3)

- M [src/session/session.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/session/session.c)
- M [src/session/session.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/session/session.h)
- M [src/session/session_sr.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/session/session_sr.c)

### src/sp (7)

- M [src/sp/jsp_cl.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/sp/jsp_cl.cpp)
- M [src/sp/jsp_cl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/sp/jsp_cl.h)
- M [src/sp/method_invoke_group.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/sp/method_invoke_group.cpp)
- M [src/sp/method_invoke_group.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/sp/method_invoke_group.hpp)
- M [src/sp/pl_session.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/sp/pl_session.cpp)
- M [src/sp/pl_signature.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/sp/pl_signature.cpp)
- M [src/sp/pl_signature.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/sp/pl_signature.hpp)

### src/storage (5)

- M [src/storage/external_sort.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/storage/external_sort.c)
- M [src/storage/oid.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/storage/oid.h)
- M [src/storage/page_buffer.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/storage/page_buffer.c)
- M [src/storage/statistics.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/storage/statistics.h)
- M [src/storage/storage_common.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/storage/storage_common.h)

### src/thread (1)

- M [src/thread/thread_entry.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/thread/thread_entry.cpp)

### src/transaction (10)

- M [src/transaction/boot.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/boot.h)
- M [src/transaction/boot_cl.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/boot_cl.c)
- M [src/transaction/locator_cl.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/locator_cl.c)
- M [src/transaction/locator_cl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/locator_cl.h)
- M [src/transaction/log_comm.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/log_comm.h)
- M [src/transaction/log_tran_table.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/log_tran_table.c)
- A [src/transaction/server_compile_tracer.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/server_compile_tracer.cpp)
- A [src/transaction/server_compile_tracer.hpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/server_compile_tracer.hpp)
- M [src/transaction/transaction_cl.c](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/transaction_cl.c)
- M [src/transaction/transaction_cl.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/transaction/transaction_cl.h)

### unit_tests (14)

- M [unit_tests/CMakeLists.txt](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/CMakeLists.txt)
- A [unit_tests/server_compile/B1JdbcSmoke.java](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/B1JdbcSmoke.java)
- A [unit_tests/server_compile/CMakeLists.txt](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/CMakeLists.txt)
- A [unit_tests/server_compile/csql.access](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/csql.access)
- A [unit_tests/server_compile/probe_csql.py](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/probe_csql.py)
- A [unit_tests/server_compile/probe_direct.py](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/probe_direct.py)
- A [unit_tests/server_compile/probe_direct_connect.py](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/probe_direct_connect.py)
- A [unit_tests/server_compile/smoke.sh](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/smoke.sh)
- A [unit_tests/server_compile/smoke_csql.sh](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/smoke_csql.sh)
- A [unit_tests/server_compile/smoke_direct.sh](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/smoke_direct.sh)
- A [unit_tests/server_compile/smoke_gate.sh](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/smoke_gate.sh)
- A [unit_tests/server_compile/smoke_jdbc.sh](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/smoke_jdbc.sh)
- A [unit_tests/server_compile/smoke_thin.sh](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/smoke_thin.sh)
- A [unit_tests/server_compile/test_main.cpp](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/unit_tests/server_compile/test_main.cpp)
