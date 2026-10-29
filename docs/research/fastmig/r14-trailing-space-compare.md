# R14 CHAR/VARCHAR 뒤 공백 비교 규칙 변경(CBRD-23731·CBRD-24149)과 옛 출발의 유니크 인덱스·파티션 배치

Part of xmilex-git/workspace#472, answers #524. 정적 판독만 했다(서버·DB·빌드 없음).
인용 ref: `R10` = `origin/release/10.2`(416bb667c), `R11.1` = `origin/release/11.1`, `R114` = `origin/release/11.4`(46212adcd),
`D` = `origin/develop`(5cd1de888). 저장소는 `~/dev/cubrid-worktree/develop`. fastmig 코드는 `~/dev/cubrid-fastmig`(14079bf).

## 질문

CHAR/VARCHAR 뒤 공백 비교 규칙이 CBRD-23731·CBRD-24149에서 바뀌었다. 바뀌기 전 버전(10.2, 11.0 초기 패치)에서 출발한 DB를 develop 규칙으로 옮기면 무엇이 깨지는가?

- (a) 유니크 인덱스를 develop 규칙으로 다시 빌드하면 중복 키가 생길 수 있는가?
- (b) CHAR(n) 키는 디스크에 어떻게 저장되는가?
- (c) 문자열 키 HASH 파티션의 행 배치가 달라지는가?
- 반대 방향은 어떤가? 10.2가 같다고 본 값을 develop이 다르다고 볼 때 무엇이 어긋나는가?
- `ignore_trailing_space=yes` DB는 받아도 되는가?
- 판정 규칙은 무엇이고, plan pre-check는 출발 DB에서 문제를 어떻게 찾아내는가?

## 결론

1. **유니크 인덱스를 다시 빌드해도 중복은 생기지 않는다.** 10.2는 끝에 붙은 가중치 0 문자(공백 0x20, 그리고 EN/ISO 콜레이션에서는 0x00)를 무시하고 비교한다. 그래서 10.2가 같다고 보는 값의 묶음이 develop보다 크다. develop이 같다고 보는 두 값은 10.2도 반드시 같다고 본다. 그러니 10.2 유니크 인덱스에 이미 들어 있는 서로 다른 키는 develop에서도 서로 다르다.
2. **반대 방향 문제는 인덱스가 아니라 다른 곳에서 생긴다.** 인덱스는 develop 규칙으로 다시 빌드하므로 순서 문제가 없다. 하지만 행을 그대로 옮기면 10.2 규칙으로 정해 둔 두 가지 관계가 develop에서 성립하지 않을 수 있다.
   - **외래 키(FK) 짝:** 10.2에서 자식 `'a '`는 부모 `'a'`와 짝이 맞았다. develop에서는 짝이 없는 자식이 된다.
   - **LIST/RANGE 파티션 배치:** `'a '` 행은 10.2에서 `'a'` 값을 가진 LIST 파티션에 들어갔다. develop은 그 행에 맞는 파티션을 찾지 못한다.
3. **HASH 파티션은 T3(#489)의 결론 "배치 그대로"가 10.2 출발에는 맞지 않는다. 이 티켓에서 새로 찾은 위험이다.**
   - 끝 공백은 두 버전 모두 해시 전에 잘라낸다. 그래서 `'a'`와 `'a '`가 같은 파티션에 간다는 점은 10.2와 develop이 같다.
   - 하지만 **문자열 중간의 공백 가중치가 0(10.2)에서 32(11.0 이상)로 바뀌었다.** 그래서 공백을 포함한 키(`'New York'` 같은 값)의 해시 값이 달라진다.
   - 영향받는 콜레이션은 utf8_bin(1), iso88591_en_ci(3), utf8_en_cs(4), utf8_en_ci(5), utf8_tr_cs(6), utf8_ko_cs(7)이다. **utf8 DB의 기본 콜레이션 utf8_bin이 여기에 들어간다.**
   - 11.0~11.4 출발은 develop과 같다(아래 표 H 줄).
4. **`ignore_trailing_space`는 DB 볼륨에 기록되지 않는 숨김 conf 파라미터다.** 10.2에는 이 파라미터가 없다. 이 파라미터가 영향을 주는 것은 출발 데이터가 아니라 **도착 서버가 인덱스를 읽는 규칙**이다. fastmig의 radix 정렬은 `no`를 가정한다. 따라서 도착 conf에 `yes`가 있으면 거부하는 것이 맞다(추천).

| # | 대상 | 10.2 출발 | 11.0.0~11.0.5·11.1 출발 (범위 밖) | 11.2~11.4 출발 | fastmig 판정 |
|---|---|---|---|---|---|
| U | VARCHAR 유니크 인덱스 재빌드 | 중복 없음. develop 쪽이 더 잘게 나눈다 | 중복 없음. B-tree VARCHAR 비교가 이미 ti=false | 같은 규칙 | 검사 불필요 |
| C | CHAR(n) 키 | 10.2는 n까지 공백을 채운 고정 폭으로 저장한다. develop은 CHAR끼리 항상 ti=true로 비교한다. 같다고 보는 묶음이 두 버전에서 같다 | 같음 | 같음 | 비교 규칙 문제는 없다. 저장 형식 재인코딩은 G2/R7 범위다 |
| N | 비유니크 인덱스 순서·범위 | 10.2의 키 하나가 develop에서 여러 키로 나뉜다. 다시 빌드하므로 문제없다 | — | — | 검사 불필요 |
| F | VARCHAR FK 짝 | **자식과 부모가 끝 공백만 다르면 develop에서 짝 없는 자식이 된다** | 없음 | 없음 | pre-check 필요 |
| L | VARCHAR LIST/RANGE 파티션 | **행 값이나 경계 값이 끝 공백만 다르면 develop이 고르는 파티션과 어긋난다** | 없음 | 없음 | pre-check 필요 |
| H | 문자열 HASH 파티션 | **콜레이션 1,3,4,5,6,7에서 중간에 공백이 있는 키는 해시가 달라진다** | 없음(가중치 분리가 11.0 GA부터) | 없음 | pre-check, 그다음 거부 또는 재분배 |
| P | `ignore_trailing_space` | 파라미터 없음 | 있음 | 있음 | 도착 conf가 `yes`이면 거부 |

## 근거

### 1. 두 커밋이 실제로 바꾼 것

- **CBRD-23731은 11.0 GA에 들어갔다.** 커밋은 `43277f316`, `513e5007b`, `b6873b9b9`, `288efc55b`, `65d6bd02b`, `8a32a412d`이고, 모두 `v11.0` 태그에 포함된다(`git tag --contains`). 10.2 선에는 없다(`git log --grep CBRD-23731 origin/release/10.2`는 비어 있다).
  - `b6873b9b9`가 `PRM_ID_IGNORE_TRAILING_SPACE`(기본 false)를 추가했다.
  - 같은 커밋이 콜레이션 가중치를 둘로 나눴다. `weights`/`next_cp`가 "공백도 의미 있는" 표이고, `weights_ti`/`next_cp_ti`가 "끝 공백 무시" 표다(`b6873b9b9` `src/base/locale_support.h` diff).
  - `QSTR_COMPARE`에 인자 `ti`가 붙었다. 10.2 정의는 `R10:src/query/string_opfunc.h:67`(5인자)이고 develop 정의는 `D:src/query/string_opfunc.h:65`(6인자)이다.
- **CBRD-24149는 11.0.6과 11.2 이상에 들어갔다.** 11.0 선에서는 `8e8ec6918`, `e1160bbea`로 백포트되었다(`git tag --contains 8e8ec6918` → 첫 태그 `v11.0.6`). 11.2 선에서는 `991c8a4bc`, `c69671eb3`, `5000a8a7e`이다. **11.1 선에는 없다**(`git log --grep CBRD-24149 origin/release/11.1`은 비어 있다).
  - 바뀐 것 1: CHAR와 VARCHAR를 섞어 비교하던 규칙. 예전에는 CHAR 쪽 끝 공백을 잘라내고 ti=false로 비교했다. 이제는 "둘 다 CHAR일 때만 ti"이다(`991c8a4bc` `mr_cmpval_char`/`mr_cmpval_string` diff).
  - 바뀐 것 2: `btree_compare_key`가 `do_coercion = 2`로 강제하던 것을 지웠다(`991c8a4bc` btree.c diff). 강제가 남아 있는 모습은 `R11.1:src/storage/btree.c:18746`에서 볼 수 있다.
  - 바뀐 것 3: CHAR B-tree의 prefix(non-leaf separator) 도메인을 VARCHAR로 바꾸던 것을 그만두었다(`btree_generate_prefix_domain` diff).
  - **같은 VARCHAR끼리의 B-tree 비교(ti=false)는 23731 이후로 바뀌지 않았다.** `R11.1`의 `mr_data_cmpdisk_string`도 `!ignore_trailing_space → ti = false`이다(`R11.1:src/object/object_primitive.c:10923`부터).

### 2. 10.2 비교: 끝의 가중치 0 문자를 무시한다

- `lang_fastcmp_byte`는 utf8_bin, utf8_en_cs, utf8_en_ci, iso88591_en_ci가 쓰는 비교 함수다(`R10:src/base/language_support.c:5590`).
  - 공통 길이까지 `weights[]`로 비교한다.
  - 남는 꼬리에서 가중치가 0이 아닌 문자가 나올 때만 크기가 갈린다(`:5611`, `:5623` "ignore trailing white spaces").
- 이 콜레이션들의 공백 가중치는 0이다: `lang_Weight_EN_cs[32] = 0`(`R10:…language_support.c:5231`), `lang_Weight_EN_ci[32] = 0`(`:5268`). `weights[i] = i`(`:5227`)이므로 `weights[0] = 0`이다. 그래서 끝의 0x00도 무시된다.
- `lang_fastcmp_iso_88591`(`R10:…:5375`, iso88591_bin·iso88591_en_cs)도 PAD(공백)를 ZERO로 바꾸고 꼬리를 `c - 0`으로 비교한다. 동작이 같다.
- UTF-8 locale 콜레이션은 `lang_strmatch_utf8`(`R10:…:2824`)을 쓴다. 끝에서 `lang_str_utf8_trail_zero_weights`로 꼬리가 모두 가중치 0인지 확인한다(`:2906`, `:2920`). `lang_Weight_TR[32] = 0`이다(`:5790`).
- `binary`(9) 콜레이션만 다르다. `lang_fastcmp_binary`(`R10:…:6410`)는 꼬리에서 0x00만 무시하고 공백은 의미 있게 본다. develop도 같은 함수다(`D:…:6497`).
- B-tree의 VARCHAR 키 비교도 이 경로를 탄다. `mr_data_cmpdisk_string`(`R10:src/object/object_primitive.c:11086`)이 5인자 `QSTR_COMPARE`(`:11111`, `:11206`)를 부르고, 그것이 위 fastcmp로 간다.
- **결론적으로 10.2의 같음은 "끝의 가중치 0 문자(0x20, EN/ISO에서는 0x00 포함)를 떼고 나서 같음"이다.**

### 3. develop 비교 (기본 `ignore_trailing_space=no`)

- `lang_fastcmp_byte`(`D:src/base/language_support.c:5535`): 공통 길이에서는 SPACE를 ZERO로 매핑하고 나머지는 `weight[c]`로 비교한다. 공통 부분이 같고 `!ignore_trailing_space && size1 != size2`이면 `size1 - size2`를 돌려준다(`:5574`). 즉 `'a' < 'a '`이고, `'a' < 'a\0'`이다.
- B-tree VARCHAR 비교는 `mr_data_cmpdisk_string`(`D:src/object/object_primitive.c:11254`)이다. 파라미터가 no이면 `ti = false`이다(`:11279`).
- B-tree CHAR 비교는 `mr_cmpdisk_char_internal`(`D:…object_primitive.c:12380`)이다. `ti = (domain->type->id == DB_TYPE_CHAR)`(`:12407`)이므로 CHAR는 항상 끝 공백을 무시한다.
- 11.4도 같은 코드다. `lang_fastcmp_byte`는 `R114:…language_support.c:5481`, `:5520`에 있다.

### 4. 판정 U의 증명 (develop의 같음은 10.2의 같음에 포함된다)

develop(ti=false)에서 두 값이 같다는 것은 세 가지가 모두 성립한다는 뜻이다. 길이가 같고, 모든 위치에서 (공백→0, 그 밖에는 `weights[c]`)가 같다. 공백이 아닌 문자의 `weights[c]`는 10.2와 develop에서 같다. 근거는 다음과 같다.

- EN 계열: `weights[i] = i`, ci 콜레이션은 a–z를 접는다. 10.2는 `R10:…:5227`/`:5255-5261`, develop은 `D:…:5401`/`:5442`.
- 공백: 10.2는 `weights[32] = 0`이다. develop은 SPACE→ZERO 매핑을 해서 같은 값 0을 쓴다.

그러면 10.2의 공통 부분 비교도 모두 같고, 길이가 같으니 꼬리도 없다. 따라서 10.2도 같다고 본다. 대우를 취하면, 10.2 유니크 인덱스(10.2 기준으로 서로 다른 키만 있음)의 키는 develop 기준으로도 서로 다르다. **재빌드에서 유니크 위반은 생기지 않는다.**

- utf8 locale 콜레이션(`lang_strmatch_utf8` ti 인자, `D:…:2913`)과 euckr_bin(`lang_fastcmp_ko`, `D:…:6138`)에도 같은 논리가 적용된다. euckr_bin은 develop ti=false에서 꼬리의 ASCII/EUC 공백을 `weight[SPACE]`로 센다. 그래서 develop 쪽이 더 잘게 나눈다(추론, 함수 본문 판독).
- `binary` 콜레이션은 두 버전에서 같은 함수다. 차이가 없다.

### 5. CHAR(n) 저장 형식 (판정 C)

- 10.2의 CHAR(n)은 고정 폭이다. `mr_cmpdisk_char_internal`(`R10:…object_primitive.c:12047`)은 길이를 `STR_SIZE(domain->precision, codeset)`로 정하고(`:12074` 부근) 공백으로 채운 바이트 전체를 비교한다. 디스크 쓰기는 `mr_writeval_char_internal`(`R10:…object_primitive.c:11745`)이 맡는다. 공백으로 채운다는 점은 R7(§CHAR 원소, "`STR_SIZE(n, codeset)`까지 공백으로 채워져 있다")이 이미 인용했다.
- develop의 CHAR는 가변 길이와 압축 인코딩을 쓰지만 precision까지 공백을 채운다(`D:…object_primitive.c:12040-12050`, `pr_pad_char_to_precision` `:12615`). 재인코딩은 R7 §(CHAR 원소) / G2 #482의 몫이다.
- CHAR끼리의 비교는 10.2도 develop도 끝 공백을 무시한다. 따라서 같다고 보는 묶음이 같다. CHAR(n) 유니크 키는 그대로 안전하다.

### 6. HASH 파티션 (판정 H)

- 파티션 번호는 `mht_get_hash_number(hash_size, val)`로 정한다. 10.2 호출부는 `R10:src/query/partition.c:1245`, `:1296`이고 develop 호출부는 `D:src/query/partition.c:1319`, `:1372`이다.
- 문자열 처리 부분(`case DB_TYPE_VARCHAR` 이하 30줄)은 10.2·11.2·11.3·11.4가 바이트 단위로 같다(md5 일치).
  - 끝의 ASCII 공백만 잘라낸다. 주석이 "only the trailing ASCII space is ignored"이다(10.2 `R10:src/base/memory_hash.c:2113`, 11.4 `R114:…:2416`, develop `D:…:2498`).
  - 그다음 `MHT2STR_COLL(collation, ptr, i)`를 부른다(`R10:…memory_hash.c:2127`, `D:…:2512`). 이것은 콜레이션의 `mht2str`이다(`R10:src/base/memory_hash.h:37`, `D:…:38`).
  - 그래서 `'a'`와 `'a '`는 두 버전 모두 같은 해시를 받는다.
- `lang_mht2str_byte`(`R10:…language_support.c:5657`, `D:…:5753`)와 `lang_mht2str_utf8`(`R10:…:3142`, `D:…:3262`)은 본문이 같다. 10.2와 11.4를 diff하면 0줄이다. 둘 다 **`lang_coll->coll.weights`**(ti가 아닌 표)를 쓴다(`R10:…:5665`/`D:…:5761`, `R10:…:3149`/`D:…:3269`).
- 그런데 그 표의 공백 가중치가 바뀌었다.
  - 10.2: `lang_Weight_EN_cs[32] = 0`(`R10:…:5231`), `lang_Weight_EN_ci[32] = 0`(`:5268`), `lang_Weight_TR[32] = 0`(`:5790`).
  - 11.0 이후 develop까지: `weights_ti[i] = weights[i] = i`를 한 다음 **`weights_ti[32] = 0`만** 따로 둔다(`R114:…:5323`/`:5327`, `:5353`/`:5370`, TR `:5837`/`:5913`; develop `D:…:5401`/`:5405`, `:5442`/`:5459`, TR `:5891`/`:5967`; 11.0·11.2·11.3도 `:5342`/`:5385`).
  - 따라서 `weights[32]`는 10.2에서 0, 11.0 이상에서 32이다.
- 콜레이션별로 쓰는 함수는 10.2·11.4·develop이 같다(`coll.sh` 판독).

| ID | 콜레이션 | mht2str | 영향 |
|---|---|---|---|
| 1 | utf8_bin | `lang_mht2str_byte` | 있음 |
| 3 | iso88591_en_ci | `lang_mht2str_byte` | 있음 |
| 4 | utf8_en_cs | `lang_mht2str_byte` | 있음 |
| 5 | utf8_en_ci | `lang_mht2str_byte` | 있음 |
| 6 | utf8_tr_cs | `lang_mht2str_utf8` | 있음 |
| 7 | utf8_ko_cs | `lang_mht2str_utf8`, EN_cs 가중치 | 있음 |
| 0 | iso88591_bin | `lang_mht2str_default`(원시 바이트) | 없음 |
| 2 | iso88591_en_cs | `lang_mht2str_default` | 없음 |
| 9 | binary | `lang_mht2str_default` | 없음 |
| 8 | euckr_bin | `lang_mht2str_ko`(공백을 ZERO로 직접 바꿈) | 없음 |

  - 콜레이션 ID 출처: `R10:src/base/language_support.h:106-115`.
  - 함수가 정해진 줄: 10.2 `R10:…language_support.c:333,369,539,597,654,694,713,730,747,764`, develop `D:…:348,380,554,615,674,717,739,759,779,799`.
- `ADD_TO_HASH`는 `pseudo_key = (pseudo_key << 4) + w`와 상위 니블 접기로 되어 있다(`R10:…:3120`, `D:…:3240`, 같은 정의). 그래서 중간 공백 하나의 w가 0에서 32로 바뀌면 그 뒤로 해시 값이 달라진다.
  - 예(추론): utf8_bin `'a b'`는 10.2에서 97 → 1552 → 24930이고, develop에서는 97 → 1584 → 25442이다.
  - `PARTITIONS 3`이면 24930 % 3 = 0, 25442 % 3 = 2이다. **10.2는 p0에 두었는데 develop pruning은 p2를 본다.**
  - `PARTITIONS 2`이면 둘 다 0이다. 어긋남은 확률적이다.
- 10.2의 끝 0x00 처리: `mht_get_hash_number`의 자르기 루프는 `ptr[i]`가 0이면 멈춘다(`R10:…memory_hash.c:2111` 부근, develop도 같음). `weights[0]`는 두 버전 모두 0이다. 그래서 0x00은 해시 차이를 만들지 않는다(추론).
- T3 #489가 비교한 쌍은 11.4 vs develop뿐이다(지도 Decisions). 11.2·11.3의 `lang_mht2str_byte`, `lang_mht2str_utf8`, `lang_init_common_en_cs/ci`는 11.4와 diff 0이다(이 티켓에서 확인). 따라서 **위험은 10.2 출발에만 있다.**

### 7. FK와 LIST/RANGE 파티션 (판정 F, L) — 추론

- **FK:** 10.2에서 자식 행을 넣을 때 부모 PK/UK 인덱스에서 키를 찾는다. 그 비교가 §2 규칙이므로 자식 `'a '`는 부모 `'a'`로 성립한다. develop은 §3 규칙(ti=false)으로 부모 키를 찾으므로 `'a '`는 부모가 없다. 결과는 두 가지다.
  - 옮긴 뒤에도 행은 남지만, develop 기준으로는 FK를 어긴 상태가 된다.
  - 부모를 DELETE·UPDATE할 때 CASCADE/RESTRICT가 그 자식을 보지 못한다.
- **LIST:** 10.2는 `'a '` 행을 `IN ('a')` 파티션에 넣었다(§2 같음). develop은 `'a ' ≠ 'a'`로 본다.
  - `WHERE c = 'a '` pruning이 그 파티션을 고르지 않는다.
  - 그 행을 UPDATE할 때 파티션이 없다는 오류가 날 수 있다.
- **RANGE:** 경계 `b`와 행 값 `v`가 끝 공백만 다르고 `v`가 짧은 경우에만 어긋난다. 예를 들어 경계가 `'b '`이고 v가 `'b'`이면, 10.2는 `v = b`로 보아 다음 파티션에 넣고 develop은 `v < b`로 보아 이 파티션을 고른다. v가 길고 경계가 짧으면 두 버전 모두 "다음 파티션"이라 같다.
- 11.2 이상 출발은 같은 VARCHAR끼리의 비교가 develop과 같으므로(§1) F와 L이 없다.

### 8. `ignore_trailing_space` (판정 P)

- 정의: `PRM_FOR_SERVER | PRM_FOR_CLIENT | PRM_FORCE_SERVER | PRM_HIDDEN`, 기본 false(`D:src/base/system_parameter.c:4713-4723`). 10.2에는 이 파라미터가 없다(`git grep IGNORE_TRAILING_SPACE origin/release/10.2 -- src` 결과 0).
- 사용처는 비교 함수들과 radix 정렬(`D:src/storage/btree_sort_radix.cpp:408`, `:415`), 통계 해시(`D:src/storage/btree.c:7419`), 히스토그램(`D:src/optimizer/histogram/histogram_cl.cpp:1289`)이다. **볼륨·카탈로그·로그 헤더 어디에도 기록되지 않는다**(정의와 사용처 전수 grep).
- fastmig radix 정렬은 `no`를 가정한다(`cubrid-fastmig@14079bf:crates/ondisk/src/value/radix_words.rs:97-99` "trailing spaces kept (`ignore_trailing_space` = no)").
- `yes`인 11.x 출발의 데이터는 10.2와 같은 성질이다(같음이 더 넓다). 그래서 develop `no`로 다시 빌드해도 유니크 위반은 없고, F/L의 같은 위험이 생긴다(추론).
- 반대로 **도착 서버를 `yes`로 띄우면** 문제가 생긴다. fastmig가 `no` 순서로 쓴 VARCHAR 인덱스를 `yes` 비교로 읽게 되어, 같은 키가 다른 자리에 있는 트리가 된다. 이것은 도구가 막아야 한다.

## fastmig에 대한 함의

- **plan pre-check (`crates/plan`, `migration_plan.rs`)** — 10.2 출발 티켓(#520)에 넣을 규칙. 비용이 싼 것부터 쓴다.
  1. **U·C·N:** 검사하지 않는다. 비용은 0이다.
  2. **P:** 도착 `$CUBRID/conf/cubrid.conf`(도착 install의 conf)에 `ignore_trailing_space=yes`가 있으면 **거부**한다. 11.x 출발에서는 출발 conf에 `yes`가 있으면 경고하고 F/L 검사를 켠다. 파일 하나를 읽으므로 비용은 무시할 만하다.
     - 지도 Not yet specified "`ignore_trailing_space=yes` DB — 받을지 거부할지"에 대한 추천은 다음과 같다. 출발 `yes`는 받는다(F/L 검사 적용). 도착 `yes`는 거부한다.
  3. **H(10.2 출발만):**
     - 카탈로그 단계: HASH 파티션 키 타입이 CHAR/VARCHAR이고 콜레이션 ID가 {1,3,4,5,6,7}인 테이블을 찾는다. 비용 0.
     - 데이터 단계: 그런 테이블의 각 행에서 키를 꺼낸다. 끝 공백을 자른 뒤 0x20이 남아 있는 행만 골라, 10.2 해시(`weights[32]=0`)와 develop 해시(`=32`)를 `% n`으로 비교한다. 그 행이 들어 있는 실제 파티션과 develop 번호가 다르면 위반이다. 비용은 해당 테이블 힙을 한 번 순차 스캔하는 것이다. 복사 전에 한 번 더 읽는 셈이다.
     - 파티션 키가 단순 컬럼이 아니라 식이면 Rust가 식을 평가해야 한다. 그러므로 **식 키 + 영향 콜레이션 + 문자열 결과이면 거부**하는 것을 추천한다.
     - 위반이 있을 때 할 일(결정 필요, 새 질문 1): (a) 거부, (b) 그 테이블만 develop 해시로 행을 재분배(배치 보존 예외), (c) 옮긴 뒤 엔진에서 `ALTER TABLE … COALESCE/REORGANIZE` 안내.
  4. **F(10.2 출발만):** FK 컬럼이 VARCHAR(binary 콜레이션 제외)인 FK마다 검사한다.
     - 부모 PK/UK 키와 자식 FK 키에서 **끝 문자가 0x20 또는 0x00인 키가 있는지만** 먼저 본다. 끝 공백이 없는 키끼리는 develop에서도 짝이 그대로다(§4).
     - 둘 다 없으면 통과한다. 있으면 그 키들만 develop 같음으로 정확히 맞춰 보고, 짝 없는 자식 수를 보고한다(거부 또는 경고는 결정 필요).
     - 비용은 부모·자식 컬럼을 한 번씩 스캔하는 것이다. 10.2 B-tree leaf를 읽을 수 있다면 leaf 순회로 대신할 수 있다.
  5. **L(10.2 출발만):**
     - RANGE: 카탈로그의 VARCHAR 경계값 중 끝이 0x20/0x00인 것이 없으면 통과한다. 비용 0.
     - LIST: 목록 값에 끝 공백이 있거나 행 값에 끝 공백이 있으면 어긋날 수 있다. 행 값 `v`를 develop 같음으로 그 행이 들어 있는 파티션의 목록 값과 맞춰 보고, 맞지 않는 행을 센다. 비용은 해당 테이블 힙 한 번이다.
- **`crates/index` (radix/비교):** 고칠 것은 없다. develop `no` 규칙이 맞다. P 거부가 그 전제를 지켜 준다.
- **T3 #489 결론의 범위를 정정해야 한다.** "HASH 파티션 행은 배치 보존 그대로"는 11.0 이상 출발에만 맞는다. 리드가 #472 Decisions의 T3 줄에 "(11.0+ 출발; 10.2는 R14 #524)"를 붙이면 된다.
- **#520(10.2 출발 열기 티켓):** 위 3–5를 받아야 한다.

## [VERIFY]

10.2 install이 이 호스트에 있다(`/home/cubrid/release/CUBRID-10.2.18.9024`, `/home/cubrid/release/CUBRID-fastmig-10.2.18`). develop은 `/home/cubrid/release/CUBRID-fastmig-dev`이다.

| # | 주장 | 확인 probe | 기대값 |
|---|---|---|---|
| V1 | 10.2 VARCHAR 유니크 인덱스는 `'a'`와 `'a '`를 함께 받지 않는다 | 10.2 utf8 DB에서 `create table t(c varchar(10) unique); insert into t values('a'); insert into t values('a ');` | 두 번째 INSERT가 unique 위반 |
| V2 | develop은 같은 두 값을 받는다(U 방향 확인) | develop에서 같은 SQL | 두 행 모두 들어감 |
| V3 | HASH 배치가 달라진다(H) | 10.2: `create table h(c varchar(20)) partition by hash(c) partitions 3; insert into h values('a b'),('New York'),('ab');` 다음 파티션별 `select c from h__p__p0`… 를 실행한다. develop에서도 같은 SQL로 파티션 번호를 비교한다 | `'a b'`는 10.2 p0, develop p2(§6 계산). `'ab'`는 같은 번호 |
| V4 | 영향받지 않는 콜레이션은 같다 | V3를 `collate iso88591_bin`, `collate binary`로 반복 | 파티션 번호 diff 0 |
| V5 | 10.2 FK가 끝 공백 짝을 허용한다(F) | 10.2: `create table p(k varchar(5) primary key); create table c(k varchar(5) foreign key references p(k)); insert into p values('a'); insert into c values('a ');` | 성공. develop에서 같은 자식 INSERT는 FK 위반 |
| V6 | LIST 어긋남(L) | 10.2: `partition by list(c) (partition pa values in ('a'))`에 `'a '` INSERT 성공 → fastmig로 옮긴 뒤 develop에서 `select count(*) from t where c='a '`와 `select count(*) from t__p__pa where c='a '`를 비교 | 10.2 INSERT 성공. develop pruning 결과 0, 파티션 직접 스캔은 1 |
| V7 | 도착 conf `yes`에서 fastmig가 쓴 VARCHAR 인덱스 순서가 어긋난다(P) | develop 도착을 `ignore_trailing_space=yes`로 띄우고 `'a'`·`'a '` 키가 있는 인덱스에서 `select … where c='a'` 인덱스 스캔과 풀 스캔을 비교 | 결과가 다르거나 검증기가 순서 위반을 보고 |

## 새 질문

**지금 정확히 서술할 수 있는 것** (티켓 후보):

1. [grilling] 10.2 출발 HASH 파티션의 해시가 어긋날 때 무엇을 할 것인가: 거부, 테이블 단위 develop 해시 재분배(배치 보존 예외), 사후 엔진 REORGANIZE 안내 중 하나. 식 키(+영향 콜레이션)는 거부를 추천한다.
2. [grilling] 10.2 출발 FK 짝 없는 자식, LIST 어긋남 행이 나오면 거부할 것인가, 경고하고 진행할 것인가.
3. [task] V1–V7 실측. 10.2·develop install이 이미 있다. V3/V4는 T3 #489의 18 테이블 스크립트를 10.2로 재실행하면 된다.
4. [task] `ignore_trailing_space` pre-check 구현: 도착 conf `yes`이면 거부, 출발 conf `yes`이면 경고 + F/L 검사.

**아직 흐린 것** (Not yet specified 후보):

- 10.2 NCHAR/VARNCHAR(develop에서 deprecated) 키 HASH 파티션의 해시. NCHAR 재인코딩은 G2 #482 범위이고, 10.2 `mht_get_hash_number`는 NCHAR도 같은 경로를 탄다(`R10:src/base/memory_hash.c:2099-2100`).
- 11.0.0~11.0.5·11.1 출발(범위 밖, G7 #514): CHAR/VARCHAR 혼합 비교와 CHAR B-tree의 VARCHAR prefix 도메인이 develop과 다르다. 범위에 들어오면 다시 본다.
- 끝 0x00 바이트가 실제 데이터에 있는가. 이론상 10.2의 같음에 포함되지만 실측 사례는 없다.
