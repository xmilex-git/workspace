# 스펙: bulkidx 리뷰 대응 구현 (CBRD-27071 머지 게이트) — 새 세션 인수인계 정본

작성 2026-07-18. grill 세션(보스 승인)으로 확정된 범위·설계·규율의 단일 문서.
이 문서만 읽고 착수 가능해야 한다. 충돌 시 우선순위: 본 문서 > ADR-0003/0004 > 리뷰 원문.

## 0. 한 줄 목표

`xmilex/bulkidx/noredo-parallel-r304-wip`(HEAD `d3e8dc262`)의 코드리뷰
(`docs/code-review-bulkidx-noredo-parallel-r304-wip.md`, BLOCK 판정) **P1 10건 + P2 5건 전부**를
수정·검증하고 push한다. 완료 후 JIRA CBRD-27071에 혼합-버전 강등 정책 코멘트를 게시한다.

## 1. 확정 결정 (변경 금지)

1. **ADR-0003** (`docs/adr/0003-...create-lsa.md`): P1 4·5·6은 **server-issued create LSA 단일
   identity**로 통합 봉인. marker `create_token` = 파일 생성 시점의 create LSA(서버 발급),
   서버측 pending-build 상태(BTID·create LSA·class set)를 등록하고 publication은 정확 일치만
   허용. suppression/cleanup은 `(VFID, create LSA)` 정확 일치, 모호하면 fail-safe(억제·삭제 안 함).
2. **ADR-0004** (`docs/adr/0004-...auto-fallback.md`): P1 8은 **혼합 버전 자동 강등** — log 호환
   게이트에 걸리면 marker 발행 금지 + legacy 전체-로깅 빌드로 자동 전환 + 서버 에러로그
   NOTIFICATION 1줄("bulk build fell back to the logged path: incompatible log consumer").
   P1 7(wire versioning)은 이 게이트의 선행 조건으로 동반.
3. **범위**: P2 5건 전부 이번 머지 게이트 포함 (보스: "전부 포함").
4. **성능 판정 완료**: 15건 중 빌드 핫패스를 늦추는 수정 없음. 11·12·14는 개선. 유일한 성능
   시나리오는 ADR-0004의 혼합-버전 기간 강등(의도된 정책). 재검토 불요.

## 2. 스펙 경계 (구현 제약 — 위반 시 스펙 변경이 돼버림)

- **CREATE INDEX(와 그 marker의 복구) 밖의 서버 동작 변화 금지.** grill에서 코드로 확인:
  `log_is_irreversible_2pc_state` 호출자는 log_recovery.c:7011(bulk 분류) 1곳,
  `locator_bulk_force_tail_unpack`은 bulk 전용 — 이 국소성을 유지할 것.
- **(a) FILE_HEADER에 새 필드 추가 금지.** create LSA는 btree용 `FILE_DESCRIPTORS` 유니온의
  기존 공간 안에 크기 불변으로 저장(디스크 포맷 불변). 불가능 판명 시 중단하고 보스 보고.
- **(b) record 130의 log 호환 레벨 선언은 릴리스 호환성 표 사안** — 새 런타임 스펙 표면을
  만들지 말 것. 유일한 신규 사용자 가시 동작 = ADR-0004의 강등 + NOTIFICATION.
- 일반 FORCE의 ignore list, 일반 2PC, DML/SELECT/일반 백업·복구/replication 경로 불변.

## 3. 작업 항목 (승인된 순서)

리뷰 원문 라인 위치는 `docs/code-review-...md` 기준(merge-base `39bdc0a77`). 현재 HEAD는
`d3e8dc262`(주석 정리+indent)라 라인이 몇 줄 어긋날 수 있음 — 심볼명으로 찾을 것.

### 단계 1 — 기계적 수정 (P1 1·2·3 + P2 13·15)

| # | 위치 | 수정 |
|---|---|---|
| 1 | `btree_bulk_unique_absent_repair` exchange 경로 (btree.c ~32427) | compensate append 후 write latch 보유 상태에서 `pgbuf_set_dirty (thread_p, leaf_page, DONT_FREE)` |
| 2 | `locator_sr.c` FORCE topop (attach ~7550, marker ~7553) | marker size/alloc/pack/append를 **attach 전**(abort 가능 시점)으로 이동, 모든 실패는 abort 라벨로. 순서: parent LSA < publication < marker < sysop attach < commit |
| 3 | `log_is_irreversible_2pc_state` (log_manager.c ~3626) | `TRAN_UNACTIVE_COMMITTED_INFORMING_PARTICIPANTS`도 irreversible로 인정 |
| 13 | `external_sort.c` B5 run 반납 (~5867) | `file_temp_retire` rc 확인 — 성공 시에만 `VFID_SET_NULL`, 실패는 빌드 에러로 전파 |
| 15 | `locator_bulk_force_tail_unpack` (network_interface_cl.c ~822, ~917) | caller-owned owner buffer/capacity로 정확 길이 복사 + NUL — packed buffer 내부 포인터 반환 금지 |

### 단계 2 — identity 묶음 (P1 4·5·6 + P2 11, ADR-0003)

- 파일 생성 시 create LSA 캡처 → btree FILE_DESCRIPTORS에 저장(§2-a), marker `create_token` 교체.
- 서버측 pending-build 등록(트랜잭션 상태): BTID·create LSA·expected class set. publication/commit은
  정확 일치 marker만 허용, 클라이언트 `eligible_no_redo`/LSA/class set은 힌트로 강등.
- suppression(log_recovery.c ~7122)·cleanup identity(~7634)를 `(VFID, create LSA)` 일치로 재작성,
  모호 시 no-suppression/no-delete fail-safe.
- **P2 11 동시에**: completion event 추적을 "marker가 수집된 transaction만"으로 축소(자료구조가
  pending-build와 겹침), completion LSA/incarnation 저장.

### 단계 3 — 호환 묶음 (P1 7·8 + P2 12, ADR-0004)

- BTREE_LOADINDEX capability bit(또는 신규 opcode): legacy peer에는 `eligible_no_redo=false` +
  기존 request/reply layout 그대로(WITH ONLINE 포함).
- log 호환 게이트: 비호환 log consumer 존재 시 marker 미발행 + legacy 빌드 강등 + NOTIFICATION 1줄.
- **P2 12 동시에**(suppression과 같은 파일): marker 0개면 redo당 검사 자체를 건너뛰는 global
  fast path + VFID/volume 기반 active-marker 색인.

### 단계 4 — P2 14 (ovf pool bootstrap)

- `bt_load_provider_...` ovf pool(btree_load.c ~4889)의 `est_ovf_pages` 전량 동기 선할당을 B4와
  동일한 bootstrap(워커당 소량)+기존 `NEED_OVF` 리필로 교체.
- **주의**: overflow-key workload는 ovf 페이지 소비율이 main보다 높다 — 리필 청크를 64→256급으로
  상향 검토하고, 반드시 overflow workload(VARCHAR(2100), 8M급) 실측으로 회귀 없음을 증명.

### 단계 5 — P1 9·10 (클라이언트 경로)

- 9: post-force descriptor/OID 처리 + root-class refetch(`au_fetch_class`)를 공용 helper로 —
  legacy 경로(locator_cl.c ~4146)와 동작 일치(parity 복원), 실패 시 savepoint rollback.
- 10: `has_bulk_desc`이면 비어 있지 않은 ignore list를 서버가 거부 + 클라도 ignored error 없이 FORCE.

## 4. 검증 계획 (리뷰 §검증 요구사항 11행의 이행)

**전 항목 harness-v3 규율(§5)로.** 매핑:

1. repair dirty 회귀: kill-hook diag로 repair 직후 checkpoint→kill→restart, 페이지 내용 검증 (행 1)
2. marker 경계 crash: pack/alloc 실패 주입 + marker/attach/commit 각 지점 kill-hook (행 2)
3. 2PC 두 crash boundary: commit-decision / informing-participants 상태에서 restore (행 3)
4. identity: DROP 후 동일 VFID 재사용 + 같은 초 재생성 + replacement index 보존 — ADR-0003으로
   한 축 (행 4)
5. server rejection: legacy empty-tail FORCE, BTID/create-LSA/class-set 불일치 (행 5)
6. **mixed-version 4조합 + old-reader/new-WAL/rolling**: "구버전 peer"는
   `/home/cubrid/release/CUBRID-bulkidx-develop-ref`(merge 직전 develop=곧 구버전) 재사용 —
   별도 준비 불요 (행 6)
7. marker-bearing FORCE partial error + interrupt/cancel/savepoint rollback (행 7)
8. 성공 직후 동일 CS 세션 DML/DDL의 catalog representation (행 8)
9. temp retire 실패 주입 + overflow-key provider 성장 (행 9)
10. 다수 marker + 대형 redo window에서 restart CPU/메모리 상한 — P2 11·12의 효과 증명 (행 10)
11. **기존 안정성 매트릭스 재수행**: U-OV3(3변형×3) / killsweep K1-K5×2(diag) / kill-switch
    4조합 / empty·1행 / serial-path / U-MARKER-MICRO — 러너와 판정 기준은
    `artifacts/u-g008/matrix-b5/SUMMARY.md`와 `/home/cubrid/dev/bkx-b5/harness-v3/
    {b5-matrix-lanes.sh,b5-killsweep.sh}` 그대로 재사용 (행 11)
12. **성능 재확인**: 20G fixture(dev vs 수정 tip, campaign convention: cold restart·교대·
    warmup1+valid3) — B5 결과(171.7s, dev 대비 3.75×) 대비 유의미 후퇴 없어야 함. overflow
    workload는 단계 4에서.

## 5. 운영 규율 (기존 context의 주의사항 — 전부 강제)

### 검증: 타임아웃 빡세게 + 소범위 + 릴리즈 우선
- **타임아웃**: harness-v3 §0 — 모든 `timeout N`은 `t_budget()` 경유(원시 timeout 금지), 상한표
  (createdb 120s / CREATE INDEX 120s / SA checkdb 120s / 백업·복원 300s / 기타 csql 60s).
  여유가 필요하면 `BKX_TIMEOUT_SCALE` export로만 — 기본값 인상 금지.
- **소범위**: TIER-A(~100행, **diagdb 유일 허용 지점**) / TIER-B(50k, t_ovf_m1=100k, 볼륨
  512M/256M). 대형 픽스처 신규 생성 금지. 20G는 §4-12 성능 재확인 한정(기존 fixture 재사용:
  `artifacts/u-g008/perf-20g/runtime-{dev,b2f}`).
- **릴리즈 우선, 에러 시에만 디버그**: 모든 검증은 release 설치본. 실패 재현·원인 규명에만
  debug(축소 재현 전용). 이번 매트릭스에서 debug가 필요했던 적 없음.
- **gdb breakpoint 개입 금지.** crash 재현은 kill-hook diff(`harness-v3/b3-kill-hooks.diff` 계열,
  `BKX_B2_KILL` env 규약) + 외부 kill -9 산포만. core는 lib-cleanup의 postmortem 훅(즉시 발췌·
  즉시 삭제)만.

### 서버 제어 (SSOT)
- **서버 start/stop은 반드시** `.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh`
  (raw `cubrid server start`를 파이프 아래서 돌리면 fd 상속으로 영구 hang). `CUBRID_SERVER_CTL_LOGDIR` 지정.
- **cub_master env 상속 함정**: `BKX_B2_KILL` 같은 서버측 env는 **master가 그 env로 새로 떠야**
  cub_server에 전달된다. 트라이얼마다 master 완전 종료(TERM→사망 대기 최대 10s→KILL) 후 재기동.
- **auto-restart 함정**: kill 계열 검증은 conf에 `auto_restart_server=no` 필수 — 없으면 master가
  죽은 서버를 (오염된 env로) 되살려 오탐을 만든다. 발화 판정은 서버 PID 변화 기준.
- 세션 종료 시: 서버 stop → 잔존 cub_master TERM으로 reap → 포트(1550/1551 등) free 확인 →
  임시 DB `cubrid deletedb`.

### 빌드
- **반드시** `WORKSPACE=<worktree> just build <mode> <전용버전명>` + **`INSTALL_PREFIX`로 격리**
  (`~/CUBRID` symlink·공용 설치본 오염 금지 — 사고 전례 있음).
- 커밋 게이트 = **debug+release 빌드 green** (그 외 slice 게이트 없음, 검증은 캠페인으로).
- kill-hook diag 빌드: diff 적용 → 별도 INSTALL_PREFIX로 빌드 → **소스 즉시 원복** →
  `git status`로 clean 재확인(cubrid-cci dirty만 정상). 현존 `CUBRID-b5diag-matrix-local`은
  `82f2d7639`+hooks 기준이라 **수정 tip 기준으로 재빌드 필요**.
- conf 변경은 라이브 파일 sed 금지 — 후보 사본에 섹션 append → diff 검증 → 교체, 종료 시
  백업으로 복원(diff 재검증). harness의 `apply_conf_section` 패턴 재사용.

### 코드/커밋 위생
- **주석에 세션 내부 지식 금지**: 태그(B4/B5류), stage/receipt/defect id, 측정 수치, 계획 문서
  참조 — `d3e8dc262` 수준 유지(단일 이슈 스쿼시 머지 전제).
- **indent**: GNU indent 2.2.11 `--gnu-style -l120 -lc120 -ts8`, **변경 라인과 교차하는 hunk만**
  적용(업스트림 포맷 불가침). `(size_t) x *CONST` 류 indent 산출은 업스트림 관례이므로 유지.
- push는 **xmilex** remote만 (origin은 push 금지 URL로 봉인돼 있음).

### 기타 함정 (이번 캠페인 실전 교훈)
- 백그라운드 장기 작업은 `setsid nohup ... < /dev/null &` — 아니면 tool 호출 종료와 함께 사살됨.
- 스캔 대조 쿼리는 `... WHERE k >= '' USING INDEX <name|NONE>` (MySQL식 `USE INDEX (...)` 아님).
- csql 카운트 파싱: `awk '/^[[:space:]]*[0-9]+[[:space:]]*$/{n=$1} END{print n+0}'` (타이밍 줄 오파싱 방지).
- PATH를 CUBRID bin으로 덮어쓸 때 python3 경로 소실 주의(`/home/cubrid/.local/bin` 포함).
- `/tmp`·`$TMPDIR` 스크래치 금지(tmpfs OOM). 증거 파일 20MB 상한(`bounded_save`), 행당 ≤2GB 즉시 정리.
- `log_btree_operations=yes`는 레코드당 2줄 — 대형 빌드에 절대 금지, TIER 소형 전용.

## 6. 완료 후 조치 (순서대로)

1. 전 항목 green + 매트릭스/성능 증거 정리(20MB 상한) → status report(`docs/`) 작성.
2. push (`xmilex bulkidx/noredo-parallel-r304-wip`).
3. **JIRA CBRD-27071 코멘트 게시** (보스 지시: 구현 전부 완료 후):
   - 내용: 리뷰 대응 완료 요지 + **ADR-0004 강등 정책**(강등 조건, NOTIFICATION 관측, 동일 버전
     클러스터 비용 0) + 브랜치 최신 커밋 링크. Description의 Specification에 강등 불릿 추가 검토.
   - 절차(검증된 방법): 자격증명 `~/.config/cubrid-skills/jira.env`, 초안은
     `.git_ignored_dir/jira/CBRD-27071/`에 저장(JIRA wiki markup, `cubrid-jira-issue-write` skill
     톤 가이드 준수) 후 REST `POST .../issue/CBRD-27071/comment`. 게시 후 재조회로 검증.
4. `docs/review-response-bulkidx-decisions.md`의 체크박스 갱신.

## 7. 참조 자산

- worktree: `/home/cubrid/dev/worktrees/r304-bulkidx` (branch `bulkidx/noredo-parallel-r304-wip`,
  HEAD `d3e8dc262`, merge-base `39bdc0a77`). cubrid-cci dirty는 의도적 보존.
- 설치본: release tip `CUBRID-b5merge-matrix-local` / develop 기준(구버전 peer 겸)
  `CUBRID-bulkidx-develop-ref` / diag(재빌드 필요) `CUBRID-b5diag-matrix-local` — 전부 `/home/cubrid/release/`.
- harness: 정본 `.not_git_tracking/bulk_index_build/harness-v3/` + 로컬 실행 사본
  `/home/cubrid/dev/bkx-b5/harness-v3/`(b5-matrix-lanes.sh, b5-killsweep.sh 포함 — 이번 매트릭스
  실측 검증 완료본).
- 문서: 리뷰 원문 `docs/code-review-bulkidx-noredo-parallel-r304-wip.md`, 결정 원장
  `docs/review-response-bulkidx-decisions.md`, ADR-0001~0004, 최근 보고
  `docs/status-report-20260718-bulkidx-b{4,5}.md`, 성능 후속 원장
  `.not_git_tracking/bulk_index_build/perf-followups.md`(2·3위는 이번 범위 아님 — P2 12와 혼동 금지).
- 매트릭스 선례: `artifacts/u-g008/matrix-b5/SUMMARY.md`(판정 기준·하네스 결함 교훈 포함).
