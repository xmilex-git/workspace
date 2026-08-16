# HTAP 제품화 후속 과제 — 차기 wayfinder 지도 입력

**용도**: [HTAP Compact POC](htap-poc-final-spec.md)가 GO로 종결([#42](https://github.com/xmilex-git/workspace/issues/42))된 뒤 남은 과제의 단일 정리본. **차기 wayfinder charting 세션의 입력 문서**로 쓴다 — 여기의 항목들은 fog이지 티켓이 아니며, 차기 지도의 destination grilling에서 재단된다.

**분리 기준** ([#42](https://github.com/xmilex-git/workspace/issues/42) Q2 확정): "제품화 **투자 결정** 전에 반드시 답해야 하는가". 필수 3건이 투자 결정 관문이고, 선택 7건은 투자 확정 후 제품화 단계의 일이다.

출처: [#30 지도](https://github.com/xmilex-git/workspace/issues/30)의 잔여 fog + 후속 외부 리뷰 §7 (`docs/reviews/issue-30-post-gate-review-excerpt.md`).

---

## 필수 — 제품화 투자 결정 관문 (3건)

### 1. 엔진 보강: supplemental log에 savepoint/문장 rollback 마커 → **[#47](https://github.com/xmilex-git/workspace/issues/47) 등록됨**

- **문제**: savepoint(s06)·문장 실패(s10) 부분 rollback이 스트림에 보상 없이 남아 팬텀 행·`_version` 오염. 영향권은 "문장 실패를 catch하고 계속 진행하는 모든 앱" — 워크로드 배제 비현실적. 임의 트래픽에 P0 blocker, **엔진 보강 전 제품화 NO-GO** (후속 리뷰 §7.1).
- **확정 스펙** (#42 Q1, 마커 최소안): `SAVEPOINT-BEGIN(trid, sp_id)` + `ROLLBACK-TO(trid, sp_id)` 레코드 2종 추가, 커넥터는 trid 버퍼를 sp_id 지점까지 되감기. 상세 스펙·선행 확인·검증 기준·PostgreSQL 선례(삼중 불변식, 파일:라인 근거)는 [#47](https://github.com/xmilex-git/workspace/issues/47) 본문에.
- 엔진 패치 절차: D9 (cubrid 워크트리 브랜치, 사용자 확인 후).

### 2. 성능 벤치마크 — 투자 결정의 관문 티켓 (차기 지도 1번)

POC는 정합성 전용이었고 벤치마크는 한 번도 없었다 (후속 리뷰 §7.3). "경로가 동작한다"까지만 증명됐고 "분석이 빨라진다·투자 가치가 있다"는 미증명. 측정 항목:

- CUBRID supplemental logging overhead (OLTP 쓰기 경로 영향)
- Debezium/JNA extraction throughput, Kafka·sink 처리량
- 정상·장애 후 catch-up lag
- **ClickHouse `FINAL` 조회 비용** — canonical view의 FINAL이 이득을 갉아먹을 수 있음
- update-heavy workload의 RMT physical amplification
- **CUBRID 직접 분석 대비 실제 성능 이득** — 이것이 곧 투자 결정 기준

### 3. 트랜잭션 버퍼 상한·spill·backpressure

현재 trid별 DML은 COMMIT까지 in-memory 무제한 (후속 리뷰 §7.2). 수백만 행·장기 미커밋·다수 동시 txn에서 Connect worker OOM 가능. 벤치마크(2번)가 update-heavy·대형 txn을 돌리는 순간 이것의 부재가 벤치마크 자체를 무너뜨리므로 2번과 사실상 한 몸. 최소 요건:

- txn별·전체 buffered bytes limit, disk spill 또는 source-side pause/backpressure
- max transaction age + 운영 경보, 재연결 시 in-flight state 규칙, OOM 전 fail-fast

## 선택 — 투자 확정 후 제품화 단계 (7건)

4. **DDL / schema evolution** — §7.8 schema barrier·shadow rebuild. POC는 스키마 고정 가정 (후속 리뷰 §7.4).
5. **online snapshot token** — 쓰기 정지 없는 §8.2/§8.3 스냅샷 + incremental/resnapshot 운영 절차 (후속 리뷰 §7.4).
6. **HA failover·epoch 실검증** — `_version`의 epoch 비트는 자리만 예약됨. failover·split-brain·old primary 재등장 미검증 (후속 리뷰 §7.5).
7. **JNA worker 격리 또는 순수 Java 포팅 + upstream 제출** — 네이티브 crash=worker 사망, CUBRID 설치본 마운트 의존, `.so` ABI 결합 (후속 리뷰 §7.6, ADR 0002 escape hatch). 프로토콜 지식은 하네스 C 코드·ADR에 박제됨.
8. **CDC 전용 권한 (`CDC_READER`)** — 현재 DBA 그룹 의존 (§3.3-7).
9. **type mapping 경계 corpus** — §9.9/§18.2 차등 테스트 전집. POC는 실제 컬럼 타입만 다룸.
10. **evidence bundle·빌드 SHA 고정 (Gate E)** — 정합성 아닌 재현성 과제 (1차 리뷰 §5 P1-3·P2-2).

## 참고 — 원 지도의 Out of scope (재개하려면 새 destination 필요)

HTAP Gateway/쿼리 라우팅/freshness token (§10) · DBLink↔ClickHouse (§11) · K8s/멀티샤드 (§14) · StarRocks/Doris (§13) · XA/2PC·HA failover fault campaign (§15.2/§18.1) — [#30](https://github.com/xmilex-git/workspace/issues/30) D4·D5 참조.
