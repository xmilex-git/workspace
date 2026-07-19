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
