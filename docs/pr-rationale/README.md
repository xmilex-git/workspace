# 열린 엔진 PR의 설계 설명 (2026-10-12 기준)

CUBRID/cubrid에 열려 있는 xmilex-git의 non-draft PR마다 "무엇이 틀렸고, 왜 이렇게 고쳤고, 무엇을 택하지 않았는지"를 적었습니다. draft PR(#8145, #7837)은 뺐습니다.

| PR | JIRA | 한 줄 요약 | 머지 전 남은 것 |
|---|---|---|---|
| [#8024](PR-8024-CBRD-27493.md) | CBRD-27493 | 언네스트된 SEMI/ANTI 뒤의 파티션 후속 조인을 행 단위로 구동 | 2026-10-12 develop 동기화(bit 28로 이동), 게이트 통과, MERGEABLE |
| [#8114](PR-8114-CBRD-27567.md) | CBRD-27567 | memoize 키에서 상관 부질의 결과를 빼고, 재생 행과 anti 생존 행에서 dptr 초기화 | 사람 리뷰 대응 완료, 승인 대기 |
| [#8129](PR-8129-CBRD-27592.md) | CBRD-27592 | no-logging 병렬 인덱스 빌드의 오류 전달(보관 후 채택), DESC FK 마지막 리프, 역방향 FK 슬롯 | 리뷰 없음. 역방향 FK 결함은 백포트 검토 |
| [#8130](PR-8130-CBRD-27590.md) | CBRD-27590 | SP가 있는 문장과 MVCC 비적용 클래스는 페이지 복사 스캔·커버링 읽기를 끔 (ADR 0026) | #8133이 위에 쌓여 있음 |
| [#8131](PR-8131-CBRD-27594.md) | CBRD-27594 | CTE 결과 temp 스캔에 참조 블록의 병렬 힌트 플래그를 복사 | 승인됨 |
| [#8132](PR-8132-CBRD-27588.md) | CBRD-27588 | row by row gather에서도 미리 계산한 스칼라 부질의 값을 워커에 넘김 | 리뷰 없음 |
| [#8133](PR-8133-CBRD-27591.md) | CBRD-27591 | SP가 있는 문장은 fixed scan을 끄고, SP 항은 key filter에서 뺌, debug 자기 대기 감지 | #8130 머지 뒤 rebase |
| [#8134](PR-8134-CBRD-27593.md) | CBRD-27593 | FOR UPDATE spec이 있는 병렬 스캔 체인은 직렬 | #8136과 같은 파일, 나중 쪽 rebase |
| [#8135](PR-8135-CBRD-27589.md) | CBRD-27589 | binary LIKE의 끝 ESCAPE에서 `str2++`를 조건 안으로 | 승인됨 |
| [#8136](PR-8136-CBRD-27596.md) | CBRD-27596 | 부질의 전체에서 미선언 SP·메서드를 찾는 `CANNOT_RUN_IN_WORKER` + px 워커 서버측 SQL 거부 | #8134와 같은 파일 |
| [#8137](PR-8137-CBRD-27599.md) | CBRD-27599 | 병렬 워커 통계를 워커 배열에 쌓고 끝날 때 한 번 합침 (trace·세션 통계) | 사람 리뷰 없음 |
| [#8138](PR-8138-CBRD-27598.md) | CBRD-27598 | `xasl_merge_stats`가 `spec_list` 없는 노드의 scan 통계를 건너뜀 | gha-ci 38221607312 결과 확인 |
| [#8139](PR-8139-CBRD-27504.md) | CBRD-27504 | `date_to_char`가 문자열이 아닌 포맷을 -621로 거부 | 승인됨 |
| [#8140](PR-8140-CBRD-27597.md) | CBRD-27597 | CTE의 두 list id가 dependent list 체인을 각자 갖도록 `QFILE_COPY_DEPENDENT` | Greptile P1 고침 + 답, 리뷰 중 찾은 `qexec_execute_cte` 복사 실패 처리 결함도 함께 고침(head `f485d965f`), 게이트 통과 |

TC PR(cubrid-testcases, private-ex)과 매뉴얼 PR(cubrid-manual#772)은 이 묶음에 넣지 않았습니다.
