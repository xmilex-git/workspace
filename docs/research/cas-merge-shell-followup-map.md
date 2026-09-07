# CAS 통합 셸 CI 후속 배정표

[CAS 통합 후속 지도](https://github.com/xmilex-git/workspace/issues/207)의 실행 티켓을 실패 계열별로 나눈 배정 기록이다. 각 TC의 판정·수정 결과는 담당 티켓에 기록한다. 이 문서는 소유권과 기준점만 유지한다.

## 기준과 해석

- 기준 CI: gha-ci run `34089071541`, 엔진 `2cb1f8865`, TC `f5ca3fd222128a02f750bf47032dfa3d6fc92e42`. 당시 OK 2,905 / NOK 295 / 미실행 0 / 보고된 코어 0. **295는 현재 head의 잔존 실패 수가 아니다.**
- 기준 NOK 경로 295개를 [기계 판독 배정표](cas-merge-shell-followup-map.tsv)에 정확히 한 번씩 기록했다. 기존 A~L/NEW/UNEXECUTED 분류와 근인 추정은 원본 로그의 초기 가설이며, 새 담당 계열은 작업 배정이지 근인 확정이 아니다.
- `local_status=recheck_required`는 현재 엔진에서 원본을 다시 검증해야 한다는 뜻이다. 최근 출력/GET 수정의 영향을 받은 TC를 검증 없이 완료로 처리하지 않는다. `verified_pass_*`는 해당 head에서 원본 TC를 실제로 통과한 행이며 전체 CI 통과를 뜻하지 않는다.
- 작업 기준/설치본은 [CI test_shell 1차 안정화](https://github.com/xmilex-git/workspace/issues/211)의 종료 기록이 우선한다. 최초 분할 준비 기준은 `54126c187`; 마지막 차단 설정 수정의 검증 결과도 이 종료 기록에 합쳐진다.
- 원본 근거: [기존 CI 분류](cas-merge-ci-test-shell-7837.md), 툴링 scratch `wf211-resume/ci-run-34089071541/classified.tsv`, `wf211-resume/repro-295/evidence/INDEX.tsv`와 개별 md. 원본 근거와 후속 소유권을 혼동하지 않는다.

## 담당 티켓

| 담당 계열 | 기준 NOK 배정 수 | 선행 조건 |
|---|---:|---|
| [CI test_shell 1차 안정화 — 제품 수정 검증과 잔여 TC 계열 이관](https://github.com/xmilex-git/workspace/issues/211) | 1 | 이 세션에서 검증한 항목; 종료 기록 확인 |
| [운영 호환 구현 잔여 — 로그·동적 제어·접속 종류·query replace](https://github.com/xmilex-git/workspace/issues/222) | 4 | 독립 진행 가능; 확정 운영 정책 준수 |
| [CAS·SHARD 가정 TC 이행 — 상태 조회·프로세스·로그 기대값 갱신](https://github.com/xmilex-git/workspace/issues/223) | 110 | [운영 호환 구현 잔여](https://github.com/xmilex-git/workspace/issues/222) |
| [csql histogram·드라이버 상세 계측 — 세션 귀속·권한·초기화 복구](https://github.com/xmilex-git/workspace/issues/224) | 14 | 독립 진행 가능; 확정 운영 정책 준수 |
| [csql 출력·이력·실행계획 TC 계열 — 원본 재현과 렌더링 호환](https://github.com/xmilex-git/workspace/issues/225) | 62 | 독립 진행 가능; 확정 운영 정책 준수 |
| [세션·설정 파일 TC 계열 — client-only 값·locale·설정 우선순위](https://github.com/xmilex-git/workspace/issues/226) | 9 | [선행 안정화 완료](https://github.com/xmilex-git/workspace/issues/211) |
| [CS·CCI·접속 오류 TC 계열 — 유틸 접속·재시도·결과 정합성](https://github.com/xmilex-git/workspace/issues/227) | 21 | 독립 진행 가능; 확정 운영 정책 준수 |
| [PL/CSQL·JavaSP·대기 TC 계열 — isolation·콜백·동시 접속](https://github.com/xmilex-git/workspace/issues/228) | 22 | 독립 진행 가능; 확정 운영 정책 준수 |
| [코어·MERGE·클라이언트 kill TC 계열 — 종료 시그니처 판정](https://github.com/xmilex-git/workspace/issues/229) | 5 | 독립 진행 가능; 확정 운영 정책 준수 |
| [loaddb·쿼리 결과·관리 유틸 TC 계열 — serial·덤프·시맨틱 정합성](https://github.com/xmilex-git/workspace/issues/230) | 5 | 독립 진행 가능; 확정 운영 정책 준수 |
| [HA cci_applier 실패 처리 TC — 오류 후 종료·정리 검증](https://github.com/xmilex-git/workspace/issues/231) | 1 | 독립 진행 가능; 확정 운영 정책 준수 |
| [환경·JDBC 로그 변경·시간 플레이키 TC 판정](https://github.com/xmilex-git/workspace/issues/232) | 4 | 독립 진행 가능; 확정 운영 정책 준수 |
| [미분류·신규 NOK TC 재판정 — 실제 diff로 담당 계열 확정](https://github.com/xmilex-git/workspace/issues/233) | 37 | 독립 진행 가능; 확정 운영 정책 준수 |
| [최종 test_shell green 게이트 — 계열 통합·정당 skip·운영 정책 완료 판정](https://github.com/xmilex-git/workspace/issues/234) | 0 | 각 계열 티켓과 선행 안정화 완료 |

최종 게이트는 개별 TC의 중복 소유자가 아니다. 기준 목록에 없던 새 CI 실패를 찾고 담당 계열에 배정하며, 모든 계열의 완료와 확정 운영 정책 검증을 합쳐 판정한다. 한 TC에 여러 원인이 있으면 담당 티켓은 하나를 유지하고 협업 링크를 추가한다. 소유권을 바꿀 때에는 양쪽 티켓의 목록과 TSV를 함께 수정한다.

## Blocking

- 운영 호환 구현 → CAS·SHARD TC 이행. 남아야 할 기능이 구현되기 전에 답안만 바꾸지 않는다.
- 모든 계열 → 최종 test_shell green 게이트. 선행 안정화도 이 게이트의 native blocker로 남는다.
- 최종 셸 게이트 → CTP/CI 결함 통합 추적의 최종 정리.
- 새 티켓 전부 → 통합 JIRA 작성. 기존 지도의 다른 blocker도 보존한다. 결함 기록 정리와 최종 게이트를 역방향으로 연결하지 않는다.

이 관계는 본문 관례가 아니라 GitHub native sub-issue/issue dependency로 연결한다. 지도 본문에는 열린 티켓을 나열하지 않고 자식 목록을 조회한다.

## 공통 실행·판정 규칙

- 구현·판단은 리드, 재현·분석·빌드·실행 검증은 `.agents/AGENTS.md`의 단일 `herdr-integration` 경로로 Sonnet에 위임한다. 실행 중 중간 로그를 리드에게 반복 유입하지 않고 native wait 뒤 최종 보고서를 읽는다.
- CTP는 `just ctp`/`just ctp-rerun`의 컨테이너 경로만 사용한다. **smoke는 호스트 실행을 허용**하며 서버 제어 래퍼·포트 관리·정리를 준수한다. DB 생성 전에 작업 디렉터리도 scratch로 옮긴다.
- 제품 수정은 fresh optdebug/release, 실제 활성화한 unit target, 관련 smoke와 원본 TC의 결과를 구분해 기록한다. `12/14`나 `No tests were found`를 PASS로 적지 않는다. 재사용 JDBC jar의 실제 버전도 명시한다.
- [운영 정책](https://github.com/xmilex-git/workspace/issues/209#issuecomment-5559332086)은 기능 보존이 기준이다. histogram 미지원 처리, 기본값만 바꾼 동적 제어, 비활성 query replace를 완료로 보지 않는다.
- 결함 상세는 [CTP/CI 결함 통합 추적](https://github.com/xmilex-git/workspace/issues/210)에 모으고 각 계열 티켓에서 참조한다. 이 분할은 결함별 독립 PR을 만드는 지시가 아니다. 기존 [엔진 PR](https://github.com/CUBRID/cubrid/pull/7837)과 [셸 TC PR](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4040)을 사용한다.

## 보존해야 할 정정

- 기본 `csql_plan`은 양 비교 빌드·일반/sysadm PTY 및 정식 TC에서 통과했다. 다른 PrintInfo.exp 실패 계열 전체가 해소됐다는 증거는 아니다.
- thin csql의 SET/GET과 SQL 실행은 서버로 전달된다. `libcubridcs` 심볼 유무나 과거 AGENTS 개요만으로 클라이언트 프로세스 내부 실행이라고 판정하지 않는다.
- `bug_bts_11548`의 GET 세션 값과 실제 lock-timeout 별칭은 별개 결함으로 수정·검증됐다.
- PL isolation의 개별 디렉터리 재현은 `common/` 누락으로 무효였다. 부모 디렉터리를 실행하고 원래 CI 원인을 새로 확인한다.
- `e51ba31`은 과거 폴드 빌드다. 이를 develop 기준선으로 부르거나 양쪽 실패를 상류 결함의 증거로 쓰지 않는다.
- 코어의 메인 스레드 `epoll_wait`는 크래시 스레드가 아니다. 실제 종료 스레드·맞는 ELF/라이브러리로 판정한다.
