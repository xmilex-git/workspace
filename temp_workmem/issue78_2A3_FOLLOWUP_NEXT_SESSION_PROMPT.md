# NEXT SESSION PROMPT — #78 Phase2 2A-3 FOLLOW-UP (병렬 PHJ outer/split 경로 NEW 이주 + perf 정상상태)

CUBRID temp-workmem 재설계(#73) Phase2 producer 이주(#78)의 **2A-3** 를 리더로서 이어서 진행한다. **직전 세션에서 2A-3 프로브(INNER) 경로 NEW 이주가 착지·검증·커밋됐다**(commit `d517fc60c`). 이 프롬프트는 그 위에서 **남은 PHJ 경로(outer-join / partition-split)의 NEW 병렬화 + perf 정상상태 규명**을 수행한다. 착수 전 아래 필독 문서를 **전부 정독**하고, 명시된 도구·거버넌스·검증·측정 규율을 강제한다.

---

## ★★★ 0) 착수 전 필독 (권위 순서 — 정독 필수, 건너뛰기 금지) ★★★
권위: **SSOT(#75) > ADR0001–0006 > tape-model.md > plan**. GitHub 이슈가 정본.
1. **SSOT 전문 정독**: `~/dev/workspace/temp_workmem/issue65_ssot.md` — 특히 **§0 오염전제 P1–P6**, §3.2 B1/B2, §5.4 마이그레이션, **round-3 UPDATE (a)(d)(f)**(입력분배 OLD=`sector_page_iterator` ↔ NEW=`chunk_distributor`, backing-kind 입력가드), **round-4 UPDATE (k)(l)(m)** (bug2=입력-리더 행유실), 그리고 **★(n) (2026-07-01, 프로브 경로 착지)** — crash=2A-0 backing guard 정상발화(gdb 확정), 프로브 INNER 경로 이주 완료, **잔여 = execute_outer NEW 병렬 + split/파티션 NEW 병렬(현 serial 강제)**.
2. **evidence 정독**: `~/dev/workspace/temp_workmem/issue65_evidence.md` — **★(r)**(2A-3 프로브 경로 착지: gdb 원인·수정·검증·release-only 빌드 함정), (q)(bug2 정정), (p)(slice-1), I-13(2A-0 chunk_distributor/tapeset_reader/backing-guard/A~E 카운터), I-9(chunk_distributor CoV), I-10(#7173 sector 공통화·21사이트), I-18(k')(2A-2e tapeset_reader tuple-level 병렬 + selftest).
3. **정정 스코프 브리프**: `~/dev/workspace/temp_workmem/issue78_2A3_CORRECTED_SCOPE.md`.
4. **ADR**: `docs/adr/0003`(per-worker private·offset-range 분배), `0004`(partition=per-worker tape import — OUTPUT측 perf, 이번 과제 아님·직교), `0005`(frozen tape 동시읽기=공유fd+`pread`+per-reader 스크래치), `0006`(overflow first-page-owner). tape-model.md.
5. **GitHub 정본**: `gh issue view 78 --repo xmilex-git/cubrid --comments` — 최근 코멘트 **`[2A-3] 병렬 PHJ 입력-리더 NEW 이주 (프로브 경로)`(comment 4851140998)** 로 현상태 확정.
6. **gdb 원인 아티팩트**: `~/dev/workspace/temp_workmem/artifacts/gdb_guard.out` (Invalid XASL = backing guard 백트레이스 원본).
7. **착수 전 HEAD `d517fc60c`에서 좌표 re-ground(`search`/`lsp`) 필수** (라인 드리프트 — 직전 세션 include 3줄 추가·람다 추출로 task_manager.cpp 대폭 이동).

---

## 1) 현재 상태
- repo `/home/cubrid/dev/cubrid-workmem`, 브랜치 `wm-integ-7173-develop`, **HEAD `d517fc60c`** (2A-3 프로브 경로; xmilex push 완료). **tracked src 클린.**
- 이력: 2A-0~2A-2f/B-ii(`cf936e0c2`) + slice-1(`017afa968`) + **2A-3 프로브 `d517fc60c`**.
- **게이트 3종(env, 서버 프로세스 getenv, 기본 OFF)**: `CUBRID_WM_SCAN_NEW`(scan producer NEW), `CUBRID_WM_SORT_NEW`(sort/groupby/distinct 출력 NEW), `CUBRID_WM_HASHJOIN_NEW`(병렬 PHJ NEW-입력 프로브 chunk 병렬).
- **직전 세션 착지 요약**: `Invalid XASL tree node content` = 2A-0 backing guard 정상발화(gdb 확정). PHJ 프로브 입력은 SCAN_NEW서 실제 NEW-backed. INNER 프로브를 `chunk_distributor`+per-worker `tapeset_reader`로 병렬화 → bug2 `<200000`=**200360** / `<2000000`=**2000495** 결정성(게이트 ON, trace `parallel workers:8`); 게이트 OFF·outer·partition은 NEW 입력 시 **serial 강제**(무크래시). env-OFF 무회귀(pre-existing OLD-sector 유실 `209198/837199` 그대로). perf median 0.68×develop(단 bimodal ~27s outlier).

---

## 2) 과제 (남은 2A-3 슬라이스 — 각각 독립 커밋)

### 슬라이스 A — `execute_outer` NEW-입력 병렬 (outer join)
현재 `probe_task::execute_outer`(px_hash_join_task_manager.cpp)는 OLD sector 페이지-워크만 있고, NEW 입력 outer join 은 `hjoin_try_parallel_probe`에서 **serial 강제**(직전 세션 가드: `IS_OUTER_JOIN_TYPE(manager->join_type)` 조건). 이 조건을 제거하려면:
- `execute_inner`가 쓴 패턴을 **그대로 미러**: (1) per-probe-tuple 처리부를 공유 람다로 추출, (2) `if (m_shared_info->new_dist != nullptr)` NEW 분기에서 per-worker `qfile::tapeset_reader(m_shared_info->new_tapeset, m_shared_info->new_dist, m_index)`로 튜플 소싱(COPY peek=0), (3) OLD 분기는 `else`로 기존 페이지-워크 보존.
- **주의**: execute_outer 는 outer-join fill 로직(`any_record_added`, non-match 시 NULL fill)이 추가로 있음 → 람다 추출 시 그 로직도 정확히 보존(execute_inner 보다 복잡). fill 시맨틱이 tuple-source 무관하게 동작하는지 확인.
- `hjoin_try_parallel_probe`의 `|| IS_OUTER_JOIN_TYPE (manager->join_type)` 가드 조건 제거(게이트 ON일 때 outer 도 병렬 허용).
- **검증**: LEFT/RIGHT OUTER JOIN robust parity serial==parallel(게이트 ON, trace 병렬 실증) + env-OFF 무회귀.

### 슬라이스 B — split/partition 경로 NEW-입력 병렬 (`build_partitions`)
현재 파티션(split) 경로는 NEW 입력 시 `hjoin_try_parallel`에서 **serial PARTITION 강제**. 병렬 split 을 NEW 입력에 지원하려면:
- `px_hash_join.cpp` split 셋업(outer `qfile_open_list_sector_scan(...outer->fetch_info->list_id...)` + inner 동일 — 직전 세션 좌표 :80/:112 근방, re-ground 필수): 입력이 NEW-backed 면 `chunk_distributor` 생성. **outer/inner 는 별도 입력** → `HASHJOIN_SHARED_SPLIT_INFO`에 (outer용/inner용) new_dist·new_tapeset 필드 필요(프로브의 `HASHJOIN_SHARED_PROBE_INFO` 패턴 참고). split_task 는 outer/inner 각각에 대해 push 되므로 어느 입력인지 태깅.
- `split_task::execute`(task_manager.cpp:181 근방): `m_page_iter.get_next_page(m_shared_info->sector_scan)` 페이지-워크를 NEW 분기(per-worker `tapeset_reader`)로. 그 안의 per-tuple 처리(hash_key 계산 → part_id 배정 → `temp_part_list_id[part_id]`에 write, membuf 풀→`part_list_id` spill under `part_mutexes`)는 **그대로 유지**(write측 mutex 직렬화는 bug2와 직교, evidence (q)).
- `hjoin_try_parallel`의 NEW-입력 serial 강제 가드 제거(게이트 ON일 때 병렬 split 허용).
- **주의**: bug2 캐노니컬 쿼리(`<200000`/`<2000000`)는 **둘 다 PARALLEL_PROBE**(build 가 work_mem 적합)라 split 경로를 **안 탄다**. split 을 실제로 태우려면 **build 측이 work_mem 초과**하는 쿼리 필요(예: 더 큰 build 관계 + `work_mem` 축소). 먼저 gdb/trace 로 `build_partitions`/`hjoin_check_partition` 진입을 실증한 뒤 검증(passthrough-tautology 금지).
- **ADR0004(per-worker OUTPUT tape, part_mutexes 제거)는 이번 과제 아님** — 그건 별도 perf 슬라이스이고 직전 시도서 자체 레이스(209198/837199) 있었으니 재구현 시 root-cause 선행. 슬라이스 B 는 **입력 읽기만** NEW 병렬화(write측 무변경).

### 슬라이스 C — perf 정상상태 규명 (bimodal outlier)
bug2 `<200000` 게이트-ON warm 이 bimodal(~4.6–5.3s vs ~27s). median 은 0.68×develop 로 게이트 통과하나 tail 이 큼. 60M lineitem BUILD(file-hash) + NEW materialize I/O 지배 의심. VTune/trace 단계분해로 outlier 원인(checkpoint/flush/temp file cleanup/NEW spill) 규명 → 필요 시 완화. **CoV≤15% + median≤develop×1.10 동시 충족**이 2A-3 EXIT.

### 하지 말 것
- **per-worker OUTPUT tape / `part_mutexes` 제거를 이 슬라이스에서 재시도 금지**(ADR0004 별도 perf 슬라이스, root-cause 선행).
- §0 P1–P6 오염 재도입 금지.
- OLD 경로(env-OFF) 동작 변경 금지 — 가드는 NEW-backing 에만 발화(byte-identical OLD 유지).

---

## 3) 착수 순서
1. 필독(§0) → `gh issue 78` + `git log` 현상태 → 좌표 re-ground(`d517fc60c`).
2. 슬라이스 A(outer) 먼저(프로브 패턴 재사용, 저위험) → 슬라이스 B(split, gdb 로 진입 실증 선행) → 슬라이스 C(perf).
3. **구현은 executor 위임 가능하나, 얽힌 루프 리팩터(람다 추출)는 정밀 좌표+패턴을 스펙에 명시.** 리더가 union 빌드·검증·거버넌스. (직전 세션 판단: 얽힌 correctness 루프는 리더 직접 구현도 방어 가능 — 검증 규율이 게이트.)
4. 검증 게이트(§5) → 거버넌스(§6).

---

## 4) 작업 도구·스킬 (★최우선 — 위반 시 즉시 실패 취급)
- **빌드 = `cubrid-build` 스킬만.** `WORKSPACE=/home/cubrid/dev/cubrid-workmem just build release` / `... just build debug`.
  - **★★ 증분빌드로 "컴파일 됐다" 판정 금지. 컴파일러 단독(`g++`/`cmake --build` 단일 TU/`-fsyntax-only`)으로 문법검사 금지. 코드 변경 후에는 반드시 `just build` 로 debug + release **둘 다 완주**해 install 까지 green 확인.** (근거: 직전 세션 `-Werror=reorder`는 **release 프리셋 풀빌드에서만** 발화, debug 증분은 통과 → debug-only/증분 통과로 착지하면 release 깨진 채 push 됨. evidence (r).) 필요 시 `just rebuild <mode>`(fresh configure+build)로 완전 풀빌드.
  - raw `cmake --build`/`ctest` 를 검증 근거로 쓰지 말 것(스킬 경유만). 긴 빌드는 background. **`just build`는 `~/CUBRID` repoint** — 필요시 `readlink ~/CUBRID` 먼저.
  - **빌드가 conf wipe → 매 빌드 직후 campaign conf 재적용 필수**: `data_buffer_size=512M, work_mem=8M, parallelism=8, max_parallel_workers=8, stored_procedure=no`(+ `server=demodb, thread_worker_timeout_seconds=4, double_write_buffer_size=0`).
- **서버 start/stop/restart = `cubrid-server-control` 래퍼만**: `~/dev/workspace/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh {start|stop|restart|status} <db>`. **raw `cubrid server start|stop` 절대 금지**(파이프 hang). binary/게이트 전환 시 `pkill -9 cub_server; pkill -9 cub_master` + readiness(SELECT 1). **★게이트는 서버 프로세스 getenv** → `CUBRID_WM_*=1`을 **래퍼 호출(=서버 start) env**로 줘라. csql 클라이언트 env 무효. env-isolated: `env -i PATH=$RED/bin:/usr/bin:/bin HOME=/home/cubrid CUBRID=$RED CUBRID_DATABASES=/home/cubrid/databases`.
- **구현 = executor 위임(권장), 리더 = 설계/grounding/통합/검증/거버넌스.** union of changed files 를 리더가 한 번에 빌드·검증(executor 는 빌드/서버/검증 금지).
- **cubrid-cci 서브모듈 / untracked `bench/harness/results` 절대 건드리지 말 것.**

---

## 5) ★측정 규율 + 검증 게이트 (2A-3 EXIT — 전부 통과해야 완료)
- **debug + release 둘 다 풀빌드 green**(§4). NDEBUG crash=silent SIGSEGV → `gdb -p <pid> -batch`; assert/셀프테스트/crash 규명은 debug.
- **재현 confound**: PHJ 병렬 유실은 세션-상태 의존 → **batched(`csql -i`) + 다회** 병행 검증(cold `-c`는 우연히 정답 나올 수 있음). debug 는 느림(serial `<200000` ~132s) → correctness 는 debug, 대량/perf 는 release.
- **robust serial==parallel 패리티**(count/sum/min/max, 터미널 포함): 게이트 ON. bug2 `<200000`=**200360**/`<2000000`=**2000495**; outer join(LEFT/RIGHT); split-태우는 큰-build 쿼리. `;trace on`의 `parallel workers:N(>1)`로 병렬 engage 실증(passthrough-tautology 금지). serial 강제 = `parallelism=1` AND `max_parallel_workers=1` 둘 다(또는 PARALLEL(1) 힌트 — hash join 은 degree<2→SINGLE).
- **env-OFF 무회귀**: OLD 경로 byte-identical(가드는 NEW-backing 에만 발화). pre-existing OLD-sector 유실(`209198/837199`)은 우리 회귀 아님(legacy-until-contract).
- **하드 카운터(게이트 ON, CS 서버 debug — SA selftest 로는 리소스 트래킹 안 됨)**: `pgbuf_fixes`=0(NEW scan), no-mixed=0, **backing-guard A~E NEW-touched-by-OLD == 0**(PHJ 가드가 더는 발화하면 안 됨), CoV≤15%, **PHJ median≤develop×1.10**, deadlock-free.
- **#77 NEW경로 해소**: wmloc 병렬 PHJ 0-length 튜플 — NEW-입력 경로 메커니즘상 해소 예상이나 **wmloc-특정 재검증 미실시**(직전 세션) → 이번에 실측.
- **debug 셀프테스트**(현 HEAD debug 재빌드 후): `env -i ... CUBRID_PRODUCER_SELFTEST=1 CUBRID_TAPEREAD_SELFTEST=1 csql -S -u dba wmg003 -c "SELECT 1;"` → `*_SELFTEST algo=1 result=0`(TDE).

---

## 6) 거버넌스 (슬라이스마다 강제)
각 논리 슬라이스(outer / split / perf)마다: (1) 커밋 1개 — 무엇·왜·**검증 측정치**, 태그 `[temp-workmem PHASE2 2A-3 …] … (#78, #73)`. (2) `git push xmilex HEAD:wm-integ-7173-develop`. (3) `gh issue comment 78 --repo xmilex-git/cubrid` 한글 보고. (4) evidence 엔트리 추가(§Z, "측정/사실" vs "구조 가정" 분리). (5) 실패/오진단은 정정 코멘트+evidence로 정직히 기록. (6) source-of-truth 사실 변경 시에만 SSOT 짧게 갱신.

---

## 7) 참조값 / 경로
- installs: develop=`/home/cubrid/release/CUBRID-develop-69e73b47`, redesign(NEW)=`/home/cubrid/release/CUBRID-11.5.develop`, debug=`/home/cubrid/debug/CUBRID-11.5.develop`.
- DB: tpch_sf10·wmloc·wmg003(TDE) in `/home/cubrid/databases`.
- golden: HASHJOIN(o_orderkey<200000) count=**200360**; <2000000 count=**2000495**; DISTINCT 15M=`15000000/449999872500000/1/60000000`; wmloc DISTINCT=`4194304/8796090925056/0/4194303`.
- perf 참조(직전 세션, warm, bug2 `<200000`): develop median ~7.83s / redesign 게이트-ON median ~5.34s(bimodal, outlier ~27s).

## 8) 스타일
- **HARD-GATE 서브페이즈 = 졸속 금지.** 측정으로 진단을 검증한 뒤 코드를 짜라(bug2 오진단·crash=guard 선례). 넓은 robust parity(batched+다회, trace 실증) 통과 전 게이트 기본 ON 금지.
- 착수 시 `todo`로 슬라이스 분해 후 하나씩 완료·커밋.

## 9) 이슈 #78 종료까지 로드맵 (2A-3 이후)
- [x] 2A-3 프로브(INNER) NEW 병렬 (`d517fc60c`) — crash-fix + bug2 해소
- [ ] **2A-3 outer (슬라이스 A)** ← 이 프롬프트
- [ ] **2A-3 split/partition 입력 (슬라이스 B)** ← 이 프롬프트
- [ ] **2A-3 perf 정상상태 (슬라이스 C) + CoV/median EXIT** ← 이 프롬프트
- [ ] (perf 후속) hash-join 파티션 per-worker OUTPUT tape (ADR0004, part_mutexes 제거) — 레이스 root-cause 후 재구현
- [ ] 2A-4 인벤토리 A~E residual sweep
- [ ] 잔여 operator 출력 이주 점검 (analytic/UNION/rollup)
- [ ] 게이트 기본 ON 결정(2A-EXIT 전제, full-suite 통과 후)
- [ ] 2A-EXIT 전수 심볼 sweep (Phase3 진입 전제)
- [ ] acceptance (a)–(g) 매핑 충족 → #78 CLOSE → Phase3(#74, 비가역 삭제)
