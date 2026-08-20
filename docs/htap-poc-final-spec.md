# HTAP 파이프라인 스펙 — CUBRID → Debezium → Kafka → ClickHouse

**현재 판정: 사내 파일럿 GO (조건부)** — 2026-08-20, [#81 종착 게이트 재판정](https://github.com/xmilex-git/workspace/issues/81) / [#74 제품화 2차 지도](https://github.com/xmilex-git/workspace/issues/74).
이력: POC 완료 GO(2026-08-17, [#42](https://github.com/xmilex-git/workspace/issues/42)/[#30](https://github.com/xmilex-git/workspace/issues/30)) → P0 silent-corruption 차단 해소(#74) → 파일럿 게이트.
후속 과제(공식 1.0): [docs/htap-poc-future-work.md](htap-poc-future-work.md).

이 문서는 **현재 고정된 파일럿 pair의 스펙**이다. "GO"는 통제된 사내 파일럿 진입 판정이며, 공식 1.0 일반 출시 판정이 아니다(공식 1.0은 다음 지도의 destination).

---

## 0. 고정 파일럿 pair (immutable tag `htap-pilot-20260820`)

배포 전 양 저장소에서 `git rev-parse htap-pilot-20260820`로 확인한다.

| 구성요소 | 저장소 / 브랜치 | tag | 기능 커밋 |
|---|---|---|---|
| 엔진 | `xmilex-git/cubrid` `htap/cdc-select-privilege` | `htap-pilot-20260820` | `bdbeaf3f1` (temporal wire v2) |
| 커넥터 | `xmilex-git/debezium-connector-cubrid` `main` | `htap-pilot-20260820` | `85ac725` (temporal wire v2 + TZ 4종) |

---

## 1. 아키텍처

```
CUBRID 서버 (supplemental_log=1, 파일럿 pair 엔진)
  │  cubrid_log CDC extraction 프로토콜 — 순수 Java wire client (네이티브 lib·JNA 불요, ADR 0012)
  ▼
debezium-connector-cubrid (Kafka Connect source, 독립 저장소)
  │  스냅샷: CUBRID JDBC(broker 경유) + barrier LSA, 쓰기 정지 불요 (ADR 0009)
  │           barrier 세션 node identity를 offset에 stamp (ADR 0010)
  │  스트리밍: trid별 버퍼링 — COMMIT publish / ABORT·부분 rollback 폐기 (ADR 0004/0007)
  │  relation identity fail-closed: empty/include-외 announce·TABLE DDL halt (ADR 0008/0011)
  │  temporal wire v2: TIMESTAMP=UTC instant / DATETIME=zone-less / TZ 4종=offset 보존 (ADR 0006, #76)
  │  기동 가드: UTF-8 charset·미지원 타입·node identity fail-fast
  │  SMT: ExtractNewRecordState + rename/cast → 평탄화 + _op/_version/_is_deleted
  ▼
Kafka — 토픽 `<topic.prefix>.<owner>.<table>` (owner 정규화, ADR 0011 D8)
  ▼
공식 ClickHouse Kafka Connect Sink (전용 htap_sink 유저)
  ▼
ClickHouse — ReplacingMergeTree(_version, _is_deleted) + canonical FINAL view (OLAP 엔드포인트)
```

- 인프라: rootless podman 단일 노드, `htap-poc/infra/`. Connect는 debezium/connect, 커넥터는 순수 Java 플러그인 jar 세트로 자립(설치본·`LD_LIBRARY_PATH` 불요, ADR 0012).
- 코드 배치: 커넥터→독립 저장소 `xmilex-git/debezium-connector-cubrid` / 하네스·compose·검증 스크립트→이 repo `htap-poc/{infra,harness,e2e,sink}` / 엔진 실험→cubrid 워크트리.

## 2. 전달·정합성 계약

- **at-least-once + 결정적 `_version` → ReplacingMergeTree 수렴.** 재시작·재전송 중복은 동일 `_version`으로 RMT가 접고 canonical view는 byte-identical 수렴(전체 토픽 재전송 실측). exactly-once 미제공.
- `_version` = `epoch[16] | counter[48]`(epoch 1.0 상수 0). 스냅샷 행 `_version=0` → 어떤 CDC 이벤트에도 짐 → 스냅샷·스트리밍 중첩 무해.
- **committed-only**: 커밋 전 트랜잭션은 커넥터 메모리 버퍼, ABORT 폐기. savepoint·문장 rollback도 정확히 걸러짐(엔진 rollback 마커 해석, [#47](https://github.com/xmilex-git/workspace/issues/47)/ADR 0007 — POC의 부분-rollback 팬텀 P0 해소).
- **fail-closed 원칙**: 데이터 복구 불가 상태를 성공처럼 처리하지 않는다 — relation 불명·include mismatch·target 부재·TABLE DDL·미지원 타입·비 UTF-8·node 불일치·구 temporal wire는 전부 명시적 halt/거부.

## 3. 확정 설계 결정 (ADR 색인)

| ADR | 결정 | 요지 |
|---|---|---|
| 0002→**0012** | log client | JNA-first(0002)는 **순수 Java wire client + 독립 저장소(0012)로 대체** — 네이티브 crash·`.so` ABI·설치본 마운트 의존 제거 |
| 0003 | full image 병합 | `all_in_cond=1` → `cond(before) ⊕ changed(after)` full after-image. DELETE는 PK만 |
| 0004 | 카운터 position | 결정적 비-TIMER 카운터, offset=4키, anchor=oldest in-flight txn 시작 |
| 0005 | JDBC 스냅샷 barrier | JDBC 스냅샷 + barrier LSA, snapshot `_version`=0, `max.threads=1` |
| 0006 | E2E 배포·temporal | SMT 체인, **temporal wire v2**(TIMESTAMP=instant/DATETIME=zone-less/TZ 4종=offset, #76) |
| 0007 | txn 버퍼 Oracle parity | trid별 버퍼 + opt-in threshold/retention → 초과 시 abandon(Oracle LogMiner 동형) |
| 0008 | DDL halt | captured 테이블 ALTER/DROP/RENAME/TRUNCATE halt, 복구는 resnapshot |
| 0009 | online 스냅샷 | 쓰기 정지 불요(RR + barrier), signal 기반 blocking snapshot |
| 0010 | HA halt master-only | non-master·node 불일치 halt, barrier node identity stamp |
| 0011 | 권한·relation 사전 | per-table SELECT 인가, in-band relation 사전, owner 정규화 토픽 |

## 4. 알려진 제약 (파일럿 수용 조건 / 공식 1.0 이관)

**파일럿에서 가드로 강제(자동 차단)** — 상세: 커넥터 `docs/support-scope.md` §5-14.
- UTF-8 DB only·미지원 타입·relation identity·node identity·temporal lockstep — 위반 시 기동/스트림 fail-fast.

**파일럿에서 운영 규율(운영자 책임)** — support-scope §5-14.
- CDC 포트 망 격리(firewall allowlist), DB당 커넥터 1개(엔진 단일 세션), JDBC/CDC same-server, 고정 include list + 변경 시 resnapshot, 재설치 후 `supplemental_log` 재확인, 계획 DDL은 커넥터 정지 후, 고정 tag pair.

**공식 1.0으로 이관(다음 지도, future-work.md)** — 아래는 Debezium GA 레퍼런스(Oracle/MySQL) 대비 판단.
1. **OLAP 성능 미증명** — 정합성 전용. FINAL 오버헤드·catch-up lag·직접 분석 대비 이득 미측정. 투자 결정 관문.
2. **트랜잭션 버퍼 상한·spill** — 기본 무제한(in-memory) + opt-in abandon. **Oracle LogMiner GA와 동형**(heap 기본 + threshold 초과 시 lossy drop). 공식 1.0 개선은 운영 guidance + off-heap/spill opt-in(하드 byte cap은 Debezium 표준 초과).
3. **서버측 CDC 인증·TLS** — CDC 포트는 서버 보안 경계 아님(망 격리 필수). **Debezium 레퍼런스도 전송 보안은 DB/드라이버·망에 위임**(커넥터가 구현하지 않음) — 다만 CUBRID 엔진의 서버측 인증 모델 자체가 별건(ADR 0011 D11, 엔진팀).
4. **at-least-once** — 물리 중복은 canonical view에서 수렴. raw `_local` 직접 조회 미지원.
5. **고정 스키마 + DDL halt** — 자동 schema evolution 없음(halt→resnapshot). **SQL Server·Db2 GA도 동일 posture**(offline 절차/재스냅샷).
6. **HA failover 이어읽기 미지원** — 새 master에서 resnapshot. epoch 비트 자리 예약만.

## 5. 증거·재현 색인

- **파일럿 게이트 번들**: `htap-poc/e2e/evidence/pilot-gate-20260820/`(SUMMARY + 10 스위트 로그), 클린 단일 실행은 `run-pilot-gate.sh`(SHA·image digest 헤더 자동 기록).
- e2e 스크립트: `htap-poc/e2e/` — `run-e2e.sh`·`diff-check.sh`·`run-faults.sh`(S1-S4)·`run-snapshot-faults.sh`·`run-blocking-snapshot.sh`·`run-owner-collision.sh`·`run-partition-ddl.sh`·`run-tz-types.sh`·`run-relation-fault.sh`·`run-port-isolation-denial.sh`.
- 단위: 커넥터 122/122(비UTC JVM matrix 포함).
- 커넥터: `xmilex-git/debezium-connector-cubrid` tag `htap-pilot-20260820`. 엔진: `xmilex-git/cubrid` tag `htap-pilot-20260820`.
- 리뷰 원문: `docs/reviews/`(issue-30 POC, issue-48 P0 전수, issue-74 파일럿 게이트).
- POC(#30) 완료 계약 판정표·ADR 상세는 [#42](https://github.com/xmilex-git/workspace/issues/42)·`docs/adr/` 참조(이력 보존).
