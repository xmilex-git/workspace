# 절대 성능과 VTune을 양쪽 모두 release 단일 빌드 하나로 측정한다

프로파일링용 빌드를 따로 두면 "프로파일에서 본 병목이 성능 수치를 낸 그 바이너리의 병목인가"를
매번 증명해야 한다. 대신 **디버그 심볼을 포함한 최적화 빌드 하나**로 두 측정을 모두 수행한다.
CUBRID는 `release` preset이 이미 `RelWithDebInfo`(`-O2 -g -DNDEBUG`)라 그대로 쓰면 되고,
PostgreSQL은 `--enable-debug`가 최적화나 assertion을 건드리지 않고 **`-g`만 추가한다**는 것을
소스와 실측으로 확인했으므로 같은 성질의 단일 빌드를 만들 수 있다.

## 실측 근거 (PostgreSQL, `~/dev/postgres` @ `5713b437a`)

동일 소스에서 out-of-tree로 `base`(옵션 없음)와 `dbg`(`--enable-debug`)를 configure한 뒤 비교:

- `src/Makefile.global` 전체 diff = **3줄**: `enable_debug`, `CFLAGS`, `CXXFLAGS`.
  `CPPFLAGS`(` -D_GNU_SOURCE`)·`LDFLAGS`·`LIBS`는 동일.
- `CFLAGS` 차이는 **`-g` 하나**: base `… -O2`, dbg `… -g -O2`.
- optimizer 불변 — `configure.ac:473-474`가 GCC일 때 `enable_debug`와 무관하게 `CFLAGS="-O2"`를 준다.
- assertions 불변 — `configure.ac:830` `PGAC_ARG_BOOL(enable, cassert, no, …)`. 두 빌드 모두
  `pg_config.h`가 `/* #undef USE_ASSERT_CHECKING */`이고, `c.h:1000`에서 `Assert()`는 `((void)true)`로 소거된다.
- stripping 불변 — `Makefile.global.in:875-882`의 `INSTALL_STRIP_FLAG=-s`는 `install-strip` 타깃 전용이라
  일반 `make install`은 심볼을 남긴다.
- CUBRID의 `-DNDEBUG`에 대응하는 것은 `-DNDEBUG`가 아니라 **cassert off**다. PG는 자체 `Assert`를
  `USE_ASSERT_CHECKING`으로 제어하므로 `-DNDEBUG`를 더할 이유가 없다.

## `.text` 검증 결과 (최초 1회, 2026-07-28)

`-g` 유무만 다른 두 빌드(`--enable-debug` 有/無, 그 외 옵션·prefix 동일)의 `src/backend/postgres` 비교:

| 검사 | 결과 |
|---|---|
| `.text` 섹션 크기 | 양쪽 `0x587eb2` = 5,799,602 B **동일** |
| `.rodata` 섹션 크기 | 양쪽 `0x26da3f` **동일** |
| text 심볼(name+size) 해시 | 양쪽 `81df3889…` **동일** (19,464개) |
| 주소·즉시값 정규화 disassembly 해시 | 양쪽 `e2d68bae…` **동일** |
| `.text` raw SHA-256 | `bd6ddd91…`(-g) vs `f1a0008a…`(no -g) — **불일치** |
| raw 바이트 차이 | **23바이트**, 전부 `get_configdata` / `get_controlfile_by_exact_path(.cold)` 내부 |

raw 해시 불일치의 원인은 코드 생성이 아니라 `CONFIGURE_ARGS` 문자열에 `'--enable-debug'`가 더 들어가
`.rodata` 배치가 밀리고, non-PIE 실행파일이라 그 주소를 참조하는 명령의 변위 바이트가 바뀐 것이다.
차이가 설정 문자열을 반환하는 두 함수에만 갇혀 있고 쿼리 실행 경로에는 없다.
**결론: `-g`는 코드 생성에 0바이트 영향.**

(주: `make CFLAGS=…`로 `-g`만 뺀 대조군도 시도했으나, 명령행 변수 대입이 makefile 내부의
`CFLAGS +=`(예: `src/common/Makefile:212`)를 전부 무시해 다른 코드가 나온다. 유효한 대조군은
configure 단계에서 `--enable-debug`를 뺀 빌드뿐이다.)

## Decision

- CUBRID: `release` preset(`RelWithDebInfo`, `-O2 -g -DNDEBUG`, `/usr/lib64/ccache/cc` = GCC 8.5.0).
- PostgreSQL: `--enable-debug --without-icu --without-readline --with-zlib --with-zstd
  --without-llvm --without-lz4 --without-libxml` → `-g -O2`, cassert off, strip 없음.
- **JIT은 off** — `with_llvm = no`. CUBRID에 대응 기능이 없어 normalized baseline을 깨뜨린다.
- frame pointer는 지금 넣지 않는다.

## Consequences

- 절대 성능 수치와 VTune 프로파일은 **같은 바이너리**에서 나온다. 프로파일 대상이 측정 대상과
  다르다는 반론이 원천적으로 성립하지 않는다.
- VTune 스택이 부실해 `-fno-omit-frame-pointer`가 필요해지면 **별도 빌드로 파생**하고, 그 빌드의
  수치는 baseline 표에 섞지 않는다(코드 생성이 실제로 바뀌므로).
- `make install-strip`은 쓰지 않는다. 심볼이 사라지면 두 측정을 한 빌드로 묶은 이유가 없어진다.
- `-g` 무해성은 이 SHA 쌍에서 검증한 것이다. 컴파일러나 pin SHA를 바꾸면 `.text` 검증을 다시 한다.
