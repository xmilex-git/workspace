# bulkidx 세션 보고 (2026-07-18) — 20GB 병렬 회귀(+13.6%) 근본원인 확정·해결

대상 브랜치: `bulkidx/noredo-parallel-r304-wip` (worktree `/home/cubrid/dev/worktrees/r304-bulkidx`).
신규 커밋 1건 `d8f6b3918` (debug+release 빌드 게이트 green, push 0회). gdb/core 분석 0회.
증거 레인: `.not_git_tracking/bulk_index_build/artifacts/u-g008/vtune-5g/` (상세는 그 SUMMARY.md).

## 1. 과제와 접근

B3-fixed(b808bdbf7) 병렬이 20GB VARCHAR(20)에서 develop 병렬보다 +13.6% 느린 원인을
VTune user+kernel 프로파일링으로 규명·해결. 지시대로 동일 성격 5GB fixture(85M행,
100k 고유키×850중복)를 신규 구축해 재현부터 시도.

## 2. 핵심 사실 체인

1. **5GB 신선 fixture에서 회귀 미재현** — b3fix가 오히려 8.8% 빠름(90.3 vs 99.0s).
   aging 6사이클 무추세 → 노화 가설 기각. 회귀는 스케일/조건 의존.
2. **20GB VTune(user+kernel)**: put 단계에서 32 워커 전원이 pgbuf direct-victim
   대기(워커 CPU duty 8%). `pthread_mutex_lock` 347s(pgbuf_unfix 하위),
   `ATOMIC_INC_64` 266s(`pgbuf_get_thread_waiting_for_direct_victim`),
   victim/hash 체인 ~460s CPU.
3. **무왜곡 계측**(1Hz /proc, spacedb 10s 샘플러 — VTune 지속수집은 빌드를
   1.6-1.9× 지연시켜 시간정량에서 배제):
   - b3fix 총 쓰기 198.6GB vs dev 176.4GB (**+22.2GB/빌드**),
   - put 시작 ~20초 안에 파일 할당 **20.0→44.7GB(+24.7GB)** 점프.
4. **원인 확정**: `bt_load_provider_open`이 메인 풀을 `est_main_pages`(최종 run
   페이지+10% = 1.55M pages ≈ 24.2GB) 전량 선할당+선포맷. 실제 인덱스는 7.8GB —
   3.6× 과다(run은 전 (key,OID) 레코드, 인덱스는 키 dedup). 빈 포맷 페이지가
   512MB 풀을 관통해 낭비 flush + victim 기아 + reconcile 대량 재반납(44.7GB
   비대의 정체). provider(V3) 도입 이래 존재 → b2final +12.6%와 연속. B3
   write-through는 원인·해결 모두 아님(기존 결론 보강).

## 3. 수정과 검증

**`d8f6b3918` [bulkidx] B4: bootstrap the provider page pool instead of
pre-publishing the whole estimate** — btree_load.c 1파일 +12/−1.
부트스트랩 풀 = 워커당 64p 1 span, 나머지는 기존 service-loop on-demand 리필
(수요 ~61/s vs 여유 5-8×, 프로토콜 변경 없음).

- **20GB 결정 측정** (campaign convention, cold restart, 교대, warmup1+valid3, 8/8 rc=0):
  dev 중앙값 607.39s vs **B4 584.90s → develop 대비 3.7% 빠름** (기존 +13.6% 느림).
  dev 중앙값은 역대 615-617과 정합(fixture 건전성 재기준선 615.6s 별도 확인).
- **비대 해소**: 빌드 후 spacedb 44.7 → **27.8GB**.
- **정합성**: 5GB 스모크 CREATE rc=0, key당 정확히 850행 인덱스 스캔, COUNT 85M
  정합. `checkdb -S -I idx_t5g_k` 완주 — 출력 0바이트(불일치 보고 없음 = 정상 시그니처; detach 실행이라 rc 미포집).

## 4. 부수 발견 (별도 판단 대상)

- 두 바이너리 공통으로 **빌드의 ~54%(≈350s/645s)가 1-2 스레드 merge tail** —
  병렬 put 이득의 구조적 상한. 후속 개선 후보(이번 범위 밖).
- `pgbuf_get_thread_waiting_for_direct_victim`의 전역 `static INT64 count`
  ATOMIC_INC는 대기자 존재 시 전 unfix가 두드리는 공유 캐시라인 — B4로 트리거는
  제거됐으나 develop 공통의 잠재 핫스팟(범위 밖, 기록만).
- VTune 원시 결과 1.8GB 보존 중(vtune-5g/vtune/) — 삭제 여부 보스 판단 대기.

## 5. 상태

- worktree HEAD `d8f6b3918`, clean(cubrid-cci 의도적 dirty 유지), push 안 함.
- 서버/포트/스트레이 마스터 정리 완료. /home 63% 사용(1.3T free).
- 다음 후보: ① B4를 캠페인 재검증 매트릭스(L1/L2/L4/L6/L7b/kill-switch)에 편입
  ② 8M 24-cell + overflow workload 재측정으로 회귀 부재 확인 ③ merge tail 병렬화 검토.
