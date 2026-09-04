# CBRD-27365 #7866 리뷰 반영 (#203) — SCRATCH 본문 4B 정렬·제자리 디코드 + 후속 2건

- 티켓: xmilex-git/workspace #203 (지도 #179). upstream PR CUBRID/cubrid#7866 리뷰 P1(`qfile_tuple_layout.h:254` ALLOC-01)·P2(`list_file.c:4077` ALLOC-06).
- 커밋: `d8e2cd220`(D-201-1 SCRATCH 4B 정렬·제자리 디코드, `QFILE_SCRATCH_*` 삭제) + `41bb16b15`(D-203-1/2 후속). 브랜치 `CBRD-27365-pr3`.
- 검증 빌드: `~/{release,optdebug}/CUBRID-cbrd27365-pr3-gate`. A/B 기준 빌드: develop `~/release/CUBRID-pr7866-base`(8e355ff59), 수정 전 PR `~/release/CUBRID-pr7866-head`(5bde57c54).

## 1. 리뷰 P1 재측정 (리뷰어 프로브: 200k 행 JSON 400B 분석함수 물질화, release, 7회)

| 빌드 | median(s) | sd | Δ vs develop |
|---|---|---|---|
| develop | 2.291 | 0.117 | — |
| PR 수정 전 | 2.557 | 0.100 | +11.6% |
| PR d8e2cd220 | 2.063 | 0.031 | **−10.0%** |

결과값 21회 동일. perf stat(1회): 명령어 4.16B / 4.87B / 4.20B, 사이클 1.87B / 2.06B / 1.70B. P2 는 코드 삭제로 소멸.

## 2. d8e2cd220 이 만든 회귀 2건과 수정 (41bb16b15)

### 2.1 CTP 전수 코어 2건 → D-203-1
- 증상: `qfile_col_read_body` SCRATCH 분기의 4B 정렬 assert(`qfile_tuple_layout.h:293`). percentile_cont 서브쿼리(`_27_banana_qa/issue_11088_percentile_cont/.../p_cont_subquery.sql` 70행), group_concat DISTINCT + 파생 테이블(`_17_sql_extension2/.../group_concat_001.sql` 52·53행). 최소 재현 `.git_ignored_dir/scratch/i203/cores/minimal-*.sql`.
- 원인: DIRECT 분기 조건이 `c->var_access == DIRECT && dom->type->has_index_readval()` 이라, 컴파일러가 미확정으로 남긴 디코딩 도메인(`DB_TYPE_NULL`/`VARIABLE`, readval 이 no-op)이 오면 DIRECT(비정렬 문자열) 컬럼이 SCRATCH 분기로 떨어져 assert. 그 슬롯은 스캔 val_list 가 리스트 전 컬럼(숨은 정렬키 포함)을 매핑한 것 중 아무 식도 참조하지 않는 것 — develop 도 같은 읽기를 하며(값 NULL 로 남음) 결과에는 쓰이지 않는다(develop 출력 = CTP 답안 4행/5그룹).
- 수정: 저장 분류로 먼저 분기, `index_readval` 없는 도메인은 구 포맷·develop 과 같이 `data_readval` 적용(assert 는 NULL/VARIABLE 한정).

### 2.2 SET 컬럼 GROUP BY 3.15배 → D-203-2
- 발견: perf-ab 세션 프로브(200k 행, JSON 400B + SET(INT) 70원소, 5문장) develop 3.56s vs PR 5.08s. 문장별 perf stat 귀속(release, 명령어:u):

| 문장 | develop | PR d8e2cd220 | 비율 |
|---|---|---|---|
| S1 JSON 분석함수 | 7.63B | 7.49B | 0.98 |
| S2 JSON 정렬 | 3.24B | 3.24B | 1.00 |
| S3 SET 정렬키 | 0.70B | 0.70B | 1.00 |
| S4 JSON UNION ALL | 7.56B | 8.46B | 1.12(A 편차) |
| S5 GROUP BY, JSON+SET, NO_MERGE 뷰 | 9.80B | 30.84B | **3.15** |
| S6 대조군 | 0.44B | 0.44B | 1.00 |

- 원인: SCRATCH 읽기의 `copy=true` 강제(PR-2b D-199-2 일시 버퍼 잔재). `mr_data_readval_set(copy=true)` = `or_get_set`→`col_add`(원소당 선형 중복검사) 전량 구성; develop 은 copy=false → `set_make_reference` 참조. perf report: PR S5 자기시간 `or_get_set` 24.7%(`col_add` 12.9%, `col_find` 5.1%), develop 은 `or_disk_set_size`+`set_make_reference` 20.6%.
- 수정: 호출자 copy 플래그 전달. 재측정(41bb16b15): S1 0.98, S3 1.00, **S5 0.98**, 결과 동일.

## 3. 검증 (41bb16b15)
- 증분 빌드 release/optdebug OK, smoke ×2 PASS/PASS(cbrd27365s 재생성), 최소 재현 2건 + CTP 케이스 파일 2개 크래시 0(assert 빌드), 격리 CTP 8디렉터리 707/707(d8e2cd220 기준), CTP 전수: 1차(d8e2cd220) 코어 2 → 중단, 2차(41bb16b15) 결과는 아래 갱신.
- 인시던트: CTP 1차 두 코어가 같은 초에 나서 외부 신호를 의심했으나 gdb `si_code=SI_TKILL`(자기 abort) 로 내부 assert 확정. 공유 설치본 conf 포트를 워커 둘이 동시에 편집(i203base/i203v2) — 서로 프로세스는 건드리지 않음; 이후 워커는 설치본당 하나만.

## 4. 결정
- D-203-1, D-203-2: ADR 0016 각주. 미참조 val_list 슬롯 fetch(도메인 미확정, NULL 읽기)는 develop 동작 유지 — 맵 Out of scope(최적화 제안 후보).
- 신규 TC 는 TC PR 이 아닌 JIRA test.md 로 QA 요청(D-201-11). test.md 검증 포인트에 위 두 형태 추가.
