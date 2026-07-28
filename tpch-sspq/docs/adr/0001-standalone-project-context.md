# TPCH-SSPQ는 저장소 루트 컨텍스트에서 분리한 독립 컨텍스트로 운영한다

이 저장소의 도메인 규칙(`docs/agents/domain.md`)은 single-context — 루트 `CONTEXT.md` 하나와 루트
`docs/adr/` 하나 — 였고, 지금까지 그 안의 용어와 ADR은 전부 **CUBRID 엔진 개발**을 대상으로 한다.
TPCH-SSPQ는 대상이 다르다. CUBRID뿐 아니라 PostgreSQL이 동등한 비교 대상이고, 결정의 대부분이
엔진 코드가 아니라 **측정 방법론**(쿼리 정본, 캐시 레짐, 게이트 검정력)에 관한 것이다. 이것을 루트
컨텍스트에 합치면 `Query Stream`·`Engine Dialect` 같은 비교 전용 용어가 CUBRID 개발 용어와 섞이고,
루트 ADR 번호열(0001~0007, 전부 CUBRID 엔진 결정)에 성격이 다른 결정이 끼어든다. 그래서 TPCH-SSPQ는
**의도적으로 분리한 독립 컨텍스트**로 두고, 용어는 `tpch-sspq/CONTEXT.md`에, 결정은
`tpch-sspq/docs/adr/`에 자체 번호열로 둔다.

## Considered Options

- **루트 컨텍스트에 흡수**: 규칙 위반은 없지만 두 도메인의 용어·결정이 한 파일에서 경쟁한다.
  루트 ADR을 읽는 사람은 CUBRID 엔진 결정을 기대하는데 측정 방법론이 섞인다.
- **문서만 `docs/`에 평면 배치**: 기존 `report-*`/`design-*` 관례와는 맞지만, 이 프로젝트는 스키마·
  쿼리셋·하네스처럼 마크다운이 아닌 산출물을 함께 관리해야 해서 `docs/`(서술형 전용)에 담기지 않는다.

## Consequences

- 루트 `CONTEXT.md`와 루트 `docs/adr/`에는 이 프로젝트 항목을 **추가하지 않는다**. 루트 ADR 다음 번호는
  TPCH-SSPQ와 무관하게 `0008`로 남는다.
- 두 컨텍스트에 같은 용어가 다른 뜻으로 존재할 수 있다. 프로젝트 문서에서 용어를 쓸 때는
  `tpch-sspq/CONTEXT.md` 정의가 우선이며, 루트 정의를 끌어 쓸 때는 출처를 명시한다.
- 분리는 문서 경계일 뿐이고 운영 규칙은 상속한다 — `/tmp` 스크래치 금지, 대용량 산출물 git 제외,
  서버 제어는 `cubrid-server-ctl.sh` 래퍼, `CUBRID_SSOT.md`의 측정 함정 목록은 그대로 적용된다.
- 이 프로젝트가 CUBRID 엔진 변경을 유발하면, 그 결정은 여기가 아니라 **루트 `docs/adr/`**에 남긴다.
