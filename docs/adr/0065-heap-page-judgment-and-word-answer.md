---
status: accepted
date: 2026-11-18
---

# 힙 묶음 순회는 페이지 판정과 첫 워드 답으로 행을 정하고, 스위치 없이 항상 켠다

힙 풀스캔의 페이지 묶음 순회(`heap_page_collect_visible`, CBRD-27361)는 REC_HOME 레코드마다 MVCC 헤더를 풀고 표현 ID를 비교했다. vacuum이 끝난 레코드는 이미 `snapshot_fnc`를 부르지 않으므로 남은 비용은 헤더 풀기와 표현 ID 비교다(develop `41ca53ce7` perf annotate, 이 함수 명령어의 약 26%와 32%). CBRD-26928의 POC는 `snapshot_fnc`만 페이지 단위로 뺐고 "불필요"로 끝났다.

CBRD-28188은 PoC(`og12-pagevis`)에서 비교한 네 방식 중 D를 채택한다.

1. **페이지 판정**: 페이지에 들어갈 때 `max_mvccid < lowest_active_mvccid`(`mvcc_satisfies_snapshot` 스냅샷, chain이 있는 페이지)를 한 번 본다.
2. **첫 워드 답**: 판정이 통과한 페이지는 delete 플래그가 없고 표현 ID가 맞으면 행, delete 플래그가 있으면 건너뛴다. 그 밖의 페이지는 MVCCID가 없고 표현 ID가 맞으면 행이다. 나머지는 develop의 헤더 판정이다.
3. **지속 표시는 두지 않는다.** 디스크 포맷, 로그, 복구, vacuum은 그대로다.
4. **시스템 파라미터나 환경 변수 없이 항상 켠다**(사용자 결정 2026-11-18). 새 엔진 경로는 기본 OFF라는 하우스 규칙의 예외다. 근거: 모든 레코드의 답이 develop과 같고(TLA+ `docs/tla/CBRD-28188`, `EquivNow`), hot 조건(오래된 트랜잭션을 연 채 적재)에서도 행당 명령어가 늘지 않는다(PoC 실측 433.8 -> 430.4).

판정이 맞으려면 데이터 페이지가 가진 모든 MVCCID가 그 페이지의 `max_mvccid` 이하여야 한다(`IdBound`). develop의 writer census(MAP.md)가 이를 받친다: MVCCID를 쓰는 연산은 모두 MVCC op로 로그되며 `heap_page_update_chain_after_mvcc_op`로 chain을 올리고, `UPDATE_INPLACE_CURRENT_MVCCID`는 MVCC가 꺼진 클래스이거나 자기 REC_ASSIGN_ADDRESS를 채우는 경우(NOTIFY_VACUUM으로 올림)뿐이며, `UPDATE_INPLACE_OLD_MVCCID`는 레코드가 이미 가진 id만 다시 쓴다. 이 전제를 깨는 writer가 생기면 이 판정도 깨진다(mutant `inplace_current_home`, `reloc_no_home_raise`).

## Considered Options

- **A: vacuum이 세우는 페이지 all-visible 표시(PostgreSQL visibility map의 비트와 같은 생각)**: 기각 — vacuum 완료 표에서는 더 줄지만(269.7 대 281.8), loaddb 표에는 표시가 서지 않고(344.1), 모든 힙 페이지 LSA 갱신에 해제 hook이 붙으며, 포맷 전 페이지를 읽는 결함이 PoC에서 실제로 났다(`dc9b2f6a4`). 표시 로깅도 따로 든다.
- **B만(페이지 판정)**: 기각 — 판정이 실패한 페이지에서 vacuum이 끝난 레코드의 이득이 없다. D는 B의 상위집합이다.
- **C만(첫 워드 답)**: 기각 — vacuum 전 commit된 행에서 이득이 없다(402.6 대 274.5).
- **시스템 파라미터, 기본 OFF**: 기각 — 결과가 같은 내부 경로라 사용자가 고를 이유가 없다.
