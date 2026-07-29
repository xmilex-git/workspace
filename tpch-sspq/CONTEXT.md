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
leader가 스캔에 거의 참여하지 않으므로(leader CPU가 SUT CPU의 0.24 %) **실행 단위 =
worker 수**다. PostgreSQL은 `parallel_leader_participation`이 기본 `on`이라 leader가
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
분할, CUBRID trace `fetch`/`ioread`). PostgreSQL은 이 축에 민감하고(Q21 12.72x ↔ 14.32x,
총 버퍼 접근은 1블록 차이로 동일) **CUBRID는 무감**하다. 두 하위 레짐의 값을 같은 표에
합치지 않으며, 모든 측정 표에 하위 레짐 필드를 적는다. (ADR 0016)
_Avoid_: WARM (하위 레짐이 불명확), 드리프트 (레짐 차이를 미규명 요인으로 오해)

**`io worker` 열 (PostgreSQL만)**:
PG 18 이후 `io_method=worker` 기본값 때문에 shared buffer read의 `preadv()`를 대행하는
별도 프로세스다. ADR 0009의 SUT 경계("플랜을 실행하는 프로세스")에 따라 **주 지표에서 빼되
별개 열로 기록**한다 — `broker+CAS` 열과 같은 취급이며 **CUBRID에 대응물이 없다**
(`cub_server` 스레드가 직접 읽는다). Q21 실측 SUT instructions의 **+4.99 %**. 세 열을
합산한 단일 숫자는 내지 않는다. (ADR 0017)
_Avoid_: PG SUT CPU (io worker 포함 여부가 불명확)
