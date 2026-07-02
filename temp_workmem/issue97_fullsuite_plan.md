# #97 full-suite gates-ON 캠페인 실행 계획서 (2026-07-02, 준비 세션)

이 문서는 **계획서**입니다 — 실행은 하지 않았습니다. #97 착수 워커가 그대로 따라갈 수 있도록
구성/절차/판정 기준만 정리합니다. 코드 변경 없음, 서버 미기동.

## 0. 선행조건 확인 (착수 시점 재확인 완료)

`gh issue view <n> --repo xmilex-git/cubrid --json state` 기준, 아래 전부 `CLOSED`:

| 이슈 | 내용 | 상태 |
|---|---|---|
| #100 | 게이트 ON NUMERIC 집계 GROUP BY SIGABRT (`687a694b3`) | CLOSED |
| #103 | ANALYTIC over NEW — 정상 경로 없음 | CLOSED |
| #105 | CONNECT BY over NEW — parent-pos TAPE 좌표 punning | CLOSED |
| #94/#84/#85 | (본문 원 선행조건) | 착지 확인됨(HEAD 기준 재확인 요, 좌표 드리프트 전제) |

**주의**: 위 CLOSED 확인은 GitHub 이슈 상태 조회로만 했고, 실제 커밋이 `wm-integ-7173-develop`
HEAD(`8ef03fa18`, 이 세션의 픽스처 커밋 포함)에 반영돼 있는지는 착수 워커가 `git log --oneline
--all | grep <commit>`로 재확인할 것 — 이슈 상태와 브랜치 반영은 별개다.

## 1. gates-ON 실행 구성

### 1.1 공통 준비 (순서대로)

1. `git -C ~/dev/workspace pull` — campaign conf(`stored_procedure=no`, `c3e8a58`) 최신화.
2. `git -C /home/cubrid/dev/cubrid-workmem fetch xmilex && git rebase xmilex/wm-integ-7173-develop`
   (다수 세션 동시 착지 — re-ground 필수).
3. `WORKSPACE=/home/cubrid/dev/cubrid-workmem just build debug` (그리고 필요시 `release`) — **debug+release
   풀빌드 green 필수**, cubrid-build 스킬만 사용.
4. `WORKSPACE=/home/cubrid/dev/cubrid-workmem just conf` 적용 — PL 서버 우회(`stored_procedure=no`).
5. `export BUILD_WORKTREE=$HOME/dev/workspace` — `bench/harness/lib.sh`의 stale 바이너리 우선-선택 함정
   (#106) 회피. 모든 검증 보고에 `cubrid_rel` 출력 첨부(방금 빌드한 바이너리 증명, #97 함정 1).
6. 서버 기동/재시작은 **cubrid-server-control 래퍼만** — raw `cubrid server start|stop` 금지(파이프 hang).
7. 게이트 env(`CUBRID_WM_SCAN_NEW/SORT_NEW/HASHJOIN_NEW`)는 **서버 프로세스 기준** — 래퍼 호출 시
   env로 전달. csql 클라이언트 env는 무효. 기본값은 OFF(#82, `303fcc6bc`) — 이번 캠페인은 이 3개를
   전부 명시 `=1`로 켠 상태에서 실행한다.
8. 픽스처 로드(**wmloc_fixture_setup.sql** 등 CONNECT BY INSERT 포함 파일)는 반드시 **게이트 OFF**로
   수행 후, 검증 단계에서만 게이트 ON으로 전환(#97 함정 2 — #105 착지로 CONNECT BY 자체는 이제 게이트
   ON에서도 안전하지만, 관례상 데이터 준비/검증 단계 분리를 유지해 회귀 범위를 좁힌다).

### 1.2 SQL 스위트 (CTP `ctp.sh sql`)

**현재 확인된 한계**: `ctp-parallel` 스킬(`ctp_parallel.sh`)은 podman 컨테이너 기동 시
(`scripts/ctp_parallel.sh:757-763`) `CUBRID`/`CTP_HOME`/`CUBRID_DATABASES`/`TZ`/`LC_ALL` **5개
고정 env만 `-e`로 주입**한다. `CUBRID_WM_SCAN_NEW/SORT_NEW/HASHJOIN_NEW`를 컨테이너 내부 서버
프로세스에 전달하는 경로가 없다 — 이 상태로는 ctp-parallel 샤딩 그대로 gates-ON 풀스위트를 돌릴 수
없다.

두 가지 선택지:

- **옵션 A (권장, 1차 판정용)**: 샤딩 없이 **단일 호스트**에서 게이트 env를 export한 뒤
  cubrid-server-control로 서버를 올리고 `ctp.sh sql -c <sql.conf>`를 직접 실행. wall-clock은
  ctp-parallel 대비 길지만(비-샤딩 풀스위트, 참고: ctp-parallel 문서의 전체 스위트 규모는
  17,420 케이스) 이 캠페인의 목적(gates-ON 최초 실증)에는 정확성이 속도보다 중요.
- **옵션 B (후속, 이번 준비 범위 밖)**: `ctp_parallel.sh`에 `--env KEY=VAL` 같은 패스스루 플래그를
  추가하는 작은 스킬 개선을 별도 이슈로 분리해 제안. 이번 세션은 코드 변경 금지 범위라 이 개선 자체는
  하지 않았음 — 착수 워커가 필요 판단 시 supervisor에게 별도 이슈화를 요청할 것.

어느 옵션이든 실패 쿼리는 개별 최소화(단일 `.sql`로 축소) 후 이 이슈(#97)에 표로 보고, 원인 미상이면
`needs-info`로 개별 이슈 분리(§2 분류 절차 참조).

### 1.3 shell 스위트

CTP shell(`ctp.sh shell`)은 `cubrid-shell-run` 스킬이 개별 테스트/좁은 서브트리 디버그용으로
문서화돼 있으나, 이번 캠페인은 "해당 범위"(#97 본문 표현) 전체이므로 스킬의 단일 테스트 워크플로를
그대로 전체 스위트에 쓰지 말고, 호스트에서 게이트 env를 export한 서버 위에 `ctp.sh shell -c
<shell.conf>`를 직접 구동하는 방식을 쓴다. 실패 시 `cubrid-shell-run` 스킬로 개별 재현/디버그.

### 1.4 검증 규모 분리 (기존 house rule)

- debug 빌드 검증: `wmloc`/`wmg003` 규모(수백만 행 이하) — 5.12M행 wmloc_t 등.
- `tpch_sf10`: release 전용(debug 메모리 과다) — A/B/C 강제 쿼리셋, positioned 워크로드.

### 1.5 판정 표기

raw-stdout md5 금지. robust 집계(`COUNT(*)`/`SUM(CAST(col AS NUMERIC(38,0)))`/`MIN`/`MAX`,
`MOD(col,997)` 그룹핑) + `;trace on`의 `parallel workers: N>1` 실증 — 이번 세션이 커밋한
`bench/harness/queries/wmloc_{union,outer_join,merge_join,cte,connect_by}_parity.sql` 5종을
`bench/harness/parity.sh`(`DB_NAME=wmloc`)로 그대로 구동 가능.

### 1.6 perf 재측정

median ≤ develop×1.10, CoV ≤ 15%. heavy DISTINCT/PSORT는 현 구조상 미충족 가능 — 그 경우 사실대로
보고하고 기본 ON 재전환은 보류(#97 본문 §3 그대로).

## 2. 실패 분류 기준 (3분류) + 판별 절차

공통 0단계 — 모든 실패에 대해 먼저 수행:

1. 실패 쿼리/케이스를 최소 재현 단위로 축소(단일 `.sql` 또는 단일 shell testcase).
2. 동일 최소 재현을 **게이트 OFF**(`CUBRID_WM_*_NEW` 미설정 또는 `=0`)로 재실행.
3. 동일 최소 재현을 **트랙 이전 baseline**(`~/dev/cubrid-baseline` 또는 develop 상당 커밋 —
   착수 워커가 실제 존재하는 baseline 체크아웃 경로를 `ls ~/dev/` 로 재확인)에서 재실행.
4. 결정성 확인을 위해 동일 조건 3회 재실행.

| 분류 | 판별 기준 | 후속 조치 |
|---|---|---|
| **A. 이번 트랙 수정 탓** | 게이트 OFF에서 통과 **AND** baseline에서 통과 **AND** 게이트 ON(HEAD)에서만 재현 | 원인 커밋을 `git bisect`(temp-workmem 커밋 범위 내)로 특정 → 이 캠페인(#97) 또는 원인 이슈에 직접 수정 착지 |
| **B. 기존 flaky** | 게이트 OFF에서도 재현 **AND** baseline에서도 동일하게 재현 (3회 중 일부만 실패 = 간헐적) | 새 이슈로 만들지 말고 기존 이슈 검색(제목/증상 키워드) 후 링크, 없으면 `needs-info`로 개별 분리 — 이번 트랙 blocker로 취급하지 않음 |
| **C. 신규 버그** | 게이트 OFF/baseline **둘 다 통과** (결정적 재현) **BUT** 원인 코드가 이번 트랙 diff(`git diff baseline..HEAD -- src/`) **밖**에 있음 — 즉 게이트 ON이 새 코드 경로를 노출시켰을 뿐, 결함 자체는 기존 엔진 코드에 있었음 | 신규 이슈 생성(`triage` 스킬 경유 권장), #97에는 이슈 번호만 링크. 캠페인 자체는 이 결함을 캠페인 blocker로 보고하되 수정은 별도 이슈에서 진행 |

A와 C의 경계는 "원인이 이번 트랙 diff 안인가 밖인가" 하나로 가른다 — 둘 다 "게이트 ON에서만
재현"이라는 표면 증상은 같으므로, `git blame`/`git bisect`로 원인 라인이 실제로 temp-workmem
커밋(#73/#78 이하 계열)에 속하는지를 반드시 코드로 확인하고 판정 보고에 커밋 해시를 명시할 것 —
"게이트 ON에서만 터지니 트랙 탓"이라는 추정만으로 A로 단정 금지.

체크리스트 항목(#97 코멘트, #103 후속): ANALYTIC leg에서는 위 절차와 별개로 매 실행마다
`Num_qfile_new_backed_create` 델타를 기록 — serial 경로에서는 델타가 항상 0임이 이미 확인됨(#103).
`PARALLEL(N)` 힌트 하에서도 델타=0이면 판정 보고에 "ANALYTIC over NEW는 현재 도달 불가능한 방어
코드 상태"를 명시할 것(코드 신규 수정 불필요, 사실 기록만).

## 3. `external_sort.c:5606` 판정 실험

### 3.1 코드 근거 (이번 세션에서 정적 확인, 실행 없음)

`sort_start_parallelism()`(`external_sort.c`)의 두 분기를 대조:

- **ORDER BY/ORDER WITH LIMIT** (`:5413-5448`): `qfile_list_has_new_backing(input_file)`을
  **명시적으로 분기**해, NEW-backed면 `qfile::chunk_distributor`(tapeset-aware)를 쓰고, 아니면
  OLD `qfile_open_list_sector_scan`을 연다.
- **GROUP BY/ANALYTIC** (`:5595-5609`): 이런 분기가 **없다** — `input_list`의 backing kind와
  무관하게 무조건 `qfile_open_list_sector_scan(thread_p, input_list, ...)`을 호출한다(`:5609`).

**추가 확인(이번 세션에서 새로 읽은 사실 — #97 본문 작성 시점엔 없었을 정보)**:
`qfile_open_list_sector_scan()` 자체(`list_file.c:8677-8707`)에 **production-hard guard**가 이미
있다:

```c
int guard_rc = QFILE_GUARD_OLD_MECHANISM (list_id);   // list_file.c:8689
if (guard_rc != NO_ERROR) { return guard_rc; }
```

주석("OLD sector-scan input 메커니즘은 NEW(Tapeset) 리스트를 절대 받지 않는다, SSOT #75 round-3
(d)")대로, 이 가드가 이미 걸려 있으므로 **NEW-backed 입력이 실제로 이 함수까지 도달해도 크래시나
무음 오답이 아니라 클린 에러(`guard_rc`)로 반환된다** — `:5606-5609` 자체는 "무조건 OLD 분기"가
맞지만, 그 무조건성이 곧바로 오답/크래시를 뜻하지는 않는다(#97 본문의 "에러? 오답?" 중 최소
"크래시 아님"까지는 코드로 이미 답이 나와 있다). 미실증인 것은 (a) 이 경로에 NEW-backed 입력이
**실제로 도달하는가**, (b) 도달 시 사용자에게 보이는 최종 에러 메시지/폴백 동작이 무엇인가, 이 두
가지뿐이다.

### 3.2 구체 실험 시나리오 (착수 워커가 그대로 실행할 절차)

1. **재현 질의 구성**: 내부 서브쿼리 결과가 게이트 ON 하에서 NEW-backed로 전환된 뒤, 그 결과가
   외부 병렬 GROUP BY/ANALYTIC의 정렬 입력으로 들어가도록 중첩 질의를 만든다. 후보:
   ```sql
   SELECT /*+ PARALLEL(8) */ MOD(s,997) g, COUNT(*) c, SUM(CAST(s AS NUMERIC(38,0))) sm
   FROM (SELECT /*+ PARALLEL(8) */ DISTINCT id AS s FROM wmloc_t) t
   GROUP BY MOD(s,997);
   ```
   (내부 DISTINCT가 게이트 ON에서 NEW-backed 출력을 만들고, 그 출력이 외부 GROUP BY 병렬 정렬의
   `input_list`가 됨 — 이번 세션이 커밋한 `wmloc_union_parity.sql`/`wmloc_cte_parity.sql`도 동일
   원리로 서브쿼리 결과를 상위 집계에 흘려보내므로 대체 가능.)
2. **비침습 도달 확인**: 코드 수정 없이 `gdb -p <cub_server_pid>`로
   `qfile_open_list_sector_scan`에 breakpoint를 걸고, `list_id`의 backing kind
   (`QFILE_GUARD_OLD_MECHANISM` 진입 전 `list_id->type` 또는 `qfile_list_has_new_backing(list_id)`
   값)를 조건 없이 매 히트마다 기록 — 위 재현 질의 실행 중 이 함수가 NEW-backed list_id로 호출되는지
   확정한다.
3. **도달 시**: `guard_rc` 리턴값과 csql 클라이언트에 최종 노출되는 에러 텍스트를 채증하고,
   `Num_qfile_new_backed_create`/`Num_qfile_old_touch_on_new`(statdump) 델타로 교차 검증(§1.5의
   parity.sh `check_wm_engagement` 패턴 재사용 가능).
4. **도달 불가 시**(예: #100/#103 수정 이후 GROUP BY/ANALYTIC 상위 레이어가 이미 입력을 OLD로
   강제하고 있어 `:5609`까지 NEW-backed가 살아서 못 옴): §2 체크리스트의 ANALYTIC 판정과 대칭되는
   결론 — "GROUP BY 병렬 정렬의 NEW 분기 부재는 현재 도달 불가능한 방어 코드 상태"임을 판정 보고에
   명시. 이 경우 #97 본문 §2-c의 (i)(NEW 분기 이주)/(ii)(NEW 입력 시 serial 강제) 수정은 **불필요**
   — "사실 기록"만으로 종결 가능.
5. **도달 가능 판정이면**: (i) chunk_distributor 패턴을 GROUP BY/ANALYTIC에도 복제하거나 (ii)
   NEW-backed 입력 감지 시 해당 정렬을 serial로 강제하는 두 옵션 중 택1 구현 — 이 구현 자체는 이번
   준비 세션 범위 밖(코드 수정 금지), 착수 워커가 실험 결과를 갖고 별도로 진행.

### 3.3 이 실험이 이번 세션에서 실행되지 않은 이유

이번 세션은 "문서/픽스처/조사만" 범위로 제한되어 서버 기동·gdb attach·실제 질의 실행을
수행하지 않았다. §3.1의 코드 대조(정적 리딩)까지가 이번 세션의 산출물이고, §3.2는 착수 워커를 위한
실행 계획이다.

## 4. Acceptance criteria 대응표 (#97 본문 대비)

| #97 AC | 이번 준비 세션 산출물 | 착수 워커 잔여 작업 |
|---|---|---|
| full-suite gates-ON 결과표 | §1 구성 계획 | 실제 실행 + 결과표 작성 |
| 잔여 5개군 robust parity 증적 | `bench/harness/queries/wmloc_{union,outer_join,merge_join,cte,connect_by}_parity.sql` 커밋(`8ef03fa18`) | `parity.sh`로 실제 구동 + proof 커밋 |
| :5606 reachability 판정 | §3.1 정적 코드 근거 + §3.2 실험 절차 | gdb 실측 + 판정 확정 |
| perf 측정치 보고 | §1.6 기준 재확인 | 실측 |
| 기본 ON 재전환 또는 #80 차단 보고 | (판단 불가 — 실행 후 결정) | 위 전부 완료 후 결정 |
