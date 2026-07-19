# Mixed-version clusters auto-fall back to the logged index build

- Status: Accepted (boss decision 2026-07-18)
- Date: 2026-07-18

## Context

The no-redo bulk build introduces a new WAL record class (RVBT_BULK_BUILD_DURABLE = 130). A log
stream containing it is unreadable by older releases: an old standby in a rolling HA upgrade, or a
downgraded node, fails dispatch on the unknown recovery index and dies at replication/restart
(code review §8). The record is load-bearing — without the marker the no-redo path must not run,
because media recovery could neither suppress nor clean up the unlogged index pages.

## Decision

Marker emission — and with it the whole no-redo/parallel bulk path — is gated on the log-format
compatibility of every log consumer. While an incompatible reader may consume the log (rolling
upgrade window, old standby, pending downgrade), CREATE INDEX **automatically falls back to the
legacy fully-logged build**. The fallback is observable: the server emits one NOTIFICATION line
("bulk build fell back to the logged path: incompatible log consumer") so operators can tell a
policy fallback from a performance regression. The gate rides the existing release/log
compatibility machinery rather than a new handshake.

## Consequences

- Same-version clusters and single-node deployments (every benchmark condition) pay zero cost; the
  measured speedups are unaffected.
- During a mixed-version window index builds run at legacy speed — the only accepted "performance
  loss" scenario of the review, chosen over the alternatives: rejecting CREATE INDEX outright
  (needless outage) or emitting record 130 unguarded (kills old readers — the defect under review).
- The wire-protocol versioning of BTREE_LOADINDEX (review §7) is a prerequisite and ships with the
  same change: legacy peers negotiate `eligible_no_redo = false` and the pre-change reply layout.
- The policy is to be recorded on the public tracking issue (JIRA CBRD-27071) once the
  implementation lands, not before.

## 상태 변경 (2026-07-19): 대부분 폐기(superseded)

리뷰 피드백 검토에서 전제가 반증되었다. merge-base 코드 확인 결과 구버전 log 소비자는 마커
레코드(기존 LOG_REDO_DATA + 신규 recovery index)를 구조적으로 건너뛴다: applylogdb의
la_log_record_process는 레코드 타입으로만 분기하고 REDO 레코드 케이스가 없어 default로
통과하며(레코드 이동은 헤더의 forw_lsa 기반), copylogdb는 레코드를 파싱하지 않고, standby는
active의 WAL을 물리 재생하지 않는다. 따라서 소비자 capability 신호, 발행 시점 재검증, 요청
시점 강등+NOTIFICATION 전부를 제거했다(커밋 7d0a58740). 남는 경계는 "구버전 바이너리로
신버전 로그 체인을 오프라인 복구하지 않는다"는 기존 운영 원칙뿐이다. 본 ADR의 자동-강등
기제 중 유일하게 살아남은 것은 NULL create LSA 반환으로 클라이언트 배선을 우회시키는
서버측 강등 경로이며, 이는 ADR-0005의 병렬-한정 강등이 사용한다.
