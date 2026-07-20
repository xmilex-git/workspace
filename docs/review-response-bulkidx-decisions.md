# 리뷰 대응 결정 원장 — `code-review-bulkidx-noredo-parallel-r304-wip.md` (2026-07-18)

grill 세션에서 확정된 결정과 이행 대기 작업. 리뷰 15건의 사실검증·성능판정은 세션 기록 참조
(요지: 15건 전부 사실, 빌드 핫패스를 늦추는 수정 없음, 11·12·14는 성능 개선).

## 확정된 결정

| # | 결정 | 근거 문서 |
|---|---|---|
| P1 4·5·6 | **server-issued create LSA 단일 identity로 통합 봉인** (marker create_token 교체, 클라 provenance는 힌트로 강등, suppression/cleanup은 (VFID, create LSA) 정확 일치 + 모호 시 fail-safe) | ADR-0003 |
| P1 7·8 | **혼합 버전 자동 강등**: log 호환 게이트로 marker 발행 금지 시 legacy 로깅 빌드로 자동 전환 + NOTIFICATION 1줄 관측. #7 wire versioning은 동반 선행 | ADR-0004 |

## 이행 완료 (2026-07-19)

- [x] **구현·검증·push 완료** — 15건 전부 + 추가 결함 2건(restore supersession 게이트,
      logged 병렬 빌드 topop 데드락) 수정. 커밋 `81b91701a` (xmilex
      `bulkidx/noredo-parallel-r304-wip`). 최종 보고:
      `docs/status-report-20260719-bulkidx-review-response-final.md`.
- [x] **JIRA CBRD-27071에 혼합-버전 자동 강등 정책 코멘트** — 2026-07-19 게시(코멘트 id
      4775274, 커밋 해시 포함, late-join은 릴리스 log 호환성 표 사안임을 명시).

## 확정 (grill 종결, 2026-07-18)

- P1 1·2·3·9·10 — 수정 확정 (성능 0).
- P2 11·12·13·14·15 — **전부 이번 머지 게이트 포함** (보스: "전부 포함"). 14는 ovf 리필 청크
  상향 + overflow workload 실측 동반.
- 스펙 경계 확인: 서버 동작 변화는 CREATE INDEX(와 그 marker 복구) 한정, 유일한 신규 스펙은
  ADR-0004 강등+NOTIFICATION. 구현 제약 2건(FILE_HEADER 필드 추가 금지 / log compat은 릴리스
  표 사안) 포함 — 상세와 착수 절차는 **`docs/spec-bulkidx-review-response-implementation.md`
  (실행 정본)**.

## ADR-0005 후속 (2026-07-19)

- [x] 복원 가용성: churn 창은 walk 생략 + 운영자 안내(영/한), restoredb 항상 완료. no-redo는
      병렬 관여 시에만(직렬은 logged 강등, marker 미발행). 커밋 `86d581d4f` push, JIRA 본문·
      분석서·검증 시나리오 교체 완료. 근거: `docs/adr/0005-...md`.

## 스펙 피벗: ADR-0006 (2026-07-20, grilling 세션 확정)

- no-redo 빌드는 **CS loaddb 한정**(client type 3종: LOADDB_UTILITY + COMPAT_UNDER_11_2/11_4 —
  compat은 구버전 unload 이관 모드), UNIQUE/PK 포함, online 제외, SA 구조 배제, 옵션 신설 없음.
- 판정 전부 서버측(`logtb_find_client_type`) → **클라이언트·wire·connection diff 0으로 원복**.
- marker = payload 없는 **replay 차단벽**(빌드 관문 직후 서버 단독 발급). identity·pending·
  발행 결합·청소 walk·suppression·repair **전부 삭제**. ADR-0003/0004/0005 대체.
- restoredb는 차단벽에서 전용 에러(영/한)로 즉시 실패(시점 복원·백업 자체 복원은 정상,
  재기동은 무해 통과). "불완전 인덱스가 남는 상태"는 도달 불가.
- 커밋 전 관문은 전역 flush로 단순화 — **별도 커밋**(성능 회귀 시 단독 revert 계약).
- JIRA: 티켓 Summary를 "support no logging-per-page parallel index build"로 변경 + 본문/자료
  전면 재작성 포함.

## ADR-0006 이행 (2026-07-20)

- [x] **커밋 A `587c8236e`** — loaddb-한정 피벗 + 기계 전체 삭제(32파일 +221/−5,059).
      merge-base 대비 잔존 17파일(+4,211/−926): 빌드 경로 + boot.h 매크로 + 서버 술어 +
      barrier 레코드 + 복구 거부 + msgcat. client/wire/connection/locator/schema_manager/
      execute_schema/file_manager/log_2pc/vacuum/log_writer = diff 0 감사 통과.
- [x] **커밋 B `88f74c4a2`** — scoped barrier 삭제, 전역 flush 승격(+37/−310; page_buffer는
      PR 7487 3-hunk만 잔존). 워커 write-through는 `pgbuf_flush_with_wal`(fixed-page flush)로
      대체. 단독 revert 계약 유지.
- [x] **PIT 판별 교정** — 시간 기반 stop은 완결 레코드에서만 멈추므로 redo가 차단벽을
      물리적으로 지나간다. 거부 기준을 "조우"에서 "빌드 트랜잭션이 replay 창 안에서 완결"로
      교정(analysis가 완결 트랜잭션을 테이블에서 제거하는 불변식 사용). -d 시점복원은 성공하고
      undo가 인덱스 파일을 제거해 "문장 미실행 상태"가 된다.
- [x] **운영자 메시지 교정** — `er_set(ER_GENERIC_ERROR)`가 포맷 인자를 버리던 결함 제거,
      fatal 포맷에 안내문+barrier LSA 직접 탑재(콘솔/에러로그 양쪽 실측 확인).
- [x] **검증 (release, 커밋 A/B 각각)** — utility/compat loaddb 발화(marker=1, 빌드 txn
      COPYPAGE=root뿐), csql/SA 비발화, kill-9 재기동 무해 통과, full-replay 거부(메시지 노출),
      -d 시점복원 성공(인덱스 부재·데이터 보존·checkdb 0), post-barrier 백업 full 복원 성공.
      debug 빌드 green.
- [x] **계측 사고 2건 규명** — 이전 세션의 LOADDB_MARKER=0은 ① diagdb 로그 덤프가 중간
      레코드에서 조용히 죽는 upstream 결함(develop 바이너리 동일 재현, rc=254) + ② `just
      build`가 설치본 conf를 리셋해 `parallel_sort_page_threshold` 소실 → 직렬 강등. 코드
      결함 아님. 계수는 역방향 tail 덤프로 교정, conf는 빌드 후 재적용 절차화.
- [x] 20G 성능(3-way: dev / 커밋 A / 커밋 B, loaddb 주도, cold 교대): dev 669.2s / A 231.6s /
      B 196.0s — **B가 A보다 15% 빠름, B 유지 확정(revert 불요)**, develop 대비 3.41×.
- [x] push 완료(xmilex, 7d0a58740..88f74c4a2) + JIRA 갱신 완료 — Summary
      "Support no logging-per-page parallel index build", 본문 교체, 첨부 3종 교체(analysis/
      verification/tc-bundle v2 — TC는 loaddb 주도로 전면 재작성·실행 검증), 코멘트 4775284.
      최종 보고: `docs/status-report-20260720-bulkidx-loaddb-pivot.md`.
