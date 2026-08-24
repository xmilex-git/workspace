# 스냅샷 import는 vacuum을 막지 않는다 — pin은 독립된 선행 단계다

> **Superseded (2026-08-24, #108/#109)** — 이 결정은 2단계 helper 프로세스의 join-tran
> 핸드셰이크(#103) 전용이었고, 목적지 축소로 helper 스택 전체가 폐기됐다. 스냅샷 import를
> 수행하는 코드가 존재하지 않는다. 아래 사실 관계(`compute_oldest_visible_mvccid`가 tdes
> 스냅샷이 아니라 `m_transaction_lowest_visible_mvccids`만 읽는다)는 여전히 유효하므로,
> 훗날 다른 문맥에서 스냅샷을 다른 트랜잭션에 옮기려 할 때 그대로 인용할 수 있다.

javasp 병렬 2단계 helper(지도 xmilex-git/workspace#87, 결정 티켓 #103)는 호출자 트랜잭션의 MVCC 스냅샷을 `mvcc_info::copy_to`로 복제해 가시성을 재현한다. 그러나 vacuum의 oldest-visible 계산(`mvcctable::compute_oldest_visible_mvccid`)은 tdes의 스냅샷 내용을 읽지 않고 전역 배열 `m_transaction_lowest_visible_mvccids[tran_index]`만 본다 — 스냅샷을 복제해 꽂아도 vacuum은 전혀 막히지 않으며, helper가 보려는 오래된 row가 helper 자신의 tran_index 기준으로 청소될 수 있다.

따라서 join-tran 핸드셰이크는 **pin-먼저-복사-나중** 순서를 강제한다: (1) 호출자 슬롯의 lowest-visible 값을 읽고 (2) helper tran_index의 슬롯에 먼저 publish한 뒤 (3) 스냅샷을 복제한다. 호출자 질의가 in-flight인 동안 호출자 슬롯이 전역 oldest를 pin하고 있으므로 이 순서면 청소 창이 생기지 않는다.

"호출자 슬롯이 어차피 pin을 유지하니 helper 쪽 pin은 생략 가능"이라는 최적화는 기각했다 — 호출자 측 상태 변화(스냅샷 재빌드·조기 정리 경로)에 대한 암묵 의존을 만들고, 위반이 조용한 wrong-result(청소된 row 미가시)로 나타나 진단이 극히 어렵기 때문이다.

## Consequences

- join-tran 핸드셰이크 구현(#103 후속 구현 티켓)은 import 절차에서 pin publish가 스냅샷 복제보다 반드시 선행해야 하며, 잡 종료 시 helper 슬롯 해제(MVCCID_NULL 복원)와 imported 가시성 상태 purge가 짝으로 수행되어야 한다.
- helper의 스냅샷은 자체 빌드(`build_mvcc_info`)가 아니라 import로만 유효해진다 — helper 경로에서 자체 빌드가 일어나면 pin 없는 스냅샷이 생기므로 설계 위반이다.
- 리뷰 체크포인트: `m_transaction_lowest_visible_mvccids` 슬롯을 갱신하는 신규 코드는 이 ADR의 순서 계약을 인용해야 한다.
