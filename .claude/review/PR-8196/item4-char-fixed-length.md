# PR 8196 항목 4 — CHAR 와 페이지 배치 (3번 세션)

대상: CUBRID/cubrid#8196 head `908bdc5af`, develop merge-base `c966fabc6`. 공유 worktree `~/dev/cubrid-worktree/pr8196-review` 를 읽기만 했고, 실행은 CI release tarball 두 개(head, merge-base)로 했습니다.

## TL;DR

"CHAR 가 고정 길이가 아니라서 빠졌다"는 전제는 반만 맞습니다. develop 은 CHAR 를 VARCHAR 와 같은 가변 영역에 저장하기 때문에(CBRD-26663/26956), CHAR 는 VARCHAR 와 같은 경로로 배치에 들어갑니다. `=`·`<>`·IN·SUBSTRING IN·OR·GROUP BY 키는 실제로 배치가 처리하고, VARCHAR 와 같은 -71% 를 냅니다. 배치에서 빠지는 CHAR 는 두 갈래입니다.

1. 공백 패딩(값을 선언 길이까지 공백으로 채우는 저장 방식) 때문에 저장 바이트가 255 이상이 되는 CHAR. 예: `CHAR(300)`, 또는 한글이 많은 utf8 `CHAR(100)`. 이 경우 페이지마다 배치를 시도했다가 실패하고 행 경로로 다시 처리합니다. 그래서 develop 보다 오히려 느려집니다(서버 명령어 수 +10~14%, 실행 시간 +13~23%).
2. CHAR 컬럼의 LIKE. 이 제외는 처음 LIKE 를 자체 매처로 구현했을 때 필요했던 것입니다. LIKE 리프가 엔진 판정 함수 `qstr_eval_like()` 로 바뀐 뒤에는 이유가 없어졌는데, 제외 조건만 남아 있습니다. 한 줄을 풀어 빌드한 수정본으로 검증했습니다. sql 17582건과 medium 975건이 실패 0, 코어 0 이었고, LIKE 정합 질의 64개의 결과가 develop 과 같았습니다. 명령어 수는 develop 대비 -60~-73% 였습니다. 다만 발견 1 의 거절 조건 (a) 와 함께 넣어야 합니다.

## 배경: develop 에서 CHAR 가 저장되는 형식

- `tp_Char` 의 `variable_p` 가 1입니다(`src/object/object_primitive.c:12678`). 이렇게 바뀐 것은 `83b29b02c` [CBRD-26663] 이고, `a9fca9002` [CBRD-26956] 이 일부를 되돌리면서도 "CHAR fixed-to-variable + compression" 은 남겼습니다.
- 디스크에 쓸 때 CHAR(N) 값은 N 글자까지 공백으로 채워진 뒤 VARCHAR 와 같은 형식으로 저장됩니다. 길이 접두가 1바이트이고, 255바이트 이상이면 `0xFF` 표지 뒤에 압축 길이와 원래 길이가 붙고 데이터는 LZ4 로 압축될 수 있습니다(`mr_writeval_char_internal`, `object_primitive.c:12119-12195`). 패딩이 공백이라 압축이 거의 항상 성공합니다. 1백만 행 시험 테이블에서 `CHAR(300)` 값 'ab1' 은 압축된 채 저장되어 있었습니다(아래 검증 참고: 페이지 수로 확인).
- 배치는 `heap_attrinfo_raw_locator()` 를 통해 VARCHAR·CHAR 를 가변 영역 컬럼으로만 받습니다. 고정 영역 CHAR 는 거절합니다(`src/storage/heap_file.c:10985-10991`). 즉 CHAR 가 가변 저장이기 때문에 배치에 들어올 수 있는 것이고, 고정 저장이었다면 별도 경로가 필요했을 것입니다.

## 실제로 배치가 처리하는 CHAR 모양 (head 에서 trace 로 확인)

| 모양 | head trace | 서버 명령어 수 develop → head (직렬, 1백만 행) |
|---|---|---|
| `c10 = 'ab1'` (`CHAR(10)`) | batch pages 12662 (row path 0) | 1.490G → 0.435G (-71%) |
| `c10 IN ('ab1','ab2')`, OR | batch, row path 0 | 측정 안 함 |
| `GROUP BY c10`, `GROUP BY c300` (원시 키 바이트 비교) | batch, row path 0 | 측정 안 함 |
| `c10 LIKE '%b1'` | `batch: no (the data filter is interpreted)` | 1.677G → 1.734G (+3.4%) |
| `c300 = 'ab1'` (`CHAR(300)`) | batch pages 3 (row path 335 / 338, last: a string the batch does not read from the record) | 2.830G → 3.102G (+9.6%) |

## 발견 사항

### Blocking

1. **패딩으로 255바이트를 넘는 CHAR 는 페이지마다 배치를 시도했다가 행 경로로 다시 돌아 develop 보다 느림** (`src/query/expr_batch.c:969`, `:1350`; 행 경로로 넘기는 곳 `src/query/scan_manager.c:8671`, `src/query/query_executor.c:12541`, `src/query/parallel/px_scan/px_scan_task.cpp:892`)
   - **무엇인가:** `eb_cell_str()` 는 길이 접두가 255 이상인 문자열(긴 형식이나 압축 형식)을 읽지 못하고 -1 을 돌려줍니다. 그러면 문자열 리프가 `eb_fallback()` 을 부르고, 그 청크와 페이지의 나머지를 행 경로가 처음부터 다시 처리합니다.
   - **문제:** CHAR(N) 은 N 글자까지 공백으로 채워 저장하므로, N ≥ 255 인 CHAR 는 NULL 이 아닌 모든 값이 255바이트 이상입니다. 그래서 거의 모든 페이지가 "가시성 판정 + 청크 수집 + 리프 실행"을 한 다음 버려지고 행 경로를 한 번 더 탑니다. 이렇게 되는 횟수를 세기만 하고(`expr_batch_plan_note_page()`, `expr_batch.c:4331`) 시도를 멈추는 장치는 없습니다. utf8 `CHAR(85~254)` 도 다바이트 글자가 많은 값이면 같은 상황이 됩니다. VARCHAR 도 실제 값이 255바이트를 넘으면 같은 일이 생기지만(`vk` 행 참고), CHAR 는 값과 상관없이 스키마만으로 항상 그렇게 된다는 점이 다릅니다.
   - **근거 (1백만 행, 서버 `instructions:u` 5회 평균 / 실행 시간 5회 중앙값):**

     | 질의 | develop | head | 변화 |
     |---|---|---|---|
     | 직렬 `c300 = 'ab1'` (CHAR(300)) | 2.830G / 0.388s | 3.102G / 0.464s | +9.6% / +19% |
     | 직렬 `v300 = 'ab1'` (VARCHAR(300), 같은 값) | 1.482G / 0.190s | 0.430G / 0.099s | -71% |
     | 직렬 `ck = '가나'` (utf8 CHAR(100), 절반 행이 280바이트) | 2.683G / 0.423s | 2.943G / 0.477s | +9.7% / +13% |
     | 직렬 `vk = '가나'` (VARCHAR(100), 절반 행이 270바이트) | 2.212G / 0.366s | 2.464G / 0.408s | +11.4% / +11% |
     | 병렬(4) `c300 = 'ab1'` | 2.742G / 0.100s | 3.051G / 0.121s | +11.3% / +20% |
     | 병렬(4) `ck = '가나'` | 2.526G / 0.107s | 2.869G / 0.132s | +13.6% / +23% |

     develop 은 두 번 측정했고 명령어 수가 네 자리까지 같았습니다(2.830289G / 2.830324G). 실행 시간은 다른 세션들과 호스트를 나눠 쓰는 상태라 잡음이 있습니다. 판단은 명령어 수로 합니다.
   - **고칠 방법 (작은 것부터):**
     - (a) 스키마로 결정되는 경우를 계획 시점에 거절: `eb_new_col_vec()` 에서 `loc.type == DB_TYPE_CHAR && loc.precision >= OR_MINIMUM_STRING_LENGTH_FOR_COMPRESSION` 이면 `eb_decline (b, "a CHAR column padded past the short string form")`. 한 줄이면 되고 `c300` 퇴행이 사라집니다. GROUP BY 키 경로(`heap_attrinfo_raw_key_locator()`)는 원시 바이트를 비교하므로 손댈 필요가 없습니다.
     - (b) 값에 따라 달라지는 경우(utf8 CHAR, 긴 VARCHAR): 계획이 이미 세고 있는 `pages_fallback` 이 일정 비율을 넘으면 그 스캔의 남은 구간은 행 경로로 바꿉니다. 이 부분은 항목 3(성능 규칙) 과 겹칩니다.
     - (c) 실제로 지원: `eb_cell_str()` 가 긴 형식을 읽게 합니다. 압축되지 않은 값(`compressed_size == 0`)은 헤더 뒤 데이터를 그대로 가리키고, 압축된 값은 계획별 버퍼에 LZ4 로 풀어서 비교합니다. 행 경로는 이미 값마다 압축을 풀고, 압축본을 `db_private_alloc` 으로 복사까지 합니다(`mr_readval_char_internal`, `object_primitive.c:12289-12312`). 그러니 이렇게 해도 행 경로보다 느려지지는 않을 것으로 보입니다(측정 안 함).
   - **그냥 두면:** `CHAR(255+)` 컬럼이나 한글이 많은 CHAR 컬럼에 필터를 거는 스캔이 이 PR 이후 develop 보다 10~20% 느려집니다. PR 이 성능 개선 PR 이라 이런 퇴행 경로는 머지 전에 막는 것이 맞다고 봅니다. 최소한 (a) 와 (b) 는 필요합니다.

### Non-blocking

2. **CHAR LIKE 제외는 이유가 사라진 채 남은 조건** (`src/query/expr_compile.c:3971`)
   - **무엇인가:** `expr_pred_term_string_info()` 의 `(TP_DOMAIN_TYPE (col->domain) != DB_TYPE_CHAR || like)` 조건 때문에 CHAR 컬럼의 LIKE 는 원시 리프(배치가 직접 판정하는 항)가 되지 못합니다.
   - **왜 생겼나:** 이 조건은 `c7f101577` (CHAR 를 리프에 추가한 커밋)에서 들어왔습니다. 그때 LIKE 리프는 자체 매처 `eb_like_match()` 였는데, 마지막 리터럴을 문자열 끝에 고정해서 비교했습니다(`git show c7f101577:src/query/expr_batch.c` 1018-1060). 그래서 패딩된 `'ab1       ' LIKE '%b1'` 을 FALSE 로 판정했고, 엔진은 TRUE 로 판정합니다(엔진 LIKE 는 문자열 끝 공백을 허용). 그 뒤 `6bc00f39f` 에서 리프가 `qstr_like_match()` → `qstr_eval_like()` 로 바뀌었는데(`expr_batch.c:1358-1368`), CHAR 제외 조건은 그대로 남았습니다.
   - **지금은 같은 판정이 나옴:** 행 경로는 `eval_pred_like6()` (`src/query/query_evaluator.c:3030-3074`) → `db_string_like()` (`src/query/string_opfunc.c:4499-4627`) → `qstr_eval_like (원본 바이트, 크기, 패턴, NULL, codeset, 공통 collation)` 순서로 판정합니다. 배치 리프는 `qstr_eval_like (레코드 바이트, 크기, 패턴, NULL, codeset, 컬럼 collation)` 을 부릅니다. 두 쪽의 입력이 같습니다.
     - 원본 바이트: 행 경로의 `mr_readval_char_internal()` 은 압축되지 않은 값일 때 레코드 바이트와 저장 크기를 그대로 DB_VALUE 에 담습니다(`object_primitive.c:12319-12327`). `eb_cell_str()` 가 주는 바이트·길이와 같습니다.
     - collation: 배치는 상수의 collation 이 컬럼과 같을 때만 리프를 만듭니다(`expr_batch.c:1019`, `:2979`).
     - escape: ESCAPE 가 없으면 행 경로도 NULL 을 넘깁니다. `_` 나 `\` 가 든 패턴은 배치가 받지 않습니다.
     - NULL 은 양쪽 모두 UNKNOWN 입니다.
     - head 에서 `c10 LIKE '%b1'` 은 3000/30000 행, 1백만 행에서는 100000 행으로 develop 과 같았습니다. 이것은 행 경로 결과이고, 배치 판정 결과는 아닙니다.
   - **영향:** 이 제외 하나로 배치를 전혀 못 쓰는 경우가 생깁니다. 필터가 해석기 경로(컴파일되지 않은 필터)이면 모든 항이 원시 리프여야 배치가 켜집니다(`eb_build_filter_interpreted()`, `expr_batch.c:1445-1490`; `expr_pred_raw_leaves()` 는 `expr_compile.c:4027-4030` 에서 -1 을 돌려줌). 그래서 CHAR LIKE 한 항이 함께 있는 VARCHAR `=` 리프까지 막습니다.

     | 직렬, 1백만 행 | develop | head |
     |---|---|---|
     | `v10 = 'ab1' AND c10 LIKE '%b1'` | 1.741G | 1.763G (+1.2%, batch: no) |
     | `v10 = 'ab1' AND v10 LIKE '%b1'` | 1.503G | 0.554G (-63%) |
     | `id > 0 AND c10 LIKE '%b1'` (컴파일 필터, LIKE 는 행 단위 항) | 2.126G | 1.553G (-27%) |
     | `id > 0 AND v10 LIKE '%b1'` | 2.125G | 0.732G (-66%) |
     | `c10 LIKE '%b1'` 단독 | 1.677G | 1.734G (+3.4%, batch: no) |
     | `v10 LIKE '%b1'` 단독 | 1.676G | 0.669G (-60%) |

   - **고칠 방법:** 조건을 `TP_DOMAIN_TYPE (col->domain) != DB_TYPE_VARCHAR && TP_DOMAIN_TYPE (col->domain) != DB_TYPE_CHAR` 로 줄이고(한 줄, 아래 "수정본 검증"), PR 본문의 "거절하는 모양" 목록에서 "CHAR 컬럼의 LIKE" 를 지웁니다. 이 수정을 단독으로 넣으면 안 되고 발견 1의 (a) 와 함께 넣어야 합니다. 그렇지 않으면 `CHAR(300) LIKE` 처럼 지금까지 배치 계획을 아예 만들지 않던 질의가 페이지마다 배치를 시도했다가 되돌아가는 경로로 들어갑니다. 측정 결과 명령어 수가 수정 전 head 대비 +4.3%, develop 대비 +6.2% 였습니다.
   - **그냥 두면:** 결과가 틀리지는 않습니다. CHAR 컬럼에 LIKE 를 쓰는 필터가 배치 효과를 받지 못하고, AND 로 함께 묶인 다른 문자열 리프까지 효과를 잃습니다.

   - **수정본 검증 (2026-10-21, 사용자 승인 후 실행):**
     - 수정: PR head `908bdc5af` 위에 위 한 줄만 바꿨습니다. 바꾼 곳은 내 worktree `~/dev/cubrid-worktree/pr8196-item4` 이고 커밋하지 않았습니다. diff 는 `scratch/pr8196-item4/char-like.patch` 입니다.
     - 빌드: Sonnet Workflow 워커가 새로 빌드했습니다(`wf_79584b1c-005`).
       - optdebug: `~/optdebug/CUBRID-pr8196-item4`, libcubrid.so sha256 `567512b122b9…`
       - release: `~/release/CUBRID-pr8196-item4`, libcubrid.so sha256 `f721354169e1…`
       - 두 빌드 모두 EXIT=0 이고, `expr_compile.c` 가 sa 와 server 대상에서 컴파일된 것을 로그에서 확인했습니다.
     - CTP (optdebug): `PR=8196 BUILD=~/optdebug/CUBRID-pr8196-item4 just ctp sql` 로 sql 전체와 medium 전체를 돌렸습니다. testcases 는 `tc/pr-8196` (`20f030b6fed9`), 파라미터는 `data_buffer_size=512M, parallelism=4` 로 고정했습니다.
       - sql: run `sql-20261021T103106Z-1792801` (16 shards), 17582건 중 실패 0, 코어 0 (`RESULT: PASSED`)
       - medium: run `medium-20261021T103106Z-1792800`, 975건 중 실패 0, 코어 0
       - 비교 기준은 같은 head 의 CI run 39374265629 입니다. sql·medium 모두 pass 이고 failed.list 가 비어 있습니다.
       - console 의 RESULT 줄과 provenance 는 직접 확인했습니다.
     - 정합 smoke (release, 직접 실행): `scratch/pr8196-item4/smoke/` 의 질의 64개입니다.
       - 대상 테이블: NULL 이 섞인 `CHAR(5)`·utf8 `CHAR(6)`·`VARCHAR(5)` 5만 행 테이블 `t3`, 그리고 `t2`
       - 다룬 경우: 패턴 `'ab'`, `'%ab '`, `'ab   '`, `''`, `'%'`, `'% %'`, `'a%b'`; NOT LIKE; `NOT (…)`; AND/OR 결합; CHAR·VARCHAR 로 캐스트한 패턴; `_`·`\`·ESCAPE 패턴; 다바이트; `CHAR(300)`
       - 각 질의를 직렬과 병렬로 돌렸습니다.
       - develop, 수정 전 head, 수정본의 출력이 모두 같았습니다(`like.{base,head,cand}.out`).
       - trace: 수정본에서는 `c10 LIKE`, `v10 = … AND c10 LIKE`, `t3.c5 LIKE '%ab'`, `t3.ck LIKE '%나'` 가 `batch pages N (row path: 0)` 입니다. 수정 전 head 에서는 모두 `batch: no` 였습니다.
     - 비용 (1백만 행 직렬, 서버 `instructions:u` 질의당):

       | 질의 | develop | 수정 전 head | 수정본 | 수정본 vs develop |
       |---|---|---|---|---|
       | `c10 LIKE '%b1'` | 1.682G | 1.736G | 0.675G | -60% |
       | `v10 = 'ab1' AND c10 LIKE '%b1'` | 1.742G | 1.781G | 0.470G | -73% |
       | `id > 0 AND c10 LIKE '%b1'` | 2.124G | 1.568G | 0.686G | -68% |
       | `c300 LIKE '%b1'` (발견 1 경로) | 2.931G | 2.985G | 3.113G | +6.2% |
       | `c300 = 'ab1'` (참고) | 2.834G | 3.100G | 3.097G | +9.3% |

       - `CHAR(10)` 의 효과는 같은 모양의 VARCHAR 질의(`v10 LIKE`: 0.670G)와 거의 같았습니다.
       - `c300 LIKE` 는 한 번 측정에서 실행 시간이 두 배로 나왔습니다. 그래서 서버 CPU tick 을 다시 쟀는데, 5회 기준 수정본 229, 수정 전 head 246 으로 비슷했습니다. 시간 차이는 같은 호스트의 다른 세션 부하에서 온 잡음으로 판단합니다.

3. **CHAR 가 들어온 뒤 갱신되지 않은 주석** (동작에는 영향 없음)
   - `src/query/expr_compile.c:3910-3912`: "A term on a VARCHAR column … over a binary collation" → 지금은 CHAR 도 받고, LIKE 는 엔진 판정을 씁니다.
   - `src/query/expr_compile.h:366`: "a VARCHAR column LIKE".
   - `src/query/expr_batch.c:94`: `EB_STR /* VARCHAR: pointed only … */` → CHAR 도 해당.
   - `src/query/expr_batch.c:1017-1018`: "a LIKE: a binary one on both sides, where '%' matches bytes" → 자체 매처 시절의 설명입니다.
   - `src/storage/heap_file.c:10953-10954`: 받는 타입 목록에 VARCHAR·CHAR 가 빠져 있습니다.

### Questions (작성자에게)

- Q1. `6bc00f39f` 에서 LIKE 리프를 `qstr_eval_like()` 로 바꾼 뒤에도 CHAR LIKE 를 제외한 다른 이유가 있나요? 없다면 발견 2 대로 풀어도 될 것 같습니다.
- Q2. PR 본문의 정합 시험 중 "255바이트 초과" 는 결과가 맞는지만 본 것으로 보입니다. 255바이트 이상 값이 대부분인 컬럼(특히 CHAR(255+))에서 페이지마다 배치 시도 후 행 경로로 다시 도는 비용도 의도한 것인가요? 계획 단계 거절이나 시도 중단 장치를 넣을 계획이 있나요?

## CHAR 와 관계없는 제외 (참고)

- 해시 조인 런타임 필터는 SHORT/INTEGER/BIGINT/DATE 키만 받습니다(`hjoin_rtf_type_ok()`, `query_hash_join.c`). 문자열 키는 VARCHAR 도 대상이 아니므로 CHAR 만의 문제는 아닙니다.
- 문자열 리프는 `=`·`<>`·IN·LIKE 만 받습니다. 범위 비교(`<`, `>=`, `LIKE 'ab%'` 를 옵티마이저가 범위로 바꾼 것)는 VARCHAR 도 리프가 아닙니다. 이 범위 비교가 배치에 들어가는지는 trace 로 확인하지 않았습니다.

## 실행한 검증

- 빌드: CI release tarball 두 개.
  - head `908bdc5af…/release` (`http://192.168.1.48:30080/builds/pr/908bdc5af67a752fd168b71cdf2c6f140520861d/release/CUBRID.tar.gz`)
  - merge-base `c966fabc6…/release`
  - 각각 `.git_ignored_dir/scratch/pr8196-item4/{head,base}/CUBRID` 에 풀었습니다. optdebug 는 쓰지 않았습니다.
- 서버: `just port-claim pr8196i4` → 포트 1712. 세션 conf 는 campaign conf(`data_buffer_size=512M`, `parallelism=24`)에서 `stored_procedure=no` 만 바꿨습니다. DB 는 `i4db` (en_US.utf8) 하나이고, `cubrid-server-control` 로 head ↔ base 를 번갈아 띄웠습니다. 매번 `/proc/<pid>/exe` 로 실행 중인 바이너리를 확인했습니다. 끝난 뒤 서버와 마스터를 정지하고 `just port-release pr8196i4` 로 포트를 반납했습니다. 코어는 생기지 않았습니다.
- 데이터:
  - `t` 3만 행
  - `t2` 1백만 행: `c10 CHAR(10)`, `v10 VARCHAR(10)`, `c300 CHAR(300)`, `v300 VARCHAR(300)`, `ck CHAR(100)`, `vk VARCHAR(100)`. 값은 `'ab'||mod(id,10)` 입니다. `ck`/`vk` 는 짝수 행이 '가나', 홀수 행이 '가'×90 입니다.
- 정합: `scratch/pr8196-item4/gen-corr.sh` 로 질의 53개를 만들었습니다. 술어 23종을 직렬(`NO_PARALLEL_SCAN`)·병렬로 각각 돌리고, GROUP BY 를 더했습니다. 술어는 CHAR/VARCHAR 캐스트 혼합, 후행 공백 상수, 혼합 IN 목록, LIKE/NOT LIKE, SUBSTRING IN, CHAR(300), utf8 CHAR, AND/OR 입니다. head 와 develop 출력에서 시간만 지우고 diff 한 결과 **같았습니다**(`corr-head.out` / `corr-base.out`). `SUM(INT)` 오버플로 오류는 develop 도 똑같이 냅니다.
- trace: `;plan detail` + `set trace on` 으로 batch pages / row path / 거절 이유를 읽었습니다(`q2.out`, `q3.out`, `q4.out`). 직렬 스캔에서만 표시됩니다.
- 비용: `bench.sh`, `bench-par.sh`, `bench3.sh`. 질의마다 예열 1회 후 5회를 돌려 csql 시간의 중앙값을 냈고, 같은 5회 동안 `perf stat -e instructions:u -p <cub_server>` 를 붙여 질의당 평균을 냈습니다. 결과 파일은 `bench-{base,base2,head}.txt`, `bench-{base,head}-par.txt`, `bench3-{base,head}.txt` 입니다.

## 확인하지 못한 것

- 발견 2 의 수정본으로 shell·ha_shell CTP 는 돌리지 않았습니다. 돌린 것은 sql·medium 과 smoke 입니다.
- 발견 1 의 고칠 방법 (a)(b)(c) 는 시제품을 만들지 않았습니다. (c) 가 행 경로보다 빠르다는 것도 추정입니다. 발견 2 수정본에 (a) 를 더한 조합도 빌드하지 않았습니다.
- utf8_bin 이외의 collation(대소문자 무시 collation 등)과 euc-kr/iso 코드셋 CHAR 는 시험하지 않았습니다. collation 쪽은 항목 5 범위입니다.
- 예전 형식의 고정 길이 CHAR 가 남아 있는 DB(마이그레이션)는 시험하지 않았습니다. 코드상 `heap_attrinfo_raw_locator()` 가 거절하므로 행 경로로 갑니다.
- 병렬 경로의 batch/row path 횟수는 trace 에 나오지 않습니다. 병렬은 명령어 수로만 판단했습니다.
- 남은 산출물: scratch 의 CI 설치본 두 개와 시험 DB(약 2.2G), 수정본 설치 `~/optdebug/CUBRID-pr8196-item4`·`~/release/CUBRID-pr8196-item4`, worktree `~/dev/cubrid-worktree/pr8196-item4`(커밋 안 한 한 줄 수정), CTP run 두 개(`~/ctp-run-out/workspace/{sql-20261021T103106Z-1792801,medium-20261021T103106Z-1792800}`). 후속 확인이 끝나면 지웁니다.
