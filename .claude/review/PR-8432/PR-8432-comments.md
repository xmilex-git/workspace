# PR-8432 post-ready comments (r2, head 945478c64) — post after the TLA+ record run prints RESULT: OK

## CUBRID/cubrid#8432 — event: APPROVE

### top-level
leaf swap 을 develop 그대로 두니 지난번 중단된 range scan 의 행 누락은 다시 나지 않습니다. 같은 재현을 이 head 빌드에서 세 번 돌려 모두 9,974행이 나왔고, swap 은 매번 첫 페이지의 마지막 객체를 옮겼습니다. 이슈 첨부 크래시 훅으로 1단계 직후 서버를 내린 경우도, 재시작 뒤 vacuum 이 directory 에서 못 찾고 순회로 첫 페이지에서 D 를 찾아 지웠습니다(checkdb rc 0).

### inline src/storage/btree.c:11522 (RIGHT)
1단계 직후 서버가 멈추고 재시도가 오기 전에 `ALTER INDEX ... COMPACT` 가 이 키를 지나가면 어떻게 되는지 궁금합니다. TLA+ 모델에서는 `btree_ovf_compact_pull` 이 D 가 남은 페이지 뒤에 다음 페이지의 앞 객체를 붙이면서 그 페이지 안 OID 순서가 깨지고(D 뒤에 D 보다 작은 OID), 그 객체를 페이지 안 이진 탐색과 directory 로 찾지 못하는 경로가 나왔습니다.
런타임으로는 재현하지 않았고, develop 은 D 를 영구히 남기니 같은 노출이 원래 있던 것이기는 합니다. 이 PR 이 창을 재시도까지로 줄이지만 재시도 전 COMPACT 는 #8431 의 안정 객체 검사로도 막히지 않는 것으로 보여서(leaf 에는 L1 이 안정 객체로 있음), 이 경우를 여기서 다룰지 별도 이슈로 둘지 의견 부탁드립니다.

### reply on thread 4510355356 (then resolve)
확인했습니다. 이 head 빌드에서 같은 재현(키 1 첫 페이지 뒤에서 멈춘 사이 vacuum 개방)을 세 번 돌려 모두 9,974행 중 9,974행이 나왔고, swap 은 첫 페이지 0|4751 의 마지막 객체를 옮겼습니다.

## CUBRID/cubrid-testcases-private-ex#4771 (head d4596a68) — event: APPROVE
(본문 없음)
