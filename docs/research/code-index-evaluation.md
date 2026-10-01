# 엔진 코드 탐색 도구 평가 (code-index)

기준: develop `2f1a1d5c5`, 2026-10-01~02 그릴링. 결정 D1~D16은 그릴링에서 사용자가 정했고, 사용법은 루트 `AGENTS.md`의 "Code lookup in an engine worktree", 구현은 `tools/code-index/`에 있다.

## 1. 왜 도입했나

이 호스트의 Claude Code 세션 기록 790개(도구 결과 약 1억 6백만 자)를 집계하면 엔진 소스 탐색이 도구 결과의 가장 큰 몫이다.

| 종류 | 호출 수 | 결과 글자 수 |
|---|---|---|
| 엔진 소스 grep/rg | 7,533 | 1,340만 |
| `sed -n` 범위 읽기 | 3,552 (요청 범위 중앙값 51줄) | 1,280만 |
| 그중 `'^이름'` 정의 찾기 grep | 1,859 | 384만 |

호출자를 찾을 때는 grep으로 호출 지점을 얻은 뒤, 지점마다 앞뒤를 다시 읽어 감싼 함수를 확인한다. 이 반복이 범위 읽기의 상당 부분이다. 이 수치는 도구 결과 글자 수만 센 것이고, 왕복 횟수와 추론 토큰은 포함하지 않는다.

조건은 세 가지였다. 컴파일이나 빌드 없이 찾을 것, 가벼울 것, MCP 같은 서버 형태가 아닐 것.

## 2. 후보

| 도구 | 판단 |
|---|---|
| Universal Ctags 6.2.1 | 채택. 정의, 함수 끝 줄, C++ 범위, 구조체 멤버, Java. 참조는 없다 |
| GNU Global 6.6.14 (nix) / 6.7 (측정) | 채택. 참조와 파일 단위 갱신. CUBRID 문법 파일에서는 규칙을 뽑지 못해 별도 검사로 보완한다(6절) |
| cscope 15.9 | 제외. 감싼 함수 이름은 주지만 C++ 클래스 한정 정의를 못 찾고 템플릿 안의 호출자를 놓친다. 이 호스트에서는 `~/.local/bin/env`가 `/usr/bin/env`를 가려 `-q` 색인이 조용히 만들어지지 않는다 |
| clangd·LSP·scip-clang | 제외. 컴파일 DB가 필요하고, 빌드 설정 하나만 본다 |
| codanna | 제외. MCP 중심이고 임베딩 모델이 150 MB이며 색인을 트리 안 `.codanna/`에 둔다 |
| cona | 제외. 512 KB를 넘는 파일을 건너뛰어 `btree.c`(1.3 MB)가 빠진다 |
| probe | 제외. 1.0 이전 RC 단계 |
| Serena·codebase-memory·mcp-gtags-server, Zoekt·OpenGrok | 제외. MCP 또는 서버 형태 |

## 3. 측정 (1차 벤치, develop 사본)

엔진 작업 범위만 색인했다(`src/`에서 `src/win_tools/` 제외, `pl_engine/`; 1,392개 파일, 146만 줄). 추적 소스 전부를 색인하면 태그의 21%가 엔진 바깥 것이다(`win/3rdparty` 13,868개, `src/win_tools` 1,880개, `contrib` 1,855개).

| 도구 | 처음 색인 | 크기 | 파일 1개 갱신 | 182개 갱신 |
|---|---|---|---|---|
| Universal Ctags | 10.3 s, YACC 파서를 빼면 2.8 s | 12 MiB | 0.21 s | 0.65 s |
| GNU Global | 1.0 s | 22 MiB | 0.08 s (`--single-update`) | 0.28 s (`gtags -i -f`) |
| cscope | 1.6 s | 72 MiB, 메모리 257 MB | 0.83 s | 0.95 s |

Universal Ctags의 10.3 s 중 7.6 s가 `csql_grammar.y` 하나였다. 다른 워크트리의 색인을 복사해 오는 방법은 이득이 없었다. 새 체크아웃은 모든 파일의 mtime이 새로워서 Global과 cscope가 전부 다시 읽는다.

| 조회 | Universal Ctags | GNU Global | rg |
|---|---|---|---|
| 정의 `btree_insert` | 231자, 끝 줄 포함 | 150자, 시작 줄만 | `-w` 1,367자 |
| 매크로 `ASSERT_ERROR` | 56자 | 72자 | 73,297자 |
| 타입 `DB_VALUE` | 111자 (정의 2곳) | 179자 | 638,023자 |
| 구조체 멤버 `spec_list` | 5곳 모두, 소속 구조체 포함 | 찾지 못함 | 47,182자 |
| 호출자 `qexec_clear_xasl` (21곳) | 참조 없음 | 21곳 모두, 오탐은 프로토타입 1개 | 39줄 중 오탐 18줄 |
| `btree.c` 개요 | 415개 모두, 끝 줄 포함, 98 ms | 600줄에 매크로가 섞이고 끝 줄 없음 | 398/415개 |

## 4. 빌드 모드와 NDEBUG

세 도구 모두 매크로를 해석하지 않으므로 SERVER/SA/CS 모드와 NDEBUG의 어느 분기에 있는 코드든 색인한다(`#if 0`만 제외). 컴파일 DB 기반 도구는 빌드 설정 하나만 보므로, 이 점은 CUBRID에서 오히려 장점이다. develop 사본에서 확인한 수치는 다음과 같다.

- GNU 스타일 함수 정의 18,124개 중 986개가 SERVER/SA/CS/NDEBUG `#if` 안에 있다.
- Universal Ctags의 함수 범위 17,923개를 검사했고, 끝 줄이 다음 함수로 넘어간 경우는 0건이다. 틀린 3건은 `REGISTER_WORKERPOOL` 매크로 안의 람다다.
- 그 조건문들의 `#else`/`#elif` 쪽에 있는 실제 호출 1,258곳 중 GNU Global `-r`가 1,228곳을 찾았다. 나머지 30곳은 Global이 정의를 기록하지 못한 함수라서 `-s` 목록에 있다(표본 3곳 확인). 27곳은 `.i` 파일에 정의된 `db_get_object`·`db_get_oid`이고, 3곳은 `db_is_utility_thread`다.

빈틈은 함수 머리만 `#if !defined(NDEBUG) … #else … #endif`로 나누고 본문을 같이 쓰는 정의다. 두 도구 모두 첫 분기만 색인한다.

- `pgbuf_fix_debug`는 찾지만, release 빌드의 실제 함수인 `pgbuf_fix_release`(page_buffer.c:2166)는 찾지 못한다.
- `db_private_alloc_release`를 물으면 진짜 정의(memory_alloc.c:438) 대신 Windows용 빈 함수(420)를 답한다.
- 이런 정의가 41개이고, 그중 21개가 모드·NDEBUG 조건 아래 있다.
- Universal Ctags는 `csql_grammar.y`·`csql_lexer.l` 안의 C 함수 101개도 놓친다. Global은 문법 파일의 C 함수를 찾는다.

code-index는 행 첫 열의 `이름 (` 뒤에 `{`가 오는 줄을 따로 검사해 이 빈틈을 메운다. 또 결과마다 파일이 들어가는 라이브러리 `{server,sa,cs}`와 그 줄의 `#if` 조건을 붙인다.

## 5. 결정

| # | 결정 |
|---|---|
| D1 | 조회 범위는 정의, 함수 본문 범위, 파일 개요, 호출자·참조. Java는 정의까지 |
| D2 | 래퍼 `tools/code-index/code-index <WORKSPACE> definition\|body\|outline\|callers\|references` |
| D3 | 색인은 작업 워크트리의 `.cache/code-index/`. 무시되지 않는 워크트리는 공통 `info/exclude`에 한 줄 추가 |
| D4 | 조회마다 바뀐 파일만 다시 색인하고 `flock`으로 직렬화 |
| D5 | `just code-index-install`로 설치하고 `cubrid-deps-check`가 없으면 MISS로 알림 |
| D6 | 루트 `AGENTS.md`에 규칙 한 절. 별도 skill 없음 |
| D7 | 색인 대상은 추적 파일과 아직 add하지 않은 새 파일 중 `src/`(`src/win_tools/` 제외)와 `pl_engine/` |
| D8 | 수락 시험으로 판정하고, 2주 뒤 재측정은 참고용 |
| D9 | `CONTEXT.md` 용어: 작업 워크트리, 코드 색인 |
| D10 | Universal Ctags(YACC·LEX 파서 끔) + GNU Global(`.i` 포함, `-r`와 `-s` 합집합) + 첫 열 정의 검사 + 문법 규칙 검사(수락 시험 1차 뒤 추가) |
| D11 | 결과마다 라이브러리와 `#if` 조건을 표시. 빌드별 판정은 하지 않음 |
| D12 | nixpkgs `c7def046b9a8`로 고정한 `tools.nix`를 `nix-build`로 `.git_ignored_dir/code-index/tools`(GC root)에 설치 |
| D13 | nixpkgs의 global을 그대로 쓰고, 함께 오는 python3로 래퍼를 실행 |
| D14 | `body`는 500줄 상한(앞 60줄)과 `--all`, `outline`은 시그니처 생략, `callers`·`references`는 200건 상한과 `--all` |
| D15 | 이 문서와 2주 뒤 재측정 이슈. ADR은 쓰지 않음(래퍼 뒤에서 도구를 바꾸기 쉬워 되돌리기 어려운 결정이 아님) |
| D16 | 수락 시험을 통과하면 `main`에 커밋하고 push |

## 6. 수락 시험

nix 바이너리(Universal Ctags 6.2.1, GNU Global 6.6.14, Python 3.14.7)로 develop `2f1a1d5c5`의 scratch 복제본에서 돌렸다. 실제 엔진 워크트리는 건드리지 않았다.

1차에서 문법 규칙이 하나도 색인되지 않았다. GNU Global의 yacc 파서가 `csql_grammar.y`와 `load_grammar.yy`에서 규칙을 뽑지 못했기 때문이다. 그래서 규칙 머리를 찾는 텍스트 검사를 넣었다. 규칙은 규칙 구간의 첫 열 이름이고, `:`가 같은 줄이나 다음 줄에 오며, `;` 줄에서 끝난다. 2차에서는 44개 항목이 모두 통과했다.

| 항목 | 결과 |
|---|---|
| 설치 | `just code-index-install`: 처음 36 s(바이너리 캐시에서 받음), 다시 실행하면 1.4 s. `cubrid-deps-check`는 OK |
| 첫 색인 | 1,393개 파일 2.9 s, 색인 35 MB. 바뀐 파일이 없을 때 조회 중앙값 0.16 s |
| 정의 | `btree_insert`, `alloc_entries`(`cubthread::manager::alloc_entries` 형태 포함), `ASSERT_ERROR`, `DB_VALUE` 2곳, `spec_list` 5곳과 소속 구조체, `ExecuteThread`, `PT_SELECT`, 문법 규칙 `stmt`·`select_stmt`·`loader_start` 모두 정답 |
| 본문 | `qexec_execute_mainblock`은 반환형 줄 15974부터 16033까지 출력. 5,186줄인 `pt_evaluate_db_value_expr`는 앞 60줄과 안내만 출력(2,285자, `--all`이면 142,423자) |
| 호출자 | `qexec_clear_xasl` 21/21, `heap_get_visible_version` 29/29, 오탐 0. `parser_make_expr_with_func`는 문법 동작 코드 안의 5곳을 감싼 규칙 이름과 함께 출력 |
| 개요 | `btree.c` 함수 415/415가 정답과 일치(26,963자). `csql_grammar.y`는 규칙 595개를 포함해 792개 항목(28,686자) |
| 모드·NDEBUG | `pgbuf_fix_release`가 `{server,sa} [#else of !defined(NDEBUG)]`로 나옴. `db_private_alloc_release`는 진짜 정의(438-538)와 Windows용 빈 함수를 둘 다 표시. `es.c:166`은 `[#else of defined (CS_MODE)]`로 나오고, 이름이 로그 문자열에만 있는 167행은 빠짐. `.i`에 정의된 `db_get_object`의 호출 210곳을 찾음 |
| 갱신 | 파일 1개 수정 0.1 s, add하지 않은 새 파일의 추가와 삭제 모두 반영, 29개 일괄 갱신 0.2 s. 작업 트리의 git status는 변화 없음 |
| 동시 실행 | 빈 색인에 두 조회를 동시에 실행해도 둘 다 정답이고, 색인은 한 번만 만들어짐 |
| info/exclude | `/.cache/`를 무시하지 않는 복제본이면 공통 `info/exclude`에 한 줄을 넣고 알림. git status에는 `.gitignore` 수정만 남음 |
| 오류 경로 | 툴링 레포나 하위 디렉터리를 WORKSPACE로 준 경우, 없는 이름, 정의가 여럿인 `body`, 색인 범위 밖 파일, 식별자가 아닌 이름 모두 의도한 종료 코드와 안내를 냄 |

출력 크기는 rg 기준선과 비교하면 다음과 같다.
- 정의 `btree_insert` 241자(rg 1,367자)
- 매크로 `ASSERT_ERROR` 54자(73,297자)
- 타입 `DB_VALUE` 107자(638,023자)
- 구조체 멤버 `spec_list` 343자(47,182자)
- 열거자 `PT_SELECT` 70자(33,063자)
- 호출자 `qexec_clear_xasl` 2,944자(4,657자)
- 호출자 `heap_get_visible_version` 5,218자(5,464자)

호출자 조회는 글자 수 차이가 작다. 대신 오탐이 사라지고 줄마다 감싼 함수가 붙으므로, 호출 지점마다 앞뒤를 다시 읽는 왕복이 없어진다.

## 7. 한계

- `callers`와 `references`는 이름으로만 맞춘다. C++에서 다른 클래스의 같은 이름 메서드를 구분하지 못한다.
- 정의의 `{...}`는 CMakeLists의 소스 목록만 본다. 헤더에는 붙지 않고, 세 라이브러리 밖에서 컴파일되는 파일은 `{other}`로 나온다.
- `.l` 파일은 GNU Global이 읽지 않는다. 그 안의 C 함수 정의는 첫 열 검사로 찾지만, 그 안의 호출은 `callers`에 나오지 않는다.
- 2주 뒤 재측정은 GitHub 이슈로 남겼다. 기준선은 도입 전 2주(2026-09-17 ~ 2026-09-30, 세션 92개) 동안 엔진 grep/rg 7,120회 12,427,114자, `sed -n` 범위 읽기 2,501회 9,641,552자다.
