---
status: accepted
date: 2026-09-04
map: xmilex-git/workspace#157
---

# CTP 러너를 cubridci `test_rl8.10` 이미지 위의 로컬 포크로 재편한다

CTP 실행은 지금까지 스위트마다 다른 경로를 탔다. sql/medium 은 자체 제작 이미지(`ctp-parallel:local`)와
자체 entrypoint 로 podman 안에서, shell 은 호스트에서 직접, HA/shell 은 별도 이미지(`ctp-ha:local`)의
상주 컨테이너 2개로 돌았다. justfile 에는 이를 위한 레시피가 10개 있었고(741줄), 호스트 shell 실행 때문에
"실행 전 다른 세션에 브로드캐스트하고 ack 받기"라는 사람이 지켜야 하는 규칙까지 남아 있었다.

이것을 **하나의 진입점 + 하나의 이미지**로 바꾼다. 이미지는 CI 가 쓰는 `cubridci/cubridci:test_rl8.10`
(Rocky Linux 8.10, digest 고정)을 그대로 쓰고, 그 위에 우리 계층을 얹는다. 러너는 스위트
sql·medium·shell·ha_shell 을 모두 지원하며, 인자 없으면 전체(sql·shell 은 병렬, medium·ha_shell 은 1샤드),
경로를 주면 그 부분집합을 돈다. `just ctp <suite> [DIRS...]` 와 `just ctp-rerun <CI URL>` 두 레시피가
전부다.

## 왜 컨테이너가 선택이 아니라 전제인가

CTP 의 teardown 은 `pkill cub` 과 `ps -u $USER` 기반 `kill -9` 를 쓴다(`sql/bin/run.sh:216`,
`common/script/util_common.sh:30,38-41`, `shell/init_path/init.sh:765,1691,1148-1155`). 이는 포트와
무관하게 **이 사용자의 모든 cub_\* 프로세스**를 죽이므로 포트 레지스트리로 막을 수 없다(2026-08-28 인시던트:
게이트 실행이 다른 세션이 클레임한 서버를 죽였다). 네임스페이스 안에서는 같은 kill 이 그 컨테이너에만
닿는다. 그래서 호스트 CTP 레시피는 이 리포에 없고, 앞으로도 추가하지 않는다.

## 왜 상류에 기여하지 않고 포크하는가

cubridci 의 entrypoint 는 우리에게 필요한 것 중 셋을 제공하지 않는다. (1) sql·medium·isolation·jdbc 에는
시나리오 오버라이드 노브가 아예 없다(README: "There is no entry point for a case list yet"), (2) 모든
카테고리에 대한 제외 목록 오버라이드가 없다, (3) `test` 가 마운트된 CTP·테스트케이스를 fetch+reset 없이
쓰는 모드가 없다. 상류 PR 을 기다리는 동안 우리 작업이 멈추고, 반영 시점도 우리가 통제할 수 없다.
그래서 entrypoint 를 포크해 `/entrypoint.sh` 위에 bind-mount 한다 — **이미지는 우리가 빌드하지 않으므로**
상류의 런타임 패키지 관리(로케일, JDK, perl DBD::cubrid, valgrind, lcov, sshd)는 계속 공짜로 받는다.
비용은 상류 entrypoint 변경을 우리가 따라가야 한다는 것이며, 그래서 이미지를 digest 로 고정하고 갱신을
명시적 편집으로 만든다.

포크가 얹는 것은 네 가지다. 시나리오·제외 목록 오버라이드를 **전 카테고리**에 적용, `testcase_update_yn=false`
강제, 출처 1행 출력, `test` 의 checkout 요구 제거. 두 번째가 특히 중요하다: 상류는 shell 계열 conf 를
`shell_ci.conf` 에서 파생하고 그 파일은 `testcase_update_yn=true` 를 싣고 있어, CTP 가 컨테이너 안에서
테스트케이스를 git-pull 해 **샤드에 물질화한 부분집합을 파괴하고 조용히 develop 으로 바꿔버린다**.

## 왜 빌드는 컨테이너 안에서 하지 않는가

이 이미지는 툴체인이 없는 런타임 전용이고(공식 문서: "CUBRID must be injected from outside"),
Rocky 8.10 / glibc 2.28 로 이 호스트와 같다. 그래서 호스트에서 `just build` 한 설치본을 마운트하면
그대로 돈다. 컨테이너 안 빌드는 CI 와 동일한 바이너리를 주지만 실행마다 수십 분과 `~/CUBRID` 체계와의
이원화를 낳는다.

## 왜 medium 과 ha_shell 은 절대 병렬이 아닌가

medium 은 단일 `data_file` tarball 에서 mdb 하나를 적재하고 케이스들이 그것을 제자리에서 변형한다.
샤드 둘이면 한 데이터셋을 두고 경쟁한다. ha_shell 의 샤드는 컨테이너 **한 쌍**(master+slave)이고, 이
스위트는 원래 버킷 하나씩만 돌린다. 그래서 `--shards N>1` 은 이유와 함께 거부한다.

부분집합은 스위트와 무관하게 기본 1샤드다. 샤드마다 설치본 전체 사본과 컨테이너가 붙으므로 17,000
케이스에는 값을 하지만 디렉토리 몇 개에는 낭비다. 큰 부분집합은 `SHARDS=N` 으로 쪼갠다.

ha_shell 샤드의 두 컨테이너는 CTP·테스트케이스는 공유하되 **설치본과 `CUBRID_DATABASES` 는 각자
사본**을 쓴다. 두 노드가 각각 서버를 띄우고 자기 conf 를 다시 쓰기 때문에 공유하면 서로를 덮어쓴다
(구 provision 스크립트가 노드별 install 사본을 만든 이유와 같다).

## 왜 테스트케이스 ref 를 명시하지 않으면 실행을 거부하는가

로컬 실행이 PR 브랜치가 아니라 develop 테스트케이스로 도는 일이 반복됐다. 기본값이 "호스트 체크아웃의
현재 HEAD"이면 (a) PR 검증이 조용히 무의미해지고 (b) 다른 세션의 `git checkout` 이 실행 중인 검증의 대상을
바꾼다. 그래서 `--tc-ref`, `--pr`, `--workspace`(브랜치에서 PR 추론) 중 하나가 없으면 거부한다. CI 규약을
그대로 따라 `cubrid-testcases` 와 `cubrid-testcases-private-ex` 는 `tc/pr-<N>` 을 쓰고 없으면 develop 으로
떨어지되 출처에 기록한다. `cubrid-testcases-private` 는 `tc/pr-<N>` 규약이 없으므로 항상 develop 이다.
ref 는 git worktree 로 물질화하므로 호스트 체크아웃의 브랜치와 커밋 안 된 수정은 건드리지 않는다.

## 결과

- justfile 741줄 → 349줄, CTP 레시피 10개 → 2개. `shell-debug*` 4종, `sql-debug*` 거부 스텁,
  `ctp-sql-isolated`, `ctp-medium-isolated`, `ha-provision`, `ha-shell`, `_ensure-conf-full` 삭제.
- 호스트 shell 실행이 사라져 "shell 실행 전 브로드캐스트+ack" 규칙과 `shell-debug-optdebug` 의
  HOME 스왑 hack 이 필요 없어졌다.
- 자체 이미지 `ctp-parallel:local`·`ctp-ha:local` 과 옛 `cubridci:develop`(CentOS 6) 은 폐기한다.
- 모든 실행이 `provenance.txt`/`.tsv` 에 설치본·이미지 digest·CTP 리비전·테스트케이스 ref+SHA 를 남긴다.

## 되돌리는 방법

이미지와 entrypoint 는 값이므로 `DEFAULT_IMAGE`/`DEFAULT_IMAGE_DIGEST` 한 줄과 포크 파일을 되돌리면
이전 이미지로 복귀한다. 삭제한 레시피는 git 이력에 있지만, 호스트 CTP 를 되살리는 것은
`pkill cub` 인시던트의 재발이므로 하지 않는다.
