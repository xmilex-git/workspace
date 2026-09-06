# D5 AREA 수명 검증과 HA 레시피 복구

## 결과

HA 원본 28개를 수정 레시피로 다시 실행해 **25 PASS / 3 FAIL, 코어 0개**로 이전 기준을 복구했다. 개별 단언은 **57 OK / 6 NOK**다. 첫 재실행에서 늘어난 15개 실패가 모두 해소됐다. 원본 러너의 종료 코드는 기존 3개 실패를 반영하는 rc1이며, 전체 green으로 표시하지 않는다.

| 실행 | 디렉터리 PASS / FAIL | 코어 |
|---|---|---|
| 이전 HA 기준 | 25 / 3 | 0 |
| 자동 포트 준비가 빠진 D5 첫 재실행 | 10 / 18 | 0 |
| 레시피 수정 후 전체 재실행 | **25 / 3** | **0** |

이전 25/28 기록은 [HA 완료 PR](https://github.com/xmilex-git/cubrid/pull/255)에 있다. 첫 재실행의 대표 기준 케이스 하나만으로 증가한 실패를 분류하고 티켓을 종료했던 판단을 이번 전체 재검증 결과로 대체한다.

## 레시피 수정

[툴링 a5429fd](https://github.com/xmilex-git/workspace/commit/a5429fd79feb6fac2dd0e5053627d673e84795d5)를 main에 반영했다.

- CTP의 default.broker2.BROKER_PORT를 읽어 master/slave 양쪽 qa SSH 환경에 CUBRID_CSQL_BROKER_PORT를 자동 전달한다. 누락·중복·비숫자·포트 범위 오류는 준비 단계에서 거부한다.
- 폴드 빌드에서만 실행 사본의 CTP HA helper에 slave 브로커 기동을 추가한다. 브로커 설정 업로드와 heartbeat 기동이 끝난 다음 수행한다.
- helper 구조 변경은 검사하고, 동일 사본에 반복 적용해도 중복 삽입하지 않는다. 호스트 CTP·테스트케이스 원본·TC 단언은 수정하지 않는다.

일반 작업 디렉터리에서 사용한 명령은 아래와 같다. 출력 디렉터리 지정 외에 별도 포트 변수나 TC 수정은 없었다.

```bash
BUILD=~/optdebug/CUBRID-wf220-area-lifetime PR=7837 just ctp ha_shell _22_ha
```

새 HA 설정 회귀 검사는 13/13 PASS, 전체 러너 자체 검사는 29개 PASS다. 실행 중 양쪽 실제 qa 로그인 환경의 포트 13091과 양쪽 query_editor/broker1의 기동 상태를 직접 수집했다. 대표 bug_3196도 같은 일반 레시피에서 PASS했다.

## 남은 실패

| 케이스 | 실패 단언 | 근거 |
|---|---|---|
| bug_3911 | 6, 12 | 이전과 같은 두 검사 실패 |
| bug_4027 | 1, 2, 3 | 기존 CAS 프로세스 수 기대값 비호환; 4번은 OK |
| bug_xdbms2760 | 1 | 자식 부하는 마지막 반복 후 abc를 DROP하지만 부모는 200초 뒤 조회한다. 마지막 배치 DELETE a=7251까지 진행했고 복제 완료 확인도 성공한 뒤, 양쪽 조회에서 이미 삭제된 abc가 없었다. 기존 고정 대기 시간 경합이며 브로커 접속 오류가 아니다. |

추가 실패는 없다. 계획의 38은 보조 스크립트를 포함한 파일 수이고, assignment/units의 28개 디렉터리는 모두 실행됐다.

## AREA 검증과 HA의 역할

[엔진 PR](https://github.com/xmilex-git/cubrid/pull/261)의 검증한 구현은 d8cbe2ddc이며, cas-merge 병합은 dbf0b6409다. AREA 가드의 수명을 확인하는 직접 검사와 원래 copylogdb 재접속 증상이 나온 HA 회귀를 함께 수행했다. 넓은 HA 스위트가 직접 수명 검사를 대체하는 것은 아니다.

- fresh optdebug/release 빌드, 양쪽 unit 각각 18/18, smoke 14/14 + JDBC/thin/csql/gate PASS.
- 같은 AREA 초기화를 두 번 호출하면 기준본은 10개, 수정본은 필요한 5개만 유지한다.
- 모듈 초기화·해제 20회 반복 후 잔여 AREA는 0개다.
- 실제 한 CS 프로세스에서 예상한 접속 실패 뒤 정상 접속·종료를 5회 반복해 PASS했다.
- 원래 오류가 나온 copylogdb를 포함한 _22_ha 전체를 이번 레시피로 재실행했다.

## 출처와 한계

전체 실행: 20260906T030349Z-4069790, 엔진 설치본 d8cbe2ddc, CTP 8cb1b9b, HA TC develop 21122e4fe033. HA의 PR 지정은 러너의 기존 규약에 따라 private TC develop을 사용하며 출처에 기록된다.

원격 증거 루트: /home/cubrid/dev/workspace/.git_ignored_dir/scratch/wf220-recipe/  
전체 원본 결과: ctp-ha22-full/ 및 ha22-full.log  
실제 환경·기동 증거: qa-env-both-nodes.txt, broker-status-both-nodes-live.txt  
최종 상태·체크섬: final-state.txt, final-sha256.txt

bug_3196의 원본 비교 단언은 통과했지만, 별도로 시도한 literal [100000] 출력 채증은 확보하지 못했다. 성공 TC의 즉시 파일 정리, 빈 파일 닫기 이벤트와 좁은 조회 시점 때문에 생긴 채증 한계이며, 개별 100000행 값을 관측했다고 주장하지 않는다. INVALID-empty-inotify-capture 및 watcher 시험 자료는 데이터 증거에서 제외한다.

작업 전용 컨테이너와 프로세스를 정리했고 공용 CUBRID는 변경하지 않았다. 기존 untracked designs/도 유지했다.
