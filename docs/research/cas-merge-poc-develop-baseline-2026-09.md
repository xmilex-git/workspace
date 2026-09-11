# develop(기존 CAS 구조) 기준선 — YCSB C×3·A×3 + 전체 프로세스 PSS 메모리 100/1,000 (2026-09-11)

workspace [#255](https://github.com/xmilex-git/workspace/issues/255) 산출물. 절차는 [develop 성능 재측정 가이드](develop-baseline-remeasure-guide-2026-09.md)를
[#244 runbook](cas-merge-poc-baseline-2026-09.md)(같은 호스트·하네스·JDBC·golden DB·conf·SMT OFF) 위에 적용했다.
**"develop 대비" 수치를 말하는 모든 티켓(#253 처분표·#237 메모리 예산·#221 JIRA S22/S25)은 이 문서의 표를 인용한다.**

## 1. 조건

| 항목 | 값 |
|---|---|
| develop sha | `a7a1db84b8b27c26ab673f7fcbe316f35eb8f9e1` (`origin/develop` tip 2026-09-11 13:15 KST, "[APIS-1107] Update cubrid-jdbc submodule to 20aeb34 (#7912)"), dirty diff 없음 |
| cas-merge 기준(#244)과의 관계 | 기준 `d533969e4`와 merge-base `14d21ef51`, develop이 **17커밋 앞섬** → develop↔cas-merge 비율은 "두 빌드 간 비교"이며 순수 통합 효과가 아님 |
| 빌드 | fresh `release` preset = **RelWithDebInfo** (`-O2 -g -DNDEBUG`, ccache gcc), `cubrid_rel` = `CUBRID 11.5.0 (11.5.0.2560-a7a1db8)`; 설치 `/home/cubrid/release/CUBRID-wf-poc-develop`, 워크트리 `~/dev/worktrees/wf-poc-develop` |
| sha256 | `libcubrid.so.11.5` `98a8a82e…a11d33` · `cub_server` `9d4d13d6…443097` · `cub_cas` `1968946d…0bbcb` · `cub_broker` `d324851b…31bf176` (전문 `results/develop/env/install-sha256.txt`) |
| JDBC | `cubrid-jdbc-11.4.0.0076.jar` sha256 `3e876fb1…f564` — #244와 **동일 파일** |
| YCSB | `~/dev/cubrid-perftools-internal/ycsb/ycsb` @ `99e07035fb63…d83`(com.yahoo.ycsb 0.4.0), `run.sh` 경로 #244와 동일, `jdbc.cachestatements` 패치 없음(grep 0건 = 기본 캐시 사용), threads=100, zipfian, recordcount 10M, operationcount 20M, `maxexecutiontime=1800`, warmup 없음 |
| 호스트 | 공유 물리 머신 위 podman 컨테이너(`container-other`), Rocky 8.10, kernel 6.9.4, **SMT OFF**(control=off, active=0, online 0-31, nproc 32 — 모든 레그 `smt_check.txt` 통과), governor performance, THP always, RAM 188 GiB, swap 32G+128G(사용 7 GiB, 우리 프로세스 아님), DB·설치 `/home`(sdb1, 487 GiB 여유). 전문 `results/develop/env/` |
| 데이터 | golden `ycsb_g`(`/home/cubrid/wf125-ycsb-db`, 10,000,000행, `iso88591_bin`, PK `pk_usertable_ycsb_key`, REUSE_OID) → 매 레그 `copydb` → `/home/cubrid/wf-poc-db/ycsb`. 검증: `COUNT(*)=10000000`, ConnHold `TEST_KEY` 1행 |
| conf | #244 `cubrid.conf`(4G/2G, vacuum 50, max_clients 200, neighbor_flush 0, port 1523, checkpoint 256G/120min) 축자. 브로커 = #244 conf에서 **`DIRECT_HANDOFF` 제거만**(develop에 없는 파라미터): `cubrid_broker.conf.develop.100` sha256 `38566c56…`, `.1000`(max_clients 1100, MIN/MAX_NUM_APPL_SERVER 1100) `0aa4e026…`. `20_apply_conf.sh`가 DIRECT_HANDOFF 부재를 assert |
| 경로 검증 | 100 conf 기동 시 **cub_cas 120개**(`broker1_cub_cas_1..120`) + cub_broker + cub_server; 100 idle JDBC 연결 시 `broker status` `#CONNECT=100`, ERR-Q 0 → JDBC → broker/CAS → server 경로 확인(`results/develop/verify/`) |
| 유휴 게이트 | **D10(사용자 결정 15:00)**: 71분간 host-wide loadavg1이 4 미만으로 내려오지 않아(5~33, 다른 테넌트; 우리 busy 프로세스 0) **loadavg1 < 10에서 시작하면 유효**로 완화. 실제 게이트 통과값은 모두 2.8~3.7이었다(아래 표). #244 레그는 loadavg1 < 4 게이트 |
| 배치 | JDBC 부하 발생기와 DB 같은 컨테이너, localhost:33000 (#244와 동일) |

## 2. 처리량·지연시간 (G1, 20M ops, 회차별 p50=HDR / p99=YCSB summary)

| leg | ops/s | runtime s | READ ops | READ p50 µs | READ p99 µs | UPDATE ops | UPD p50 µs | UPD p99 µs | 오류 | ckpt | loadavg1 게이트→leg 직전→종료 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| c1 | **85,659** | 233.5 | 20,000,000 | 1,025 | 3,619 | – | – | – | 0 | 0 | 2.87 → 27.54¹ → 70.0 |
| c2 | **99,861** | 200.3 | 20,000,000 | 929 | 2,307 | – | – | – | 0 | 0 | 3.55 → 3.84 → 64.7 |
| c3 | **93,883** | 213.0 | 20,000,000 | 980 | 2,569 | – | – | – | 0 | 0 | 2.94 → 3.56 → 67.7 |
| a1 | **31,383** | 637.3 | 9,999,875 | 511 | 2,671 | 10,000,125 | 4,855 | 22,767 | 0 | 0 | 3.73 → 4.38 → 17.6 |
| a2 | **26,240** | 762.2 | 10,003,998 | 521 | 10,487 | 9,996,002 | 5,399 | 25,359 | 0 | 0 | 2.79 → 4.00 → 24.1 |
| a3 | **27,726** | 721.4 | 9,997,937 | 555 | 4,843 | 10,002,063 | 5,207 | 24,959 | 0 | 0 | 3.25 → 7.34 → 12.1 |

¹ c1의 "leg 직전" 값은 게이트 통과(2.87) 뒤 copydb(47 s)·서버 기동을 거친 시점의 1분 loadavg다. c1이 3회 중 최저치라 부하 개입 가능성을 배제하지 않지만 20M 완료·오류 0·checkpoint 0으로 유효하며 삭제하지 않는다.
모든 레그: Java 정상 종료, `Return=0`만 존재(비정상 반환 0), READ+UPDATE = 20,000,000, `*.hdr` 존재, checkpoint 0, SMT OFF 유지.

| WL | 개별 3회 ops/s | **median** | raw MAD | READ p50 / p99 (µs, 회차 median) | UPDATE p50 / p99 (µs) |
|---|---|---|---|---|---|
| C | 85,659 / 99,861 / 93,883 | **93,883** | 5,977 | 980 / 2,569 | N/A |
| A | 31,383 / 26,240 / 27,726 | **27,726** | 1,486 | 521 / 4,843 | 5,207 / 24,959 |

기준선이므로 MAD 클램프·합격선은 적용하지 않는다(raw MAD만).

## 3. 전체 프로세스 PSS 메모리 (G5, 51_smaps_pss_leg.sh)

포함 범위: 설치본의 **모든 프로세스** = cub_master 1 + cub_server 1 + cub_broker 1 + cub_cas 전부(100 레그 120개, 1,000 레그 1,100개) — snapshot마다 PID 집합 재수집, 100 레그 123 PID·1,000 레그 1,103 PID로 5단계 15 snapshot 전부 완전(누락 0). Java 보유 도구(ConnHold) 제외. 단위 KiB(`/proc/PID/smaps_rollup` kB). stage 값 = snapshot별 합 → 3개 중앙값(10 s 간격).
ConnHold: S2 `connected 100/100`·`1000/1000`, S3 prepared READ+UPDATE 실행·유지, `broker status` `#CONNECT`=N, ERR-Q 0.

### N=100 (max_clients 200, CAS 120)

| 지표 | S1 | S2 idle | S2post | S3 prepared | S5 closed | idle/conn | prepared/conn | S3−S2 | 잔류 S5−S1 | S2post−S1 |
|---|---|---|---|---|---|---|---|---|---|---|
| **전체 PSS 합 (KiB)** | **3,673,541** | 3,769,641 | 3,769,690 | 3,802,150 | 3,800,329 | **961.0** | **1,286.1** | 32,509 | **126,788** (124 MiB) | 96,149 |
| 전체 RSS 합 (참고, 공유 중복) | 4,683,292 | 5,030,736 | 5,030,764 | 5,163,036 | 5,161,204 | 3,474 | 4,797 | 132,300 | 477,912 | 347,472 |
| 서버 RSS (KiB) | 3,365,892 | 3,371,496 | 3,371,524 | 3,376,924 | 3,376,928 | 56.0 | 110.3 | 5,428 | 11,036 | 5,632 |

### N=1,000 (max_clients 1100, CAS 1,100 — S1에 미리 fork된 CAS 비용 포함)

| 지표 | S1 | S2 idle | S2post | S3 prepared | S5 closed | idle/conn | prepared/conn | S3−S2 | 잔류 S5−S1 | S2post−S1 |
|---|---|---|---|---|---|---|---|---|---|---|
| **전체 PSS 합 (KiB)** | **8,859,472** (8,652 MiB) | 9,761,145 | 9,761,172 | 10,041,186 | 10,033,209 | **901.7** | **1,181.7** | 280,041 | **1,173,737** (1,146 MiB) | 901,700 |
| 전체 RSS 합 (참고) | 18,038,200 | 21,467,256 | 21,467,276 | 22,754,300 | 22,746,312 | 3,429 | 4,716 | 1,287,044 | 4,708,112 | 3,429,076 |
| 서버 RSS (KiB) | 6,623,564 | 6,640,896 | 6,640,900 | 6,662,792 | 6,662,796 | 17.3 | 39.2 | 21,896 | 39,232 | 17,336 |

관찰(해석 아님): ① develop의 연결당 증가는 거의 전부 **CAS 프로세스 쪽**(서버 RSS 기울기 56/110 KiB vs 전체 961/1,286 KiB). ② S2post ≈ S2 — idle 연결을 닫아도 CAS가 유지한 메모리는 거의 돌아오지 않는다(KEEP_CONNECTION=AUTO, CAS 상주). ③ 서버 RSS S1이 100 레그 3.37 GiB → 1,000 레그 6.62 GiB: `max_clients` 1100의 서버측 사전 할당(4G data buffer 외) 차이 3.25 GiB — 두 N의 S1 절대량은 conf가 달라 서로 비교하지 않는다. ④ "잔류"는 종료 후 allocator/CAS 상주 잔량이며 leak 단정 근거가 아니다.

## 4. cas-merge 기준(#244)과의 비교 — 같은 장소, 조건 차이 명시

| 항목 | cas-merge `d533969e4` (#244, 09-10, 게이트 <4) | develop `a7a1db84b` (이 문서, 09-11, 게이트 <10·실통과 2.8~3.7) | 비율 cas-merge/develop |
|---|---|---|---|
| C median ops/s (MAD) | 118,374 (1,545) | 93,883 (5,977) | **1.261 (+26.1 %)** |
| C READ p50 / p99 µs | 750 / 2,299 | 980 / 2,569 | −23.5 % / −10.5 % (cas-merge 낮음) |
| A median ops/s (MAD) | 31,423 (24; a3 outlier) · 같은날 재측정 a4ref 28,662(09-11 12:33) | 27,726 (1,486) | **1.133 (+13.3 %)** · a4ref 기준 1.034 (+3.4 %) |
| A READ p50 / p99 µs | 351 / 5,507 | 521 / 4,843 | −32.6 % / **+13.7 %**(cas-merge p99 높음) |
| A UPDATE p50 / p99 µs | 4,687 / 22,927 | 5,207 / 24,959 | −10.0 % / −8.1 % |
| 메모리 | 서버 RSS만(cas-merge는 CAS 없음 → 서버≈전체): 100/1,000 idle/conn 421/401 KiB, prepared 897/829 KiB, 잔류 59/502 MiB | 전체 PSS: idle/conn 961/902 KiB, prepared 1,286/1,182 KiB, 잔류 124/1,146 MiB | **직접 비율 미산출** — 지표(RSS vs PSS)·범위가 다름. #253이 `51_smaps_pss_leg.sh`를 base·stack에 같은 범위로 돌린 뒤 산출 |

비교 한계: ① sha 차이 17커밋(develop 추가 변경) → "두 빌드 간 비교". ② 게이트 기준 4 vs 10(실제 통과값은 모두 4 미만이었으나 규약이 다름). ③ A는 일 단위 드리프트(#249: 같은 시간대 base 28,662 = −8.8 %)가 확인되어 cas-merge A의 절대 우위는 **같은 세션 교차 재측정**(#253)에서 확정한다. ④ 처리량 2배 목표는 제품화 검토 목표일 뿐 이 기준선의 합격선이 아니다.

## 5. 원자료

`/home/cubrid/dev/workspace/.git_ignored_dir/scratch/wf-poc/results/develop/` — `env/`(§3 식별 정보 33파일), `verify/`, `c1..c3`, `a1..a3`(`run.log`, `READ.hdr`/`UPDATE.hdr`, `summary.tsv`, `checkpoints`, `loadavg_*`, `smt_check.txt`, `leg.log`), `smapspss100/`, `smapspss1000/`(`totals.tsv`, `stages.tsv`, `S*-{1,2,3}/<pid>.{smaps_rollup,cmdline,exe}`, `broker_status.S*.txt`, `hold.S*.{out,err}`, `cubrid*.conf`+`conf.sha256`). runbook 결정 D5–D10: `wf-poc/runbook.md`.
