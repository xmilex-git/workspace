# PR #8022 단순화 검토

**PR:** [CUBRID/cubrid#8022](https://github.com/CUBRID/cubrid/pull/8022)
**제목:** [CBRD-27510] implement domain collation pin before execution
**작성자:** xmilex-git
**HEAD SHA:** `ca907aaed3d94ed7e1aa87a5463fd064b8f3c208`
**리뷰 일시:** 2026-09-30

> **TL;DR** (Non-blocking): 미사용 메타데이터 외에도 analytic의 함수별 union을 활용하지 않은 추가 상태와, 두 입력 변환에 전체 `RESOLVED_DOMAIN`을 저장하는 과한 표현이 있다. 기존 공간 재사용과 용도에 맞는 저장 크기를 먼저 검토하고, 남는 실행 상태의 수명을 분리하는 방향을 권한다. 이 결론은 구조 단순화 검토이며 PR 전체의 승인 판정은 아니다.

## Summary

- **범위:** #312 본문·댓글과 최신 #374 결정에 비춰 도메인 계획/실행 상태, 비교·변환·키 정책의 복잡성을 검토했다.
- **우선순위:** 기존 공간 재사용 검토, 미사용 필드 제거, 필요한 정보만 저장, 남은 상태 수명 분리, #375의 항목 압축 순으로 권한다.
- **필드 문서:** [현재 구조의 전체 필드·데이터 흐름·소유권 설명](../../../docs/research/pr8022-domain-state-guide.md)을 작성했다.

## Findings

### Non-blocking (should consider)

1. **소비하지 않는 계획 목록과 cold 필드가 남아 있다.** `domain_plan.h:105`의 `pair`는 개별 필드 사용처가 없다. `n_non_cacheable/non_cacheable_refs` 목록은 `domain_plan.c:4693,4788,4821`에서 세고 할당하고 채운 뒤 소비하지 않는다. 세는 코드·할당·실패 검사·채우는 코드까지 제거할 수 있다. `OPERAND_NON_CACHEABLE` 분류와 `resolved_non_cacheable`는 실제 사용되므로 유지한다.
   - 근거: [cold 필드](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_plan.h#L98), [불필요한 목록 할당](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_plan.c#L4788). LP64에서 cold의 `pair`만 제거하면 32 -> 24바이트 배치가 가능하다. N개 item이면 배열 payload 8N바이트 후보 절감이며, 실제 전체 캐시 절감률은 따로 측정한다.

2. **소비자 없는 flags가 남아 있다.** `domain_plan.h:44`의 KEY1/KEY2/ISS/KEEP_LAZY는 정의만 있다. TRUNCATE_OK는 `domain_plan.c:1592`에서 설정하고 읽지 않는다. 해당 비트와 설정을 제거하되 나머지 비트 값은 유지한다. 실제 키 정책과 truncation 동작은 별도 코드에 있다.
   - 근거: [flags 정의](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_plan.h#L42), [설정만 하는 비트](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_plan.c#L1592), 고정 HEAD 전체 `src`의 사용처 검색.

3. **세션 의존성을 개별 읽기의 64비트 마스크로 표현하지만 현재 흐름은 유무만 필요하다.** `domain_plan.c:4871`은 읽기마다 비트를 부여하고 63 이후는 같은 비트로 합친다. 준비 함수와 executor는 `!= 0` 또는 LATE_BIND_SESSION 구분만 사용한다. 계획의 의존성은 `depends_on_session` bool로 전파하고, 실행 `DOMAIN_COMPARE.session_reads`는 제거하는 후보가 적절하다. 변수별 `reads/assigns` 목록은 유지한다.
   - 근거: [마스크 구성](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_plan.c#L4866), `domain_resolve.c:777,2265,2677`, `query_executor.c:22153`. `domain_rules.c:1998`의 비교 정책 동일성 검사도 필드를 읽으므로 함께 수정하고 전역 표의 중복 제거 결과를 확인해야 한다.

4. **준비 전용 오류 3개 필드와 행에서 변경하는 상태가 확정 결과 테이블에 섞여 있다.** `domain_plan.h:456`의 27개 필드 중 deferred errors는 준비 종료에 사라지고, 노드 상태와 scope 캐시는 행 처리에서 변경된다. `frozen`도 상수식 평가 전에 true로 바뀌어 객체 전체의 불변 상태를 뜻하지 않는다. 오류 목록을 resolver의 지역 작업 상태로 옮기고, 노드 상태·scope 캐시는 실행 상태의 별도 inline 멤버로 묶는 편이 역할과 복사 규칙을 명확하게 한다.
   - 근거: [전체 구조](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_plan.h#L456), [frozen의 설정 시점](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_resolve.c#L2688), `domain_resolve.c:2786,2924,2978`. 조기 반환의 오류 정리와 준비 중 fetch 접근을 함께 바꿔야 한다. 중첩 구조만 만들면 메모리 사용량은 줄지 않는다.

5. **scope 캐시의 `conv`와 `target`은 검증에만 사용된다.** 저장·초기화 외 읽기는 `domain_resolve.h:306`의 assert다. 검증 빌드 전용 필드로 한정할 수 있다. `generation`, `scope`, 소유 값, 성공/실패 표시와 최초 사용 시 변환은 유지한다.
   - 근거: [temporary 정의](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_plan.h#L414), [유일한 소비자](https://github.com/CUBRID/cubrid/blob/ca907aaed3d94ed7e1aa87a5463fd064b8f3c208/src/query/domain_resolve.h#L296), `domain_resolve.c:271,3013`. 두 포인터의 LP64 저장 공간은 16바이트이며 최종 sizeof와 행 경로는 변경 후 확인한다.

## Compact Design

기존 함수별 runtime 공간으로 흡수할 수 있는 상태부터 조사한다. 아래 배치는 그 뒤 남는 상태의 책임을 나누는 예시이며 새 구조 추가가 필수는 아니다. 이름은 제안이며 #374의 확정 용어를 이미 바꾼 것은 아니다.

```text
DOMAIN_PLAN                    로드의 읽기 전용 계획
XASL_STATE.resolved_domain      이번 실행의 값·도메인·비교·키 확정 결과
XASL_STATE.domain_execution     노드별 실행 상태 + scope 변환 캐시
DOMAIN_RESOLVE_WORK             준비 함수 안의 보류 오류 목록
```

`DOMAIN_RESOLVE_WORK`는 조기 반환까지 한 정리 경로로 회수한다. 나머지는 기존 owner 할당 방식과 배열 배치를 유지하여 행 접근에 별도 할당·가상 호출·추가 간접 참조를 넣지 않는다. `frozen`을 단순히 함수 끝으로 옮기면 상수 평가의 fetch가 깨지므로 내부 준비 접근과 완료 시점을 먼저 분리해야 한다.

저장 크기 압축은 이미 [#375](https://github.com/xmilex-git/workspace/issues/375)에 남긴 과제다. 작은 공통 item에 번호·flags를 두고 풍부한 고정 도메인/변환 결과는 필요한 노드만 별도 pool에 두는 후보를 비교한다. 가변 항목만 남기거나 `fixed`를 무조건 실행 결과와 union으로 합치면 고정 CAST·피연산자 변환·aggregate·list 소비자 정보가 빠질 수 있다. O(1) 배열 접근을 유지하고 item 수·XASL cache bytes·준비 명령 수·행 경로 비용으로 후보를 선택한다. 봇이 철회한 기존 메모리 지적을 새 결함으로 반복하지 않는다.

| 단계 | 권장 변경 | 기대하는 결과와 한계 |
|---|---|---|
| 0 | analytic 함수별 union 재사용, SUM/AVG 저장 폭 축소, 특수 배열 선택 배정 검토 | 기존 공간과 필요한 정보부터 확인한다. 초기화·PX·layout 검증 후 적용한다. |
| 1 | 미사용 목록·cold pair·flags 제거 | 작은 변경으로 실제 메타데이터와 할당을 줄인다. |
| 2 | 세션 의존성을 bool로, temporary 검증 필드를 검증 빌드로 | 필요 이상으로 저장한 정보를 줄인다. 실제 sizeof를 확인한다. |
| 3 | 준비 오류를 지역 상태로, 노드 상태·scope 캐시를 실행 멤버로 | table의 역할과 PX 복사가 명확해진다. 묶기만 하면 전체 크기는 그대로다. |
| 4 | #375에서 공통 item + 필요한 고정 결과만 저장하는 방식 비교 | 큰 캐시 절감 후보지만 간접 접근·준비 비용이 늘 수 있어 측정 후 결정한다. |

## Reuse Audit

- **구체적 재사용 기회:** `xasl_analytic.hpp:64`에는 함수별 `info` union이 있지만 SUM/AVG용 `operand_coercion`을 `:107`에 공통 멤버로 추가했다. `query_analytic.cpp:101,119,497`의 초기화·작성·소비를 SUM/AVG branch로 옮겨 union 멤버로 둘 수 있는 후보다. LP64에서 기존 union은 최대 16바이트, 추가 상태는 56바이트인 배치이므로 둘을 합치는 것만으로 약 16바이트의 순절감이 가능하다. 실제 sizeof와 pack/unpack·partition 초기화·PX를 검증한다.
- **필요보다 큰 공통 타입:** SUM/AVG 상태는 `RESOLVED_DOMAIN.domain`과 `conv[2]/operand_domain[2]`를 사용하지 않는다. `domain_rules.c:572`는 결과 없는 양측 변환만 만들고 `query_opfunc.c:2458`도 양측만 읽는다. 56바이트 대신 두 converter/target 쌍 32바이트의 저장을 검토한다. 기존 산술 규칙과 helper를 재사용하고 규칙 구현을 복제하지 않는다.
- **일괄 할당의 과잉:** `domain_resolve.c:212`는 모든 node-domain 슬롯에 interpolation-list 포인터와 operand type도 배정한다. 두 특수 배열은 관련 함수가 없는 문장에서는 필요 없으므로 선택 할당/특수 상태 분리가 후보이며, 현재 접근·복사 계약에 맞춰 검증해야 한다. 단순 bind의 큰 공통 item과 REGU union 안의 작은 handle은 ADR-0020 D-323-16/#375의 후속 비교 대상이다.
- **이미 유지한 재사용:** regu/arith/agg/analytic의 `domain_plan`은 기존 `original_domain` 포인터 자리를 교체한다. `domain_plan.c:4751`은 실행 도메인이 없는 alias의 item을 공유하고, `query_aggregate.cpp:898`의 SUM/AVG accumulator 공유도 유지한다. 상수의 노드 `value`를 별도 배열로 옮기는 이유는 `domain_resolve.c:1699`의 PX 교차 heap 정리이며 단순 중복 캐시로 제거하지 않는다.

## Constraints

- 실행 전 확정과 읽기 전용 공유 계획은 유지한다. client cast 전체 제거, 공통 DOUBLE/VARCHAR 통일, 행에서 타입 재추론은 현재 계약을 바꾼다.
- 상수 오류의 도달 가능성 판단, 비교의 변환 순서·오류 타입 이름·rank, 컬럼별 strict-or-keep 혼합 키는 필요한 복잡성이다.
- PX(병렬 worker)는 확정 결정을 복사받고 자신의 값·scope 캐시를 소유한다. `value_states`는 행 fetch도 사용하므로 준비 전용 상태와 함께 제거하지 않는다.
- #374가 이미 없앤 변환기 대형 표·중복 래퍼와 이미 적용한 scope 변환 재사용·타입 쌍 비교 표는 다시 미구현 문제로 지적하지 않는다.

## Verification

- 고정 HEAD의 선언·작성·전체 사용처, 값/오류 정리, worker 복사를 추적하고 #312/#374/ADR의 반례로 단순화 후보를 재검토했다. 저장소 역할 지침에 따라 정적 조사와 문서 검토는 lead가 직접 수행했다.
- 이번 작업에서 엔진 변경·빌드·SQL/CTP·성능 측정은 없다. 위 항목은 구조 개선 제안이며 성능 개선/무회귀의 측정 결과가 아니다.
- 구현 시에는 기존 공간 재사용 -> 미사용 제거 -> 세션 표현 -> 남는 상태 분리 -> 항목 크기 압축 순으로 검증한다. optdebug/release 빌드, 명시적 TC ref의 컨테이너 SQL/medium CTP, NULL·상수 분기·세션 대입·상관 재진입·혼합 키·PX 사례를 확인한다. 크기/행 경로 변경에는 같은 DB의 반복 A/B와 실제 sizeof/offset 검증을 추가한다.

## JIRA Context

CBRD-27510의 목표는 도메인/collation 결정을 실행 전에 끝내는 것이다. 제안은 그 동작을 보존하면서 남은 메타데이터와 수명 혼합을 정리하는 방향이다.
