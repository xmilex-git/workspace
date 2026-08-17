# CDC P0 하네스 — `cubrid_log` dump 유틸 + 시나리오

티켓: [#33](https://github.com/xmilex-git/workspace/issues/33) · 근거: `htap-cubrid.md` §21-1, §21-2

`cdclogdump`는 `supplemental_log=1` 서버에 붙어 `cubrid_log_connect_server →
find_lsa → extract` 루프를 돌며 모든 CDC 이벤트를 사람이 읽을 수 있게 출력한다.
시나리오 러너가 시나리오당 하나의 덤프를 `../dumps/`에 남긴다 — 후속 결정 티켓
(full image 판정, position·경계 확정)의 1차 증거.

## 실행 순서 (처음부터)

```bash
# 0) 격리 빌드·설치 — ~/CUBRID 심링크를 건드리지 않음 (INSTALL_PREFIX 사용, D1)
cd ~/dev/cubrid && git worktree add .not_git_tracking/htap-cdc-wt develop
cd <이 tooling repo 루트>
WORKSPACE=$HOME/dev/cubrid/.not_git_tracking/htap-cdc-wt \
  INSTALL_PREFIX=$HOME/htap-cdc/CUBRID-11.5-htapcdc just build release

# 1) 하네스 환경 (이 셸에서만)
# !! 2026-08-17 현재 유효 설치본은 -prv (#47 엔진 패치 빌드, Connect 컨테이너 마운트와 동일).
# !! 구 경로($HOME/htap-cdc/CUBRID-11.5-htapcdc)는 pre-#47 빌드 — #47이 CDC API 구조체
# !! 레이아웃을 바꿔(rec_lsa 등) 서버/클라이언트가 섞이면 SIGSEGV 난다 (#61에서 실증).
# !! 어느 설치본이 유효한지 헷갈리면: readlink /proc/$(pgrep cub_master)/exe
export CUBRID=$HOME/htap-cdc/CUBRID-11.5-htapcdc-prv
# 셸 프로필의 CUBRID_DATABASES를 물려받으면 "Database htapdb is unknown" 으로
# 기동 실패 — 실행 중인 cub_master의 환경과 반드시 일치시킨다 (SSOT #14)
export CUBRID_DATABASES=/home/cubrid/CUBRID/databases
export PATH=$CUBRID/bin:$PATH LD_LIBRARY_PATH=$CUBRID/lib:${LD_LIBRARY_PATH:-}

# 2) DB 생성 + supplemental_log=1 + 서버 기동 (server-control 래퍼 경유)
htap-poc/harness/db_setup.sh htapdb

# 3) dump 유틸 빌드
make -C htap-poc/harness CUBRID=$CUBRID

# 4) 전체 시나리오 실행 + 덤프 수집
htap-poc/harness/run_scenarios.sh htapdb
```

## 시나리오

| 파일 | 내용 |
|---|---|
| `s00_setup.sql` | 스키마 + trigger 생성 — DDL 이벤트로 classoid↔테이블 매핑 확보 |
| `s01_insert_commit.sql` | insert → commit |
| `s02_insert_rollback.sql` | insert → rollback |
| `s03_update_rollback.sql` | update → rollback |
| `s04_multi_update_commit.sql` | 동일 PK 다중 update(price만) → commit — **full image 프로브**, `-a 0/1` 두 번 덤프 |
| `s05_insert_delete_commit.sql` | 동일 txn insert→delete |
| `s06_savepoint_partial_rollback.sql` | savepoint 부분 rollback |
| `s07_trigger_dml.sql` | trigger 유발 DML (TRIGGER_INSERT 여부) |
| `s08_large_txn.sql` | 30,000행 단일 txn (커밋본은 발췌, 전체는 scratch) |
| `s09_crash_recovery.sql` | 미커밋 txn 진행 중 `cub_server` kill -9 → recovery undo — **`run_scenarios.sh`가 아니라 `s09_crash_recovery.sh`로 실행** (세션을 열어둔 채 서버를 죽여야 하므로) |
| `s10_statement_failure.sql` | txn 도중 문장 실패(멀티행 INSERT PK 위반) 후 COMMIT — 실패 문장의 부분 DML이 보상 없이 스트림에 남음(팬텀·오염, ADR 0004 개정 근거, #42) |

## 덤프 읽는 법

- `FIND_LSA` / `EXTRACT ... in_lsa -> out_lsa` — position 의미론 증거. LSA의
  pageid/offset 분해는 비트필드 레이아웃 **추정**(low48/high16)이며 라벨에 `?`를 붙였다.
- `ITEM ... type=DML` 아래 `changed[i]` / `cond[i]` — full image 판정 증거.
- **컬럼 값 인코딩 주의 (P0 발견, D2)**: 서버의 pack-func code가 클라이언트 API에
  노출되지 않고 길이만 남는다. len=4는 int|float, len=8은 bigint|double로 모호 —
  덤프는 raw hex + 모든 후보 해석을 병기한다. DECIMAL/DATETIME은 문자열 pack으로
  온다(코드 5/7/8). 커넥터는 스키마 없이 값 타입을 복원할 수 없다는 뜻.

## 유틸 옵션

`cdclogdump -d <db> [-H host] [-p 1523] [-u dba] [-w pw] [-t epoch]
[-a 0|1] [-m max_items] [-i idle_rounds] [-T extract_timeout] [-f follow]`
