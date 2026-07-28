# 파리티는 worker 수가 아니라 실행 단위 수로 맞춘다

"목표 DOP는 양쪽 6으로 고정"(ADR 0005)이라고 정했고 양쪽 플랜에서
`parallel workers: 6` / `Workers Launched: 6`을 채증했으므로 파리티가 맞았다고
봤다. **틀렸다.** A 카운터 측정이 그것을 드러냈다.

| | CUBRID | PostgreSQL |
|---|---|---|
| worker 수 (플랜 채증) | 6 | 6 |
| **leader의 튜플 처리 참여** | **거의 없음** — leader(`transaction`) 스레드 CPU **0.470 s** | **완전 참여** — leader CPU **8.870 s**, worker 평균 **8.88 s** |
| **실제로 튜플을 처리한 동시 주체 수** | **6** | **7** |

즉 같은 "6 worker" 설정이 서로 다른 병렬도를 만들고 있었다. PostgreSQL은
`parallel_leader_participation`이 기본 `on`이라 leader가 worker와 동등하게 스캔에
참여한다.

이 어긋남이 격차 분해의 두 번째 항을 그대로 설명한다.

```
wall 3.555x = SUT CPU 3.035x  ×  (PG 6.940 / CUBRID 5.926 = 1.1711)
병렬 효율은 사실상 같다:  CUBRID 5.926/6 = 98.8 %   PG 6.940/7 = 99.1 %
단위 수 비만 다르다:      7/6 = 1.1667  ->  실측 1.1711의 100.4 %를 설명
```

## Decision

### 1. 새 용어 — 실행 단위 (execution unit)

**실행 단위 = 실제로 튜플을 처리하는 동시 실행 주체의 개수.** worker 수와 같지 않다.

| 엔진 | 실행 단위 | 근거 |
|---|---|---|
| CUBRID | **= worker 수** | leader는 스캔에 거의 참여하지 않는다(leader CPU 0.470 s = 전체 SUT CPU의 0.25 %) |
| PostgreSQL | **= worker 수 + 1** | `parallel_leader_participation` 기본 `on`. leader CPU가 worker 평균과 같고, `Parallel Seq Scan`의 `loops`가 worker 수 + 1이다 |

플랜의 `parallel workers: N` / `Workers Launched: N`을 **파리티 근거로 쓰지 않는다.**
실행 단위 수를 따로 세고, 그 수를 표에 적는다.

### 2. 파리티는 실행 단위로 맞춘다

**확정: CUBRID `parallelism=6` ↔ PostgreSQL `max_parallel_workers_per_gather=5`
(+ leader) = 양쪽 6 실행 단위.**

ADR 0005의 "목표 DOP는 양쪽 6" 조항은 이 정의로 대체된다 — 숫자 6은 그대로지만
그것이 뜻하는 것이 worker 수에서 실행 단위 수로 바뀐다.

### 3. `parallel_leader_participation`은 기본값 `on` 그대로 둔다

끄면 PG의 실행 단위 = worker 수가 되어 파리티가 더 단순해진다. **그 방식은 채택하지
않는다.**

근거: `parallel_leader_participation=off`는 PostgreSQL 사용자가 실제로 쓰지 않는
구성이다. 이 프로젝트는 두 엔진의 **기본 자세에서의 병렬 동작**을 비교하는 것이고
(ADR 0002/0003의 pin posture와 같은 취지), 파리티를 맞추려고 상대 엔진을
비-기본 구성으로 밀어넣으면 측정 대상이 "아무도 안 쓰는 PostgreSQL"이 된다.
대신 **PG는 기본값을 유지하고 worker 수를 하나 줄여** 같은 실행 단위 수를 만든다.
비용은 PG 쪽 worker 수가 5라는 것뿐이고, 이는 사용자가 실제로 설정할 수 있는 값이다.

(참고: CUBRID 히스토그램은 반대로 기본값을 벗어났다 — ADR 0008. 그쪽은 옵티마이저
정보량을 맞추는 것이 목적이었고 단서 문구를 의무화했다. 이번 건은 그런 이탈이
필요하지 않다.)

### 4. 지표는 2트랙 — natural / unit-parity-controlled

기존 natural-plan / plan-family-controlled 2트랙 규칙과 같은 구조다.

| 트랙 | 구성 | 용도 |
|---|---|---|
| **(1) 자연 구성값 (natural)** | 양쪽 "목표 DOP 6" = CUBRID 6단위 / **PG 7단위** | 각 엔진을 같은 설정 숫자로 놓았을 때 실제로 벌어지는 일. 이미 측정됨 |
| **(2) 단위 파리티 통제값 (unit-parity-controlled)** | 양쪽 **6단위** (PG worker 5 + leader) | **헤드라인 배수는 이쪽을 쓴다** |

두 트랙을 같은 표에 나란히 싣고, 어느 트랙 값인지 이름을 붙인다. 트랙을 섞은 단일
숫자는 내지 않는다.

## 실측 확인 (교정 후)

| 지표 | CUBRID (6단위) | PostgreSQL (6단위) | 비 |
|---|---|---|---|
| wall | 31.842 s | 10.442 s | **3.049x** |
| SUT CPU | 189.747 s | 62.090 s | **3.056x** |
| CPU/wall (활용도) | 5.959 (99.3 %) | 5.946 (99.1 %) | — |
| leader CPU | 0.460 s | 10.340 s | — |
| worker 평균/단위 | 31.52 s | 10.350 s | — |

* PG SUT CPU는 자연 구성(62.163 s)에서 **−0.12 %**밖에 안 변했다 — 총 CPU 작업량은
  같고 단위 수만 줄었다.
* PG wall은 8.957 → 10.442 s로 올랐고, 7/6 배 예측치 10.450 s와 **−0.07 %** 일치한다.
* PG leader/worker CPU 비 **0.9990** — worker가 5개일 때도 leader는 worker와 동등하게
  참여한다.
* **wall 비가 SUT CPU 비로 수렴했다**: 3.555x → 3.049x, SUT CPU 비 3.056x와 0.2 % 차.

즉 격차의 두 항 중 하나(단위 수 불일치)는 계약 결함이었고 제거됐다. 남은 것은 SUT CPU
비 하나다. **원인은 여전히 지목하지 않는다**(ADR 0005).

## Consequences

* G1~G5의 모든 측정은 실행 단위 파리티(양쪽 6단위)를 기본으로 하고, 자연 구성값을
  두 번째 트랙으로 함께 낸다.
* DOP sweep을 다시 열면 축은 worker 수가 아니라 **실행 단위 수**여야 한다
  (PG는 단위 N을 worker N−1로 설정).
* 표에 **실행 단위 수 행**을 반드시 넣는다. worker 수만 적은 표는 불완전하다.
* ADR 0010의 기준선(CUBRID 31.511 / PG 8.908 / 3.537x)은 **자연 구성 트랙의 값**으로
  재라벨된다. 단위 파리티 트랙의 헤드라인은 이 ADR의 3.049x다.

## Status

Accepted (2026-07-28). ADR 0005의 "목표 DOP 6" 조항을 대체한다.
