---
status: accepted
date: 2026-11-10
issue: CBRD-27993
---

# 메모이즈 키는 inner의 XASL을 만들 때 정한다

develop의 서버 쪽 `key_maker`(`memoize.cpp`)는 inner XASL의 술어에서 TYPE_CONSTANT를 모두 모은 뒤, inner 자신의 컬럼과 부질의 결과를 빼서 키를 추정한다. TYPE_CONSTANT는 앞선 스캔의 컬럼, 뒤 스캔의 컬럼, 부질의 결과를 구별하지 않는다. 그래서 무엇이 들어오느냐에 따라 키가 틀어진다. CBRD-27567에서는 상관 부질의 결과가 키에 들어갔다. CBRD-27993에서는 `pt_get_mvcc_reev_range_data`가 range term의 next 체인까지 복사한 where_range로 뒤 스캔 y의 컬럼이 들어갔다. 반면 옵티마이저는 "inner가 평가하는 term이 참조하는 바깥 컬럼"을 키로 정의하고 있었다(`qo_nl_inner_memoize_is_useless`, CBRD-27543).

사용자 결정(2026-11-10 그릴링, CBRD-27993):

- 메모이즈 키는 probe 동안 바뀌지 않는 inner 밖의 값으로, join 순서에서 inner보다 앞선 스캔의 컬럼이다(GLOSSARY "메모이즈 키"). 바깥 질의의 상관 값은 넣지 않는다. 저장소가 그 부질의의 실행마다 새로 만들어지기 때문이다.
- 키는 inner의 XASL을 만들 때 정해 XASL에 싣는다. 상관 부질의 캐시의 키(`pt_prepare_corr_subquery_hash_result_cache`)와 같은 방식이다. 서버의 `key_maker`는 없앤다.
- 수집은 `plan_generation.c`의 NL inner 자리에서 한다. inner가 평가하는 term의 파스 트리를 `parser_walk_tree`로 훑어 바깥 plan 노드의 PT_NAME을 모으고, 그 테이블 `table_info` value_list의 DB_VALUE로 바꾼다. 파스 트리 훑기는 부질의의 GROUP BY, HAVING, 분석 함수, CONNECT BY까지 내려가므로, CBRD-27567이 그 모양에 건 memoize 거부를 풀 수 있다.
- optdebug 빌드는 서버에 기존 `key_maker` 훑기를 남겨, 앞선 스캔의 val_list를 가리키는 슬롯이 모두 키에 있는지 assert한다.

## Considered Options

- **런타임 key_maker에 화이트리스트 추가**(앞선 XASL 노드의 val_list를 가리키는 슬롯만 남김): 기각. "모은 뒤 거른다"는 구조가 남는다. 앞선 스캔과 뒤 스캔의 구분을 실행 시점에 val_list 주소로 다시 추정하게 된다.
- **원인 term만 차단**(`pt_get_mvcc_reev_range_data`에서 next 체인 끊기): 기각. 이번 경로만 막는다. key_maker는 인덱스 key range를 직접 보지 않고 where_range를 통해서만 range term의 바깥 값을 본다. 그래서 where_range에 의존하는 상태가 그대로 남는다.
- **생성된 XASL을 훑어 수집**(A2): 기각(3라운드). 거부를 풀면 BUILDLIST와 CONNECTBY의 regu 필드 24개를 손으로 열거해야 한다. CBRD-27567은 이런 열거에서 GROUP BY를 놓쳤다.
- **옵티마이저의 key segment 사용**: 기각. `set_seg_expr`는 PRIOR, CONNECT_BY_ROOT, SYS_CONNECT_BY_PATH 안에서 멈춘다.
- **바깥 질의 상관 값도 키에 넣기**: 기각(3라운드). 결과는 같고(`enc-key` 통과) 비교 비용만 늘며, 파스 트리 쪽에서 상위 질의의 심볼까지 찾아야 한다.
- **put이 probe 키를 재사용**: 이것만으로도 결과는 맞는다(`overkey-put-probe` 통과). 그러나 키에 뒤 스캔의 낡은 값이 남아 hit가 거의 나지 않는다. 단독 수정으로는 기각했다.

## Consequences

- 검증: `docs/tla/CBRD-27993/` `RESULT: OK`(2026-11-10, run `.git_ignored_dir/scratch/tla/CBRD-27993-20261110-130842-2300886`). 저장소를 실행마다 새로 만들지 않으면서 상관 값을 키에서 빼면 C1이 깨진다(`mutant-storage-kept`). C1(memoize off와 같은 결과)과 C2(답하는 키는 완전)가 키 = 바깥 값으로 성립한다. 뒤 스캔 값이 키에 있는 develop(`mutant-develop`)과 바깥 값이 빠진 키(`mutant-missing-outer`)는 C1을 깬다.
- XASL 형식이 바뀐다. inner 노드에 키 배열과 도메인이 실리고, xasl_to_stream, stream_to_xasl, query_dump가 따라 바뀐다.
- 키의 완전성은 XASL 생성 쪽 수집이 inner가 읽는 바깥 값을 빠짐없이 보는 데 달려 있다. 인덱스 key range, 술어, inner의 상관 부질의, 그리고 inner가 읽는 상관 파생 테이블(바깥 행마다 다시 만들어진다, MAP.md D24)이 그 대상이다.
