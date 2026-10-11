# PR #8022 리뷰 코멘트 초안

기준 HEAD: `ca907aaed3d94ed7e1aa87a5463fd064b8f3c208`. 로컬 초안이며 GitHub에 게시하지 않았다. 구조 단순화 제안이며 기존 메모리 코멘트/#375는 중복 게시 대상에서 제외했다.

## src/xasl/xasl_analytic.hpp:107

NIT: `operand_coercion`은 SUM/AVG에서만 쓰는데 모든 analytic 노드의 공통 멤버로 들어가 있습니다. 기존 함수별 `info` union의 SUM/AVG 멤버로 옮기는 건 어떨까요? 현재 무조건 하는 초기화는 SUM/AVG 조건 안으로 옮겨 percentile 등의 활성 union 멤버를 보존하고, partition 재시작과 PX 경로도 함께 확인하면 좋겠습니다.

## src/xasl/xasl_aggregate.hpp:86

NIT: SUM/AVG의 `operand_coercion`은 두 입력의 converter/target만 사용하므로 `RESOLVED_DOMAIN`의 결과 도메인과 세 번째 입력 공간이 비어 있습니다. 저장은 두 입력만 담고 기존 산술 규칙과 coercion helper를 계속 재사용하는 형태를 검토하면 어떨까요? Hash GROUP BY와 worker의 accumulator-domain 전달 경로도 같은 표현으로 맞춰야 할 것 같습니다.

## src/query/domain_resolve.c:217

NIT: interpolation list와 aggregate operand type용 배열도 모든 `node_domain_index`에 맞춰 함께 할당합니다. 관련 함수가 없는 문장에서는 이 배열들을 배정하지 않는 선택지를 검토하면 어떨까요? 현재 공통 인덱스와 accessor/PX 복사 계약을 함께 맞추되, 행마다 lookup하는 별도 map은 피하면 좋겠습니다.

## src/query/domain_plan.h:105

NIT: `DOMAIN_PLAN_ITEM_COLD.pair`를 개별적으로 설정하거나 읽는 곳이 보이지 않습니다. 이 필드를 빼고 cold 항목 크기를 줄이는 건 어떨까요?

## src/query/domain_plan.c:4788

NIT: `non_cacheable_refs`는 개수를 세고 배열을 채우지만 이후 소비하는 경로가 없습니다. `resolved_non_cacheable`와 operand 분류는 유지하고 이 목록과 관련 할당·검사만 제거하면 어떨까요?

## src/query/domain_plan.h:44

NIT: KEY1/KEY2/ISS/KEEP_LAZY는 정의 외 사용처가 없고 TRUNCATE_OK도 설정만 하고 읽지 않습니다. 실제 키/변환 정책은 유지하면서 사용하지 않는 비트와 설정을 정리하는 건 어떨까요?

## src/query/domain_plan.c:4871

NIT: 세션 읽기마다 비트를 배정하지만 준비 함수는 의존성이 있는지만 검사하고 있습니다. `resolved_session_reads`와 원소 비교의 의존성은 bool로 표현하고, 실행 비교에는 마스크를 복사하지 않는 건 어떨까요? `domain_compare_equal()`의 필드 비교도 함께 정리해야 할 것 같습니다.

## src/query/domain_plan.h:483

NIT: `deferred_errors`는 `qexec_resolve_domains()`에서만 사용하고 반환 전에 해제하는 상태입니다. 조기 반환의 정리 경로를 함께 정리하여 resolver의 지역 작업 상태로 옮기는 건 어떨까요? 노드 도메인과 scope 캐시도 실행 중 변경되는 상태로 묶으면 worker 복사 규칙을 읽기 쉬울 것 같습니다.

## src/query/domain_plan.h:421

NIT: temporary의 `conv`와 `target`은 저장한 뒤 재사용 경로의 assert에서만 읽습니다. assert는 유지하면서 이 두 필드를 검증 빌드에만 두는 건 어떨까요?
