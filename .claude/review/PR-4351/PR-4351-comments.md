# PR-4351 post-ready comments (재리뷰 2026-10-13)

## CUBRID/cubrid-testcases-private-ex#4351

- event: APPROVE (사용자 결정 2026-10-13, grill Q3)
- commit_id: a68097f3b54d4f90092868a221348e658a796ebf
- 인라인: 없음. 기존 스레드 4개는 작성자 답글 반영, resolve 하지 않음 (grill Q4)
- 형식: 평문, 합니다체, 인라인 코드/굵게 없음 (Android 앱 표시 문제)

### top-level body

반영 확인했습니다.

cbrd_25717_split_scaling 은 이 호스트(32코어)에서 10/08 에 같은 3배 데이터로 잰 2647 release 결과로도 8워커 5.0~5.7x, 4워커 3.5~3.8x 라 새 기준을 통과합니다. 헤더의 원인 설명도 측정과 맞습니다.

cbrd_25454 는 2625, 2632 분포까지 재 주셔서 11% 가 최신 빌드 기준의 선이라는 점이 분명해졌습니다. 합격선은 말씀하신 판단대로 두면 될 것 같습니다.

감사합니다.
