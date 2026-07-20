# 인계서: no-redo 병렬 인덱스 빌드를 loaddb "명시 옵션" 게이트로 전환 (2026-07-20)

새 세션 착수용 정본. 직전 완결 작업의 인계서(`docs/handoff-bulkidx-loaddb-pivot-20260720.md`)와
최종 보고(`docs/status-report-20260720-bulkidx-loaddb-pivot.md`)를 전제로 하며, 환경/규율은
그 문서들이 상위 참조다. 충돌 시 본 문서 > ADR-0006 > 이전 인계서.

## 0. 목표 한 줄

현재는 **CS 모드 loaddb면 무조건 자동 발화**(no-redo 병렬 인덱스 빌드 + replay 차단벽)다.
이를 **loaddb에 특정 옵션을 준 경우에만 발화**하도록 바꾼다(기본 = 기존 로깅 빌드).
보스 지시로 ADR-0006의 "loaddb 옵션 신설 없음" 결정이 뒤집혔다 — ADR 개정 필수.

## 1. 현재 상태 (전부 완결·push됨 — 미커밋 WIP 없음)

- worktree: `/home/cubrid/dev/worktrees/r304-bulkidx`, branch `bulkidx/noredo-parallel-r304-wip`,
  HEAD `88f74c4a2` (xmilex push 완료). merge-base `39bdc0a77`.
  - `587c8236e` 커밋 A: loaddb 한정 피벗 + 이전 기계(identity/pending/발행 marker/청소 walk/
    클라 배선) 전체 삭제. 잔존 diff = 17파일 +4,211/−926.
  - `88f74c4a2` 커밋 B: scoped barrier → 전역 flush 승격(단독 revert 가능하게 분리했으나
    **실측에서 A보다 15% 빨라 유지 확정**).
- **불가침**: `cubrid-cci` submodule dirty, `.gjc-install-debug/` untracked — 보존.
  reset/checkout/stash/clean 금지. push는 **xmilex remote만**.
- JIRA CBRD-27071: Summary = "Support no logging-per-page parallel index build",
  본문/첨부(analysis·verification·tc-bundle) 최신화 완료, 코멘트 4775284.
  옵션 게이트가 들어가면 **본문 Specification·첨부 전부 재갱신 대상**.
- 문서: ADR-0006(§2에 "옵션 신설 없음" 문구 있음 — 개정 대상), ADR-0003/4/5는 superseded.
  결정 원장 `docs/review-response-bulkidx-decisions.md`.

## 2. 관련 코드 지도 (HEAD `88f74c4a2` 기준)

| 위치 | 내용 |
|---|---|
| `network_interface_sr.cpp` ~4715-4719 (`sbtree_load_index`) | **적격성 술어의 현 위치**: `eligible_no_redo = BOOT_IS_LOADDB_CLIENT_TYPE (logtb_find_client_type (thread_p->tran_index)) && index_status != OR_ONLINE_INDEX_BUILDING_IN_PROGRESS` → `xbtree_load_index(..., eligible_no_redo)` |
| `boot.h` :56-60 | `BOOT_IS_LOADDB_CLIENT_TYPE` (LOADDB_UTILITY + ADMIN_LOADDB_COMPAT_UNDER_11_2/11_4) |
| `btree_load.c` :1240 부근 | `load_args->no_redo = eligible_no_redo` (SERVER_MODE에서만 — SA 구조 배제) |
| `btree_load.c` :1392-1441 | 커밋 전 전역 flush 관문 + barrier append(`RVBT_BULK_BUILD_DURABLE`, payload 0) |
| `external_sort.c` :1532, :5744(+`sort_check_parallelism` :6061) | 직렬 강등 2지점(병렬 미관여 시 no_redo 해제 — 옵션과 무관하게 유지) |
| `log_recovery.c` :3261-3285, :3594-3606 | restoredb 거부: media crash + barrier 조우 + **빌드 트랜잭션이 replay 창 안에서 완결**(트랜잭션 테이블 부재)일 때만 fatal. 크래시/시점복원 창은 undo가 파일째 제거 → 통과 |
| `recovery.h/.c` | `RVBT_BULK_BUILD_DURABLE = 130`, no-op redo 등록 |
| `msgcat_set_log.hpp` 31 + `msg/{en_US,ko_KR}.utf8/cubrid.msg` §16(LOG)의 31 | 거부 안내문(영/한) |
| `load_db.c` :586-595 | loaddb 클라이언트 타입 선택(-u dba + `--no-user-specified-name` → COMPAT_11_2) |
| `load_db.c` :1321, `utility.h` :1366-1367 | **기존 `--no-logging`(LOAD_IGNORE_LOGGING) 옵션이 이미 존재** — 데이터 로드용, `load_common.hpp:110 ignore_logging`으로 CS 세션 args에 직렬화되어 서버 load session까지 전달됨(`load_sa_loader.cpp:6390`은 SA 소비처). 단 `-i` 인덱스 파일 실행은 load session이 아니라 일반 SQL 실행 경로라 이 플래그가 인덱스 빌드에 자동 전달되지는 않는다 |
| `xserver_interface.h`, `network_interface_cl.c` :~6510 | `xbtree_load_index` 시그니처(SA 직결 호출부는 false 고정) — 현재 wire는 upstream과 동일 |

## 3. 설계 결정 포인트 (새 세션에서 grilling으로 확정할 것)

1. **옵션 이름과 기존 `--no-logging`의 관계** — 최대 분기점.
   - (a) 기존 `--no-logging`에 인덱스 빌드 의미를 확장(별도 옵션 없음): 의미론이 이미 "로깅
     포기 + 이후 백업 필수"라 자연스럽지만, 기존 옵션의 동작 범위(데이터 로드)가 함께 걸려
     스펙이 섞인다. 기존 옵션이 CS 모드에서 실제 뭘 하는지 먼저 확인 필요.
   - (b) 신규 전용 옵션(예: `--no-logging-index` 류): 표면이 깨끗하고 독립 문서화 가능. 권고.
   - (c) 시스템/세션 파라미터: 보스가 과거 kill-switch 파라미터를 전부 제거시킨 이력이 있어
     비권고.
2. **옵션 → 서버 전달 경로** (클라이언트 무지 원칙이 깨지는 지점 — 어디까지 되살릴지):
   - (a) **BTREE_LOADINDEX 요청에 플래그 1개 재도입**: 이전 설계에서 쓰다가 커밋 A에서 제거한
     배선의 최소 부활(요청 int 1개, 응답 불변). cas/서버 동일 버전 정책이라 협상 불요.
     구현 소요 최소: `btree_load_index()`(클라, network_interface_cl.c) → 요청 pack →
     `sbtree_load_index` unpack → 술어 AND. 단점: wire diff 0 원칙 포기(1필드).
   - (b) 접속/세션 상태로 전달(예: loaddb가 세션 파라미터·세션 커맨드로 서버에 마크): wire
     불변이지만 새 세션 상태 표면이 생긴다. "새 런타임 스펙 표면 금지"였던 이전 제약과 충돌.
   - (c) 클라이언트 타입 분화(예: LOADDB_UTILITY_NOLOG): 타입 공간 오염 + compat 매트릭스
     2배. 비권고.
   - 권고: (a). 판정은 여전히 서버가 최종(클라 값은 요청 의사표시, `BOOT_IS_LOADDB_CLIENT_TYPE`
     검사와 AND — loaddb 아닌 클라이언트가 플래그를 보내도 무시).
3. **옵션 없는 CS loaddb = 완전 기존 동작**(barrier 0, 전체 로깅) — 새 기본 대조군.
4. compat 모드(`--no-user-specified-name`)에서도 옵션 허용? (권고: 허용 — 이관 플로우가 주 사용처)
5. SA 모드 + 옵션: 무시 vs 에러? (권고: 경고 없이 무시 — 기존 SA 배제 구조 유지. 단 문서 명시)
6. 옵션 + WITH ONLINE / 직렬 강등: 현행 유지(옵션은 필요조건 추가일 뿐).
7. ADR-0006 개정: §2 "옵션 신설 없음" 삭제·사유 기록(운영자 명시 opt-in으로 차단벽/백업 계약을
   인지시키는 방향). JIRA Description의 "옵션을 만들지 않는다" 불릿도 교체.

## 4. 서버 구동/빌드 유의사항 (이번 세션 실전 교훈 — 전부 실제로 밟았던 함정)

- **빌드**: `WORKSPACE=<worktree> just build <mode> <전용버전명>` + `INSTALL_PREFIX` 격리
  (`~/CUBRID` 공용 설치본 오염 금지). 커밋 게이트 = release+debug 둘 다 green.
- **`just build`가 설치본 `conf/cubrid.conf`를 초기화한다** — 빌드 후 매번 오버라이드 재적용:
  `parallel_sort_page_threshold=1`(기능 레인 필수), `log_max_archives=100`(복원 레인),
  `auto_restart_server=no`(kill 레인). ※ 이걸 빼먹으면 소형 픽스처가 **조용히 직렬 강등되어
  기능이 꺼진 채 PASS**한다 — 직전 세션 "marker=0" 소동의 절반이 이것.
- 서버 start/stop은 `.agents/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh` 경유
  (raw `cubrid server start`를 파이프 밑에서 돌리면 fd 상속으로 hang). 부득이 raw로 돌릴 땐
  `>file 2>&1 </dev/null` 필수.
- kill 레인: 발화 판정은 서버 PID 변화 기준, 잔존 cub_master reap, 트라이얼마다 master 재기동
  (env 상속). 백그라운드 장기 작업은 `nohup setsid ... >log 2>&1 </dev/null & disown` (plain
  `setsid nohup ... &`는 tool 호출 종료와 함께 죽은 사례 있음).
- `/tmp`·`$TMPDIR` 스크래치 금지(tmpfs OOM), gdb/코어 기반 검증 금지, **core 파일 생기면 즉시
  삭제**(ulimit -c 0 습관화 — diagdb가 죽으면서 846MB 코어를 남긴 사례 있음).
- csql 카운트 파싱: `awk '/^[[:space:]]*[0-9]+[[:space:]]*$/{n=$1} END{print n+0}'`.
  스캔 강제: `... WHERE k >= '' USING INDEX <name>`. `restoredb -d` 시각 형식: `dd-mm-yyyy:hh:mm:ss`.

## 5. TC 유의사항 (tc-bundle v2 기준 — 옵션 게이트가 바꿀 것 포함)

- 현행 TC: `~/dev/workspace/.git_ignored_dir/jira/CBRD-27071/tc-bundle-v2/`
  (`tc-loaddb-basic.sh`, `tc-crash-restart.sh`, `tc-replay-barrier.sh`, `lib-oracle.sh`,
  `sql/fixture-tc.sql` + `sql/tc_indexes`). **3종 전부 현 HEAD에서 실행 green 확인된 상태.**
  JIRA 첨부 `CBRD-27071-tc-bundle.tar.gz`가 이 내용.
- 옵션 게이트 반영 시 TC 매트릭스 변화:
  - 기존 발화 레인(P1/compat/재기동/복원) 전부에 **옵션 추가** 필요.
  - **신규 대조군: 옵션 없는 CS loaddb = 비발화(barrier 0, COPYPAGE 다수)** — 이게 새 기본
    동작의 핵심 증명. SA+옵션(무시) 레인도 추가.
- 오라클 함정 (전부 v2에서 이미 밟고 고친 것 — 재발 금지):
  - **발화 계수는 역방향 diagdb 덤프로만**: 정방향 전체 덤프(`diagdb -d 8`)는 중간 레코드에서
    조용히 죽는다(rc=254, **develop 바이너리도 동일 재현 = upstream 결함**). `lib-oracle.sh`의
    `barrier_count`(역방향, npages=-1) 재사용.
  - 좁은 tail 윈도우 금지: 이후의 로깅 활동(csql 빌드 등)이 barrier를 윈도우 밖으로 밀어내
    오판을 만든다(전체 역방향이 기본).
  - `grep -c`는 매치 0일 때 "0"을 출력하고도 exit 1 → `|| echo 0` 붙이면 "0\n0"이 된다.
  - barrier는 **인덱스 빌드당 1건**(인덱스 파일에 문장 3개면 3건).
  - csql 음성 레인의 인덱스는 기존 인덱스와 **컬럼 구성이 겹치면 중복 정의로 거부**된다
    (PK(id)와 (id) 인덱스 충돌 사례).
  - 복원 레인 순서 고정: **사후백업 복원 → full replay 거부 → 시점복원(-d)** —
    시점복원의 resetlog가 로그 체인을 절단하므로 그 뒤에 다른 백업을 복원하면 hang.
  - loaddb 산탄: `<db>_loaddb.log`, `<db>_bkvinf` 잔여 파일 정리, `databases.txt` 등록 정리.
- compat 발화 트리거는 `-u dba --no-user-specified-name` 조합(그냥 `-u dba`는 LOADDB_UTILITY,
  `-u 없음`은 PUBLIC 로그인이라 스키마 권한 에러).

## 6. 검증 자산 / 설치본 / 픽스처

- 설치본: tip release `/home/cubrid/release/CUBRID-review-response-release`,
  debug `.../CUBRID-review-response-debug`, develop 대조군 `.../CUBRID-bulkidx-develop-ref`.
  (옵션 작업 후 재빌드하면 conf 재적용 잊지 말 것 — §4.)
- 50k 픽스처(unload 형식 3파일): `/home/cubrid/dev/bkx-review-response/evidence/adr0006/unload/`
  (`reviewresp_tb_{schema,objects,indexes}`) — loaddb E2E 레인 그대로 재사용 가능.
- 20G 성능: 픽스처 `~/dev/workspace/.not_git_tracking/bulk_index_build/artifacts/u-g008/perf-20g/
  runtime-{dev,b2f}`(194G/112G, 보존됨), 러너 `/home/cubrid/dev/bkx-review-response/
  measure-20g-pivot.sh`(loaddb 주도, 3-way 교대, conf 준비/원복 포함), 결과
  `.../evidence/perf-20g-pivot/measurements.tsv` — dev 669.2s / scoped 231.6s / **전역 196.0s
  (3.41×)**. 옵션 게이트는 핫패스 불변이라 성능 재측정은 원칙적으로 불요(스모크면 충분).
- JIRA 자격증명 `~/.config/cubrid-skills/jira.env`, 초안 디렉토리
  `~/dev/workspace/.git_ignored_dir/jira/CBRD-27071/` (REST 절차·payload 예시 파일들 잔존).

## 7. 완료 조건 (옵션 게이트 작업의 게이트)

1. 옵션 설계 grilling 확정(§3의 1·2번이 핵심) → ADR-0006 개정.
2. 구현: 기본 OFF, 옵션 ON시에만 술어 성립. 서버 최종 판정 원칙 유지(클라 값은 의사표시).
3. release+debug 빌드 green, indent는 GNU indent 2.2.11 `--gnu-style -l120 -lc120 -ts8`을
   변경 hunk에만(선례: `/home/cubrid/dev/bkx-b5/style-pass.py <repo> 39bdc0a77 <files>`).
   주석에 세션 내부 지식(태그/수치/계획 참조) 금지 — 단일 이슈 스쿼시 머지 전제.
4. TC v2 개정(옵션 on/off 매트릭스) + **전 스크립트 실행 green 후** JIRA 첨부 교체.
5. 검증: 옵션 ON 발화 / 옵션 없음 비발화 / compat+옵션 / SA+옵션 무시 / 재기동 / 복원 3종.
6. push(xmilex) → JIRA Description(옵션 명시, "옵션을 만들지 않는다" 불릿 교체)·analysis·
   verification·tc-bundle·코멘트 갱신 → 결정 원장·status report 기록.
