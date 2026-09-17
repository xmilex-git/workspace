# PR #7866 레이아웃 재계산 가드 — 설계 문답

- 날짜: 2026-09-14
- 상태: 구현·빌드·정확성 검증 완료. 사용자 지시로 커밋·push·원 리뷰 스레드 답글 게시까지 완료. 성능 측정은 명시적으로 제외.
- 기준: `57f33d1e91675557ebf05be253b04885feffd870` (GitHub HEAD와 로컬 엔진 HEAD 일치)
- 리뷰: https://github.com/CUBRID/cubrid/pull/7866#discussion_r4002740225
- 관련 설계: [ADR 0016](../adr/0016-qfile-tuple-format-pg-style.md), [레이아웃 디스크립터](cbrd27365-layout-descriptor.md)
- 용어: [CONTEXT.md](../../CONTEXT.md)의 기존 튜플 호환성, NULL-only 컬럼, 도메인 확정, 레이아웃 확정.

## 확인한 사실

1. `qfile_set_layout()`은 기존 컬럼 배열을 덮어쓴다. 현재 도메인에서 재계산한 결과와 비교하는 debug `qfile_type_list_check()`는 이전 튜플 호환성을 검사하지 않는다 (`src/query/qfile_tuple_layout.c:165–235`).
2. 직렬 `qfile_update_domains_on_type_list()`는 `changed`일 때 재계산한다. 따라서 도메인 확인 함수의 호출 횟수와 재계산 횟수를 구분해야 한다 (`src/query/list_file.c:6898–6983`).
3. 병렬 `update_domains_on_type_list_by_val_list()`는 NULL 값을 만나면 `is_domain_resolved=false`로 남기며, 끝에서 재계산을 무조건 수행한다. 호출부는 미확정 상태이면 이를 다시 호출한다. NULL 컬럼이 계속 남는 실행에서는 행마다 재계산할 수 있다 (`src/query/parallel/px_scan/px_scan_result_handler.cpp:60–85,1085–1095`).
4. 값 배열 크기 계산 경로는 VARIABLE 컬럼 하나를 확정할 때 재계산하고 처음부터 다시 계산한다. 여러 컬럼이 같은 행에서 확정되는 경우도 있어, 재계산을 질의당 1회로 제한하는 구조가 아니다 (`src/query/qfile_tuple_layout.h:740–787`).
5. `layout_ready`는 계산 완료 상태다. 기록 이력을 나타내지 않으며 `qfile_set_layout()` 인자에는 `tuple_cnt`도 없다. 집계 리스트는 입력 operand 도메인으로 열리고 (`src/query/query_aggregate.cpp:93–100`), interpolation 도메인 조정이 튜플 추가보다 먼저 실행된다 (`:1184–1206`). 조정 함수는 VARIABLE/NULL 게이트 없이 리스트 도메인을 교체한다 (`:3297–3302`). 따라서 기록 전 물리적 타입 변경을 허용하는 계약이 필요하다. SQL 실행으로 검증하지 않았으며 현재 오답 재현 사례로 주장하지 않는다.
6. walker는 `alignby`에도 의존한다. `kind/size/value_format`만 비교하면 정렬 규칙 변경을 빠뜨린다. 이 네 필드의 일치도 임의 타입 간 값 해석의 의미까지 보장하는 일반적인 증명은 아니다.
7. 기존 ADR은 늦은 도메인 확정 전 값이 NULL이라는 계약과 debug 교차 검증을 채택했다. 기존 교차 검증과 이번의 이전/이후 호환성 검사는 서로 다른 검사다.
8. `qfile_value_body_size()`에는 FIXED 폭 불일치와 DIRECT 인코딩 불일치를 release에서도 거부하는 기존 처리가 있다 (`src/query/qfile_tuple_layout.h:407–471`). 이는 새로 쓰는 값과 현재 레이아웃의 일치에 대한 검사이며, 이전 튜플과 바뀐 레이아웃의 호환성 검사는 아니다. `qfile_tuple_size_from_values()`의 타입 일치 경로는 크기를 직접 계산하고 이 함수와의 교차 검증은 assert로만 수행한다 (`:754–793`). 따라서 모든 쓰기에서 이 가드가 실행된다고 설명하지 않는다.

## 성능 판단의 경계

- 현재 벤치마크 없음. "release 성능 저하"와 "비용 사실상 0" 모두 미입증이다 (cpp-perf-rules MEAS-01).
- 별도 사전 검사라면 재계산당 컬럼 C개의 도메인 파생과 비교를 추가한다. 병렬 미확정 경로에서 R개 행 동안 반복되면 추가 작업은 O(R×C)이다. 기존 재계산 자체도 O(C)이므로 새 복잡도 계층이 생기는 것은 아니다.
- 아직 hot-path 프로파일이 없으므로 측정된 병목이라고 부르지 않는다. 도메인 변경 경계에서 검사하는 설계와 정상 행 접근자마다 검사하는 설계를 구분한다 (BR-04).
- debug 전용을 택한다면 비교뿐 아니라 임시 값 생성과 사전 순회 전체가 `!NDEBUG`에서만 컴파일되어야 한다. 실제 release 산출물 확인 전에는 비용 0을 확정하지 않는다.
- release 가드의 회귀 판정이 필요해지면 미확정 NULL이 오래 남는 병렬 경로, 넓은 컬럼, 직렬 대조군을 포함한다. 반복 실행 중앙값·산포를 비교하고 바이너리 배치 변화도 분리한다 (MEAS-04/07/08).

## 결정 트리

- D1 방어 범위 — 사용자 확정: debug 전용으로 검사한다.
  - 이유: 내부 불변식 검증을 debug에 한정한다. 실제 release 성능 저하가 측정됐다는 주장은 하지 않는다.
  - 대가: 향후 불변식 위반을 debug 검증에서 놓치면 이번 검사로 release에서 차단하지 못한다.
  - 재검토 조건: 정상 SQL로 기존 튜플의 비호환 해석이 재현되면 별도 정확성 결함으로 보고한다. 검사를 debug로 제한하는 것만으로 그 결함을 해결했다고 하지 않는다.
- D2 성능 수용 기준 — 사용자 확정: release 추가 검사 자체를 피한다.
  - 구현 제약: 비교, 임시 값, 추가 순회 등 검사 전용 작업 전체를 `!NDEBUG`로 제거한다. 검사 때문에 release 오류 전파를 추가하지 않는다.
  - 검증 방향: release에서 검사 코드가 제외되는지 확인한다. 성능 A/B를 debug 전용 선택의 선행 조건으로 요구하지 않는다.
- D2 후속 변경 — 사용자 구현 지시: 기존 FIXED 폭·DIRECT 인코딩 검사와 새 재계산 검사를 모두 debug 전용으로 바꾼다. "기존 release 검사 유지"라는 앞선 범위는 이 지시로 대체한다. 실제 성능 테스트는 하지 않고 코드와 리뷰 답변에 집중한다.
  - 대가: 기존 두 불변식 위반도 release 오류 반환으로 차단하지 않는다. debug assert로 계약 위반을 검출한다. 정상 크기 계산에서 발생하는 별도의 실패 처리는 유지한다.
- D3 검사 범위 — 사용자 결정: 우선 리뷰의 물리적 조건(`kind/size/alignby/value_format`) 검증에 한정한다.
  - 이유와 대가: 리뷰 범위를 작게 유지한다. 같은 폭의 다른 타입을 포함한 값 해석 호환성은 보장하지 않으며, 이를 확장하려면 타입·도메인별 허용 관계 정의가 별도로 필요하다.
  - 필요한 조건: 기록 전 변경 허용과 기록 후 검사를 구분한다. NULL/VARIABLE 예외는 기존 값이 NULL-only라는 계약에 의존한다. `layout_ready`만으로 기록 후 상태를 추정하지 않는다.
  - 구현 검토안: 기존 배열 덮어쓰기 전 debug 전용 비교, 추가 힙 할당 없이 컬럼별 임시 레이아웃 사용. 기록 전 예외는 해당 호출부에서 빈 리스트임을 assert하는 등 명시적 근거를 둔다. release에서 추가 인자 평가·분기·상태 추적이 생기지 않도록 구현한다. 구체 API는 미정이다.
- D4 검증 계획: 아래 계약별 검증을 구현 시 수행한다. 아직 실행하지 않았다.

## 최종 검사 계약안

1. **검사 위치와 동작:** 기존 컬럼 레이아웃을 덮어쓰기 전에 debug에서만 검사한다. 최초 계산은 이전 레이아웃과 비교하지 않는다. 실패하면 assert로 불변식 위반을 드러낸다. 검사 때문에 `void → int` 또는 release 오류 전파를 추가하지 않는다.
2. **비교 대상:** 기존 타입이 NULL/VARIABLE이 아닌 컬럼의 `kind`, `size`, `alignby`, `value_format`을 새 도메인에서 파생한 값과 비교한다. 전체 구조체 `memcmp`는 사용하지 않는다. 늦은 타입 확정으로 뒤 컬럼의 캐시 오프셋과 고정 접두 경계는 합법적으로 바뀔 수 있다.
3. **허용 전환:** 기존 NULL/VARIABLE 컬럼의 구체 타입 확정은 이전 값들이 모두 NULL이었다는 기존 계약 아래 허용한다. 빈 리스트에서 저장 도메인을 조정하는 경우도 허용한다. 빈 리스트 예외는 해당 호출 경계의 기록 이력으로 입증하며, interpolation이라는 함수 이름만으로 항상 우회시키지 않는다.
4. **release 제약:** 검사 전용 순회, 임시 레이아웃, 예외 확인, 인자 평가와 상태 추적 전체를 `!NDEBUG`로 제외한다. 기록 여부 추적을 위해 release의 행 쓰기 경로에 작업을 추가하지 않는다. 구체적인 helper/API 형태는 이 제약 안에서 구현 시 결정한다.
5. **검증:** debug에서 최초 계산·빈 리스트 타입 변경·NULL-only 이후 확정과 기존 행 읽기·동일 물리 포맷 변경이 통과해야 한다. 기존 bound 값이 있을 때 네 필드 중 하나가 비호환으로 바뀌면 assert로 검출해야 한다. 병렬 미확정 NULL 경로도 확인한다. release 빌드에서 검사 코드 전체가 제외되는지 확인한다. 성능 저하가 있었다고 주장하기 위한 벤치마크는 이번 선택의 전제가 아니다.

이 계약은 기존 ADR 0016의 debug 교차 검증을 보완한다. 기존 설계 결정을 뒤집는 새 ADR은 만들지 않고, 이 문서에 선택 근거와 검증 범위를 남긴다. 사용자는 이 정리가 의도한 범위와 맞는다고 답했으며, 추가 release 안전가드 필요성을 질문했다.

## 추가 release 안전가드에 대한 판단

- 당시 권고는 **기존 release 검사를 유지하고, 이번 이전/이후 레이아웃 불변식 검사는 debug에 추가**하는 것이었다. 이후 사용자 구현 지시(D2 후속 변경)로 기존 두 가드도 debug 전용으로 바꾸는 것으로 대체했다. 추가 release 가드가 불필요하다는 전체 경로 증명과 사용자 선택을 혼동하지 않는다.
- 예를 들어 bound INT가 기록된 뒤 레이아웃을 BIGINT로 바꾸고 새 값도 BIGINT로 주면, 새 값과 새 레이아웃은 일치한다. 기존 쓰기 가드로 이전 INT 튜플의 오독을 막을 수 없다. 이는 위험을 설명하는 가상 전환이며 정상 SQL에서 재현한 결함이 아니다.
- 단순 `layout_ready`/포인터/폭 정상 범위 검사는 이 시간에 따른 불일치를 검출하지 못한다. 이 위험을 release에서도 막으려면 도메인 변경 경계에서 이전/이후 호환성을 검사하거나, 유효한 전환만 가능하도록 그 경계의 계약을 강제해야 한다. 이를 값 검사 하나로 대체했다고 하지 않는다.
- debug 전용 결정은 정상 도메인 전환이 계약을 지킨다는 전제의 개발 불변식 검사 정책이다. 구현 검증에서 정상 SQL이 기록 후 비호환 전환에 도달한다면 assert를 끄거나 우회해 통과시키지 않고, 잘못된 전환의 수정 또는 필요한 경계 검증으로 별도 정확성 결함을 처리한다.

## 구현

- 대상 체크아웃: `/home/cubrid/dev/worktrees/cbrd27365`, 브랜치 `CBRD-27365-pr3`. fetch 후 tracking branch와 동기 상태 확인. 기존 `cubrid-cci` 변경은 보존.
- `src/query/qfile_tuple_layout.h`: 기존 DIRECT 인코딩·FIXED 폭 오류 분기를 assert로 바꿨다. 인코딩 선택 및 크기 계산은 유지한다.
- `src/query/qfile_tuple_layout.c`: 기존 배열을 덮어쓰기 전에 네 필드를 비교한다. 추가 루프와 컬럼별 임시 값 전체를 `!NDEBUG`로 감싼다. NULL/VARIABLE 예외와 최초 계산 건너뛰기를 포함한다.
- `src/query/query_aggregate.cpp`: interpolation 도메인 변경 시 빈 리스트에 한해 debug에서 `layout_ready`를 해제한 뒤 계산한다. 이미 튜플이 있으면 새 비교가 수행된다. release에서는 이 분기와 상태 변경이 모두 제외된다.
- 새로운 API, 구조체 필드, release 반환형 변경은 추가하지 않았다.
- 검증 작업: `.git_ignored_dir/scratch/herdr-integration/pr7866-debug-guards-e9b58de8/`. Sonnet 작업자에게 optdebug/release 빌드, 실제 전처리 결과, assert 및 소형 정확성 검증을 위임했다. 성능 테스트·프로파일링·속도 향상 주장은 금지했다.

### 기존 release 검사의 비용에 대한 추가 확인

- 여기서 "기존"은 현재 PR HEAD `57f33d1e9`에 이미 존재한다는 뜻이다. develop에 있던 검사라는 의미로 사용하지 않는다.
- `qfile_value_body_size()`의 DIRECT 인코딩 불일치와 FIXED 폭 불일치 검사는 `!NDEBUG` 밖에 있다. 정상 경로에서는 조건 평가를 하고, 오류일 때만 `er_set` 및 실패 반환을 수행한다. 이 두 검사 자체는 추가 배열 할당이나 튜플 재순회를 하지 않는다.
- `qfile_tuple_size_from_values()`는 값 타입과 컬럼 타입이 같으면 직접 크기를 계산한다. 이 경로의 `qfile_value_body_size()` 호출은 assert 안에만 있으므로 release에서 제외된다. 다만 경로 선택을 위한 타입 비교 자체는 남는다. 타입이 다르고 늦은 도메인 확정으로 처리되지 않는 경우에는 크기 함수와 오류 반환 검사가 실행된다.
- 일반 `qfile_tuple_size()`는 NULL이 아닌 DB_VALUE 소스마다 해당 함수를 호출하고 음수 반환을 검사한다. 반면 raw 바이트 소스는 이 함수를 호출하지 않는다. 실제 예로 `qfile_build_sort_rec()`는 컬럼 소스를 raw로 만든다.
- 따라서 두 기존 가드의 비용을 전체 행·전체 컬럼에 일괄 적용할 수 없다. 해당 일반/타입 불일치 경로를 통과하는 값 수에 비례한다. 크기 계산과 인코딩 선택은 원래 필요한 작업이므로 그 함수 전체 비용을 검사만의 비용으로 귀속하지 않는다.
- 예상되는 직접 추가 작업은 조건 비교와 분기지만, 실제 명령 수·인라이닝·분기 예측·전체 질의 영향은 컴파일 산출물과 프로파일 없이 확정하지 않는다. 병목 측정과 A/B 없이 제거를 성능 개선으로 권고하지 않는다 (MEAS-01, BR-08, CC-05).

## 최종 검증 결과

- 최종 엔진 diff SHA256(세 파일): `5f24b95818f2799a670d7fd33be8bb9e96554acd08b1e25e36f9a880547e9dcd`. 최초 검증 후 긴 assert 식만 줄바꿈했고, 해당 최종 소스로 두 모드 증분 빌드와 검사를 갱신했다.
- optdebug/release 전체 설치 빌드 통과. 실제 컴파일 명령의 전처리 출력에서 기존 두 assert·새 비교 루프·interpolation의 빈 리스트 예외가 release에 포함되지 않음을 확인했다. 인코딩 선택과 크기 계산은 유지됨을 별도로 확인했다.
- 보완한 실제 엔진 함수 harness **10/10 통과**: VARIABLE→INTEGER/BIGINT 및 NULL→INTEGER 전환 뒤 기존 `(NULL,77)` 튜플의 바이트 불변과 읽기 결과를 확인했다. VARCHAR 정밀도 확대는 기존 `hi` 값을 유지했다. 실제 INT→BIGINT 도메인 교체, FIXED 폭 불일치, JSON 값을 사용한 DIRECT 불일치에서 의도한 assert를 확인했다. kind/alignby/value_format 개별 비교는 과거 레이아웃 필드를 인위적으로 바꾼 음성 사례이며 실제 도메인 전환 재현으로 주장하지 않는다.
- INT→BIGINT 재계산의 이전/이후 검출 차이: 기준 HEAD의 `qfile_tuple_layout.c` 한 파일만 별도 컴파일한 제어 사례는 정상 반환했고, 변경 함수는 assert로 검출했다. 이 음성 사례는 레이아웃 상태만 사용했으며 잘못된 튜플을 release에서 쓰거나 읽지 않았다.
- 두 모드의 소형 CS SQL 스모크 통과: 정수/문자열 MEDIAN·PERCENTILE_CONT, GROUP BY, DISTINCT, NULL UNION 등의 결과가 일치했다. 병렬 실행 경로의 실제 진입은 입증하지 않았으며, 전체 CTP 통과로 확대하지 않는다.
- CI 설정 그대로 적용한 indent/astyle 결과와 세 파일이 일치하고 `git diff --check` 통과.
- 첫 harness의 OBJECT 값은 목표 DIRECT assert 전에 다른 assert에서 멈췄고, 초기 NULL 전환 사례는 레이아웃만 확인했다. 이 두 증거의 부족을 실제 JSON 값·실제 튜플 기록/읽기 테스트로 보완했다. 최초 보고서의 관련 과장 표현은 후속 보고서에서 정정했다.
- 검증 서버/master와 포트 클레임 정리 완료. 전용 Herdr 세션도 중지 상태 확인 후 삭제했고, 보고서와 설치본은 보존했다. 기존 `cubrid-cci` 변경 및 공용 `~/CUBRID`는 보존했다.
- 증거: [첫 보고서](../../.git_ignored_dir/scratch/herdr-integration/pr7866-debug-guards-e9b58de8/report.md), [보완 보고서](../../.git_ignored_dir/scratch/herdr-integration/pr7866-debug-guards-e9b58de8/report-followup.md), [최종 패치](../../.git_ignored_dir/scratch/herdr-integration/pr7866-debug-guards-e9b58de8/source.patch), [리뷰 답변 초안](pr7866-relayout-review-reply.md).

성능 테스트·프로파일링은 수행하지 않았다. 속도 향상은 입증하거나 주장하지 않는다.

## 커밋·리뷰 대응 완료

- 사용자 지시: "커밋+푸쉬+댓글게시". 함께 질문한 동작 동일성에는 정상 경로의 인코딩·계산은 유지하지만, 기존 두 불변식 위반 시 release 오류 반환은 제거됐음을 설명했다. 댓글에도 같은 경계를 명시했다.
- 커밋: [`30d57a1a0`](https://github.com/CUBRID/cubrid/commit/30d57a1a0ab275ac049203f6b8c6869d4c38f2fb), `[CBRD-27365] Keep tuple layout invariant checks debug-only`.
- push 대상: `xmilex/CBRD-27365-pr3`. GitHub PR #7866의 HEAD가 해당 커밋과 일치함을 재조회해 확인했다.
- 답글: [원 리뷰 스레드에 게시](https://github.com/CUBRID/cubrid/pull/7866#discussion_r4003101104). `in_reply_to_id=4002740225`, `commit_id=30d57a1a0ab275ac049203f6b8c6869d4c38f2fb` 확인.
- 커밋된 세 파일 diff SHA256이 위 최종 검증 대상 해시와 일치한다. 엔진의 남은 변경은 작업 전부터 있던 `cubrid-cci` 항목뿐이다.

## CI 후속 발견 — 앞선 정상 경로 판단의 범위 정정

사용자가 공유한 CircleCI 155077에서 17,459개 중 45개가 실패했다. 실행 로그의 직접 발화 지점은 새 `qfile_set_layout` 네 필드 비교 assert(`qfile_tuple_layout.c:190`)로 확인됐다. 실패는 일반 `qfile_update_domains_on_type_list` 경로의 지연 도메인 확정에 집중된다. 구체 타입도 collation 미확정이면 실제 결과 타입으로 교체될 수 있으며, interpolation에만 빈 리스트 예외를 둔 구현은 이 경로를 처리하지 못했다.

앞선 harness 및 작은 SQL 스모크의 통과는 그대로 사실이지만, 그것으로 모든 정상 SQL에서 동작이 유지된다고 일반화한 판단은 정정한다. [기록 기반 상세 분석](pr7866-ci155077-analysis.md)에 관측 사실·가장 유력한 원인·당시 지역변수 부재의 한계를 구분했다. 사용자 지시에 따라 이 후속 분석에서는 재현·엔진 수정·추가 게시를 하지 않았다.

이후 사용자 요청으로 [실제 값 기록 이력을 사용하는 수정](pr7866-bound-layout-fix.md)을 구현했다. 이전의 `layout_ready` 및 interpolation 한정 예외 방식은 `6ab2bc614`로 대체됐다. debug 전용 기록 이력을 추가했으며 release에는 상태/추적 코드를 추가하지 않았다. 최종 로컬 SQL 17,459/17,459와 원래 실패 45/45 통과를 확인하고 PR에 반영했다.
