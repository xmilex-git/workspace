# SUT CPU 경계는 "플랜을 실행하는 프로세스"다 — broker/CAS는 분리 기록

CPU 계정의 주 비교 단위를 아키텍처적으로 대응하는 쌍으로 바꾼다.

## Decision

| 항목 | CUBRID | PostgreSQL |
|---|---|---|
| **주 지표 (SUT CPU)** | `cub_server` | backend + parallel workers |
| **별개 항목 (항상 같이 기록)** | broker + CAS (`cub_broker`/`cub_cas`), 없으면 그 자리를 대신하는 클라이언트측 질의 처리 프로세스 | **대응물 없음** — 명시적으로 "N/A"로 적는다 |
| 하네스/수집기 (perf, VTune, 모니터링) | SUT와 다른 cpuset | SUT와 다른 cpuset |
| **wall time** | end-to-end 그대로. **이 변경은 CPU 계정에만 적용되며 wall time 정의를 바꾸지 않는다** | 동일 |

유지되는 기존 규칙: **worker 합산 CPU를 wall time에서 감산하거나 wall time과 직접
비교하지 않는다.**

## 이 조항은 신설이다 (대체가 아니다)

지시에는 기존 문구 "cub_server+broker+CAS ↔ backend+workers를 같은 cpuset"이
대체된다고 되어 있으나, **저장소를 실측 검색한 결과 그런 조항은 존재하지 않았다**
(`grep -rn 'Comparison Contract|SUT 경계|SUT boundary|cpuset' tpch-sspq/ CONTEXT.md`
→ 0건). 따라서 이 ADR은 **최초로 SUT 경계를 문서화**하는 것이고, 이전 문서의 어떤
문장도 이 결정과 충돌하지 않는다. 이전 측정이 다른 경계를 전제로 해석된 적도 없다
(§"이전 측정 해석에 대한 영향" 참조).

## 왜 broker/CAS를 주 지표에서 분리하는가

**대응물이 없기 때문이다.** PostgreSQL은 하나의 backend 프로세스가 파싱·플랜
생성·실행·결과 마샬링을 전부 한다. CUBRID는 그 일이 두 프로세스로 쪼개진다 —
**옵티마이저가 클라이언트측이다.**

```
src/optimizer/AGENTS.md:3    Client-side (`#if !defined(SERVER_MODE)`).
src/optimizer/AGENTS.md:55   - Optimizer runs **client-side** — statistics fetched from server, planning done locally
```

`cub_server`+broker+CAS를 한 덩어리로 묶어 backend+workers와 비교하면, 서로 다른
일을 하는 집합을 같은 숫자로 만들어 버린다. 반대로 CAS를 계정에서 **빼면** "파싱과
플랜 생성 비용이 어디로 갔냐"에 답할 수 없다. 그래서 **분리하되 기록은 유지**한다.

## 남는 비대칭 — 제거 불가, 매 보고서에 명시

경계를 이렇게 그으면 **CUBRID의 파싱·플랜 생성은 SUT 밖, PostgreSQL의 파싱·플랜
생성은 SUT 안**이 된다. 이것은 경계 선택의 실수가 아니라 두 엔진의 아키텍처 차이가
드러난 것이며, "backend"의 정의를 바꾸지 않는 한 없앨 수 없다. 따라서:

* 모든 측정 표에 `broker+CAS` 열을 두고, PostgreSQL 쪽은 **`N/A (backend 내부)`**로
  적어 이 비대칭을 표에서 바로 보이게 한다.
* Q1처럼 문장 1개가 6천만 행을 스캔하는 질의에서는 이 항목이 무의미하게 작지만,
  값싼 질의에서는 지배적일 수 있다. 크기를 추정하지 말고 측정해 적는다.

## CAS가 경로에 없는 경우 (현재 하네스가 그렇다)

실측(2026-07-28): 현재 측정 경로에 **broker도 CAS도 존재하지 않는다.**

```
$ pgrep -a -f 'cub_broker|cub_cas|cub_proxy'   -> (none running)
$ cubrid broker status                          -> ++ cubrid broker is not running.
$ pgrep -a -f 'cub_'                            -> cub_master / cub_server / cub_pl
```

`csql -C`는 `cub_master`를 통해 `cub_server`에 **직결**한다. CAS는 CCI/JDBC/ODBC
경로에서만 등장한다. 그러므로:

> `broker+CAS` 열은 **"CUBRID의 클라이언트측 질의 처리를 수행하는 프로세스"**로
> 읽는다. CCI/JDBC 경로에서는 `cub_cas`, csql 경로에서는 **`csql` 자신**이다.
> 프로세스 이름이 아니라 **역할**로 정의한다. 그렇지 않으면 csql 측정에서 이 열이
> 항상 0이 되어 계정의 목적이 사라진다.

## 코어핀 정책 — 판단만, 변경하지 않음

지시대로 판단만 적는다. **아무것도 바꾸지 않았다.**

**계약과 정합적인 것은 "분리"다.** 근거:

1. 주 지표와 별개 항목이 같은 cpuset을 공유하면 두 열이 서로 간섭하므로, 분리
   기록의 의미가 약해진다.
2. SUT cpuset의 정의가 "플랜을 실행하는 프로세스"로 바뀌었으므로, cpuset도 그
   정의에 맞춰 그어야 계약과 표가 일치한다.

**다만 분리가 CUBRID에 유리한 비대칭을 만든다.** PostgreSQL의 파싱·플랜 생성은
backend 안에서 일어나므로 **반드시 SUT cpuset의 코어를 쓴다.** CUBRID의 것을 SUT
밖으로 빼면, 같은 코어 수에서 CUBRID의 SUT는 실행에만 코어를 쓰고 PG의 SUT는
실행+파싱+플랜에 써야 한다.

**실측: 이 규모에서는 무의미하다.** 같은 DOP 6 Q1을 클라이언트 배치만 바꿔 두 번
측정했다.

| 클라이언트 배치 | CUBRID 평균 | PG 평균 |
|---|---|---|
| node0 `0-15` (SUT와 공유, 파일럿과 동일) | 31.511 s | 8.908 s |
| node1 `16-19` (SUT와 분리) | 31.876 s | 8.912 s |
| 차이 | +1.16 % (분리가 오히려 느림) | +0.04 % |

즉 Q1에서는 어느 쪽을 골라도 결론이 바뀌지 않는다. 값싼 질의를 재는 시점에는
달라질 수 있다.

**권고(형님 결정 대기)**: `cub_server`를 SUT cpuset에, 클라이언트측 처리
프로세스(csql 또는 CAS)와 `psql`을 **같은 비-SUT cpuset**에 둔다. 그러면 양쪽에서
"SUT cpuset = 플랜 실행 프로세스"가 되어 계약과 표가 일치한다. 남는 비대칭(PG의
파싱·플랜은 여전히 SUT 안)은 제거 대상이 아니라 **기록 대상**이다.
`cub_master`는 접속 브로커링만 하고 질의를 실행하지 않으므로 어느 쪽이든 무관하다
(현재 `0-31`로 남아 있고, 재기동하지 않았다).

## 이전 측정 해석에 대한 영향

**없다.** 지금까지 산출한 수치는 전부 **wall time**이고, 이 ADR은 wall time 정의를
바꾸지 않는다. CPU 계정은 아직 한 번도 산출하지 않았다(프로파일러 미부착). 구체적으로:

| 산출물 | 영향 |
|---|---|
| Q1 파일럿 (CUBRID 34.699 / PG 8.974) | 영향 없음 — wall time |
| 3단계 Q1 DOP6 재측정 | 영향 없음 — wall time |
| 취소된 DOP 스윕의 부분 DOP1 값 | 영향 없음 — wall time |

앞으로의 프로파일링 산출물부터 이 경계가 적용된다.

## 산출물 표 형식 (강제)

모든 측정 표는 다음 열을 **분리해서** 낸다.

| 지표 | CUBRID | PostgreSQL |
|---|---|---|
| wall time (end-to-end) | … | … |
| **SUT CPU** — `cub_server` / backend+workers | … | … |
| **broker+CAS** — 클라이언트측 질의 처리 | … | **N/A (backend 내부)** |

`SUT CPU`와 `broker+CAS`를 합산한 단일 숫자는 **내지 않는다.**

> **직전 지시의 "A~D 측정"**: 이 대화 맥락에 A~D로 지정된 측정 지시가 없다.
> A~D 지시는 이후 라운드에서 받았고 이 형식으로 산출했다 —
> `docs/report-q1-abcd-counters-round2-20260728.md`.

## Status

Accepted (2026-07-28). **CPU 회계 경계 정의는 유효하다.**

단 이 문서의 **코어핀 "분리" 권고는 기각되어 ADR 0012로 대체됐다** — cpuset은 회계
경계와 **독립된 축**이고, `cub_server`와 클라이언트측 처리는 계속 같은
cpuset(node0 `0-15`)을 공유한다. 여기 실린 "분리가 계약과 정합적"이라는 논지는
ADR 0012 §"이 결정으로 버려지는 반대 근거"에서 반박됐다(회계는 프로세스 단위이므로
cpuset 공유가 열을 간섭시키지 않는다).

`broker+CAS` 열의 정의는 ADR 0011이 확장했다(역할 기준 + 파싱·플랜 시간 열 의무화).
