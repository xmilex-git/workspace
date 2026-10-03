---
status: accepted
date: 2026-10-03 (2026-09-22 판 #320 과 정정 D-335-08·D-336-B·#339·D-345-04 를 최종 구현 기준으로 다시 씀)
basis: CUBRID/cubrid#8022 HEAD 23a5e5561 (develop 15e7dc8b5 동기화)
locked-by: xmilex-git/workspace#335 D-335-08 (2026-09-23, 사용자 승인) · #336 D-336-A·B (2026-09-24) · #345 D-345-04·06 (2026-09-28, 사용자 (가))
---
# 바인드 값은 클라이언트가 develop 대로 캐스트하고, 실행 전 도메인 확정은 실행이 소유하는 값 배열에 POS 참조마다 값을 둔다 (입력 배열 불변, 해제는 만든 스레드, 워커는 자기 사본)

클라이언트(CAS·csql·PL)는 기대 도메인이 있는 바인드 값을 develop 호출 자리에서 develop 규칙대로 캐스트해 보낸다: `pt_set_host_variables`(`parse_dbi.c`)와 `do_cast_host_variables_to_expected_domain`(`db_vdb.c`)의 `tp_value_cast_preserve_domain`(CHAR 도메인의 VARCHAR 값은 원 값 유지), auto-param 과 데이터 타입이 있는 호스트 변수는 `pt_make_regu_hostvar` 꼬리의 `tp_value_cast`. 서버의 실행 전 도메인 확정은 값을 도메인 계획의 도메인으로 바꾸지 않는다 — 가변 POS 는 받은 값의 도메인(바인드 도메인)을 확정 도메인 표에 기록하고, 고정 도메인 POS 는 "값 타입 = 계획 도메인" 을 전제로 읽는다(D-335-08, D-336-A·B).

값의 소유는 실행이다. `qexec_init_resolved_domains` 가 값 배열·확정 배열·실행 도메인 배열을 한 블록으로 할당하고, 입력 배열은 `resolved_domain.in` 으로 빌려 둔 채 바꾸지 않는다(const; SA_MODE 에서는 클라이언트 `parser->host_variables` 그 자체다). 실행이 읽는 `vd.dbval_ptr` 는 `resolved_domain.vals` 를 가리킨다. 바인드는 `qexec_share_value` 로 payload 를 공유하고, 실행 전 확정이 만든 변환값 — 확정 비교의 상수 쪽(`DOMAIN_COMPARE.value[side]`), 상수식 결과, 인덱스 키 상수(`RESOLVED_KEY_ELEMENT.value`), ALL/SOME 상수 원소 — 만 실행이 소유한다. 같은 `?`(`val_pos`)를 다른 도메인이나 `DOMAIN_PLAN_CONSUMER_CONVERTS` 로 읽는 regu 는 POS 참조(`DOMAIN_PLAN_ITEM.ref`)가 갈리고(`n_refs ≥ dbval_cnt`), 원 값은 불변이다. 해제는 만든 스레드가 실행 종료 때 `qexec_clear_resolved_domains` 로 하고 `vd.dbval_ptr` 를 `in` 으로 되돌린다. PX 워커는 `qexec_copy_resolved_domains` 가 값 payload 를 워커 힙에 clone 하고 워커가 자기 사본을 해제한다(교차 mspace free 없음).

결정 원문: #312 D-M4(원안), #318 D-318-03·06, #323 D-323-03·04, #335 D-335-08(정정), #336 D-336-A·B, #339 D-339-01, #345 D-345-04·06, #371 B.

## Considered Options

- **클라이언트 캐스트를 지우고 실행 전 확정이 `val_pos` 마다 값을 바인드 도메인으로 변환**(원안 D-M4, 2026-09-22 판의 본문): **철회**(D-335-08, 사용자 승인 2026-09-23). ① XASL 캐시 공유 — 계획 키는 해시 텍스트의 SHA-1 뿐이고 auto-param 과 사용자 `?` 가 같은 `?:N` 으로 찍혀 리터럴 문장과 바인드 문장이 계획 하나를 쓴다; 캐스트 결정을 계획에 실으면 먼저 컴파일한 형태가 답을 정한다(`bind_misc`·`bug_bts_4966`·`zero_date_format`). 클라이언트는 자기 문장의 기대 도메인을 알므로 문장마다 캐스트하면 캐시와 무관하다. ② OBJECT 바인드 — CS 모드에서 MOP 는 OID 로 오고 OBJECT 목표 변환(클래스 검사·뷰 객체)은 클라이언트 전용 코드다(`tp_value_cast_internal` 의 `#if !defined (SERVER_MODE)`). 클라이언트 캐스트와 서버 확정이 같은 변환기(ADR 0022)를 부르므로 "규칙 두 벌" 문제는 없다.
- **입력 `vd.dbval_ptr[]` 를 제자리 변환**: 기각. SA_MODE 별칭이 클라이언트 값을 바꾸고, 결과 캐시 키(`params.vals`)·DBLINK·파티션 프루닝은 원 값 기준이어야 하며, 연결 스레드가 만든 값을 PX 워커가 해제하던 교차 mspace free 힙 손상(L-46)의 소유 문제를 다시 연다.
- **한 `?` 의 다중 참조를 "가장 좁은 공통 도메인" 1회 변환으로**: 기각. 등식 축약(`qo_reduce_equality_terms`: `a = ? AND a = b` → `b = ?`)과 UNION 가지 푸시다운(`pt_copypush_terms`)이 같은 `val_pos` 를 다른 형제 옆에 복사해 참조별 도메인이 실제로 갈린다(#323 탐침).
- **리터럴 문장과 바인드 문장의 계획을 캐시 키 접미사 `;host_var_cnt=N` 로 가르기**(#336 결정 ②): 넣었다가 **철회**(D-345-04, 사용자 (가)). upstream shell 에서 결과 캐시 공유(`cbrd_25035`)와 plandump 의 sha1·SQL_ID(`cbrd_20149_*`)를 바꿨다. 캐시 키는 develop 과 같다.
- **실행 전 확정의 변환 실패를 일률 -494 또는 일률 NULL 로**: 기각. 실패 정책은 항목의 문맥별 develop 그대로다(산술·함수 인자 `return_null_on_function_errors`, 대입 -494, 비교 keep).

## Consequences

- 캐스트의 손실 정책(정수 목표 반올림 등)은 develop 그대로 클라이언트에서 일어나고 -494 시점도 develop 과 같다. 가변 POS 의 값은 캐스트 없이 그 타입이 답이다(`id IN (?, ?)` 에 1, 2.5 → 1행).
- 계획을 함께 쓰는 문장(리터럴 형태와 바인드 형태, CTE 부질의)이 출력 목록의 바인드(UPDATE SET 값, `DEFAULT (다른 컬럼)`)에 다른 타입을 보내는 자리만 실행 전 확정이 develop 의 튜플 캐스트(`tp_value_auto_cast`)로 한 번 바꾼다(`DOMAIN_PLAN_LIST_BIND`, `qexec_convert_list_bind`, D-345-06). 캐스트가 거부한 값은 develop 처럼 튜플 쓰기에서 오류다. 비교·키는 바인드 값으로 확정하고 대입은 속성 도메인으로 바꾸므로 그 밖의 자리는 없다.
- `host_var_expected_domains[]` 는 남는다 — prepare 응답의 파라미터 메타, PL/CSQL 보고(`method_callback.cpp`), 바인드 피크 재계획의 입력이다. PL/CSQL 선언 타입 전달(`host_var_decl_domains[]`)은 구현하지 않았다(#339).
- 변환할 것이 없는 리터럴·상수식 쪽은 복사하지 않고 행이 그 값을 비교하며, 바인드 쪽은 공유 사본이다(#371 B). 공유 바인드를 제자리에서 바꾸던 키 상한 리밋·ORDER BY LIMIT 읽기도 지역 값으로 바뀌었다.
- 되돌리는 길: 값 소유는 `qexec_init_resolved_domains`/`qexec_clear_resolved_domains` 한 쌍에 있어 독립 커밋으로 되돌릴 수 있고, 되돌리면 SA_MODE 별칭 문제가 돌아온다. 클라이언트 캐스트는 develop 코드 그대로라 되돌릴 것이 없다.
