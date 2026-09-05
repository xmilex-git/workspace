# HA 논의용 검증: 종료 근거와 향후 검증 범위

[논의 자료 부록](develop-vs-cas-merge-appendices.md) · [HA 논의용 검증 티켓](https://github.com/xmilex-git/workspace/issues/219)

## 사용자와 확정한 범위 — 2026-09-06

- **D1 목적**: 개발자 논의에 필요한 검증 근거 확보. 사용자는 “논의만”으로 확정했다. 병합·배포 승인 수준의 HA 전수 검증은 이번 티켓의 목적에서 제외한다.
- **D2 종료선**: 현재 실행을 중단하고 완료 결과·로그를 수거한다. 발견 결함과 검증 근거를 문서화하고, 미실행 범위를 향후 병합 전 검증 목록으로 남긴 뒤 티켓을 종료한다. 사용자가 이 제안에 동의했다.
- **이유와 대가**: 핵심 HA 및 부하 검증으로 실제 결함을 찾아 수정·재검증했고, 논의에 필요한 근거가 확보됐다. 남은 시나리오의 회귀 가능성은 검증되지 않았다. 전체 HA green이나 병합·배포 승인으로 해석하지 않는다.
- **재개 조건**: 병합 판단 단계에서 아래 목록을 입력으로 별도 검증 범위를 정한다. 자동 재실행이나 새 작업은 예약하지 않았다. 다른 운영 정책·CI 티켓의 완료 조건은 이 결정으로 바꾸지 않는다.

## 해결한 문제와 통합 상태

| 문제 | 해결·검증 근거 |
|---|---|
| HA DB 레지스트리 권한 | 러너 75ea433, 원 실패 케이스 1/1 PASS, 실행기 자체 검사 28/28 |
| 케이스 사이 이전 DB 복제 로그 재사용 | 러너 936721c, 원래 두 케이스 연속 실행 2회 모두 2/2 PASS |
| 600개 연결의 슬롯 부족·원격 thin csql 접속 설정 | 원래 600개 연결과 단언을 유지한 호환 설정, 비공개 TC 초안 PR에 반영 |
| 종료한 드라이버 엔트리의 private LRU 상태 잔류 | 엔진 cd6ab1b08, fresh optdebug/release·양쪽 unit 18/18·smoke 통과, 동일 600개 연결 HA 재검증 후 cas-merge 통합 |

상세 원인과 이전 검증은 [CTP/CI 결함 통합 추적](https://github.com/xmilex-git/workspace/issues/210)의 결함 19–22에 있다. 엔진 [수정 커밋](https://github.com/xmilex-git/cubrid/commit/cd6ab1b085300df69c28105f918075d6ffce1612)은 [CAS 통합 PR](https://github.com/CUBRID/cubrid/pull/7837)에 반영됐다. [TC 초안 PR](https://github.com/CUBRID/cubrid-testcases-private/pull/1644)은 열려 있으며 병합 완료를 뜻하지 않는다.

## 마지막 부분 실행 결과

출처: 엔진 cd6ab1b08 optdebug 설치본, CTP 8cb1b9b, TC 21122e4fe033 기반 호환 사본(as-is 출처 명시). 이번 사본의 변경은 TC 커밋 1d7f6e0과 같은 패치다. 단일 master/slave 컨테이너 쌍에서 실행했다.

- 계획: enhancement 55개 테스트 디렉터리, 그 안의 SQL 파일 108개.
- 완료: **6개 디렉터리 OK, NOK 0, skip 0; 단언 23/23 OK**.
- 완료 목록: bug_bts_3885_1, bug_bts_3885_2, bug_bts_3885_3, bug_bts_3928_1, bug_bts_3928_2, bug_bts_3971.
- 600개 연결 케이스: 단언 2/2 OK, 534초, Java 예외·오류·접속 타임아웃 문자열 0. 앞선 별도 수정 후 실행에서는 실제 600개 테이블·69,017행 일치를 확인했다. 그 행 수를 이번 실행의 측정으로 재사용하지 않는다.
- 코어/fullstack: 중단 전 컨테이너 검사와 수거 후 파일 검사에서 발견되지 않았다.
- 중단 시 bug_bts_3973은 결과 파일이 비어 있어 미완료다. 이후 48개 디렉터리는 미실행이다.
- 사용자 승인에 따라 해당 실행의 두 컨테이너만 중단했다. 종료 유예 후 SIGKILL로 shard rc137, 실행기 exit1이 발생했다. 실행기 최종 표시는 FAILED지만, 이 종료 코드는 운영자 중단의 결과이며 엔진 크래시나 TC NOK로 분류하지 않는다.
- 두 컨테이너와 실행 전용 프로세스 정리를 확인했고 증거를 보존했다.

중단 실행에는 JUnit 파일이 없으므로 test_status.data와 개별 result 파일을 대조했다. SQL 파일 108개와 완료 디렉터리 6개는 서로 다른 단위다. 6/108 같은 통과율을 계산하지 않는다.

## 향후 병합 전 검증 목록

원 제목의 “14버킷”과 달리, 본문이 가리키는 enhancement·features·과일 계열은 아래 **13개 버킷**이다. 구형 _12_bts_issue와 _16_bts_issue는 이 목록에 포함하지 않았다.

| 버킷 | 이번 종료 시 남은 범위 |
|---|---|
| _23_ha_enhancement | 미완료 bug_bts_3973 + 미실행 48개 디렉터리; 순서·대상은 보존한 units.tsv |
| _25_features_844 | 이번 게이트 미실행 |
| _26_features_845 | 이번 게이트 미실행 |
| _27_features_920 | 이번 게이트 미실행 |
| _28_features_930 | 이번 게이트 미실행 |
| _29_banana_qa | 이번 게이트 미실행 |
| _30_banana_pie | 이번 게이트 미실행 |
| _31_cherry | 이번 게이트 미실행 |
| _36_damson | 이번 게이트 미실행 |
| _37_elderberry | 이번 게이트 미실행 |
| _38_fig | 이번 게이트 미실행 |
| _39_fig_cake | 이번 게이트 미실행 |
| _40_guava | 이번 게이트 미실행 |

선행 _22_ha 기록은 25/28 통과와 3건 정당분류이며, 현재 수정 커밋에서 다시 전수 실행했다는 뜻은 아니다. 향후 병합 검증에서는 사용할 최종 엔진·TC 커밋을 고정하고 필요한 재실행 범위를 정해야 한다.

## 보존한 원격 증거

호스트: cubrid@192.168.6.34.

- 실행: /home/cubrid/dev/workspace/.git_ignored_dir/scratch/ctp-run-out/ha_shell-20260905T171707Z-3751274/
- 수거 보고서: /home/cubrid/dev/workspace/.git_ignored_dir/scratch/wf219-ha23-gate/report.md
- 실행 로그: 같은 보고서 디렉터리의 run.log
- provenance.txt/tsv, units.tsv, test_status.data, 개별 cases/*.result와 Java 로그 보존.
