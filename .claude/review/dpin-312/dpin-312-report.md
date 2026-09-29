# dpin / Issue #312 코드 리뷰

**Spec:** [workspace#312](https://github.com/xmilex-git/workspace/issues/312)
**Compare:** [develop...dpin](https://github.com/CUBRID/cubrid/compare/develop...xmilex-git:cubrid:dpin)
**Base / HEAD:** `c63a3b993be552ef6ad3ce244c386d5081147958` / `4b55eaaf965476b7d8e73fe44dfb516b5ea2c354`
**Date / Scope:** 2026-09-27 / 32 commits, 86 files, +40,862 / -7,498. 정적 소스·호출 경로·요구사항 리뷰.

> **TL;DR** (Blocking): 핵심 게이트 구조와 원본 바인드·PX 소유권 처리는 구현되어 있다. 다만 상관 피연산자의 스코프당 1회 변환이 빠져 있고, 인덱스 키 비교표 준비에 불필요한 제곱 비용이 추가되어 #312 완료 판정 전에 보완해야 한다. SQL 오답·크래시를 확정한 항목은 없다.

## Summary

- **변경 요약**: XASL(실행 계획)을 로드할 때 변환 계획을 만들고, 실행 시작 게이트에서 도메인과 변환기를 결정한다.
- **주요 이슈**: F1 상관 값 반복 변환, F2 긴 IN 목록의 비교표 생성 비용.
- **확인 필요 사항**: P4와 감사표 S-08의 산술 디스패치 처리 기준 충돌, #345의 최종 성능·양 빌드 검증.

## Findings

### Blocking (must fix)

**F1 [P2] 상관 비교 피연산자를 내부 후보마다 다시 변환한다.** [domain_resolver.c:1301](https://github.com/xmilex-git/cubrid/blob/4b55eaaf965476b7d8e73fe44dfb516b5ea2c354/src/query/domain_resolver.c#L1301)

- 규칙표 P3와 인터페이스 §3.4는 외부 N행 × 내부 M후보에서 외부 값 변환을 N회로 제한한다. 현재 `OPERAND_CORRELATED`는 로드 분류에만 쓰이며, 일반 비교에는 스코프 소유 변환값을 저장·재사용하는 경로가 없다.
- `qexec_resolve_compare`는 CONST만 별도 값으로 바꾸고(`query_executor.c:4579`), `eval_compare_planned`는 나머지를 행 값으로 전달한다(`query_evaluator.c:344`). `domain_compare_converted`는 호출할 때마다 변환하고 임시값을 해제한다. 서로 다른 타입의 상관 피연산자에 변환이 필요한 중첩 스캔에서 N×M회 변환이 남는다. 인덱스 range 생성의 스크래치는 일반 술어 비교를 대신하지 않는다.
- 수정: scan open/상관 스코프 진입에서 해당 외부 피연산자를 한 번 변환하고 스캔 소유 값으로 재사용한다. `Num_planned_convert`에서 외부 값 몫이 N회인지 확인한다. 휘발 피연산자는 계속 행마다 읽어야 한다.

**F2 [P2] 동일 타입 IN 키도 전체 키 쌍을 순회한다.** [domain_resolver.c:1437](https://github.com/xmilex-git/cubrid/blob/4b55eaaf965476b7d8e73fe44dfb516b5ea2c354/src/query/domain_resolver.c#L1437)

- 인덱스를 사용하는 `id IN (?, ..., ?)`의 K개 원소는 K개 range가 된다(`xasl_generation.c:11186`). `domain_key_compare_keys`가 각 range의 인덱스 타입을, 게이트가 각 상수의 타입을 다시 추가하므로 같은 INTEGER만 있어도 `n_keys = 2K`다(`domain_plan.c:3466`, `query_executor.c:5374`).
- `domain_key_compares_count`와 `domain_resolve_key_compares`가 각각 `n_keys × n_keys`를 순회한 뒤에야 중복을 걸러낸다. 최종 비교표가 비어도 release 소스 경로에 약 8K²회 쌍 검사가 생기며, 이 준비는 바인드 실행마다 반복된다. optdebug는 assert 안에서 같은 크기 계산도 반복한다. 시간 악화율은 측정하지 않았다.
- 수정: 먼저 `(column, type, codeset, collation)`을 중복 제거하고 고유 키 사이에서만 비교표를 만든다. 동일 타입의 긴 IN 목록에 대해 게이트 비용의 증가 추이를 확인한다.

### Questions for the author

**Q1 산술 타입 디스패치의 완료 기준이 문서마다 다르다.** [fetch.c:1572](https://github.com/xmilex-git/cubrid/blob/4b55eaaf965476b7d8e73fe44dfb516b5ea2c354/src/query/fetch.c#L1572)

- 규칙표 P4는 `qdata_*`의 2단 타입 디스패치 제거를 요구하지만, 최신 감사표 S-08은 이를 연산 구현으로 분류해 유지한다. 실제 `fetch`도 `qdata_add_dbval` 등의 기존 타입별 분기로 진입한다. 유지 결정을 적용한다면 P4의 문구를 갱신해야 한다. 이 충돌을 확정 코드 결함으로 세지는 않았다.

## Standards

- **1건, F2 [P2]**: 새 비교표 생성 경로가 입력 키 수의 제곱으로 증가한다. 단순히 카운터가 0이라는 이유로 성능 개선을 판정할 수 없다.
- `cpp-perf-rules` BR-04/A59의 고정 조건 반복 검사 기준과 MEAS-01/04/06/08의 측정 기준도 별도 확인이 필요하다. `compare->kernel`·`conv[s]` 등의 행별 분기는 소스에 남아 있다. 실제 생성 코드의 분기 수나 성능 영향은 이번 리뷰에서 측정하지 않았다.

## Spec

- **1건, F1 [P2]; 기준 확인 1건, Q1**: P3의 상관 값 변환 시점은 미구현이며, P4는 감사표와 충돌한다.
- 현재 결정에 맞게 구현된 부분: 원본 바인드 `resolved.in`을 이용한 결과 캐시 조회, 복합 인덱스 키의 원소별 strict 성공값/실패값 혼합, 휘발 값의 행별 평가, PX(병렬 실행) 상태 복사·해제, 상수 오류의 게이트 전달과 상수 조건의 분기 가드.
- 최초 설계의 형제 타입 미러 철회, UNION/CTE 타입 거부 시점 이동, #366의 세션변수 고정 타입, #367의 상수 오류 시점 변경은 최신 승인 결정으로 취급했다. 기존 develop 결함과 문서에 승인된 답 변경은 회귀로 세지 않았다.

## Validation

- **기존 실행 기록 확인**: `sql-20260927T043826Z-2492523` 17,479/17,479, `medium-20260927T043826Z-2492524` 975/975, 실패·core 0. 로그와 provenance는 optdebug 설치 및 TC `63172ab860cf`를 가리킨다. 엔진 SHA 연결은 #367 감사·종료 기록의 `4b55eaaf9`에 근거한다. provenance 자체에는 엔진 SHA가 없다.
- `t367-g1`과 직전 `t366-g2`의 결과·카운터 차이 0 기록도 확인했다. 이는 develop 대비 최종 성능 판정이 아니다.
- **미실행**: 이번 리뷰에서 빌드·CTP·SQL 재현·성능 측정을 새로 실행하지 않았다. F1/F2의 호출·반복 구조는 소스 근거이며, SQL 재현 결과나 지연 시간 실측으로 표현하지 않는다.
- **완료 게이트**: [#345](https://github.com/xmilex-git/workspace/issues/345)의 optdebug/release 최종 검증과 develop 대비 반복 측정은 열려 있다. [#344](https://github.com/xmilex-git/workspace/issues/344)의 정리 및 [#346](https://github.com/xmilex-git/workspace/issues/346)의 upstream PR/CI도 남아 있다. 이것들은 별도 코드 결함 수에 포함하지 않았다.
- 리뷰 도중 작업 트리에 별도 수정이 생겨 발견 사항을 고정 SHA의 원본과 다시 대조했다. 위 코드 링크는 모두 그 SHA를 가리킨다. 소스 수정·GitHub 게시·승인은 하지 않았다.

## Evidence

- [규칙표 P3/P4](/home/cubrid/dev/workspace/docs/research/domain-pin-rule-table.md:19), [상관 스코프 계약](/home/cubrid/dev/workspace/docs/research/domain-pin-interface.md:314), [감사표 S-08](/home/cubrid/dev/workspace/docs/research/domain-pin-audit.md:25).
- [기존 CTP 집계 로그](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/312-367/gate/ctp-gate.log), [SQL provenance](/home/cubrid/ctp-run-out/workspace/sql-20260927T043826Z-2492523/provenance.tsv), [카운터 비교](/home/cubrid/dev/workspace/.git_ignored_dir/scratch/312-367/counters/t367-g1-compare.txt).
- 고정 소스 및 리뷰 입력: `.git_ignored_dir/scratch/dpin-review-20260927/`.
