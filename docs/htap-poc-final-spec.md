# HTAP Compact POC 최종 스펙 — CUBRID → Debezium → Kafka → ClickHouse

**판정: GO** (2026-08-17, [#42 Go/No-Go 판정 및 지도 종결](https://github.com/xmilex-git/workspace/issues/42))
지도: [#30 HTAP 지도](https://github.com/xmilex-git/workspace/issues/30) · 근거 제안서: `htap-cubrid.md` · 후속 과제: `docs/htap-poc-future-work.md`

여기서 GO는 **"§1.3 완료 계약 충족, POC 종결"**이다. 제품화 투자 승인이 아니다 — 투자 관문은 후속 지도의 성능 벤치마크와 엔진 보강([#47](https://github.com/xmilex-git/workspace/issues/47))으로 분리됐다.

---

## 1. 아키텍처 최종형

```
CUBRID (supplemental_log=1, 워크트리 빌드)
  │  cubrid_log C API (libcubrid_log, JNA 래핑 — ADR 0002)
  ▼
debezium-connector-cubrid  (fork xmilex-git/debezium, 브랜치 cubrid-connector, 커밋 490a3a8)
  │  스냅샷: CUBRID JDBC + Debezium relational 프레임워크 (barrier LSA = JNA find_lsa — ADR 0005)
  │  스트리밍: trid별 버퍼링, COMMIT-publish / ABORT-폐기, 카운터 position (ADR 0004)
  │  SMT: ExtractNewRecordState(rewrite) + add.fields=op,source.lsn → _version 승격
  ▼
Kafka (KRaft, kafka:3.8.1) — 토픽 htapcdc.htapdb.<table>, 계약=post-SMT 평탄화 레코드
  ▼
공식 ClickHouse Kafka Connect Sink v1.4.0 (전용 htap_sink 유저)
  ▼
ClickHouse 24.8 — ReplacingMergeTree(_version UInt64, _is_deleted Bool) × 2 테이블
  └─ canonical FINAL view (OLAP 엔드포인트)
```

- 인프라: rootless podman 단일 노드, 스크립트 `htap-poc/infra/` ([#34](https://github.com/xmilex-git/workspace/issues/34)). Connect는 debezium connect:3.0.0.Final, 커넥터 기준 버전 v3.0.0.Final ([#37](https://github.com/xmilex-git/workspace/issues/37)).
- 코드 배치: 커넥터→debezium fork / 하네스·compose·검증 스크립트→이 repo `htap-poc/{infra,harness,e2e,sink}` / 엔진 실험→cubrid 워크트리.

## 2. §1.3 완료 계약 판정표

| # | 계약 항목 | 증거 | 판정 |
|---|---|---|---|
| 1 | CUBRID 단일 DB + ClickHouse 단일 노드 | [#34](https://github.com/xmilex-git/workspace/issues/34) 인프라, [#33](https://github.com/xmilex-git/workspace/issues/33) 워크트리 빌드 | PASS |
| 2 | PK 있는 2~3개 테이블 등록 | [#39](https://github.com/xmilex-git/workspace/issues/39) RMT 2테이블 + canonical view | PASS |
| 3 | 쓰기 정지 초기 스냅샷 | [#38](https://github.com/xmilex-git/workspace/issues/38) ADR 0005 + [#40](https://github.com/xmilex-git/workspace/issues/40) barrier gap 없음 실측 | PASS |
| 4 | cubrid_log I/U/D/COMMIT/ABORT 추출 | [#33](https://github.com/xmilex-git/workspace/issues/33)+[#35](https://github.com/xmilex-git/workspace/issues/35) full image 병합(ADR 0003), [#37](https://github.com/xmilex-git/workspace/issues/37) 스모크 | PASS ⚠A |
| 5 | commit 전 trid별 버퍼링 | [#36](https://github.com/xmilex-git/workspace/issues/36) ADR 0004 + 전제 검증 [#43](https://github.com/xmilex-git/workspace/issues/43)/[#44](https://github.com/xmilex-git/workspace/issues/44) + [#45](https://github.com/xmilex-git/workspace/issues/45) anchor 수정 | PASS ⚠A |
| 6 | RMT full-row upsert + tombstone | [#39](https://github.com/xmilex-git/workspace/issues/39)+[#40](https://github.com/xmilex-git/workspace/issues/40) `_version`/`__deleted` 실측 | PASS |
| 7 | durable LSA checkpoint | [#36](https://github.com/xmilex-git/workspace/issues/36) 4키 offset + [#40](https://github.com/xmilex-git/workspace/issues/40) 재시작 왕복 + [#46](https://github.com/xmilex-git/workspace/issues/46) crash 캠페인 15/15 | PASS |
| 8 | 재시작·중복·CH 장애 복구 | [#41](https://github.com/xmilex-git/workspace/issues/41) 4 시나리오 + [#46](https://github.com/xmilex-git/workspace/issues/46) S4 assert 강화 재검증 | PASS |
| 9 | differential check | [#41](https://github.com/xmilex-git/workspace/issues/41) 0 mismatch + [#46](https://github.com/xmilex-git/workspace/issues/46) keyed full-row digest 교체 | PASS ⚠A |
| 10 | 별도 OLTP/OLAP 엔드포인트 | CUBRID:33000 / ClickHouse canonical view ([#40](https://github.com/xmilex-git/workspace/issues/40)) | PASS |

**⚠각주 A — 부분 rollback 팬텀**: savepoint(s06)·문장 실패(s10) 경로에서 취소된 DML이 supplemental log에 보상 없이 남아 팬텀 행·`_version` 오염을 만든다. 항목 4·5·9는 **이 제약 밖의 워크로드에서 통과**다. 알려진 제약으로 명기하고 PASS 처리([#42](https://github.com/xmilex-git/workspace/issues/42) Q1 확정), 엔진 보강은 제품화 선결 P0 → [#47](https://github.com/xmilex-git/workspace/issues/47).

**외부 리뷰 Gate**: A([#45](https://github.com/xmilex-git/workspace/issues/45) anchor 조기 전진 수정, fork 490a3a8) · B+C+D([#46](https://github.com/xmilex-git/workspace/issues/46) keyed oracle + crash point 4종+interleaved 15/15 PASS, 커밋 673a6fd) 전부 해소. E(빌드 SHA·evidence bundle)는 재현성 과제로 제품화 이관. 리뷰 원문: `docs/reviews/issue-30-go-no-go-review.md`, 후속 리뷰 발췌: `docs/reviews/issue-30-post-gate-review-excerpt.md`.

## 3. 확정 설계 결정 (ADR 색인)

| ADR | 결정 | 요지 |
|---|---|---|
| [0002](adr/0002-debezium-connector-jna-first.md) | JNA-first | `cubrid_log`를 JNA로 래핑. 순수 Java 프로토콜 포팅은 escape hatch — **#42 확정: POC는 JNA로 종결**, 포팅·upstream 제출은 제품화로 이관 |
| 0003 | full image 병합 | all_in_cond=1이면 cond=full before-image. 커넥터가 `cond(before) ⊕ changed(after)`로 full after-image 생성 — **엔진 패치 불요**. DELETE는 PK만(PG REPLICA IDENTITY DEFAULT 상당) ([#35](https://github.com/xmilex-git/workspace/issues/35)) |
| 0004 | 카운터 position | per-item LSA 부재 → 결정적 비-TIMER 아이템 카운터 합성. offset=flat 4키(page_id/lsa_offset/seq/epoch), anchor=oldest in-flight txn 시작 배치 경계, `_version`=epoch[16]\|counter[48]. 전제 ①replay 결정성([#43](https://github.com/xmilex-git/workspace/issues/43))·②recovery ABORT 방출([#44](https://github.com/xmilex-git/workspace/issues/44)) 실측 확정. **개정: 부분 rollback 팬텀 = 알려진 제약** ([#36](https://github.com/xmilex-git/workspace/issues/36)) |
| 0005 | 스냅샷 | JDBC 스냅샷 재사용, 쓰기 정지=운영자 절차+RR 승격, barrier LSA는 JNA 캡처, snapshot `_version`=0, max.threads=1 ([#38](https://github.com/xmilex-git/workspace/issues/38)) |
| [0006](adr/0006-e2e-deployment-and-impl-decisions.md) | E2E 배포·구현 10건 | SMT 체인(`add.fields.prefix=""`+rename, `__deleted` ReplaceField+Cast), DATETIME=CUBRID 기본 출력 포맷 등 ([#40](https://github.com/xmilex-git/workspace/issues/40)) |

주요 파생 계약: 전달 시맨틱은 **at-least-once + 결정적 `_version` → RMT 수렴** ([#41](https://github.com/xmilex-git/workspace/issues/41)에서 canonical byte-identical로 실증). anchor는 커밋 중 트랜잭션 자신을 포함한 oldest in-flight 시작점, inflight 제거는 publish 후 ([#45](https://github.com/xmilex-git/workspace/issues/45), 단위 테스트 5종).

## 4. 알려진 제약 (GO에 명기된 수용 조건)

1. **부분 rollback 팬텀 (P0 제품화 선결)** — savepoint·문장 실패 워크로드 미지원. 임의 앱 트래픽에는 blocker. 엔진 보강 [#47](https://github.com/xmilex-git/workspace/issues/47) 전까지 제품화 NO-GO.
2. **OLAP 성능 미증명** — 이 POC는 정합성 전용. FINAL 오버헤드·catch-up lag·CUBRID 직접 분석 대비 이득은 벤치마크 전무. 후속 지도 1번 티켓이자 제품화 투자 결정 관문.
3. **무제한 트랜잭션 버퍼** — COMMIT까지 in-memory, 상한·spill·backpressure 없음 (30k 실측은 통과). 후속 리뷰 §7.2.
4. **at-least-once** — 중복은 동일 `_version`으로 RMT 수렴. exactly-once 미검증.
5. **DATETIME tz** — 세션 tz 운영 규율로 완화 가능한 알려진 제약.
6. **고정 스키마 + 쓰기 정지 스냅샷** — DDL/schema evolution·online snapshot 미지원. offset만 삭제하는 운영 금지(스냅샷과 결합).

## 5. 증거·재현 색인

- 하네스: `htap-poc/harness/` (P0 실측 s00~s10 덤프), `htap-poc/infra/` (podman 기동), `htap-poc/sink/` (RMT+sink 설정), `htap-poc/e2e/` (E2E·장애·crash 캠페인, `diff-check.sh`·`run-faults.sh`)
- 커넥터: `xmilex-git/debezium` 브랜치 `cubrid-connector`, 최종 커밋 [490a3a8](https://github.com/xmilex-git/debezium/commit/490a3a8)
- 이 repo 증거 커밋: 673a6fd([#46](https://github.com/xmilex-git/workspace/issues/46)), 120bcf4([#41](https://github.com/xmilex-git/workspace/issues/41)), d2449d5(s10 팬텀 실측)
- 결정 레코드 D1~D10: [#30](https://github.com/xmilex-git/workspace/issues/30) 첫 코멘트
