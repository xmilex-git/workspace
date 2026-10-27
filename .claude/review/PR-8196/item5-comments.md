# PR 8196 항목 5 게시용 코멘트 (4번 세션)

리뷰 이벤트: COMMENT (commit_id `908bdc5af67a752fd168b71cdf2c6f140520861d`)
근거: `item5-like-byte-path.md`

## 리뷰 본문

문자열 리프(LIKE, `=`, `<>`, IN, SUBSTRING IN)가 행마다 거치는 경로 위주로 살펴봤습니다. head `908bdc5af` 위에 아래 인라인 내용을 켜고 끌 수 있게 한 시제품을 만들어, 같은 바이너리 안에서 1백만 행 `csql -S` 로 `instructions:u` 를 비교했습니다(반복 편차 0.25% 이하). 경계값 534 질의(후행 공백, NUL, 한글, `%`/`_`/`\`, 콜레이션 6종)는 모든 변형에서 develop 과 결과가 같았고 optdebug 에서 assert 도 나지 않았습니다. 아래 숫자는 모두 1백만 행 1회 실행의 명령어 수입니다.

## 인라인

### src/query/expr_batch.c:1362

`qstr_like_match()` 를 행마다 부르면 `qstr_eval_like()` 가 매번 `lang_get_collation()`, `intl_pad_char()`, ESCAPE 검사, `byte_lockstep_kind` switch 를 다시 거친 뒤에 lockstep 에 들어가는데, 콜레이션과 codeset 은 리프를 만들 때 정해지니 lockstep 인스턴스를 리프에서 한 번 골라 두고 이 루프에서 바로 부르는 것은 어떨까요? `vc LIKE '%ABC%'`(utf8_bin) 에서 이 경유가 행당 84 명령어, 전체의 11% 였습니다(callgrind). `qstr_eval_like()` 와 같은 조건으로 인스턴스를 돌려주는 함수를 `string_opfunc.c` 에 두고 함수 포인터로 부르게 해 보니 751M -> 667M(-11.2%), UTF-8 인스턴스를 직접 부르면 656M(-12.7%)이었습니다. L1i 미스는 원래 행당 1회 미만이라 이득은 대부분 명령어 수에서 나오는 것 같습니다.

### src/query/expr_batch.c:1372

lockstep 이 되는 콜레이션(`byte_lockstep_kind != LANG_LOCKSTEP_NONE`)에서는 `lang_fastcmp_byte()`(utf8_ko_cs 의 `lang_strmatch_utf8()` 비교 모드도)의 결과가 "공백과 NUL 은 같은 값, 길이가 다르면 ignore_trailing_space 일 때만 꼬리가 공백/NUL 뿐이어야 같음" 과 같아서, 시제품에서 memcmp 로 이 루프 안에서 비교해 보니 `instr_v = 'TAKE BACK RETURN'` 455M -> 354M(-22%), `mode_v IN (5개)` 804M -> 662M(-18%), 짧은 `mode_c = 'MAIL'` 은 -5% 였습니다. 꼬리 규칙이 LIKE 와 달라서(`'abc ' = 'abc'` 는 FALSE, `'abc ' LIKE 'abc'` 는 TRUE) lockstep 함수를 그대로 쓰지는 못하고, `binary` 는 꼬리 NUL 만 보는 `lang_fastcmp_binary()` 규칙이라 커널이 둘 필요해 보이는데, `=`/`<>` 와 IN(1300) 을 `fastcmp` 간접 호출 대신 이런 바이트 커널로 평가하는 것은 어떨까요?

### src/query/expr_batch.c:1277

여기서 행마다 문자열 전체의 문자 수를 세고 `intl_char_size()` 를 두 번 더 부르는데, `start - 1` 문자를 건너뛰고 `len` 문자만 전진하는 한 번의 순회로 같은 결과를 낼 수 있지 않을까요? `substring(instr_v, 1, 4) IN ('TAKE', 'NONE')` 이 PR 그대로 699M, 바이트 비교만 했을 때 657M, 한 번 순회까지 하면 517M(-26%)였습니다. 문자열 끝에서 잘리는 경우는 `qstr_substring()` 과 같게 맞춰야 할 것 같습니다.

### src/query/expr_batch.c:980

`_` 와 `\` 를 거르는 것은 `eb_like_match()` 시절의 조건으로 이해하고 있습니다. 해석기 필터는 항 하나만 거절돼도 스캔 전체가 `batch: no (the data filter is interpreted)` 가 되어서 `vc LIKE '%AB_C%'` 가 1767M 로 행 경로 그대로였고, 이 함수를 풀면 655M(-63%)였습니다. 지금은 `qstr_eval_like()` 가 `_` 를 처리하고 ESCAPE 가 없으면(`expr_pred_term_string_info()` 가 `esc_char` 를 거름) `\` 는 리터럴이라 이 함수는 없어도 되지 않나요?

## 기존 스레드 답글

### 4335899593 (src/query/expr_compile.c:3971, CHAR LIKE 제외)

덧붙이면, 이 조건과 `eb_like_pattern_ok()` 를 풀어 시제품으로 배치에서 직접 돌려 보니 CHAR(8)/CHAR(44) LIKE 가 경계값 질의에서 develop 과 결과가 같았고(optdebug 포함), `ch LIKE '%ABC%'` 1백만 행이 1770M -> 664M(-63%)이었습니다. 참고 부탁드립니다.
