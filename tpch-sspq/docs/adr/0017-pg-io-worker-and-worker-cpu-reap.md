# PostgreSQL의 `io worker`는 SUT 밖으로 두되 크기를 기록하고, worker CPU 회수 누수를 브래킷으로 제거한다

Q21 3단계 대칭 프로파일링에서 PostgreSQL 쪽 회계에 **두 개의 새 사실**이 측정으로 나왔다.
둘 다 ADR 0009의 SUT 경계 정의를 바꾸지 않지만, 그 경계를 실제로 집행하는 방법을 바꾼다.

## 사실 1 — `io worker`가 SUT의 5 %만큼 일한다

PostgreSQL 18 이후 `io_method=worker`가 기본이라 shared buffer read의 `preadv()`를 별도
`io worker` 프로세스가 대행한다. Q21은 `shared read` 580,522블록을 내므로 이 경로가 실제로
쓰인다.

| 프로파일 (`perf record -a -C 0-15`, SUT 밖 pid로 분리 집계) | 값 | SUT 대비 |
|---|---|---|
| `io worker 0` + `io worker 1` instructions | **4,880,000,000** (488 샘플) | **+4.99 %** |
| `io worker 0` + `io worker 1` cycles | 2,140,000,000 (214 샘플) | +3.42 % |

이 값은 귀속 검증의 잔차를 정확히 설명한다. `perf stat -a -C 0-15`에서 idle 기준선을 뺀
PG SUT 추정이 **101,676,565,612 instructions**인데 SUT pid 6개 귀속분은
**97,830,000,000 (96.2 %)**이고, 여기에 io worker 4.88 G를 더하면 **102,710,000,000 =
101.0 %**로 닫힌다.

## 사실 2 — worker CPU는 **회수 시점에** postmaster에 가산되어 다음 런으로 누수한다

`/proc/<postmaster>/stat`의 `cutime`/`cstime`은 자식이 **reap될 때** 갱신된다. 질의 직후에
스냅샷을 찍으면 아직 회수되지 않은 parallel worker의 CPU가 **다음 런의 델타**로 넘어간다.

| Q21 런 (같은 세트) | `pg_proc_count_before` | worker CPU | SUT CPU | **CPU/wall** |
|---|---|---|---|---|
| warmup1 | 9 | 21.91 s | 26.13 s | 5.860 |
| run1 | **11** (미회수 worker 2개) | 26.38 s | 30.60 s | **6.862** |
| run2 | 12 | 26.38 s | 30.60 s | **6.860** |
| warmup2 | 9 | 21.81 s | 26.02 s | 5.863 |
| run3 | 10 | 26.16 s | 30.34 s | **6.867** |

**`CPU/wall = 6.86`은 실행 단위 6개로 물리적으로 불가능한 값**이다(상한 6.0). 차이
26.38 − 21.91 = 4.47 s는 worker 1개분 CPU와 일치한다.

## Decision

### 1. `io worker`는 SUT 밖이다 — `broker+CAS` 열과 같은 취급

ADR 0009의 SUT 경계는 "플랜을 실행하는 프로세스" = **backend + parallel workers**다.
`io worker`는 postmaster가 미리 띄운 보조 프로세스이고 플랜을 실행하지 않는다. 따라서
**주 지표에서 빼되 별개 열로 항상 같이 기록한다.**

| 지표 | CUBRID | PostgreSQL |
|---|---|---|
| **SUT CPU / instructions** | `cub_server` | backend + parallel workers |
| **broker+CAS** (클라이언트측 질의 처리 역할) | `csql` 자신 | N/A (backend 내부) |
| **`io worker`** (버퍼 read 대행) | **N/A** (`cub_server` 스레드가 직접 읽는다) | `postgres: io worker N` |

CUBRID에 대응물이 없다는 것이 이 열의 존재 이유다 — ADR 0009가 `broker+CAS`에 대해 세운
논리와 같다. **세 열을 합산한 단일 숫자는 내지 않는다.**

`io_method`는 기본값 `worker`를 **그대로 둔다.** `sync`로 바꾸면 대외 인용 단서가 네 개로
늘어나고, 측정 대상이 "아무도 안 쓰는 PostgreSQL"이 된다(ADR 0014가
`parallel_leader_participation`에 대해 세운 논리와 같다).

### 2. PG SUT 프로세스 집합의 판정 규칙

"런 전에 존재하지 않았던 `postgres` pid"만으로는 부족하다 — 런 중 재기동된 보조
프로세스가 섞인다(Q21 `cycles` 프로파일 실측: 608124/608125/608126이 35/7/1 샘플). 규칙:

> 런 전에 존재하지 않았던 `postgres` pid 중 **샘플 수가 중위값의 10 % 이상**인 것만
> SUT로 센다. 걸러진 pid와 그 샘플 수는 산출물에 적는다.

근거: parallel worker는 같은 계획 조각을 돌므로 샘플 수가 균등하다(Q21 실측
1654/1640/1626/1622/1621/1620). 10 % 문턱은 그 균등성과 잡음 사이에 자릿수 여유가 있다.

### 3. PG CPU 브래킷에는 settle 구간이 필요하다

worker 회수 누수를 제거하려면 브래킷이 회수 시점을 포함해야 한다.

> PG의 SUT CPU는 **N회 연속 실행 + settle(≥2 s)** 을 하나의 브래킷으로 재고 **N으로
> 나눈다.** 그 브래킷의 wall은 settle을 포함하므로 **CPU 산출에만 쓰고 wall 측정에는
> 쓰지 않는다** — wall은 별도 세트에서 질의 구간으로 잰다.

Q21 실측(N=3, settle 2 s): leader 4.193 s + worker 21.723 s = **SUT CPU 25.917 s/런**,
`CPU/wall` = 25.917/4.4457 = **5.830**(6단위의 97.2 %). 누수 제거 전 6.86과 달리 물리적으로
가능한 값이다.

CUBRID에는 이 문제가 없다 — `cub_server`는 단일 프로세스이고 `/proc/<pid>/stat`의
`utime+stime`이 전 스레드를 집계하므로 스레드가 구간 안에서 생성·소멸해도 프로세스 델타가
정확하다(Q21 실측 스레드 잔차 −0.03 / +0.01 / −0.02 s).

## Consequences

* ADR 0014가 만든 "wall 배수 ≈ SUT CPU 배수" 검산이 PG 쪽에서 다시 성립한다. Q21:
  wall 14.319x vs CPU 14.291x = **0.2 % 차**.
* 이전 라운드(Q1 A~D, Q1 단위 파리티)의 PG CPU 수치는 **이 누수를 갖고 있을 수 있다.**
  단 Q1은 warmup·측정 런 사이 간격이 길고 `CPU/wall`이 5.946(6단위 이하)로 나왔으므로
  누수가 관측되지 않았다. **재측정하지 않고, 재인용 시 이 ADR을 참조한다.**
* `io worker` 열이 빈 PG 프로파일 표는 불완전하다. 다만 물리 read가 0인 쿼리(Q1 등)에서는
  값이 0에 가깝다 — 크기를 추정하지 말고 측정해 적는다(ADR 0009의 같은 조항).

## Status

Accepted (2026-07-29). ADR 0009의 SUT 경계 **정의는 불변**이고, 그 경계의 **집행 방법**을
확장한다.
