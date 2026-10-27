# PR 8196 리뷰 분배 브리프 (5번 세션 작성, 2026-10-21)

## 사용자 원문 요청 (5번 세션에 입력됨)

> /cubrid-pr-review https://github.com/CUBRID/cubrid/pull/8196 이거 리뷰해줘. 1. 원래 cubrid-pr-review 스킬에 나와있는 flow 대로 리뷰. 2. heap scan 시 내가 알기로 지금 페이지 fix 를 놓고 있다가 작업 끝나고 다음 page fix 를 잡으면 그 page가 dealloc 되어있을수도있어서 간간히 오류가 나거든? vacuum이랑 엮여서? 그쪽 측면으로 리뷰. 3. /cpp-perf-rules 기반리뷰 4. char 가 지금 고정 길이가 아니어서 char  가 최적화 대상에 들지 못했는데, 그것에 대한 리뷰. 5. like 관련해서는 특정 codeset,collation 일때 byte로 움직이는 최적화가 들어가있는데, 왜 여기선 그걸 사용하지 않았는지 리뷰. 6. 또 더 생각해볼점, postgres (~/dev/postgres) 의 (volcano?) 그거랑 차이점과 한계 등 리뷰. 이거 각 항목을 이 호스트에 다른 claude 세션에 분배해서 리뷰 진행해줘. 각각 서버 실행 따로 해봐도 되고, 완전히 자율적이고 독립적이게 리뷰 돌아가게 해. 각각 세션에 내가 직접 접근해서 답변할테니, 넌 리뷰 뿌리고 1~6번 항목중 하나 너가 직접 잡아서 수행해.

## 항목 배정

| 항목 | 세션 | 산출물 |
|---|---|---|
| 1. cubrid-pr-review 스킬 flow 그대로 (JIRA, TC PR, CI, 보고서, grill, comments) | 5번 세션 | `PR-8196-report.md`, `PR-8196-comments.md` |
| 2. heap scan 페이지 fix 해제 후 다음 페이지 fix 시 dealloc/vacuum 측면 | 1번세션 | `item2-heap-page-vacuum.md` |
| 3. `cpp-perf-rules` 스킬 기반 성능 리뷰 | 2번세션 | `item3-cpp-perf-rules.md` |
| 4. CHAR 가 고정 길이가 아니어서 최적화 대상에서 빠진 점 | 3번 세션 | `item4-char-fixed-length.md` |
| 5. LIKE: 특정 codeset/collation 의 바이트 단위 최적화를 왜 안 썼는지 | 4번 세션 | `item5-like-byte-path.md` |
| 6. PostgreSQL(`~/dev/postgres`) 실행기(Volcano 등)와의 차이·한계 | 6번 세션 | `item6-postgres-compare.md` |

산출물 경로는 모두 `/home/cubrid/dev/workspace/.claude/review/PR-8196/` 아래. 다른 항목 파일은 읽기만 한다.

## 공통 사실 (5번 세션이 확인함)

- PR: https://github.com/CUBRID/cubrid/pull/8196 , 작성자 soheejung-cs, JIRA CBRD-27361
- 제목: `[CBRD-27361] Page batch execution: heap scans in chunks, vector filters, hash GROUP BY merge and hash join runtime filter`
- head `908bdc5af67a752fd168b71cdf2c6f140520861d` (develop 머지 커밋), develop merge-base `c966fabc6b4c8ac86aa4b5abb0a4cbefae01bf5b`
- 규모: 36파일 +14669/-3590. 핵심 파일: `src/query/expr_batch.c`(신규 4359줄), `expr_compile.c`, `scan_manager.c`, `query_executor.c`, `query_aggregate.cpp`, `query_hash_join.c`, `px_scan/*`, `src/storage/heap_file.c`(`heap_page_collect_visible()` 등)
- PR 본문 전문: `gh pr view 8196 -R CUBRID/cubrid --json body`
- 공유 엔진 worktree (head, detached): `~/dev/cubrid-worktree/pr8196-review` — **읽기 전용**. 이 안에서 checkout/stash/reset/build 금지. merge-base 코드는 `git -C ~/dev/cubrid-worktree/pr8196-review show c966fabc6:<path>` 로 읽거나, 필요하면 자기 이름의 worktree 를 따로 만든다 (`git -C ~/dev/cubrid-worktree/develop worktree add --detach ~/dev/cubrid-worktree/pr8196-item<N> <sha>`).
- code-index 는 이미 인덱싱됨(동시 실행은 flock 으로 직렬화): `tools/code-index/code-index ~/dev/cubrid-worktree/pr8196-review <definition|body|callers|references|outline> <name>`
- CI 빌드 tarball (모두 200 확인, "debug" 슬롯은 optdebug):
  - head: `http://192.168.1.48:30080/builds/pr/908bdc5af67a752fd168b71cdf2c6f140520861d/{debug,release}/CUBRID.tar.gz`
  - merge-base: `http://192.168.1.48:30080/builds/develop/c966fabc6b4c8ac86aa4b5abb0a4cbefae01bf5b/{debug,release}/CUBRID.tar.gz`
  - `curl --noproxy '*'`. 자기 scratch 에 자기 사본으로 풀어 쓴다(설치 공유 금지: conf·포트가 섞임). 서버는 `just port-claim` 으로 자기 포트를 잡고 `cubrid-server-control` 로 기동, 끝나면 정지·`just port-release`. `CUBRID_TMP` 경로는 짧게(소켓 경로 107바이트 제한). `data_buffer_size=512M`.
- CI: run 39374265629 (head 908bdc5af) build/sql/medium/shell 통과(PR 본문 주장). 결과는 `http://192.168.1.48:30080/runs/<run id>/`.
- TPC-H SF10 측정 자산: `~/databases/tpch` (GLOSSARY.md 참조).

## 공통 규칙

- 각 세션은 독립적으로 끝까지 진행한다. 결정이 필요한 질문은 그 세션에서 사용자에게 직접 한국어로 묻는다(사용자가 각 세션에 직접 들어가 답함). 5번 세션을 거치지 않는다.
- 자기 scratch: `/home/cubrid/dev/workspace/.git_ignored_dir/scratch/pr8196-item<N>/` (다른 항목 디렉터리에 쓰지 않음). `/tmp` 금지.
- 빌드·CTP·벤치(A/B)·대용량 적재·10분 넘는 단계는 이 저장소 CLAUDE.md 의 분업대로 Sonnet Workflow 워커에 위임하고 위임 실행 계약·CTP 규칙을 원문 그대로 넣는다. smoke(서버 기동, 작은 csql 질의, gdb)는 세션이 직접. 이 호스트에서 6개 세션이 동시에 돌고 있으므로 시간 측정은 잡음이 크다 — 벤치는 `perf stat instructions:u` 같은 경합에 둔감한 지표를 우선하거나 잡음을 보고서에 명시.
- 발견 사항은 PR 이 새로 들인 것만, `파일:라인` 과 코드/실행 근거를 붙여서. 추측성 지적 금지.
- GitHub/JIRA 게시·커밋·푸시는 그 세션에서 사용자가 명시적으로 승인할 때만. `GLOSSARY.md` 는 다른 세션도 편집할 수 있으니 Edit 로 작은 추가만 한다.
- 산출물 형식: 한국어 본문, 이모지·비BMP 문자 없음, 맨 위에 `TL;DR` 1-3문장, 그다음 근거 있는 발견 사항(Blocking / Non-blocking / Questions), 실행한 검증(빌드 sha·종류·명령·결과), 확인하지 못한 것.
