# 기존 `tpch_sf10_v2`와 포팅된 q1~q22를 CUBRID 정본으로 재사용하고 provenance 한계를 수용한다

이 장비에는 TPC-H 공식 kit이 없다. `dbgen`·`qgen`·`dists.dss` 어느 것도 없어
(`/home/cubrid`·`/data` 전역 탐색 결과 0건) **바이너리 SHA-256도 kit·spec 버전도 산출할 수 없고**,
기존 데이터의 생성 명령·RNG seed·`-s` 인자 기록도 남아 있지 않다. 확인 가능한 근거는
`scale10/load_data/scale_factor.txt` = `SCALE_FACTOR=10`과 `scale10/queries/README.md`의
"Generated with qgen -d (default substitution values)" 두 줄뿐이다.

kit을 새로 받아 재생성하면 provenance는 확보되지만, kit 확보·빌드·12GB 생성·양쪽 적재까지
수 시간과 `/home` 60GB 이상이 추가로 들고, 이 프로젝트의 1차 질문(단일 세션 병렬성의 구조적 차이)에는
데이터 생성 파라미터가 거의 영향을 주지 않는다. 그래서 **기존 자산을 재사용하고 한계를 명시적으로
문서에 박아 두는 쪽**을 택한다.

## Decision

- 데이터: `~/databases/tpch_sf10_v2`(55G, `scale_factor.txt`=10)를 그대로 쓴다. 재생성하지 않는다.
- 쿼리: `~/dev/cubrid/.vscode/TPC-H/scale10/queries/`의 q1~q22(+`q15_create_view`/`q15_select`/
  `q15_drop_view`)를 **CUBRID 정본**으로 삼는다.
- 스키마: 같은 디렉터리의 `create_tpch_table.sql` / `create_tpch_index.sql`.
- PG 적재와 PG판 쿼리 파생은 **이번 범위 밖**이다.

## Consequences

- **이 데이터셋은 감사 불가능하다.** `dbgen` 버전·seed·kit revision을 확정할 수 없으므로 결과는
  "TPC-H 공식 결과"가 아니고, 제3자가 같은 데이터를 재생성할 수도 없다. 모든 보고서에 이 한계를 적는다.
- 정본 쿼리가 이미 CUBRID 방언이다. `CONTEXT.md`의 Canonical Query Set 정의상 **엄밀한 기준선이 없는
  상태**이며, 나중에 PG판을 만들 때는 CUBRID 정본에서 역파생하게 된다. 이때 가한 변형은
  Engine Dialect 규칙(문법이 강제하는 최소 변형만, 플랜을 바꾸는 재작성 금지)에 따라 diff로 남긴다.
  q1의 `DATE_SUB(DATE '1998-12-01', INTERVAL 90 DAY)`처럼 spec 원문과 다른 표기가 이미 존재한다.
- 결과적으로 **엔진 간 절대 성능 비교의 대외 인용 가치는 낮고, 같은 데이터 위에서의 병렬성 거동
  비교가 이 프로젝트의 유효 산출물**이다. 스코프를 그 이상으로 넓히려면 kit 재확보가 선행 조건이다.
- 재생성으로 방향을 바꾸는 순간 이 ADR을 supersede하고, 그 전에 나온 수치는 새 데이터셋 수치와
  같은 표에 올리지 않는다.
