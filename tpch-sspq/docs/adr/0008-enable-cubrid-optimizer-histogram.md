# CUBRID 옵티마이저 히스토그램을 활성화한다 (기본값 이탈)

ADR 0003은 "release 단일 빌드로 절대 성능을 측정한다"고 정했고, 2단계는 양쪽
통계를 각자의 표준 명령으로 갱신한 뒤 이를 "통계 파리티"라고 적었다. 2.5단계
채증이 그 표현을 깼다(`docs/report-cubrid-statistics-content-20260728.md`).

**기본 설정 CUBRID의 컬럼당 옵티마이저 통계는 NDV 하나뿐이다.** min/max·null
비율·도수분포·MCV가 모두 없다. 히스토그램 서브시스템은 이 pin에 존재하지만
(`src/optimizer/histogram/`, CBRD-26202 이후) `update_statistics_update_histogram`
기본값이 `no`라 만들어지지 않았고, 그 결과 `<`/`<=`/`>`/`>=`의 셀렉티비티는
데이터와 무관한 상수 `0.1`, `BETWEEN`은 `0.01`이었다
(`query_planner.c:10624`, `10645`).

PostgreSQL은 같은 데이터에서 null_frac·n_distinct·MCV+빈도·100버킷 히스토그램·
correlation·avg_width를 갖는다. 이 상태로 G4의 plan diff / 추정-실측 행수 괴리를
비교하면, 관측되는 차이가 **실행 엔진의 차이인지 옵티마이저 입력 정보량의 차이인지
분리되지 않는다.** TPCH-SSPQ의 판정 축은 "세션 하나가 확보하는 병렬성"이고
(CONTEXT.md), 카디널리티 추정 정보량 격차는 그 축이 아니다.

## Decision

`update_statistics_update_histogram=yes`로 CUBRID 히스토그램을 활성화한다.
**이는 CUBRID 기본값에서 의도적으로 이탈하는 것이다.**

적용 경로와 범위:

| 항목 | 값 |
|---|---|
| 적용 파일 | `~/tpch-sspq-install/cubrid-f30f1c260/conf/cubrid.conf` (측정 install 전용) |
| 적용 방식 | `[common]` 섹션에 `update_statistics_update_histogram=yes` 추가 후 래퍼로 서버 재기동 |
| 채증 | `cubrid paramdump` → `[C*] …=y (n)` / `[S*] …=y (n)` — `*`가 기본값 이탈, `(n)`이 기본값 |
| 불가침 | `~/CUBRID` 심링크 불변(`jdbc-direct-poc-release/CUBRID-jdbc-direct-v3-r1`), 공용 `~/databases` 불변, **데이터 재적재 없음** |
| 버킷 수 | CUBRID 자기 기본값 `default_histogram_bucket_count=300`을 쓴다. **명시적으로 설정하지 않는다**(기본값이 적용되도록 비워 둠) |

## 왜 (a) 기본값 유지가 아닌가

(a)는 "기본 설정 CUBRID"를 측정한다는 장점이 있지만, G4에서 관측될 모든 plan
차이에 "CUBRID는 범위 술어 셀렉티비티를 상수로 추정한다"는 교란 요인이 항상
섞인다. 그러면 G5에서 열 트랙을 증거로 좁히는 것이 불가능해진다(ADR 0005의 얇은
경로가 성립하지 않는다). 정보량을 맞춘 뒤 남는 차이를 보는 것이 이 프로젝트의
질문에 더 가깝다.

(c) 둘 다 측정은 게이트 하나에 두 레짐을 동시에 여는 것이므로 ADR 0005가 금지한다.
필요해지면 별도 게이트로 연다.

## 대외 인용 시 필수 단서

이 설정에서 나온 수치는 **기본 설정 CUBRID의 성능으로 인용할 수 없다.** 보고서·
발표·이슈 코멘트에 수치를 옮길 때 다음 문구를 함께 적는다.

> 이 측정의 CUBRID는 `update_statistics_update_histogram=yes`(기본값 `no`)로
> 옵티마이저 히스토그램을 활성화한 구성이다. 기본 설정 CUBRID는 컬럼 히스토그램을
> 만들지 않으며, 그 경우 범위 술어 셀렉티비티가 상수로 추정된다. 따라서 이 수치는
> 기본 설정 CUBRID의 성능이 아니다.

ADR 0002의 PostgreSQL 단서(개발 스냅샷이므로 릴리스 PostgreSQL 성능으로 인용
불가)와 **둘 다** 붙는다. 즉 이 프로젝트의 수치는 어느 쪽 엔진에 대해서도
"출시 제품의 성능"이 아니다.

## 4. 버킷 수 비대칭은 사실로 기록하고 맞추지 않는다

| 엔진 | 파라미터 | 값 | 성격 |
|---|---|---|---|
| CUBRID | `default_histogram_bucket_count` | **300** | 버킷 수 |
| PostgreSQL | `default_statistics_target` | **100** | 버킷 수 + MCV 상한 + 표본 크기(300×target=30,000행) |

두 값은 의미가 같지 않다(PG의 target은 표본 크기까지 좌우한다). 지금은 **각 엔진의
자기 기본값을 쓰고 비대칭을 사실로 기록한다.** 나중에 정렬 여부를 판단할 수 있도록
변경 비용만 실측해 뒀다(`docs/report-cubrid-histogram-enabled-20260728.md` §6):
8테이블 DROP+재구축이 300버킷 39.7s, 100버킷 36.5s로 **차이 3.2s**이며, 정렬은
언제든 40초 이내에 되돌릴 수 있다. 즉 이 비대칭은 값싸게 가역적이므로 지금 결정을
서두를 이유가 없다.

## 실행 경로의 함정 (측정 전 반드시 알아야 함)

`UPDATE STATISTICS ON ALL CLASSES WITH FULLSCAN`만으로는 **의도한 히스토그램이
만들어지지 않는다.**

* 두 `UPDATE STATISTICS` 경로 모두 `histogram_info.bucket_count = -1`을 넘기는데
  (`network_interface_cl.c:6197`, `execute_statement.c:4777`),
  `execute_schema.c:4289-4291`은 값이 **정확히 0일 때만** `default_histogram_bucket_count`를
  대입한다. `-1`은 그대로 범위 클램프(`4294-4296`)에 걸려 **최소값 4**가 된다.
* `ON ALL CLASSES` 경로는 `with_fullscan = false`를 하드코딩해
  (`network_interface_cl.c:6198`) 문장의 `WITH FULLSCAN`을 **버린다**.

따라서 기본값 300 + 전체 스캔을 실제로 얻으려면 테이블별로
`ANALYZE TABLE <t> UPDATE HISTOGRAM WITH FULLSCAN`을 쓴다(빈 `opt_with_n_buckets`가
`0`이라 300이 적용된다 — `csql_grammar.y:4889-4892`). 또한 기존 카탈로그 엔트리
위에 다시 만들면 `with_fullscan` 플래그가 갱신되지 않으므로
(`sm_add_histogram`이 `ER_LC_CLASSNAME_EXIST`를 관용 — `execute_schema.c:4373`)
**`ANALYZE TABLE <t> DROP HISTOGRAM`을 먼저 실행한다.**

이 절차는 `.git_ignored_dir/g1-assets/scratch/rebuild-hist.sh`에 고정했다.
G1 하네스는 통계 재구축이 필요할 때 이 스크립트를 쓴다.

## Consequences

* CUBRID 옵티마이저가 컬럼 히스토그램·MCV·null 비율을 갖게 되고, 범위/등식 술어
  셀렉티비티가 데이터에 반응한다(실측: `l_shipdate < date` 추정 오차 4.30배 →
  1.004배).
* **여전히 없는 것**: 물리 correlation, avg_width. 소스에 해당 개념이 없다
  (`grep -E 'correlation|avg_width'` → 히스토그램·통계 코드 0건). 그리고
  `attr op attr` 술어는 히스토그램 경로 자체가 없어(`query_planner.c:10523-10525`)
  상수 `0.1`로 남는다. 이 세 항목은 G4에서 여전히 전제로 명기해야 한다.
* 도메인 min/max는 **여전히 정확히 얻을 수 없다.** 최저 버킷이 `(-inf, hi]`로 열려
  있어 min은 복원 불가이고, max도 항상 정확하지는 않다(실측: `o_orderdate` max는
  정확, `l_shipdate`는 1998-11-29로 실제 1998-12-01보다 2일 짧음). PG는
  `histogram_bounds` 양 끝이 실제 양 끝이다.
* 통계 재구축 비용이 생겼다: 8테이블 39.7s(300버킷, 전체 스캔). WARM 레짐의 warmup
  전에 완료해야 한다(ADR 0006).
* ADR 0007의 "데이터를 pin 빌드로 재적재한다"와 무관하다. **데이터는 건드리지 않았다.**

## Status

Accepted (2026-07-28). 적용 완료, 채증은
`docs/report-cubrid-histogram-enabled-20260728.md`.
