# PR 8196 항목 4 — 게시용 코멘트 (cubrid-pr-review 말투)

- 대상: CUBRID/cubrid#8196, commit_id `908bdc5af67a752fd168b71cdf2c6f140520861d`
- 리뷰 이벤트: COMMENT
- 근거: `item4-char-fixed-length.md` 발견 1-3 (사용자 지시: "말투로 고쳐서 리뷰 올려")

---

## top-level

CHAR 컬럼이 페이지 배치에서 어떻게 처리되는지 위주로 살펴봤습니다. develop 의 CHAR 는 VARCHAR 와 같은 가변 영역에 공백 패딩된 채 저장되어서, `=`, `<>`, IN, SUBSTRING IN, OR, GROUP BY 키는 VARCHAR 와 같은 효과가 나는 것을 확인했습니다(1백만 행 `CHAR(10) = 'ab1'` 서버 명령어 수 develop 대비 -71%). 측정은 CI 의 head·develop release 빌드에서 `;plan detail` trace 와 `perf stat -e instructions:u` 로 했고, 호스트를 다른 작업과 같이 쓰고 있어서 시간 대신 명령어 수로 봤습니다.

확인 부탁드립니다:
- 인라인 두 건을 반영하시면 본문의 "지금 배치가 거절하는 모양" 에서 "CHAR 컬럼의 LIKE" 는 빠지고, 대신 "`CHAR(255)` 이상 컬럼" 이 들어가야 할 것 같습니다.

---

## src/query/expr_batch.c:969

`eb_cell_str()` 가 255바이트 이상(긴 형식·압축)인 문자열을 읽지 못해 그 페이지를 행 경로로 다시 도는데, CHAR(N) 은 N 글자까지 공백을 채워 저장하니 `CHAR(255)` 이상 컬럼은 거의 모든 페이지가 두 번 처리되는 것 같습니다. 1백만 행에서 서버 명령어 수가 develop 대비 직렬 +9.6%, `parallel(4)` +11.3% 였고, 같은 값의 `VARCHAR(300)` 은 -71% 였습니다. 한글 90자가 섞인 utf8 `CHAR(100)` 도 +9.7% 였습니다.

```sql
create table t (id int, c300 char(300));
insert into t select rownum, 'ab' || mod(rownum, 10) from db_class a, db_class b, db_class c limit 30000;
select /*+ no_parallel_scan */ count(*) from t where c300 = 'ab1';
-- batch pages: 1 (row path: 125, last: a string the batch does not read from the record)
```

precision 이 `OR_MINIMUM_STRING_LENGTH_FOR_COMPRESSION` 이상인 CHAR 는 `eb_new_col_vec()` 에서 계획 단계에 거절하고, utf8 CHAR·긴 VARCHAR 처럼 값에 따라 달라지는 경우는 `pages_fallback` 이 일정 비율을 넘으면 남은 페이지는 배치를 시도하지 않는 것은 어떨까요?

## src/query/expr_compile.c:3971

`|| like` 는 `c7f101577` 의 `eb_like_match()` 가 마지막 리터럴을 문자열 끝에 붙여 비교하던 때, 패딩된 CHAR(`'ab1       ' LIKE '%b1'`) 때문에 넣은 것으로 이해하고 있습니다. 지금 리프는 `qstr_eval_like()` 를 레코드 바이트에 그대로 부르고 있어서 행 경로(`eval_pred_like6()` -> `db_string_like()`)와 바이트·collation·escape 가 같으니 더는 필요 없어 보입니다.
이 조건만 풀어 빌드해 보니 optdebug 로 sql 17582건·medium 975건 실패 0 이었고, CHAR LIKE 64개 질의(NULL, 후행 공백 패턴, NOT, AND/OR, 다바이트, 직렬·병렬) 결과가 develop 과 같았습니다. 명령어 수는 `c10 LIKE '%b1'` -60%, `v10 = 'ab1' AND c10 LIKE '%b1'` -73% 였습니다(지금은 CHAR LIKE 한 항 때문에 같이 있는 VARCHAR `=` 리프까지 배치가 꺼집니다).
다만 `CHAR(255)` 이상 거절이 없으면 `CHAR(300) LIKE` 가 새로 행 경로 되돌림을 타서 +6.2% 가 되니, 위 코멘트와 함께 반영하는 것은 어떨까요?

```suggestion
      || (TP_DOMAIN_TYPE (col->domain) != DB_TYPE_VARCHAR && TP_DOMAIN_TYPE (col->domain) != DB_TYPE_CHAR))
```

## src/query/expr_compile.c:3910

NIT: CHAR 가 들어오고 LIKE 가 `qstr_eval_like()` 로 바뀐 뒤 주석 몇 곳이 그대로인 것 같습니다. 이 함수의 "A term on a VARCHAR column ... over a binary collation", `expr_compile.h` 의 `like` 필드 "a VARCHAR column LIKE", `expr_batch.c` 의 `EB_STR /* VARCHAR: ... */` 와 `eb_add_str_leaf()` 의 "a LIKE: a binary one on both sides, where '%' matches bytes", `heap_attrinfo_raw_locator()` 의 받는 타입 목록(VARCHAR·CHAR 빠짐)입니다.
