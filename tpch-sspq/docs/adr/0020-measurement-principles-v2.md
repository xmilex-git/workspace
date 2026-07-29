# 측정 원칙 v2 — 연결 모드·계약 리비전·configured-cap parity·censoring 분리

사용자 지시(2026-07-29, Q3 3단계 진행 중 하달)로 여덟 개 원칙을 채택한다. 이 ADR은 각 원칙의
**적용 방식**을 확정하고, 기존 결과를 **삭제 없이 재분류**하는 규칙을 정한다.
이 ADR 이후 모든 보고서는 `contract_revision: 2`를 명시한다.

## Contract revision

| rev | 범위 | 상태 |
|---|---|---|
| **rev 1** | ADR 0001~0019까지의 측정 계약. `G2` 명칭, "6 실행 단위 파리티" 표현, 연결 모드 미기록, censoring 미분리 | **과거 결과의 실행 계약** — 폐기하지 않고 이력으로 보존(ADR 0010) |
| **rev 2** | 이 ADR. 아래 8개 원칙 | **현행**. Q3 보고서부터 적용 |

rev 1에서 나온 수치는 **재측정하지 않는다.** 재분류·재명명·라벨 강등만 한다. rev 1 실행 결과를
rev 2 용어로 다시 쓸 때는 `실행 계약 rev 1 / 기술 rev 2`를 명기한다(Q3의 metadata가 그 예다).

---

## 1. `G2`는 단일 세션이 아니다 → `PER_QUERY_CONNECTION_DIAG`로 재명명

`.git_ignored_dir/g2-stream/scratch/run-g2.sh`는 쿼리마다 `csql`/`psql` 프로세스를 새로 띄운다.
따라서 그 결과는 **쿼리당 새 연결**이며 "한 세션이 22쿼리를 순서대로 돈다"는 서술은 부정확하다.
버퍼 레짐(ADR 0016 `stream`)은 여전히 유효하다 — 엔진 버퍼는 연결과 무관하게 공유되기 때문이다.

* 트랙 명칭을 **`PER_QUERY_CONNECTION_DIAG`**로 바꾼다. `G2`는 문서에서 별칭으로만 남긴다.
* **단일 connection 결과로 표현하는 것을 금지한다.** "single-session"·"한 세션이"라는 서술을
  이 트랙에 붙이지 않는다.
* **`TRUE_SINGLE_CONNECTION` 트랙을 백로그에 등재만 한다** — 한 연결에서 완주 19개 쿼리를
  순서대로 실행하고 연결 내 상태(플랜 캐시, 세션 통계, `xcache`, PG plan cache/`work_mem` 재사용)
  효과를 분리하는 트랙. **실행은 별도 지시 전까지 하지 않는다.**
* 프로젝트 이름의 `SSPQ`(single-session parallel query)는 **판정 축의 정의**(세션 하나가 쿼리 하나를
  실행할 때 확보하는 병렬성)로 유지하되, `PER_QUERY_CONNECTION_DIAG`가 그 정의를 만족하는 근거는
  "각 연결이 쿼리 하나만 실행한다"는 사실이다. 여러 쿼리를 한 연결로 도는 성질은 미측정이다.

## 2. 모든 run에 metadata를 기록한다

하네스 표준: `.git_ignored_dir/q3/scratch/meta.sh` (다음 라운드는 이 스크립트를 복사해 쓴다).
run 디렉터리마다 `meta.json`을 남기고 아래 필드를 전부 채운다.

| 필드 | 예 |
|---|---|
| `contract_revision` | `2` |
| `track` | `SINGLE_QUERY_REPEAT` / `PER_QUERY_CONNECTION_DIAG` / `TRUE_SINGLE_CONNECTION` |
| `connection_mode` | `per-query-connection` / `single-connection-n-statements` |
| `protocol` | CUBRID `csql -C direct (cub_server)` / PG `psql libpq unix-socket` |
| `cpuset` | `sut 0-15`, `client 0-15 (shared)`, `collector 20-23` |
| `timeout_method` | CUBRID `external timeout(1) 300s` / PG `session GUC statement_timeout=300s` |
| `sut_boundary` | 주 지표 집합 + **별개 열 목록**(`broker+CAS`, `io worker`, `cub_server 내부 배경 스레드`) |
| `configured_cap` | 노드 단위 cap과 **전역 예산**을 따로 |
| `build` | CUBRID/PG의 `commit` + ELF `Build ID` |
| `config_deviations` | 대외 인용 단서(히스토그램 on, PG mmap, PG dev 스냅샷) |
| `correctness` | `sf1_reference` 상태 + 대체 채증 |
| `artifacts` | 파일별 `bytes` + `sha256_16` |

**계약과 실행이 다르면 즉시 중단·보고한다.** `meta.sh`는 `connection_mode` 화이트리스트와
양쪽 서버의 cpuset을 검사해 불일치 시 `CONTRACT_MISMATCH`를 출력하고 exit 2 한다.
metadata가 없는 run은 **표에 올리지 않는다**(ADR 0016의 하위 레짐 필드와 같은 취급).

## 3. complete-case Pareto와 censored lower-bound를 분리한다

`PER_QUERY_CONNECTION_DIAG` 실측: **q17·q20은 양쪽 timeout, q22는 CUBRID만 timeout**이다.

| 구분 | 쿼리 | 처리 |
|---|---|---|
| **complete-case (19개)** | q1~q16, q18, q19, q21 | Pareto 순위를 여기서만 낸다 |
| **censored — 한쪽만** | **q22** (CUBRID `timeout_ext` ≥300.008 s / PG **0.971 s**) | 격차 **≥299.03 s**, 배수 **≥309x** = **전체 22개 우선순위 최상위**. lower-bound로만 인용 |
| **censored — 양쪽** | q17, q20 (양쪽 ≥300 s) | 격차 판정 불가. 순위에 넣지 않는다 |

* **Q21은 "완주 19개 complete-case Pareto 1위"로만 표기한다.** "절대격차 1위"·"최대 격차"라는
  무조건 서술을 금지한다. Q21 격차 59.05 s는 q22의 lower-bound 299.03 s보다 작다.
* Pareto 누적 비율(`positive_pareto`)도 **complete-case 분모**임을 명기한다.
* censored 값에 대치·보간을 하지 않는다(ADR 0005 유지).

## 4. "6 실행 단위 파리티" 폐기 → `configured-cap parity`

`parallelism`(CUBRID)과 `max_parallel_workers_per_gather`(PG)는 **노드 단위 상한**이고,
쿼리 전체 예산은 CUBRID `max_parallel_workers`(현 구성 **100**,
`px_worker_manager_global.cpp:57-78`) ↔ PG `max_parallel_workers`(**8**)다.
**전역 예산이 12.5배 비대칭**이며 현행 파리티는 그것을 맞추지 않는다.

* 용어를 **`configured-cap parity`**로 바꾼다. "실행 단위 파리티"·"양쪽 6단위"라는 표현을 금지한다.
* 모든 표에 다음 5개를 **따로** 적는다:
  `planned` / `launched` / `동시 활성 (표본 최대)` / `time-weighted active units` / `serial tail`.
* `time-weighted active units`가 노드 cap을 **초과**하면 라벨 `configured-cap 초과`,
  cap의 80 % 미만이면 `단위 붕괴`, 그 사이는 `병렬 유지`다.
  (Q3 cubH가 첫 `configured-cap 초과` 사례 — 7.05 = cap 6의 117.5 %, 동시 활성 12.)
* **전역 예산 비대칭은 제거 대상이 아니라 기록 대상**이다. PG 클러스터 기본값
  `max_parallel_workers=8`은 바꾸지 않는다(ADR 0019 §7-b 유지). 배수 인용 시
  `CUBRID 전역 예산 100 / PG 8`을 명기한다.
* ADR 0014의 정의 자체(파리티는 worker 수가 아니라 실제 단위 수로 맞춘다)는 **불변**이다.
  바뀌는 것은 명칭과 기록 항목 수다.

## 5. 기여도·배수는 이벤트 단위를 명시하고 혼용하지 않는다

* 모든 배수·기여도에 `[wall]` / `[질의실행분 CPU-초]` / `[cycles]` / `[instructions]` /
  `[time-weighted active units]` 중 하나를 붙인다.
* 곱 분해는 축마다 이벤트 단위를 적는다. Q3:
  `2.2573x [wall] = 1.2465x [wall] × 0.7986x [units 비] × 2.2676x [CPU-초 비]`.
* **Q8 분해는 `0.999x × 0.9314x × 4.2559x` 또는 `3.508x × 1.129x`로만 표기한다.**
  두 표기를 섞거나 다른 인자 조합으로 재배열하지 않는다.
* 정본 비교축은 계속 `cycles`이고 IPC 비 ±20 % 규칙은 유지한다(ADR 0019 §2).

**Q3 실측으로 두 조항을 좁힌다.**
* **ADR 0016 민감도 판정** — "버퍼 잔존율이 상태에 따라 움직이는가"는 필요조건이지 충분조건이
  아니다. Q3 PG는 잔존율이 30.2 → 66.6 %(**+36.4 %p**, Q8의 3.6배)로 움직이는데
  `Execution Time`은 −1.86 %다(미스 단가 **0.175 µs**). 판정 기준을
  **"미스 감소량 × 미스 단가가 wall에서 관측되는가"**로 좁히고, 미스 단가를 항상 같이 적는다.
* **ADR 0019 §4-c leader 클럭 이득** — Q3에서 재현되지 않는다(leader 2.378 GHz < worker
  2.513 GHz, 직렬 0.50 s). 조항을 **"직렬 구간이 wall의 20 % 이상일 때만 클럭 이득을 가정한다"**로
  좁힌다. 그 미만이면 역산 클럭을 그대로 적고 이득을 가정하지 않는다.

## 6. Q3 다음 대상은 Q22다

`bounded profile + 플랜 규명`으로 진행한다. CUBRID가 300 s에서 잘리므로:
* 먼저 **bound를 확정**한다 — 쿼리별 개별 호출 패스에서 CUBRID 외부 `timeout`을 늘려
  실제 완주 시간을 재거나(계약 변경 필요), timeout 안에서 끝나는 축소 변형으로 플랜을 규명한다.
* **새 세션으로 별도 지시**한다. 이 세션에서 착수하지 않는다.

## 7. SF1 correctness 미수행 — 모든 항목을 `measured, correctness-unverified`로 강등한다

**결정: 면제하지 않는다. 강등 + 백로그 등재.**

근거:
* SF1 reference answer 대조에는 SF1 데이터셋과 TPC-H kit의 검증 answer가 필요하다.
  현 환경에 **SF1 데이터셋이 없고**(적재된 것은 SF10 단일 세트), **재적재가 금지**되어 있으며,
  `dbgen`/`qgen` SHA-256과 spec/kit 버전이 확정 불가다(ADR 0004의 수용된 한계).
* 따라서 지금 수행할 수 없고, 수행 불가를 이유로 면제하면 "완료" 표시가 근거 없이 남는다.

집행:
* **README·보고서의 어떤 항목에도 "완료"를 쓰지 않는다.** 상태 라벨은
  `measured, correctness-unverified`다. 기존 "규명 완료" 표현을 전부 이 라벨로 바꾼다.
* 대체 채증은 **하위 증거**로만 기록한다: (a) 양쪽 엔진 결과 동일성, (b) 노드별 실제 행수 일치,
  (c) 결과 행 수. 이것들은 correctness를 증명하지 않는다(둘 다 같이 틀릴 수 있다).
* **백로그 등재**: `SF1_CORRECTNESS` 트랙 — SF1 데이터셋 생성 + reference answer 대조.
  선행 조건은 (1) 재적재 금지 예외 승인 또는 별도 DB 사용 승인, (2) TPC-H kit 확보.

## 8. 기존 결과는 삭제 금지 — 재분류만, manifest와 백업 위치를 남긴다

* rev 1 산출물(`g2-stream`, `q21`, `q9`, `q8`, `q18`, `q15`)은 **경로·내용 그대로 둔다.**
  라벨과 명칭만 문서에서 바꾼다.
* raw evidence의 목록·해시·백업 위치는 **`docs/MANIFEST-raw-evidence.md`** 한 곳에 모은다.
* 무효 run도 삭제하지 않고 **무효 사유와 함께 보고서에 남긴다**(Q3: `final` 블록 6 loadavg 33.15,
  `s2` `pg-nl R1` sda 1,551 MiB, `s2b` `cubH B2` 배경 부하).

---

## Consequences

* README의 용어가 전면 치환된다(`G2` → `PER_QUERY_CONNECTION_DIAG`,
  `실행 단위 파리티` → `configured-cap parity`, `규명 완료` → `measured, correctness-unverified`).
* Q21의 "절대격차 Pareto 1위"는 **"완주 19개 complete-case Pareto 1위"**로 한정되고,
  전체 22개 최상위는 **q22(censored lower-bound ≥309x)**가 된다.
* `configured-cap parity`의 전역 예산 비대칭(100 ↔ 8)이 새 미결 항목으로 등재된다.
  Q3 개선 후보 D가 그 항목의 코드 축이다.
* Q15의 PG `InitPlan` 3워커 기아(ADR 0019 §7-b)는 이 비대칭의 **PG 쪽 대칭 사례**로 재해석된다 —
  PG는 전역 예산 8에서 굶고, CUBRID는 전역 예산 100에서 cap을 넘는다.
* 백로그 3건: `TRUE_SINGLE_CONNECTION`, `SF1_CORRECTNESS`, `Q22 bounded profile`(다음 대상).

## Status

Accepted (2026-07-29, 사용자 지시). ADR 0001~0019를 **폐기하지 않고 보강**한다 —
측정 방법과 SUT 경계 정의는 불변이고, 명칭·기록 의무·상태 라벨·순위 표기 규칙이 바뀐다.
