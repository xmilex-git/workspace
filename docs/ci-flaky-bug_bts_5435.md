# CI 실패 분석 — `bug_bts_5435.sh` (test_shell)

- **대상 잡**: [CircleCI build 149208 / `test_shell`](https://app.circleci.com/pipelines/github/CUBRID/cubrid/35560/workflows/1e914d45-9fdf-43f3-a650-9b13d7663664/jobs/149208/tests)
- **PR**: CUBRID/cubrid#7788 — *Allow PARALLEL_ENABLE on PL/CSQL functions* (`aad9491`)
- **결론**: **PR 코드와 무관한 환경 의존성 플래키 실패.** 테스트 판정 로직의 오탐(false positive).
- **분석일**: 2026-08-26

---

## 1. 실패 범위

| 항목 | 값 |
|---|---|
| 워크플로 | `build_test` |
| 잡 | `test_shell` (parallelism 50) |
| 실패 노드 | **node 10 단독** (exit 1), 나머지 49 노드 전부 성공 |
| 실패 스텝 | `Run tests` |
| 테스트 총 개수 | 3262 |
| 실패 테스트 | **1건** |

실패 테스트:

```
cubrid-testcases-private-ex/shell/_06_issues/_15_1h/bug_bts_5435/cases/bug_bts_5435.sh
```

빌드 / 체크아웃 / 테스트 스플릿 / GlusterFS 마운트 등 다른 모든 스텝은 정상.
서버 크래시·코어덤프 없음.

---

## 2. 무엇이 문제인가

### 2.1 테스트의 판정 로직

`bug_bts_5435.sh`는 FBO(iBATIS/Spring 기반) 동시성 부하 시나리오를 20 클라이언트로 60초 돌린 뒤,
서버 로그에 특정 에러코드가 남았는지로 OK/NOK를 판정한다.

```sh
./fbo_reset_debug.sh
./run.sh A &

sleep 60
java_pid=`ps -u $USER -f | grep -v grep | grep "PerfMain" | awk '{print $2}'`
kill -9 $java_pid

cd ..

cnt_err=`cat $CUBRID/log/server/*.* | grep -E "\-17|\-48" | wc -l`

if [ $cnt_err -eq 0 ]; then write_ok; else write_nok; fi
```

의도한 검사 대상:

| 코드 | 심볼 | 정의 위치 |
|---|---|---|
| `-17` | `ER_PB_BAD_PAGEID` | `src/base/error_code.h:70` |
| `-48` | `ER_HEAP_UNKNOWN_OBJECT` | `src/base/error_code.h:105` |

문제는 **에러코드 필드를 파싱하지 않고 로그 전체를 생 문자열로 grep** 한다는 점이다.
`\-17` / `\-48`은 로그 어디에 나타나든 매치된다.

### 2.2 서버 로그에는 클라이언트 호스트명이 매 줄 박힌다

`ER_BO_CLIENT_CONNECTED`는 `.err`가 아니라 `.access` 로그로 분기되어 기록된다.

`src/base/error_manager.c:1615`
```c
if (er_Accesslog_filename != NULL && err_id == ER_BO_CLIENT_CONNECTED)
  {
    log_file_name   = er_Accesslog_filename;
    log_file_suffix = ER_ACCESS_LOG_FILE_SUFFIX;
    log_fh          = &er_Accesslog_fh;
  }
```

그리고 SERVER_MODE에서는 **모든 로그 라인의 헤더에 클라이언트 정보가 덧붙는다** — `src/base/error_manager.c:1720`

```c
ret = snprintf (more_info, sizeof (more_info), ", CLIENT = %s:%s(%d), EID = %u",
                host_name ? host_name : "unknown", prog_name ? prog_name : "unknown", pid, er_Eid);
```

실제 `.access` 로그 형태 (로컬 재현):

```
Time: 08/25/26 19:32:45.008 - NOTIFICATION *** file .../boot_sr.c, line 3339  CODE = -972, Tran = 1, CLIENT = <HOST>:csql(3333597), EID = 2
Program 'csql' (pid 3333597) was connected from the host '<HOST>'. (transaction index 1)
```

즉 접속 1건당 **헤더 줄과 본문 줄 양쪽에 호스트명이 들어간다.**
`.err` / `.event` 로그도 동일한 헤더 포맷을 쓰므로, 클라이언트 트랜잭션이 붙은 모든 로그 줄에 호스트명이 실린다.

### 2.3 CircleCI 컨테이너 호스트명이 패턴에 걸린다

이번 실행(node 10)의 호스트명:

```
ccita-71e591b7-486f-59a3-af3c-f243a7441f32-p0p74i
                  ^^^
                  "-48"  →  grep -E "\-17|\-48" 매치
```

결과적으로 **호스트명이 실린 정상 로그 줄 전부가 "에러"로 집계**되었다.

```
+ cnt_err=1020
+ '[' 1020 -eq 0 ']'
+ write_nok
----------------- 1 : NOK
```

### 2.4 실제 서버 에러는 없었다

같은 스크립트가 이어서 수행하는 내부 에러 검사는 0을 반환했다.

```
++ grep 'Internal Error' /home/CUBRID/log/server/fdb_20260826_0538.err /home/CUBRID/log/server/fdb_latest.err
+ internal_err=0
```

`-17`(`ER_PB_BAD_PAGEID`) / `-48`(`ER_HEAP_UNKNOWN_OBJECT`)이 실제로 발생했다는 증거는 로그 어디에도 없다.

---

## 3. 재현된 동일 패턴 (근거)

`flaky-tc-watch` 이력상, **develop 기준 다른 PR의 베이스라인 빌드에서도** 같은 TC가 같은 방식으로 실패했다.

| 빌드 | 날짜 | 브랜치/PR | 호스트명 | 매치 | `cnt_err` |
|---|---|---|---|---|---|
| 149208 | 2026-08-26 | PR #7788 | `ccita-71e591b7-`**`486f`**`-59a3-af3c-f243a7441f32-p0p74i` | `-48` | 1020 |
| 146770 | 2026-08-18 | PR #6853 (무관한 PR) | `ccita-19bd6c98-`**`1776`**`-521b-b924-584350bfdc7f-jesdfl` | `-17` | 966 |

두 건 모두 **호스트명 안에 `-17` 또는 `-48` 문자열이 존재**했다.
서로 다른 PR·서로 다른 날짜·서로 다른 코드 변경에서 동일 원인으로 실패했으므로,
코드 회귀가 아니라 환경 요인임이 확정된다.

### 부수 문제 — 중복 집계

`cat $CUBRID/log/server/*.*`는 실제 로그 파일과 `*_latest.*` **심볼릭 링크를 둘 다** 읽는다.
실패 로그에 찍힌 `cat` 인자가 그 증거다.

```
cat .../fdb_20260826_0538.access .../fdb_20260826_0538.err .../fdb_20260826_0538.event \
    .../fdb_latest.access        .../fdb_latest.err        .../fdb_latest.event
```

`er_file_create_link_to_current_log_file()` (`error_manager.c`)가 `<db>_latest<suffix>` 심볼릭 링크를
현재 로그 파일로 걸어두기 때문에, 같은 내용이 정확히 두 번 집계된다
(관측된 `cnt_err` 1020, 966이 모두 짝수인 것이 이를 뒷받침한다).

테스트를 깨뜨리는 원인 자체는 아니지만, 실패 시 숫자가 실제의 두 배로 보여 진단을 흐린다.

### 발생 확률

호스트명은 `ccita-<uuid>-<suffix>` 형태이고, `-17` / `-48`은 하이픈 바로 뒤 2자리에서만 매치된다.
하이픈 경계가 약 6곳이므로 대략 `6 × 2/256 ≈ 4~5%` — **실행마다 수 % 확률로 랜덤 실패**한다.
CI를 계속 돌리면 주기적으로 반드시 재발한다.

---

## 4. PR 관련성 판단

PR #7788은 `jsp_cl.cpp`에서 `PARALLEL_ENABLE` DDL 거부 게이트를 *PL/CSQL × PROCEDURE* 로 좁히고
관련 카탈로그 메시지(-1379)를 조정하는 변경이다.

반면 `bug_bts_5435`는 iBATIS/Spring 기반 FBO 동시성 부하 시나리오로,
**PL/CSQL·저장 프로시저·`PARALLEL_ENABLE`을 전혀 사용하지 않는다.**

→ **인과관계 없음.**

---

## 5. 조치

### 5.1 즉시 (이 PR 기준)

**해당 잡을 재실행하면 통과한다.** 컨테이너 호스트명이 새로 배정되므로 패턴에 걸릴 확률이 다시 수 %로 떨어진다.

### 5.2 근본 수정 (테스트 저장소)

수정 대상: `CUBRID/cubrid-testcases-private-ex`
→ `shell/_06_issues/_15_1h/bug_bts_5435/cases/bug_bts_5435.sh`

```diff
-cnt_err=`cat $CUBRID/log/server/*.* | grep -E "\-17|\-48" | wc -l `
+cnt_err=`find $CUBRID/log/server -maxdepth 1 -type f -name '*.err' -exec cat {} + \
+          | grep -E "CODE = -(17|48)," | wc -l `
```

세 가지 결함을 동시에 제거한다.

1. **대상 축소** — `.access` / `.event`를 제외하고 `.err`만 검사.
   접속 로그(호스트명이 가장 많이 실리는 곳)가 애초에 후보에서 빠진다.
2. **중복 제거** — `find ... -type f`는 심볼릭 링크인 `*_latest.*`를 걸러낸다.
   (주의: `*_*.err` 같은 글롭으로는 `fdb_latest.err`도 매치되므로 중복이 남는다.)
3. **앵커링** — 실제 로그 헤더 포맷인 `CODE = -17,` / `CODE = -48,` 형태로 고정.
   앞뒤 문맥이 고정되므로 `-170`, `-1720`, 호스트명 조각 같은 부분 문자열 오탐이 원천 차단된다.

> **검증 필요**: 수정 후에도 `-17` / `-48`이 실제로 발생하는 상황에서 NOK가 나는지 한 번은 확인해야 한다.
> 검사 자체가 무력화되면 이 TC는 존재 의미가 없다.
> (예: `.err` 로그에 `CODE = -17, Tran = 1, ...` 한 줄을 주입해 판정이 NOK로 뒤집히는지 확인)

### 5.3 확장 점검 (권장)

동일한 "로그 생 문자열 grep" 패턴을 쓰는 다른 TC가 있는지 스캔할 가치가 있다.

```sh
grep -rn 'log/server/\*\.\*' ~/cubrid-testcases-private-ex/shell/ ~/cubrid-testcases/shell/
grep -rn 'grep -E "\\-[0-9]' ~/cubrid-testcases-private-ex/shell/ ~/cubrid-testcases/shell/
```

같은 원인으로 잠재 플래키인 TC가 더 있을 수 있다.

---

## 6. 요약

| | |
|---|---|
| **증상** | `test_shell` node 10에서 `bug_bts_5435.sh` NOK, `cnt_err=1020` |
| **직접 원인** | 테스트가 서버 로그를 `grep -E "\-17\|\-48"` 로 검사하는데, CircleCI 컨테이너 호스트명 `...-486f-...` 이 패턴에 매치 |
| **매개** | `error_manager.c:1720` — SERVER_MODE 로그 헤더에 `CLIENT = <hostname>` 이 매 줄 기록됨 |
| **증폭** | `*_latest.*` 심볼릭 링크를 함께 `cat` 하여 카운트 2배 |
| **PR 영향** | 없음 (FBO 부하 TC, PL/CSQL 미사용) |
| **실제 엔진 에러** | 없음 (`internal_err=0`) |
| **재현성** | 호스트명 UUID 의존, 실행당 약 4~5% |
| **조치** | ① 잡 재실행 ② private-ex TC 판정 grep 수정 (§5.2) |
