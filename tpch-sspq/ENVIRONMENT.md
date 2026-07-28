# TPCH-SSPQ 실행 환경

측정 재현에 필요한 고정값을 모은다. Comparison Snapshot의 기계 부분이 여기 있고,
캠페인별 설정값은 각 보고서가 따로 기록한다. 조사 시점 2026-07-28.

## 1. 장비

| 항목 | 값 |
|---|---|
| host / user | `ilhansong_data2` / `cubrid` (uid 340001) |
| OS / kernel | Rocky Linux 8.10 / `6.9.4-1.el8.elrepo.x86_64` |
| 격리 | podman 컨테이너 내부(`/proc/self/cgroup` = `libpod_parent/libpod-2dd433b1e760…`), **cgroup v1**(`/sys/fs/cgroup` = tmpfs, `cgroup.controllers` 없음) |
| CPU | Intel Xeon Silver 4216 @2.10GHz(max 3.2GHz), 2 socket × 16 core, L3 22528K |
| 온라인 CPU | 논리 64개 중 **0-31 online / 32-63 offline**, SMT off(`smt/control`=off), thread/core=1 |
| governor | `performance` |
| NUMA | node0 CPU 0-15 / MemTotal 131,650,732 kB, node1 CPU 16-31 / MemTotal 66,050,424 kB — **비대칭** |
| Memory | MemTotal 197,701,156 kB(188Gi), HugePages_Total 0 |
| Swap | 159Gi = `/dev/dm-1` 32G(prio -2) + `/swapfile2` 128G |
| 디스크 | `/home` xfs `/dev/sda1` 3.5T · `/data` xfs `/dev/sdc1` 11T · `/` overlay 3.0T |
| 제약 | `ulimit -r`=0(RT 우선순위 불가), `-e`=0, memlock 8192K, nofile 1048576 |
| 프로파일링 권한 | `perf_event_paranoid=-1`, `kptr_restrict=0` |
| 쓰기 가능 prefix | `~/.local`, `~/bin` — `/usr/local`·`/opt`는 불가 |

**측정 배치 원칙**: CUBRID DB와 PGDATA를 모두 `/home`(sda1)에 둔다. `/data`(sdc1)는 물리 디스크가
달라 I/O 비교가 성립하지 않는다.

## 2. 이번에 설치한 것

### CUBRID (pin `f30f1c26003e5aa8e93182648e06cad76fc77064`)

| 항목 | 값 |
|---|---|
| pin 커밋 | `f30f1c26003e5aa8e93182648e06cad76fc77064` (`origin/develop`, 2026-07-27 16:23:31 +0900, `[APIS-1087] Update cubrid-jdbc submodule (#7501)`) |
| 빌드 워크트리 | `~/dev/wt-tpch-sspq` (detached, `git status` clean — `~/dev/cubrid`는 dirty이므로 분리) |
| 빌드 명령 | `WORKSPACE=~/dev/wt-tpch-sspq INSTALL_PREFIX=~/tpch-sspq-install/cubrid-f30f1c260 JOBS=24 just build release tpch-sspq-f30f1c260` |
| preset / 빌드 타입 | `release` → `CMAKE_BUILD_TYPE=RelWithDebInfo`, `CMAKE_C_FLAGS_RELWITHDEBINFO=-O2 -g -DNDEBUG` |
| 컴파일러 | `/usr/lib64/ccache/cc` (GCC 8.5.0) |
| install prefix | `~/tpch-sspq-install/cubrid-f30f1c260` (714M) |
| 채증 | `bin/cubrid_rel` → `CUBRID 11.5.0 (11.5.0.2374-f30f1c2) (64bit release build for Linux) (Jul 28 2026 13:24:29)` |
| 불가침 확인 | `~/CUBRID` → `jdbc-direct-poc-release/CUBRID-jdbc-direct-v3-r1` (변경 없음) |

### PostgreSQL (pin `5713b437abed7085e7d59849c6e9e0f4f469633d`)

| 항목 | 값 |
|---|---|
| pin 커밋 | `5713b437abed7085e7d59849c6e9e0f4f469633d` (`~/dev/postgres` master, `git describe` = `REL_19_BETA1-472-g5713b437abe`, **20devel**) |
| 소스 | `~/dev/postgres` — checkout 변경 없음, out-of-tree 빌드 |
| 빌드 디렉터리 | `~/pg/build-5713b437` (337M) |
| configure | `--prefix=$HOME/pg/pg20devel-5713b437 --enable-debug --without-icu --without-readline --with-zlib --with-zstd --without-llvm --without-lz4 --without-libxml` |
| 결과 CFLAGS | `-Wall … -fno-strict-aliasing -fwrapv -fexcess-precision=standard … -g -O2 -Wstrict-prototypes -Wold-style-definition` |
| assertions | `pg_config.h`: `/* #undef USE_ASSERT_CHECKING */` (cassert off) |
| 링크 | `LIBS = -lzstd -lz -lpthread -lrt -ldl -lm`, `USE_ZSTD 1`, `HAVE_LIBZ 1` |
| install prefix | `~/pg/pg20devel-5713b437` (116M), `make install`(strip 아님) |
| 채증 | `pg_config --version` → `PostgreSQL 20devel` / `postgres --version` → `postgres (PostgreSQL) 20devel` |
| 클러스터 | `initdb -D ~/pg/pgdata-tpch-sspq -E UTF8 --locale=C` 성공(43M). **서버 미기동**(`pgrep postgres` 없음) |

## 3. 기존 자산 (설치하지 않음, 참조만)

| 자산 | 경로 | 상태 |
|---|---|---|
| CUBRID 소스 | `~/dev/cubrid` (develop, dirty 12) | 빌드에는 미사용 |
| CUBRID 기존 install | `~/release`(111), `~/optdebug`(5), `~/debug`(22), `~/jdbc-direct-poc-release`(3) | 불가침 |
| TPC-H 데이터/쿼리 | `~/dev/cubrid/.vscode/TPC-H/scale10/{load_data(12G, SF=10), queries/q1~q22, create_tpch_{table,index}.sql}` | CUBRID 정본(ADR 0004) |
| TPC-H DB | `~/databases/tpch_sf10_v2` 55G (`scale_factor.txt`=10), `CUBRID_DATABASES=~/databases` | 재사용 |
| VTune | `/opt/intel/oneapi/vtune/2025.0/bin64/vtune` = **2025.0.1 (build 629235)** | `source /opt/intel/oneapi/setvars.sh` 필요 |
| VTune 드라이버 | `sep5`·`socperf3`·`pax` 로드, `/dev/sep*` 존재 → root 없이 HW 이벤트 샘플링 가능 | present |
| 서버 제어 래퍼 | `.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh` | raw `cubrid server start\|stop` 금지 |
| 도구 | cmake 3.26.5 · ninja 1.8.2 · ccache 3.7.7 · gcc 8.5.0 / gcc-toolset-14 14.2.1 · clang 20.1.8 · sysstat 11.7.3 · gdb 8.2 · valgrind 3.22.0 · jq 1.6 · just 1.52.0 | present |

## 4. 사용자가 직접 실행할 sudo 설치 (에이전트 미실행)

`perf`와 `numactl`은 전역 설치가 필요하고 `/usr/local`·`/opt` 쓰기 권한이 없어 홈 우회가 불가하다.

```bash
sudo dnf install -y numactl numactl-libs numactl-devel
sudo dnf install -y perf
```

- `numactl` — NUMA 바인딩(`numactl --cpunodebind/--membind`)과 `numastat`. 노드 메모리가 비대칭이라
  배치 실험에 필요하다. `numactl-devel`은 하네스가 libnuma에 링크할 경우에만 필요하다.
- `perf` — el8 패키지는 배포 커널 기준이고 이 장비는 elrepo `6.9.4`다. 설치 후
  `perf stat true`가 동작하는지 먼저 확인한다. 실패해도 **VTune이 이미 sep 드라이버로 동작하므로
  프로파일링 자체는 막히지 않는다**.
- 선택(현재 불필요): `readline-devel`(psql 줄편집), `libicu-devel`(ICU 로케일).
  둘 다 지금 configure에서 명시적으로 off 처리했다.

설치 후 확인:

```bash
numactl --hardware && numastat -m | head -20
perf --version && perf stat -e cycles true
```

## 5. 남은 pending

- TPC-H kit 미확보 — `dbgen`/`qgen` SHA-256과 spec/kit 버전은 **여전히 확정 불가**(ADR 0004에서 한계 수용).
- PG 데이터 적재와 PG용 스키마·쿼리 파생 — 얇은 경로 G1이 양쪽 22개 쿼리를 요구하므로 **G1의 선행 조건**이다.
- 양측 파라미터 공정 대응 규칙(`data_buffer_size`/`sort_buffer_size` ↔ `shared_buffers`/`work_mem`).
- cold/warm 캐시 레짐 고정 방식.
- 측정 격리 — cgroup v2·`chrt`(RT 우선순위)·HugePages가 불가하므로 `taskset`+`numactl` 바인딩으로
  대체 확정(ADR 0005). 남은 것은 핀 집합 크기(목표 DOP 6 기준)와 상주 프로세스 정리 범위이며,
  `numactl` 바인딩은 4절 sudo 설치가 선행 조건이다.
- 게이트 마진 — 판정은 paired AB/BA + 신뢰구간으로 확정(ADR 0005). G2 절대격차 컷 마진 수치만
  G1의 paired sd 실측치로 정한다.
- 병렬 여부 분류표 라벨 규칙 — 목표 DOP 6과 채증 수단은 확정. 플랜 일부만 병렬인 경우의 라벨과
  `Workers Launched < 목표 DOP` 처리만 미정.
- stray `cub_master` 4개 정리 여부 — 측정 시작 전에 판단한다.
