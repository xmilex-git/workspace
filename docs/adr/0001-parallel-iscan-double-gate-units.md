# Parallel index scan 이중 게이트의 단위·threshold 분리

Parallel index scan 활성화 판정에서 client 게이트는 `ceil(selectivity × cum_stats->pages)`를
`parallel_index_scan_page_threshold`(추정 단위 전용 prm)와 비교하고, server 게이트는
`file_get_num_user_pages(btid.vfid)`를 heap 등 다른 실제-페이지 게이트와 동일한
`parallel_scan_page_threshold`와 비교한다. 실제-페이지 게이트는 경로(heap/index)와 무관하게
같은 단위이므로 prm을 공유하고, 추정 게이트만 index 전용 prm을 갖는다.

## Considered Options

- `cum_stats->leafs` 사용(이슈 #160 초안 문구): 기각. 기본 `UPDATE STATISTICS`(AR 샘플링)에서
  leafs는 `exp_ratio = pages/leafs; leafs *= exp_ratio` 외삽 + `MIN(leafs, npages-(height-1))`
  클램프로 **사실상 pages − height + 1로 붕괴**하고(btree.c:7213-7215, :7557), WITH FULLSCAN일
  때만 진짜 leaf 수가 된다. 즉 통계 수집 방식에 따라 의미가 흔들리고, OID-overflow 체인(워커가
  실제 순회하는 작업량, btid.vfid 내부 할당)을 빠뜨린다. statistics.h:70의 "including overflow
  pages" 주석은 현행 코드와 불일치(스테일)한 점도 확인.
- 서버 게이트에 `parallel_index_scan_page_threshold` 재사용: 기각. 그 prm은 추정치(선택도×페이지)
  스케일로 튜닝되는 값이고, 서버가 재는 것은 heap 게이트와 같은 실제 파일 페이지다. 단위가 다른
  두 판정이 한 prm을 공유하면 튜닝이 서로를 깨뜨린다.

## Consequences

- keylen-overflow(ovfid) 파일은 별도 VFID라 양 게이트 모두에서 자연 배제되고, OID-overflow
  체인은 양쪽 모두 포함된다 — 두 게이트가 같은 "인덱스 파일" 단위를 공유한다.
- `parallel_scan_page_threshold` 기본값(2048)에서는 소중형 인덱스가 서버 게이트에서 직렬로
  떨어진다. 이는 heap과 동일한 "병렬 이득이 나는 실물 크기" 기준을 공유하는 의도된 동작이다.
