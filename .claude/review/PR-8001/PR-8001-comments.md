# PR #8001 게시용 리뷰 코멘트

이 파일은 사용자가 확인한 뒤에만 게시한다. 리뷰 이벤트와 commit_id 는 메타데이터이며 본문에 넣지 않는다.

기존 코멘트: greptile 의 top-level 코멘트 2건은 작성자가 이미 답했다. 다시 달 항목은 없다.

---

## CUBRID/cubrid#8001

- event: COMMENT
- commit_id: 718f3699e55ffe09a0c24c25700aa1f9c315ff3c

### top-level

SEMI/ANTI JOIN 을 해시 조인으로 실행할 수 있게 하면서 직렬/병렬 실행기, 후보 평가, 결과 행 수 추정, ANTI ON 절 조건 분류를 함께 바꾼 PR 로 이해하고 있습니다. 리뷰하면서 head(718f3699e)와 merge-base(a59140bdd)의 CI optdebug 빌드로 경계 사례를 몇 가지 돌려봤습니다. ON 절에 바깥쪽 테이블만 참조하는 조건이 있는 ANTI JOIN 은 develop 에서 틀리던 결과가 이 PR 에서 맞게 나왔습니다. 해시 조인 세 가지 모드(단일, 파티션, 병렬)의 SEMI/ANTI 결과도 NL 조인, NO_UNNEST 결과와 같았습니다.

확인 부탁드립니다
- JIRA DoD 의 시나리오 TC 가 아직 TC PR(CUBRID/cubrid-testcases#3565)에 없는 것 같습니다. 자세한 내용은 그쪽에 남겼습니다.
- CUBRID/cubrid-testcases-private-ex#4232 는 파일 변경이 없는 것 같은데, TC Merge Gate 안내대로 close 하는 것은 어떨까요?

추가로 논의가 필요해 보이는 항목
- 이 PR 범위 밖이고 develop 에서도 결과가 같은데, ANTI JOIN 이 NL 조인의 마지막 조인이 되면 LEFT JOIN 결과를 거르는 WHERE 조건(`rc.x is null`)이 일치 판정 안에서 평가되는 것 같습니다. 아래 질의는 해시 조인과 NO_UNNEST 에서 5, 7 인데 `ORDERED USE_NL` 에서는 1, 3, 4, 5, 6, 7 이 나옵니다. 해시 조인 쪽은 AC-4.2 로 맞게 처리됐지만 NL 쪽은 그대로라, 같은 질의가 계획에 따라 결과가 달라질 수 있어 보입니다. 별도 이슈로 보는 것이 맞을지 의견 부탁드립니다.

```sql
drop table if exists ra, rb, rc;
create table ra (id int, k int, x int, cc int);
create table rb (k int, x int, y int);
create table rc (id int, x int);
insert into ra values (1, 1, 1, 1), (2, 2, 2, 2), (3, 3, 3, null), (4, null, 4, 4), (5, 5, 5, 5), (6, 6, 6, 6), (7, 1, 7, null);
insert into rb values (1, 0, 1), (1, 5, 2), (1, 9, 3), (2, 100, 4), (null, 999, 5), (5, 0, 6), (6, 7, 7);
insert into rc values (1, 1), (2, 20), (3, 3), (4, 4), (5, 50), (6, 6), (7, 70);
update statistics on ra, rb, rc with fullscan;

-- USE_HASH: 5, 7 / ORDERED USE_NL: 1, 3, 4, 5, 6, 7
select /*+ recompile ORDERED USE_NL */ ra.id
from ra left outer join rc on rc.id = ra.id and rc.x < 10
where rc.x is null
  and not exists (select 1 from rb where rb.k = ra.k and rb.x > 50)
order by 1;
```

### inline

1. `src/query/query_executor.c` line 16534 (side RIGHT)

NIT: 해시 조인도 `JOIN_RIGHT` 를 그대로 받아서(`hjoin_check_empty_inputs ()` 의 `JOIN_RIGHT` case) 이 분기를 지나는 것으로 알고 있습니다. 안쪽이 비면 바깥쪽 aptr 을 건너뛰는 동작이 해시 조인 RIGHT 에도 맞으니, `(merge join only)` 는 빼는 것이 맞지 않나요?

2. `src/query/query_hash_join.c` line 3626 (side RIGHT)

NIT: 같은 루프의 자연 종료(`hjoin_probe_key ()` 의 not found)처럼 `qfile_slot_reset (&build->tuple_record)` 를 쓰는 것은 어떨까요? 지금은 PEEK 레코드라 `size` 가 0 이어서 결과에는 영향이 없어 보입니다. `hjoin_outer_probe ()` 의 ANTI 분기와 `px_hash_join_task_manager.cpp` 의 두 곳도 같이 맞추면 좋을 것 같습니다.

---

## CUBRID/cubrid-testcases#3565

- event: REQUEST_CHANGES
- commit_id: c27353c9535718b4eac38cefb7cc858ff3306daa

### top-level

`cbrd_27465`, `cbrd_27485` 에 `USE_NL` 을 넣어 기존 NL 계획을 유지한 변경은 답안과 맞고, CI(`tc/pr-8001`)도 통과한 것을 확인했습니다.

다만 CBRD-27379 의 DoD 에 있는 시나리오 TC(`cbrd-27379_test_scenarios_[1-5]`)가 아직 없는 것 같습니다. 지금은 SEMI/ANTI 해시 조인 계획을 답안에 고정한 TC 가 없습니다. 그래서 실행기(단일/파티션/병렬)나 ANTI ON 절 조건 분류가 다시 깨져도 CI 에서 잡히지 않을 것 같습니다.

`sql/_36_guava/cbrd_27379/` 에 AC-1, AC-2, AC-4 시나리오를 넣는 것은 어떨까요? AC-1.9 실행 모드는 trace 의 `SPLIT`, `PARALLEL` 줄로 구분되어 답안에 남습니다. AC-3 추정 행 수는 CTP 가 계획의 card 를 마스킹해서 답안으로 고정하기는 어려울 것 같습니다.

develop 에서 결과가 틀리던 아래 두 질의도 같이 넣어두면 좋을 것 같습니다. develop(a59140bdd)에서는 각각 4 와 3, 4 가 나오고, 이 PR 에서는 3, 4, 7 과 2, 3, 4, 5, 7 이 나옵니다.

```sql
-- 데이터는 cubrid#8001 코멘트의 ra, rb, rc 와 같습니다
select /*+ recompile USE_HASH */ ra.id
from ra anti join rb on rb.k = ra.k and ra.cc is not null
order by 1;

select /*+ recompile USE_HASH */ ra.id
from ra inner join rc on rc.id = ra.id
  anti join rb on rb.k = ra.k and ra.x = rc.x
order by 1;
```

### inline

없음

---

## 후속 (2026-10-10): CUBRID/cubrid#8001

- event: APPROVE (review 5479197673, 게시됨)
- commit_id: 718f3699e55ffe09a0c24c25700aa1f9c315ff3c

### top-level

답변 감사합니다. 주석 수정과 `qfile_slot_reset` 검토, DoD 시나리오 TC 추가는 말씀하신 대로 진행해 주시면 될 것 같습니다.

## 후속 (2026-10-10): CUBRID/cubrid-testcases#3565

- event: APPROVE (review 5479200252, 게시됨)
- commit_id: c27353c9535718b4eac38cefb7cc858ff3306daa

### top-level

cubrid#8001 에 남겨주신 답변대로 DoD 시나리오 TC 는 추가해 주시면 될 것 같습니다.
