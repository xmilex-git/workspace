# PR #8022 코드 리뷰 보고서 — 효율·유지보수 관점

**PR:** [CUBRID/cubrid#8022](https://github.com/CUBRID/cubrid/pull/8022)
**제목:** [CBRD-27510] implement domain collation pin before execution
**작성자:** xmilex-git
**HEAD SHA:** `23a5e5561` (develop merge-base `15e7dc8b5`)
**JIRA:** CBRD-27510 / 연관: 없음
**TC PR:** CUBRID/cubrid-testcases#3588 (`tc/pr-8022`) / cubrid-testcases-private-ex#4258
**리뷰 일시:** 2026-10-04
**리뷰 결정:** 자체 리뷰(게시 없음). 승인 판정(JIRA·TC)은 2026-09-30 보고서(`PR-8022-report-20260930-simplify.md`)와 CI 로 이미 끝났고, 이 보고서는 "더 효율적인가, 더 읽기 쉬운가" 만 본다.

> **TL;DR** (Non-blocking): 결함은 없다. 실행당 추가 비용은 단순 문장 0.4~0.9 %, 바인드 30개 문장 0.5~2 % 로 작고, 그 안에서 줄일 수 있는 것은 실행 종료의 `pr_clear_value` 호출과 실행당 할당 2~4회다. 가장 큰 비용은 빌드 쪽이다: `XASL_STATE` 가 두 상태 구조체를 값으로 안아 `query_executor.h` 를 포함하는 203 TU 가 `domain_rules.h`·`object_domain_convert.h` 에 재컴파일 의존한다. 읽기 난도는 번호 규약 혼재(1-based/0-based)와 태그 없는 union, 이력 흔적이 남은 단계 번호에서 온다.

## Summary

- **변경 요약**: 도메인·collation 확정을 컴파일과 실행 전 도메인 확정 두 곳으로 모은 PR(+27,842 / -9,005, 89 파일).
- **주요 이슈**: (1) 헤더 fan-out 203 TU — 작은 절연 헤더로 해결, (2) 번호 규약 혼재·union 태그 없음·단계 번호 흔적 — 기계적 정리.
- **확인 필요 사항**: 구현 범위(아래 Findings 의 N1~N9 중 무엇을 이번에 반영할지).

---

## Findings

### Blocking (must fix)
없음.

### Non-blocking (should consider)

**유지보수·직관성**

- N1. `src/query/query_executor.h:37,95-96` — `XASL_STATE` 에 `RESOLVED_DOMAIN_TABLE`·`DOMAIN_EXECUTION_STATE` 를 값으로 두려고 `domain_plan.h` 전체를 포함한다. 두 구조체의 멤버는 포인터·정수·bool 뿐(`domain_plan.h:448-502`)이라 전방 선언으로 충분하다. 결과: `ninja -t deps` 기준 `domain_plan.h` 203 TU, `domain_rules.h` 212 TU, `object_domain_convert.h` 218 TU 가 재컴파일 의존(서버 309 + SA 371 TU 중). 도메인 계획 항목을 실제로 읽는 TU 는 10여 개(`fetch.c`·`query_executor.c`·`scan_manager.c`·`query_evaluator.c`·`query_aggregate.cpp`·`query_analytic.cpp`·`domain_*.c`·`stream_to_xasl.c`·`query_dump.c`·`query_hash_scan.c`). -> 두 구조체와 `DOMAIN_VALUE_STATE` 만 담은 `domain_state.h` 로 절연.
- N2. `src/query/domain_plan.h:76-91`, `src/xasl/xasl_aggregate.hpp:88` — 번호 규약이 둘이다. `resolved_index`·`ref`·`compare_index`·`resolved_elements_index`·`resolved_keys_index`·`constant_branch` 는 0-based/-1, `node_domain_index`·`temporaries[2]`·`accumulator_domain.temporary` 는 1-based/0. 접근자가 `- 1` 을 보정하고(`domain_resolve.h` `qexec_node_domain_index`), 상태 가이드 §3 이 표로 설명해야 했다. -> 0-based/-1 로 통일.
- N3. `src/query/domain_plan.h:81-91` — `compares`/`temporaries[2]` union 을 opcode 로만 구분한다. 두 부류에 모두 드는 opcode 가 생기면 조용히 겹친다. -> `flags` 의 빈 비트로 태그, optdebug 는 opcode 와 일치 assert.
- N4. 가변 판정이 세 벌이다: regu 플래그 `REGU_VARIABLE_VARIABLE_DOMAIN`(`domain_plan.c:1499` 에서 세팅, `fetch.h:63` 에서 읽음), 항목 플래그 `DOMAIN_PLAN_VARIABLE`, 도메인 타입 검사 `regu_is_variable_pos`(`regu_var.hpp:299`). 세 답이 같다는 불변식이 코드에 없다. -> 로드 끝 assert + 플래그 주석.
- N5. `src/query/domain_resolve.c:2616-2644` — `qexec_resolve_domains_internal` 머리말의 단계가 1, 2, 3(접힘), 4, 5, 6, 7, 7b, 8, end 로 번호에 이력이 남았다. `RESOLVED_DOMAIN_TABLE.frozen` 은 "읽어도 된다" 는 뜻인데 이름은 "더 쓰지 않는다" 로 읽힌다(상수식·세션변수·키 확정은 그 뒤에도 쓴다). -> 단계는 함수 이름으로, `frozen` -> `readable`.
- N6. `src/query/domain_plan.h`(라이선스 뒤 바로 enum) — 모듈 개요가 없다. 자료 흐름·번호 공간·소유권·PX 복사를 설명하는 14절 가이드(`pr8022-domain-state-guide.md`)는 workspace 레포에만 있어 upstream 리뷰어는 보지 못한다. -> 헤더 상단 40줄 개요.
- N7. `src/query/domain_resolve.c:441-452` — `DOMAIN_DEFERRED_ERROR.arg`/`arg2` 의 뜻이 `kind` 마다 다르다(COMPARE: key-range 여부, KEY: 두 타입, ARGUMENT_TYPE: 함수 종류). -> 이름 있는 union.
- N8. PR 본문과 덤프의 이름 불일치: 본문은 `domain_resolver.c/h`(실제 `domain_rules.c/h`), "GATE 비트를 붙입니다"(실제는 `tp_Variable_domain` 적재 + 로드 도출 플래그), "게이트/슬롯"(용어집: 실행 전 도메인 확정/가변 POS); `query_dump.c` 는 `slot=`·`VOLATILE` 로 찍는다(enum 은 `OPERAND_NON_CACHEABLE`).
- N9. 긴 함수: `domain_walk_xasl` 276줄, `stx_build_domain_plan` 272줄(적재 항목 연결 리스트를 8번 순회하는 번호 매기기 패스가 본문에 그대로), `domain_walk_regu` 217, `qexec_resolve_domains_internal` 264, `domain_resolve_function` 208. 번호 매기기 패스를 `domain_plan_number_*` 로 빼면 읽는 순서가 드러난다. (이번 범위 밖 후보)

**효율 (측정은 아래 표)**

- E1. `src/query/domain_resolve.c:3042-3079` — `qexec_clear_resolved_domains` 가 `vals[]` 전부에 `pr_clear_value` 를 부른다. 바인드는 `qexec_share_value` 가 payload 를 공유해 해제할 것이 없다. 실행당 case-30 13.0k, in-30 2.5k, pkand-30 2.5k 명령. -> `DB_NEED_CLEAR`·집합·VOBJ 일 때만 호출.
- E2. `src/query/domain_resolve.c` — 실행당 할당이 한 블록이 아니다: 값·확정 블록 외에 `temporaries`·`scope_generations`(`:264,267`), ALL/SOME scratch·출력(`:1427,1469`), 인덱스 스캔(`:2128`), 세션변수(`:2290`), 상수 가지(`:2539`), `comparison_resolved`(`:2792`). 크기는 전부 로드가 안다. 측정: `qexec_alloc_resolved_domains` + alloc/free 호출이 실행당 0.4~1.2k. -> 1단계로 `temporaries`·`scope_generations` 를 같은 블록에.
- E3. 같은 키 쌍의 확정 비교를 30번 따로 푼다: `qexec_resolve_compare` 가 in-30 10.3k, pkand-30 10.7k, and-30 12.2k, case-30 11.8k(비교당 ~350). 직전 비교와 키 쌍이 같고 상수 변환이 없으면 복사로 대신할 수 있다(선택, 위험 중간).
- E4. 정적 계획 빠른 길은 보류 권고: 단순 문장의 resolve+clear 가 pk-1 1.5k(0.36 %), nobind 0.9k(0.89 %), sel-1 0.4k(0.5 %) 라 `vals = in` 별칭·clear 가드·PX 분기를 더할 만큼의 이득이 아니다.

### Questions for the author
- 구현 범위: N1~N8 + E1·E2 를 추천(각각 독립 커밋, 커밋마다 게이트). E3 는 선택, E4·N9·#375 는 보류.

## 측정 (dpin HEAD release, SA `csql -S`, 메인 스레드 사용자 공간 명령, N=20,000 또는 2,000, 3회 중앙값; `-camp` = 캠페인 §6.2 셀과 같은 문장·표)

| 셀 | 명령/실행 | resolve+clear /실행 | 비율 | 안에서 큰 것 |
|---|---:|---:|---:|---|
| nobind(auto-param 1) | 100,681 | 897 | 0.89 % | self 439, alloc 421, compare 364 |
| pk-1 | 418,495 | 1,495 | 0.36 % | self 562, compare 408, alloc 373 |
| sel-1 | 73,822 | 384 | 0.52 % | |
| in-30 | 1,257,359 | 25,805 | 2.05 % | self 10.7k, compare 10.3k, clear 2.5k, `domain_value_domain` 2.1k |
| pkand-30 | 4,420,623 | 20,242 | 0.46 % | compare 10.7k, self 4.3k, clear 2.5k |
| and-30 | 31,907,218 | 22,365 | 0.07 % | compare 12.2k, self 5.6k |
| case-30 | 1,121,145 | 87,303 | 7.79 % | 상수식 평가 51.0k(설계: 행에서 옮김), clear 13.0k, compare 11.8k, self 11.6k |
| upd-31 | 2,849,321 | 5,164 | 0.18 % | self 3.4k, clear 1.4k |

- 캠페인 §6.2 의 dpin 명령 수와 1~7 % 안에서 일치(pk-1 389,557 / in-30 1,228,632 / case-30 1,060,281 / upd-31 2,803,118). `stx_build_domain_plan` 은 플랜 캐시 재사용으로 0.00~0.02 %.
- 타입 쌍 비교 표(gdb, optdebug): n_keys 57(원소 타입 27 + 문자 3종 × 등록 collation 10), n_pool 1,956, 상주 141 KB(pool, 빌드 끝에 `realloc` 로 축소) + entry 26 KB, 빌드 0.8 ms. 과대 할당 아님(정적 읽기의 오판을 측정이 바로잡음).
- 구조체 크기(LP64): `DOMAIN_PLAN_ITEM` 80, cold 16, `RESOLVED_DOMAIN` 56, `DOMAIN_COMPARE` 72, `DOMAIN_COMPARE_PLAN` 184, `RESOLVED_DOMAIN_TABLE` 104, `DOMAIN_EXECUTION_STATE` 64, `XASL_STATE` 232, `DOMAIN_EXECUTION_TEMPORARY` 104(optdebug), `REGU_VARIABLE` 104 / `ARITH_TYPE` 72 / `AGGREGATE_TYPE` 240 / `ANALYTIC_TYPE` 384 (develop 과 같음).
- 컴파일 시간(release, 단일 TU): `object_domain_convert.cpp` 4.0 s × 3 라이브러리, `domain_plan.c` 4.1, `domain_resolve.c` 3.5, `domain_rules.c` 2.7; `object_domain.c` 4.0 -> 3.0; `query_executor.c` 10.2 -> 10.1. 전체 빌드에 더해지는 CPU 는 약 30 s — 문제는 TU 당 시간이 아니라 fan-out(N1).

## 오판으로 확인되어 뺀 것
- 타입 쌍 표 pool 과대 할당(위 측정). `btree_compare_key` 래퍼 비용(`btree_compare_key_with` 는 `STATIC_INLINE`). 날짜·TZ `_core`/래퍼 40쌍의 중복(래퍼가 core 를 부른다).

## Runtime Verification
- 재사용: PR CI(빌드·sql·medium green), 캠페인 벤치 §6(develop 대비 비율).
- 새로 돌린 것: dpin `23a5e5561` release/optdebug 설치본(`dpin21/install-c-*`, lib `327f99d52b5a`/`5ff47918eb8b`), SA DB `rev8022a/b`(t30 10,000행), `perf stat`/`perf record --call-graph dwarf` 8셀 × 3회, `ninja -t deps` 역의존 집계, gdb 크기 판독. 원자료 `.git_ignored_dir/scratch/pr8022-review/`. CTP 는 돌리지 않았다(코드 변경 없음).
