# Online snapshot 1.0 — 엔진 확장 없는 커넥터-only 방식 + blocking snapshot, incremental은 post-1.0

HTAP 제품화(지도: xmilex-git/workspace#48, 결정 티켓: #53)에서 초기/재 스냅샷의
1.0 지원 수준을 결정한다. 현행 ADR 0005는 운영자 write-stop barrier를 요구하는데
(§8.1), 운영 DB 쓰기 정지는 제품 도입 장벽이고, DDL halt(ADR 0008)의 유일한 복구
절차가 resnapshot으로 확정되면서 "DDL 한 번 = 쓰기 정지 한 번"이 되는 문제가 있다.

근거 조사 2건(#53 리서치, 원문은 티켓 코멘트):

- Debezium incremental snapshot(DBLog watermark)은 chunk 쿼리가 keyset pagination +
  MySQL-style `LIMIT n`만 사용 — CUBRID에서 SQL 방언 장벽은 없다. 비용은 순전히
  검증(dedup 경계·resume·DDL 상호작용)이며, read-only watermark는 MariaDB/MySQL/PG
  3종만 지원(Oracle도 signal table 쓰기 필수).
- PG/Oracle은 snapshot READ 이벤트에 스냅샷 시점의 현재 LSN/SCN을 실어 version이
  단조 증가 → 재스냅샷을 부어도 자연 수렴하지만, **삭제된 행의 stale 잔존**은
  못 푼다. 채워진 RMT 테이블 재적재의 유일하게 제품화된 절차는 ClickPipes(PeerDB)의
  shadow table + 원자 swap. epoch bump 패턴은 선례 전무이며 삭제 문제도 못 푼다.

## 확정 규칙

**D1 — 1.0은 커넥터-only online snapshot (write-stop 제거)**: 엔진 확장(§8.3
`BEGIN CONSISTENT CDC SNAPSHOT` token) 없이 기존 부품 — barrier LSA JNA 캡처(ADR
0005 D3) + REPEATABLE READ 일관 뷰(D2) + snapshot `_version=0`(D4) + RMT 수렴 —
만으로 쓰기 정지 없는 스냅샷을 1.0에 넣는다. barrier 이후 commit을 스냅샷이 봐도
CDC(counter≥1)가 덮어서 수렴한다(§8.2 논리). write-stop 절차(ADR 0005 체크리스트)는
보수적 fallback으로 운영 문서에 남긴다.

**D2 — fault-test PASS 기준 4종이 1.0 확정 조건**: ① snapshot 중 지속
INSERT/UPDATE/DELETE 워크로드 → diff-check 0 mismatch(overlap 수렴), ② barrier
캡처↔RR 뷰 확립 사이 커밋 인위 주입 → "snapshot에도 CDC에도 없는" 유실 창 부재,
③ barrier 이후 DELETE된 행의 최종 소거, ④ snapshot 중단 후 재수행 경로 수렴.
하나라도 실측 실패 시 escape hatch: write-stop fallback으로 1.0 출고 + 엔진 token
(§8.3) 재소환. 부수 제약 명기: RR 리더는 스캔 동안 DDL을 블록한다(실측, ADR 0005)
— online snapshot 중 DDL은 대기한다.

**D3 — `snapshot.max.threads=1` 유지**: `LIMIT n [OFFSET m]`만으로는 chunked 병렬
initial snapshot의 boundary 쿼리가 불가(ADR 0005). 대형 테이블 스냅샷 소요 시간은
알려진 제약으로 문서화. 병렬화는 post-1.0.

**D4 — incremental snapshot은 post-1.0, 1.0은 blocking snapshot + 선배선**:
incremental(DBLog watermark)은 기술적 불가 논거가 없으나(chunk 쿼리 `LIMIT n`으로
성립) 검증 캠페인 한 벌이 추가되는 비용으로 1.0 제외 — post-1.0 로드맵 1순위
(signal-table 기반 기본형 우선, read-only는 그 다음). 1.0은 같은 신호 체계의
**blocking snapshot**(type=BLOCKING, dedup·watermark 불요, initial과 동일 경로 =
D1/D2 검증이 그대로 커버)으로 "테이블 추가 백필·특정 테이블 재적재" 수요를
받는다. 선배선 2건을 1.0 구현에 포함: (a) offset context 직렬화를 core 규약
(`AbstractIncrementalSnapshotContext`) 호환으로, (b) streaming 경로에
`processMessage()` 훅 호출 지점 확보.

**D5 — resnapshot은 debezium-kafka 표준 부품의 운영 절차, 표준은 shadow swap**:
커넥터/sink에 ClickPipes류 자동 resync 기능을 만들지 않는다. 절차는 운영 문서로:

- **표준**: shadow table + `EXCHANGE TABLES` 원자 swap — sink 테이블 매핑
  오버라이드로 shadow에 적재 → swap → 매핑 복귀. 재적재 중 원본이 계속 서빙
  (가시성 공백 0), 삭제 행 구조적 해결.
- **간이**: truncate 후 재적재 — 공백 노출을 문서화하고 소형/공백 허용 테이블만.
- **금지**: 채워진 테이블에 그대로 붓기 — D4(`_version=0`) 탓에 기존 고버전 행이
  이겨 재적재가 무효이고, 단조 version으로 바꿔도 삭제 행 stale 잔존은 못 푼다.

ClickPipes 대비 약점(자동화 없음, soft-delete 행 이관 없음, swap 수동)은 스펙과
기술지원 가이드에 명시한다.

**D6 — 1.0 signal channel은 Kafka**: blocking snapshot 트리거는 Kafka signal
topic(파티션 1)으로 받는다 — Kafka 스택이라 추가 인프라 0, source signal table의
소스 DB 쓰기 권한 요구를 회피(CDC_READER #55 방향과 정합). source signal table은
post-1.0 incremental의 watermark에 필수라 그때 도입하고, #55 권한 모델에 "signal
테이블 INSERT 권한(post-1.0)"을 메모해 둔다.

## Considered Options

- **write-stop 유지 + 정밀 문서화(A안)**: 구현 0이나 DDL halt 복구마다 운영 쓰기
  정지를 강제 — 1.0 제품성 훼손. 기각.
- **엔진 API 확장(§8.3 token, C안)**: 가장 견고하나 §8.2 수렴 논리가 커넥터만으로
  성립하는지 검증 전에 엔진부터 늘리는 과잉. D2 escape hatch로만 유지.
- **incremental snapshot 1.0 포함**: 검증 캠페인 +1벌 대비 사용자 이득은 "백필 중
  streaming 무중단"뿐 — blocking snapshot이 동일 수요를 얇게 커버. 기각(post-1.0).
- **resnapshot epoch bump / 단조 version 덮어쓰기**: epoch는 선례 전무 + 삭제 행
  잔존을 못 풀고, 단조 version은 D4 재설계에 삭제 행 문제 동일. 기각.

## Consequences

- ADR 0005의 스냅샷 절차 체크리스트 1(쓰기 정지)·6(쓰기 재개)은 fallback 경로로
  강등된다. D3(barrier 캡처)·D4(`_version=0`)·D5(anchor 규칙)는 불변.
- ADR 0008(DDL halt)의 복구 절차 resnapshot이 쓰기 정지 없이 수행 가능해진다.
- 구현·검증은 xmilex-git/workspace#64(online snapshot B안 + fault test),
  #65(blocking snapshot + 선배선)로 재단. 운영 절차(D5)와 약점 명시는 기술지원
  가이드 티켓 #59의 요건에 편입된다.
