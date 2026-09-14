# cas-merge 브랜치/커밋별 sysbench(CCI) 측정 자료

workspace [#267](https://github.com/xmilex-git/workspace/issues/267) 산출물. 이후 다른 브랜치·커밋을 재면 §4 표에 행을 추가한다(runbook: 툴링 리포 `.git_ignored_dir/scratch/wf-poc/sysbench/runbook.md`).

## 1. 목적

YCSB(JDBC)로 잰 [중간 스택 ×2.17](https://github.com/xmilex-git/workspace/issues/253#issuecomment-5634090357)이 QA 회귀가 실제로 쓰는 sysbench 1.0.17 + CCI(`libcascci`) 경로에서도 같은 방향을 가리키는지 확인한다. 측정만 하며 제품 변경은 없다.

## 2. 대상·조건 (2026-09-14)

| 항목 | 값 |
|---|---|
| 비교 쌍 | stack `poc/stack` `ad795c5fc`(cas-merge 기준 `d533969e4` + PoC 6커밋) = `CUBRID-wf-poc-stack` vs develop `a7a1db84b` = `CUBRID-wf-poc-develop`. 설치본은 #253/#255 것을 재사용(재빌드 없음). `cub_server` sha256 stack `8d16c756…5707211` / develop `9d4d13d6…5443097` |
| 하네스 | `cubrid-perftools-internal/sysbench/sysbench`(1.0.17, perftools `99e0703`)를 설치본마다 복사·빌드(`--without-mysql --with-cubrid=$CUBRID`). `bin/sysbench` sha256 develop `25067d09…`, stack `19e1f28d…`; 각각 자기 설치본의 `libcascci.so.11.3`에 링크(ldd 확인). 소스 변경 1건: `drv_cubrid.c`의 upstream 스위치 `ADD_CAS_ERROR_HEADER=1`(설치본은 `broker_cas_error.h`만 배포; 오류 코드 동일) |
| 워크로드 | `oltp_read_only.lua`, `oltp_read_write.lua`; `--threads=100 --time=300 --events=0 --cubrid-isolation-level=4 --report-interval=10`; 레그당 1회, warmup 없음 |
| DB | 20 × 1,000,000, `--create_secondary=on`; golden `sbtest_g`는 develop 설치본으로 1회 로드(`prepare --threads=20`, 205 s, 25 GB; `qa_load.inf` 동봉), 레그마다 develop의 `copydb` → `sbtest` |
| conf | 소스 트리 기본 conf + QA 자동화 항목(`data_buffer_size=4G`, `log_buffer_size=2G`, `vacuum_worker_count=50`, `max_clients=500`) + `cubrid_port_id=1523`; broker `BROKER_PORT=33000`, `MIN/MAX_NUM_APPL_SERVER=120`, `SQL_LOG=OFF`, query_editor OFF; stack만 `DIRECT_HANDOFF=ON`. 체크포인트 파라미터 기본값. 레그마다 assert·sha256 기록(cubrid.conf `4a8c7baa…` 공통, broker develop `a20fb04a…` / stack `c40e371f…`) |
| 게이트 | SMT OFF(nproc 32) 통과, 유휴 게이트 loadavg1 < 10(#255 D10). 경로 검증: develop = cub_cas 120 BUSY, stack = `broker status -f` HANDOFFS 0→100(연결당 1회), SLOTS 100/120, cub_cas 0 |

### QA 일일 회귀와 다른 점

| 항목 | QA 일일 회귀 (`config_dailyqa.properties`, README §7) | 이 측정 | 이유 |
|---|---|---|---|
| 배치 | sysbench / 브로커 / 서버 3대 분리 | 한 컨테이너(32 CPU, SMT OFF)에 셋 다 | 이 호스트만 사용 가능 |
| 테이블 × 행 | 20 × 10,000,000 | 20 × 1,000,000 (25 GB, 인덱스 포함) | IO 바운드 구성은 컨테이너 스토리지 잡음이 지배; 로드 수 시간 |
| 스레드 / CAS | 300 / 320 | 100 / 120 | YCSB ×2.17과 같은 동시성 |
| 실행 시간 | 3600 s × 1 | 300 s × 1 | 4레그 합 20분 |
| `SQL_LOG` | 기본값(ON) | OFF | CAS SQL 로그 쓰기 비용 제거 |
| `DIRECT_HANDOFF` | 없음 | stack만 ON | 측정 대상 기능 |
| `cubrid_port_id` | 기본값 | 1523 | 호스트 포트 레지스트리 |
| `--report-interval` | 없음 | 10 | 시계열 기록용 |
| broker conf 편집 | `Test.java`가 `[%BROKER1]`부터 끝까지 삭제 후 query_editor 절에 키 추가 | BROKER1 제자리 편집, query_editor OFF | 같은 단일 브로커 구성, diff가 명확 |
| 수집 | cubrid_monitor·qahome 업로드 | 로컬 결과 파일만 | — |

같은 것: sysbench 1.0.17 + CCI, `oltp_*.lua` 원본, `--create_secondary=on`, isolation 4, warmup 없음, 버퍼·vacuum·max_clients, createdb+addvoldb(data 10G / index 2G / temp 2G), 체크포인트 기본값.

## 3. 결과 (N=1, MAD 없음)

| 워크로드 | 지표 | develop `a7a1db84b` | stack `ad795c5fc` | stack/develop |
|---|---|---|---|---|
| RO | tps (ro1, 티켓 순서 레그 — 외부 부하 오염 §5) | 8,461.58 | 8,861.82 | ×1.047 |
| RO | qps (ro1) | 126,923.72 | 132,927.23 | ×1.047 |
| RO | latency avg / p95 / max ms (ro1) | 11.81 / 14.73 / 44.73 | 11.27 / 22.28 / 155.75 | — |
| **RO** | **tps (stack ro2, 깨끗한 레그)** | 8,461.58 | **16,067.34** | **×1.899** |
| RO | qps (ro2) | 126,923.72 | 241,010.07 | ×1.899 |
| RO | latency avg / p95 / max ms (ro2) | 11.81 / 14.73 / 44.73 | 6.22 / 7.98 / 44.42 | — |
| RO | tps (stack ro2diag, 진단 레그 — 오염 §5) | | 9,265.15 | ×1.095 |
| RO | errors / reconnects / checkpoints | 0 / 0 / 0 | 0 / 0 / 0 (ro1·ro2) | |
| RW | tps | 5,167.36 | 8,774.84 | **×1.698** |
| RW | qps (read/write/other) | 98,182.59 (21.7M/6.2M/1.55M) | 166,766.21 (36.9M/10.5M/2.64M) | ×1.699 |
| RW | latency avg / p95 / max ms | 19.35 / 30.26 / 66.21 | 11.38 / 21.11 / 94.51 | — |
| RW | ignored errors(-670 unique 위반, sysbench 정상) / reconnects / checkpoints | 49 / 0 / 4 | 782 / 0 / 6 | |

레그 시각(KST)·loadavg1(전→후): develop RO 16:32 2.35→103, stack RO 16:54 2.92→136, develop RW 17:07 1.18→93, stack RW 17:19 1.69→74. loadavg 상승은 자체 부하(100 스레드 + 120 CAS + 서버, 32 CPU)이며 호스트 샘플러(`hostmon.log`, RW 두 레그 커버)에서 다른 테넌트의 CPU 사용은 없었다.

10 s tps 시계열:

- develop RO: 8323 8381 8568 8500 8662 8620 8400 8507 8553 8467 8563 8548 7878 8190 8498 8531 8422 8535 8555 8532 8412 8498 8285 8415 8455 8472 8504 8617 8522 8456
- **stack RO**: 14400 14870 15008 13859 15072 15110 15482 14200 **9088 6009** 5874 6381 6404 6249 5872 5819 4124 4172 4383 5465 12227 10852 7804 6722 6985 6516 6410 6957 6924 6862
- develop RW: 5322 4920 5105 5398 5133 5278 5359 5341 5317 5260 5261 5243 5243 5248 5297 5289 5212 5123 5345 5244 5336 5282 4782 4783 5207 4752 4789 5036 5327 4806
- **stack RO ro2** (17:29, 깨끗): 15497 15828 15982 15991 16095 16024 16034 16090 16129 16168 16181 16105 16082 16103 16014 16110 16144 16159 16131 16145 16209 16148 16139 16155 16125 16103 15898 16166 16165 16167
- stack RO ro2diag (17:39, 진단): 11697 11892 11748 10871 8720 **5832** 6358 6323 6461 6122 6098 6428 5918 5605 5755 5811 7485 **11363** 10996 11223 11387 11108 11310 11407 11551 11478 11716 11836 11848 11763
- stack RW: 9336 9360 9205 9035 9126 8801 9096 9323 9022 8928 9065 8878 8965 9044 8899 8912 8693 8830 8816 8350 8421 8471 8583 8499 8334 8494 8158 8389 8459 8108

### 해석 — YCSB와 나란히

| | YCSB(JDBC, #253/#255) | sysbench(CCI, 이 문서) |
|---|---|---|
| 읽기 | C 203,566 vs 93,883 = **×2.17** (20M ops ≈ 100 s) | RO **×1.90**(ro2, 16,067 vs 8,462 tps, p95 7.98 vs 14.73 ms, 300 s 평탄). ro1은 첫 80 s ×1.75 뒤 외부 부하로 붕괴(평균 ×1.05) |
| 갱신 | A 31,185 vs 27,726 = +12.5 % | RW **×1.70**, 300 s 내내 안정(9.3k→8.1k 완만 감소) |

- CCI 경로도 핸드오프 스택이 같은 방향(빠름)을 가리킨다: RO ×1.90, RW ×1.70. RW 이득이 YCSB A(+12.5 %)보다 크고 RO 이득은 YCSB C(×2.17)보다 조금 작다 — 워크로드(sysbench RO는 트랜잭션당 14 쿼리, range·sum·order·distinct 포함, RW는 갱신 4종)와 드라이버가 다르므로 배율 자체를 맞출 이유는 없다. stack RO p95 7.98 ms vs develop 14.73 ms, RW 21.1 vs 30.3 ms.
- stack RO 세 번 중 두 번(ro1, ro2diag)이 실행 도중 tps 절반으로 붕괴했다가 회복했다. §5의 진단 결과 **같은 물리 호스트의 다른 테넌트 CPU 부하**이며 스택 결함이 아니다. ro1은 티켓 순서상의 레그이므로 표에 남기되, RO 비교값은 깨끗한 ro2를 쓴다(N=1 규칙은 유지: ro2는 "레그 1회"의 재실행이 아니라 오염 레그의 대체이며 셋 다 공개).

## 4. 브랜치/커밋별 sysbench 측정 이력

| 날짜 | 브랜치 / sha | 설치본 | RO tps | RW tps | 조건 | 비고 |
|---|---|---|---|---|---|---|
| 2026-09-14 | develop `a7a1db84b` | `CUBRID-wf-poc-develop` | 8,461.58 | 5,167.36 | §2 | 전통 CAS 120 |
| 2026-09-14 | `poc/stack` `ad795c5fc` | `CUBRID-wf-poc-stack` | **16,067.34** (ro2; ro1 8,861.82·ro2diag 9,265.15는 외부 부하 오염) | 8,774.84 | §2, `DIRECT_HANDOFF=ON` | RO 붕괴 원인 §5 |

## 5. stack RO 붕괴 진단 — 외부 테넌트 CPU 부하

ro1(16:54)의 붕괴가 ro2(17:29)에서는 재현되지 않았고, 진단 레그 ro2diag(17:39, `35_diag_leg.sh`: `statdump -i 10` + cub_server RSS/스레드 10 s 샘플 + perf 15 s × 2)에서 t≈50–170 s에 재현됐다(11,800 → 5,600–6,500 → 11,400 tps).

| 관찰 | 빠른 구간(t≈30–45 s) | 느린 구간(t≈120–165 s) | 뜻 |
|---|---|---|---|
| statdump 10 s 델타 | fetch 51.1M, ioreads 5,102, selects 1.53M, lock waits 0 | fetch 30.2M, ioreads 1,053, selects 0.91M, lock waits 0 | 서버 내부 병목 없음 — 모든 지표가 tps에 비례해 줄었을 뿐(plan cache 100 % hit 양쪽) |
| cub_server 스레드 상태 | R 83–89 / S 240 | R 72–86 / S 243 | 대기 증가 없음 |
| cub_server RSS | 6.9 GB | 7.1 GB | 단조 증가(버퍼 채움), 붕괴 시점과 무관 |
| **perf 샘플(cycles, 15 s, -F 199)** | **68K, 1,235 G cycles** | **34K, 677 G cycles** | **서버가 받은 CPU 사이클이 절반** — 프로파일 형태는 동일(libcubrid 73→67 %, kernel 17→21 %, 상위 심볼 같은 순서, 새 핫스팟 없음) |
| 호스트(`hostmon.log`) | busy 99.4 % | busy **100.0 %**, 우리 프로세스 비중 하락, pid 네임스페이스 안의 다른 프로세스 없음 | CPU를 가져간 주체가 이 컨테이너 밖에 있음 |

이 "호스트"는 공유 물리 머신 위의 podman 컨테이너이고 `/proc/stat`·loadavg는 호스트 전체 값이라(#244 runbook D3), 다른 테넌트의 CPU 사용은 우리 `ps`에 보이지 않는다. 사후 보강한 샘플러(cgroup `cpuacct.usage` 대비 호스트 busy)는 17:50:47에 "호스트 busy 34.9 %, 이 컨테이너 0.4 %"의 외부 버스트를 바로 잡았다. 결론: **붕괴는 외부 테넌트의 CPU 경쟁이며 스택 결함이 아니다.** develop 레그와 stack RW·ro2가 평탄한 것은 그 시간대에 외부 부하가 없었기 때문이다. 앞으로의 RO/CPU 바운드 레그는 D14(runbook) 규칙으로 오염 여부를 판정한다.

## 6. 사건·결정 기록

- D6 `ADD_CAS_ERROR_HEADER=1`(빌드 복사본만). D7 golden 쓰기 보호 없음(`copydb`가 원본 볼륨을 rw로 연다). D10 `copydb`는 항상 develop 바이너리. D11 레그마다 `broker status -f` 20 s 샘플.
- 16:26 develop RO 1차 시도: 270 s까지 정상(8,082–8,743 tps) 후 CAS 4개가 100 ms 안에 서버 연결을 닫고 sysbench가 CCI -20004로 중단(exit 1). 코어·dmesg·CAS .err 없음, psize ≈26 MB(Linux 기본 재시작 한도 = 시작 크기 ×10, 유휴 CAS ≈10 MB). 재실행은 300 s 완주·CAS 재시작 0 → 1회성으로 기록, 원인 미확정(`results/develop/ro0_abort_defaultconf/`).
- stack RO 경로 검증이 처음 `PATH_FAIL`로 나온 것은 `broker status -b`에 HANDOFFS 필드가 없어서 생긴 파서 오탐. `-f` 증거로 PATH_OK 재분류, 스크립트 수정.
- stack 기동 시 서버 `.err`에 `-380 Dynamic loader already initialized` 99줄(연결 100개 기동 직후 0.6 s, 워크로드 중 0건) — develop에는 없음. stack 전용 기동 잡음, 기능 영향 없음(기록).
- stack RW 정지: 17:24:35 시작된 체크포인트(216,055 페이지)가 17:28:03에 끝난 뒤 DOWN. 래퍼 120 s 타임아웃만 초과(행 아님). develop RW는 즉시 정지.

원자료: 툴링 리포 `.git_ignored_dir/scratch/wf-poc/sysbench/results/{develop,stack}/{ro1,rw1}/`, `stack/{ro2,ro2diag}/`(statdump·srv_samples·perf 포함), `logs/hostmon.log` (`run.log`, `leg.log`, `bstat/`, 적용 conf 전문·sha256, 서버 `.err` 복사본).
