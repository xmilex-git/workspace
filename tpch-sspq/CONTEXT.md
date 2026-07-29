# TPCH-SSPQ

CUBRID vs PostgreSQL TPC-H single-session parallel query 분석에서 쓰는 공통 언어를 정의한다.
저장소 루트 `CONTEXT.md`와 분리된 독립 컨텍스트다(ADR 0001).

## Language

**TPCH-SSPQ**:
TPC-H 워크로드를 쓰되 판정 축을 **세션 하나가 쿼리 하나를 실행할 때 엔진이 확보하는 병렬성**에 두는
비교 분석이다. 동시 세션 수를 늘려 얻는 처리량은 측정 대상이 아니며, 공식 TPC-H 성능 지표를
산출하거나 인용하지 않는다.
_Avoid_: TPC-H 벤치마크, QphH, 처리량 비교

**Query Stream**:
한 세션이 정해진 순서로 실행하는 쿼리 실행 단위이며, 한 번의 실행에서 나온 타이밍·플랜·프로파일이
같은 스트림에 귀속된다. 스트림은 비교의 최소 단위이고, 서로 다른 캐시 레짐이나 설정에서 나온
스트림은 같은 표에 합치지 않는다.
_Avoid_: run, iteration (어느 단위인지 모호)

**Canonical Query Set**:
엔진 방언을 적용하기 전의 기준 쿼리 집합이다. 이 집합만이 "두 엔진에 같은 질의를 던졌다"의 근거이며,
여기서 파생되지 않은 쿼리는 비교에 쓰지 않는다. 파생 시 가한 변형은 전부 기준 집합 대비 diff로 남긴다.
_Avoid_: 원본 쿼리, 표준 쿼리 (어느 쪽이 기준인지 모호)

**Engine Dialect**:
Canonical Query Set을 특정 엔진에서 실행 가능하게 만드는 **최소 변형**과 그 사유의 묶음이다.
날짜 산술 표기나 결과 행 제한처럼 문법이 강제하는 것만 허용하며, 플랜을 바꾸는 재작성
(조인 순서 변경, 서브쿼리 평탄화, 힌트 추가)은 방언이 아니라 별도 실험으로 분리한다.
_Avoid_: 쿼리 튜닝, 최적화 변형

**Comparison Snapshot**:
비교 하나를 재현하는 데 필요한 고정값의 묶음이다. 양측 엔진의 exact SHA와 빌드 플래그, 데이터셋
생성 파라미터, 설정 파일 실측값, 캐시 레짐, 코어 배치가 모두 들어간다. 스냅샷이 불완전한 측정치는
표에 올리지 않는다.
_Avoid_: 실험 환경, 측정 조건 (범위가 불명확)

**Gate**:
얇은 경로의 한 단계이며, **통과 조건과 산출물이 미리 정해진 측정 관문**이다. 앞 게이트의 증거만이
다음 게이트의 대상 범위를 좁히고, 통과 조건을 채우지 못하면 다음 게이트를 열지 않는다. 게이트를
건너뛰거나 여러 게이트를 동시에 여는 진행은 유효한 진행으로 세지 않는다(ADR 0005).
_Avoid_: 단계, 페이즈 (통과 조건 없이 시간 순서만 뜻함)

**SUT Boundary**:
CPU를 계정할 때 "측정 대상"으로 세는 프로세스 집합이며, **플랜을 실행하는 프로세스**로
정의한다. CUBRID는 `cub_server`, PostgreSQL은 backend + parallel workers다. CUBRID의
클라이언트측 질의 처리(파싱·플랜 생성·결과 마샬링 — CCI/JDBC 경로에서는 `cub_cas`,
csql 경로에서는 `csql` 자신)는 **주 지표에서 빼되 `broker+CAS` 열로 항상 같이 기록**한다.
PostgreSQL에는 이에 대응하는 별개 프로세스가 없으므로 그 열은 `N/A (backend 내부)`로
적는다 — 이 비대칭은 제거 대상이 아니라 기록 대상이다. 두 열을 합산한 단일 숫자는
내지 않는다. **wall time에는 적용되지 않는다**: wall time은 계속 end-to-end이며,
worker 합산 CPU를 wall time에서 감산하거나 직접 비교하지 않는다. (ADR 0009)
_Avoid_: 서버 CPU, 엔진 CPU (어느 프로세스까지인지 불명확)

**Within-set sd (런 내 재현성)**:
**하나의 측정 세트 안에서** 같은 구성·같은 서버 인스턴스·연속된 런들의 표준편차다.
엔진 내부 반복 노이즈와 그 순간의 배경 부하만 담는다. ADR 0005의 paired AB/BA +
신뢰구간 판정은 이 축에 적용된다.
_Avoid_: sd, 표준편차 (어느 축인지 불명확)

**Between-session drift (세션 간 드리프트)**:
**서버 재기동·구성 변경·시간 경과를 건너뛴** 두 측정 세트의 평균 차이다. 런 내 요인
전부에 더해 미규명 요인까지 담는다. **런 내 sd를 세션 간 비교의 유의성 문턱으로 쓰지
않는다** — 두 양은 분산원이 다르므로 그 비율은 유의성을 뜻하지 않는다. 세션 간 차이를
판정하려면 세션 간 분산을 그 자체로 표본화해야 한다. (ADR 0010)
_Avoid_: 노이즈, 오차 (원인을 이미 안다는 함의)

**Baseline (기준선)**:
현재 구성에서 확정된 비교 기준값이며, **CUBRID 31.511 s / PostgreSQL 8.908 s /
3.537x**(8테이블 + 히스토그램 활성화)다. 파일럿 값(34.699 / 8.974 / 3.867x)은 폐기하지
않고 이력으로 보존하되, 인용 시 **구성이 다르다**는 단서를 반드시 붙인다. 구성이 바뀌면
그 구성에서 처음 돌리는 측정 라운드가 기준선을 겸하며, 기준선 전용 재측정 라운드는
만들지 않는다. (ADR 0010, 0013)
_Avoid_: 파일럿 값, 초기값 (어느 구성인지 불명확)

**Canonical Protocol (정본 접속 경로)**:
`csql -C` → `cub_server` 직결 ↔ `psql`(libpq) 직결이다. broker/CAS는 측정 경로에
없으며(CCI/JDBC 경로에서만 등장), 그래서 `broker+CAS` 열은 **역할**로 정의된다 —
csql 경로에서는 `csql` 자신이다. 모든 측정 표는 **쿼리별 파싱·플랜 생성 시간**을 별도
열로 채증한다: CUBRID 옵티마이저가 클라이언트측이라 SUT 경계에서 CUBRID 플랜은 SUT
밖, PostgreSQL 플랜은 SUT 안이라는 비대칭이 남기 때문이다. (ADR 0011)
_Avoid_: CCI 경유, broker 경유 (현 정본이 아니다)

**cpuset 정책**:
`cub_server`·PG backend·**클라이언트측 처리(csql/psql)가 모두 node0 `0-15`를 공유**하고
수집기(perf·VTune·모니터링)만 SUT 밖에 둔다. **cpuset은 SUT CPU 회계 경계와 독립된
축이다** — 같은 cpuset에 있다고 회계에 합산되지 않고, 다른 cpuset에 있다고 빠지지도
않는다(회계는 프로세스 단위). 클라이언트를 SUT 코어에 두는 이유는 PostgreSQL이 파싱·
플랜을 SUT 코어에서 하므로 경합 조건을 대칭으로 맞추는 것이다. (ADR 0012)
_Avoid_: SUT 분리, 코어 분리 (회계 경계와 혼동)

**Execution unit (실행 단위)**:
**실제로 튜플을 처리하는 동시 실행 주체의 개수**이며, worker 수와 같지 않다. CUBRID는
**쿼리에 따라** leader가 스캔에 거의 참여하지 않으므로(Q1·Q21의 leader CPU가 SUT CPU의
0.24 %) 그 쿼리들에서는 **실행 단위 = worker 수**다. **단 이것은 쿼리 성질이지 엔진 성질이
아니다** — Q18에서 CUBRID leader는 질의 실행분 CPU의 **28.5 %**(26.8/94.1 s)를 쓰고
**wall의 69.8 %를 혼자 실행한다**(GROUP BY 외부 정렬 병합). 따라서 목표 단위 수는 설정으로
정하되 **실제 단위 수는 항상 이용률로 판정한다**(ADR 0018+0019). PostgreSQL은
worker와 동등하게 참여하므로(leader/worker CPU 비 0.999, `Parallel Seq Scan`의
`loops` = worker 수 + 1) **실행 단위 = worker 수 + 1**이다. 파리티는 worker 수가 아니라
**실행 단위 수**로 맞춘다 — 확정값은 CUBRID `parallelism=6` ↔ PG
`max_parallel_workers_per_gather=5`(+leader) = 양쪽 6단위다.
`parallel_leader_participation`은 기본 `on`을 유지한다(끄면 PG 사용자가 실제로 쓰지 않는
구성이 된다). 플랜의 `parallel workers: N` / `Workers Launched: N`을 파리티 근거로
쓰지 않으며, 모든 표에 **실행 단위 수 행**을 넣는다. (ADR 0014)
_Avoid_: DOP, worker 수, 병렬도 (실행 단위와 다를 수 있다)

**Natural / unit-parity-controlled (2트랙)**:
병렬 지표를 낼 때 **(1) 자연 구성값** — 양쪽을 같은 설정 숫자로 놓은 값(양쪽 "DOP 6",
PG는 실제로 7단위) — 과 **(2) 단위 파리티 통제값** — 양쪽 실행 단위 수를 맞춘 값 — 을
나란히 낸다. **헤드라인 배수는 (2)를 쓴다.** natural-plan / plan-family-controlled
2트랙 규칙과 같은 구조이며, 두 트랙을 섞은 단일 숫자는 내지 않는다. (ADR 0014)
_Avoid_: 배수, 격차 (어느 트랙인지 불명확)

**쿼리 timeout 비대칭 (engine asymmetry, 계약 사실)**:
300초 쿼리 timeout 규칙(ADR 0005)은 **두 엔진에서 같은 방식으로 집행되지 않는다.**
PostgreSQL은 세션 GUC `statement_timeout='300s'`로 **문장을 실제로 취소**하고
스트림은 다음 쿼리로 계속된다(`ERROR: canceling statement due to statement timeout`).
CUBRID에는 **쿼리 단위 timeout 기제가 없다** — `query_timeout` 파라미터가 존재하지
않고, `lock_timeout`은 락 대기 전용이며, broker의 `QUERY_TIMEOUT`은 ADR 0011이 정한
정본 경로(`csql -C` 직결)에 broker가 없으므로 적용되지 않는다. 따라서 CUBRID는
**클라이언트를 외부 `timeout 300`으로 감싸 경계를 건다.** 그 결과 두 가지가 다르다:
(1) PG는 300초에서 잘린 값이고 CUBRID는 클라이언트가 죽은 시점이며 서버 측 질의는
클라이언트 단절을 감지할 때까지 이어질 수 있다, (2) 단일 세션 스트림 안에서는 외부
timeout이 세션 전체를 끊으므로 **CUBRID의 timeout 채증은 쿼리별 개별 호출 패스에서만**
가능하다. timeout에 걸린 쿼리는 어느 엔진에서든 **값 대체·보간 없이** timeout으로
기록하고 Pareto에서 제외한다.
_Avoid_: timeout (어느 엔진의 어느 기제인지 불명확)

**WARM 하위 레짐 (stream / single-query-repeat)**:
ADR 0006의 WARM 판정(물리 read ≈ 0)을 **둘 다 통과하는 두 상태**다. `stream`은 다중 쿼리
스트림을 도는 상태로 상대 쿼리가 대상 쿼리의 워킹셋을 **엔진 버퍼**에서 밀어내고,
`single-query-repeat`은 한 쿼리만 반복해 그 워킹셋이 엔진 버퍼에 상주한다. 물리 read
카운터로는 구분되지 않으므로 **엔진 버퍼 카운터**로 채증한다(PG `shared hit`/`shared read`
분할, CUBRID trace `fetch`/`ioread`). **PG의 민감도는 쿼리 조건부다** — 판정 기준은
워킹셋 크기가 아니라 **버퍼 잔존율이 상태에 따라 움직이는가**다(Q21 12.72x ↔ 14.32x;
**Q8은 같은 `single-query-repeat` 안에서 3.43x ↔ 3.96x**, lineitem 잔존율 43.3 % ↔ 53.3 %,
`hit+read` 1,465,669 완전 동일, 단가 2.62 µs/미스). **움직이지 않으면 무감하다**: Q9 PG는
미스를 −39.9 % 줄여도 wall이 **+2.70 %**였고 워킹셋 조건(lineitem 힙 8.6 GB > 8 GB)은
Q8과 같았다. **Q18 PG도 무감하다** — `hit+read` 2,552,611 완전 동일에 미스 −18.0 %인데 wall은
**+0.68 %**다. 이유는 비용이 shared buffer 미스가 아니라 **임시파일 스필**(temp 6.9 GB read /
9.0 GB written)에 있기 때문이다. **CUBRID는 네 쿼리 모두 무감**하다. 두 하위 레짐의 값을 같은
표에 합치지 않으며, 모든 측정 표에 하위 레짐 필드를 적고 **PG 표에는 `shared hit`/`read` 분할을
같이 적는다**. (ADR 0016)
_Avoid_: WARM (하위 레짐이 불명확), 드리프트 (레짐 차이를 미규명 요인으로 오해)

**프로파일 배수 (이벤트 명기 의무 — 정본 축은 `cycles`)**:
프로파일에서 얻은 CUBRID/PG 비는 **어느 하드웨어 이벤트에서 나온 것인지 반드시 붙인다.**
IPC가 두 엔진에서 다를 수 있으므로 `instructions` 비와 `cycles` 비와 wall 비가 갈린다.

| Q | instructions | cycles | wall | CUBRID IPC | PG IPC | IPC 비 |
|---|---|---|---|---|---|---|
| Q1 | 3.011x | — | 3.070x | 2.339 | 2.357 | 0.992 |
| Q21 | 17.748x | 15.353x | 14.32x | 1.807 | 1.563 | 1.156 |
| Q9 | 4.233x | 3.022x | 2.741x | 1.929 | 1.378 | 1.401 |
| Q8 | 5.796x | 3.734x | 3.960x | 2.132 | 1.374 | 1.552 |
| **Q18** | **0.858x** | **1.159x** | **1.247x** | **1.811** | **2.447** | **0.740** |

**`instructions` 비는 상한도 하한도 아니다.** Q1~Q8에서는 상한이었으나 **Q18에서 0.858x < wall
1.247x로 깨진다** — CUBRID가 명령을 **더 적게** 실행하고도 느리고, IPC 부호가 Q9·Q8과 반대다.
따라서 **비교의 정본 축은 `cycles`이고, 결론 문장과 기여도 서술은 `cycles`로 쓴다**(주 표는
`instructions`를 유지해도 된다). **IPC 비를 표에 항상 넣고 1에서 ±20 % 벗어나면 `instructions`
기반 서술을 금지한다.** 격차가 **음수**인 버킷 표에서는 "기여 %"를 쓰지 않는다(분모 음수).
**cycles에서 버킷 순위가 뒤집히는 지점을 명시한다** — Q9: 버퍼 고정·래치 instr 3위 13.3 %
→ cycles 1위 27.8 %; 집계·해시 기여 부호 +2.2 % → −4.7 %(PG `ExecParallelScanHashBucket` IPC 0.27로
PG cycles의 21.2 %). Q8: 같은 두 역전 재현, 버퍼 고정·래치 instr 5위 8.4 % → cycles 2위 19.8 %.
**Q18: 같은 역전이 세 번째로 재현**(버퍼 고정·래치 instr 3위 7.9 % → **cycles 2위 14.0 %**,
CUBRID IPC **1.03**)되고 **수치 연산(DECIMAL)이 cycles로 재면 1.00x 완전 동률**이 된다
(instr 1.18x). **`cycles:u`가 wall보다 커지는 경우도 있다** — Q8 형상 일치 쌍에서 cycles 4.910x vs
wall 3.964x이고, 차는 이용률 비(1.074x)와 커널 시간 비중 차(PG sys 23.2 % vs CUBRID 11.9 %)로
2 % 내에 닫힌다. (ADR 0019 §2. 규명 `docs/report-q{9,8,18}-gap-20260729.md`)
_Avoid_: 프로파일 배수, 명령 수 배수 (이벤트가 불명확), instructions 상한 (Q18에서 깨졌다)

**격차 축 3분해 (플랜 / 실행 단위 / 행당 실행 비용)**:
한 쿼리의 배수를 **세 축의 곱**으로 가르는 방법이다. **플랜·조인 전략 축**은 같은 엔진 A/B로
잰다 — 질의 재작성이나 힌트로 상대 엔진의 플랜 형상을 강제하고 **형상 일치를 노드별 실제
행수로 채증한 뒤** 같은 엔진의 두 값을 비교한다. **실행 단위 축**은 `CPU/wall ÷ 목표 단위 수`
(ADR 0018)로 잰다. **행당 실행 비용 축**은 형상이 일치한 상태의 엔진 간 비다. 세 축의 곱이
실측 배수와 맞는지 **검산을 반드시 낸다.** 실측 5건 — Q21 `14.319x = 4.436x × 3.228x`
(실행 단위 0.2 %), Q9 `2.6944x = 0.9844x × 2.7371x`(검산 오차 0.00 %, 실행 단위 0.23 %),
Q8 `3.9599x = 0.9990x × 0.9314x × 4.2559x`(검산 오차 0.01 %),
**Q18 `1.2468x = 0.6643x × 1.5409x × 1.2180x`(검산 오차 0.014 %)**.
**플랜 축이 1에 가깝다는 것은 유효한 결과다** — Q9는 0.984x로 CUBRID 플랜이 오히려 유리했고,
역방향(PG에 CUBRID 순서 강제) 0.741x가 그것을 확인했다. Q8은 0.999x인데 역방향이 **1.870x**다 —
**CUBRID 행당 비용이 형상 차이를 압도해 어느 플랜을 골랐는지가 관측되지 않는다.**
**플랜 축이 1보다 작으면 상대 엔진이 자기 플랜으로 잃는다는 뜻이다** — Q18은 **0.664x**이고
사유가 PG 통계에 있다(`pg_stats.n_distinct(l_orderkey)` 397,034 vs 실제 15,000,000 = 37.8x 과소).
그 경우 **정본 플랜 배수와 형상 일치 배수를 같은 줄에 병기한다**(Q18 1.247x ↔ **1.877x**,
집계 서브쿼리 단독 1.958x) — 낮은 배수를 "행당 비용이 근접했다"로 읽지 않는다(ADR 0019 §1).
**실행 단위 축이 항상 닫히는 것은 아니고 주축이 될 수도 있다** — Q8은 **1.129x(격차의 12.9 %)**로
열려 있고 원인은 gather 위 중간 리스트 스캔이 `parallel_scan_page_threshold=2048`에 걸려 직렬로
떨어지는 것이다(wall의 15.1 %가 실행 단위 1). **Q18은 이 축이 처음으로 지배한다(1.541x)** —
**양쪽이 동시에 `단위 붕괴`**(이용률 CUBRID 41.1 % / PG 46.9 %)이고 격차 7.56 s의 **86.3 %가
1단위 구간**에서 난다. CUBRID 원인은 `external_sort.c:5232`의 `hash_eligible` 선반환으로
GROUP BY 외부 정렬이 항상 직렬인 것, PG 원인은 `Gather Merge` 위 `Finalize GroupAggregate`다.
**같은 엔진 A/B가 실패하는 경우도 기록한다** — Q8에서 PG에 CUBRID 형상을 강제하려 할 때
`join_collapse_limit=1`은 조인 트리만 고정하고 outer/inner를 뒤집었고, `enable_hashjoin=off`도
마찬가지였다. `cross join lateral (… offset 0)` 펜스만 성공했으나 그 펜스가 병렬 경로를
죽이므로 **양쪽을 직렬로 놓고** 비교해야 했다. Q18에서는 PG측 A/B가 성공했고
(`enable_hashjoin`+`enable_mergejoin`+**`enable_eager_aggregate`**를 모두 off — 앞 둘만 끄면
lineitem을 두 번 집계하는 다른 형상이 나온다) 노드 6개 실제 행수 일치를 채증했다. 반대로
CUBRID측 `/*+ USE_HASH */`는 **조인 방법 계열만** 일치하고 순서는 달라, 그 값(0.811x)은
"형상 일치"가 아니라 "방법 계열 일치"로만 인용한다.
_Avoid_: 병목, 주 원인 (어느 축인지 불명확)

**`io worker` 열 (PostgreSQL만)**:
PG 18 이후 `io_method=worker` 기본값 때문에 shared buffer read의 `preadv()`를 대행하는
별도 프로세스다. ADR 0009의 SUT 경계("플랜을 실행하는 프로세스")에 따라 **주 지표에서 빼되
별개 열로 기록**한다 — `broker+CAS` 열과 같은 취급이며 **CUBRID에 대응물이 없다**
(`cub_server` 스레드가 직접 읽는다). 실측 — Q21 SUT instructions의 **+4.99 %**, Q9 SUT CPU의
**+6.56 %**(2.953 s/런), **Q8 SUT CPU의 +20.8 %**(3.196 s/런 — 현재 최대),
Q18 SUT CPU의 **+3.4 %**(2.960 s/런 — 절대량은 Q9·Q8과 비슷한데 SUT가 커서 비중이 작다). 세 열을
합산한 단일 숫자는 내지 않는다. (ADR 0017)
_Avoid_: PG SUT CPU (io worker 포함 여부가 불명확)

**행위자별 프로파일 (actor-split profile)**:
프로파일을 **CUBRID는 tid의 comm(`transaction`=leader / `parallel-query`=worker / 배경 스레드),
PG는 pid 역할(leader / parallel worker)**로 갈라 버킷을 다시 내는 것이다. 직렬 구간이 wall의
20 % 이상인 쿼리에서 **필수**다 — 버킷 총량은 단일 스레드 구간의 비용을 감춘다. Q18 실측:
버퍼 고정·래치가 전체 cycles의 14.0 %인데 **CUBRID leader만 보면 23.2 %**이고, TLS/런타임은
전체 3.6 %인데 **worker만 보면 5.2 %, leader는 0.2 %**다. 귀속 검산은 **행위자별
`cycles ÷ CPU-초`로 클럭을 역산**해서 한다(Q18 네 행위자 2.52~2.71 GHz, 명목 2.1 / turbo 3.2).
도구 `q18/scratch/{actors.sh,actor-buckets.sh}`. (ADR 0019 §4)
_Avoid_: 프로파일 버킷 (행위자 구분이 없으면 직렬 비용이 안 보인다)
