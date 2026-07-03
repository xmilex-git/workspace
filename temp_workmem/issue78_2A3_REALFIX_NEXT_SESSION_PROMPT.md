# NEXT SESSION PROMPT — #78 Phase2 2A-3 REAL FIX (병렬 PHJ 입력-리더 NEW 이주)

CUBRID temp-workmem 재설계(#73) Phase2 producer 이주(#78)의 **2A-3 (parallel hash join)** 를 리더로서 이어서 진행한다. **직전 세션에서 플랜의 bug2 진단이 코드사실로 반증되어 정정되었다** — 이 프롬프트는 그 정정된 스코프로 진짜 수정을 수행한다. 착수 전 아래 필독 문서를 **전부 정독**하고, 명시된 도구·거버넌스·검증·측정 규율을 강제한다.

## ★★★ 0) 착수 전 필독 (권위 순서 — 정독 필수, 건너뛰기 금지) ★★★
권위: **SSOT(#75) > ADR0001–0006 > tape-model.md > plan**. GitHub 이슈가 정본.
1. **SSOT 전문 정독**: `~/dev/workspace/temp_workmem/issue65_ssot.md` — 특히 **§0 오염전제 P1–P6**, §3.2 B1/B2, §5.4 마이그레이션, **round-3 UPDATE (a)(d)(f)**(입력분배 OLD=`sector_page_iterator` ↔ NEW=`chunk_distributor`, backing-kind 입력가드, #77), 그리고 **★round-4 UPDATE (k)(l)(m) (2026-07-01 bug2 원인 정정)** — bug2 는 파티션 write race 가 아니라 **병렬 PHJ 입력-리더(sector) 행유실**이고, 수정은 round-3 (a)/(d)의 입력-리더 sector→chunk 이주다.
2. **evidence 정독**: `~/dev/workspace/temp_workmem/issue65_evidence.md` — 엔트리 **(l)/(m-CORRECTION)**(buggy1=sector 행유실, 측정 confound), **(o)**(2A-3 grounding — 단 bug2 귀속은 (q)로 정정됨), **(p)**(slice-1 착지), **★(q)**(2A-3 정정: bug2=입력 sector-read 행유실, per-worker tape 직교·revert, Invalid XASL crash). I-9(chunk_distributor/no-mixed), I-10(#7173 sector 공통화·21사이트), I-13(2A-0 ADR0005/0006 + backing-kind 가드), I-18(k')(2A-2e tapeset_reader/PRODUCER·TAPEREAD selftest).
3. **정정 스코프 브리프 정독**: `~/dev/workspace/temp_workmem/issue78_2A3_CORRECTED_SCOPE.md` (정밀 좌표·crash lead·correctness↔perf).
4. **ADR**: `docs/adr/0002`(tapeset), `0003`(per-worker private·offset·64page offset-range 분배), `0004`(partition=per-worker tape import — OUTPUT측 perf), `0005`(frozen tape 동시읽기=공유fd+per-reader 스크래치), `0006`(overflow first-page-owner). tape-model.md.
5. **GitHub 정본**: `gh issue view 78 --repo xmilex-git/cubrid --comments` — 최근 코멘트 **`[2A-3 slice-1]`(死코드 착지)** + **`[2A-3 ★정정]`(bug2 진단 정정, comment 4850257401)** 로 현상태 확정. (#73/#75/#65 도.)
6. **착수 전 HEAD `017afa968`에서 좌표 re-ground(`search`/`lsp`) 필수** (라인 드리프트).

## 1) 현재 상태
- repo `/home/cubrid/dev/cubrid-workmem`, 브랜치 `wm-integ-7173-develop`, **HEAD `017afa968`** (slice-1 死코드 제거만; xmilex push 완료). **소스 클린**(직전 세션의 버그 있는 per-worker-tape 이주는 revert 됨).
- 이력: 2A-0~2A-2f/B-ii(`cf936e0c2`) + **slice-1 `017afa968`**(vestigial raw-fd sector-scan 死코드 제거).
- **이번 과제 = 정정된 진짜 bug2 수정** (아래 §2). 직전 세션에 시도한 per-worker OUTPUT tape 이주는 bug2 와 직교 + 자체 레이스라 폐기했다 — **재시도 금지**(그건 perf용 후속 슬라이스).

## 2) 과제: 병렬 PHJ 입력-리더를 sector → chunk_distributor(NEW 입력)로 이주 (bug2/#77 correctness)
### 확정된 근본원인 (직전 세션, gdb·측정)
- bug2(`SELECT /*+ USE_HASH(o,l) PARALLEL(8) */ count(*) FROM orders o, lineitem l WHERE o.o_orderkey=l.l_orderkey AND o.o_orderkey<200000` = golden **200360**)는 **파티션을 하지 않고** `HASHJOIN_STATUS_PARALLEL_PROBE`(단일 해시테이블+병렬 프로브) 경로다.
- 병렬 프로브가 **프로브 입력을 `qfile_open_list_sector_scan`/`sector_page_iterator`로 읽는데(px_hash_join.cpp `probe_execute` ~:611), 이 OLD sector 리더가 임의 파생리스트에서 행 유실**(= buggy1/2A-2c 동일 #7173 sector 결함). 병렬 파티션 split(`split_task::execute`의 `m_page_iter.get_next_page(sector_scan)`)도 동일 리더 → 동일 유실.
- 측정: serial(PARALLEL(1))=정답(200360 / <2M:2000495), 병렬(8)=유실(149510 / 149574), **env-OFF(게이트 무관)도 동일** ⇒ pre-existing. **write측 `part_mutexes`는 mutex 직렬화라 유실 아님** — 그래서 per-worker OUTPUT tape 는 bug2 를 못 고친다.

### 수정 (round-3 (a)/(d) 설계 그대로 — 입력-리더 이주)
병렬 PHJ(프로브 + 파티션 split)의 **입력 읽기**를 `sector_page_iterator` → `chunk_distributor`+`tapeset_reader`(NEW 입력, offset-range, 2A-0/2A-2e 검증된 경로)로 이주. 좌표(re-ground 필수):
- 병렬 프로브 입력: `parallel_query::hash_join::probe_execute`(px_hash_join.cpp) `qfile_open_list_sector_scan(...single_context.probe->list_id...)` + `probe_task` 페이지 순회(px_hash_join_task_manager.cpp).
- 병렬 split 입력: `split_task::execute` `m_page_iter.get_next_page(m_shared_info->sector_scan)`.
- 공통 OLD 리더: `sector_page_iterator`(query_list.h:860 근방) / `qfile_open_list_sector_scan`; NEW = `qfile::chunk_distributor`/`qfile::tapeset_reader`(qfile_tape.hpp/cpp).
- **전제(하드-prereq): PHJ 입력이 NEW-backed 여야 한다.** 현재 `CUBRID_WM_SCAN_NEW=1 CUBRID_WM_SORT_NEW=1`+병렬 PHJ = **서버 crash + `ERROR: Invalid XASL tree node content`**(PHJ가 NEW 입력 미지원). **이 크래시를 먼저 규명**(§3 착수순서 1). 그리고 **hash-join 입력이 SCAN_NEW/SORT_NEW로 실제 NEW-backed가 되는지** gdb로 확인(안 되면 2A-3가 입력을 NEW로 materialize/convert 해야 하는지 설계 결정).
- backing-kind 입력 가드(SSOT round-3 (d), production-hard): OLD sector-scan 진입은 NEW list 거부, chunk_distributor는 OLD list 거부.
- **게이트 `CUBRID_WM_HASHJOIN_NEW`(env, 기본 OFF=byte-identical OLD)**. env-OFF 무회귀.

### 하지 말 것
- **per-worker OUTPUT tape / `part_mutexes` 제거를 bug2 수정으로 재시도 금지** — bug2 와 직교(write는 mutex 직렬화). 그건 ADR0004 perf 후속 슬라이스이며, 직전 시도서 자체 레이스(varying 209198/837199) 있었으니 재구현 시 root-cause 선행.
- §0 P1–P6 오염 재도입 금지.

## 3) 착수 순서
1. 필독(§0) → `gh issue 78` + `git log` 현상태 → 좌표 re-ground.
2. **crash 규명**: debug 빌드로 `CUBRID_WM_SCAN_NEW=1 SORT_NEW=1`+병렬 PHJ 재현 → `Invalid XASL tree node content`(`ER_QPROC_INVALID_XASLNODE`) 스택 확보(gdb/core). lead: 병렬 워커 XASL clone(`src/xasl/xasl_spawner.cpp` :95/:160/:352/:668) 또는 `px_scan_task.cpp` :536/:555. **pre-existing(SCAN_NEW×PHJ) vs 도입 판별.**
3. PHJ 입력이 NEW-backed 가능한지 확정(gdb: `single_context.probe->list_id->tapeset_`/`backing_kind_`). NEW 가능 → 입력-리더 chunk 이주. NEW 불가 → 입력 NEW 변환 설계.
4. **executor 위임**으로 입력-리더 이주 슬라이스 구현(≤3–5파일 + 정확 좌표 + 설계 + "빌드/서버/검증 하지 말 것"). 리더가 union 빌드·검증.
5. 검증 게이트(§5) → 거버넌스(§6).

## 4) 작업 도구·스킬 (최우선 — 위반 금지)
- **구현은 executor subagent 위임(강력 권장).** 리더는 설계/grounding/통합/검증/거버넌스. 다중 독립 슬라이스는 병렬 executor. 리더가 union of changed files 한 번에 빌드·검증.
- **빌드=`cubrid-build` 스킬 `just build`만.** `WORKSPACE=/home/cubrid/dev/cubrid-workmem just build release`(perf/RelWithDebInfo) / `... just build debug`(assert/crash/gdb/selftest/Debug). **raw `cmake --build`/`ctest` 금지. 수동 증분바이너리로 (성능)테스트 금지.** 긴 빌드 background. **`just build`는 `~/CUBRID` repoint** — 필요시 `readlink ~/CUBRID` 먼저. **빌드가 conf wipe → 매 빌드 직후 campaign conf 재적용 필수**: `data_buffer_size=512M, work_mem=8M, parallelism=8, max_parallel_workers=8, stored_procedure=no`.
- **서버 start/stop/restart=`cubrid-server-control` 래퍼만**: `~/dev/workspace/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh {start|stop|restart|status} <db>`. **raw `cubrid server start|stop` 절대 금지**(파이프 hang). binary 전환 시 `pkill -9 cub_server; pkill -9 cub_master` + readiness poll(SELECT 1 반복).
- **cubrid-cci 서브모듈 / untracked `bench/harness/results` 절대 건드리지 말 것.**

## 5) ★측정 규율 + 검증 게이트 (2A-3 EXIT — 전부 통과해야 완료)
- **★게이트는 서버 프로세스 getenv**: `CUBRID_WM_*=1`을 **`cubrid server start` 시점 서버 env**로 줘라(래퍼 호출을 그 env로). **csql 클라이언트 env 무효.** env-isolated: `env -i PATH=$RED/bin:/usr/bin:/bin CUBRID=$RED CUBRID_DATABASES=/home/cubrid/databases`.
- **★재현 confound(직전 세션 교훈)**: 병렬 PHJ 유실은 **세션-상태 의존** — cold separate `csql -c` run 은 200360 나올 수 있고, batched `csql -i` 세션에서 149510 결정적. **반드시 batched + 다회 병행**으로 검증.
- **robust serial==parallel 패리티**(count/sum/min/max, terminal 포함): tpch_sf10 PHJ(golden `<200000`=200360, `<2000000`=2000495) + wmloc. serial(`parallelism=1 AND max_parallel_workers=1`) vs 병렬(8), develop 대조. `;trace on` 의 `parallel workers:N(>1)` 로 병렬 engage 실증(passthrough-tautology 금지, evidence I-11).
- **bug2 결정성**: 병렬 PHJ `<200000` count=**200360** ×여러회(batched 포함).
- **#77 NEW경로 해소**(0-length 튜플 크래시). OLD crash 는 legacy-until-contract.
- 하드 카운터: `pgbuf_fixes`=0(NEW scan), no-mixed=0, backing-kind entry guard 라이브 발화 0, CoV≤15%, **PHJ median≤develop×1.10**, deadlock-free.
- **debug 셀프테스트**(현 HEAD debug 재빌드 후): `env -i ... CUBRID_PRODUCER_SELFTEST=1 CUBRID_TAPEREAD_SELFTEST=1 csql -S -u dba demodb -c "SELECT 1;"` → `*_SELFTEST result=0`. release=RelWithDebInfo(gdb 심볼); NDEBUG crash=silent SIGSEGV → `gdb -p <pid> -batch`.
- **correctness↔perf 상충 인지(SSOT (m))**: 즉효 correctness(OLD입력→serial 강제)는 median≤develop×1.10 미충족. 둘 다 충족 = NEW-입력 chunk 병렬 완성 필요. correctness>perf 상 필요 시 correctness 먼저 착지(단 EXIT 완료는 perf 포함).

## 6) 거버넌스 (슬라이스마다 강제)
각 논리 슬라이스(crash-fix / 입력-리더 이주 / 가드 / 검증)마다: (1) 커밋 1개 — 무엇·왜·**검증 측정치**, 태그 `[temp-workmem PHASE2 2A-3 …] … (#78, #73)`. (2) `git push xmilex HEAD:wm-integ-7173-develop`. (3) `gh issue comment 78 --repo xmilex-git/cubrid` 한글 보고. (4) evidence 엔트리 추가. (5) 실패/오진단은 정정 코멘트+evidence로 정직히 기록(직전 세션 (q) 선례).

## 7) 참조값 / 경로
- installs: develop=`/home/cubrid/release/CUBRID-develop-69e73b47`, redesign(NEW)=`/home/cubrid/release/CUBRID-11.5.develop`, debug=`/home/cubrid/debug/CUBRID-11.5.develop`.
- DB: tpch_sf10·wmloc·wmg003(TDE) in `/home/cubrid/databases`.
- golden: HASHJOIN(o_orderkey<200000) count=**200360**; serial <2000000 count=**2000495**; DISTINCT 15M=`15000000/449999872500000/1/60000000`; wmloc DISTINCT=`4194304/8796090925056/0/4194303`.

## 8) 스타일
- **구현=executor 위임, 리더=설계/검증/거버넌스.** 착수 시 `todo`로 슬라이스 분해 후 하나씩 완료·커밋.
- **HARD-GATE 서브페이즈 = 졸속 금지.** 넓은 robust parity(batched+다회, 10+ operator군) 통과 전 게이트 기본 ON 금지. 직전 세션 최대 교훈: **측정으로 진단을 검증한 뒤 코드를 짜라**(플랜 전제도 틀릴 수 있다 — bug2 오진단 선례).

## 9) 이슈 #78 종료까지 로드맵 (2A-3 이후)
- [ ] **2A-3 REAL** ← 이 프롬프트 (병렬 PHJ 입력-리더 NEW 이주 + crash-fix; bug2/#77 해소)
- [ ] (perf 후속) hash-join 파티션 per-worker OUTPUT tape (ADR0004, part_mutexes 제거) — 레이스 root-cause 후 재구현
- [ ] 2A-4 인벤토리 A~E residual sweep
- [ ] 잔여 operator 출력 이주 점검 (analytic/UNION/rollup)
- [ ] 게이트 기본 ON 결정(2A-EXIT 전제, full-suite 통과 후)
- [ ] 2A-EXIT 전수 심볼 sweep (Phase3 진입 전제)
- [ ] acceptance (a)–(g) 매핑 충족 → #78 CLOSE → Phase3(#74, 비가역 삭제)
