# PR-4724 post-ready comments

## CUBRID/cubrid-testcases-private-ex#4724

- review event: APPROVE
- commit_id: 3459b70ce3c3da362a1e81c091445a809c3fe1d0

### top-level

최신 develop release 빌드 11.5.0.2817-bbc3328로 이 TC를 `shell_perf` CTP 컨테이너에서 한 번 돌렸습니다(32코어 공유 호스트). 판정 줄 10개가 모두 나왔고 그중 9개가 OK, core는 0개였습니다. NOK 하나는 검사 2의 heap 비율(2.30배, 2.86배 필요)인데, 이 호스트는 직렬 heap 합이 3.93s로 성능 장비보다 훨씬 빨라서 생긴 차이로 보고 있습니다. list는 1.74배, index는 6.74배였고, 세 스캔 모두 trace에 워커 8이 찍히고 5회 값이 직렬과 같았습니다.
### inline: shell_perf/_40_guava/cbrd_26722/cases/cbrd_26722.sh:439 (RIGHT)

검사 8·9는 수정 전 빌드에서도 통과해서, 이 이슈를 가르기보다는 이후 빌드를 감시하는 쪽으로 이해했습니다. 그런데 감시용으로 보더라도 한계가 넓지 않나요? 최신 2780의 병렬 1.676s 기준으로는 약 50% 느려져도 2.51s 안에 듭니다. 장비가 다르면 판정 자체가 달라지기도 해서, 이 호스트에서는 직렬 합 3.93s에 한계가 12.13s라 직렬이 3배 느려져도 OK가 나왔습니다.
Definition of done 3번의 답은 본문의 7회 x 3대 측정(+0.5%, +2.0%)으로 이미 나와 있으니, 상시 감시가 목적이면 기준값을 최신 빌드로 다시 잡거나, 아니면 두 검사를 빼고 본문 측정을 답으로 두는 건 어떨까요?
