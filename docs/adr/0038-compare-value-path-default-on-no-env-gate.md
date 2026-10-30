---
status: superseded by 0039
date: 2026-10-30
issue: CBRD-27819 (map #562, ticket #567)
---

# 비교값 비교 경로는 env 게이트 없이 기본 동작한다 — "새 엔진 경로는 default OFF" 규칙의 예외

저장소 규칙("A new engine path is env-gated default OFF unless a ticket records a feature-specific exception")의 예외를 이 ADR 이 기록한다. BIGINT/NUMERIC × DOUBLE/FLOAT 비교를 비교값(ADR 0037)으로 판정하는 경로가 그 대상이다. 이 경로는 env 게이트 없이 항상 켜진다. 판정 지점은 `domain_compare_cmp`·`tp_value_compare_with_error`·해시 키 도메인·NULLIF·`qo_reduce_equality_terms`·리터럴 고정이다. survey 의 `CUBRID_NUMERIC_EXACT_COMPARE` 같은 스위치는 남기지 않는다.

이유는 세 가지다.

1. **목적이 사양 변경이다.** ADR 0037 은 develop 의 틀린 답(CBRD-27797/27799/27703)을 바로잡는 사양 결정이다. 꺼 둔 경로는 이 이슈들을 닫지 못하고, 켠 상태와 끈 상태 두 사양이 공존하게 된다.
2. **클라이언트와 서버가 같은 결정을 내려야 한다.** 비교 방식은 XASL 에 타입 쌍과 method 로만 실린다. 서버는 풀 때 같은 함수로 cmpval 을 다시 고른다(`stx_unpack_decided_compare` → `domain_compare_cmp`). 해시 키의 상 변환도 (소스, 키) 도메인만으로 고른다. 환경 변수는 프로세스마다 다를 수 있다(CAS·csql·cub_server, SA). 그래서 클라이언트가 "conv 없음 + KEEP 경계"로 만든 XASL 을 서버가 DOUBLE cmpval 로 풀면, BIGINT 값을 DOUBLE 로 읽는 잘못된 비교가 된다. 같은 이유로 플랜 캐시 서명에도 env 가 들어가지 않는다.
3. **되돌리기 수단은 PR 이다.** 게이트는 "기본 OFF 로 들여와 나중에 켠다"는 단계적 도입용인데, 이 변경은 CTP 답 파일과 TC(ADR 0037 표)로 고정되는 사양이라 단계가 없다.

## Considered Options

- **env 게이트 default OFF**(저장소 기본): 기각. 위 1·2.
- **시스템 파라미터(cubrid.conf) 로 전환**: 기각. 서버와 클라이언트가 같은 파라미터를 읽는다는 보장은 있지만 두 사양이 남는다. 바인드·플랜 캐시·인덱스 키 범위가 파라미터마다 다른 XASL 을 갖게 되어 표면이 두 배가 된다.

## Consequences

- #569 게이트(optdebug·release, CTP sql·medium + shell 관련 디렉터리)에서 바뀐 답은 모두 ADR 0037 의 경우여야 하며, 목록으로 남겨 TC 티켓(#571)으로 넘긴다.
- 성능 검증(JIRA AC, TPC-H 5%)도 이 기본 경로로 한다(#572).
