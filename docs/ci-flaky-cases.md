# CI flaky TC 목록 (2026-10-02 기준)

메모리에 기록된 flaky 케이스와 PR 8034 리뷰 대응 세션(2026-10-01~02)에서 새로 확인한 케이스를 한곳에 모았다. 케이스마다 근거, flaky한 이유, 해결 여부(날짜), 오늘도 발생하는지를 적는다.

## 집계 방법과 한계

- **출처:** upstream gha-ci 아티팩트 서버 `http://192.168.1.48:30080/runs/<run>/<suite>/collect/failed.list`. 2026-09-16 19:34 ~ 2026-10-02 10:32 KST 실행분(shell 410, sql 346, medium 331개 목록)을 모두 받아 케이스별로 셌다. run 날짜와 PR 번호는 `gh run list --workflow gha-ci`로 붙였다.
- **"PR 수":** 그 케이스가 실패한 서로 다른 PR의 수. PR 하나에서만 반복되면 그 PR 탓일 수 있고, 여러 PR에 흩어져 있으면 flaky 쪽 근거가 된다.
- **"오늘":** 2026-10-02 00:00 KST 이후 실행분. 집계 시점(10:47 KST)까지 5개 run(PR 8034 재실행, nightly 2, PR 7972, PR 8046)뿐이라 표본이 작다.
- **failed.list의 한계:** 원인을 적지 않는다. 앞 케이스의 서버 abort 뒤 연쇄 실패(-677 등), 엔진과 TC 브랜치의 develop 시차(skew), PR 자체 결함이 모두 같은 형태로 섞인다. 아래 "근거"에 적은 것만 원인을 확인한 것이다.
- **격리 커밋:** 2026-09-30 19:53 KST, cubrid-testcases-private-ex `a72b396e6` ([CUBRIDQA-1136] #4268, tw-kang)이 shell 7건을 `shell/_25_unstable/`로 옮겼다. 사유는 `_25_unstable/readme.txt`에 있다. 이동한 경로로는 실패 기록이 0건이다. 다만 PR의 `tc/pr-<N>` 브랜치가 이 커밋 전에 develop을 합쳤다면 옛 경로로 계속 돌기 때문에, 그 뒤에도 일부 PR에서 실패가 나온다. 예를 들어 tc/pr-8022, 8025, 8034, 8046, 7987에는 이 커밋이 없다.

## 요약

| 케이스 | 스위트 | 실패 run (전체 대비) | PR 수 | 마지막 발생 (KST) | 오늘 | 상태 |
|---|---|---|---|---|---|---|
| `_06_issues/_17_1h/cbrd_20759/hide_cubrid_replay` | shell | 72 / 410 | 42 | 10-02 09:44 (PR 8046) | **발생** | 2026-09-30 `_25_unstable`로 격리, 수정 없음 |
| `_06_issues/_15_1h/bug_bts_15156` | shell | 37 / 410 | 25 | 10-01 17:33 | 없음 | 2026-09-30 격리 |
| `_06_issues/_18_1h/bug_bts_14305` | shell | 18 / 410 | 11 | 10-01 15:01 | 없음 | 2026-09-30 격리 |
| `_06_issues/_11_2h/bug_bts_6199` | shell | 9 / 410 | 8 | 10-01 17:33 (PR 8034) | 없음 | 2026-09-30 격리 |
| `_06_issues/_15_1h/bug_bts_15489` | shell | 8 / 410 | 7 | 10-01 08:31 | 없음 | 2026-09-30 격리 |
| `_39_fig_cake/cbrd_23768` | shell | 2 / 410 | 2 | 10-01 17:07 (PR 8034) | 없음 | 미해결 |
| `_36_damson/cbrd_23608_tde/temp_enc_06` | shell | 9 / 410 | 7 | 10-01 20:01 | 없음 | 미해결(원인 판단이 갈림, 아래) |
| `sql/_27_banana_qa/.../_02_addmonths.sql` | sql | 2 / 346 | 2 | 10-01 16:22 | 없음 | 미해결, 시간대 창에서만 발생 |
| `sql/_27_banana_qa/.../_10_new_time.sql` | sql | 0 / 346 | 0 | (로컬 2026-09-27) | 없음 | 미해결, 다음 창은 2027-09-26 |
| `shell/_06_issues/_15_1h/bug_bts_5435` | shell | 0 / 410 | 0 | (CircleCI 2026-08-26) | 없음 | **2026-08-28 해결** (`e01a78bfc`) |
| `sql/_35_fig_cake/cbrd_25382/cbrd_25382_1` 외 DDL 케이스 | sql | 18 / 346 | 14 | 10-01 17:33 | 없음 | 엔진 결함, 수정 PR 8034 미머지 |

## 케이스별 상세

### 1. `shell/_06_issues/_17_1h/cbrd_20759/hide_cubrid_replay`

- **근거:** 최근 410개 shell run 중 72회, 42개 PR에서 실패했다. PR 8034 run 36834387518(10-01)에서는 판정 6·7만 NOK였고, 결과에 가려진 비밀번호 줄 `******`가 없었다(diff `1d0 < ******`). 재실행 36881333228에서는 통과했다. 9/21 PR 7866 run에서는 판정 8이 같은 이유로 떨어졌다.
- **이유:** 케이스가 백그라운드에서 `ps -f -u $USER | grep cubrid_replay`를 무한 루프로 찍어 `cubrid_replay` 프로세스의 인자 줄을 잡아야 한다. 프로세스가 짧게 끝나면 한 번도 못 잡아 기대 줄이 비고, 노드가 바쁘면 반대로 줄이 하나 더 잡힌다. upstream readme는 "a busy ps loop with uniq assumes a quiet node"라고 적었다.
- **해결:** 2026-09-30에 `_25_unstable`로 격리됐고 스크립트는 고치지 않았다. 오늘 09:44 KST에 PR 8046에서 다시 실패했는데, tc/pr-8046에는 격리 커밋이 없다.

### 2. `shell/_06_issues/_15_1h/bug_bts_15156`

- **근거:** 37회, 25개 PR. PR 8022의 `ca907aaed`·`c997c02d5` run(36791529439)을 포함한다.
- **이유:** `cub_master`를 죽인 뒤 `top -b`로 5초 동안 찍어, 한 번이라도 `cub_server` CPU가 18%를 넘으면 실패로 본다. 병렬 shard가 도는 노드에서는 다른 부하 때문에 쉽게 넘는다.
- **해결:** 2026-09-30 격리.

### 3. `shell/_06_issues/_18_1h/bug_bts_14305`

- **근거:** 18회, 11개 PR(#7987, #8022 등).
- **이유:** 백그라운드 csql이 `select N;` 20만 개를 실행하는 중에 `kill 1`을 하는데, 그 csql이 트랜잭션 1번이라고 가정한다. 다른 접속이 1번을 먼저 받으면 엉뚱한 트랜잭션을 죽인다.
- **해결:** 2026-09-30 격리.

### 4. `shell/_06_issues/_11_2h/bug_bts_6199`

- **근거:** 9회, 8개 PR(#8001, #8021, #7968, #8034 등). PR 8034 run 36834387518의 trace에는 `bug_bts_6199.sh: line 65: [: -gt: unary operator expected`가 찍혔고 판정 2·3이 NOK였다.
- **이유:** 자바 클라이언트를 띄운 뒤 `cubrid broker status -f`를 1초 간격으로 10번 찍어 BUSY를 기다린다. 한 번도 BUSY를 못 보면 `connect_02`가 빈 값이 되어 `[ -gt 0 ]` 비교 자체가 깨진다.
- **해결:** 2026-09-30 격리.

### 5. `shell/_06_issues/_15_1h/bug_bts_15489`

- **근거:** 8회, 7개 PR(#8002, #8025, #8026, #8022 등).
- **이유:** vacuum을 60초 기다린 뒤 `show index capacity`의 `Num_total_page`가 100 미만이어야 하는데, 부하에 따라 107 같은 값이 나온다. 고정 sleep에 기댄 판정이다.
- **해결:** 2026-09-30 격리.

### 6. `shell/_39_fig_cake/cbrd_23768` (이번 세션에서 확인)

- **근거:** 2회 모두 10-01에 나왔다. 하나는 PR 8063(develop `30043f492`, 이 변경 없음)이고 Active process 3개였다. 다른 하나는 PR 8034 run 36834387518이고 1개였다. 둘 다 Test 1.2 NOK이고, 재실행에서는 통과했다.
- **이유:** 세션 1이 `for update` 행 잠금을 잡은 채 30초 sleep하는 동안 세션 2의 csql 3개를 띄운다. 겹치지 않는 행만 잠그므로 즉시 끝나야 정상이고, 판정은 `sleep 1` 뒤 그 pid들이 사라졌는지로 한다. 바쁜 노드에서는 csql 시작에만 1초를 넘길 수 있다. 또 pid를 `ps -ef | grep -E "<pid>|..."`로 찾아서, 숫자가 다른 줄(시각, 다른 pid)에 들어 있어도 걸린다.
- **해결:** 없다. 이 케이스는 lock 경합을 다루는데, PR 8034의 lock 대기 값 변경은 override 창 밖의 요청을 바꾸지 않는다. 그래서 엔진 결함 신호로 보지 않았다.

### 7. `shell/_36_damson/cbrd_23608_tde/temp_enc_06`

- **근거:** 9회, 7개 PR.
- **이유 (두 판단이 있음):**
  - 메모리 기록(PR 8022 run 36734211415): `<db>_latest.err`에서 TDE 줄 두 개를 찾는데, 서버 시작 두 번이 분 경계를 넘어 줄이 `…_0040.err`와 `…_0041.err` 두 파일로 나뉘었다.
  - upstream `a72b396e6` 커밋 메시지: open 상태의 TC PR이 엔진 PR에 맞춰 재기준선 중인 케이스라 flaky가 아니라며 격리 대상에서 다시 뺐다.
  - 둘 다 맞을 수 있다(분 경계 오판 + 특정 PR의 기대값 변경). 실패 run별로 원인을 다시 읽어야 가를 수 있다.
- **해결:** 없다.

### 8. `sql/_27_banana_qa/issue_5765_timezone_support/_08_current_date_function/_02_functions/cases/_02_addmonths.sql` (이번 세션에서 확인)

- **근거:**
  - PR 8034 로컬 게이트(10-01 07:52 UTC): 판정 #10~#15 여섯 줄이 `nok, 0, 1, <now>`였다. 08:00 UTC에 디렉터리를 다시 돌리니 26/26 OK였다.
  - CI: 10-01 16:07·16:22 KST(07:07·07:22 UTC)에 다른 PR 2개에서 실패했다. 모두 같은 창 안이다.
- **이유:** Chicago와 LA 시간대에서 각각 "지금 +1개월"의 월을 비교하는데, 기대값을 "Chicago 시각 +1개월이 그 달 1일 2:00 이전인가"로 계산한다.
  - Chicago 10/1 02:52 CDT에 +1개월 하면 11/1이 되고, 이날은 미국 DST 종료일이다.
  - TIMESTAMP 계열(`current_timestamp`, `localtimestamp`, `localtime`) 6건만 01:52 CST로 보여 기대값이 1이 되는데, 실제 월 차이는 0이다.
  - 그래서 DST 전환 달 직전 달 1일의 Chicago 02:00~03:00(예: 2026-10-01 07:00~08:00 UTC)에만 실패한다.
- **해결:** 없다. 이 시간대에 이 케이스가 실패하면 실행 시각을 확인하고, 창 밖에서 다시 돌리면 된다.

### 9. `sql/.../_02_functions/cases/_10_new_time.sql`

- **근거:** 메모리 기록(#368 C9/C10 게이트, 2026-09-27 13~14 UTC 로컬 실행). develop도 같은 줄에서 실패했다. CI 집계 범위에는 실패가 없는데, 그 창에 CI run이 없었던 것으로 보인다.
- **이유:** Pacific/Chatham이 DST에 들어가는 날(9월 마지막 일요일, 규칙 `Sep lastSun 2:45s`) 13:00~14:00 UTC에 29~30번째 줄의 `new_time(current_datetime(),'Pacific/Chatham',…)`이 Error:-495를 낸다. 근본 오류는 -1166이다.
- **해결:** 없다. 다음 창은 2027-09-26이다.

### 10. `shell/_06_issues/_15_1h/bug_bts_5435` (해결됨)

- **근거:** `docs/ci-flaky-bug_bts_5435.md`(2026-08-26, CircleCI build 149208, PR 7788).
- **이유:** 서버 로그 전체를 `grep -E "\-17|\-48"`로 검사했다. 그런데 매 줄 헤더에 클라이언트 호스트명이 들어가고, CircleCI 컨테이너 호스트명 `...-486f-...`가 이 패턴에 걸렸다.
- **해결:** **2026-08-28** cubrid-testcases-private-ex `e01a78bfc` ([CUBRIDQA-1136] #4000)에서 `grep -E "CODE = -(17|48)," …_[0-9]*.err`로 앵커링했다. 같은 커밋이 다른 3개 케이스도 고쳤다. 이후 gha-ci 집계에 실패가 0건이다.

### 11. 엔진 결함 때문에 간헐적으로 나는 실패 (TC 문제 아님)

- **해당 케이스:**
  - `sql/_35_fig_cake/cbrd_25382/cases/cbrd_25382_1.sql`: 18회, 14개 PR
  - `sql/_35_fig_cake/cbrd_25372/cases/cbrd_25372.sql`: 1회
  - `sql/_35_fig_cake/cbrd_25352/cases/07_javasp_with_view.sql`: 2회
- **이유:** 병렬 워커가 트랜잭션 대기 시간 `tdes->wait_msecs`를 공유하는 데서 생기는 경합이다(CBRD-27486). 세션 값이 -2로 남으면 debug 서버가 page fix 실패 후 오류 없이 assert로 죽는다.
  - 증상: `btree.c:1913`, `catalog_class.c:3614`, `catalog_class.c:3030`
  - 코어에서 `tdes wait_msecs=-2`를 확인했다.
  - PR 8051 shard 09에서 develop `35f528e89`로도 18회 중 2회 재현됐다.
  - 집계된 실패에는 다른 케이스의 abort 뒤에 이어진 연쇄 실패가 섞여 있을 수 있다.
- **해결:** 수정 PR CUBRID/cubrid#8034(TC private-ex#4266, cubrid-testcases#3596)는 미머지 상태다. 10-01 CI는 sql·medium·shell 모두 통과했다(shell 3건은 재실행 후 통과).

## flaky로 보이지만 아닌 것

- **PR이 기대값을 바꾸는 중인 케이스:** `issue_11202_temp_volume_create`(44회), `_03_eventlog_tempvolume`(32회), `cbrd_20149_xasl`(30회), `catcls_general_object`(19회), `file_enc_05/07`, `bug_bts_13242`.
  - upstream `a72b396e6`가 "open TC PR이 엔진 PR에 맞춰 재기준선 중"이라며 격리 대상에서 다시 뺀 목록이다.
  - 대부분 PR 7866(임시 파일 tuple format 변경) 계열이다. issue_11202는 9/30 이후 실패가 없다.
- **엔진과 TC 브랜치의 develop 시차:** `bug_bts_4670`, `cbrd_20953`, `itrack_1002485`, `itrack_1002486`, `cbrd_20149_xasl`, `catcls_general_object`.
  - PR 7866의 9/18·9/21 run에서 tc/pr-7866은 develop을 합쳤는데 엔진 브랜치는 합치지 않아 실패했다.
  - 엔진 쪽도 develop을 합치면 사라진다.
- **배치 순서 의존:** 캠페인 TC `list_aggregate_probes`가 세션 변수 7개를 남겼다(#357, 2026-09-26). 같은 shard에서 뒤에 돈 `json_functions_with_host_variable_2`가 -1071/-1070으로 실패했다. 케이스 끝에 `deallocate variable`을 넣어 해결했다.
- **실제 결함 (MERGE 병렬 정렬 hang):** `_06_merge_statement/_20_adhoc_merge_1`은 full suite에서 간헐적으로 hang했다. 서버 재시작으로 임시 파일 캐시가 차가울 때만 걸린다.
  - CBRD-27492로 등록됐고, 수정 PR CUBRID/cubrid#8046은 미머지다.
  - 로컬 ctp-run은 `dirsplit_exclusions.txt`로 이 케이스를 우회하고 있고, #8046이 머지되면 그 항목을 뺀다.

## 부록: 아직 원인을 보지 않은 다발 실패 (15회 이상, PR 10개 이상)

failed.list 집계만 있고 원인은 확인하지 않았다. flaky일 수도 있고 skew나 특정 PR 계열 결함일 수도 있다. 날짜는 UTC 월-일이다.

| 케이스 | 스위트 | 실패 run | PR 수 | 처음 | 마지막 |
|---|---|---|---|---|---|
| `shell/_05_addition/bug_xdbms_sus575/cases/bug_xdbms_sus575.sh` | shell | 34 | 18 | 09-16 | 10-01 |
| `shell/_40_guava/cbrd_26403/cases/cbrd_26403.sh` | shell | 27 | 18 | 09-17 | 10-01 |
| `sql/_05_plcsql/_01_testspec/_05_bug_fix/cases/19_user_cursor_system_view.sql` | sql | 26 | 18 | 09-17 | 10-01 |
| `shell/_32_features_930/issue_12504_show_log_header/_01_show_log_header/_03_absolute_path/_01_self_log/cases/_01_self_log.sh` | shell | 26 | 16 | 09-22 | 10-01 |
| `shell/_32_features_930/issue_12504_show_log_header/_01_show_log_header/_02_relative_path/_01_csql/cases/_01_csql.sh` | shell | 26 | 16 | 09-22 | 10-01 |
| `shell/_32_features_930/issue_12504_show_log_header/_01_show_log_header/_01_basic_log/cases/_01_basic_log.sh` | shell | 26 | 16 | 09-22 | 10-01 |
| `shell/_06_issues/_25_1h/cbrd_25478/cases/cbrd_25478.sh` | shell | 26 | 16 | 09-22 | 10-01 |
| `shell/_06_issues/_17_1h/cbrd_20145_1/cases/cbrd_20145_1.sh` | shell | 26 | 17 | 09-17 | 10-01 |
| `shell/_06_issues/_15_1h/bug_bts_16378/cases/bug_bts_16378.sh` | shell | 26 | 16 | 09-22 | 10-01 |
| `shell/_06_issues/_15_1h/bug_bts_15912/cases/bug_bts_15912.sh` | shell | 26 | 16 | 09-22 | 10-01 |
| `sql/_33_elderberry/cbrd_23844/cbrd_24337/cases/cbrd_24337.sql` | sql | 25 | 15 | 09-22 | 10-01 |
| `sql/_35_fig_cake/cbrd_24044/cbrd_25214/cases/cbrd_25214.sql` | sql | 21 | 15 | 09-17 | 10-01 |
| `sql/_36_guava/cbrd_25447/cases/cbrd_25447.sql` | sql | 20 | 14 | 09-17 | 10-01 |
| `sql/_13_issues/_23_1h/cases/cbrd_24906_2.sql` | sql | 19 | 13 | 09-17 | 10-01 |
| `sql/_13_issues/_23_1h/cases/cbrd_24906_1.sql` | sql | 19 | 13 | 09-17 | 10-01 |
| `shell/_36_damson/cbrd_23608_tde/temp_enc_09/cases/temp_enc_09.sh` | shell | 17 | 12 | 09-17 | 09-30 |
| `shell/_06_issues/_23_1h/cbrd_24781/cases/cbrd_24781.sh` | shell | 17 | 10 | 09-22 | 10-01 |
| `sql/_35_fig_cake/cbrd_24044/cbrd_25089/cases/cbrd_25089.sql` | sql | 16 | 10 | 09-17 | 10-01 |
| `sql/_28_features_930/issue_9024_loose_index_scan/cases/_06_partition.sql` | sql | 16 | 10 | 09-17 | 10-01 |
| `shell/_40_guava/cbrd_25846/cases/cbrd_25846.sh` | shell | 16 | 12 | 09-17 | 10-01 |
| `shell/_06_issues/_19_2h/cbrd_23136/cases/cbrd_23136.sh` | shell | 16 | 12 | 09-23 | 10-01 |
| `shell/_06_issues/_11_2h/bug_bts_5423/cases/bug_bts_5423.sh` | shell | 16 | 12 | 09-17 | 09-30 |
| `sql/_35_fig_cake/cbrd_24044/cbrd_26419/cases/cbrd_26419.sql` | sql | 15 | 10 | 09-17 | 10-01 |
| `shell/_39_fig_cake/cbrd_24044_enhance_optimizer/cbrd_25080/cases/cbrd_25080.sh` | shell | 15 | 10 | 09-17 | 09-30 |
| `shell/_06_issues/_17_1h/cbrd_20149_ddl/cases/cbrd_20149_ddl.sh` | shell | 15 | 10 | 09-16 | 10-01 |

- 오늘(10-02) 실패한 케이스는 위 표의 `hide_cubrid_replay`(PR 8046)와 `shell/_40_guava/cbrd_26403`(PR 7972, 부록) 두 개뿐이다.

## 다시 집계하는 법

```bash
curl -s http://192.168.1.48:30080/runs/ | grep -oE 'href="[0-9]+/"' | grep -oE '[0-9]+' > runs.txt
for s in shell sql medium; do
  xargs -P 24 -I{} sh -c "curl -s -m 5 -f http://192.168.1.48:30080/runs/{}/$s/collect/failed.list -o fl/{}.$s || true" < runs.txt
done
gh run list -R CUBRID/cubrid --workflow gha-ci --limit 1600 --json databaseId,createdAt,displayTitle > runs.json
```

케이스의 실제 diff와 trace는 `runs/<run>/shell/shard/<NN>/artifacts/ctp_log.tgz` 안의 `current_runtime_logs/test_local.log`에 있다.
