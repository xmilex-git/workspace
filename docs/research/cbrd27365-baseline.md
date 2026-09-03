# CBRD-27365 성능 기준선·검증 인프라 캡처 (티켓 #187)

캡처일 2026-09-03. 출처: Notion TPC-H 캠페인 DB(`ntn datasources query`, database `4e97947e-5772-435b-a680-67d7d4a7ca7a`, data source `5d23253e-d89d-44e9-837c-fc98b4042d63`) 22행 + 각 행의 미러 원본 `tpch-sspq/reports/QNN/report.md`(이 레포). 원시 JSON: `.git_ignored_dir/scratch/cbrd27365/notion-baseline.json`(git-ignored).

## 1. 측정 조건 (캠페인 `tpch-sspq-fk-r1-20260730`, Q01 report §환경)

| 항목 | 값 |
|---|---|
| CUBRID 소스 | develop `607f1ee9f` (2026-07-24, [CBRD-26981] 직후) + PR #7441 `b334446d6` |
| CUBRID 바이너리 | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9` — **release 빌드** (`11.5.0.2366-607f1ee`, 2026-09-03 현재 디스크에 존재) |
| DB | `tpch_sf10_q1` (SF10, lineitem 59,986,052행, 8 FK + 8 자식 B-tree), 포트 1523 |
| 병렬 | `parallelism=6`, `max_parallel_workers=100` (PG 측 5 workers + leader) |
| 버퍼 | `data_buffer_size=8192M` (PG `shared_buffers=8192MB`), `sort_buffer_size=2M`, `log_buffer_size=256M` |
| 통계 | `update_statistics_update_histogram=yes`, `default_histogram_bucket_count=300` |
| cpuset | 엔진+클라이언트 CPU 0-15, 수집기 20-23 |
| 레짐 | `single-query-repeat WARM`: warmup 1회(미집계) + measured 3회, **median** 이 헤드라인. 단일 커넥션, 4 statement. 정합성 `result-equivalent-at-SF10` |
| 보조 열 | `CUBRID 512MB seconds` = 2026-08-07 `data_buffer_size=512M` 진단 arm(`/data/tpch-sspq-buffer-512m-20260807`, develop `a2c3e03`, 별도 빌드) — 기준선 아님, 참고용 |

재현용 conf 원본: `/data/tpch-sspq-buffer-512m-20260807/conf/cubrid.conf.b8192` (parallelism=6, 8192M, port 1533 — 포트는 레지스트리에서 재할당).

## 2. TPC-H 22종 헤드라인 (초, median of 3)

| Q | CUBRID 8192M | CUBRID 512M | PostgreSQL | Wall ratio C/P | 완료일 | report commit |
|---|---|---|---|---|---|---|
| Q01 | 31.193 | 31.550 | 11.113 | 2.807 | 2026-07-30 | c73e858 |
| Q02 | 0.353 | 0.456 | 2.395 | 0.147 | 2026-07-30 | ff65f29 |
| Q03 | 4.808 | 11.697 | 3.499 | 1.374 | 2026-07-30 | ddd12cf |
| Q04 | 1.770 | 2.115 | 0.960 | 1.843 | 2026-07-31 | 17ff531 |
| Q05 | 9.615 | 30.208 | 2.564 | 3.749 | 2026-07-31 | e89194b |
| Q06 | 3.875 | 3.989 | 1.618 | 2.395 | 2026-07-31 | 51b6476 |
| Q07 | 23.719 | 29.353 | 2.521 | 9.409 | 2026-07-31 | 6f213cf |
| Q08 | 1.136 | 2.732 | 1.022 | 1.111 | 2026-07-31 | 18c48a9 |
| Q09 | 10.981 | 20.783 | 5.192 | 2.115 | 2026-07-31 | 4a39b0d |
| Q10 | 7.128 | 8.993 | 4.219 | 1.690 | 2026-07-31 | cc1869d |
| Q11 | 1.342 | 3.843 | 0.798 | 1.681 | 2026-07-31 | 3cda62b |
| Q12 | 4.039 | 4.186 | 2.620 | 1.542 | 2026-07-31 | f0ee9ca |
| Q13 | 11.426 | 30.884 | 5.087 | 2.246 | 2026-07-31 | 13375df |
| Q14 | 3.228 | 3.697 | 1.713 | 1.885 | 2026-08-01 | 99edb42 |
| Q15 | 10.445 | 13.379 | 10.665 | 0.979 | 2026-08-01 | b6f6c00 |
| Q16 | 2.886 | (없음) | 1.197 | 2.411 | 2026-08-01 | 1188583 |
| Q17 | 0.146 | 0.270 | 8.755 | 0.017 | 2026-08-01 | a8eadce |
| Q18 | 37.453 | 42.786 | 41.787 | 0.896 | 2026-08-02 | 8f86552 |
| Q19 | 46.515 | 106.687 | 0.289 | 160.720 | 2026-08-02 | 1b5fbc0 |
| Q20 | 1.992 | 5.686 | 6.838 | 0.291 | 2026-08-02 | 80a8826 |
| Q21 | 49.395 | 65.948 | 3.083 | 16.021 | 2026-08-02 | 2780563 |
| Q22 | 1.101 | 1.267 | 0.608 | 1.810 | 2026-08-02 | 802b892 |

22종 모두 Status=Complete, Correctness=Pass. 총합(8192M) 264.5초.

## 3. #193 무회귀 판정에 대한 권고 (D-187-1)

- **Notion 절대값과의 비교는 참고용으로만** 쓴다. 기준선은 release 빌드·cpuset 고정·collector 분리 환경이고, 이 맵의 PR 빌드는 optdebug 가 기본이라 절대값이 맞지 않는다.
- 판정은 **같은 호스트·같은 conf 의 A/B** 로 한다: A = 브랜치 분기점 develop 의 동일 빌드 종류(또는 디스크에 남아 있는 `CUBRID-tpch-sspq-fk-r1-607f1ee9` release 바이너리), B = PR 빌드. conf 는 `cubrid.conf.b8192` 를 포트만 바꿔 재사용, warmup 1 + measured 3 median. 임시 리스트 파일 포맷이 직접 관여하는 정렬·집계·해시조인 무거운 질의(Q01, Q03, Q05, Q07, Q09, Q13, Q18, Q21)를 우선 보고 나머지는 1회 확인.
- 실패 기준(제안): 우선 8종 중 어느 하나라도 median 이 A 대비 +3% 초과 악화, 또는 22종 총합 +2% 초과. 개선 폭은 기록만 하고 판정에 쓰지 않는다.

## 4. 환경 상태표 (2026-09-03)

| 항목 | 상태 | 비고 |
|---|---|---|
| worktree | **OK** `~/dev/worktrees/cbrd27365`, 브랜치 `CBRD-27365` = `origin/develop` `c5645f924` ([CBRD-27176] #7673) | `~/dev/cubrid` 로컬 develop(`6dbf6d92f`)은 origin 보다 3커밋 뒤라 origin/develop 을 직접 기준으로 삼음. 서브모듈은 `just build` 의 `_submodules` 가 초기화 |
| 설치 빌드 `~/CUBRID` | optdebug `11.5.0.2626-f6374a8` (2026-08-30) — **wf122 브랜치 빌드**, develop 아님 | PR-1(#189)부터는 worktree 빌드(`WORKSPACE=~/dev/worktrees/cbrd27365 just optdebug`)로 교체 필요. conf: `data_buffer_size=512M`, `cubrid_port_id=1523` |
| 포트 | cub_master 1523(`~/CUBRID`, pid 1054247, 타 세션 소유)·1702(`release/CUBRID-wf109`); 레지스트리 claim 1701 r10db | `~/CUBRID` 서버는 1523 master 재사용, master 는 절대 내리지 않음. 새 빌드용 포트는 `just port-claim` |
| `tpch_sf10_q1` 개방 | **OK** — `CUBRID_DATABASES=.git_ignored_dir/tpch-sspq/cubrid-databases` 로 start 성공, 볼륨/로그 호환 문제 없음. 8 테이블, region 5, lineitem 59,986,052 | 21GB, 카탈로그는 해당 디렉터리의 databases.txt 만(기본 미등록) — 항상 `CUBRID_DATABASES` 지정. 기준선 바이너리 `~/release/CUBRID-tpch-sspq-fk-r1-607f1ee9`(release) 도 잔존 |
| sql 스위트 분할 | **OK** `just ctp-parallel --dry-run`: 17,457 .sql, 7 shard(315~324s 가중), 전부 정확히 1 shard 배정 | podman 4.9.4 존재 |
| medium 스위트 | **불가(현재)** — `just ctp-sql-isolated ~/cubrid-testcases/medium/_01_fixed` 는 "not under a testcases sql/ tree" 거부; 오케스트레이터가 `ctp.sh sql`/`sql.conf`/`/home/cubrid-testcases/sql` 하드코딩 | medium 은 `ctp.sh medium -c medium.conf` + `files/mdb.tar.gz`(존재) + ha_mode=yes 필요 → 티켓 #195 (#192 를 block) |
| smoke | **OK** csql 12항목 0.1초, expected.out 247줄 오류 0; JDBC 역방향 커서 34줄 기대 출력 확보(브로커 BROKER1 33000) | 발견 1: `JSON_OBJECT/JSON_ARRAY` 인자가 ROWNUM 파생 컬럼이면 "INST_NUM() or ROWNUM is not allowed" 오류(기존 파서 제약, 무관) → id 를 실체 테이블 `t_seq` 경유로 생성. 발견 2: 러너 sed 에 `/g` 누락으로 DDL 줄의 2번째 타이밍이 남아 재실행 spurious FAIL → 수정. 재실행 idempotence: 수정 후 `run_smoke.sh cbrd27365s 33000` 2회 연속 csql PASS + scroll PASS(diff 없음, 각 0.8초) |
| 스크래치 DB | `cbrd27365s` (`.git_ignored_dir/scratch/cbrd27365/db/`, 64M+64M) 유지 | smoke 재실행용 |

## 5. smoke 설계 (D-187-2)

위치 `docs/research/cbrd27365-smoke/`: `smoke.sql`(csql, 12항목) + `ScrollSmoke.java`(JDBC 역방향 커서) + `run_smoke.sh`(타이밍 제거 후 `expected*.out` 과 diff). 항목 ↔ 포맷 접점:

| # | 항목 | 건드리는 경로 |
|---|---|---|
| 1 | NULL 혼합 정렬 (14컬럼, 고정폭 NULL 선두) | 정렬 리스트, 널비트맵, 상수 오프셋 캐시 한계 |
| 2 | 고정/가변 혼합 GROUP BY + NULL 그룹 | 집계 튜플, in-place 누산 |
| 3 | NULL-only 첫 브랜치 UNION ALL | 늦은 도메인(DB_TYPE_VARIABLE→확정) 재finalize |
| 4 | 40,000B 값 정렬 | 오버플로 튜플 |
| 5 | CONNECT BY NOCYCLE + ISLEAF/ISCYCLE/PATH | in-place 덮어쓰기 3지점(#185) |
| 6 | USE_HASH inner/outer, NULL·중복 키 | 해시조인 리스트 |
| 7 | USE_MERGE (`optimizer_enable_merge_join=yes`, 클라이언트 세션 파라미터) | MERGELIST outer/inner = backward 리스트(#184 B) |
| 8 | 분석함수 PARTITION/ORDER/LAG/NTILE | 분석함수 group/value 리스트(#184 C) |
| 9 | ORDERBY_NUM / ROWNUM 서브쿼리 | orderby_num·inst_num in-place(#185) |
| 10 | SET/JSON 컬럼 정렬 | `index_readval` 없는 타입 스크래치 복사(#180) |
| 11 | DISTINCT | list unify |
| 12 | 71컬럼 SELECT | 비트맵 다중 워드 |
| S | JDBC TYPE_SCROLL_INSENSITIVE previous/absolute/relative | 최종 결과 리스트 backward(#184 A), `cursor_prev_tuple` |

역방향 커서는 csql 로 낼 수 없어 JDBC 1클래스가 추가된다(브로커 BROKER1 33000 필요). 실행 시간·기대 출력 생성 결과는 §4 와 티켓 #187 코멘트에 기록.
