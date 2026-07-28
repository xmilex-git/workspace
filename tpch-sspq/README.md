# TPCH-SSPQ

CUBRID와 PostgreSQL의 **TPC-H single-session parallel query** 동작을 같은 장비·같은 데이터셋 위에서
비교 분석하는 프로젝트다. 다중 사용자 처리량(QphH)이 아니라, **세션 하나가 쿼리 하나를 실행할 때
엔진이 확보하는 병렬성과 그 확장 한계**가 관심 대상이다.

이 폴더는 workspace 저장소의 기존 single-context 규칙에서 **의도적으로 분리된 독립 컨텍스트**다.
프로젝트 문서와 ADR은 모두 이 폴더 안에 둔다(ADR 0001).

## 상태

**환경 세팅 완료 / 측정 미시작.** Grill 종료, 양쪽 엔진 설치와 pin 채증까지 끝났다.

- 인벤토리 조사 완료(2026-07-28, 읽기 전용) → `ENVIRONMENT.md`.
- CUBRID `f30f1c260` release 빌드 설치 완료 — `~/tpch-sspq-install/cubrid-f30f1c260`,
  `cubrid_rel` = `11.5.0 (11.5.0.2374-f30f1c2)`. `~/CUBRID` 심링크 불변.
- PostgreSQL `5713b437a`(20devel) 빌드·설치 완료 — `~/pg/pg20devel-5713b437`,
  `initdb -D ~/pg/pgdata-tpch-sspq` 성공. **서버는 아직 띄우지 않았다.**
- `-g` 무해성 `.text` 검증 통과(ADR 0003).
- 남은 것: **G1(R0 재현)이 다음 행동**이다. 아래 pending 중 게이트 진행을 막는 항목만 그 전에 닫는다.

## 확정 결정

1. **독립 컨텍스트** — 저장소 루트 `CONTEXT.md` / `docs/adr/`에 이 프로젝트 항목을 추가하지 않는다.
   용어는 `tpch-sspq/CONTEXT.md`, 결정은 `tpch-sspq/docs/adr/`에 둔다. (ADR 0001)
2. **PostgreSQL은 개발 스냅샷을 그대로 pin** — `~/dev/postgres` master
   `5713b437abed7085e7d59849c6e9e0f4f469633d` (**20devel**, `git describe` = `REL_19_BETA1-472-g5713b437abe`).
   안정 릴리스가 아니므로, 이 프로젝트의 수치는 **릴리스 PostgreSQL의 성능이라고 인용할 수 없다**. (ADR 0002)
3. **CUBRID는 `f30f1c26003e5aa8e93182648e06cad76fc77064` pin** — clean 워크트리 `~/dev/wt-tpch-sspq`에서
   빌드해 전용 prefix에 설치했다. `~/CUBRID`의 JDBC-direct PoC 빌드는 사용하지 않으며 심링크도
   건드리지 않는다. (ADR 0002)
4. **release 단일 빌드로 절대 성능과 VTune을 함께 측정** — CUBRID `release`(RelWithDebInfo,
   `-O2 -g -DNDEBUG`), PG `--enable-debug`(→ `-g -O2`, cassert off, JIT off). `--enable-debug`가
   `-g`만 추가한다는 것과 `.text` 코드 동일성은 실측으로 확인했다. (ADR 0003)
5. **데이터·쿼리는 기존 자산 재사용** — `~/databases/tpch_sf10_v2`(SF10)와
   `scale10/queries/q1~q22`(CUBRID 정본). TPC-H kit 부재로 dbgen seed·kit 버전은 확정 불가이며
   그 한계를 수용한다. PG 적재·PG판 쿼리 파생은 ADR 0004 시점에는 범위 밖이었고, ADR 0005에서
   **G1 선행 조건으로 승격**됐다. (ADR 0004, 0005)
6. **`perf`/`numactl`은 사용자가 직접 sudo 설치** — 정확한 `dnf` 명령은 `ENVIRONMENT.md` 4절.
7. **실행 전략은 얇은 경로(게이트 기반)** — R1~R8 전체 매트릭스를 순서대로 돌지 않고 G1~G5를
   차례로 통과시키며, 각 게이트의 증거로 다음 게이트의 대상 범위를 좁힌다. multi-seed(R4)와
   POWER-SHAPED는 삭제하고, 전용 C driver와 네트워크 실험(N1~N4)은 연기한다. (ADR 0005)
8. **목표 DOP는 양쪽 6으로 고정** — CUBRID `parallelism=6` ↔ PG `max_parallel_workers_per_gather=6`,
   PG `max_parallel_workers`(및 `max_worker_processes`)는 6 이상을 확보한다. CUBRID 서버 풀
   `max_parallel_workers`는 기본값 100이라 제약이 되지 않는다. DOP sweep 범위는 1~6. (ADR 0005)
9. **단일 쿼리 timeout은 양쪽 300초** — 초과한 쿼리는 값을 대체하거나 보간하지 않고 **별도 상태
   `timeout`으로 기록**하며, 스트림은 다음 쿼리로 계속한다. 하네스 필수 요구사항이다. (ADR 0005)
10. **캐시 레짐은 WARM이 주 레짐** — 측정 세트마다 warmup 스트림 1회를 돌려 집계에서 빼고, AB/BA
    엔진 전환 직후에는 warmup을 재수행한다(CUBRID 46GB + PG ~25GB vs available ~91Gi — 상대 엔진
    런이 page cache를 밀어낼 수 있다). 측정 런의 물리 read 카운터로 warm임을 채증하며 **검증 실패
    런은 무효**다. cold는 주 축이 아니라 **I/O 진단 트랙 전용**이고 warm과 같은 표에 합치지 않는다.
    (ADR 0006)

## 실행 전략(얇은 경로)

전체 매트릭스를 순회하지 않는다. **게이트를 하나 통과할 때마다 그 게이트의 증거로 다음 게이트의
대상 범위를 좁히는 얇은 경로**로 진행한다. 각 게이트는 통과 조건과 산출물이 정해져 있고, 조건을
채우지 못하면 다음 게이트를 열지 않는다. (ADR 0005)

| 게이트 | 하는 일 | 통과 조건 / 산출물 |
|---|---|---|
| **G1** | R0 재현 — 기존 하네스를 그대로 쓰고, 새 pinned 빌드 2개(CUBRID `f30f1c260`, PG `5713b437a`) 위에서 AB/BA interleaved 3회. **세트 시작 전과 엔진 전환 직후마다 warmup 스트림 1회(미집계)** | 양쪽 22개 쿼리 완주(또는 `timeout` 상태 기록), 집계 런 전부 warm 검증 통과, paired 차이의 sd 실측치 확보 |
| **G2** | 절대격차 Pareto + 22개 쿼리 양쪽 plan **병렬 여부 분류표** | **PG-only Parallel subset 식별이 최우선 통과 조건**, 절대격차 상위 목록 확정 |
| **G3** | top5만 DOP 1 vs 목표 DOP(6) 분해 | 쿼리별 병렬 이득/무이득 구분, 필요한 쿼리에만 DOP sweep 1~6 |
| **G4** | top3~5 plan diff + actual rows | **선행 조건: 통계 파리티**(CUBRID 통계 갱신 ↔ PG `ANALYZE`)를 먼저 맞춘 뒤 비교. plan 형상 차이와 추정/실측 행수 괴리를 기록 |
| **G5** | 증거가 가리키는 **한 트랙만** 오픈 — optimizer 트랙 또는 VTune DIAG-PREFIX 트랙 | 증거로 확정된 영역에만 계측 패치. 두 트랙 동시 오픈 금지 |

**원인 후보는 측정 증거에서만 도출한다.** 어떤 연산자·코드 경로·서브시스템도 게이트를 통과하기 전에
병목 후보로 지목하지 않는다. 사전 지목은 G2~G4의 분류와 비교를 편향시키므로 문서·하네스·보고서
어디에도 넣지 않는다.

**환경 대체**: cgroup v2·HugePages·`chrt`(RT 우선순위)가 이 장비에서 불가하므로 `taskset`+`numactl`
바인딩으로 격리하고, CV 3% 절대 기준 대신 **paired AB/BA + 신뢰구간**으로 판정한다. (ADR 0005)

## Pending decisions

- 양측 파라미터 공정 대응 규칙(CUBRID `data_buffer_size`/`sort_buffer_size` ↔ PG `shared_buffers`/`work_mem`).
- 병렬 여부 분류표의 라벨 규칙 — 목표 DOP(6)와 채증 수단(CUBRID `;trace on`의 `parallel workers: N`,
  PG `EXPLAIN (ANALYZE, VERBOSE)`의 Workers Launched)은 확정됐다. 플랜 일부만 병렬인 경우의 라벨과
  `Workers Launched < 목표 DOP`의 처리만 G1 산출물을 보고 정한다.
- 게이트 마진 — 판정 방식은 paired AB/BA + 신뢰구간으로 확정됐고, G2 절대격차 컷 마진 수치만
  G1의 paired sd 실측치로 정한다.
- ~~cold/warm 캐시 레짐 고정 방식~~ → **해결**: WARM 주 레짐 + cold 진단 트랙(ADR 0006). 잔여는
  컨테이너 안에서 `sudo /home/cubrid/bin/drop_caches.sh`가 동작하는지 **1회 실측**뿐이며, cold 트랙을
  여는 시점에 확인한다. warm 검증 문턱(1% / 100MiB)은 G1 실측 분포로 확정한다.
- 측정 격리 — `taskset`+`numactl` 바인딩으로 확정. 핀 집합 크기(목표 DOP 6 기준), 상주 프로세스
  정리 범위, stray `cub_master` 4개 처리만 남았다.
- PG 데이터 적재와 PG판 쿼리 파생 규칙 — G1이 양쪽 22개 쿼리를 요구하므로 **G1의 선행 조건**이며
  다음 스코프의 첫 항목이다.

## 산출물 배치 원칙

- **대용량 결과는 git 밖.** raw 측정치, 생성 데이터, 적재 로그, VTune 결과는
  `.git_ignored_dir/tpch-sspq/`에 두고 이 폴더에는 **결론과 그 근거 포인터만** 커밋한다.
- 스크래치는 `/tmp`·`$TMPDIR` 금지(저장소 house rule). `.git_ignored_dir/` 사용.
- 서버 기동/정지는 예외 없이
  `.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh` 래퍼 경유
  (raw `cubrid server start|stop`은 파이프에서 무한 hang).
