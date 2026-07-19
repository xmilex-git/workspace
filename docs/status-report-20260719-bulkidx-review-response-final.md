# bulkidx 리뷰 대응 캠페인 — 최종 보고 (2026-07-19)

대상: `xmilex/bulkidx/noredo-parallel-r304-wip` (base `d3e8dc262`), 머지 게이트 CBRD-27071.
스펙: `docs/spec-bulkidx-review-response-implementation.md` (우선순위: 스펙 > ADR-0003/0004 > 리뷰 원문).

## 결론

리뷰 **P1 10건 + P2 5건 전부 구현·검증 완료**. 검증 도중 발견한 추가 결함 2건(복구 supersession,
logged 병렬 빌드 데드락)까지 수정. 클리너 CLEAN, 크리틱 APPROVE(MUST-FIX 0), debug+release+diag
빌드 green, 전체 매트릭스·복구·혼합버전·성능 게이트 통과.

## 구현 요약 (15건 + 추가 2건)

- **P1-1** repair 경로 compensate 후 `pgbuf_set_dirty(DONT_FREE)` (btree.c).
- **P1-2** FORCE topop: marker size/pack/append를 sysop attach 전으로 이동, 실패 전부 abort 라벨로.
- **P1-3** `TRAN_UNACTIVE_COMMITTED_INFORMING_PARTICIPANTS`도 irreversible 2PC 상태로 인정.
- **P1-4/5/6 (ADR-0003)** server-issued create LSA 단일 identity: `FILE_BTREE_DES`에 크기 불변
  저장(디스크 포맷 불변), `(tran_index, trid)` 키 pending-build 레지스트리
  (register/validate/consume/requires_marker/discard), suppression/cleanup은 `(VFID, create LSA)`
  정확 일치 + 모호 시 fail-safe. 공용 토큰 인코더 `btree_bulk_lsa_token` (btree.h).
- **P1-7** `NET_CAP_BULK_NO_REDO` 핸드셰이크 capability + `CSS_CONN_ENTRY.client_capabilities`,
  BTREE_LOADINDEX 요청/응답 4조합(구/신 × 클라/서버) 호환.
- **P1-8 (ADR-0004)** log 호환 게이트: 요청 시 강등 + NOTIFICATION 1줄, 발행 직전
  `wr_list_mutex` 하 재검사(TOCTOU 봉쇄) — 비호환 조인 시 빌드 fail-safe 실패, 재시도는 자동 강등.
- **P1-9** post-force descriptor/OID 처리 + root-class refetch 공용 helper로 legacy parity 복원.
- **P1-10** bulk FORCE + ignore list 조합 서버 거부, pending 중 legacy empty-tail FORCE 거부.
- **P2-11** completion event 추적을 marker 수집 트랜잭션으로 한정(bounded events[4]).
- **P2-12** marker 0개 fast path + VFID/volume 색인.
- **P2-13** `file_temp_retire` rc 확인 후에만 `VFID_SET_NULL`, 실패 전파.
- **P2-14** ovf pool 전량 선할당 → bootstrap(워커당 256) + NEED_OVF 리필.
- **P2-15** tail unpack caller-owned buffer 정확 길이 복사 + NUL.
- **추가 A (supersession 게이트)**: restoredb cleanup publication walk를 "카탈로그가 여전히
  marker의 BTID에 constraint를 바인딩할 때"로 제한 — 아니면 identity-exact orphan 파일만 제거.
- **추가 B (logged 병렬 데드락, 실결함)**: `xbtree_load_index`가 logged 빌드에서 setup 시점
  sysop을 열어 tdes topop rmutex를 px 워커 대기 내내 보유 → 워커 temp 파일 생성과 ABBA 데드락
  (gdb 스택 확증). setup-time sysop 제거로 merge-base 규율 복원. **이 경로는 ADR-0004 강등이
  신클라이언트에도 태우는 경로** — 혼합버전 윈도우의 P1급 hang을 머지 전에 제거.

## 검증 (최종 바이너리 기준 전부 재실행)

| 게이트 | 결과 |
|---|---|
| 매트릭스: kill-switch 4조합 / empty·1행 / serial-path / crash-restart | 전부 PASS |
| U-MARKER-MICRO (sticky-root oracle) | PASS |
| U-OV3 campaign/dwb-on/smallbuf ×3 | 9/9 PASS |
| R4 restore (backup 중 no-redo 빌드 → DROP → 구클라 legacy 재생성 → rollover → restoredb) | PASS (report_lines=0, idx 보존, scan 50000/50000, checkdb 0) |
| R7 savepoint rollback + client-kill interrupt | PASS |
| R10 15-marker + redo-heavy restart 상한 | PASS (~3.1s, RSS ~540MB) |
| 장애 주입 diag 캠페인 (R2/R5/R9/G003 emission·2PC, 9케이스) | VERDICT=PASS, FAILURES=0 |
| 혼합버전: 구클라(legacy wire) 병렬 logged CREATE ×3 + 직렬 + Tier-A 양방향 | PASS (0.17–0.35s, tranlist clean, checkdb 0) |
| debug 빌드(assert 활성) 스모크: no-redo·logged-parallel | PASS, assert 무발화 |
| 20G 성능 (dev 596.7s vs tip 174.0s 3-sample = 3.43×; 최종 바이너리 단일 새니티 189.5s = 3.15×, 게이트 ≥90% 충족) | PASS |

R1 동적 커버리지는 결정론적 트리거 부재로 정적 커버리지만 (diag SUMMARY에 문서화).
R4의 이전 FAIL 2회는 하네스 전제 오류였음(`parallel_sort_page_threshold`는 정렬 병렬성만 제어;
"logged 재생성"은 구클라이언트로 수행해야 구조적으로 보장됨).

## 리뷰 게이트

- ai-slop-cleaner: **CLEAN** (P2/P3 위생 6건 → 전부 반영: 공용 토큰 인코더, pending API 헤더
  선언 통합+doc block, 가드 er_set 서술형 메시지 6곳, 세션 태그/디프-내레이션 코멘트 제거,
  dead 함수 제거).
- critic: **APPROVE**, MUST-FIX 0. 잔여 advisory(후속 문서화): ① n_shards<2 폴스루 + 전행
  NULL key 엣지의 파일 누수 가능성(HEAD 대비 비회귀, 도달성 협소) ② pending 엔트리 savepoint
  생존(fail-safe 방향, R7로 동작 증명, 메시지로 진단 가능) ③ 강등 게이트는 point-in-time —
  late-join 구 consumer 보호는 릴리스 호환성 표 사안(JIRA 코멘트에 명시).

## 증거

`/home/cubrid/dev/bkx-review-response/evidence/` (release-rows/, b5-lane-*/, 20260719-034012/
diag, perf-20g/, oldcli-hang-stacks.txt 등, 20MB 상한 준수).

## 딜리버리

- 커밋: `81b91701a` ("Address code review for the bulk no-redo parallel index build",
  21 files +1138/-261) — `xmilex/bulkidx/noredo-parallel-r304-wip` push 완료 (d3e8dc262..81b91701a).
- JIRA: CBRD-27071 코멘트 게시(id 4775274, 2026-07-19 04:20 KST) — 강등 정책 + late-join
  호환성 표 경계 + 커밋 링크. 게시 후 재조회 검증.
- 결정 원장 체크리스트 갱신: `docs/review-response-bulkidx-decisions.md`.

## 후속 (비차단, 릴리스/후속 PR 사안)

1. record 130(RVBT_BULK_BUILD_DURABLE) log 호환 레벨의 릴리스 호환성 표 등재 — late-join
   구 consumer 차단은 표 사안 (JIRA 코멘트에 명시).
2. n_shards<2 폴스루 + 전행 NULL key 대형 테이블 엣지의 파일 누수 가능성 — HEAD 대비
   비회귀, 도달성 협소 (critic P2, confidence 0.75).
3. pending 엔트리의 savepoint 부분 rollback 생존 — fail-safe 방향(과잉 거부), 서술형
   에러 메시지로 진단 가능. 등록 LSA 기반 discard가 개선안.
4. 강등 NOTIFICATION의 에러 코드가 ER_PT_ERROR 재사용 — 모니터링은 메시지 텍스트 매칭 권장.
