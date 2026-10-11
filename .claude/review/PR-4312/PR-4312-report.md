# PR #4312 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases-private-ex#4312](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4312)
**제목:** [CBRD-27365] Revise for Reduce temp file size by changing the tuple format inside temp files
**작성자:** ssihil
**HEAD SHA:** `06dbca9cf` (develop merge-base `9e9f773d1`)
**JIRA:** CBRD-27365 (Improve Function/Performance, Resolved; 엔진 변경 CUBRID/cubrid#7866 `453da49c8`) / 연관: CBRD-25717 (원 TC), CBRD-27557 (disk-only split 크래시)
**TC PR:** 이 PR 자체가 TC 단독 PR (엔진 PR 없음). SQL 쪽 짝은 cubrid-testcases#3642 (Approve 완료)
**리뷰 일시:** 2026-10-06
**리뷰 결정:** #4312 Comment (review 5424709369) -> 작성자가 ffc9a3c15 에서 disk-only 블록을 주석 처리한 뒤 Approve (review 5425207224, 정적 분석 근거, 미실행) (CI 크래시 사실 + 본문 기재 요청, 인라인 질문 1건: `set_membuf` 재시작 확인)

> **TL;DR** (작성자 확인 필요): 두 수정은 gha-ci (optdebug) 에서 통과했다 (membuf-only 1-2, parallel_degree 5/5). 그러나 `membuf_config` 는 머지 후에도 CI 에서 disk-only 크래시 (CBRD-27557) 로 3-6 NOK + 코어 2개가 남고, 크래시 뒤 `set_membuf` 재시작이 적용되지 않아 membuf+disk 가 0 페이지 서버에서 한 번 더 죽는다.

## Summary

- **변경 요약**: `membuf_config` 의 `t_mb_small` 을 500 -> 8000 행으로 늘려 병렬 하한 (2 페이지) 위로 올림, `parallel_degree` 2번을 `pmax` 절대값 단정에서 `PARALLEL(1000)` == `PARALLEL(pmax)` 동치 비교로 바꿈
- **주요 이슈**: 없음
- **확인 필요 사항**: CI 크래시를 본문에 기재, `set_membuf` 재시작 후 파라미터 확인

---

## Findings

### Questions for the author
- PR 본문 검증은 release 기준 `membuf_config` 8/8 OK 다. gha-ci 의 shell 은 optdebug 라서 disk-only (`temp_file_memory_size_in_pages=0`) 에서 `split_task::execute` (병렬 해시 조인 분할 작업) 의 `assert (VFID_ISNULL (...temp_vfid))` 가 abort 하고 3-6 이 NOK, 코어 2개가 남는다 (CBRD-27557, run 37421351718). 머지 후에도 CI 에서 크래시한다는 점을 본문에 남길지.
- `cbrd_25717_membuf_config.sh:137` (`set_membuf 0`) — `set_membuf` 는 stop -> 파라미터 변경 -> start 만 하고 재기동/반영을 확인하지 않는다. disk-only 크래시 뒤 `set_membuf 20` 이 적용되지 않아 membuf+disk 가 0 페이지 서버에서 같은 assert 로 다시 죽는다 -> 5-6 은 membuf+disk 를 검사하지 못한다. 근거: 2026-10-04 gdb 로 본 같은 케이스 코어 2개가 모두 `temp_file_memory_size_in_pages=0` 이고, serial 질의는 `no_parallel_hash_join` 이라 split 을 타지 않는다. 기존 코드 (이 PR 미변경) 지만 CI 코어 2개 중 하나의 원인이라 질문으로 남긴다.

## JIRA -> TC PR

CBRD-27365 Specification Changes: "실행기가 리스트 페이지 수로 내리는 결정 (병렬 정렬/해시 조인 워커 수 ...) 이 페이지 수 감소로 바뀐다 ... 결과 집합은 동일하다."

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 워커 수 결정 변경 (500 행 = 1 페이지 -> 직렬) | `t_mb_small` 8000 행 (약 6 페이지, 20 페이지 버퍼 안) | 충족 |
| 결과 집합 동일 | membuf-only parallel/serial 모두 8000 | 충족 |

`parallel_degree` 2번은 CBRD-27365 와 무관한 환경 의존 (CI 컨테이너 CPU 할당 8 개) 수정이고, PR 본문이 원인이 다름을 밝히고 있다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| membuf-only 병렬 발동 (check 1-2) | optdebug 실행 `workers=6 parallel_count=8000 serial_count=8000` | 통과 |
| 상한 clamp 동치 (parallel_degree 2) | optdebug 실행 `PARALLEL(1000) workers=25 / PARALLEL(32) workers=25`, rows 동일 | 통과 |
| parallel_degree 나머지 1,3-5 | 변경 없음, 실행 OK | 통과 |
| membuf_config 3-6 (disk-only, membuf+disk) | gha-ci optdebug 에서 CBRD-27557 크래시로 NOK + 코어 2개, develop 과 동일 | 미해결 (엔진) |

TC 파일 검토: 헤더/케이스 주석의 엔진 설명은 코드와 맞다. `compute_parallel_degree` (`px_parallel.cpp`) 는 `page_threshold = MAX (page_threshold, 2)` 미만 페이지면 0 을 반환하고, 힌트 상한 32 는 `scanner_support.c` 에서 자른다. 2번 동치 비교는 인식 코어가 32 이하인 환경에서 clamp 누락을 직접 구분하지 못하지만, clamp 가 빠지면 debug 빌드는 `compute_parallel_degree` 의 `hint_degree <= PRM_MAX_PARALLELISM` assert 로 abort 하므로 `workers` 가 비어 NOK 가 된다. 새 변수 (`w_huge`, `w_cap`, `r_huge`, `r_cap`) 는 `init.sh` 전역과 겹치지 않고, 2번은 여전히 verdict 한 줄이다.

## Runtime Verification

- gha-ci `/run shell` on CUBRID/cubrid#8103 (develop `07aec2c5c` + 빈 커밋 `0587d1bbe`, debug=optdebug, TC `tc/pr-8103` `f2c5574ba` = #4312 트리와 동일): run 37421351718 verdict `fail`, shell 3291 건 중 실패 1 (`cbrd_25717_membuf_config`, shard 39). `membuf_config` 1-2 OK (`workers=6 parallel_count=8000 serial_count=8000`), 3-6 NOK (`workers=none ... none`), 7-8 OK, 코어 2개 (`split_task::execute` `__assert_fail`, `px_hash_join_task_manager.cpp:256`). `parallel_degree` 5/5 OK (shard 00). 그 밖의 shell 은 이번 실행에서 flaky 포함 전부 통과.
- gha-ci develop (run 37407986024, optdebug `1d1981943`): `membuf_config` 1,3-6 NOK + 코어 2개, `parallel_degree` 2 NOK (`actual='8' expected='32'`, `cores=192`).
- 로컬 `just ctp shell` (develop `07aec2c5c` optdebug tarball, `TC_REF=refs/pull/4312/head`, 컨테이너 nproc 32): CI 와 같은 패턴 (`membuf_config` 1-2 OK, 3-6 NOK, 코어 4개 = 2회 시도 x 2, `parallel_degree` 5/5, clamp 25 vs 25). 증거 `.git_ignored_dir/scratch/pr4312/evidence/`, 코어와 run dir 삭제.
- 작성자 첨부: release 16 코어, `membuf_config` 8/8, `parallel_degree` 5/5.
