# CBRD-27365 신규 TC 재료 (#192)

test.md 첨부용 재료. 각 `.sql` 은 csql `-i` 로 단독 실행 가능하며 CTP sql 케이스 형식(문장마다 `;`, 마지막에 DROP)을 따른다.
`.answer.develop` 은 develop 참조 빌드(c67e642) 출력, `.answer.pr2b-fix` 는 PR-2b 수정 빌드(`de9018bf2`) 출력이며 둘의 diff 가 곧 정합성 판정이다(tc08 (6)(7) 은 develop 이 abort 하므로 develop 쪽은 그 지점에서 끊김).

| 파일 | 주제 | 겨냥하는 설계 결정 |
|---|---|---|
| tc01_null_mix.sql | NULL 혼합 | has-null 비트·조건부 비트맵·첫 NULL 뒤 걷기 시작(D-199-7) |
| tc02_fixed_var_mix.sql | 고정/가변 혼합 + 127/128/129B 경계 | 정렬 상수 4·1B/4B 가변 헤더·NUMERIC/CHAR/BIT 가변 취급 |
| tc03_overflow.sql | 오버플로 튜플 | 페이지 초과 튜플의 len/비트맵/4B 헤더 |
| tc04_connect_by.sql | CONNECT BY | bf2df 경계 밖 읽기(D-191-1)·다중 루트 -495·ISLEAF/ISCYCLE in-place |
| tc05_hash_join.sql | 해시 조인 키 | 해시키 in-place·파티션 raw 복사·외부조인 NULL |
| tc06_analytic.sql | 분석 함수 정렬키 | 정렬 미니튜플·값 리스트 역방향(backward C)·PERCENTILE |
| tc07_set_json.sql | SET/JSON | SCRATCH 접근·비교자 힙 폴백(>256B) |
| tc08_late_domain.sql | 늦은 도메인·재귀 CTE 공용 리스트 | D-199-13·R1(스캔 열린 채 append) |
| tc09_wide.sql | 64+ 컬럼 | 비트맵 9B·컬럼 65 NULL·접두 deform |
| tc10_inplace.sql | in-place 5지점 | #185 계약(가변 컬럼 뒤 대상) |
| (JDBC) 역방향 커서 | `../cbrd27365-smoke/ScrollSmoke.java` | backward_capable A·prev_len·hdr 8B — shell TC 후보 |

## 배치 (#201, 2026-09-04)

TC PR CUBRID/cubrid-testcases#3420(`tc/pr-7866`) `sql/_36_guava/cbrd_27365/cases/cbrd_27365_<n>.sql`(n = tc 번호, 1~10)로 배치했다. CTP 답안(`answers/`)은 PR 빌드의 CTP 출력이며 tc08 을 제외한 9건은 develop 빌드 출력과 바이트 동일(tc08 은 develop 이 `qfile_unify_types` assert 로 서버가 죽는다).
tc04/tc06/tc07/tc09 의 `.sql` 은 CTP 반입 과정에서 문법 오류였던 문장을 고쳤다(여기 `.sql` 도 동기화; `.answer.*` 는 수정 전 csql 출력이라 해당 문장 자리에 ERROR 가 남아 있다 — 정합성 판정의 근거는 TC PR 의 CTP 답안).

