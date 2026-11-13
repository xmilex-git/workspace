# PR #8364 r3 게시 코멘트 (2026-11-06 게시 완료)

## 엔진 PR CUBRID/cubrid#8364 -- REQUEST_CHANGES (review 5794917472, commit f65d0c0fa)

### top-level

r1 의 debug assert 는 `b05e88633` 에서 `agg_optimized` 를 XASL 생성 단계에서 내리도록 바뀌어 해소된 것을 확인했습니다(optdebug CI sql 통과).

다만 그 방식이 이 블록에서 집계 빠른 길과 병렬 스캔을 꺼서, #8196 이전에도 NULL 이던 형태를 고치는 대가로 develop 의 최적화를 잃습니다. 인라인 두 곳 확인 부탁드립니다. 그렇게 바뀌면 TC #3985 의 Case 6, 8 답안도 다시 맞춰야 할 것 같습니다.

shell 의 `locks_count` NOK 는 `sleep` 에 맞춘 `lockdb` 잠금 수 검사라 이 변경과 무관해 보여서 `/run rerun 42006019072` 부탁드립니다.

### src/parser/xasl_generation.c:21062

이 블록은 이제 WHERE 없는 MIN/MAX 와 키 범위 COUNT(*) 를 인덱스·통계로 끝내지 않고 소스 행을 모두 돕니다. release 에서 `g` 에 인덱스가 있는 100만 행 `big` 으로 `insert into tt (id) select max(s.g) + 1 from big s on duplicate key update c = s.c` 를 재 보면 develop 은 csql 기동과 같은 1.31G instructions, 이 PR 은 4.0G(기동을 빼면 약 2.75G)였습니다. 그렇게 얻은 `c` 도 MAX 행의 'v1000000' 이 아니라 스캔 마지막 행의 'v999739' 였습니다.

이 형태는 #8196 이전에도 NULL 이라 이번 회귀 범위 밖이니, 빠른 길(여기 `agg_optimized` 해제, `qexec_intprt_fnc ()` count-only 조건의 `!XASL_OUTPUT_READS_SCAN`, debug assert)은 develop 대로 두고 값이 필요하면 별도 이슈로 다루는 건 어떨까요?

### src/query/parallel/px_scan/px_scan_checker.cpp:969

병렬 `gather: buildvalue` 의 NULL 도 #8196 이전부터였는데, 여기서 병렬을 끄면 큰 소스가 직렬로 돕니다(Case 6 trace 에 parallel workers 줄이 없습니다). 숨은 컬럼 값을 위해 병렬을 끄기보다 develop 대로 병렬로 두는 건 어떨까요?

페이지 배치가 이 블록을 받지 않는 것은 #8196 이전 직렬로 돌아가는 것이라 괜찮아 보입니다.

### src/query/query_executor.c:810

NIT: `qexec_keep_last_row ()` 등 세 함수는 `qexec_end_buildvalueblock_iterations ()` 앞에 정의되어 있어서 선언도 그 앞으로 옮기면 정의 순서와 맞을 것 같습니다. `xasl_generation.c` 의 `pt_buildvalue_output_reads_scan ()` 선언도 `pt_to_buildlist_proc ()` 와 `pt_to_buildvalue_proc ()` 선언 사이로 옮기면 좋겠습니다.

### 답글: 스레드 4464626986 (r1 Blocking) -> 4488354996

`b05e88633` 에서 생성 단계로 옮긴 것 확인했습니다. optdebug CI 에서 Case 8 도 통과합니다.

## TC CUBRID/cubrid-testcases#3985 -- COMMENT (review 5794918400, commit 37a909eac)

r2 에서 말씀드린 머리 주석 `;` 은 고쳐졌고, 본문의 debug 통과도 head CI(optdebug sql) 와 맞는 것 확인했습니다.

엔진 PR 에 집계 빠른 길과 병렬 스캔은 develop 대로 두자는 의견을 남겼습니다. 그렇게 바뀌면 Case 6 과 Case 8 의 답안을 다시 맞춰야 할 것 같아서, 엔진 쪽이 정해진 뒤 다시 보겠습니다.

## TC CUBRID/cubrid-testcases-private-ex#4695 -- 리뷰 없음 (r1 Approve 유지, 이후 develop merge만)
