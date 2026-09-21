# 도메인·collation 사전 확정 캠페인(dpin) — 작업 트리·기준선 설정

지도: xmilex-git/workspace#312 · 준비 티켓: #316 · 작성 2026-09-22

## 작업 트리 (세 저장소, develop 최신, 포크에만 푸시)

| 저장소 | 워크트리 | 브랜치 | 시작 해시 | 푸시 리모트 |
|---|---|---|---|---|
| CUBRID/cubrid | `~/dev/cubrid-worktree/dpin` | `dpin` | `cad27172b` (2026-09-21) | `fork` → xmilex-git/cubrid |
| CUBRID/cubrid-testcases | `~/dev/cubrid-tc-worktree/dpin` | `dpin-tc` | `4a7a4aed9` (2026-09-21) | `fork` → xmilex-git/cubrid-testcases |
| CUBRID/cubrid-testcases-private-ex | `~/dev/cubrid-tc-ex-worktree/dpin` | `dpin-tc-ex` | `dfb7da195` (2026-09-21) | `fork` → xmilex-git/cubrid-testcases-private-ex |

규칙: CUBRID 조직 저장소(`origin`)에는 절대 푸시하지 않는다. CTP 는 `just ctp <suite> [DIRS...]` 에 `TC_REF=dpin-tc` 를 명시한다.
이전 캠페인 브랜치(`wf268*`)는 읽기 전용 참고이며 체리픽하지 않는다.

## 기준선 증거 = GitHub nightly (로컬 전수 재측정 없음, 사용자 결정 2026-09-22)

- `gha-ci` 워크플로의 cron(`20 15 * * *` UTC)이 48시간 창의 develop 머지 커밋마다 `dispatch all <sha>` 를 띄우고, 커밋 상태 `gha-ci: test_sql` / `test_medium` / `test_shell` 을 남긴다.
- 확인 명령: `gh api repos/CUBRID/cubrid/commits/cad27172b/status --jq '.state, (.statuses[] | "\(.context) \(.state) \(.target_url)")'`
- 2026-09-22 현재: `cad27172b` 는 CircleCI build/build_debug success 만 있고 gha-ci 세 상태는 아직 없다(2026-09-20 nightly run 35519534097 은 `5d8fc7bd5` 까지 커버). 직전 develop `5d8fc7bd5` 는 세 suite success — <https://github.com/CUBRID/cubrid/actions/runs/35423041306>.
- **TODO(다음 세션)**: 2026-09-22 15:20 UTC nightly 뒤 위 명령으로 `cad27172b` 의 세 상태와 run URL 을 여기 기록한다.

## 빌드 설치본 (잔여)

- optdebug/release: 툴링 리포 `.git_ignored_dir/scratch/dpin/install-{optdebug,release}` (`just build` 에 `INSTALL_PREFIX` 명시, `~/CUBRID` 는 덮어쓰지 않음). — 미착수.

## 마이크로벤치 계측 설계 (잔여)

- 미착수. 준비 티켓 4번 항목.
