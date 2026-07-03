# 다음 세션 프롬프트 — CUBRID temp-workmem #78 Phase2: 2A-1b SORT 회귀 진단/프로파일링

> 이 파일 전체를 다음 세션 첫 입력으로 붙여넣으세요. 자체 완결형입니다.

## 0. 너의 역할 / 권위 순서
CUBRID temp-workmem 재설계(#73)의 Phase2 producer 이주(#78) 리더(opus xhigh)다. **구현 슬라이스는 executor subagent에 bounded 위임**하고, 리더는 설계/grounding/통합/검증/거버넌스만 맡는다(토큰 관리).

권위 순서(절대): **SSOT(#75 = `~/dev/workspace/temp_workmem/issue65_ssot.md`) > ADR 0001–0006 > tape-model.md > plan(`~/dev/workspace/issue78_plan.md`)**. 용어=CONTEXT.md(PostgreSQL canonical).
- **먼저 읽을 것(필수)**: `issue65_ssot.md`(특히 §0 P1–P6 금지사항, §6 게이트 방법론), `issue65_evidence.md`(특히 **I-16**=2A-1b 착지+gotcha, **I-17**=이번 회귀 진단), `issue65_handoff.md`, ADR0006, tape-model.md.
- **🔴 GitHub 이슈 SSOT/evidence를 무조건 먼저 참고(권위 우선)**: 로컬 `.md`는 미러일 뿐, **정본은 GitHub 이슈**다. `gh issue view <n> --repo xmilex-git/cubrid --comments`로 반드시 읽을 것:
  - **#75 [SSOT]** (OPEN) — 단일 진실원. 최신 heavy-gate 방법론/회귀 요약 코멘트 포함.
  - **#65 [perf/heavy-gate]** (CLOSED이나 정본 perf 근거) — 대표-4 perf 표 + heavy-spill 정렬/distinct 근본원인 + **이번 heavy-gate 회귀 측정표**(2026-06-30 코멘트).
  - **#78** (OPEN, 현재 작업) — producer 이주 진행/정정 코멘트.
  - heavy gate 관련 결정·측정은 **반드시 #65·#75 코멘트를 정본으로** 대조하고, 새 측정/프로파일 결과도 해당 이슈에 코멘트로 업데이트할 것.
- **§0 P1–P6 contamination 절대 재도입 금지**: correctness-done/perf-only; dirty-flush 방안E; force membuf==NULL real-VPID connect; raw-fd-single-overflow revival.

## 1. 지금까지 구현된 것 (2A-1b CORE — DONE, env-gated)
브랜치 `wm-integ-7173-develop` (repo `/home/cubrid/dev/cubrid-workmem`), **HEAD=`eb5d7e211`**. push 완료(remote=`xmilex`). 커밋 3개:
| 커밋 | 내용 |
|---|---|
| `7e5cb0504` | ① overflow-on-NEW producer stamping (ADR0006) — `qfile_producer_add_overflow_tuple` |
| `1b75074be` | ② serial SORT 출력→NEW (`qfile_list_make_new_backed`, env `CUBRID_WM_SORT_NEW` 기본 OFF) |
| `eb5d7e211` | ③ parallel SORT per-worker NEW + fan-in `qfile_tapeset_import` |
변경 파일: `src/query/list_file.{c,h}`, `src/query/qfile_tape.{cpp,hpp}`, `src/storage/external_sort.c`.
환경게이트: `CUBRID_WM_SORT_NEW`(서버 프로세스 environ, 기본 OFF). do_close=false 정렬(query_aggregate.cpp:1378, query_analytic.cpp:797)은 이주 대상 아님.

## 2. 검증 상태
- **correctness 견고**: debug G1–G18, PRODUCER_SELFTEST(wmg003 TDE + overflow byte-exact), wmloc heavy DISTINCT serial==parallel 동일 + WM_SORT_NEW 로그 8개(병렬 NEW 실증) + no leak, tpch 15M serial==parallel 데이터행 동일. env-off 무회귀(40c47f2e).
- **perf 게이트는 통과한 적 없음** — 아래 3절 참조.

## 3. ⚠️ 핵심 문제 (이번 세션 발견 — 이전 결론 정정)
**`median ≤ develop×1.10` perf 게이트 측정 결과 대실패.** 동일 DB(tpch_sf10)/동일 쿼리(15M DISTINCT spill)/공정 config(512M·parallelism=8·sort 8M, paramdump effective 확인). 결과행 모두 동일(정합성 무결):

| build / path | serial | parallel median |
|---|---|---|
| **develop** (CUBRID-develop-69e73b47) | 9.93s | **4.30s** |
| redesign **OLD** (eb5d7e211 env-OFF) | 16.91s | **15.91s** |
| redesign **NEW** (eb5d7e211 env-ON=2A-1b) | ~17–19s | **~14.07s** |

**진단(매우 중요)**:
1. **회귀는 2A-1b가 원인이 아니다.** redesign 트리는 NEW backing을 **꺼도(env-off)** develop 대비 parallel **~3.7×**(15.91 vs 4.30) 느림 → 회귀는 **redesign 트리 전반(tree-wide)**에 내재. (env-off vs env-on은 동일 빌드 비교라 build-type 독립 → 이 결론은 확정.)
2. **2A-1b NEW는 redesign-OLD보다 ~11% 빠름**(14.07 vs 15.91) — 회귀 무추가, 미세 개선.
3. 이전 세션 "heavy gate PASS"(evidence I-16, #78 코멘트)는 **serial==parallel parity(정합성)만** 확인했고 **develop 대비 perf 비교가 아니었음**. 그 주장은 perf 게이트 통과를 의미하지 않는다(I-17에 정정 기록됨).

**유저 가설(핵심 방향)**: "정합성은 정상인데 느리다 = 어딘가 **불필요한 과정/오버헤드**가 있다." §0 P-history(per-tuple lock / double-spill / membuf-connect 잔재)가 redesign 경로에 살아있을 개연성. **프로파일링으로 hotspot을 특정**해야 한다.

**미해결 confound(반드시 먼저 배제)**: redesign `release` preset = **RelWithDebInfo**. develop-69e73b47의 최적화 수준 미확인. develop이 full Release(-O3/assert off)면 3.7× 중 일부는 빌드 플래그 차이. → **동일 preset로 develop·redesign 재빌드 후 재측정**하거나, develop 빌드 플래그를 확인해 동급인지 검증할 것. (단 "2A-1b 무관"은 이미 확정.)

## 4. heavy gate(perf 게이트) 운영 메모
- 진짜 게이트 = **develop 대비** 비교(이전처럼 serial==parallel parity만 보면 안 됨).
- 재측정 스크립트: `/tmp/wm_median_gate.sh <CUBRID_INSTALL> <WMNEW 0|1> <runs> <label>` (서버 사전 기동 가정; PARALLEL(1)/PARALLEL(8) wall-clock + robust 집계행 출력). 필요시 재사용/개선.
- 하네스(untracked, **수정·커밋 금지, 실행만**): `/home/cubrid/dev/cubrid-workmem/bench/harness/`. `run_3way.sh <a|b|c|positioned> <baseline|asbuilt|redesign>`, develop band은 `baselines/baseline.bands.tsv`(develop @c08453968). 단 harness `B_parallel_sort`는 group-by+소형 order-by라 **대형 external-sort spill을 안 탐** → SORT 회귀 게이트엔 부적합. 대형 DISTINCT/ORDER BY(15M+)로 측정할 것. `RESULTS_DIR=/tmp/...`로 돌려 harness results/ 오염 회피.
- develop release install: `/home/cubrid/release/CUBRID-develop-69e73b47` (NEW 심볼 없음=순수 develop). 또 `/home/cubrid/release/CUBRID-develop-rel`도 있음.

## 5. 🔬 VTune Profiler (병목 측정 도구)
- 설치: **`/opt/intel/oneapi/vtune/latest/bin64/vtune`** (Intel VTune 2025.0.1). env: `source /opt/intel/oneapi/vtune/latest/env/vars.sh`.
- 권장 사용: 대형 parallel DISTINCT 쿼리 실행 중 `cub_server` 프로세스를 attach-profiling.
  - hotspots: `vtune -collect hotspots -target-pid <cub_server_pid> -d <초> -r /tmp/vt_redesign_new` (쿼리 실행 타이밍에 맞춰). 또는 `-collect threading`로 lock/대기 분석(per-tuple lock 가설 검증에 적합).
  - 비교군 3개를 각각 수집: ① develop, ② redesign env-OFF(OLD), ③ redesign env-ON(NEW). develop↔redesign-OLD 핫스팟 diff가 tree-wide 회귀의 정체를 드러낼 것.
  - 결과(`-r` 디렉터리)는 `vtune -report hotspots -r <dir>`로 텍스트화 가능, 또는 `*.vtune`/디렉터리를 GUI로 열 수 있게 보존.
- RelWithDebInfo라 심볼/라인 정보 있음(프로파일에 함수/라인 보임).

## 6. SSOT / evidence 고려
- **evidence는 사실 변경 시 자유롭게 APPEND**. 이번 I-17(회귀 진단)이 최신 기준. 새 측정/프로파일 결과는 I-18+로 추가.
- **SSOT는 실제 사실 변경 + 유저 허락 시에만 편집**. §6 게이트 방법론에 "perf 게이트=develop 대비 비교(parity만으론 불충분)" 명확화가 필요하면 유저 허락 받고 반영. §0 금지사항은 건드리지 말 것.
- 이전 #78 코멘트의 perf 뉘앙스는 정정 코멘트로 보강됨(이번 세션). audit trail 유지: substep마다 commit(#78 & #73 인용)→push(xmilex)→#78 코멘트→ledger 체크포인트.

## 7. 다음 단계 (유저 지정 — 이 순서로)
1. **VTune으로 병목 측정.** (confound 먼저 배제: develop 빌드 타입 확인/동급 재빌드 → 그 다음 develop / redesign-OLD / redesign-NEW 3종 프로파일 수집. 대형 parallel DISTINCT spill 워크로드 사용.)
2. **VTune 결과를 유저가 볼 수 있게 올려주기 (vtune 자체 웹 인터페이스 기능 사용)** + **에이전트도 내용 분석**. (report 텍스트화 + 핫스팟/lock-wait diff 정리. 결과 디렉터리/리포트를 공유 가능한 위치에 보존하고 경로 안내.)
3. **분석 결과 기반으로 "뭐가 문제인지" 유저와 토론 후 스펙 정하기 — `/skill:deep-interview` 활용.** (불필요 과정/오버헤드의 정체와 제거 방안을 스펙화. deep-interview는 요구사항 워크플로라 product code 수정 금지·`.gjc/specs/` 산출.)
- 그 이후(deep-interview 뒤) 방향은 **유저가 판단**한다. 임의로 구현 진행하지 말 것.

## 8. 운영 정보 (gotchas)
- **빌드**: `WORKSPACE=/home/cubrid/dev/cubrid-workmem just build debug|release` (cwd `/home/cubrid/dev/workspace`). release→`~/release/CUBRID-11.5.develop`, `~/CUBRID` repoint. **빌드는 conf 전체를 wipe** → 매 빌드 후 `stored_procedure=no`, `parallelism=8`/`max_parallel_workers=8`/`work_mem=8M`/`data_buffer_size=512M` 재적용. (주의: 재설계는 `sort_buffer_size`를 **제거**하고 `work_mem`으로 rename함 — sort_buffer_size 쓰면 startup 실패.) (절대 증분빌드된 바이너리로 테스트하지말것, 풀 빌드된 바이너리만 성능/각종 테스트에 활용할것!!!!!)
- **심볼 확인**: query 코드(qfile_*)는 thin `cub_server` 실행파일이 아니라 **`lib/libcubrid.so` / `libcubridsa.so`**에 있음. NEW 빌드 검증은 `nm libcubrid.so | grep qfile_tapeset_import` 등으로.
- **서버 lifecycle는 래퍼로만**: `/home/cubrid/dev/workspace/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh <start|stop|restart|status> <db>` (CUBRID env로 install 선택). **binary 전환시(release↔develop) stale cub_master/cub_server를 `pkill -9`로 정리 후 start** (공유메모리/포트 충돌 회피).
- **NEW 경로 판별**: 결정은 **서버 프로세스 environ**의 `CUBRID_WM_SORT_NEW`로(클라이언트 env 아님). 서버 start 시점에 env가 들어가 있어야 NEW. `tr '\0' '\n' </proc/<pid>/environ | grep WM_SORT_NEW`로 확인. (release는 `er_log_debug` WM_SORT_NEW 로그가 기본 안 뜸 → environ+결정성으로 판별.)
- **DB**: tpch_sf10(heavy, ~/databases; orders 15M), wmg003(TDE), wmloc(table t, 4.19M ints). `CUBRID_DATABASES=/home/cubrid/databases`. canonical databases.txt=`/home/cubrid/databases/databases.txt`.
- **selftest**: `CUBRID_PRODUCER_SELFTEST=1 csql -S -u dba <db> -c "SELECT 1 FROM db_root;"` (SA, query_manager.c:1195 게이트). resource-leak/crash는 **CS 서버 per-request에서만** 검출(SA selftest 아님).
- **golden 쿼리/값**: 위 15M DISTINCT → `15000000 / 449999872500000 / 1 / 60000000`. wmloc DISTINCT → `4194304/8796090925056/0/4194303`. ORDER BY는 옵티마이저가 drop할 수 있으니 SORT 강제엔 DISTINCT/ROWNUM/LAG 사용.
- **건드리지 말 것**: `m cubrid-cci` 서브모듈, untracked `bench/harness`/results.

## 9. ultragoal
이전 세션 ledger=`/home/cubrid/dev/workspace/.gjc/_session-019f179d-43aa-7000-bbeb-3517b5f53f54/ultragoal/`(G001 active, 회귀 진단 annotate됨, paused). 새 세션은 자체 ultragoal로 시작하거나 이 ledger를 참조. **G001은 perf-blocked**(correctness done, perf 회귀=tree-wide redesign 이슈, 2A-1b 무관). G002–G005(2A-2 pre-agg / 2A-3 hash join / 2A-4 inventory / 2A-EXIT)는 perf 회귀 방향 정해진 뒤 진행 권장.
