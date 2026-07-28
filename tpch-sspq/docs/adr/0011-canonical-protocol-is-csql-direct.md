# 정본 접속 경로는 `csql -C` 직결이고, 클라이언트측 플랜 시간을 의무 채증한다

이전 문서들은 CUBRID 접속을 broker/CAS 경유(CCI)로 전제하고 있었다. 실측하면
**측정 경로에 broker도 CAS도 존재하지 않는다**(ADR 0009 §"CAS가 경로에 없는 경우").

```
$ cubrid broker status                        -> ++ cubrid broker is not running.
$ pgrep -a -f 'cub_broker|cub_cas|cub_proxy'  -> (none running)
$ pgrep -a -f 'cub_'                          -> cub_master / cub_server / cub_pl
```

`csql -C`는 `cub_master`를 통해 `cub_server`에 직결한다. CAS는 CCI/JDBC/ODBC
경로에서만 등장한다.

## Decision

### 1. 정본 접속 경로 = `csql -C` 직결

기존 "CUBRID는 broker/CAS 경유(CCI)" 조항은 **대체된다.** PostgreSQL 대응은
`psql`(libpq) 직결이고, 이 조합이 정본이다.

**기존 측정은 전부 유효하다** — 파일럿과 현 기준선(ADR 0010)을 포함해 지금까지의 모든
측정이 이미 `csql -C` 직결로 수행됐다. 즉 이 개정은 문서를 실제와 맞추는 것이고
수치를 무효화하지 않는다.

### 2. 의무 조항 — 쿼리별 클라이언트측 파싱·플랜 생성 시간을 별도 열로 채증

앞으로 모든 측정 표에 이 열을 둔다. **기록만 하지 말고 크기를 잰다.**

이유: CUBRID 옵티마이저는 **클라이언트측**이다
(`src/optimizer/AGENTS.md:3` `Client-side (#if !defined(SERVER_MODE))`, `:55`
`planning done locally`). ADR 0009이 SUT 경계를 "플랜을 실행하는 프로세스"로 정의한
결과, **CUBRID의 파싱·플랜은 SUT 밖, PostgreSQL의 파싱·플랜은 SUT 안**이라는 비대칭이
남는다. 그 비대칭의 크기를 모르면 SUT CPU 비교의 해석 범위를 알 수 없다.

측정 방법(정본):

| 엔진 | 방법 | 근거 |
|---|---|---|
| CUBRID | `SET OPTIMIZATION LEVEL 514` + 질의. `level & 0x02`가 "질의를 실행하지 않는다"(`execute_statement.c:12562-12564`)이므로 파싱+최적화+플랜덤프만 수행된다. 같은 형태의 최소 문장을 기준선으로 빼서 접속·기동 비용을 제거한다. | 실행이 섞이지 않는다 |
| PostgreSQL | `EXPLAIN (SUMMARY ON)`의 `Planning Time` | backend가 보고하는 값 |

Q1 실측치(2026-07-28):

| | CUBRID (클라이언트측) | PostgreSQL (backend 내부) |
|---|---|---|
| 파싱+플랜 | **3.0 ms** (엔진 보고, plan-only 문장) / 프로세스 CPU 한계 델타 ≈ 10 ms 미만(계측 분해능 10 ms) | **0.640 ms** (0.631 / 0.663 / 0.625) |
| wall 대비 | 0.0095 % | 0.0072 % |

Q1에서는 양쪽 다 무의미하게 작다. **그러나 값싼 질의에서는 지배적일 수 있으므로
매번 잰다.** 열이 비어 있는 표는 불완전한 표로 취급한다.

### 3. 표 형식

ADR 0009 형식에 이 열이 추가된다.

| 지표 | CUBRID | PostgreSQL |
|---|---|---|
| wall time (end-to-end) | … | … |
| **SUT CPU** (`cub_server` / backend+workers) | … | … |
| **broker+CAS** (클라이언트측 질의 처리 역할) | … (csql) | **N/A (backend 내부)** |
| **파싱+플랜 생성 시간** | … (클라이언트측) | … (backend 내부, `Planning Time`) |

`SUT CPU`와 `broker+CAS`를 합산한 단일 숫자는 여전히 내지 않는다.

## Consequences

* CCI/JDBC 경로를 측정하려면 별도 게이트를 열어야 하고, 그때는 `broker+CAS` 열이
  실제 `cub_cas` 프로세스를 가리킨다. 지금은 그 역할이 `csql`이다.
* 네트워크 실험(ADR 0005가 연기한 N1~N4)은 이 조항의 영향을 받는다 — 정본이 직결이므로
  broker 경유는 별도 변형으로 다뤄야 한다.

## Status

Accepted (2026-07-28).
