# CBRD-27071 no-redo parallel index build — 세션 인계서

작성 시각: 2026-07-20

## 1. 지금 하던 일

기존의 **일반 DDL까지 지원하는 no-redo 병렬 인덱스 빌드** 구현이 복구·HA·2PC·혼합 버전·클라이언트 wire까지 너무 넓어져 머지하기 어려워졌다. 승인된 방향에 따라 기능을 **CS 모드 `loaddb` 전용**으로 축소하고, 가능한 코드를 삭제하는 작업을 진행 중이다.

구현 워크트리:

```text
/home/cubrid/dev/worktrees/r304-bulkidx
branch: bulkidx/noredo-parallel-r304-wip
HEAD: 7d0a58740
remote: xmilex/bulkidx/noredo-parallel-r304-wip (현재 HEAD까지 push됨)
```

문서 워크스페이스:

```text
/home/cubrid/dev/workspace
branch: main
HEAD: fb75ac9
remote: origin/main (현재 HEAD까지 push됨)
```

승인된 최종 설계의 기준 문서:

```text
docs/adr/0006-noredo-restricted-to-cs-loaddb-with-replay-barrier.md
```

## 2. 승인된 최종 스펙

1. 기능은 CS 모드 `loaddb`에서만 자동 활성화한다. 별도 system parameter나 loaddb 옵션은 만들지 않는다.
2. 허용 client type은 다음 셋이다.
   - `DB_CLIENT_TYPE_LOADDB_UTILITY`
   - `DB_CLIENT_TYPE_ADMIN_LOADDB_COMPAT_UNDER_11_2`
   - `DB_CLIENT_TYPE_ADMIN_LOADDB_COMPAT_UNDER_11_4`
3. UNIQUE와 PK 인덱스도 포함한다.
4. 일반 `csql`/응용 프로그램의 `CREATE INDEX`와 `ALTER`는 기존처럼 per-page redo를 남긴다.
5. SA 모드 loaddb는 no-redo를 사용하지 않는다. 비상 우회 수단이기도 하다.
6. 활성 여부는 서버 `sbtree_load_index`가 client type과 online-build 여부로 판정한다. 클라이언트와 wire protocol은 이 기능을 몰라야 한다.
7. 실제 sort 결과가 병렬일 때만 no-redo를 유지한다. 직렬로 결정되면 일반 logged build로 강등한다.
8. no-redo 빌드 성공 시 서버가 durability barrier 뒤, commit 전에 payload 없는 `RVBT_BULK_BUILD_DURABLE` 로그 레코드를 남긴다.
9. crash restart는 이 레코드를 no-op으로 통과한다.
10. `restoredb`의 media recovery/replay가 이 레코드를 만나면 즉시 영문/한글 안내와 함께 실패해야 한다. 불완전 인덱스를 가진 복원 DB를 성공 상태로 만들어서는 안 된다.
11. 안내 내용은 loaddb 이후 백업을 사용하거나 loaddb 이전 시점까지만 복원하라는 것이다.
12. identity/create-LSA, pending registry, publication 결합, client descriptor, recovery cleanup/repair walk, 2PC guard, HA consumer gate 등 이전의 큰 상태기계는 삭제한다.
13. 최종 durability barrier는 전역 flush로 단순화하되, 아래 커밋 B로 분리한다. 성능 회귀 시 B만 revert할 수 있어야 한다.

## 3. 커밋 분리 원칙

### 커밋 A — loaddb-only pivot 및 대규모 삭제

- 일반 DDL/client/wire 경로를 upstream 상태로 복원한다.
- 서버 client-type 판정만 추가한다.
- payload 없는 replay barrier와 media-recovery 거부만 남긴다.
- identity/pending/publication/cleanup/HA/2PC 기계를 제거한다.
- 이 커밋에서는 기존 scoped durability barrier와 관련 page-buffer 지원 코드를 일단 유지한다.
- 빌드와 기본 동작 검증 후 독립적으로 push한다.

### 커밋 B — scoped barrier 삭제 및 global flush 전환

- `page_buffer.c/.h`의 이번 기능 전용 변경을 upstream 상태로 복원한다.
- `btree_load.c`의 scoped dirty-page/volume 추적을 제거한다.
- no-redo 완료 관문을 global page flush + storage synchronization으로 단순화한다.
- worker unfix 후 flush는 유지한다.
- 빌드·기능·20G 성능 검증 후 push한다.
- 성능 회귀가 확인되면 B만 revert하고 A의 기능 축소는 유지한다.

두 커밋을 squash하지 않는다.

## 4. 현재 작업 트리 상태 — 매우 중요

현재 소스는 **커밋 A를 만드는 중간 상태이며 아직 빌드/테스트되지 않았다.** 완료된 구현으로 간주하면 안 된다.

`git status --short`에는 staged와 unstaged가 섞여 있고 `MM` 파일도 있다. staged diff는 주로 이전의 큰 구현을 merge-base 상태로 되돌리는 대규모 삭제이며, unstaged diff는 loaddb-only 판정과 최소 barrier 구현이다.

현재 staged 통계:

```text
25 files changed, 137 insertions(+), 5026 deletions(-)
```

현재 unstaged 통계:

```text
15 files changed, 95 insertions(+), 53 deletions(-)
```

주요 현재 구현:

- `src/transaction/boot.h`
  - `BOOT_IS_LOADDB_CLIENT_TYPE`가 위 세 client type을 판정한다.
- `src/communication/network_interface_sr.cpp`
  - `sbtree_load_index`가 `logtb_find_client_type(thread_p->tran_index)`와 `index_status`를 근거로 `eligible_no_redo`를 계산한다.
- `src/storage/btree_load.c`
  - `eligible_no_redo`를 내부 인자로 받아 no-redo 후보를 설정한다.
  - 성공 시 durability barrier 뒤 `RVBT_BULK_BUILD_DURABLE` zero-payload redo를 append한다.
  - 아직 scoped durability barrier가 남아 있다. 이것은 커밋 A 의도와 일치한다.
- `src/transaction/recovery.c/.h`
  - `RVBT_BULK_BUILD_DURABLE = 130`과 crash-recovery용 no-op redo가 추가되어 있다.
- `src/transaction/log_recovery.c`
  - media recovery 중 barrier를 만나면 localized message를 설정한 뒤 fatal recovery error로 중단하는 코드가 있다.
- `msg/en_US.utf8/cubrid.msg`, `msg/ko_KR.utf8/cubrid.msg`, `src/base/msgcat_set_log.hpp`
  - replay 차단 안내 메시지 변경이 진행 중이다.

현재 `log_recovery_refuse_bulk_build_replay()`는 `er_set(ER_FATAL_ERROR_SEVERITY, ER_GENERIC_ERROR, ...)` 후 `logpb_fatal_error()`를 호출한다. 이것이 실제 `restoredb`에서 원하는 종료 코드와 사람이 읽을 메시지를 안정적으로 남기는지 아직 검증되지 않았다. crash restart가 이 분기로 절대 들어가지 않는지도 동적 검증해야 한다.

## 5. 절대 훼손하지 말아야 할 작업

다른 세션은 아래를 사용자/외부 작업으로 취급해야 한다.

- `cubrid-cci` submodule이 `ef5470ff...`로 dirty하게 보인다. 이번 변경과 무관하므로 checkout/reset/submodule update 금지.
- `.gjc-install-debug/`는 untracked이며 삭제 금지.
- workspace의 `.agents/AGENTS.md`, `CUBRID_SSOT.md`, `cubrid.conf` 및 여러 untracked log/scratch 파일도 이번 작업과 무관하다.
- `git reset --hard`, `git clean`, 전체 트리 `git checkout -- .`, stash 금지.
- 현재 index에 올라간 5천 줄 규모 삭제는 의도된 커밋 A 재료다. index를 무심코 비우거나 HEAD로 되돌리지 않는다.

수정 전 반드시 다음으로 staged/unstaged 양쪽을 따로 확인한다.

```bash
git status --short
git diff --stat
git diff --cached --stat
git diff -- <file>
git diff --cached -- <file>
```

## 6. 커밋 A에서 최종적으로 0 diff가 되어야 하는 영역

ADR-0006 기준으로 다음 축은 이번 기능의 변경이 없어야 한다. 현재 staged 복원과 unstaged 잔여를 합쳐 merge-base 대비 실제 결과를 다시 확인해야 한다.

- client-side request/response 및 wire negotiation
- connection capability/state
- locator client/server descriptor 전달
- schema-manager provenance/identity
- execute-schema publication deferral
- file-manager create-LSA identity
- vacuum recovery cleanup
- log writer consumer gate
- 2PC compatibility guard
- btree 일반 recovery cleanup/repair machinery

대표 파일:

```text
src/communication/network_cl.c
src/communication/network_interface_cl.c
src/communication/network_interface_cl.h
src/connection/connection_defs.h
src/connection/connection_sr.c
src/object/schema_manager.c
src/query/execute_schema.c
src/query/vacuum.c
src/query/vacuum.h
src/storage/btree.c
src/storage/btree.h
src/storage/file_manager.c
src/storage/file_manager.h
src/transaction/locator*.{c,h}
src/transaction/log_2pc.c
src/transaction/log_writer.c
src/transaction/log_writer.h
```

단, 서버 내부 호출 시그니처를 위해 꼭 필요한 최소 변경은 근거를 남겨야 한다. 클라이언트 wire layout은 develop과 완전히 같아야 한다.

## 7. 유지해야 할 핵심 빌드 경로 수정

대규모 삭제 중 아래 실제 결함 수정과 성능 경로를 함께 날리지 않는다.

- 병렬 leaf construction과 no-redo page update
- sort 결과가 직렬이면 logged build로 강등
- worker가 page를 unfix한 뒤 수행하는 flush
- logged-parallel topop/rmutex deadlock 수정
- 병렬 실패 시 temp file retire 및 누수 방지
- overflow-key pool bootstrap 수정
- 병렬 shard 수가 확정된 뒤 파일을 생성하여 orphan file을 막는 수정

이 항목들은 `src/storage/btree_load.c`, `src/storage/external_sort.c`의 merge-base diff를 줄일 때 특히 주의한다.

## 8. 남은 구현 순서

1. `MM` 파일을 하나씩 검토해 staged 복원과 unstaged 최소 구현을 합친 최종 결과를 확정한다.
2. client/wire가 develop과 동일한 request/reply layout인지 비교한다.
3. 내부 API에서 이전 identity/pending/create-LSA 타입 참조가 모두 제거됐는지 검색한다.
4. 커밋 A 상태를 release/debug로 빌드한다.
5. CS loaddb, compat loaddb, 일반 csql, SA loaddb의 활성/비활성 분기를 동적으로 확인한다.
6. barrier의 crash restart 통과와 restoredb media replay 거부를 실제 백업/복원으로 확인한다.
7. 커밋 A를 commit/push한다.
8. page-buffer/scoped barrier 제거만 수행해 커밋 B를 만든다.
9. 커밋 B를 build/기능 검증하고 20G cold 교대 3-sample을 측정한다.
10. 회귀가 있으면 B만 revert하고 재검증한다. 없으면 B를 push한다.
11. 검증 자료, JIRA 본문/첨부, review-answer 문서를 새 스펙으로 교체한다.

## 9. 필수 검증과 합격 기준

### 기능 표면

- CS `loaddb`: parallel sort일 때 no-redo 사용 및 barrier 1건 발생.
- compat loaddb 11.2/11.4 client type: 같은 정책.
- CS loaddb라도 실제 sort가 직렬: logged build로 강등, barrier 없음.
- 일반 csql/application `CREATE INDEX`/`ALTER ... ADD PRIMARY KEY`: per-page redo, barrier 없음.
- SA-mode loaddb: per-page redo, barrier 없음.
- online index build: no-redo 비활성.

### 복구

- no-redo loaddb가 정상 종료된 뒤 crash restart 성공, checkdb 0.
- barrier를 포함한 archive replay/restoredb는 실패해야 하며 영문/한글 메시지가 명확해야 한다.
- loaddb 이후 취한 full backup으로 restore 성공.
- barrier 이전 point-in-time restore는 성공.
- 실패한/rollback loaddb에서 barrier가 남는 false positive는 승인된 보수적 정책이나, 실제 메시지와 실패 모양은 기록한다.

### 실패 경로

loaddb 경로로 다시 구성해 각각 최소 1회 확인한다.

- 병렬 빌드 중 client kill
- mid-sort failure injection

각각:

- `tranlist` 서버 트랜잭션 잔존 0
- temp file 누수 0
- `checkdb` 0
- 동일 인덱스 재시도 성공

데드락/정지 의심 시 정적 추측보다 먼저 아래를 evidence에 저장한다.

```text
gdb: thread apply all bt
```

### 성능

- 20G 데이터로 cold 교대 3-sample.
- 새 스펙상 csql이 아니라 **CS loaddb 인덱스 생성 단계**를 측정해야 한다.
- 비교 shape는 develop parallel 대비 flat key, overflow key, skewed/중복 OID가 많은 key.
- 커밋 A와 커밋 B를 같은 조건으로 비교한다.
- B에서 의미 있는 회귀가 발생하면 B만 revert한다.
- 과거 csql 기반 20G 수치는 loaddb-only 기능의 최종 성능 증거로 재사용하면 안 된다.

### 전체 게이트

- release build
- debug build
- 관련 unit/SQL/shell tests
- crash/recovery/restore 시나리오
- `checkdb`
- 최종 diff audit

검증하지 않은 상태에서 PASS 또는 완료라고 쓰지 않는다.

## 10. JIRA와 문서 갱신

티켓:

```text
CBRD-27071
http://jira.cubrid.org/browse/CBRD-27071
```

최종 Summary는 사용자 지시대로 다음으로 변경한다.

```text
Support no logging-per-page parallel index build
```

JIRA 본문은 loaddb-only 표면, 일반 DDL 제외, replay barrier 정책, loaddb 후 full backup 운영 계약을 반영해 전면 갱신한다. develop serial 비교는 제거하고 develop parallel 대비 아래 세 shape만 남긴다.

- flat key
- overflow key
- skewed / OID 중복이 많은 key

현재 로컬 JIRA 자료 위치:

```text
.git_ignored_dir/jira/CBRD-27071/
```

주요 파일:

```text
CBRD-27071-analysis.md
CBRD-27071-verification.md
description-updated.txt
```

이 파일들은 이전 일반-DDL/복원-cleanup 설계를 포함할 수 있으므로 그대로 재업로드하지 않는다. 새 구현과 새 검증 결과로 교체하고, 기존 JIRA 분석/검증 첨부도 삭제 후 최신본만 올린다. 영문/한글 operator message를 모두 포함한다.

코드 검토 답변 원본:

```text
docs/review-feedback-answers-bulkidx.md
docs/review-response-bulkidx-decisions.md
```

이들 역시 ADR-0006 이후 결론과 충돌하는 기존 답변은 superseded 표시 또는 최신 결론으로 수정해야 한다.

## 11. 현재 알려진 위험/검토 포인트

1. `logpb_fatal_error()`를 사용한 media-recovery 거부가 restoredb에서 지나치게 강한 종료인지 확인이 필요하다. 요구사항은 복원 실패이지 서버 프로세스의 부적절한 abort나 메시지 유실이 아니다.
2. barrier record가 `LOG_REDO_DATA`로 정상 스캔되며 zero-length payload 처리에 문제가 없는지 확인한다.
3. crash restart와 media recovery를 구분하는 `is_media_crash`가 모든 restoredb 경로에서 기대대로 true인지 실제 실행으로 확인한다.
4. barrier가 commit 전에 flush 관문 뒤에 기록되는 순서와 WAL/fsync 순서를 검증한다.
5. rollback/실패 후 barrier false positive가 실제로 어느 시점부터 archive에 남는지 기록한다. 정책상 수용했지만 메시지는 사용자가 이해할 수 있어야 한다.
6. client/wire를 upstream으로 되돌리는 과정에서 request unpack 순서 또는 reply 크기가 어긋나면 치명적이다. 양쪽 소스 비교와 실동작 검증을 모두 한다.
7. `RVBT_BULK_BUILD_DURABLE = 130`이 현재 develop의 recovery index 배정과 충돌하지 않는지 merge-base 및 최신 develop 기준으로 재확인한다.
8. 커밋 B 전에는 `page_buffer.c/.h`가 HEAD 기준 clean이어도 기존 기능 변경을 포함하고 있다. B에서 반드시 merge-base와 비교해 제거한다.

## 12. 세션/goal 상태 주의

이 인계서 작성 시 `goal({op:"get"})` 결과는 `No active goal`이었다. 또한 다음 canonical 파일은 현재 workspace/worktree에서 발견되지 않았다.

```text
.gjc/ultragoal/goals.json
.gjc/ultragoal/ledger.jsonl
```

따라서 새 세션은 이전 ultragoal이 완료됐다고 추정하지 말고, 런타임 goal/ledger 위치를 먼저 확인해야 한다. 파일이 복구되면 기존 목표와 later accepted/appended story 전체를 현재 ADR-0006 및 사용자 승인사항과 대조하여 completion audit을 다시 수행한다.

## 13. 완료 조건

아래가 모두 직접 증명되어야 완료다.

- 커밋 A와 B가 의도대로 분리되어 있고 둘 다 빌드 가능하다.
- 일반 DDL에는 기능이 없고 CS loaddb 병렬 build에만 기능이 있다.
- crash restart는 성공하고 media replay는 안내와 함께 안전하게 실패한다.
- 실패 주입 두 경로에서 트랜잭션/temp file 누수가 없고 재시도가 성공한다.
- checkdb가 모두 성공한다.
- 20G cold 3-sample 결과가 있고 B 유지/revert 판단이 근거와 함께 기록되어 있다.
- branch가 push되어 있다.
- JIRA Summary/본문/첨부와 문서가 최종 스펙 및 현재 증거로 갱신되어 있다.
- 최종 diff가 ADR-0006의 최소 변경 원칙과 일치한다.
