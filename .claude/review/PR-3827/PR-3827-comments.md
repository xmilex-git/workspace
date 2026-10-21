# 게시용 리뷰 코멘트 (CBRD-26678 TC PR)

## CUBRID/cubrid-testcases#3827 (head `d07fa316d6c2`)

- 리뷰 이벤트: REQUEST_CHANGES
- 같은 지적이 bagus-kim 의 인라인 코멘트(4334380243, `cbrd_26678.sql:32`)에 이미 있어 새 인라인 코멘트는 달지 않고, 그 스레드에 답글로 근거와 해결 방안을 붙인다.
- Greptile 2건은 작성자가 d07fa31 에서 반영하고 답글을 달았으므로 손대지 않는다.

### 답글 (in_reply_to 4334380243)

말씀하신 대로 develop 에서는 이 TC 의 인덱스가 전부 단일 스레드로 빌드되는 것으로 보입니다. CBRD-27235 (#7831) 이후 인덱스 빌드 병렬도는 `btsort_compute_parallel_degree` 가 `parallel_index_build_page_threshold` (hidden, 기본 2048) 로 판정하고, `test_mode=yes` 는 `prm_tune_parameters` 에서 `parallel_scan_page_threshold` / `parallel_hash_join_page_threshold` 만 낮춥니다. `parallel_sort_page_threshold` 는 이제 쿼리 정렬에만 쓰입니다.
develop optdebug 서버에 gdb 를 붙여 `test_mode=yes, parallelism=4` 로 확인해 보니 tb(469 페이지), pt 파티션(325 x 4)이 모두 `page_threshold=2048` 에서 0 으로 떨어졌고, 같은 조건에 `parallel_index_build_page_threshold=0` 만 더하면 degree 4 로 병렬 진입했습니다.

### 최상위 본문

병렬 인덱스 빌드 경로 진입 조건 관련해서는 위 bagus-kim 님 코멘트 스레드에 확인한 내용을 남겼습니다. 이 파라미터는 동적으로 바꿀 수 없어서 SQL TC 안에서는 낮출 방법이 없는 것으로 알고 있습니다.

확인 부탁드립니다
- 병렬 경로를 타게 하려면 몇 가지 방법이 있을 것 같습니다. 엔진에서 `test_mode=yes` 일 때 `parallel_index_build_page_threshold` 도 hash join 처럼 기본값이면 0 으로 낮추게 하는 방법(별도 엔진 이슈), 테이블을 2048 페이지(약 32MB, 파티션은 파티션마다) 이상으로 키우는 방법, 병렬 정확성 검증은 임계값을 바꿀 수 있는 shell TC 로 옮기고 이 TC 는 경로와 무관한 정확성 검증으로 설명을 고치는 방법입니다.
- 테이블을 키우는 경우 char(2048) 처럼 긴 문자열은 압축돼서 bk 는 89 페이지에 그쳤습니다. 255 바이트 미만 char 컬럼 여러 개로 행 폭을 늘리는 쪽이 나아 보입니다. 또 임계값 2048 에서는 degree 2 에 섹터가 32 개라 케이스 32 의 섹터 부족 fallback 은 SQL TC 로는 만들 수 없을 것 같습니다.
- PR 본문과 헤더의 진입 조건 설명(`parallel_sort_page_threshold`, `compute_parallel_degree`, `sort_check_parallelism`)도 함께 갱신이 필요해 보입니다.

## CUBRID/cubrid-testcases-private-ex#4515 (head `05363cccc140`)

- 리뷰 이벤트: REQUEST_CHANGES

### 인라인 `shell/_40_guava/cbrd_26678/cases/cbrd_26678.sh:62`

CBRD-27235 이후 `parallel_sort_page_threshold` 는 쿼리 정렬에만 쓰이고, 인덱스 빌드는 `parallel_index_build_page_threshold` (hidden, 기본 2048) 로 판정하는 것으로 알고 있습니다. 이 테이블은 653 페이지라 지금은 병렬 쪽도 단일 스레드로 빌드되고, 시나리오 3 이 직렬끼리 비교하게 되는 것 같습니다. develop optdebug 에서 아래처럼 바꾸면 degree 4 로 병렬 진입하는 것을 확인했습니다. 59-61행 주석과 헤더 21-25행 설명도 같이 바꾸는 것은 어떨까요?
```suggestion
change_db_parameter "parallel_index_build_page_threshold=0"
```

### 인라인 `shell/_40_guava/cbrd_26678/cases/cbrd_26678.sh:186`

직렬 쪽도 같은 파라미터로 맞춰야 할 것 같습니다. 181행 주석도 함께 부탁드립니다.
```suggestion
change_db_parameter "parallel_index_build_page_threshold=2147483647"
```

### 인라인 `shell_perf/_40_guava/cbrd_26678/cases/cbrd_26678.sh:19`

판정은 develop 에서도 맞게 동작하는 것으로 보입니다(`index_build_parallelism` 기본값 -1 이 `parallelism` 을 따르므로 1 이면 직렬). 다만 `SORT_INDEX_LEAF`, `compute_parallel_degree` 는 CBRD-27235 이후 인덱스 빌드 경로에 없는 이름이라, 6행과 함께 `btsort_compute_parallel_degree`, `index_build_parallelism` 기준으로 고쳐 두는 것은 어떨까요?

### 최상위 본문

shell_perf 는 2.7GB 힙이라 develop 에서도 병렬 경로를 타는 것을 확인했습니다. shell TC 는 인덱스 빌드 임계값 파라미터가 바뀌어서 두 설정 모두 직렬로 빌드되는 것으로 보여 인라인으로 남겼습니다. 확인 부탁드립니다.
