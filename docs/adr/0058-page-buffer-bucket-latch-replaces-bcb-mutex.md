---
status: accepted
date: 2026-11-16
issue: workspace 설계 (`docs/tla/bcb-mutex-removal/`, D1–D15, C1–C9, model `BucketLatch`; RESULT: OK, run `bcb-mutex-removal-20261116-040414-603034`, commit 1365192)
---

# 페이지 버퍼의 BCB mutex를 버킷 read-write 래치 하나로 대신한다

페이지 버퍼의 BCB 상태(fix count, 래치 모드, 대기자 목록, vpid, flush 상태)는 지금 BCB마다 있는 pthread mutex(`PGBUF_BCB_LOCK`)와, READ에만 쓰는 락 없는 경로(`pgbuf_lockfree_fix_ro`/`_unfix_ro`)가 함께 지킨다. 이것을 해시 버킷마다 하나인 read-write 래치(CAS 워드, 공유/배타)로 바꾼다. 모든 fix와 unfix가 이 래치를 잡는다(READ는 공유로 잡고 fix count를 원자적으로 올린다, 나머지는 배타). 희생자 claim, invalidate, BCB의 페이지 교체는 배타로 잡고 fix도 대기자도 없을 때만 한다. 보호 방식이 하나뿐이어야 경로마다 따로 따질 경합이 없어지고, flush가 페이지를 복사하는 동안 mutex를 쥘 필요도 없어진다. 목표는 경합 성능이다(perf 서버에서 측정, 단일 스레드 `instructions:u`는 퇴행 없음만 확인).

사용자 결정(2026-11-15): 모든 경로에서 mutex를 없애고(D2), 한 모델을 끝까지 따른다(D7, 섞지 않음).

## Considered Options

- **PostgreSQL식 버퍼 상태 word + 대기 큐**: 상태를 64비트 word 하나에 담고 CAS로 바꾸며, 내용 잠금에 share-exclusive 모드를 두어 flush 중 복사를 없앤다. 락 없는 READ 경로를 살릴 수 있지만, 대기자 목록·희생자 선택·flush 상태를 word와 큐 두 곳에서 맞춰야 한다. 하지 않았다.
- **락 없는 READ 경로를 두고 나머지만 래치로(섞기)**: 직렬 READ의 명령 수는 가장 적지만, READ 경로와 래치 경로가 만나는 지점(희생자 선택, 승격, 대기자 깨우기)마다 경합을 따로 증명해야 한다. 하지 않았다(D7, D9).
- **버킷 래치 하나(채택)**: 상태가 바뀌는 곳은 언제나 그 페이지 버킷의 래치 아래다. TLA+ 모델 하나로 9개 클레임을 검사한다.

## Consequences

- 새 요청은 대기자 목록을 보지 않는다(barging, D8). 깨어난 대기자도 다른 요청과 똑같이 경쟁한다. WRITE 대기자가 새 READ에 밀릴 수 있다.
- 대기자는 깨워 줄 뿐 래치를 넘겨받지 않는다(D4). 깨어나면 자기 항목을 스스로 떼고, 남은 대기자에게 깨우기를 넘기고(D12), 해시 체인부터 다시 찾는다.
- 승격은 기다리지 않는다. 혼자가 아니거나 쓰기 중이면 `ER_PAGE_LATCH_PROMOTE_FAIL`로 실패하고 호출자가 WRITE로 다시 fix한다(D13). 기다리는 승격은 barging과 함께 쓰면 "승격 뒤 페이지가 READ 때와 같다"(C9)를 깨뜨린다.
- flush는 write-in-progress 플래그를 세우고 래치 없이 복사한다. 그동안 WRITE fix와 승격은 기다리고 READ는 기다리지 않는다(D10). 쓰기에만 막힌 대기자를 남기는 쪽이 write-waiter 플래그를 세워, 쓰기가 끝날 때 깨운다(D11, D14).
- 희생자 검색은 후보의 버킷 래치를 기다리지 않고 시도만 하고, 안 되면 다음 후보로 넘어간다. 기다리면 서로 다른 LRU 순서의 두 스레드가 교착한다(`mutant-victim-wait`).
- 마지막 unfix는 사용 표시만 남긴다. LRU 이동은 희생자 검색이 한다(D5). 버퍼 적중률을 같이 측정한다.
- claim 뒤 페이지 읽기가 실패하면 BCB를 비우고 대기자를 모두 깨운다. 각자 다시 찾고 필요하면 다시 읽는다(D15). 깨진 페이지를 N개가 기다리면 실패하는 읽기가 최대 N번 난다.
- 구현은 단계별 PR로 나눈다(D6): READ fix/unfix + claim → 대기자 → WRITE·승격·flush → LRU. 구현 spec은 `BucketLatch`를 refine하고 trace 검증을 붙인다.
