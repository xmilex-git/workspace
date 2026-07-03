# NEXT SESSION PROMPT — #78 Phase2 post-2A-3 (per-worker OUTPUT tape + 2A-4 sweep)

CUBRID temp-workmem 재설계(#73) Phase2 producer 이주(#78)의 **post-2A-3** 를 리더로서 이어서 진행한다. **직전 세션에서 2A-3 세션 오염 root-cause 해소 + 잔여 EXIT 게이트 충족 + 100GB 부트 메모리 수정이 완료·커밋·push 됐다.** 이 프롬프트는 **per-worker OUTPUT tape(ADR0004)** + **2A-4 인벤토리 sweep** 을 수행한다. 착수 전 아래 필독 문서를 **전부 정독**하고, 명시된 도구·거버넌스·검증·측정 규율을 강제한다.

---

## ★★★ 0) 착수 전 필독 (권위 순서 — 정독 필수, 건너뛰기 금지) ★★★
권위: **SSOT(#75) > ADR0001–0006 > tape-model.md > plan**. GitHub 이슈가 정본.
1. **SSOT 전문 정독**: `~/dev/workspace/temp_workmem/issue65_ssot.md` — 특히 **§0 오염전제 P1–P6**, §3.2 B1/B2, §5.4 마이그레이션, 그리고 **★★★ UPDATE (o)~(u):**
   - **(t)** 세션 오염 root-cause 해소 (`d9ad680ad`): subquery parallel executor worker 선점 → OLD probe → serial 강제 + aptr executor 차단
   - **(u)** perf 갱신: median=4.261s (0.201×develop), CoV=8.2%
2. **evidence 정독**: `~/dev/workspace/temp_workmem/issue65_evidence.md` — 특히 **(s)**(session-fix), **(t)**(과제B+메모리풀), **(q)**(bug2 정정), **(o)**(2A-3 grounding).
3. **GitHub 정본**: `gh issue view 78 --repo xmilex-git/cubrid --comments` — 최근 코멘트 확인.
4. **착수 전 HEAD `fb4e20af6`에서 좌표 re-ground 필수** (라인 드리프트).

---

## 1) 현재 상태
- repo `/home/cubrid/dev/cubrid-workmem`, 브랜치 `wm-integ-7173-develop`, **HEAD `fb4e20af6`** (workmem-pool; xmilex push 완료). **tracked src 클린.**
- 이력: 2A-0~2A-2f/B-ii(`cf936e0c2`) + slice-1(`017afa968`) + 2A-3 프로브(`d517fc60c`) + outer(`b519ac5e4`) + split(`09150351d`) + **session-fix(`d9ad680ad`) + workmem-pool(`fb4e20af6`)**.
- **게이트 3종**: `CUBRID_WM_SCAN_NEW`, `CUBRID_WM_SORT_NEW`, `CUBRID_WM_HASHJOIN_NEW` (서버 프로세스 getenv, 기본 OFF).
- **campaign conf: `work_mem=1G`, `data_buffer_size=512M`, `parallelism=8`, `max_parallel_workers=8`, `stored_procedure=no`** — `just conf` 로 idempotent 적용.
- **perf**: median=4.261s (0.201×develop), CoV=8.2%≤15%. 전부 충족.
- **session-fix**: batched csql -i 포함 전부 정답. cold 별도 세션 제약 해소.

---

## 2) 과제

### 과제 A — per-worker OUTPUT tape (ADR0004, part_mutexes 제거)
**목표**: 병렬 PHJ 파티션 결과를 per-worker 개별 tape로 생산하고, 리더가 import. 현재 `part_mutexes[part_id]` 하에 `qfile_append_list`로 공유 파티션에 직렬화 쓰기 — per-worker tape로 바꾸면 **mutex-append 제거 + perf 이점**.

**주의**: 이전 세션에서 per-worker OUTPUT tape 초기 시도가 자체 레이스(209198/837199)로 revert됨 (evidence (o)/(q)). **root-cause 선행 후 재구현**.
- evidence (q)에서 확인: bug2는 입력-리더(sector_page_iterator) 행유실이지 출력 write race가 아님 → per-worker OUTPUT tape는 bug2와 직교 → 재구현 가능하나, 초기 시도의 자체 레이스 원인 규명이 선행.

### 과제 B — 2A-4 인벤토리 A~E residual sweep
**목표**: Phase2 producer 이주에서 아직 OLD 경로에 남아있는 임시파일 사용 사이트 전수조사.
- 인벤토리 A: 살아있는 membuf cross-worker 접근 (connect_list, use_connect 등)
- 인벤토리 E: scan subquery 결과 list 의 tapeset destroy 시점
- 각 사이트마다 NEW 전환 가능/불가 판정 + 미전환 사이트는 "legacy-until-contract" 태그.

### 과제 C — 잔여 operator 출력 이주 점검
- analytic/UNION/rollup 등 아직 이주 안 된 operator의 출력 경로 점검.
- 전환 필요 사이트 식별 → 별도 슬라이스 계획.

### 하지 말 것
- §0 P1–P6 오염 재도입 금지.
- OLD 경로(env-OFF) 동작 변경 금지.
- 게이트 기본 ON을 이 슬라이스에서 결정 금지 (full-suite 통과 후 별도 결정).

---

## 3) 착수 순서
1. **SSOT(`issue65_ssot.md`) 전문 정독** — 특히 UPDATE (o)~(u).
2. 좌표 re-ground (`fb4e20af6`).
3. 과제 A → 과제 B → 과제 C 순서 (A가 blocking이면 B부터).
4. 검증 게이트 → 거버넌스.

---

## 4) 작업 도구·스킬 (★최우선)
- **빌드 = `just build release` / `just build debug` 만.** 빌드 후 `just conf` 필수 (work_mem=1G 포함 전체 campaign 파라미터 idempotent). `WORKSPACE=/home/cubrid/dev/cubrid-workmem` 필수.
- **★★ debug + release 둘 다 풀빌드 green 필수.**
- **서버 start/stop = `cubrid-server-ctl.sh` 래퍼만**: `~/dev/workspace/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh {start|stop|restart|status} <db>`. **raw `cubrid server start|stop` 절대 금지** (파이프 hang).
- **★게이트는 서버 프로세스 getenv** → `CUBRID_WM_SCAN_NEW=1 CUBRID_WM_SORT_NEW=1 CUBRID_WM_HASHJOIN_NEW=1` 을 래퍼 호출 env 로 전달. csql 클라이언트 env 무효.
- **★★ debug tpch_sf10 주의**: debug 빌드에서 tpch_sf10(60M행)은 메모리 과다 사용 가능. **debug 검증은 wmloc(4.19M행) 또는 wmg003(TDE)에서 수행**. tpch_sf10은 release에서만 사용.
- cubrid-cci 서브모듈 / untracked `bench/harness/results` 절대 건드리지 말 것.

---

## 5) 검증 게이트
- debug + release 풀빌드 green.
- robust serial==parallel 패리티 (cold 세션): `<200000`=200360, `<2000000`=2000495, wmloc DISTINCT=`4194304/8796090925056/0/4194303`.
- env-OFF 무회귀.
- median ≤ develop×1.10, CoV ≤ 15%.
- debug selftest green (PRODUCER_SELFTEST + TAPEREAD_SELFTEST algo=1).
- 하드 카운터 (CS debug): pgbuf_fixes 최소, no-mixed=0, backing-guard 위반 0.

---

## 6) 거버넌스
각 논리 슬라이스마다: (1) 커밋 — 태그 `[temp-workmem PHASE2 …] … (#78, #73)`. (2) `git push xmilex HEAD:wm-integ-7173-develop`. (3) `gh issue comment 78` 한글 보고. (4) evidence 엔트리 추가. (5) 실패/오진단은 정정 기록. (6) SSOT 갱신 (사실 변경 시만).

---

## 7) 참조값 / 경로
- installs: develop=`/home/cubrid/release/CUBRID-develop-69e73b47`, redesign(release)=`/home/cubrid/release/CUBRID-11.5.develop`, debug=`/home/cubrid/debug/CUBRID-11.5.develop`.
- DB: tpch_sf10·wmloc·wmg003(TDE) in `/home/cubrid/databases`.
- golden: HASHJOIN `<200000` count=**200360**; `<2000000` count=**2000495**; DISTINCT 15M=`15000000/449999872500000/1/60000000`; wmloc DISTINCT=`4194304/8796090925056/0/4194303`.
- perf (work_mem=1G, `<200000`, cold 7회): redesign median **4.261s** (0.201×develop), develop median **21.206s**, CoV=8.2%.
- 래퍼: `~/dev/workspace/.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh`

## 8) 이슈 #78 종료까지 로드맵 (post-2A-3)
- [x] 2A-3 프로브(INNER) NEW 병렬 (`d517fc60c`)
- [x] 2A-3 outer probe NEW 병렬 (`b519ac5e4`)
- [x] 2A-3 split/partition NEW 병렬 (`09150351d`)
- [x] median ≤ develop×1.10 (0.201×)
- [x] 세션 상태 오염 root-cause → CoV ≤ 15% (`d9ad680ad`)
- [x] #77 wmloc 재검증 + debug 셀프테스트 + 하드 카운터
- [x] 100GB 부트 메모리 수정 (`fb4e20af6`)
- [ ] **per-worker OUTPUT tape (ADR0004, part_mutexes 제거)** ← 이 프롬프트
- [ ] **2A-4 인벤토리 A~E residual sweep** ← 이 프롬프트
- [ ] **잔여 operator 출력 이주 점검 (analytic/UNION/rollup)** ← 이 프롬프트
- [ ] 게이트 기본 ON 결정 (2A-EXIT 전제, full-suite 통과 후)
- [ ] 2A-EXIT 전수 심볼 sweep (Phase3 진입 전제)
- [ ] acceptance (a)–(g) 매핑 충족 → #78 CLOSE → Phase3(#74, 비가역 삭제)
