# CUBRID 매뉴얼 집필 스타일 가이드 — CBRD-26722 (parallel query & memoize)

- 티켓: [#149](https://github.com/xmilex-git/workspace/issues/149) (맵 [#144](https://github.com/xmilex-git/workspace/issues/144))
- 출처: PR [#753](https://github.com/CUBRID/cubrid-manual/pull/753) diff·리뷰, 머지된 [#723](https://github.com/CUBRID/cubrid-manual/pull/723) diff·리뷰 코멘트 ~90건, `/home/cubrid/cubrid-manual` (`develop`+`parallel_scan_all`) 관례 전수 조사.
- 지위: **집필 티켓 #152(parallel)·#153(memoize)의 규범.** 이 가이드와 어긋나는 서술은 리뷰에서 되돌린다.

## 1. 언어·어조

### 한국어 (ko가 원본 — 매뉴얼은 한국어 우선 집필 후 영어 미러)

- **한다체.** 모든 본문 문장은 `-다`로 끝난다. 합니다체·명령형(~하십시오) 금지.
  - 기능 정의 공식: "X(English Name)은/는 …하는 기능이다."
  - 조건·폴백: "다음 조건 중 하나라도 해당되면 …이 적용되지 않으며, 단일 스레드 방식으로 실행된다." / "다음 조건을 모두 만족해야 한다."
  - 기본값: "기본값은 \*\*100\*\*\ 이며, 최소값은 \*\*0\*\*, 최대값은 \*\*1000\*\*\ 이다."
  - 상호 참조: "자세한 내용은 :ref:\`parallel-query\`\ 를 참고한다."
  - 권장: "…하는 것을 권장한다."
- **"질의", "쿼리" 금지** (#723 리뷰어 교정, 전역 적용됨).
- 영문 기술 용어는 첫 등장에 "한글(English)" 병기 — "선택도(selectivity)", "임시 결과 리스트(list file)". mergeable list, row-by-row, gather, BUILDVALUE처럼 번역이 어색한 것은 영문 그대로 쓴다.
- 닫힌 목록에 막연한 "등"을 붙이지 않는다 (#723 리뷰어 교정).
- 개발자 전용 내부 용어(if_pred 등)는 사용자 언어로 풀어 쓴다 — "대상 테이블을 스캔하며 평가할 수 없는 조건절". XASL 같은 내부명 노출은 최소화.
- 목록 도입 문장은 마침표로 끝낸다(콜론 아님) — #753의 최신 관례.

### 영어

- 현재시제 평서문, ko와 문단 단위 대응. "Parallel Scan splits a single scan input across multiple worker threads that process it concurrently."
- **미국식 철자** (optimize, parallelize, synchronization). #753 신규 en 프로즈에 섞인 영국식(parallelised, materialises)은 계승하지 않고 교정한다.
- 조건: "X is not applied — and falls back to a single-threaded scan — if any of the following hold:"

## 2. 문서·섹션 구조

- 파일 첫머리: `:meta-keywords:` / `:meta-description:` 필드 유지.
- 헤딩 레벨: 페이지 박스 제목 `*`(over+under, `*_index.rst` toctree 래퍼 전용) → `=`(H1) → `-`(H2) → `^`(H3). `"` 레벨은 쓰지 않는다(#753이 `^`로 승격). 밑줄 길이는 제목 폭 이상이면 됨(한글은 넉넉히).
- `^` 아래 세분은 실제 헤딩 대신 **굵은 줄 의사-헤딩**: `**활성화 조건**`, `**예제**`, `**Additional list-scan constraints**`.
- 앵커: 개념·절은 kebab-case `.. _parallel-hash-join:`; **파라미터 앵커는 snake_case 파라미터명 그대로** `.. _memoize_memory_limit:`. 앵커는 헤딩(또는 굵은 파라미터명) 바로 위, 앞뒤 빈 줄. 힌트 개명 시 앵커도 개명하고 구 앵커는 남기지 않는다.
- 기능 절 내부 순서(#753 정규형): 도입 문단 → 공통 제약 조건 → 종류별 하위 절(앵커+도입+"추가 제약" 의사-헤딩+불릿+SQL 예제+선택적 note) → 성능 고려사항("효과가 크다" 목록 → "저하될 수 있다" 목록) → 최적화 하위 절 → trace/프로파일링 하위 절 → (페이지 말미) 처리량 규칙 절.
- 새 페이지를 만들 경우 `{en,ko}/sql/index.rst` 요약 불릿 + `*_index.rst` toctree에 등록. (이번 여정은 신규 페이지 없음 — 갭 감사 D2: memoize는 tuning.rst 절.)

## 3. RST 형식 규칙

- **`.. versionadded::`/`.. versionchanged::` 사용 금지** — 전체 매뉴얼에 0건, 버전별 브랜치 체계라 도입하지 않는다. 버전 언급이 꼭 필요하면 본문 프로즈로.
- `:ref:` 뒤에 조사·글자가 붙으면 백슬래시-공백 이스케이프: `` :ref:`parallel-query`\ 를 ``. 굵은 글씨 뒤도 동일: `**100**\ 이며`. (리뷰에서 강제되는 위생 항목.)
- 파라미터 링크는 명시 텍스트형 `` :ref:`max_parallel_workers <max_parallel_workers>` ``, 절 제목 그대로면 bare `` :ref:`parallel-query` ``.
- SQL 입력은 `.. code-block:: sql`; trace·플랜·csql **출력은 언어 태그 없는 `::` 리터럴 블록**. conf 스니펫은 "다음은 … 예제이다. ::" 후 들여쓴 리터럴.
- 주의·해석 가이드는 `.. note::` (연속 여러 개 허용, 파라미터 들여쓰기 레벨에 중첩). `.. warning::`은 드묾 — 데이터 손상급에만.
- 불릿은 `*` + 공백 3칸(`*   `), 중첩은 4칸 들여쓰기. 굵게: 기능명·파라미터명·힌트명·trace 필드명·핵심 수치(`**2 이상**`). 기울임: 메타변수(*degree*).
- 표: config 요약은 grid table, 처리량 규칙 등 신규 표는 `.. csv-table::` + `:header:`/`:widths:`.

## 4. 파라미터 서술 패턴 (config.rst)

새 파라미터는 **세 곳**을 갱신한다: ① `.. _cubrid-conf:` 마스터 표(Category/Applied/Session/Type/Default/Dynamic Change — 적용 대상·동적 변경 여부는 표에만, 본문에 재서술하지 않음) ② 해당 카테고리의 타입·범위 grid table ③ 본문 항목. 본문 템플릿:

```rst
.. _memoize_memory_limit:

**memoize_memory_limit**

    **memoize_memory_limit**\ 는 …를 설정하는 파라미터이다. 단위 문장(byte형일 때: B, K, M, G, T …).
    기본값은 **2M**\ 이며, 최소값은 **0**\ 이다.

    이 파라미터가 **0**\ 으로 설정되면 …가 비활성화된다.   ← 특수값 의미는 별도 문장

    자세한 내용은 :ref:`memoize`\ 를 참고한다.

    다음은 …로 설정하는 예제이다. ::

        memoize_memory_limit=8M

    .. note::

        …
```

- 기본값이 앞으로 바뀔 수 있는 수치는 기능 페이지 프로즈에 하드코딩하지 않는다(#723 리뷰어 교정) — config.rst 항목에만 두고 기능 페이지는 참조.
- 0/1/2+ 같은 경계값 의미는 전부 명시적으로 쓴다("0 이상의 정수이며, 0이나 1로 지정하면 비활성화된다").

## 5. 힌트 서술 패턴 (tuning.rst)

세 곳: ① `SQL 힌트` 절의 문법 리터럴 블록에 파이프로 추가 ② 앵커 달린 불릿 항목 ③ 기능 페이지에서 언급.

```rst
.. _no-parallel-hash-join:

*   **NO_PARALLEL_HASH_JOIN**: 해당 질의 블록에서 병렬 해시 조인을 사용하지 않도록 하는 힌트이다. 자세한 내용은 :ref:`parallel-query`\ 를 참고한다.

    .. code-block:: sql

        SELECT /*+ NO_PARALLEL_HASH_JOIN */ ... ;
```

- 공식: "…하는/…하지 않도록 하는 힌트이다." 인자는 기울임(*degree*)에 "*degree* 는 …이며" 해설.
- 우선순위 문장 패턴: "**PARALLEL** 힌트와 같이 사용하는 경우에는 **NO_X** 가 우선 적용된다."
- 예제의 힌트는 실제 파서가 수용하는 것만(#723 리뷰어 교정 — 가짜 힌트 금지).
- memoize는 **힌트가 없다** — "끄는 방법은 `memoize_memory_limit=0`이 유일하다"를 명시하는 것이 곧 문서화다.

## 6. Trace/프로파일링 표기

- 입력: `.. code-block:: sql` 안에 `csql> ;trace on` 한 줄 + 빈 줄 + 프롬프트 없는 SQL(`/*+ PARALLEL(4) RECOMPILE */`처럼 RECOMPILE 동반). csql 프롬프트는 세션 명령에만 보인다.
- 출력: 별도 `::` 리터럴 블록에 `Trace Statistics:` 트리. **결과 행(result set)은 싣지 않는다.**
- 출력 뒤 필드 해설을 굵은 용어 불릿 범례로: `*   **parallel workers**: …` (중첩 불릿 허용), 해석 가이드는 `.. note::`.
- **trace 문자열은 실제 출력 그대로 인용한다**: `temp time`("list time" 아님), `row by row`(공백; 서술어로는 row-by-row 가능), `buildvalue`(구명 `gather: count` 금지). 실측과 다른 필드(`key time` 류)를 창작하지 않는다.

## 7. 예제 정책 ★ (이번 여정의 핵심 규범)

- **모든 예제는 수록 전에 mandb(포트 1701, `cubrid_port_id=1701`)에서 실행해 통과·출력 확인한다.** 실행하지 않은 예제 금지. 절차는 §8.
- **데이터셋: #753 방식의 ad-hoc 범용 스키마** (`large_table`, `orders`, `customers` …) + 자기완결 셋업 블록(CREATE TABLE + 대량 INSERT + `UPDATE STATISTICS`, 기대 통계를 `-- Total pages in class heap: 4215 (약 66MB…)` 주석으로). demodb는 규모가 작아 병렬 활성 임계(2,048페이지)를 못 넘으므로 이 주제에는 쓰지 않는다.
  - **대량 데이터 생성은 recursive CTE를 쓰지 않는다(너무 느림).** 카탈로그 테이블 크로스 조인 방식으로 쓴다: `INSERT INTO large_table SELECT … FROM db_class a, db_class b, db_class c LIMIT 10000000;` — 셋업 블록에 수록하는 형태도 이 방식이다(사용자 확정).
  - 셋업 블록은 페이지에서 한 번(처리량 규칙 예제)만 전체 수록하고, 나머지 예제는 동일 스키마를 전제로 재사용한다.
- **trace 출력 수치 정책: 실측 원본 그대로 수록한다(사용자 확정).** 반올림·정리·창작 없이 mandb 실행 출력을 verbatim으로 붙인다. 실측에 없는 필드·라인 창작은 당연히 금지. (#753의 이상화된 예제 수치는 실측본으로 교체 대상.)
- 모든 예제 블록 첫 줄은 의도 주석 1줄: `-- 병렬 스캔이 적용되지 않는 예`. 뻔한 내용을 재진술하는 2번째 주석은 달지 않는다(#753이 일괄 삭제한 패턴).
- 긍정 예와 부정 예(적용/미적용)를 짝으로 보여준다.
- memoize 예제는 trace에 `MEMOIZE` 블록이 **hit>0으로 실제 출력되는** 질의여야 한다(hit 0이면 블록 자체가 안 나옴 — 검증 필수 지점).

## 8. 예제 실행 검증 절차

1. 환경은 티켓 [#151](https://github.com/xmilex-git/workspace/issues/151)이 구축한 mandb(11.5 develop 빌드, `cubrid_port_id=1701`, broker 36100-36199)를 쓴다. 서버 기동·정지는 반드시 `cubrid-server-control` 스킬 경유. 포트 상태는 `just ports`로 확인.
2. 빌드·서버 기동·질의 실행·trace 채취는 **sonnet 서브에이전트에 위임**한다(레포 규칙).
3. 예제별 검증 기록(실행한 SQL, 실측 출력 원본)을 집필 티켓 코멘트에 남긴다 — 문서의 정리본과 실측본이 어긋나는지 리뷰에서 대조 가능해야 한다.
4. 스크래치는 `/tmp` 금지 — 이 레포 `.git_ignored_dir/scratch/`.
5. **렌더링 검증(사용자 확정, 애자일 조항)**: 집필 중 sphinx livehtml로 매뉴얼을 빌드하고 **playwright로 렌더링 결과를 확인**한다 — 새로 쓴 절이 주변 절과 다르게 렌더링되는 이상점(표 깨짐, 이스케이프 누락, 앵커 미해석 등)을 발견하면 그 자리에서 고치고, **그 유의점을 이 가이드에 추가한다.** 이 가이드는 living document다 — 집필 티켓이 발견한 규범은 §12에 append한다.

## 9. ko/en 대칭 규칙

- 파일 경로·앵커·절 순서·예제·굵기/`:ref:` 위치까지 **문단 단위 미러**. 앵커는 양 언어 공유(언어 무관 타깃).
- **ko를 먼저 확정하고 en을 그로부터 작성한다** (매뉴얼의 역사적 방향).
- #753에서 발견된 비대칭 결함을 반복하지 않는다: en에만 있는 제약 불릿, en/ko 목록 항목 불일치(ORDERBY_DESC 유무 등), 한쪽에만 있는 note. **집필 완료 시 절 단위로 en↔ko 불릿 수·note 수를 기계적으로 대조한다.**

## 10. 커밋·PR 관례

- 작업 브랜치: `cbrd-26722-115-docs` (origin/develop 기반). 의미 단위 커밋(파라미터/힌트/절 단위).
- 커밋 제목: `[CBRD-26722] <요약>` — 매뉴얼 레포는 `[CUBRIDMAN-NNN]`도 통용되나 이 여정은 엔진 티켓 키로 통일(맵 결정).
- PR: base `develop`, ko+en 같은 PR, 제목 `[CBRD-26722] …`, 본문에 JIRA 링크 + 한국어 요약 1-2문장. CI 봇이 ko/en 프리뷰 링크를 단다 — 머지 전 프리뷰로 렌더링 확인.

## 11. #723 리뷰어 교정 체크리스트 (리뷰 예방)

1. 질의 ○ / 쿼리 ✕.
2. 기본값을 기능 페이지 프로즈에 하드코딩하지 않는다.
3. 닫힌 목록의 "등" 삭제.
4. 경계값(0/1/2+) 의미를 명시적으로.
5. 내부 엔진 용어를 사용자 언어로.
6. 기능명을 과잉 수식하지 않는다(제한은 프로즈로).
7. 예제 힌트는 실존하는 것만.
8. 절 제목은 상위 맥락 중복 제거("병렬 질의 처리" → "병렬 실행").
9. RST 이스케이프 공백 위생(`**0**\ 으로`).

## 12. 집필 중 발견한 유의점 (living — 집필 티켓이 append)

<!-- livehtml+playwright 렌더링 검증에서 발견한 이상점과 그 교정 규범을 여기에 추가한다. -->

- **게이트·제약 조건은 사용자 행동으로 번역해서 쓴다 (집필 티켓 #152, 사용자 교정).** 엔진 내부 게이트(예: "선택도가 히스토그램 산출일 것")를 내부 조건 나열로만 녹이지 말고, ①사용자가 관찰하는 결과("통계가 없으면 자동 병렬 인덱스 스캔이 선택되지 않는다")와 ②그때 해야 할 행동("**UPDATE STATISTICS** 문으로 통계를 갱신한다")을 명시적 문장으로 함께 쓴다. 전제조건이 기능의 사용 가능 여부를 통째로 좌우하는 경우(통계 존재, 파라미터 활성화, 재시작 필요)는 불릿 속 수식어가 아니라 독립 문장으로 승격한다.

- **매뉴얼에 없는 신조어를 만들지 않는다 (집필 티켓 #152, 사용자 교정 2건째).** 집필 중 새 개념을 지칭할 어휘가 필요하면, 먼저 매뉴얼 전체를 grep해서 기존 어휘를 찾아 그것만 쓴다. 실제 사례: trace 출력의 워커별 통계 줄을 "서브라인", 항목을 "라인"이라고 썼는데 매뉴얼 전체에 두 단어 모두 선례가 0건 — 기존 어휘는 "**항목**", "**병렬 처리 상세 정보**", "~가 추가로 출력된다"였다. 신조어가 정말 필요하다고 판단되면 임의로 도입하지 말고 사용자에게 먼저 확인한다.

- **"실체화(materialization)"는 매뉴얼 어휘가 아니다 (집필 티켓 #152, 사용자 교정 3건째).** derived table이 임시 결과로 만들어지는 것은 매뉴얼의 기존 어휘인 **View Merging**\ 의 반대로 서술한다 — "병합되지 않는 derived table에서 임시 결과 리스트가 생성된다". 그리고 임시 결과 생성을 강제하는 표준 수단은 **NO_MERGE 힌트**\ 다 — derived table 실체화가 필요한 예제·서술에서는 NO_MERGE를 함께 언급한다.

