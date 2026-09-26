# FAST-SA — 게이트 레인 B(카운터)·C(SA 프로브)를 병렬·fsync 없이

위치: `V=/home/cubrid/dev/workspace/tools/fast-gate` (추적 파일). 스냅숏과 검증 증거는 git-ignored scratch인 `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/fast-gate/`에 있다.

| 파일 | 역할 |
|---|---|
| `fast-counters.sh` | 레인 B. JDBC DomainBench(자바 코드 그대로)를 C/S 스택 9개에 나눠 동시에 돌린다 |
| `fast-sa.sh` | 레인 C. `csql -S` 작업을 동시에 돌린다. 작업마다 새 DB를 쓴다 |
| `compare-counter-runs.py` | 카운터 실행 두 개의 동등성 비교(`ms`만 빼고 모든 열) |
| `lane-b-fast-prompt.md`, `lane-c-fast-prompt.md` | 워커에 그대로 넘길 레인 프롬프트(`<LABEL>` 같은 자리표시자만 채우면 된다) |
| `scratch/fast-gate/base/` | bench DB의 reflink 스냅숏(`SNAPSHOT.txt`에 시각). 모든 카운터 스택의 DB lower. 없으면 러너가 다시 뜬다 |
| `scratch/fast-gate/validate-343/` | 아래 동등성 확인의 스크립트(`validate-1.sh`, `validate-2.sh`)와 출력(`validate2/`) |

## 원리

- 스택(또는 작업) 하나가 `unshare -Urmipnf --mount-proc --kill-child` 안에서 돈다. user·mount·IPC·PID·net 네임스페이스가 모두 사적이다.
- install(O·R)은 volatile overlay의 lower로만 쓴다. conf 복사와 로그는 그 스택의 upper에 떨어진다. 그래서 install 사본도, `just conf`도 없고, O·R에는 아무것도 쓰지 않는다.
- DB도 volatile overlay다. `volatile`은 upper로 가는 sync 호출을 전부 생략하므로 fsync가 디스크에 닿지 않는다. 카운터 DB의 lower는 스냅숏이라 공유 `312-330/baseline-runtime/db`는 읽지도 쓰지도 않는다. 스냅숏은 원래 경로(`databases.txt`와 volume info에 적힌 경로) 위에 마운트되므로 경로가 그대로 맞는다.
- 포트(1523, 30000, 33000)와 SysV shm은 스택마다 사적이다. 스택끼리, 그리고 호스트의 다른 서버와 충돌하지 않는다. `CUBRID_TMP`는 네임스페이스 안에서 `/srv`로 bind한다(마스터·PL 소켓 경로 108바이트 제한 대비).
- 네임스페이스 안에서 두 가지를 더 사적으로 붙인다. (1) `/etc/hosts` 사본: 호스트 이름(ilhansong_data3)을 127.0.0.1로 둔다. 서버는 호스트 이름으로 마스터에 TCP 접속하는데, 원래 주소(192.168.6.35)는 netns 안에 없다. (2) `/dev/shm`(tmpfs, 64M 상한): DMRB의 POSIX shm 이름이 `/cubbase_dmrb_<pid>_<n>`인데, PID 네임스페이스마다 pid가 겹쳐 스택끼리 충돌한다. 스크래치가 아니라 CUBRID가 호스트에서도 쓰는 shm 세그먼트 자리다(곧바로 unlink되는 32KB급).
- 워커의 Bash 검사기는 경로에 "git"이 든 명령을 `&`·`wait`·루프와 섞으면 거부한다(`.git_ignored_dir`). 러너는 `bash <스크립트> <인자>` 한 줄로만 부른다.
- 스택이 끝나면(정상 종료든 timeout이든) PID 1이 죽으면서 그 안의 cub_*·JVM이 모두 죽는다. 마운트도 네임스페이스와 함께 사라진다.
- 필요한 것: 비특권 user namespace(`/proc/sys/user/max_user_namespaces` > 0)와 userns 안의 overlay(커널 5.11 이상; 이 호스트는 6.9). 스냅숏은 XFS reflink로 떴다(3.6GB, 0.004초).

## 레인 B — 카운터

```
bash $V/fast-counters.sh <out-dir> <install>
# 예: bash $V/fast-counters.sh $T/counters/t343-c2 $O
```

- 입력: `<out-dir>`은 새 경로여야 한다(있으면 거부). `<install>`은 O를 그대로 넘긴다(읽기만 한다).
- 출력: 기존 하네스와 같은 배치다. `<out-dir>/output/counters-p0.tsv`, `counters-p24.tsv`(+ `.err`), `<out-dir>/logs/provenance.txt`. 그래서 `compare-t343.py <label>`을 그대로 쓴다. 스택별 자료는 `<out-dir>/s/<n>/`(stack.log, bench.tsv/.err, `up-install/log/` = 그 스택의 서버·브로커 로그).
- 동시 실행: 스택 9개(p0 8개 + p24 1개). p0 셀은 #342 게이트(t342-c1)의 셀별 시간으로 나눴다. 가장 긴 셀인 P2-expr(약 1분)이 하한이다.
- 셀 분할 규칙(카운터를 바꾸지 않으려고): 셀은 쪼개지 않는다(한 연결에서 L → H= → H!= 순서, 기존과 같음). SQL 텍스트가 같은 셀(P1-int, P7-scan-0)은 같은 스택에서 기존 순서로 돈다. 이름을 적지 않은 셀은 "나머지" 스택이 모두 가져간다(DomainBench에 셀이 추가돼도 빠지지 않는다).
- `ms` 열은 병렬 부하 때문에 순차 실행과 다르다. 게이트 비교(`compare-t343.py`)는 `ms`를 보지 않는다.
- `FAST_CTR_SHARDS=1`: p0 셀 전체를 스택 하나에서 기존 순서로 돌린다(동등성 확인용).

## 레인 C — SA 프로브

```
bash $V/fast-sa.sh <out-dir> <label> <install> <sql> [<label> <install> <sql> ...]
# 예: bash $V/fast-sa.sh $T/sa/out s2 $O $TC s2r $R $TC s2r $R $T/sa/probe-branch.sql s2r $R $T/sa/probe-branch2.sql
```

- 출력: `<out-dir>/<label>.<sql 이름>.out` / `.err`(run-probe.sh와 같은 이름), `.createdb.log`, `.rc`, `.rel`. 기존 출력은 덮어쓰지 않는다(있으면 거부하니 새 label을 쓴다).
- run-probe.sh와 다른 점: label마다 DB 하나가 아니라 작업마다 새 DB다. 각 파일이 자기가 읽을 것을 직접 만들어야 동등하다(#343 프로브와 CTP 케이스는 그렇다).
- 동시 실행: `FAST_SA_JOBS`(기본 16).

## 정리

- 프로세스·마운트: 따로 할 일이 없다(네임스페이스와 함께 사라진다).
- 디스크: 러너가 DB upper와 overlay work 디렉터리를 지운다. 남는 것은 로그뿐이다. 카운터는 `<out-dir>/s/<n>/up-install/`, SA는 `<out-dir>/.fast-sa/<run>/<n>/up-install/`. 지울 때는 리터럴 경로로 지운다.
- 스냅숏을 새로 떠야 할 때(bench DB 내용이 바뀐 경우): 서버가 bench DB를 열지 않은 때 `scratch/fast-gate/base/`를 치우고 러너를 실행하면 다시 뜬다(`cub_server dpin330bench`가 돌고 있으면 거부한다).

## 동등성 확인 (같은 install, 2026-09-26)

#343 게이트(엔진 be3fc1d88, install b4)의 레인 B·C가 기존 러너로 만든 출력과, 같은 install로 돌린 새 러너 출력을 비교했다. 스크립트와 출력은 `scratch/fast-gate/validate-343/`에 있다(당시 러너는 포크 세션의 worktree에서 돌았다. 이후 이 폴더로 옮기면서 경로 설정만 바꿨다).

- 카운터: `libcubrid.so` sha256이 양쪽 모두 `480899838b97…aae7db`이다(O와 레인 B의 사본 `312-343/install-ctr-c1`).
  - 기존 순차 하네스 `312-343/counters/t343-c1`: 17:23:57Z → 17:30:48Z, **6분 51초**.
  - `fast-counters.sh` 9스택 `validate2/par`: **63초**. 가장 긴 스택은 P2-expr 단독 스택으로 java 54초였다.
  - `compare-counter-runs.py t343-c1 par`: p0 375행, p24 30행이 모두 양쪽에 있고, `ms`를 뺀 모든 열(rows, 카운터 9종)에서 다른 값이 0개다. 결과는 **EQUIVALENT**다.
  - 그래서 1스택 순차 비교(`validate-2.sh`, 진단용)는 돌리지 않았다.
- SA: 6작업(O·R × TC·프로브 2개)이 동시에 **3초**에 끝났다. 레인 C는 run-probe.sh로 4회를 순차 실행해 약 20초가 걸렸다.
  - 레인 C의 `s1.*`·`s1r.*`와 새 러너의 `fvo.*`·`fvr.*`는 경과 시간 `(0.000040 sec)`만 빼면 `.out`·`.err` 모두 **차이 0**이다.
  - optdebug와 release 사이도 차이 0이다.
- install 무변경(START 이후 `find -newermt` 결과 없음), 남은 cub_* 프로세스 0, 호스트에 보이는 overlay 0, 코어 0.

처음 검증에서 발견해 고친 것이 세 가지다. ① netns 안에서 서버가 호스트 이름으로 마스터에 접속하다가 네트워크 없음으로 실패했다. 사적 /etc/hosts로 고쳤다. ② PID 네임스페이스 간 DMRB shm 이름이 충돌했다. 사적 /dev/shm으로 고쳤다. ③ `fast-sa.sh`에 실행 비트가 없었다. `bash "$SELF"`로 재실행하게 바꿨다. 위 결과는 모두 고친 뒤의 것이다.
