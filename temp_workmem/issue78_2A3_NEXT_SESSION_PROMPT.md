# NEXT SESSION PROMPT — #78 Phase2 2A-3 (hash join) 이주

CUBRID temp-workmem 재설계(#73) Phase2 producer 이주(#78)의 **2A-3 (hash join per-worker tape import, ADR0004)** 를 리더로서 진행한다. 착수 전 아래를 반드시 정독하고, 명시된 도구·거버넌스·검증·측정 규율을 강제한다.

## ★★★ 작업 도구·스킬 (최우선 — 위반 금지) ★★★
- **구현은 executor subagent에 위임(강력 권장).** 리더(너)는 설계/grounding/통합/**검증**/거버넌스만. 각 코드 슬라이스는 executor에게 파일 ≤3–5 + 정확한 좌표 + 설계 + "빌드/포맷/서버/검증 하지 말 것" 지시로 bounded 위임. 다중 독립 슬라이스는 병렬 executor. 리더가 union of changed files에 대해 한 번에 빌드·검증.
- **빌드·설치는 무조건 `cubrid-build` 스킬의 `just build`.** 
  - `WORKSPACE=/home/cubrid/dev/cubrid-workmem just build release` (perf/측정용, RelWithDebInfo) / `... just build debug` (correctness·assert·crash·gdb·selftest용, Debug).
  - **raw `cmake --build` / `ctest` 직접 호출 절대 금지. 수동 증분빌드 바이너리로 (특히 성능)테스트 절대 금지 — 무조건 `just build` 파이프라인(build+install+locale+repoint)을 거친 install 바이너리로만 측정.**
  - 긴 빌드는 background로. `just build`는 **`~/CUBRID`를 repoint** 하므로 필요시 `readlink ~/CUBRID` 먼저 기록.
  - **빌드는 conf를 wipe한다 → 매 빌드 직후 campaign conf 재적용 필수**(누락 시 `stored_procedure` 기본값으로 PL server 기동 실패): `data_buffer_size=512M, work_mem=8M, parallelism=8, max_parallel_workers=8, stored_procedure=no`.
- **서버 start/stop/restart는 무조건 `cubrid-server-control` 스킬 래퍼.** 
  - `~/dev/workspace/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh {start|stop|restart|status} <db>`.
  - **raw `cubrid server start|stop` 절대 금지** — 출력이 파이프(Bash 툴)로 잡히면 daemon이 파이프를 물고 **영원히 hang**. 래퍼만 capture-safe.
  - binary(release↔debug) 전환 시 `pkill -9 cub_server; pkill -9 cub_master`. pkill -9 후 재기동은 recovery로 느리니 **readiness poll**(SELECT 1 반복)로 준비 확인 후 쿼리.
- **cubrid-cci 서브모듈 / untracked `bench/harness/results` 절대 건드리지 말 것** (기존 상태).

## 0) 착수 전 필독 (권위 순서 — 건너뛰기 금지)
권위: **SSOT(#75) > ADR0001–0006 > tape-model.md > plan**. GitHub 이슈가 정본.
1. **SSOT**: `~/dev/workspace/temp_workmem/issue65_ssot.md` (§0 오염전제 P1–P6 재도입 금지 포함 전체)
2. **ADR**: `~/dev/workspace/temp_workmem/docs/adr/0001~0006` (특히 **0004 per-worker tape 파티션**, 0002 tapeset, 0005 frozen tape 동시읽기, 0006 overflow first-page-owner)
3. **tape-model**: `~/dev/workspace/temp_workmem/docs/tape-model.md`
4. **plan**: `~/dev/workspace/issue78_plan.md` (2A-3 :84-87, 재ground 좌표 :201-205, risk R5)
5. **evidence(강제)**: `~/dev/workspace/temp_workmem/issue65_evidence.md` — 엔트리 **(k')~(o) 전부**, 특히 **(o) 2A-3 grounding**(정밀 좌표·설계·안전 1차 슬라이스·EXIT GATE), (l)/(m-CORRECTION)(버그2 귀속 + 측정 confound 교훈)
6. **GitHub 정본**: `gh issue view 78 --repo xmilex-git/cubrid --comments` (그리고 #73, #75, #65). 최근 코멘트(회귀발견/정정/B-ii/확대스윕 등)로 현상태 확정.

## 1) 현재 상태
- repo `/home/cubrid/dev/cubrid-workmem`, 브랜치 `wm-integ-7173-develop`, **HEAD `cf936e0c2`** (xmilex 원격 push 완료). 소스 클린.
- 이력: 2A-2 `3fd601626` / 2A-2c `c94ae5081` / 2A-2d `15fe7c549` / 2A-2e `7559d1445` / **2A-2f `3711786dd`**(GROUP BY silent-wrong 수정) / **B-ii `cf936e0c2`**(group-by 출력 NEW 이주).
- **해결대상 bug2**: 미이주 **병렬 HASH JOIN 레이스**(silent wrong, 간헐 `149510` vs 정답 `200360`, develop 안정 정상). pre-existing(내 2A-2 시리즈는 hash join 실행부 미변경). **2A-3가 구조 해소**.

## 2) 과제: 2A-3 hash join per-worker tape import (ADR0004)
각 (worker, partition)을 자체 NEW per-worker tape로, partition = 그 tape들 import한 tapeset. `part_mutexes` + `qfile_append_list` copy 제거(NEW 한정), `use_connect` NEW엔 drop(OLD until-contract 유지), PRIVATE_SPILL membuf-OFF 제거 NEW scope, 병렬 partition reader = `chunk_distributor`, backing-kind entry guard. **게이트(예 `CUBRID_WM_HASHJOIN_NEW`, default OFF)** 로 감싸 default 무회귀.
좌표(evidence (o)): `query_hash_join.c` `hjoin_build_partitions`:1507→`hjoin_split_qlist`:1602(write `qfile_add_tuple_to_list` :1739, spill `qfile_append_list` :1709/:1764), part 슬롯 alloc :2221/2228, `use_connect` per-PAIR :1898(connect :1909/append :1913), `part_mutexes` :2342/:2415, 병렬 `execute_partitions`(qexec_hash_join :220); `px_hash_join.cpp/.hpp`, `px_hash_join_task_manager.cpp`.
**안전 1차 슬라이스(de-risk, behavior 무변경)**: vestigial raw-fd-overflow 死코드 제거 — `get_raw_fd_overflow_page`/`get_sector_scan_list_id`(호출0), `register/unregister_sector_scan_list_id`(unread map) → `task_manager.cpp:46-120` + `px_hash_join.cpp`(:87/121/146/527/605) + `.hpp`. 별도 커밋+무회귀 후 본 이주.
**착수 전 HEAD `cf936e0c2`에서 좌표 re-ground(`search`/`lsp`) 필수**(라인 드리프트; plan 좌표는 provisional).

## 3) 강제 규율 (MUST)
- **정합성 > perf. wrong-fast 절대 불가.** §0 P1–P6 오염(per-tuple lock skip / double-spill / membuf-connect / raw-fd-single-overflow revival) 재도입 금지.
- **모든 NEW 경로 변경은 게이트 뒤(default OFF), env-OFF는 byte-identical.**
- **★측정 confound(이번 세션 최대 교훈)**: WM 게이트(`qfile_scan_new_backing_enabled`/`qfile_sort_new_backing_enabled`/신규 hashjoin 게이트)는 **서버 프로세스 getenv**. 반드시 `cubrid server start` 시점에 `CUBRID_WM_*=1`을 **서버 env**로 줘라(래퍼 호출을 그 env로). **csql 클라이언트 env는 무효.** env-isolated(`env -i PATH=$RED/bin:/usr/bin:/bin CUBRID=$RED CUBRID_DATABASES=/home/cubrid/databases`) + warm(warmup + median).
- develop×1.10 perf 게이트.

## 4) 검증 게이트 (2A-3 EXIT — 전부 통과해야 완료 선언)
- **robust serial==parallel 패리티**(count/sum/min/max, terminal page 포함): `wmloc`(4.19M) + `tpch_sf10`. serial=서버 `max_parallel_workers=1` vs 병렬=8, develop 대조.
- **#77(병렬 PHJ allocate-0/FAIL-10) NEW 경로 해소**(OLD crash는 legacy-until-contract 미수정).
- **bug2 레이스 해소**: 병렬 hash join 결정적 정답(`o_orderkey<200000` count=`200360`) ×여러회.
- 하드 카운터: `part_mutexes`=0(이주경로), merge-entry guard 0 live, `pgbuf_fixes`=0, no-mixed=0, CoV≤15%, PHJ median≤develop×1.10, deadlock-free.
- **debug 셀프테스트**(반드시 현 HEAD로 debug 재빌드 후): `env -i ... CUBRID_PRODUCER_SELFTEST=1 CUBRID_TAPEREAD_SELFTEST=1 csql -S -u dba demodb -c "SELECT 1;"` → `*_SELFTEST result=0`. release는 RelWithDebInfo라 gdb 심볼有; NDEBUG crash는 silent SIGSEGV+0byte core → `gdb -p <pid> -batch`.

## 5) 거버넌스 (슬라이스마다 강제)
각 논리 슬라이스(死코드제거 / 파티션 producer NEW / 병렬 reader / use_connect·PRIVATE_SPILL scope / 검증)마다:
1. **커밋 1개** — 메시지에 무엇·왜·**검증 측정치** 명시. 태그 `[temp-workmem PHASE2 2A-3 …] … (#78, #73)`.
2. **`git push xmilex HEAD:wm-integ-7173-develop`**.
3. **`gh issue comment 78 --repo xmilex-git/cubrid`** — 한글 보고(변경·설계·검증치·다음).
4. **evidence 엔트리 추가**(`issue65_evidence.md`) — 좌표·설계·측정치·리스크.
5. 실패/오진단은 **정정 코멘트+evidence로 정직히 기록**(이번 세션 측정오류 정정 선례처럼).

## 6) 참조값 / 경로
- installs: develop=`/home/cubrid/release/CUBRID-develop-69e73b47`, redesign(NEW 심볼)=`/home/cubrid/release/CUBRID-11.5.develop`, debug=`/home/cubrid/debug/CUBRID-11.5.develop`.
- golden(tpch_sf10): DISTINCT 15M=`15000000/449999872500000/1/60000000`; GROUPBY=`15000000/59986052/1/7`; HAVING(cnt≥4)=`8569672/47128037/7`; HASHJOIN(o_orderkey<200000) count=`200360`. wmloc DISTINCT=`4194304/8796090925056/0/4194303`.

## 7) 스타일
- **구현=executor 위임, 리더=설계/검증/거버넌스**(§도구 참조). 착수 시 `todo`로 슬라이스 분해 후 하나씩 완료·커밋.
- **HARD-GATE 서브페이즈 = 졸속 금지.** 2A-2c가 한 쿼리(DISTINCT)만 보고 성급히 질러 GROUP BY silent-wrong을 default로 push한 게 이번 세션 최대 교훈 — **넓은 robust parity(10+ operator군)로 검증하기 전엔 게이트 기본 ON 금지.**

시작 순서: 필독(0) → `gh issue 78` + `git log`로 현상태 → 좌표 re-ground → **안전 1차 슬라이스(死코드, executor 위임)** → 본 이주(executor 위임) → 검증 게이트(리더) → 거버넌스.

## 8) 이슈 #78 종료까지 남은 일 (전체 로드맵 — 이 프롬프트의 2A-3는 그 첫 조각)
plan(issue78_plan.md) 서브페이즈 순서 + 현 진행:
- [x] 2A-0 pre-flight/R2 concurrent-read/merge-guard (착지)
- [x] 2A-1 SORT final-output NEW (착지; DISTINCT/ORDER_BY 출력 NEW·0.97×)
- [x] 2A-2 parallel-scan pre-agg NEW (`3fd601626`~`7559d1445`) + **2A-2f 정합성 수정**(`3711786dd`) + **B-ii group-by 출력 NEW**(`cf936e0c2`)
- [ ] **2A-3 hash-join per-worker tape import** ← 이번/다음 세션 (bug2 PHJ 레이스 해소, ADR0004)
- [ ] **2A-4 인벤토리 A~E residual sweep** — 이주된 각 operator의 NEW 경로에서 OLD scan-bypass 잔재=0 (정적 열거 + 2A-0 런타임 카운터==0). A membuf 직접 / B membuf==NULL / C sort_split(#7173로 소멸) / D last_pgptr next_vpid / E sector 분배.
- [ ] **잔여 operator 출력 이주 점검** — 확대 스윕서 analytic/UNION/rollup 등은 결과 정합했으나 그 출력이 NEW인지(외부 스캔 병렬화 가능) vs OLD-serial인지 확인. 미이주면 B-ii 패턴으로 이주 or 명시적 잔존 기록.
- [ ] **게이트 기본 ON 결정(2A-EXIT 전제)** — 현재 `CUBRID_WM_SCAN_NEW`/`SORT_NEW`(+신규 `HASHJOIN_NEW`)는 default OFF. 광범위 full-suite(ctest/CTP + robust parity 10+군, TDE wmg003, orphan-zero 정상/비정상 종료, debug no-assert/crash) 통과 확인 후 default ON 승격 검토. (2A-2c 교훈: 검증 없이 ON 금지.)
- [ ] **2A-EXIT 전수 심볼 sweep** — OLD 심볼(connect_list×7, coord_type×16, dependent_list_id×4, rawfd_find_and_mark_dirty×3, QFILE_LIST_SECTOR_SCAN_INFO×21, PRIVATE_SPILL 게이트) 분류 체크리스트(`bench/harness/checklists/`) = 이주로 死 vs 특정 OLD operator용 live. **Phase3(#74 CONTRACT 삭제)의 게이트 진입 전제.**
- [ ] **acceptance (a)–(g) 매핑 충족**(plan §Acceptance): (a)A~E residual0 (b)membuf 재활성/tiny-no-spill (c)pre-sized slot+chunk_distributor (d)hash join per-worker import(no part_mutexes) (e)no-mixed+backing-kind guard live=0 (f)2A-EXIT sweep (g)all-path robust parity(serial==parallel, terminal).
- 그 후 **#78 CLOSE** → Phase3(#74)는 별개 이슈(비가역 삭제, #78 종료·sweep 후).

**남은 핵심 리스크**: bug2(병렬 PHJ 레이스, silent wrong) = 2A-3가 해소해야 할 최우선 정합성 항목. #77(PHJ allocate-0) NEW경로 해소는 2A-3 exit 필수(OLD는 legacy-until-contract).
