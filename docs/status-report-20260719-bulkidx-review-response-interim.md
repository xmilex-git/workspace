# bulkidx 리뷰 대응 중간 리포트 (2026-07-19 02:00, 진행 중)

대상: `bulkidx/noredo-parallel-r304-wip` 리뷰 15건(P1 10 + P2 5) 대응 캠페인 (CBRD-27071 머지 게이트).

## 1. 구현 — 완료 (빌드 green)

- **15건 전부 구현 완료**, 21개 파일 +931/-217. debug/release 빌드 green.
  - 단계 1 기계적 수정: repair dirty(#1), marker abort-가능 시점 이동(#2), 2PC informing 상태(#3), temp retire rc 전파(#13), unpack caller-buffer(#15).
  - 단계 2 identity(ADR-0003): 서버 발급 create LSA를 btree FILE_DESCRIPTORS 기존 64B 유니온 안에 저장(디스크 포맷 불변), 서버측 pending-build 등록/정확일치 publication, suppression/cleanup (VFID, create LSA) 정확 일치 + fail-safe, P2-11 marker-only completion 추적.
  - 단계 3 호환(ADR-0004): NET_CAP_BULK_NO_REDO 핸드셰이크 협상(4조합 wire 안전), 비호환 log 소비자 시 자동 강등 + NOTIFICATION 1줄, P2-12 zero-marker fast path + volume 색인.
  - 단계 4: ovf pool bootstrap 상한(워커당 256) + NEED_OVF 256 리필.
  - 단계 5: post-force catalog 공용 helper parity(#9), marker FORCE ignore-list 거부(#10).
- **아키텍트 리뷰 후속 3건 추가 봉인**: 2PC prepare/commit의 pending-marker 가드 우회, marker 발행 직전 소비자 호환 재검사(TOCTOU), abort 시 pending 상태 discard.

## 2. 검증 — 대부분 green

| 항목 | 결과 |
|---|---|
| 20G 성능 (dev vs tip, cold·교대·warmup1+valid3, 8/8 rc=0) | dev 중앙값 597.5s vs tip 173.4s = **3.45×**, B5 171.7s 대비 +1% (노이즈) — 후퇴 없음 |
| 안정성 매트릭스 (kill-switch 4조합 / empty·1행 / serial / crash-restart 5회) | 전부 PASS |
| U-OV3 (campaign/dwb-on/smallbuf × 3) | 9/9 PASS |
| marker micro oracle (MK/CP delta, sticky root) | PASS |
| 실패 주입 진단 캠페인 (격리 diag 빌드): marker alloc/pack 실패, BTID/create-LSA/class-set 불일치 거부, temp retire 전파, 발행 직전 호환 거부, 2PC prepare/commit 가드 | **9/9 PASS** |
| 혼합 버전: 구클라→신서버, 신클라→구서버 (Tier-A 실측) | PASS (legacy wire 형식 유지) |
| R7 savepoint rollback + 클라이언트 kill 인터럽트 | PASS (카탈로그 0, 재시도 OK, checkdb 0) |
| R10 다수 marker + 대형 redo 재시작 상한 | PASS (marker 15개 3.10s ≈ marker-free 3.10s, RSS 평탄) |

## 3. 진행 중 — R4 복원 시나리오에서 실결함 포착 (캠페인의 성과)

백업 중 no-redo 빌드 → DROP → 로그드 방식 재생성 → 아카이브 롤오버 → restoredb 완전 재생 시나리오에서:

- **증상**: 데이터는 최신 시점까지 재생됐는데(replay 완주 확인) 커밋된 재생성 인덱스가 복원본에서 소실.
- 1차 수정: cleanup publication walk에 카탈로그 supersession 게이트 추가 — 반영했으나 증상 지속.
- **심화 분석 중**: 복구 UNDO 단계가 커밋된 트랜잭션 11개를 되돌리는 오분류 확인(재생성 트랜잭션의 카탈로그 삽입이 UNDO됨, 이후 UPDATE 트랜잭션은 생존). 정적 리뷰가 우려만 했던 §4/§5 축을 동적 검증이 실제로 잡아낸 것. 아키텍트 에이전트가 보존된 복원 산출물로 원인 체인 추적 중.

## 4. 남은 일

1. R4 오분류 원인 확정 → 수정 → 재빌드 → R4 green.
2. cleaner 재실행 + architect/executor QA 최종 게이트 → 스토리 체크포인트.
3. status report 정본 → push (xmilex) → JIRA CBRD-27071 강등 정책 코멘트 → 결정 원장 체크박스.

증거: `/home/cubrid/dev/bkx-review-response/evidence/` (진단 결과 tsv, 성능 tsv, 복원 산출물 보존).
