# PR #7866 / CircleCI 155077 — 기록 기반 실패 원인 분석

## 결론

대량 실패의 직접 발화 지점은 커밋 `30d57a1a0`에서 추가한 `qfile_set_layout()`의 **기존/신규 물리 레이아웃 비교 assert**다. CircleCI 실행 로그에 `qfile_tuple_layout.c:190`과 네 필드 비교식이 명시돼 있다. 이것은 추측이 아닌 로그로 확인한 사실이다.

코드와 실패 SQL을 함께 보면, **`layout_ready`를 기존 튜플에 대한 호환성 검사가 필요한 상태로 취급한 것이 과도하며, interpolation 외의 지연 도메인 확정 경로를 빠뜨린 것**이 가장 유력한 설계 원인이다. 특히 collation 미확정 도메인은 타입이 VARIABLE이 아니어도 실제 계산 결과 타입으로 바뀔 수 있다. 다만 아티팩트는 텍스트 호출 스택이므로 당시 `tuple_cnt`, 컬럼 번호, old/new 타입과 필드 값은 관측하지 못했다. 모든 발생 건이 빈 리스트였다고 확정하거나, 기존 튜플 손상 여부까지 판단하지 않는다.

사용자 지시에 따라 **재현·빌드·SQL 실행·CI 재실행·엔진 수정 없이** 이미 생성된 기록과 코드를 분석했다. 성능 측정도 하지 않았다.

## 1. 실행 및 실패 규모

- [CircleCI job 155077](https://app.circleci.com/pipelines/github/CUBRID/cubrid/37236/workflows/253208fd-5eba-47ac-9ea8-ef9a74c6e0a8/jobs/155077/tests)
- 엔진 SHA: `30d57a1a0ab275ac049203f6b8c6869d4c38f2fb`, `pull/7866/head`.
- TC ref: `tc/pr-7866`, SHA `1eea18808fd865f6f77c33950f8f9750bb662eda`.
- 실행: 2026-09-14 08:27:17–08:51:46 UTC. 애플리케이션 로그는 17시대(KST)를 사용한다.
- 실행 결과 클래스: `linux_sql_64bit_debug`. 빌드 다운로드 로그와 `64 optdebug build` 배너도 확인했다. release를 실행한 결과로 해석하지 않는다.
- 테스트 결과 API: **17,459개 중 성공 17,414 / 실패 45**. 페이지 토큰 없음.

| shard | JUnit에 기록된 실행 수 | 실패 | 실패 결과에 `-21019` 포함 | 그 외 실패 |
|---|---:|---:|---:|---:|
| 1 | 882 | 21 | 3 | 18 |
| 3 | 2,538 | 17 | 5 | 12 |
| 8 | 612 | 7 | 2 | 5 |
| 실패 shard 합계 | 4,032 | **45** | **10** | **35** |

나머지 7개 shard는 `Run tests` 성공으로 기록됐다. 표의 실행 수 합계는 실패 shard만의 수이며 전체 17,459와 혼동하지 않는다.

45개를 45개의 독립 엔진 결함으로 볼 근거는 없다. 10개는 서버 종료 시점/통신 단절과 직접 연결되는 실패이고, 나머지 35개는 이후 접속 실패, 읽기 전용 서버 상태, 남은 테이블/준비문 상태 때문에 실패가 확산된 양상이다. **35개 각각의 독립 원인을 재현으로 배제한 것은 아니다.** [전체 45개 분류](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/failure-classification.md).

## 2. 정확한 assert와 저장 스택

실행 stdout/stderr에서 동일한 문구가 14줄 확인된다. 이는 **로그 출력 횟수**이며, 중복 출력·동시 실행 가능성 때문에 독립 crash 횟수와 같다고 하지 않는다.

```text
cub_server: /home/src/query/qfile_tuple_layout.c:190:
void qfile_set_layout(QFILE_TUPLE_VALUE_TYPE_LIST*):
Assertion `old_layout->kind == new_layout.kind && old_layout->size == new_layout.size
  && old_layout->alignby == new_layout.alignby
  && old_layout->value_format == new_layout.value_format' failed.
```

- shard 1: [실행 로그](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/steps/1-Run-tests.txt) 604–605, 630, 697행.
- shard 3: [실행 로그](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/steps/3-Run-tests.txt) 2236, 2357–2358, 2382, 2409–2410, 2434행.
- shard 8: [실행 로그](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/steps/8-Run-tests.txt) 526–527, 570행.

`.coredump` 아티팩트 **19개 모두** 확인했다. 바이너리 ELF 코어가 아닌 CUBRID가 남긴 호출 스택 텍스트다.

- cub_server 9개 중 5개는 충분한 스택이 있고 모두 같은 핵심 호출 경로다.
- 나머지 서버 4개는 스택 기록 함수 1–3프레임까지만 남은 불완전 자료다. crash가 없었다는 증거로 사용할 수 없다.
- CAS 10개는 대부분 서버 응답을 기다리는 `poll`/네트워크 수신, 하나는 `accept` 대기 상태다. 파일이 있다는 이유로 CAS 독립 crash 10개로 세지 않는다. 실제 broker SQL 로그에는 이후 CAS 종료·재기동도 기록되므로 대기 중 스냅샷과 이후 프로세스 종료를 구분한다.

완전한 서버 스택의 확인 가능한 핵심 경로:

```text
qexec_execute_mainblock
  → [텍스트 스택에서 이름이 없는 중간 프레임들]
  → qfile_update_domains_on_type_list
  → qfile_set_layout
  → libc assertion/abort
```

중간 프레임을 `qexec_generate_tuple_descriptor`라고 실제로 심볼 해석한 것은 아니다. 아래 절의 해당 함수 연결은 소스에 존재하는 호출 관계다.

## 3. 사용자가 지목한 17:30:53.310 파일의 SQL 연결

[해당 서버 스택](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/artifacts/1/tmp/logs/cubrid_log/coredump/cub_server_20260914173053.310.coredump)의 12–13행에 `qfile_set_layout`과 `qfile_update_domains_on_type_list`가 있다. [안정적인 CircleCI 아티팩트 주소](https://output.circle-artifacts.com/output/job/cdb77062-f334-4b5d-a41c-b1f313642df7/artifacts/1/tmp/logs/cubrid_log/coredump/cub_server_20260914173053.310.coredump)를 사용했으며, 사용자 메시지의 단기 서명 URL은 보고서에 재기록하지 않았다.

[shard 1 broker1_1.sql.log](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/artifacts/1/tmp/logs/cubrid_log/broker/sql_log/broker1_1.sql.log) 12778–12802행:

1. **17:30:53.306** — ENUM 컬럼을 포함한 다음 준비문 생성.
   ```sql
   prepare x from 'select e1 + ?, ? + e1, e1 + ?, e1 * ?, e1 + ?
   from t1 where e1 < ? order by 1, 2, 3, 4, 5';
   ```
2. **17:30:53.308** — `execute x using 1, 1, 1.1, 5, '-', 7;` 실행.
3. **17:30:53.310** — 사용자가 지목한 서버 스택 생성.
4. **17:30:53.416** — `CAS TERMINATED pid 2128`.
5. **17:30:58.160** — 다음 연결 시도에서 `error:-677`, `Failed to connect to database server`.

테스트 결과의 `issue_8700_enum/cases/late_binding_003.sql`에 나타난 첫 `-21019` 문장과 일치한다. 같은 실행 인자는 다른 ENUM TC에도 있으므로 쿼리 문자열만으로 파일을 결정하지 않고 순서·시간·TC 결과를 함께 사용했다.

CTP의 `Testing ...` 문구와 서버 stderr는 비동기로 섞인다. 예를 들어 assert 바로 위 줄이 성공한 `index_003.sql` 또는 `number_number.sql`이라고 해서 그 TC가 발화점이라고 판단하면 틀린다. broker의 실제 실행 요청과 JUnit 문장 diff를 우선했다.

## 4. 코드와 대조한 메커니즘

좌표는 현재 SHA `30d57a1a0` 기준이다.

| 단계 | 코드 | 확인한 동작 |
|---|---|---|
| 리스트 초기 도메인 | `query_opfunc.c:6654–6710`, `qdata_get_valptr_type_list` | outptr의 도메인 포인터를 리스트 입력 도메인으로 복사한다. |
| 리스트 생성 | `list_file.c:1138–1144,1180–1194`, `qfile_open_list` | `tuple_cnt=0`인 상태에서 `qfile_set_layout`을 호출한다. 계산이 끝나면 `layout_ready=true`다. |
| 실제 표현식 평가 | `fetch.c:4483–4495`, `fetch_peek_arith` | collation 미확정 도메인이고 결과가 non-NULL이면 **실제 값으로 도메인을 다시 결정**하여 `regu_var->domain`을 교체한다. 타입 id가 VARIABLE인 경우에만 한정되지 않는다. |
| 도메인 갱신 | `list_file.c:6941–6954` | 이전 리스트 도메인의 collation이 미확정이면 새 `reg_var->value.domain`으로 교체한다. VARIABLE/NULL 타입 제한이나 동일 물리 포맷 제한이 없다. |
| 재계산 호출 | `list_file.c:6969–6971` | `changed`이면 `qfile_set_layout`을 호출한다. 완전한 CI 스택이 이 호출 관계를 직접 확인한다. |
| 이번 검사 | `qfile_tuple_layout.c:173–190` | `layout_ready`만으로 비교를 켜고, 이전 타입이 VARIABLE/NULL일 때만 제외한다. 실제 기록 여부는 보지 못한다. |
| 기록 전 순서 | `query_executor.c:982–1005`, `qexec_generate_tuple_descriptor` | 값 수집 → 도메인 갱신 → tuple size 계산 순서다. 첫 행도 이 경로를 탄다. |

ENUM 덧셈은 `query_opfunc.c:2389–2429`에서 상대 타입에 따라 ENUM을 VARCHAR 또는 SMALLINT로 변환한 후 계산한다. 따라서 ENUM/문자열 + host variable 테스트는 실제 값에 의해 결과 타입이 구체화되는 경로를 잘 드러낸다. `fetch_peek_arith`의 collation 처리도 실제 결과 타입을 반영한다.

**가장 유력한 원인:** 물리 레이아웃의 최초 계산과 저장 타입의 최종 확정을 같은 상태로 취급했다. 이전 도메인이 구체 타입이라도 collation 미확정 상태일 수 있고, 아직 튜플을 쓰지 않았는데도 호환성 assert가 발화할 수 있다. 기존 배열을 계산한 사실(`layout_ready`)은 기존 바이트가 그 배열로 저장돼 있다는 증거가 아니다.

이번 패치의 빈 리스트 예외는 `query_aggregate.cpp:3297–3309`의 interpolation에만 있다. 실제 CI 스택은 `qfile_update_domains_on_type_list`를 거치므로 그 예외를 적용받지 못한다. **제가 놓친 호출 경로가 이 일반적인 지연 도메인 확정 경로다.**

## 5. 우선순위별 가설과 증거 경계

1. **높은 확신 — 새 검사로 초기 도메인 확정을 과도하게 제한.**
   - 증거: exact assert, 일반 도메인 갱신 caller, ENUM/문자열+host variable에 집중된 실패, 생성 직후에도 ready인 코드, 첫 기록 전에 수행되는 갱신 순서.
   - 아직 없는 증거: 각 사고의 `tuple_cnt`, old/new 타입 id, 정확히 어느 필드가 달랐는지. 이 값이 없으므로 모든 사고가 빈 리스트에서 발생했다고 쓰지 않는다.
2. **열린 가능성 — 이미 저장한 non-NULL 값과 실제로 비호환인 변경을 잡았을 수 있음.**
   - 이를 확인하려면 당시 저장 이력·컬럼 값 상태가 필요하다. 텍스트 스택만으로 오탐/기존 정확성 결함의 경계를 각 사고별로 확정할 수 없다.
3. **35개 후속 실패를 독립 결함으로 해석하는 가설은 우선순위가 낮음.**
   - 접속 실패 `-677`, 수정 금지 `-581`, 테이블/컬럼 상태 관련 `-494/-493`, 준비문 없음 `-995`가 앞선 server abort 뒤에 몰린다.
   - broker 오류 로그에는 `client: read/write, server: read only` handshake 오류가 반복되고, CTP에는 서버 복구·재연결 기록이 있다. 첫 TC의 cleanup 실패가 뒤 TC의 같은 테이블 이름/준비문 사용에 영향을 줄 수 있다.

이번 기록에서 발화한 것은 새 네 필드 비교다. 기존 FIXED/DIRECT 검사를 assert로 바꾼 두 위치가 이번 job의 실패 지점이라는 증거는 없다. 또한 debug SQL job의 결과만으로 release의 동일 실패를 주장하지 않는다.

## 6. 앞선 검증에서 빠진 부분과 수정 방향

앞선 단위 harness는 직접 구성한 VARIABLE/NULL 전환과 물리 포맷 불일치를 검사했다. SQL 스모크는 interpolation을 포함했지만, **구체 타입 + 미확정 collation + host variable** 조합을 다루지 않았다. 그래서 검사 자체의 작동은 확인했어도 적용 범위가 실제 parser/executor 계약과 일치하는지 충분히 확인하지 못했다. "정상 동작 유지"는 그 작은 검증 범위를 넘어 일반화하면 안 되는 결론이었다.

수정 방향은 release 검사를 되살리는 것이 아니라, debug 검사의 전제를 실제 저장 이력에 맞추는 것이다.

- 빈 리스트의 합법적인 도메인 확정은 일반 갱신 경로에서도 허용해야 한다.
- `tuple_cnt==0` 여부를 아는 리스트 소유 지점에서 검사 여부를 결정하거나, 최초 확정과 기록 후 변경의 계약을 분리하는 방향이 적절하다. `qfile_set_layout` 자체는 현재 type_list만 받아 기록 이력을 알 수 없다.
- collation 미확정이라는 이유만으로 모든 재계산 검사를 무조건 생략하면, 실제 non-NULL 값이 이미 쓰인 뒤의 비호환 변경도 놓칠 수 있다.
- 반대로 단순한 빈 리스트 예외만으로 모든 지연 확정 사례가 해결된다고도 단정하지 않는다. 구체 타입의 미확정 컬럼에 NULL 행만 먼저 기록된 후 타입이 확정되는 경우에는 리스트가 비어 있지 않아도 기존 바이트가 안전할 수 있다. 이 경계는 다음 구현에서 따로 다뤄야 한다.
- 앞서 합의한 release 추가 작업 배제와 네 필드 비교 범위는 유지할 수 있다. 이번 분석에서는 수정하지 않았다.

## 자료와 한계

- 아티팩트 목록 **110개 전부 다운로드**, 총 110,848,435 bytes. 서버 shard 3의 초기 `.err` 한 파일은 첫 요청 timeout 후 재조회로 확보했다. [최종 manifest](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/download-manifest-final.json).
- [실패 45개 분류](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/failure-classification.md), [직접 연관 10개 문장](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/primary-trigger-cases.json), [선택한 SQL 시점](../../.git_ignored_dir/scratch/pr7866-ci155077-analysis/selected-sql-timeline.json).
- 코어 텍스트 분석은 저장소 분업 규칙에 따라 Sonnet이 맡고, 리드는 실행 로그·SQL·소스의 관계를 종합했다. 완전한 스택 수, 파일 수, assert 출력 수, 실패 TC 수는 서로 다른 지표다.
- 직전 SHA의 GitHub commit status 조회에서는 `test_sql` 기록을 찾지 못했다. 동일한 전체 suite의 직전 성공과 A/B 대조했다고 주장하지 않는다.
- 스택에는 런타임 지역변수·메모리·컬럼별 저장 이력이 없다. 기존 바이너리 코어를 gdb로 연 것도 아니며, 실행 재현 없이 얻을 수 있는 결론의 범위는 위와 같다.
- 엔진 파일 수정, 커밋, push, 댓글 게시, 테스트 재실행은 하지 않았다.

## 이후 사용자 요청에 따른 수정 완료

위 기록 분석 뒤 사용자가 코드 수정을 요청했다. [수정 및 검증 기록](pr7866-bound-layout-fix.md)의 `6ab2bc614`에서 debug의 컬럼별 사용 이력으로 검사 전제를 바꿨다. 최종 소스의 로컬 CTP SQL 17,459개와 원래 실패 45개 모두 통과했고 커밋·push·후속 답글을 완료했다. 위 "재현/수정하지 않음"은 최초 기록 분석 단계의 범위다.
