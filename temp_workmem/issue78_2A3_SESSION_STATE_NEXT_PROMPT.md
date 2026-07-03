# NEXT SESSION PROMPT — #78 Phase2 2A-3 세션 상태 오염 root-cause + 잔여 EXIT 게이트

CUBRID temp-workmem 재설계(#73) Phase2 producer 이주(#78)의 **2A-3** 를 리더로서 이어서 진행한다. **직전 세션에서 outer probe + split/partition NEW 병렬 이주가 착지·검증·커밋·push 됐고, perf median=0.234×develop 충족 확인.** 그러나 **CoV EXIT 기준(≤15%)이 bimodal 때문에 미충족** — bimodal 의 원인은 **pre-existing 세션 상태 오염**(env-OFF에서도 재현). 이 프롬프트는 그 root-cause 규명 + 잔여 EXIT 게이트 충족을 수행한다. 착수 전 아래 필독 문서를 **전부 정독**하고, 명시된 도구·거버넌스·검증·측정 규율을 강제한다.

---

## ★★★ 0) 착수 전 필독 (권위 순서 — 정독 필수, 건너뛰기 금지) ★★★
권위: **SSOT(#75) > ADR0001–0006 > tape-model.md > plan**. GitHub 이슈가 정본.
1. **SSOT 전문 정독**: `~/dev/workspace/temp_workmem/issue65_ssot.md` — 특히 **§0 오염전제 P1–P6**, §3.2 B1/B2, §5.4 마이그레이션, round-3~round-4 UPDATE, 그리고 **★★★ 2026-07-01 UPDATE (o)~(s):**
   - **(o)** work_mem=1G 필수 (develop 은 data_buffer 512M 공유풀, redesign 은 per-worker work_mem → 공정 비교 전제)
   - **(p)** outer probe NEW 이주 완료
   - **(q)** split/partition NEW 이주 완료
   - **(r) 세션 상태 오염 = pre-existing (env-OFF 재현)** — batched csql -i 에서 2번째 PHJ 부터 wrong result (count=407). cold 별도 세션에서는 전부 정답. **검증 프로토콜: PHJ 는 반드시 cold 별도 csql 세션.**
   - **(s)** perf: median=4.959s=0.234×develop, median 충족, CoV=78.5% 미충족 (bimodal=세션오염 폴백)
2. **evidence 정독**: `~/dev/workspace/temp_workmem/issue65_evidence.md` — (r)(프로브 경로 착지), (q)(bug2 정정), (k)(bug2=입력-리더 행유실).
3. **GitHub 정본**: `gh issue view 78 --repo xmilex-git/cubrid --comments` — 최근 코멘트 `[2A-3 follow-up 완료 보고]` 로 현상태 확정.
4. **착수 전 HEAD `09150351d`에서 좌표 re-ground 필수** (라인 드리프트).

---

## 1) 현재 상태
- repo `/home/cubrid/dev/cubrid-workmem`, 브랜치 `wm-integ-7173-develop`, **HEAD `09150351d`** (2A-3 split; xmilex push 완료). **tracked src 클린.**
- 이력: 2A-0~2A-2f/B-ii(`cf936e0c2`) + slice-1(`017afa968`) + 2A-3 프로브(`d517fc60c`) + **2A-3 outer(`b519ac5e4`) + 2A-3 split(`09150351d`)**.
- **게이트 3종**: `CUBRID_WM_SCAN_NEW`, `CUBRID_WM_SORT_NEW`, `CUBRID_WM_HASHJOIN_NEW` (서버 프로세스 getenv, 기본 OFF).
- **campaign conf: `work_mem=1G`, `data_buffer_size=512M`, `parallelism=8`, `max_parallel_workers=8`, `stored_procedure=no`** — `just conf` 로 idempotent 적용 (`_set` helper). 빌드 후 반드시 재적용.

---

## 2) 과제

### 과제 A — 세션 상태 오염 root-cause (CoV EXIT blocker)
**증상**: `csql -i`(batched) 에서 PHJ 쿼리 2개 이상 실행 시, 2번째 쿼리부터 probe readrows 가 극소(407)로 wrong result. **fully env-OFF(모든 게이트 OFF)에서도 동일 재현** → 우리 코드 아닌 기존 결함.
- `work_mem=1G` 에서 `PARALLEL_PROBE` 경로 활성화되면서 노출 (기존 work_mem=8M 에서는 항상 파티션 스플릿 → sector_page_iterator 사용 안 함).
- cold 별도 `csql -c` 세션에서는 전부 정답 (200360 / 2000495).
- **bimodal perf**: fast run ~4.7s (PARALLEL_PROBE 정상), outlier ~23s (corrupt 폴백 ≈ develop 수준). 이 bimodal 이 전체 CoV=78.5% 의 원인.

**접근**:
1. **gdb / trace**: batched 세션에서 2번째 쿼리의 probe 입력 list_id 메타데이터(tuple_cnt, page_cnt, tapeset 포인터 등) 를 1번째와 비교. 어느 시점에서 stale/corrupt 되는지 규명.
2. **XASL 캐시 의심**: 같은 parameterized 쿼리(WHERE o_orderkey < ?)의 XASL 캐시 히트 시, 이전 실행의 temp list_id 가 재사용되거나 freed tapeset 를 가리키는지 확인.
3. **타 연산자 영향**: scan subquery 의 결과 list 가 hash join 종료 시 제대로 destroy 되는지. 특히 parallel scan worker 의 tapeset destroy 시점과 hash join 의 probe 읽기 시점 간 race.
4. **최소 재현**: `csql -c` 2연속 vs `csql -i` 1파일 2쿼리 → 서버측 차이 = 트랜잭션/세션 레벨 상태.

**검증**: batched `csql -i` 에서 N회 연속 PHJ 쿼리가 전부 정답(200360 / 2000495)이면 해소. CoV ≤ 15% 재측정.

### 과제 B — 잔여 EXIT 게이트
1. **#77 wmloc PHJ 재검증**: wmloc DISTINCT `4194304/8796090925056/0/4194303` — NEW 입력 경로 메커니즘상 해소 예상이나 실측 미실시. 게이트 ON 실행.
2. **debug 셀프테스트**: `env -i ... CUBRID_PRODUCER_SELFTEST=1 CUBRID_TAPEREAD_SELFTEST=1 csql -S -u dba wmg003 -c "SELECT 1;"` → `*_SELFTEST algo=1 result=0` 확인 (TDE).
3. **하드 카운터 (게이트 ON, CS debug)**: `pgbuf_fixes`=0(NEW scan), no-mixed=0, backing-guard A~E NEW-touched-by-OLD == 0.

### 하지 말 것
- per-worker OUTPUT tape / `part_mutexes` 제거를 이 슬라이스에서 재시도 금지 (ADR0004 별도).
- §0 P1–P6 오염 재도입 금지.
- OLD 경로(env-OFF) 동작 변경 금지.

---

## 3) 착수 순서
1. **SSOT(`issue65_ssot.md`) 전문 정독** — 특히 UPDATE (o)~(s) 와 세션 오염 증상.
2. 좌표 re-ground (`09150351d`).
3. 과제 A (세션 오염 root-cause) → 과제 B (잔여 게이트) 순서.
4. 검증 게이트 → 거버넌스.

---

## 4) 작업 도구·스킬 (★최우선)
- **빌드 = `just build release` / `just build debug` 만.** 빌드 후 `just conf` 필수 (work_mem=1G 포함 전체 campaign 파라미터 idempotent).
- **★★ debug + release 둘 다 풀빌드 green 필수.** 증분빌드 판정 금지.
- **서버 start/stop = `cubrid-server-ctl.sh` 래퍼만. raw `cubrid server start|stop` 금지** (파이프 hang).
- **★게이트는 서버 프로세스 getenv** → `CUBRID_WM_*=1` 을 래퍼 호출 env 로 전달. csql 클라이언트 env 무효.
- **★★ PHJ 검증은 반드시 cold 별도 csql 세션 (`csql -c`)** — batched (`csql -i`) 는 세션 오염 재현. (과제 A 해소 후에만 batched 검증 가능.)
- cubrid-cci 서브모듈 / untracked `bench/harness/results` 절대 건드리지 말 것.

---

## 5) 검증 게이트
- debug + release 풀빌드 green.
- robust serial==parallel 패리티 (cold 세션): `<200000`=200360, `<2000000`=2000495, LEFT/RIGHT OUTER, wmloc DISTINCT.
- env-OFF 무회귀 (cold 세션).
- 과제 A 해소 시: batched 패리티 + CoV ≤ 15% + median ≤ develop×1.10.
- debug 셀프테스트 green.
- 하드 카운터 (CS debug).

---

## 6) 거버넌스
각 논리 슬라이스마다: (1) 커밋 — 태그 `[temp-workmem PHASE2 2A-3 …] … (#78, #73)`. (2) `git push xmilex HEAD:wm-integ-7173-develop`. (3) `gh issue comment 78` 한글 보고. (4) evidence 엔트리 추가. (5) 실패/오진단은 정정 기록. (6) SSOT 갱신 (사실 변경 시만).

---

## 7) 참조값 / 경로
- installs: develop=`/home/cubrid/release/CUBRID-develop-69e73b47`, redesign(release)=`/home/cubrid/release/CUBRID-11.5.develop`, debug=`/home/cubrid/debug/CUBRID-11.5.develop`.
- DB: tpch_sf10·wmloc·wmg003(TDE) in `/home/cubrid/databases`.
- golden: HASHJOIN `<200000` count=**200360**; `<2000000` count=**2000495**; DISTINCT 15M=`15000000/449999872500000/1/60000000`; wmloc DISTINCT=`4194304/8796090925056/0/4194303`.
- perf (work_mem=1G, `<200000`, cold 7회): redesign median **4.959s** (0.234×develop), develop median **21.206s**.

## 8) 이슈 #78 종료까지 로드맵 (2A-3 이후)
- [x] 2A-3 프로브(INNER) NEW 병렬 (`d517fc60c`)
- [x] 2A-3 outer probe NEW 병렬 (`b519ac5e4`)
- [x] 2A-3 split/partition NEW 병렬 (`09150351d`)
- [x] median ≤ develop×1.10 (0.234×)
- [ ] **세션 상태 오염 root-cause → CoV ≤ 15%** ← 이 프롬프트
- [ ] **#77 wmloc 재검증 + debug 셀프테스트 + 하드 카운터** ← 이 프롬프트
- [ ] (perf 후속) per-worker OUTPUT tape (ADR0004, part_mutexes 제거) — 별도 슬라이스
- [ ] 2A-4 인벤토리 A~E residual sweep
- [ ] 잔여 operator 출력 이주 점검 (analytic/UNION/rollup)
- [ ] 게이트 기본 ON 결정 (2A-EXIT 전제, full-suite 통과 후)
- [ ] 2A-EXIT 전수 심볼 sweep (Phase3 진입 전제)
- [ ] acceptance (a)–(g) 매핑 충족 → #78 CLOSE → Phase3(#74, 비가역 삭제)
