# PR-3707 post-ready comments


## CUBRID/cubrid-testcases#3707

- event: COMMENT
- commit_id: 203c1614f520aefcbc7dbe7f21414390d630137f

### top-level body

상관 파생 테이블 병렬 스캔 케이스 추가 감사합니다. 로컬 컨테이너 CTP 로 최신 develop optdebug 빌드(4333ce3a8, gha-ci 아카이브)에서 돌려봤는데 OK 였고 코어도 없었습니다. .result 도 답지와 그대로 같았습니다.

확인 부탁드립니다
- 본문에 "수정 전 빌드 검증은 아직 하지 않았습니다(draft)" 가 남아 있는데, 지금은 리뷰 요청 상태라 수정 전(46e0abd95^) 결과를 채우거나 문구를 정리해주시면 좋겠습니다. 코드로 보면 수정 전에는 Case 2, 5 의 parallel workers 줄이 빠지고 Case 10 이 틀린 값을 내서 NOK 이고, 나머지는 양쪽 모두 직렬이라 PASS 일 것 같습니다.
- Greptile 이 남긴 세 건(Case 8, 9 직렬 확인, Case 11 trace, Case 10 키 누락/중복)에 대한 의견도 각 스레드에 남겨주시면 좋겠습니다.

### inline: sql/_36_guava/cbrd_27205/cases/cbrd_27205.sql:120 (RIGHT, Case 5 파생 테이블)

Case 5 를 sort GROUP BY 로 설명하고 있는데, 파생 테이블에 no_hash_aggregate 가 없어서 답지의 GROUPBY 줄이 `hash: true, sort: true` 로 나옵니다. 해시 집계로 도는 것 같습니다. Case 11 처럼 `/*+ no_hash_aggregate */` 를 넣으면 trace 가 Case 10 처럼 `hash: false` 가 되어서, 병렬 워커 안에서 정렬 GROUP BY 를 도는 상관 파생 테이블을 trace 로 확인할 수 있지 않을까요? 해시 쪽을 의도하신 거라면 헤더와 본문의 이름만 맞춰주시면 될 것 같습니다.

### inline: sql/_36_guava/cbrd_27205/cases/cbrd_27205.sql:82 (RIGHT, Case 2 using index)

상관 파생 테이블 케이스가 모두 `using index ix_o27205(+)` 로 고정돼 있고 체인 끝이 파생 테이블 temp scan 이라, #7794 가 heap 쪽에 넣은 두 분기는 지나가지 않는 것 같습니다. 체인에 dptr 이 있으면 마지막 inner heap scan 을 cached scan 으로 여는 부분(`px_scan_task.cpp` 의 `inner_cached_scan`, JIRA 첨부 테스트 설명의 실버그 2)과, row-by-row fallback 에서 비연결 dptr 이면 heap spec 도 `NO_PARALLEL_SCAN` 으로 두는 부분(`px_scan_checker.cpp`)입니다. 최신 develop(4333ce3a8)에서 인덱스 없는 작은 테이블 t27205 를 하나 더 두고 아래 두 쿼리를 돌려보니, A 는 바깥 o 가 parallel(gather: buildvalue)이고 그 아래 체인 끝이 t 의 heap scan 이었고, B 는 바깥 heap 이 직렬이었습니다. 둘 다 no_parallel_scan 쪽과 결과가 같았습니다(A 150000 / 37575000, B 3000 / 4501500). 이 두 쌍을 케이스로 추가해보는 건 어떨까요?
```sql
create table t27205 (k int, v int, s varchar(200));
insert into t27205 select mod(level, 10), level, lpad('y', 200, 'y') from db_root connect by level <= 500;
-- A: ordered use_nl 이 없으면 hash join 으로 바뀌어 체인이 d 에서 끝납니다
select /*+ recompile parallel(4) ordered use_nl */ count(*), sum(t.v)
  from o27205 o, (select i.v from i27205 i where i.k = o.k) d, t27205 t
 where o.k <= 3000 and t.k = mod(d.v, 10) using index none;
-- B: dptr 이 없으면 같은 rownum 조건에서 gather: row by row 로 병렬입니다
select /*+ recompile parallel(4) */ count(*), sum(d.v)
  from o27205 o, (select i.v from i27205 i where i.k = o.k) d
 where o.k <= 3000 and rownum <= 100000 using index none;
```

### 기존 스레드 (새로 게시하지 않음)

- Greptile 4254097438 (Case 8, 9 직렬 확인), 4254097443 (Case 11 trace), 4254097447 (Case 10 키 누락/중복) 은 작성자 답이 없다. 같은 내용을 다시 달지 않고, top-level 본문에서 스레드 답변만 요청한다.
