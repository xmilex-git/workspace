# PR-3716 post-ready comments

## CUBRID/cubrid-testcases#3716

- event: COMMENT
- commit_id: 201dfe74e4e9a477f9ad7080dc7a7b778fa8fbab
- 게시하지 않는 항목: report Finding 4 (NIT, 워크스페이스 형식 규칙)

### top-level body

sort-merge join 입력의 parallel scan 케이스 추가 감사합니다. 최신 develop(4333ce3a8, gha-ci optdebug 빌드)에서 컨테이너 CTP 로 돌려보니 18개 블록 모두 answer 와 같았고 코어도 없었습니다.

케이스 밖에서 같은 빌드로 몇 가지를 더 찍어봤습니다(커밋하지 않은 probe).
- SHOW INDEX CAPACITY: i_mj_k 40페이지, i_mj_kn 37페이지
- Case 2 의 g 범위를 절반(g < 10000)으로 줄이면 MERGELIST 입력의 temp scan parallel 줄이 사라짐
- 비교문에 trace 를 켜면 Case 1, 3 비교문의 p 쪽 MERGELIST 에 parallel workers 줄이 붙음(Greptile 첫 번째 코멘트에 따로 적었습니다)

확인 부탁드립니다
- CBRD-27307(#7795)에서 MERGELIST 자체를 병렬화하면 이 answer 의 MERGELIST 줄도 바뀔 것 같은데, 그쪽 tc/pr-7795 에 이 케이스 answer 갱신도 같이 들어가야 할 것 같습니다.

### inline: sql/_36_guava/cbrd_27404/cases/cbrd_27404.sql:70 (RIGHT, Case 2 traced select)

md5 는 항상 32자라 sum(length(d1.p) + length(d2.p)) 는 건수 x 64(answer 도 20000 / 1280000)여서 결국 건수만 보는 것 같습니다. g 가 0..39999 순열이라 입력마다 g 당 한 행씩이어서, parallel temp scan 이 한 페이지를 두 번 읽고 같은 행 수의 다른 페이지를 빠뜨려도 건수와 합이 그대로라 traced 행과 hash join 비교가 모두 PASS 일 것 같습니다. 키 합으로 바꾸는 건 어떨까요? 77, 80행도 같이 바꾸면 되고, develop 에서 20000 / 399980000 으로 hash join 결과와 같았습니다(g 마다 한 행이라 d1.p = d2.p 개수를 세면 값까지 볼 수 있습니다).
```suggestion
select /*+ USE_MERGE PARALLEL(4) NO_PARALLEL_SUBQUERY */ count(*), sum(cast(d1.g as bigint) + d2.g)
```

### inline: sql/_36_guava/cbrd_27404/cases/cbrd_27404.sql:45 (RIGHT, insert limit 40000)

SHOW INDEX CAPACITY 로 보니 develop 에서 i_mj_k 40페이지, i_mj_kn 37페이지라 32페이지 게이트와 1.25배, 1.16배 차이밖에 안 나는 것 같습니다. Case 2 도 g 범위를 절반으로 줄이니 MERGELIST 입력의 parallel 줄이 사라져서 list 도 2배가 안 됩니다. b-tree 나 temp tuple 형식이 조금만 바뀌어도(453da49c8 처럼) Case 1, 2 는 정상 엔진에서 NOK 가 되고, trace 가 없는 Case 3 은 직렬끼리 비교하게 되어도 알 수 없을 것 같습니다. 행과 키 수를 3배 정도(limit 120000, mod(rownum, 90000), mod(rownum * 7, 120000), 범위와 g 조건도 비례)로 늘리는 건 어떨까요?

### inline: sql/_36_guava/cbrd_27404/cases/cbrd_27404.sql:52 (RIGHT, Case 1 traced select)

JIRA 첨부 S1 은 인덱스에 없는 v 를 합산해서 입력이 non-covered index scan 인데, 이 케이스에는 covered 입력만 있는 것 같습니다. develop 에서 Case 1 을 sum(cast(a.g as bigint) + b.g) 로 바꿔보니 두 입력 모두 (lookup time ...) 이 붙은 parallel index scan 이었고 결과(59504 / 2393772100)가 NO_PARALLEL_SCAN 과 같았습니다. lookup 경로는 covered 경로와 다른 코드라 Case 4 로 추가하거나, 빼신 이유를 본문에 남겨주시면 좋겠습니다.

### Greptile thread replies

reply to 4254104682 (cbrd_27404.sql:58):

develop 에서 세 비교문에 trace 를 켜 보니 p 의 입력 scan 은 세 곳 모두 parallel 이었습니다. 다만 Case 1, 3 비교문에서는 p 의 MERGELIST 에도 parallel workers 줄이 붙어서, 바깥 쿼리가 p 를 subquery executor 로 따로 돌리고 있었습니다. 바깥 SELECT 에 NO_PARALLEL_SUBQUERY 를 넣으니 그 줄만 사라지고 입력 scan 은 그대로 parallel 이었고 answer 도 바뀌지 않아서, 말씀대로 세 비교문에 넣어두는 게 좋을 것 같습니다.

reply to 4254104689 (cbrd_27404.sql:88):

덧붙이면 단일 컬럼 인덱스에는 NULL 키가 저장되지 않아서(SHOW INDEX CAPACITY 의 i_mj_kn Total_value 가 39604 = 40000 - 396) BETWEEN 을 빼도 index 입력에는 NULL 이 들어가지 않을 것 같습니다. NULL 키가 merge 입력에 들어가는 경우를 보려면 kn 으로 GROUP BY 한 derived table 처럼 list 입력으로 만들어야 하지 않을까요?
