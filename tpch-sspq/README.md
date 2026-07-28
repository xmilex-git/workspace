# TPCH-SSPQ

CUBRID와 PostgreSQL의 **TPC-H single-session parallel query** 동작을 같은 장비·같은 데이터셋 위에서
비교 분석하는 프로젝트다. 다중 사용자 처리량(QphH)이 아니라, **세션 하나가 쿼리 하나를 실행할 때
엔진이 확보하는 병렬성과 그 확장 한계**가 관심 대상이다.

이 폴더는 workspace 저장소의 기존 single-context 규칙에서 **의도적으로 분리된 독립 컨텍스트**다.
프로젝트 문서와 ADR은 모두 이 폴더 안에 둔다(ADR 0001).

## 상태

**G1 선행 조건 완료 / G1 미시작.** 양쪽 엔진에 8개 테이블이 모두 적재됐고 q1~q22가 양쪽
방언으로 준비됐다. 측정은 아직 시작하지 않았다.

- 인벤토리 조사 완료(2026-07-28, 읽기 전용) → `ENVIRONMENT.md`.
- CUBRID `f30f1c260` release 빌드 설치 완료 — `~/tpch-sspq-install/cubrid-f30f1c260`,
  `cubrid_rel` = `11.5.0 (11.5.0.2374-f30f1c2)`. `~/CUBRID` 심링크 불변.
- PostgreSQL `5713b437a`(20devel) 빌드·설치 완료 — `~/pg/pg20devel-5713b437`,
  `initdb -D ~/pg/pgdata-tpch-sspq` 성공. **기동 완료**(port 5442), `shared_buffers=8GB`.
- `-g` 무해성 `.text` 검증 통과(ADR 0003).
- **Q1 한정 파일럿 완료(2026-07-28)** → `docs/report-g1-q1-pilot-20260728.md`.
  warm 3회 평균 **CUBRID 34.699 s vs PostgreSQL 8.974 s (3.867x)**, 양쪽 4행 결과 일치,
  양쪽 목표 DOP 6 실제 적용 확인(CUBRID `parallel workers: 6` / PG `Workers Launched: 6`).
- **`tpch_sf10_v2`는 pin 빌드로 열리지 않는다** — CBRD-26956(`a9fca9002`)의 CHAR/VARCHAR
  저장 포맷 revert 때문이다. DB를 은퇴시키고 pin 빌드로 재적재한다. (ADR 0007)
- **G1 자산 완성(2026-07-28)** → `docs/report-g1-assets-20260728.md`. 나머지 7테이블을
  양쪽에 적재(8테이블 행수 3자 일치, 합계 86,586,077), 인덱스는 양쪽 PK 8개만(FK 0),
  통계 양쪽 갱신, q2~q22 PG 방언 파생(11파일 11줄 변경, 22개 전부 `EXPLAIN` 통과).
  자료형 파리티는 `schema/README-type-parity.md`, 쿼리 방언은
  `queries/README-q2-q22-dialect.md`.
- **CUBRID 통계에는 히스토그램·MCV·min/max·null 비율이 없다 (사실, 2026-07-28 채증)** →
  `docs/report-cubrid-statistics-content-20260728.md`. 컬럼당 저장되는 것은 **NDV 하나**뿐이고
  (`src/storage/statistics.h:87-95`), 인덱스당 keys/부분키/pages/leafs/height가 추가된다.
  히스토그램 서브시스템은 이 pin에 **존재하지만**(`src/optimizer/histogram/`, `_db_histogram`,
  CBRD-26202 이후) `update_statistics_update_histogram` 기본값이 `n`이라 2단계
  `UPDATE STATISTICS ... WITH FULLSCAN`은 히스토그램을 **0개** 만들었다(`db_histogram` 0행).
  따라서 2단계의 "통계 파리티"는 **"양쪽 다 stale이 아니다"(freshness)로만** 읽어야 하며
  정보량 동등을 뜻하지 않는다. 히스토그램이 없을 때 `<`/`<=`/`>`/`>=`는 상수
  `DEFAULT_COMP_SELECTIVITY 0.1`, `BETWEEN`은 `DEFAULT_BETWEEN_SELECTIVITY 0.01`을 쓰고
  (`query_planner.c:10624`, `10645`), 등식만 `1/NDV`로 데이터에 반응한다. **G4는 이 비대칭을
  자기 산출물의 전제로 명시해야 한다.**
- **CUBRID 히스토그램 활성화 완료 — 기본값 이탈 (2026-07-28, ADR 0008)** →
  `docs/report-cubrid-histogram-enabled-20260728.md`. 측정 install `cubrid.conf`에
  `update_statistics_update_histogram=yes`를 넣고 래퍼로 재기동, `paramdump`에서
  `[C*]`/`[S*]` 양쪽 `y` 채증. `db_histogram` **0 → 283행**, 8테이블 **61컬럼 전부**
  300버킷·`full scan`. 히스토그램이 실제로 소비된다 — `l_shipdate < date` 추정이
  실제의 **0.232배 → 1.004배**로 교정됐다. **함정**: `UPDATE STATISTICS ... WITH FULLSCAN`
  만으로는 안 된다(`bucket_count=-1`이 기본값 300 대신 **최소 4**로 클램프되고
  `ON ALL CLASSES`가 `WITH FULLSCAN`을 버린다). 테이블별
  `ANALYZE TABLE <t> DROP HISTOGRAM` → `UPDATE HISTOGRAM WITH FULLSCAN`을 쓴다
  (`.git_ignored_dir/g1-assets/scratch/rebuild-hist.sh`, 8테이블 39.7s).
  **그래도 여전히 없는 것**: 물리 correlation, avg_width(소스에 개념 없음), 정확한
  도메인 min/max(최저 버킷이 `(-inf, hi]`로 열림), `attr op attr` 히스토그램 경로
  (`query_planner.c:10523-10525`, 상수 0.1 유지). 버킷 수도 미정렬(CUBRID 300 vs
  PG 100, 의미도 다름 — 정렬 비용 3.2s로 값싸게 가역적).
- **대외 인용 단서 (필수)**: 이 프로젝트의 CUBRID 수치는
  `update_statistics_update_histogram=yes`(기본값 `no`) 구성에서 나온 것이므로
  **기본 설정 CUBRID의 성능이 아니다.** ADR 0002의 PG 단서(개발 스냅샷이므로 릴리스
  PostgreSQL 성능 아님)와 **둘 다** 붙는다. 즉 어느 엔진에 대해서도 "출시 제품의
  성능"으로 인용할 수 없다. (ADR 0008)
- **Q1 DOP6 재측정 — CUBRID 재현 안 됨 (2026-07-28)** →
  `docs/report-q1-dop6-reproduction-20260728.md`. warm 3회 AB/BA 교차:
  **CUBRID 31.511 s (sd 0.301) / PG 8.908 s (sd 0.008) = 3.537x**.
  PG는 파일럿 대비 −0.74 %로 재현됐고, **CUBRID는 −9.19 %(파일럿 sd의 26.6배)로
  재현되지 않았다** — 비율이 3.867x → 3.537x로 내려갔다. 플랜 형상은 양쪽 다 파일럿과
  동일하고 worker도 6/6이며, 바뀐 것은 CUBRID 추정 카디널리티뿐이다
  (`sel 0.1 → 0.9868`, `card 5,998,605 → 59,194,236`, 실제 59,142,609). 4행 결과는
  양쪽 다 파일럿과 바이트 단위 동일, 집계 6런 물리 read 전부 0.0 MiB.
  파일럿 이후 달라진 것은 7테이블 적재·히스토그램 활성화·**서버 코어핀 실제 적용**·
  배경 부하 차이다. **원인은 지목하지 않는다**(ADR 0005).
  DOP 스윕(1/2/3/4)은 취소됐다.
- **Q1 DOP6 A~D 카운터 측정 (2026-07-28)** → `docs/report-q1-abcd-counters-20260728.md`.
  프로파일러 미부착, 카운터만. **CPU 작업량 비 3.035x vs wall 비 3.555x**
  (CUBRID SUT CPU 188.673s / PG 62.163s). **instructions 비 3.021x, IPC는 사실상 동일**
  (2.485 vs 2.520) — 명령 수 자체가 3배다. 평균 병렬 활용도 CUBRID 5.926(워커 6개,
  리더 스레드 0.47s) / PG 6.940(리더 8.87s가 스캔 참여 + 워커 53.29s). 버퍼 fetch
  CUBRID 683,137×16KiB=10,674MiB / PG 1,125,170×8KiB=8,791MiB, 물리 디스크 read 양쪽 0.
  **바이트 1.214x는 전부 컬럼 저장 표현**: CHAR +21.91 B/행, DECIMAL +12.53,
  VARCHAR +7.89, DATE +1.50, INTEGER ±0이고 행 구조 오버헤드는 CUBRID가 10.96 B **작다**.
  8테이블 합계도 1.188x로 lineitem 특유가 아니다. **해석·원인 지목 없음**(ADR 0005).
- 남은 것: **G1(R0 재현)이 다음 행동**이고 선행 조건은 모두 닫혔다. 아래 pending 중
  게이트 진행을 막는 항목만 그 전에 닫는다.

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
5. **쿼리·스키마 정본은 기존 자산 재사용, CUBRID 데이터는 pin 빌드로 재적재** —
   `scale10/queries/q1~q22`와 `create_tpch_{table,index}.sql`이 CUBRID 정본이다.
   TPC-H kit 부재로 dbgen seed·kit 버전은 확정 불가이며 그 한계를 수용한다(ADR 0004).
   반면 `~/databases/tpch_sf10_v2`는 **pin 빌드로 열리지 않아 은퇴**시켰다 — CBRD-26956
   (`a9fca9002`)이 CHAR/VARCHAR on-disk 포맷을 revert했고 그 DB는 revert 이전 빌드
   `4cfc837`이 썼다. 데이터는 `scale10/load_data/*.load`에서 pin 빌드로 다시 적재하며
   전용 `databases.txt`를 쓴다(공용 `~/databases` 불변). PG 적재·PG판 쿼리 파생과 함께
   **G1 선행 조건**이다. (ADR 0004, 0005, 0007)
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
11. **CUBRID 옵티마이저 히스토그램을 활성화한다 — 기본값 이탈** —
    `update_statistics_update_histogram=yes`(출시 기본값 `no`)를 측정 install
    `cubrid.conf`에 넣는다. 목적은 양쪽 옵티마이저의 카디널리티 추정 정보량을 맞춘 뒤
    **실행 엔진 차이를 보는 것**이다. 버킷 수는 각 엔진 기본값(CUBRID 300 /
    PG `default_statistics_target` 100)을 쓰고 정렬하지 않는다. 통계 재구축은
    `UPDATE STATISTICS`가 아니라 테이블별 `ANALYZE TABLE <t> DROP HISTOGRAM` →
    `UPDATE HISTOGRAM WITH FULLSCAN`으로 한다(전자는 버킷을 4로 클램프하고
    `WITH FULLSCAN`을 버린다). **이 구성의 수치는 기본 설정 CUBRID의 성능으로 인용할
    수 없다.** (ADR 0008)
12. **Comparison Contract — SUT CPU 경계는 "플랜을 실행하는 프로세스"** —
    주 지표는 CUBRID `cub_server` ↔ PG backend + parallel workers다. CUBRID의
    클라이언트측 질의 처리(파싱·플랜 생성·결과 마샬링)는 **주 지표에서 빼되
    `broker+CAS` 열로 항상 같이 기록**하며, PG는 그 열이 `N/A (backend 내부)`다
    (CUBRID 옵티마이저는 클라이언트측 — `src/optimizer/AGENTS.md:3,55`). 두 열을
    합산한 단일 숫자는 내지 않는다. 하네스·수집기(perf/VTune/모니터링)는 SUT와 다른
    cpuset. **wall time은 종전대로 end-to-end이고 이 변경의 영향을 받지 않는다** —
    worker 합산 CPU를 wall time에서 감산·직접 비교하지 않는 규칙도 유지된다.
    현재 하네스에는 broker/CAS가 **존재하지 않는다**(`csql -C`는 `cub_server` 직결,
    `cubrid broker status` → not running)이므로 그 열은 `csql` 자신을 뜻한다.
    코어핀 변경은 **미적용, 형님 결정 대기**. (ADR 0009)

## 실행 전략(얇은 경로)

전체 매트릭스를 순회하지 않는다. **게이트를 하나 통과할 때마다 그 게이트의 증거로 다음 게이트의
대상 범위를 좁히는 얇은 경로**로 진행한다. 각 게이트는 통과 조건과 산출물이 정해져 있고, 조건을
채우지 못하면 다음 게이트를 열지 않는다. (ADR 0005)

| 게이트 | 하는 일 | 통과 조건 / 산출물 |
|---|---|---|
| **G1** | R0 재현 — 기존 하네스를 그대로 쓰고, 새 pinned 빌드 2개(CUBRID `f30f1c260`, PG `5713b437a`) 위에서 AB/BA interleaved 3회. **세트 시작 전과 엔진 전환 직후마다 warmup 스트림 1회(미집계)** | 양쪽 22개 쿼리 완주(또는 `timeout` 상태 기록), 집계 런 전부 warm 검증 통과, paired 차이의 sd 실측치 확보 |
| **G2** | 절대격차 Pareto + 22개 쿼리 양쪽 plan **병렬 여부 분류표** | **PG-only Parallel subset 식별이 최우선 통과 조건**, 절대격차 상위 목록 확정 |
| **G3** | top5만 DOP 1 vs 목표 DOP(6) 분해 | 쿼리별 병렬 이득/무이득 구분, 필요한 쿼리에만 DOP sweep 1~6 |
| **G4** | top3~5 plan diff + actual rows | **선행 조건: 통계 파리티** — 충족(2.6단계, ADR 0008). 양쪽 다 히스토그램·MCV·null 비율 보유, 범위 술어 추정이 양쪽 다 데이터에 반응한다. 단 CUBRID에 **여전히 없는 4항목**(물리 correlation, avg_width, 정확한 도메인 min/max, `attr op attr` 히스토그램 경로)과 **버킷 수 미정렬**(300 vs 100)을 산출물에 **전제로 명기**한 뒤 plan 형상 차이와 추정/실측 행수 괴리를 기록 |
| **G5** | 증거가 가리키는 **한 트랙만** 오픈 — optimizer 트랙 또는 VTune DIAG-PREFIX 트랙 | 증거로 확정된 영역에만 계측 패치. 두 트랙 동시 오픈 금지 |

**원인 후보는 측정 증거에서만 도출한다.** 어떤 연산자·코드 경로·서브시스템도 게이트를 통과하기 전에
병목 후보로 지목하지 않는다. 사전 지목은 G2~G4의 분류와 비교를 편향시키므로 문서·하네스·보고서
어디에도 넣지 않는다.

**환경 대체**: cgroup v2·HugePages·`chrt`(RT 우선순위)가 이 장비에서 불가하므로 `taskset`+`numactl`
바인딩으로 격리하고, CV 3% 절대 기준 대신 **paired AB/BA + 신뢰구간**으로 판정한다. (ADR 0005)

## Pending decisions

- ~~CUBRID 히스토그램을 켤지 여부~~ → **해결: (b) 켜고 재실행** (2026-07-28, ADR 0008,
  `docs/report-cubrid-histogram-enabled-20260728.md`). 잔여 판단은 **버킷 수 정렬 여부**
  뿐이다 — CUBRID 300 vs PG 100이고 두 파라미터의 의미 범위가 다르다(PG `default_statistics_target`은
  표본 크기 300×target까지 좌우). 지금은 각 엔진 기본값을 쓰며, 정렬 비용은 실측
  3.2s(8테이블 재구축 39.7s → 36.5s)로 값싸게 가역적이므로 G4 증거를 보고 정한다.
- 양측 파라미터 공정 대응 규칙(CUBRID `data_buffer_size`/`sort_buffer_size` ↔ PG `shared_buffers`/`work_mem`).
  Q1 파일럿은 **잠정으로 buffer 8G ↔ 8GB**를 썼다 — `tpch_sf10_v2`를 운용한 실측값
  (`paramdump`: `data_buffer_size=8.0G`)을 PG `shared_buffers`에 그대로 미러링했다. 규칙 자체는 미확정.
  `sort_buffer_size`/`work_mem`은 기본값이며 Q1에서는 무의미했다(CUBRID `GROUPBY … page: 0, ioread: 0`,
  PG 4행 quicksort 26kB).
- 병렬 여부 분류표의 라벨 규칙 — 목표 DOP(6)와 채증 수단(CUBRID `;trace on`의 `parallel workers: N`,
  PG `EXPLAIN (ANALYZE, VERBOSE)`의 Workers Launched)은 확정됐다. 플랜 일부만 병렬인 경우의 라벨과
  `Workers Launched < 목표 DOP`의 처리만 G1 산출물을 보고 정한다. Q1에서는 양쪽 다 목표 DOP 6을
  그대로 확보해 이 케이스가 발생하지 않았다.
- 게이트 마진 — 판정 방식은 paired AB/BA + 신뢰구간으로 확정됐고, G2 절대격차 컷 마진 수치만
  G1의 paired sd 실측치로 정한다. Q1 파일럿의 sd(CUBRID 0.120s / PG 0.018s)는 **엔진 내부 반복 노이즈**일
  뿐 paired AB/BA sd가 아니므로 마진 근거로 쓰지 않는다.
- ~~cold/warm 캐시 레짐 고정 방식~~ → **해결**: WARM 주 레짐 + cold 진단 트랙(ADR 0006). 잔여는
  컨테이너 안에서 `sudo /home/cubrid/bin/drop_caches.sh`가 동작하는지 **1회 실측**뿐이며, cold 트랙을
  여는 시점에 확인한다. warm 검증 문턱(1% / 100MiB)은 G1 실측 분포로 확정한다. Q1 파일럿의 집계 6개
  스트림은 최악값이 11.8MiB(스캔 대상의 0.13%)로 잠정 문턱을 충족했다(표본 6개로는 확정 불가).
- 측정 격리 — `taskset`+`numactl` 바인딩으로 확정. Q1 파일럿에서 `taskset -c 0-15`(node0 16코어)가
  PG 7개 프로세스·CUBRID 7개 스레드를 worker 부족 없이 수용했다. stray `cub_master`는 **0개**였고
  `ENVIRONMENT.md`의 4개는 stale이다. 상주 프로세스 정리 범위만 남았다.
- ~~PG 데이터 적재와 PG판 쿼리 파생 규칙~~ → **해결**(2026-07-28,
  `docs/report-g1-assets-20260728.md`). 양쪽 8테이블 적재 완료, q1~q22 양쪽 방언 확보.
  잔여로 넘어간 것은 **Q14/Q17/Q22의 결과 비교 시 십진 스케일 정규화**뿐이다 —
  CUBRID의 나눗셈/`AVG`이 PG `numeric`보다 소수 자릿수를 더 많이 남긴다
  (`schema/README-type-parity.md` §3).

## 산출물 배치 원칙

- **대용량 결과는 git 밖.** raw 측정치, 생성 데이터, 적재 로그, VTune 결과는
  `.git_ignored_dir/tpch-sspq/`에 두고 이 폴더에는 **결론과 그 근거 포인터만** 커밋한다.
- 스크래치는 `/tmp`·`$TMPDIR` 금지(저장소 house rule). `.git_ignored_dir/` 사용.
- 서버 기동/정지는 예외 없이
  `.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh` 래퍼 경유
  (raw `cubrid server start|stop`은 파이프에서 무한 hang).
