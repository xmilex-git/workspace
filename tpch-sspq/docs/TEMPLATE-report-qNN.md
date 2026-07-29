# QNN 격차 규명 — <한 줄 결론>

기존 `report-q15-gap-20260729.md` / `report-q3-gap-20260729.md`의 형식을 정본으로 하고,
ADR 0021이 요구하는 **`PG 대조 (의무)`** 절을 필수로 포함한다. 절 번호는 쿼리별로 달라도 되지만
**아래 절 중 하나라도 빠지면 4단계 완주로 세지 않는다.**

---

## 0. 메타 (모든 표의 전제)

| 항목 | 값 |
|---|---|
| `contract_revision` | `2` (ADR 0020) + ADR 0021 보고 요건 |
| `track` / `connection_mode` | `SINGLE_QUERY_REPEAT` 등 / `single-connection-n-statements` 등 |
| `protocol` | CUBRID `csql -C direct (cub_server)` ↔ PG `psql libpq unix-socket` |
| `cpuset` | sut `0-15` / client `0-15 (shared)` / collector `20-23` |
| `timeout_method` | CUBRID 외부 `timeout(1)` Ns / PG 세션 GUC `statement_timeout` |
| `sut_boundary` | 주 지표 + 별개 열(`broker+CAS`, `io worker`, 배경 스레드) |
| `configured_cap` | 노드 cap과 전역 예산을 **따로** |
| `build` | CUBRID/PG `commit` + ELF `Build ID` |
| WARM 하위 레짐 | `stream` ↔ `single-query-repeat` (섞지 않는다) |
| 상태 라벨 | `measured, correctness-unverified` |
| `meta.json` | run 디렉터리별 경로 목록 |

## 1. 플랜 규명

양쪽 플랜 전체 덤프(CUBRID `SET OPTIMIZATION LEVEL 514` 무실행 / PG `EXPLAIN (ANALYZE, BUFFERS,
VERBOSE)`), 추정 ↔ 실측 카디널리티 표, 형상이 갈리는 지점.

## 2. 실행 채증

wall / 질의실행분 CPU-초 / `planned` / `launched` / `동시 활성(표본 최대)` /
`time-weighted active units` / `serial tail` — **5개 축을 따로**. 라벨은 노드 cap 대비
`time-weighted active units`로 판정(80 % 미만 `단위 붕괴` / 100 % 초과 `configured-cap 초과`).
CUBRID trace의 `rows == readrows` 함정을 명시적으로 확인한다.

## 3. 프로파일

정본 축 `cycles`. `instructions`·IPC 비를 같이 적고 IPC 비가 1에서 ±20 % 벗어나면
`instructions` 기반 서술을 금지한다. 기능 단계 버킷(UNION 규칙) + 상위 심볼.
직렬 구간이 wall의 5 % 초과면 **행위자별 프로파일**을 산출하고, 20 % 이상이면 필수다.
`perf record -a -C` 심볼 함정(`q3/scratch/resolve.py`) 검산율을 적는다.

## 4. 소스 규명 (CUBRID)

버킷별 `file:line`과 호출 빈도·단가.

## 5. PG 대조 (의무 — ADR 0021)

**필수 절.** 4단계에서 지적한 **문제 항목마다** 아래 표를 채운다. 한 열이라도 비면 그 항목은
`PG 대조 미채증`으로 표시하고 개선 후보의 근거로 쓰지 않는다. pin은
**PG `5713b437abed7085e7d59849c6e9e0f4f469633d`**(20devel)이며 다른 커밋을 인용하면 같은 줄에 적는다.

| # | 항목 | CUBRID `file:line` | PG `file:line` (pin 5713b437) | 구현 차이 (한 문장) | 분류 |
|---|---|---|---|---|---|
| 1 | | | | | (a) 구조적 부재 / (b) 같은 단계가 있으나 싸다 — 단가 숫자 / (c) **양쪽 공통** |

* **(c) 양쪽 공통**으로 분류된 항목은 삭제하지 않고 라벨을 붙여 남기고, **개선 후보에서 내린다.**
* PG에 대응 코드가 **없다**는 주장도 채증한다 — 탐색한 심볼·경로·grep 패턴을 적는다.
* 플랜 수준 서술("PG는 hash join을 쓴다")은 대조가 아니다. 그 노드를 구현하는 파일·행이 필요하다.

## 6. 개선 후보

후보마다 (1) 기존 번호 후보와의 겹침(①~⑯) (2) **§5의 PG 참조 구현** (3) 예상 배수 레인지와
그 산출 근거 (4) 난이도·위험. **구현은 하지 않는다.**

## 7. 채증 목록

파일별 경로 + `bytes` + `sha256_16`. 무효 run은 **삭제하지 않고 무효 사유와 함께** 남긴다(ADR 0020 §8).

## 8. 상태

`measured, correctness-unverified`. "완료"·"규명 완료"를 쓰지 않는다(ADR 0020 §7).
