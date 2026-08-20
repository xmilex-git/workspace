# HTAP 제품화 후속 과제 — 공식 1.0 지도 입력

**용도**: POC(#30) → P0 차단 해소·사내 파일럿 GO(#74/#81) 이후 남은 과제의 단일 정리본. **공식 1.0 wayfinder 지도의 입력 문서**다 — 여기 항목은 fog이지 티켓이 아니며 그 지도의 destination grilling에서 재단된다.

**분리 기준**: (a) #74가 이미 해소한 것, (b) 공식 1.0 GA 관문, (c) Debezium GA 레퍼런스(Oracle/MySQL 커넥터) 대비 **표준 초과**라 필수로 볼 필요 없는 것. (c)는 리뷰가 blocker로 지목했더라도 레퍼런스 커넥터도 안 하므로 커넥터-1.0 필수가 아니다.

출처: [#30 POC 지도](https://github.com/xmilex-git/workspace/issues/30) 잔여 fog + [#74 파일럿 지도](https://github.com/xmilex-git/workspace/issues/74) + [#74 재리뷰](reviews/issue-74-pilot-gate-review-nogo-20260820.md) + Debezium Oracle/MySQL 커넥터 조사(2026-08-20).

---

## A. #74에서 이미 해소됨 (공식 1.0 이월 아님)

- **부분 rollback 팬텀** → [#47](https://github.com/xmilex-git/workspace/issues/47)/ADR 0007 엔진 마커 + 커넥터 되감기로 해소(파일럿 pair 포함).
- **temporal 의미론(DATETIME tz)** → wire v2(#76): TIMESTAMP=UTC instant / DATETIME=zone-less / TZ 4종=offset 보존. 운영 규율 아니라 구조로 강제.
- **비 UTF-8 무성 훼손** → 기동 charset fail-fast(#77).
- **relation identity fail-open** → empty/mismatch/DDL halt(#82) + 실 e2e(`run-relation-fault.sh`).
- **snapshot node identity 공백** → barrier stamp + anchored fail-closed(#78).
- **JNA/네이티브 결합** → 순수 Java wire client + 독립 저장소(ADR 0012). 후속 #7 해소.
- **CDC 전용 권한** → per-table SELECT 인가(#68). (단 raw client 전체 스트림은 여전히 DBA — 아래 B-3.)
- **type 경계 corpus** → TZ 4종 포함 실측 corpus + parity(#58/#86). 광범위 corpus는 부분.
- **evidence bundle·SHA 고정** → 파일럿 게이트 번들 + immutable tag `htap-pilot-20260820`.

## B. 공식 1.0 GA 관문 (진짜 필요)

### B-1. OLAP 성능 벤치마크 — 투자 결정 관문 (다음 지도 1번)
POC·파일럿 모두 정합성 전용. 미측정: supplemental logging OLTP overhead(파일럿 pair 재측정), extraction throughput, catch-up lag, **ClickHouse `FINAL` 조회 비용**, update-heavy RMT amplification, **CUBRID 직접 분석 대비 실제 이득**(=투자 기준). 반드시 고정 pair에서.

### B-2. 트랜잭션 버퍼 운영 안전 (Debezium 표준 수준으로)
현재 in-memory 무제한 + opt-in threshold/retention → 초과 시 abandon. **이 설계는 Oracle LogMiner GA와 동형**(heap 기본, `log.mining.transaction.retention.ms`·events threshold 초과 시 lossy drop + JMX 메트릭). 따라서 GA 관문은:
- (표준) heap sizing **운영 guidance 문서** + `AbandonedTransactionCount` 상당 메트릭·경보.
- (opt-in) off-heap/spill 경로(Oracle의 Infinispan buffer 대응) — 로드맵.
- **하드 byte cap·zero-loss는 Debezium 표준 초과**(Oracle도 안 함) → 필수 아님, 문서화로 충분.

### B-3. 릴리스 엔지니어링
- **PGP 서명 아티팩트** — Maven Central 게시 필수 요건(진짜 blocker). protected/signed tag·release.
- 안정 Debezium 릴리스 기준선(현재 `3.7.0.Alpha2`) — Final 계열로. (단 개발 중 non-final parent 의존은 Debezium 자체 out-of-tree 커넥터도 하는 정상.)
- JDBC 드라이버 단일 canonical 버전(현재 CI=공개 0053 / e2e=엔진 번들 0058). Oracle/MySQL은 라이선스상 드라이버 미번들(운영자 설치)이 표준.
- release-grade CI(현재 checkstyle/format/revapi/enforcer skip, live e2e 없음), 문서 consistency 테스트(타입 매트릭스 단일 출처).
- CUBRID org 이관·매뉴얼 편입·"incubating"→GA 성숙도. ("incubating"·fat plugin 번들은 Debezium 정상 관행.)
- **SBOM** — Debezium 커뮤니티도 미발행. org 정책이면 추가, Debezium 규범은 아님.

### B-4. 최종 pair crash campaign
`run-crash-campaign.sh` cp1~cp5(offset flush 경계 crash)를 파일럿 pair에서 1회 재실행(전용 `OFFSET_FLUSH_INTERVAL_MS=1000` 프로파일). 직전 PASS는 #46 Gate B/#83.

### B-5. HA failover 이어읽기 + epoch 실검증
`_version` epoch 비트 실사용, cross-node LSA 매핑, failover 후 자동 재개, split-brain·old-primary 재등장 캠페인. 현재는 halt→resnapshot(수동).

## C. Debezium 레퍼런스 대비 "표준 초과" — 필수 아님 (리뷰가 blocker로 지목했으나)

조사 근거: Debezium Oracle/MySQL 커넥터 실측(2026-08-20).
- **커넥터가 전송 보안(TLS/mTLS/인증)을 구현** — 아님이 표준. Oracle/MySQL 모두 DB 드라이버 TLS + 망에 위임, 커넥터는 전송 암호화 코드 0. (CUBRID 엔진 서버측 인증은 별개 엔진 과제 — ADR 0011 D11.)
- **프로토콜 version/capability negotiation** — 레퍼런스 없음(테스트된 버전 매트릭스로 대체). 우리 lockstep은 오히려 엄격.
- **PK 필수 startup 가드** — 레퍼런스는 거부 안 함(null key + `message.key.columns`). 하드 게이트는 표준보다 엄격.
- **자동 online schema evolution** — 필수 아님. SQL Server·Db2 GA도 halt/offline 절차.
- **unknown 이벤트 fail-closed 강제** — 레퍼런스 기본은 fail이되 `warn`/`skip` opt-in 제공. 설정 가능한 degradation이 표준.
- **atomic target handshake(TOCTOU 제거)** — 레퍼런스는 schema-history 기반 fail-closed(missing schema error)로 충분. 엔진 프로토콜 변경이 필요한 강화는 가치는 있으나 GA 필수는 아님.

## D. 원 지도 Out of scope (재개하려면 새 destination)

HTAP Gateway/쿼리 라우팅/freshness token · DBLink↔ClickHouse · K8s/멀티샤드 · StarRocks/Doris · XA/2PC·HA failover fault campaign — [#30](https://github.com/xmilex-git/workspace/issues/30) D4·D5.
