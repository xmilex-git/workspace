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

**D7 — sql/medium의 DB 디렉터리는 volatile overlay로 둔다 (2026-09-24).**
CTP는 `$CUBRID/databases`(`run.sh`의 `cubrid_root_dir=$CUBRID`) 아래에 `basic`/`mdb`를 만든다.
autocommit 문장마다 로그 fsync를 기다린다. 이 DB는 샤드와 함께 버려진다. 서버가 죽어도
쓴 내용은 page cache에 있어 잃지 않는다. 그래서 fsync가 지키는 것은 호스트 크래시뿐이다.
컨테이너에 `--cap-add SYS_ADMIN`을 주고 `scripts/volatile_entry.sh`가 그 경로에
overlayfs `volatile`(커널 5.10+)을 마운트한다. lower는 원래 경로, upper/work는 샤드의
`volatile/`이다. 마운트 후 `setpriv`로 권한을 버리고 upstream entrypoint를 실행한다.
cubrid-testkit의 `TESTKIT_SLOT_VOLATILE`과 같은 방식이다. rootful podman이나 podman
업그레이드는 필요 없다. 이 호스트 측정에서 autocommit INSERT 5,000건이 9.08초에서
5.73초로, 디바이스 flush가 5,642회에서 59회로 줄었다.
- **대가:** 호스트가 run 중에 죽으면 그 run의 DB는 버려야 한다. 원래 다시 만드는 DB다.
- **범위:** shell/ha_shell은 케이스마다 자기 디렉터리에 DB를 만들어 적용하지 않았다.
  `--overlay`도 제외했다.
- **되돌리기:** `CTP_VOLATILE=0` 또는 `--no-volatile`로 이전의 plain bind로 돌아간다.
  entrypoint 포크는 여전히 HA 보완 두 건만 가진다(D2). 이 기능은 별도 래퍼다.

**D8 — CTP 서버 파라미터는 엔진 기본값으로 고정한다 (2026-09-24).** `just conf`는 캠페인 conf를
모든 설치본에 넣는다. 거기에는 `parallelism=24`(엔진 기본 4) 같은 튜닝값이 있다. CTP conf에는 이
키들이 없어서, 그동안 CTP 서버는 캠페인 값으로 돌았다. 그래서 CTP run은 엔진 기본값을 고정한다.
- **모든 스위트:** `data_buffer_size=512M`, `parallelism=4`, `max_parallel_workers=100`. 모두
  `system_parameter.c`의 기본값이다. `data_buffer_size`는 32768페이지 × 기본 16K 페이지다.
- **sql/medium만:** `max_clients=20`을 더한다. 샤드를 16개 이상 띄우면 호스트의 pids cgroup 하나를
  나눠 쓴다. 이 호스트는 `pids.max`가 8192이고, 16샤드 측정에서 7,637까지 찼다. CQT는 연결을 하나만
  쓰고, sql/medium 케이스 중 `max_clients`를 언급하는 것은 없다. shell/HA는 케이스가 직접 연결을 열고
  124개가 `max_clients`를 다루므로 설치본 값을 둔다.
- **넣는 곳:** sql/medium은 샤드 CTP conf의 `[sql/cubrid.conf]`에 넣는다. CTP는 medium도 이 섹션에서
  읽는다. shell/HA는 설치본 사본 `conf/cubrid.conf`의 `[common]`에 넣는다.
- **`--conf`와의 순서:** 고정값을 먼저 넣고 `--conf`를 적용한다. 명시한 `--conf`가 이긴다. PX 부하
  시험은 `CONF=`로 `parallelism=24`를 준다.
- **계기:** 16샤드 측정에서 parallelism 24로 돈 샤드 하나가 PX 정렬 워커와 리더 사이의 뮤텍스 교착으로
  멈췄다. 엔진 결함으로 별도 이슈에 기록했다.
- **함께 고친 것:** 기존 `--conf` 병합은 medium에서 존재하지 않는 `[medium/cubrid.conf]`에 넣어
  효과가 없었다.
- **정정:** 처음 요청은 `data_buffer_size` 256M이었다. 기본값이 512M인 것을 확인한 뒤 정정했다.
- **되돌리기:** `CTP_PIN_PARAMS=0`이면 설치본 값을 그대로 쓴다.

**D9 — sql은 cases 디렉터리 단위, 16샤드로 나누고, medium을 곁에 띄운다 (2026-09-24).**
카테고리 단위 분할은 가장 무거운 카테고리(`_05_plcsql` 약 323초)가 상한이라 7샤드에서 멈췄다.
디렉터리 단위로는 순서 의존 실패가 없음을 사용자가 확인했다. 그래서 sql의 기본 단위를 cases
디렉터리로 바꾸고 기본 샤드 수를 16으로 올린다.
- **측정:** develop `c63a3b993`, volatile, 16샤드. 케이스 합계는 2,668초였다. 16으로 나누면 샤드당
  약 167초다. 이보다 긴 디렉터리는 `_01_object/_09_partition/_005_reorganization`(203초) 하나뿐이다.
- **`split.tsv`:** 너무 긴 디렉터리를 측정 가중치가 같은 **연속 구간** K개로 자른다. 구간 안에서는 CQT
  순서를 지키고, 각 구간은 샤드 하나에 간다. colocate의 keep-whole과 겹치면 거부한다. 항목은 구간
  단독 실행에서 통과한 뒤에만 올린다.
- **가중치:** `baseline_weights.tsv`를 같은 run의 측정값으로 갱신했다. 측정에 빠진 케이스는 이전
  값으로 채웠다.
- **pid 상한:** 샤드당 약 400으로 잡고 cgroup `pids.max`에 맞춰 샤드 수를 줄인다. RAM 상한과 같은
  방식이다.
- **hang 감시:** sql/medium 샤드가 300초 동안 아무것도 출력하지 않으면, 서버 전체 스택·CQT jstack·
  tranlist·lockdb를 `shard_N/hang/`에 남기고 그 샤드만 멈춘다. CTP sql/medium에는 케이스 타임아웃이
  없어서, hang 하나가 run 전체를 무한정 붙잡았다(35분). 측정된 가장 긴 단일 케이스는 69초였다.
- **medium 동행 (사용자 결정 2026-09-24):** `just ctp sql`로 전체 sql을 돌리면 medium 전체(항상 1샤드)를
  sql 샤드 곁에 함께 띄운다. `just ctp sql+medium`도 같은 동작이다.
  - 측정: medium 151–193초(준비 38–39초, 케이스 102–143초), sql 약 5분. 그래서 둘을 합쳐도 sql 시간으로
    끝난다.
  - `CTP_WITH_MEDIUM=0`이면 sql만 돈다.
  - 부분 실행(DIRS)이나 `EXCLUDE`가 있으면 medium을 붙이지 않는다. 제외 목록의 경로 기준이 스위트마다
    다르기 때문이다.
- **testcase worktree 락:** 저장소 단위 flock으로 순서대로 만든다. 동시에 시작한 medium이 git
  `index.lock` 충돌로 죽었기 때문이다.
- **설치본 복사:** `cp --reflink=auto`로 바꿨다. 16개를 일반 복사하면 37초가 걸렸다.
- **시간 기록:** 모든 run이 `timing.txt`/`timing.tsv`에 호스트 단계와 샤드별 CTP 단계의 시작 시각을
  남긴다. 샤드별 단계는 `podman logs --timestamps`로 읽는다.
- **순서 의존 케이스 (첫 16샤드 run 두 번에서 확인):**
  - **세션 상태:** `_02_function_based_index`의 `last_insert_id()` 케이스는 CQT 연결 하나에 남은 마지막
    AUTO_INCREMENT 값을 읽는다. 그래서 CI 순서의 바로 앞 디렉터리 `_01_filtered_index`와 colocate로
    묶는다. 두 디렉터리는 정렬상 붙어 있어서 한 샤드에 두면 사이에 다른 디렉터리가 끼지 않는다.
  - **ORDER BY 없는 카탈로그 목록:** `_001_db_class/1003.sql`은 CI 순서의 `_01_object` 481초가 앞에
    있어야만 통과한다. 이런 묶음을 두면 run이 7샤드 카테고리 분할보다 느려진다. 그래서
    `dirsplit_exclusions.txt`로 디렉터리 분할 run에서만 뺀다(사용자 결정 2026-09-24).
    `--by-category`와 CI는 그대로 돌리고, upstream에서 ORDER BY를 넣으면 항목을 지운다.
  - **관찰 중:** `alter_03.sql`(인덱스 목록 순서)은 parallelism 24에서 한 번 실패했고 그 뒤 재현되지
    않았다.
  - **배치를 바꿀 때마다 새 순서 의존 케이스가 나온다.** 조정한 16샤드 배치의 첫 run들에서 네 건이 더
    나왔다.
    - `example.sql`: 이름이 겹친 잔존 테이블 `t4`
    - `comment_on_table_index_01.sql`: ORDER BY 없는 인덱스 주석 목록
    - `create_view_data_type.sql`: 정답이 CI 선행 케이스가 남긴 객체의 `-494`를 기대함
    - `cbrd_26104.sql`: 권한 캐시가 차가울 때만 찍히는 내부 쿼리의 Query Plan

    한 배치 안에서는 매 run 같은 식으로 실패하고, CI 순서에서는 통과한다. 모두
    `dirsplit_exclusions.txt`에 넣었다.
  - **케이스 구성이 다르면 배치도 다르다.** dpin 캠페인 세션은 `dpin-tc`로 돌려 다른 배치가 나왔고, 거기서
    같은 유형 두 건이 더 나와 목록에 추가했다(`_01_adhoc_update_stree.sql`, `sleep_001.sql`). PR testcase처럼
    케이스 구성이 바뀌면 이런 케이스가 더 나올 수 있다. 그래서 배치를 고정한다(아래 "배치 고정").
- **배치는 디렉터리 분할 제외 전 케이스 전체로 계산한다.** 제외 목록을 적용하기 전 케이스로 단위와
  가중치를 정하고, 제외 케이스는 배정 뒤에 샤드에서 뺀다. LPT는 민감해서 가중치 4초 차이에도 거의 모든
  디렉터리의 샤드가 바뀌었다. 이렇게 하면 제외 항목을 더해도 검증된 배치의 앞뒤 관계가 그대로라, 수정이
  run 한 번으로 수렴한다. 가중치나 케이스 구성이 바뀔 때 배치를 지키는 일은 아래 "배치 고정"이 맡는다.
- **배치 고정 (`plan_pin.tsv`, 사용자 결정 2026-09-24):** 검증된 run의 배치(cases 디렉터리 → 샤드)를
  파일로 두고, 16샤드 sql 전체 run은 이 배치를 그대로 쓴다.
  - **동작:** pin에 있는 디렉터리는 지금 가중치와 관계없이 pin의 샤드로 먼저 간다. pin에 없는 디렉터리만
    그 부하 위에 LPT로 놓는다. colocate 그룹에 새로 든 디렉터리는 그룹의 pin 샤드로 간다. pin 샤드가
    서로 다른 디렉터리를 새로 묶은 그룹은 한 덩어리로 다시 놓는다.
  - **근거:** 순서 의존 케이스는 각 디렉터리 앞에 어떤 디렉터리가 오느냐로 드러난다. 그런데 LPT는 케이스
    하나, 가중치 몇 초만 바뀌어도 거의 전부를 다시 섞는다. `dpin-tc`(케이스 구성이 develop과 다름)에서는
    LPT가 1,422행 중 621행을 옮겼고, dpin 세션이 본 두 실패가 그 결과다. pin을 쓰면 옮기는 행이 0이고, 새
    디렉터리 2개만 놓인다. `sleep_001.sql`은 통과했던 run #3과 같은 57개 디렉터리 뒤로 돌아간다. 재측정 이전
    가중치를 넣어도 옮기는 행은 0이다(LPT만 쓰면 1,306행).
  - **원본:** run `sql-20260924T044116Z-3751818`(develop `c63a3b993`, testcases `4004f1e13bce`)의 배치다.
    17,462건 통과였고, 같은 배치의 앞 run `sql-20260924T042749Z-3629721`에서 나온 두 실패는 목록에
    들어가 있다. dry-run으로 다시 만든 배치가 두 run과 한 줄도 다르지 않음을 확인했다. pin을 넣은 뒤의 전체
    run `sql-20260924T062044Z-4061888`도 같은 배치로 17,460건 통과했다. medium은 975/975, 샤드별 tc는 177–202초였다.
  - **적용 범위:** 전체 sql run, cases 디렉터리 단위, 16샤드일 때만 쓴다. subset, `--by-category`/
    `--by-case`, `--no-plan-pin`은 LPT만 쓴다. 샤드 수가 다르면(`SHARDS=N`, pid 상한) 경고하고 LPT로 간다.
    샤드 수가 같아야 같은 샤드이기 때문이다. suite나 단위가 다른 pin 파일은 거부한다.
  - **대가:** 가중치가 바뀌어도 균형을 다시 맞추지 않는다. 가장 무거운 샤드가 평균의 110%를 넘으면 경고한다.
  - **다시 고정하기:** 의도해서만 한다. `--no-plan-pin`으로 돌리고, 그 배치를 전체 run 2회로 검증한다. 그런
    다음 그 run의 `<out>/plan_pin.tsv`를 번들 파일 위에 복사한다. 모든 샤드 run이 자기 배치를 이 형식으로
    남긴다.
- **가중치 추출 수정:** `harvest_weights.sh`는 로그의 마지막 케이스를 버렸다. 스위트 끝 근처의
  `_36_guava/cbrd_26707.sql`은 약 74초가 걸리는데 늘 어느 샤드의 마지막이라 0초로 잡혔다. 그 샤드가
  늘 꼴찌였던 이유다. 이제 CQT의 `Elapse Time:`에서 마지막 케이스 시간을 되살린다. `timing.txt`의
  tc도 `Testing End!`까지로 잰다.
- **사본 준비:** 샤드 사본 준비를 병렬로 돌린다. 순서대로 16개를 만들면 reflink로도 26초였다.
- **#350 hang 케이스 제외 (사용자 결정 2026-09-24):** `_06_merge_statement/_20_adhoc_merge_1.sql`은 서버를
  새로 띄운 상태에서 돌면 항상 PX 정렬 교착으로 멈췄다(parallelism 24에서 2/2, 기본 4에서 1/1). 그래서
  #350이 develop에 고쳐질 때까지 `dirsplit_exclusions.txt`에 둔다. hang 감시는 그대로 둔다.
- **pid 여유가 부족할 때 (사용자 결정 2026-09-24):** 샤드 수를 줄이지 않고 최대 900초 기다린다. 부족한 이유는
  대개 다른 세션의 CTP run이기 때문이다. 호스트 `pids.max`는 32,000 이상으로 올린다.
- **유지하는 것:** 샤드 수는 16이다. medium을 함께 띄우므로 더 늘리지 않는다. `ha_mode=yes`와 이번에 잰
  가중치도 그대로 쓴다.
- **예상 균형:** 다른 run의 실측 케이스 시간을 현재 배치에 대입하면 샤드당 171–196초(평균 181초)다. 첫
  샤드와 마지막 샤드가 끝나는 시각은 10–25초쯤 차이 날 것으로 본다.
- **되돌리기:** `CTP_ARGS='--by-category'`와 `SHARDS=7`로 이전 분할이 된다. `--no-split`은 분할을
  끈다. `--no-plan-pin`은 배치 고정을 끈다. `CTP_HANG_SECS=0`은 hang 감시를 끈다.

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
