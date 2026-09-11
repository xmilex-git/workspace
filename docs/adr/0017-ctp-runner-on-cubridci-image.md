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

## 상류 반영 후 남기는 로컬 변경 (2026-09-11)

**D1 — 공통 기능은 상류 구현을 사용한다.** 초기 포크의 시나리오·제외 목록, shell 테스트케이스
자동 갱신 방지, DB 경로 권한 처리는 [#123](https://github.com/CUBRID/cubridci/pull/123),
[#121](https://github.com/CUBRID/cubridci/pull/121), [#120](https://github.com/CUBRID/cubridci/pull/120)에
반영됐다. 상류 `452b7be0cee601b9efd59a1d9c9faf89886d255f`의 entrypoint로 갱신하고,
`apply_ctprun_overrides`와 자체 출처 출력은 제거한다. 호스트의 `provenance.tsv`는 계속 남긴다.
이미지의 출처 출력은 `.git`을 복사하지 않는 샤드에서는 unknown일 수 있다.

**D2 — HA 보완 두 건만 포크에 남긴다.** thin-csql broker 포트의 SSH 환경 전달과
`make_ha_upper.sh` 사본의 slave broker 시작 패치는 아직 엔진 develop에 없는 기능에 의존한다.
해당 엔진 기능과 CTP 지원이 상류에 들어가면 이 두 차이도 제거한다. 그때까지 entrypoint를
`/entrypoint.sh`에 bind-mount하며 이미지는 빌드하지 않는다.

**D3 — 제외 목록은 계획과 실행에 같은 값을 쓴다.** `--only`/just의 디렉터리 인자로 부분 트리를
만들고 이미지의 `TEST_SCENARIO`에 그 루트를 전달한다. `--exclude`/`EXCLUDE`는 호스트 파일을
받아 샤드 계획 전에 적용하고 같은 사본을 `TEST_EXCLUDE`로 전달한다. 빈 값은 제외 해제,
미설정은 기존 기본 목록이다. 이미지 환경변수만 덮으면 계획과 실행 개수가 달라지므로
`--env`를 통한 scope 변경은 거부한다. 옛 `CTP_*` scope 이름도 조용히 무시하지 않는다.
상류가 stock conf에서 실행 conf를 매번 생성하므로 이전 실행의 scope가 다음 실행에 남지 않는다.

**D4 — 기본 실행은 전체 digest에 고정한다.** 이번 이미지 digest는
`sha256:79a344fc7664af48cd13b4b01bc54c059dd92ac2be812f2e4d9802234e06fb7e`이다.
단순 태그를 실행하고 digest 불일치를 경고만 하던 방식 대신 pull/run에 digest 참조를 사용한다.
다른 이미지는 명시적 `--image`로 선택한다.

**D5 — shell/HA 사본의 상속된 전체-locale 설정만 초기화한다.** 이번 이미지 검증에서 SQL은
통과했지만 shell/HA가 locale 초기화에 실패했다. 동일 바이너리로 확인한 원인은 CTP가 매
케이스 전에 생성된 locale 라이브러리를 삭제하는 동작과, SQL 실행용 전체-locale 설정을
가진 설치본의 조합이다. `cubrid_locales.txt`가 `cubrid_locales.all.txt`와 정확히 같을 때만
shell/HA의 설치 사본에서 활성 항목을 비운다. 원본 설치본, SQL/medium, 별도 사용자 설정은
변경하지 않는다. 이 초기화가 필요한 설치본의 `--overlay`는 사본 모드를 사용하도록 거부한다.
CTP 코드와 entrypoint에 추가 패치를 넣지 않으며, locale 테스트의 명시적 생성 경로도 유지한다.

초기 기록 정정: 상류 `test`는 원래도 checkout을 자동 호출하지 않았다. 포크의 해당 차이는
누락 디렉터리 안내 문구였으므로 별도 skip-checkout 기능은 필요하지 않다. 또한 당시 기록의
“실행 중 develop으로 바뀌었다”는 서술은 실행 전후 SHA로 입증한 관측이 아니라 설정과 CTP
갱신 경로에 근거한 위험 설명이다. 새 상류 구현은 shell/rqg 실행 설정에서 갱신을 명시적으로 끈다.

## 왜 빌드는 컨테이너 안에서 하지 않는가

이 이미지는 CTP 실행용으로 엔진 설치본을 외부에서 받는다(공식 문서: "CUBRID must be injected from outside").
locale·테스트 보조 프로그램을 컴파일하는 gcc는 포함하지만, 엔진 빌드는 호스트의 기존 워크플로를 쓴다.
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
HA의 컨테이너 내부 DB 경로는 `$CUBRID/databases`로 유지하고 그 위에 노드별 호스트 디렉터리를
마운트한다. CTP HA 스크립트와 케이스가 이 경로를 직접 참조하므로 외부 경로로 옮기는 문제는
소유권 변경만으로 해결되지 않는다.

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

이전 이미지로 복귀할 때는 digest, entrypoint, 러너의 옵션 이름을 함께 되돌린다.
이미지만 이전 digest로 바꾸면 새 옵션 계약과 어긋난다. 이전 이미지 레이어는 제거하지 않는다.
삭제한 레시피는 git 이력에 있지만, 호스트 CTP 를 되살리는 것은
`pkill cub` 인시던트의 재발이므로 하지 않는다.
