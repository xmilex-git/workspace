# 도메인·collation 사전 확정 캠페인(dpin) — 작업 트리·빌드·기준선·마이크로벤치 계측 설계

지도: xmilex-git/workspace#312 · 준비 티켓: #316 · 작성 2026-09-22 · 기준: CUBRID/cubrid `develop` `cad27172b`

## 1. 작업 트리 (세 저장소, develop 최신, 포크에만 푸시)

| 저장소 | 워크트리 | 브랜치 | 시작 해시 | 푸시 리모트 |
|---|---|---|---|---|
| CUBRID/cubrid | `~/dev/cubrid-worktree/dpin` | `dpin` | `cad27172b` (2026-09-21, [CUBRIDQA-1603] #7984) | `fork` → xmilex-git/cubrid |
| CUBRID/cubrid-testcases | `~/dev/cubrid-tc-worktree/dpin` | `dpin-tc` | `4a7a4aed9` (2026-09-21, [CBRD-27043] #3536) | `fork` → xmilex-git/cubrid-testcases |
| CUBRID/cubrid-testcases-private-ex | `~/dev/cubrid-tc-ex-worktree/dpin` | `dpin-tc-ex` | `dfb7da195` (2026-09-21, [CBRD-27043] #4196) | `fork` → xmilex-git/cubrid-testcases-private-ex |

규칙: CUBRID 조직 저장소(`origin`)에는 절대 푸시하지 않는다. CTP 는 `just ctp <suite> [DIRS...]` 에 `TC_REF=dpin-tc` 를 명시한다.
이전 캠페인 브랜치(`wf268*`)는 읽기 전용 참고이며 체리픽하지 않는다(D-M1).

## 2. 빌드 설치본 (양 빌드, `~/CUBRID` 는 건드리지 않음)

| 모드 | 설치 prefix (툴링 리포 기준) | 빌드 명령 |
|---|---|---|
| optdebug | `.git_ignored_dir/scratch/dpin/install-optdebug` | `INSTALL_PREFIX=<abs prefix> WORKSPACE=~/dev/cubrid-worktree/dpin just build debug` |
| release | `.git_ignored_dir/scratch/dpin/install-release` | `INSTALL_PREFIX=<abs prefix> WORKSPACE=~/dev/cubrid-worktree/dpin just build release` |

- `just build` 가 `just conf` 로 캠페인 `cubrid.conf` 를 각 prefix 에 넣는다(`parallelism=24`, `max_parallel_workers=100`, `stored_procedure=yes`).
- 빌드 결과(exit·버전 스탬프·conf 일치)는 §2.1. 빌드 로그: `.git_ignored_dir/scratch/dpin/build-{optdebug,release}.log`.
- 게이트 규약: 비교는 같은 빌드 타입끼리만(L-03). 계측 카운터 검증은 optdebug, 시간 측정은 release.

### 2.1 빌드 결과 (2026-09-22)

| 모드 | exit | 버전 스탬프(`bin/cubrid_rel`) | conf 일치 |
|---|---|---|---|
| optdebug | 0 | `CUBRID 11.5.0 (11.5.0.2600-cad2717) (64bit optdebug build for Linux) (Sep 22 2026 09:07:02)` | 캠페인 `cubrid.conf` 와 diff 없음 |
| release | 0 | `CUBRID 11.5.0 (11.5.0.2600-cad2717) (64bit release build for Linux) (Sep 22 2026 09:09:13)` | 캠페인 `cubrid.conf` 와 diff 없음 |

- `~/CUBRID` mtime 2026-09-21 16:17:46 전후 동일(건드리지 않음). 워크트리 HEAD `cad27172b` 유지; `git status` 의 ` m cubrid-cci` 는 빌드가 서브모듈을 초기화하며 생긴 빌드 산출물(gitlink `bd86063a5` 불변)이다.
- 서버 기동·CTP 는 이 티켓에서 하지 않았다(빌드 검증은 설치본 존재 + 버전 스탬프까지).

## 3. 기준선 = GitHub nightly (로컬 전수 재측정 없음, 사용자 결정 2026-09-22)

- `gha-ci` 워크플로의 cron(`20 15 * * *` UTC)이 develop 머지 커밋마다 `dispatch all <sha>` 를 띄우고 커밋 상태 `gha-ci: test_sql` / `test_medium` / `test_shell` 을 남긴다.
- 확인 명령: `gh api repos/CUBRID/cubrid/commits/cad27172b/status --jq '.state, (.statuses[] | "\(.context) \(.state) \(.target_url)")'`

**엔진 시작 해시 `cad27172b` 의 nightly** — run <https://github.com/CUBRID/cubrid/actions/runs/35619124899> (`dispatch all cad27172b…`, 2026-09-21 15:28 UTC):

| 상태 컨텍스트 | 결과 | 집계 |
|---|---|---|
| `gha-ci: test_sql` | **success** | 17466 / 17466 pass |
| `gha-ci: test_medium` | **success** | 975 / 975 pass |
| `gha-ci: test_shell` | failure | 3254 / 3256 pass, 실패 2, skip 30 |

test_shell 실패 2건(둘 다 `cubrid-testcases-private-ex`):
- `shell/_28_features_844/issue_10986_eventlog/_03_eventlog_tempvolume/cases/_03_eventlog_tempvolume.sh` — 서버 이벤트 로그의 `DISK_ADD_VOLUME`/`DISK_EXTEND`/`TEMPORARY_VOLUME` 줄 수를 세는 볼륨 확장 TC.
- `shell/_06_issues/_15_1h/bug_bts_15156/cases/bug_bts_15156.sh` — `cub_master` 를 kill 한 뒤 `top` 으로 `cub_server` CPU 점유율이 5% 이하인지 보는 TC.

**판정: 기준선은 이 상태로 고정한다.** 두 실패는 도메인·호스트 변수·collation 과 무관한 볼륨/프로세스 인프라 TC 이고, 이웃 develop 커밋의 같은 날 nightly 에서도 번갈아 실패한다(`684c8e8c3` run 35619132844: `_03_eventlog_tempvolume` + `hide_cubrid_replay`; `4f0f90b62` run 35619127534: `issue_11202_temp_volume_create`; 직전 `5d8fc7bd5` run 35423041306 은 세 suite 모두 success). 이 캠페인의 게이트는 D-M 게이트 규약대로 **optdebug CTP sql 전수 + medium** 이며 shell 은 최종 게이트에서 위 2건을 known-flaky 로 제외하고 본다.

## 4. 마이크로벤치 계측 설계 — "행당 도메인 결정·변환 횟수" 를 세는 방법

목표(지도 게이트): 호스트 변수·auto-param 경로에서 **행당 도메인 결정·변환 0회**, 게이트 변환은 **실행당 값 1회**. 이를 코드 리뷰가 아니라 **실행 중 카운터** 로 증명한다.

### 4.1 계측 수단 (D-316-1)

- **perfmon 누적 카운터**(`src/base/perf_monitor.h` `PERF_STAT_ID` enum 에 `PSTAT_QM_…` 항목 추가 + `perf_monitor.c` `pstat_Metadata[]` 에 `PSTAT_METADATA_INIT_SINGLE_ACC (…, "Num_…")` 한 줄). 삽입 지점에서는 `perfmon_inc_stat (thread_p, PSTAT_…)` 1줄.
- 읽는 법: 세션 단위는 `SET @collect_exec_stats = 1` (session.c:1147 `perfmon_start_watch`) 뒤 질의 실행 → `SHOW EXEC STATISTICS ALL` (해당 세션 누적, 카운터 이름으로 행이 나온다); 서버 전체는 `cubrid statdump <db>`.
- 비용: 감시자 없으면 `perfmon_is_perf_tracking()` (`pstat_Global.n_watchers > 0`) 검사 1회로 끝나 행당 비용이 사실상 0 — 카운터를 **영구 코드**로 남겨 CTP TC(`SHOW EXEC STATISTICS ALL` 의 값이 0 인지 비교하는 sql TC 1개, `dpin-tc` 에 추가)가 회귀 감시를 겸한다.
- 기각 대안: (a) `er_log_debug`/환경변수 fprintf — 클라이언트에서 읽을 수 없고 CTP 로 감시 불가. (b) gdb 브레이크포인트 히트 카운트 — release 빌드에서 재현 불가, 자동화 불가. (c) `#ifdef` 전용 빌드 — L-03(같은 빌드끼리 비교) 위반.
- 순서(D-316-2): **계측 커밋을 먼저** dpin 에 올려 develop 상태의 "이전" 횟수를 같은 카운터로 측정해 두고, 구현 뒤 같은 셀에서 "이후" 를 잰다. 계측 커밋은 동작을 바꾸지 않으므로 게이트는 optdebug 빌드 green + 셀 실행으로 충분하다.

### 4.2 카운터 목록과 삽입 지점 (지점 번호는 `domain-pin-exec-sites.md` S-xx, 줄은 `cad27172b`)

| 카운터(`Num_…`) | 세는 사건 | 삽입 지점 | 구현 뒤 기대값 |
|---|---|---|---|
| `Num_domain_resolve_fetch` | fetch 가 **값** 에서 regu 도메인을 정하거나 VARIABLE 도메인을 탈착·재확정 | S-01 `fetch_peek_arith` fe:1316 탈착 분기(한 번만; 재확정 fe:4465~4477 은 같은 사건) · S-04 NVL/COALESCE/NVL2/NULLIF/LEAST/GREATEST 의 `tp_infer_common_domain` 호출 · S-05 `fetch_peek_dbval_slow` fe:5225~5229 `regu_var->domain = tp_domain_resolve_value(…)` · S-06 REGUVAL_LIST 행별 확정 fe:5233~5262 | **0** |
| `Num_domain_coerce_compare` | 비교가 타입 불일치로 값을 강제변환 | S-09 `eval_value_rel_cmp` qe:220~262 in-place `tp_value_coerce` 분기 · S-10 qe:271/276 에서 `DB_VALUE_DOMAIN_TYPE(dbval1) != DB_VALUE_DOMAIN_TYPE(dbval2)` 인 호출 · S-11 `qexec_topn_cmpval` qx:27786 VARIABLE 폴백 | **0** |
| `Num_domain_resolve_list` | 리스트 파일 컬럼·위치 서술자·정렬 키 도메인을 실행 중 결정(재시도 포함) | S-13 `qfile_update_domains_on_type_list` lf:7041 에서 실제로 컬럼 도메인을 바꾸는 반복 + `is_domain_resolved=false` 로 남는 튜플 · S-15 `qfile_unify_types` lf:910~921 VARIABLE 채택 · S-16 lf:4505 · S-17 qx:21176 · S-18 qx:21223 · S-19 qx:23130 · S-20 `resolve_domains_on_list_scan` sm:8216 진입 · S-21 qx:17975 · S-22 hj:1015 | **0** |
| `Num_domain_resolve_agg` | 집계·분석 누산기 도메인을 첫 값에서 결정하거나 행마다 값 coerce | S-23 `qexec_resolve_domains_for_aggregation` qx:21504 호출(`*resolved==0` 재호출도 각각) · S-26 qa:3343 · S-27 qn:188~259 첫값 확정 + qn:284~292 행당 coerce · S-28 qn:683 · S-29 빠른 경로 차단 판정(`opr_dbtype VARIABLE || collation_flag` 참) | **0** |
| `Num_domain_key_coerce` | 인덱스 키를 range 마다 값 도메인으로 다시 정하거나 폴백 비교 | S-30 `scan_dbvals_to_midxkey` sm:1871: `tp_value_coerce_strict` 실패/불일치로 **값 도메인 setdomain 을 새로 만드는** 분기(sm:2251) + `retry` sm:2079 · S-31 sm:612/629 · S-32 bt:22282~22320 NULL 컬럼 채움 · S-12 `btree_compare_key` bt:22095~22119 `tp_value_compare_with_error` 폴백 | **0** (바인드 불변 키의 1회 변환은 `Num_domain_gate_convert` 로 잡힘) |
| `Num_domain_px_resolve` | PX 워커가 도메인을 결정·역전파 | S-34 px:926 · px:2145 · pxs:1977 · S-35 px:2683~2687 복사 분기 · S-36 px:1655/1750/1979/2000 폴백 · S-37 `update_domains_on_type_list_by_val_list` px:58 이 도메인을 바꾼 컬럼 수 | **0** |
| `Num_domain_restore_clone` | 실행 종료 시 `domain = original_domain` / `opr_dbtype = original_opr_dbtype` 원복 | S-38 qx:1484 · qx:1519 · qx:1773 · qx:2301 · qx:2356 (원본과 다를 때만) | **0** (필드·원복 코드 자체가 삭제됨) |
| `Num_domain_gate_convert` | **새 게이트**가 변환한 값 수 | 게이트(`qexec_execute_query` 가 `xasl_state` 를 만든 직후, aptr 순회 qx:16538 이전) 안에서 값 하나 변환할 때마다 | **= (호스트 변수 수 + auto-param 수) × 실행 횟수**, 즉 실행당 값 1회 |

- 카운터 1~7 은 develop 에서 **> 0** 이어야 정상(계측 자체의 검증), 구현 뒤 셀·CTP sql 전수에서 **0** 이 게이트 조건.
- 카운터 위치는 삭제 대상 코드 안이다 — 구현이 그 코드를 지우면 카운터도 함께 사라지므로, 지우는 커밋에서 "이 지점은 삭제되어 0 이 보장" 을 정적 감사표에 적고 카운터 정의는 남긴다(다른 지점이 되살아나면 다시 잡힌다).

### 4.3 성능 셀 초안 (실측은 구현 뒤 최종 게이트에서, release 빌드, 같은 세션에서 develop 설치본과 dpin 설치본을 번갈아)

데이터: 테이블 `bench_t` 100만 행 — `c_int INT`, `c_big BIGINT`, `c_dbl DOUBLE`, `c_num NUMERIC(15,3)`, `c_str VARCHAR(32)`, `c_chr CHAR(8)`, `c_dt DATETIME`, `c_grp INT (100 값)`; 인덱스 `i_int(c_int)`, `i_str(c_str)`, `i_grp_int(c_grp, c_int)`. 결정적 생성(`INSERT … SELECT` 로 값 = 행번호 함수). 플랜 캐시 워밍 1회 뒤 5회 실행 중앙값(ms), 각 셀은 **바인드 방식 3종**: (L) 리터럴(auto-param 경로), (H=) 컬럼과 같은 타입의 호스트 변수, (H≠) 다른 타입의 호스트 변수(INT 컬럼에 VARCHAR/DOUBLE 바인드, VARCHAR 컬럼에 INT 바인드).

| 셀 | 질의 형태 | 두드리는 지점 | 지표 |
|---|---|---|---|
| P1 스캔·비교 | `SELECT COUNT(*) FROM bench_t WHERE c_int = ?` / `c_str = ?` / `c_num < ?` / `c_dt < ?` (힙 스캔, 인덱스 없는 컬럼 변형 포함) | S-05 S-09 S-10 | ms, `Num_domain_resolve_fetch`, `Num_domain_coerce_compare` |
| P2 산술·함수 | `SELECT SUM(c_int + ?), SUM(c_dbl * ?), COUNT(COALESCE(c_str, ?)), SUM(NVL(c_int, ?))` | S-01 S-03 S-04 | ms, `Num_domain_resolve_fetch` |
| P3 집계·분석 | `SELECT SUM(?), AVG(?), MEDIAN(c_int + ?) FROM bench_t`; `SELECT c_grp, GROUP_CONCAT(?), MAX(c_str) … GROUP BY c_grp`; `SELECT LEAD(c_int, 1, ?) OVER (ORDER BY c_int)` | S-18 S-23 S-26~S-29 | ms, `Num_domain_resolve_agg`, `Num_domain_resolve_list` |
| P4 정렬·top-N | `SELECT c_int + ? AS k FROM bench_t ORDER BY k LIMIT 100`; `… GROUP BY c_grp ORDER BY SUM(c_int * ?)` | S-11 S-16 S-17 | ms, `Num_domain_resolve_list`, `Num_domain_coerce_compare` |
| P5 키 범위 | `WHERE c_int = ?` / `BETWEEN ? AND ?` (i_int); `WHERE c_grp = ? AND c_int > ?` (복합); 상관 키 `SELECT … FROM bench_t a JOIN bench_t b ON b.c_int = a.c_int + ? WHERE a.c_grp = ?` (외부 행마다 range); ISS `WHERE c_int = ?` 로 i_grp_int 스킵 스캔; MRO `… ORDER BY c_int LIMIT 10` | S-12 S-30 S-31 S-32 | ms, `Num_domain_key_coerce`, `Num_domain_gate_convert` |
| P6 리스트 스캔·집합 | `WHERE c_int IN (SELECT c_grp + ? FROM bench_t WHERE c_grp < 10)`; `SELECT ? UNION ALL SELECT c_int FROM …`; `WITH r AS (SELECT c_int + ? k FROM bench_t) SELECT COUNT(*) FROM r JOIN bench_t ON k = c_int` | S-13 S-15 S-20 S-22 | ms, `Num_domain_resolve_list` |
| P7 PX | P1·P3 을 `parallelism=24`(캠페인 conf) 와 `parallelism=0` 두 값으로 | S-34~S-37 S-39 | ms, `Num_domain_px_resolve`, 워커 수 대비 `Num_domain_gate_convert` 가 늘지 않는지 |
| P8 다중 행 VALUES | `INSERT INTO bench_t2 VALUES (?,?),(?,?),…` 1000 행 배치 ×100 | S-06 | ms, `Num_domain_resolve_fetch` |

- 클라이언트: JDBC(`<prefix>/jdbc/cubrid_jdbc.jar`, 호스트 java 1.8) 로 `PreparedStatement` 바인드; 하네스 소스는 측정 티켓에서 툴링 리포 `.git_ignored_dir/scratch/dpin/bench/` 에 두고, 셀 정의·결과표는 `docs/research/` 문서로 기록한다. csql 은 호스트 변수 바인드가 없어 (L) 변형 전용.
- 각 셀 실행 직전 `SET @collect_exec_stats = 1`, 직후 `SHOW EXEC STATISTICS ALL` 로 카운터를 뽑아 ms 와 같은 표에 적는다(카운터는 optdebug·release 어디서나 같은 값이어야 한다 — 다르면 빌드별 코드 경로 차이 = 조사 대상).
- 성능 판정 기준(초안, 최종 게이트 티켓이 확정): 어떤 셀도 develop 대비 **+5% 이상 느려지지 않고**, (H≠) 변형은 (H=) 와 같은 플랜·같은 카운터 0 을 보인다.

## 5. 잔여·다음 티켓으로 넘기는 것

- 카운터 실제 삽입(4.2)과 하네스·데이터 생성 스크립트(4.3)는 아키텍처(#318)·인터페이스(#323) 잠금 뒤 구현 슬라이스의 첫 커밋(계측 커밋, D-316-2)에서.
- shell known-flaky 2건(§3)은 최종 게이트 티켓의 shell 판정에서 제외 목록으로 인용.
