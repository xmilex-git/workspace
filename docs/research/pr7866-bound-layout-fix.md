# PR #7866 — 저장된 값에 맞춘 debug 레이아웃 검사

## 문제와 변경

CircleCI 155077의 45개 실패는 새 `qfile_set_layout` assert에서 시작됐다. `layout_ready`는 계산 완료일 뿐 실제 값 기록 여부가 아니므로, 구체 타입이더라도 collation/host variable에 의해 첫 저장 타입이 결정되는 정상 경로를 막았다. [기록 분석](pr7866-ci155077-analysis.md).

수정은 검사 예외를 특정 함수나 도메인 플래그에 더하는 대신, **사용된 물리 레이아웃을 debug에서 추적**한다. 빈 리스트와 NULL-only 컬럼의 도메인 변경을 허용하고, 실제 non-NULL 값에 사용된 컬럼 레이아웃은 네 필드 비교로 보호한다.

## 결정

- D1: `QFILE_COL_LAYOUT`에 `!NDEBUG` 전용 `uint16_t has_bound_value`를 추가한다. release 구조체는 기존 8바이트를 유지하며 이력 갱신·검사 코드도 컴파일에서 제외된다. uint16_t는 기존 2바이트 정렬에 맞춰 새 패딩 없이 상태를 담는다.
- D2: 타입 id가 VARIABLE/NULL인지, collation 미확정인지로 기존 바이트 존재를 추정하지 않는다. 초기 이력은 0이며 non-NULL tuple bitmap을 기록한 컬럼에만 1을 남긴다. 이후 재계산은 이력이 있는 컬럼의 `kind/size/alignby/value_format`만 비교한다.
- D3: `qfile_tuple_fill*` 같은 공용 조립기에서는 이력을 바꾸지 않는다. 정렬 키 디스크립터가 병렬 sort worker 사이에 읽기 전용으로 공유되는 경로를 쓰기 경로로 바꾸지 않기 위해 **리스트 소유자의 기록 지점**에서 갱신한다.
- D4: 기존 배열 재계산과 type-list 복사는 이력을 보존하고, `qfile_type_list_check`는 도메인 파생값만 교차 검증하도록 scratch 배열에 같은 이력을 전달한다. 리스트 truncate는 이력을 0으로 되돌린다.
- D5: overflow tuple의 bitmap이 첫 페이지를 넘을 수 있으므로, 해당 페이지 복사는 소스의 사용 이력을 보수적으로 상속한다. 전체 페이지 append/connect도 소스 이력을 OR로 합친다. 이력은 "해당 물리 레이아웃이 사용됐다"는 보수적인 정보이며 row count 대체가 아니다.
- D6: interpolation 전용 `layout_ready=false` 우회는 제거한다. 새 공통 검사는 기록 이력이 없는 초기 타입 변경을 직접 허용한다.

기존 FIXED 폭·DIRECT 인코딩 검사는 앞서 합의한 debug assert를 유지한다. release 오류 경로를 다시 추가하거나 성능 테스트를 수행하지 않는다.

## 쓰기 경로별 처리

| 경로 | 이력 처리 |
|---|---|
| `qfile_generate_tuple_into_list` | 성공적으로 만든 페이지 내 tuple의 bitmap으로 갱신 |
| `qfile_add_tuple_to_list_from` (`qfile_add_tuple_to_list` 포함) | 완전한 원본 tuple과 원본 header 크기로 갱신 |
| `qfile_add_tuple_get_pos_in_list` | 원본 tuple bitmap으로 갱신 |
| 해시 집계의 retained `first_tuple`, `qfile_copy_tuple_descr_to_tuple` | 소유자가 실제로 보관한 tuple buffer의 bitmap으로 갱신 |
| `qfile_add_overflow_tuple_to_list` | 소스 리스트의 사용 이력을 보수적으로 상속 |
| `qfile_append_list`, `qfile_connect_list` | 소스 이력을 목적지에 합침 |
| `qfile_type_list_copy` / list-id clone | 기존 합본 블록 복사로 이력 상속 |
| `qfile_truncate_list` | 이력 초기화 |
| 임시 sort-key 조립 / descriptor 계산 | 새 사용 이력을 만들지 않음 |

## 검증 계획과 진행 상태

- 엔진 기준 HEAD: `30d57a1a0ab275ac049203f6b8c6869d4c38f2fb`.
- TC 고정 SHA: `1eea18808fd865f6f77c33950f8f9750bb662eda` (`tc/pr-7866`).
- `herdr-integration` Sonnet 작업자에게 기존 설치본으로 실패 디렉터리 red 확인, 수정 빌드, CI 실패 디렉터리 전체 재실행 및 optdebug 전체 SQL suite를 위임했다. CTP는 `ctp-run` 컨테이너만 사용한다.
- 작은 실제 엔진 검증은 구체 미확정 도메인의 첫 기록, 선행 NULL 행, 이후 bound 컬럼 읽기, 이미 기록한 bound 값의 비호환 변경 assert, clone/truncate/복사 이력을 다룬다.
- release에서 상태 필드와 코드가 제외되는 실제 컴파일 증거, CI 포맷 검사, 정확한 엔진/TC/설정 provenance를 남긴다.
- 검증 작업 디렉터리: `.git_ignored_dir/scratch/herdr-integration/pr7866-bound-layout-3c94dc2e/`.
- 검증 중 source diff SHA256: `d220f11e2730faa06485380569c3de34f3bf1cdc79006bdca0fded21d21cc3e8`.

## 첫 검증 결과와 최종 보완

소스 diff `d220f11e…` 기준:

- 기존 설치본의 첫 시도는 JDBC jar 누락으로 테스트 자체가 실행되지 않았다. 원본 설치를 바꾸지 않고 별도 복사본에 jar를 보완한 뒤, `issue_8700_enum/001_late_binding.sql`에서 기존 `qfile_set_layout:190` assert를 재현했다.
- 수정 optdebug/release 빌드 통과. release `QFILE_COL_LAYOUT` 8B, optdebug 10B이며 release에는 새 이력 필드/갱신 코드가 제외됨을 확인했다.
- CI 실패 45개가 속한 10개 디렉터리: **123/123 통과, 실패 0, core 0**.
- optdebug 전체 SQL: **17,459/17,459 통과, 실패 0, core 0**.
- release의 작은 CTP 확인: **61/61 통과**.
- 실제 엔진 helper를 사용하는 focused harness 7개 통과. 그중 truncate는 실제 API 호출이 아닌 이력 초기화 효과만 확인한 제한이 있으므로 truncate 통합 검증이라고 쓰지 않는다.
- 헤더의 함수 선언 줄바꿈 1곳이 CI formatter와 달랐으며 리드가 수정했다. 사용자와 무관한 기존 문제가 아니라 이번 변경의 포맷 문제였다.

소스 감사에서 해시 집계가 페이지 삽입 전에 따로 보관하는 `first_tuple` 두 경로를 추가 확인했다. 이 버퍼도 나중에 해당 레이아웃으로 읽으므로, 소유자의 두 저장 지점에 debug 이력 갱신을 연결했다. 공용 sort-key 조립기는 계속 건드리지 않는다.

## 최종 검증 및 반영 완료

최종 6파일 diff SHA256: `95f9e9b8e1e9dfd90f5b02b30bd25c8c58a022006e841151c4b742ca9832f0d7`.

- 최종 소스로 optdebug/release 증분 설치 빌드 통과. 6파일 모두 CI formatter와 일치하고 `git diff --check` 통과.
- 최종 optdebug SQL 전체 재실행: **17,459 성공 / 실패 0 / core 0**. run `sql-20260914T102420Z-349275`, SHARDS=4, TC SHA는 위와 동일.
- 최종 4개 shard의 `summary.xml`을 원래 실패 목록과 다시 대조: **45/45 발견 및 성공, 누락 0, 비성공 0**. 리드가 원본 XML에서도 재확인했다.
- 최종 객체로 focused helper harness 재실행 7/7 통과. 앞서 적은 truncate 수동 초기화 테스트의 한계는 유지하며 별도 실제 API 단위 검증이라고 하지 않는다. 전체 suite 통과 역시 개별 코드 행의 실행을 계측했다는 뜻은 아니다.
- release에서 `sizeof(QFILE_COL_LAYOUT)==8`, optdebug에서 10을 실제 컴파일로 확인했다. 새 상태와 호출부는 `!NDEBUG`에만 존재한다. 성능 측정·프로파일링은 하지 않았다.
- [최종 검증 보고서](../../.git_ignored_dir/scratch/herdr-integration/pr7866-bound-layout-3c94dc2e/report-final.md), [전체 SQL 실행 로그](../../.git_ignored_dir/scratch/herdr-integration/pr7866-bound-layout-3c94dc2e/logs/step4-full-suite-final.log), [원래 45개 대조 결과](../../.git_ignored_dir/scratch/herdr-integration/pr7866-bound-layout-3c94dc2e/original-45-verification.json).
- 커밋 [`6ab2bc614`](https://github.com/CUBRID/cubrid/commit/6ab2bc614839f1ed3cedc79620f9d2fc9224c12b)을 `xmilex/CBRD-27365-pr3`에 push했고 PR #7866 HEAD 일치를 재조회했다. 커밋 diff 해시도 최종 검증 해시와 일치한다.
- [원 리뷰 스레드 답글](https://github.com/CUBRID/cubrid/pull/7866#discussion_r4004345740)에 회귀 원인, 수정, 로컬 검증 결과를 게시했다. 게시 본문이 준비한 본문과 일치함을 확인했다.
- 테스트 컨테이너와 전용 Herdr 세션 정리 완료. 보고서·설치본·기존 코드의 red core는 scratch에 보존했다. 공용 `~/CUBRID`와 작업 전의 `cubrid-cci` 변경은 보존했다.

이 결과는 **로컬 컨테이너 CTP 검증**이다. 새 커밋의 CircleCI 테스트 재실행 결과를 확인했다는 의미는 아니다.
