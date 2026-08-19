# 1.0 DDL 지원 = DDL halt — captured 테이블 DDL 감지 시 fail-fast, 복구는 resnapshot 단일 절차

CUBRID Debezium 커넥터 1.0의 DDL/schema evolution 지원 수준을 정한다(지도:
xmilex-git/workspace#48, 티켓: #52). POC는 스키마 고정을 가정했고, 현재 커넥터는
mid-stream ALTER 시 DROP/RENAME/타입 변경을 **조용히 오디코딩**하는 silent corruption
경로가 실측으로 확인됐다(`CubridLogValueDecoder.java:45-47` 범위 체크는 ADD COLUMN만
잡음). 선례 상세는
[docs/research/debezium-pg-oracle-ddl-handling.md](../research/debezium-pg-oracle-ddl-handling.md)
(Debezium v3.0.0.Final 소스 + 공식 문서 기준).

결정: **자동 evolution도, historized schema도 아닌 DDL halt** — captured 테이블의
스키마를 바꾸는 DDL을 감지하면 안전 정지(fail-fast)하고, 복구는 문서화된 resnapshot
절차 하나로 고정한다. Postgres식 자동 추적은 CUBRID 로그가 이벤트에 스키마 메타데이터를
싣지 않아 구조적으로 불가하고, Oracle식 historized는 CUBRID SQL DDL 파서 신규 개발이라
1.0 범위를 초과한다. fail-stop 자체는 Oracle 커넥터의 기본 동작("stop processing so a
human can fix the issue")과 같은 자세다.

## 1.0 지원 매트릭스

| captured 테이블 DDL | 1.0 동작 |
|---|---|
| ALTER TABLE (컬럼 추가/삭제/변경/개명) | **DDL halt** (D1) |
| DROP TABLE / RENAME TABLE | **DDL halt** (D1) |
| TRUNCATE TABLE | **DDL halt** (D2) |
| CREATE TABLE (include 패턴 일치) | 계속 진행 + WARN/metric, 캡처는 재시작+스냅샷 절차 (D3) |
| CREATE/ALTER INDEX, SERIAL, TRIGGER, VIEW 등 비-TABLE object | 무시 (D1) |
| 비대상 테이블·시스템 클래스 DDL | 서버측 필터가 이미 차단 — 커넥터 도달 안 함 |
| DDL 이벤트의 Kafka 발행 / schema history topic / 자동 전파 | 없음 (후속 과제) |

## 확정 규칙

- **D1 — 발동 범위 = captured 테이블 + `object_type=TABLE`의 ALTER/DROP/RENAME.**
  `cubrid_log` DDL item의 `ddl_type`/`object_type` enum 비교만으로 판별한다
  (`src/api/cubrid_log.h:71-80` — 문장 파싱 불요). row 인코딩·정체성에 영향 없는
  비-TABLE object DDL은 무시. Oracle 리스너 구성(테이블 DDL만 처리, INDEX 등 무시)과
  동일한 모양이며, 비대상 테이블 DDL은 엔진이 이미 걸러 보낸다
  (`log_manager.c:13416` `ER_CDC_IGNORE_LOG_INFO`) — Oracle의 "남의 DDL에 죽는" 사고가
  구조적으로 차단된 상태.
- **D2 — TRUNCATE도 halt.** Debezium parity(PG·Oracle 모두 `skipped.operations` 기본
  `"t"`로 **기본 무시**)보다 의도적으로 엄격하다: 우리 제품 계약은 ClickHouse RMT
  current-state 복제본이라, TRUNCATE 무시는 "소스 0행 vs 복제본 옛 행 전부"라는 영구
  divergence를 조용히 만든다. truncate 이벤트 발행(op `t`)은 sink 반영 문제(파티션
  drop 수준)까지 얽혀 1.0 범위 초과.
- **D3 — mid-stream CREATE TABLE은 halt하지 않는다.** WARN + metric만 남기고 계속
  진행. halt의 존재 이유는 기존 데이터의 오디코딩 차단인데 CREATE는 그 위험이 없고,
  include 패턴에 우연히 걸리는 무관한 새 테이블로 파이프라인 전체가 서는 것을 피한다.
  신규 테이블 캡처는 "커넥터 재시작 + 해당 테이블 스냅샷" 운영 절차(가이드 #59)로
  해소 — Oracle의 테이블 추가 절차와 동일 구조.
- **D4 — 정지 semantics = DDL item 감지 즉시 fail-fast, anchor는 DDL 이전 고정.**
  DDL 로그 위치 이전의 커밋된 이벤트는 전부 정상 발행하고, DDL item을 보는 순간 예외로
  task FAILED. 재시작 anchor(ADR 0004)는 DDL을 지나치지 않으므로 조치 없는 재시작은
  같은 DDL에서 **결정론적으로 다시 멈춘다** — silent bypass 불가능이 이 결정의 핵심.
  트랜잭션 버퍼의 미커밋 txn은 발행하지 않는다(in-flight drain 불채택 — PG·Oracle도
  drain하지 않으며, drain은 DDL 이후 커밋을 기다리는 동안 새 스키마 이벤트를 읽어야
  하는 모순을 만든다).
- **D5 — 에러 표면.** 예외 메시지에 테이블명 + ddl_type + **DDL 문장 전문**(로그가
  전문을 제공) + 세팅 가이드 복구 절차 포인터. JMX metric: halt 발동 counter + 마지막
  halt 원인(테이블/문장) gauge — #60의 metrics 자리에 추가. Kafka Connect가 자동
  재시도로 무한 재-실패하지 않도록 **non-retriable**로 분류.
- **D6 — 복구 = 전체 resnapshot 단일 공식 절차.** "해당 테이블 DML 정지 → 커넥터 로그
  소진 확인 → DDL 실행 → resnapshot 절차(offset 리셋 + 쓰기 정지 스냅샷 재수행)"를
  가이드(#59)에 명문화한다. Oracle FAQ의 lock-step(정지→DDL→재시작)이 선례이고, 1.0엔
  incremental/online snapshot이 없어(#53 별도 결정) 대안 절차가 성립하지 않는다.
  additive 판별 후 스키마 재적재 같은 분기 절차는 오답 여지를 기술지원팀에 떠넘기므로
  두지 않는다.
- **D7 — 용어 = DDL halt (DDL 정지).** 설계 문서 §7.8의 "schema barrier"를 대체한다 —
  기존 용어 "barrier LSA"(스냅샷/스트리밍 경계)와의 충돌을 피하기 위한 개명.
  CONTEXT.md에 등재.

## 트레이드오프 (명시)

**halt는 가용성보다 정합성을 택한 것이다** — captured 테이블 DDL 한 건으로 파이프라인이
선다. Postgres처럼 계속 달리는 대안은 CUBRID 로그 포맷상 "조용히 컬럼 누락/오디코딩"으로
귀결되므로(선례 조사 참조) 1.0에서 수용 불가로 판단했다. TRUNCATE halt(D2)는 Debezium
기본값보다 엄격한 유일한 지점이며, 근거는 parity가 아니라 RMT current-state 계약이다.

탈출구: halt는 동작이지 포맷이 아니다 — 후속에 `ddl.handling.mode` 류 config로 additive
evolution이나 historized 모델을 얹어도 1.0 동작(halt)을 기본값으로 유지하면 호환이
깨지지 않는다. DDL 문장 전문이 로그에 이미 오므로 향후 파서 기반 evolution의 재료도
확보돼 있다.

## 추기 (2026-08-19, workspace#82 / P0-1) — 도착한 TABLE DDL은 무조건 halt

#48 전수 리뷰 P0-1(CONFIRMED): 종전 halt 판정은 "사전(announce)으로 라우팅되고
스키마에 있는 captured 테이블"일 때만 발동해, 사전이 비었거나(드랍 lag) 라우팅이
어긋난 DDL이 halt를 **조용히 우회**했다. 판정을 다음처럼 단순화·강화한다(#75 D3).

- **판정 = 도착 사실.** 커넥터에 도착한 `object_type=TABLE` &
  `ddl_type ∈ {ALTER, DROP, RENAME, TRUNCATE}`(및 미지의 future type — fail-safe)는
  사전·captured 조회 **없이 무조건 halt**한다. 서버측 extraction 필터를 통과했다는
  사실 자체가 캡처 대상임의 증명이다. NULL-classoid도 halt(판별 불가 → halt 기본값).
  사전은 에러 라벨(테이블명)에만 참조하고, 미해석 시 classoid로 표기한다.
  CREATE 경로(D3 warn)는 불변.
- **halt 판정 기준(4축) 채택** — #75에서 확립, CONTEXT.md 등재: DDL이 로그 이벤트 없이
  ① 행 인코딩 ② 테이블 identity ③ 이벤트 key identity ④ 테이블의 논리적 내용 중
  하나를 바꿀 때만 halt. 인덱스·constraint-only ALTER의 면제는 커넥터 판정이 아니라
  **엔진의 DDL 분류**(CDC_INDEX로 재분류, #75 D10 → 구현 workspace#83)로 실현한다 —
  커넥터 규칙은 "도착한 TABLE DDL = halt"로 단순 유지. 파티션 DDL은 DROP/PROMOTE
  PARTITION만 halt(#75 D11, 엔진 분류의 몫). PK 추가·삭제와 일반형
  `DROP CONSTRAINT <이름>`은 halt 유지(#75 D13).
- **에러 표면(D5) 보강**: 복구 처방을 "include list 정비 → resnapshot" 단일 공식으로
  메시지에 명시(#75 D6/D7). JMX는 기존 counter 유지.
- 검증: 단위 — 4종 DDL 무조건 halt(사전 미등재·NULL-classoid 포함), 4종 전부 재시작
  결정론적 re-halt, CREATE·CDC_INDEX 통과 불변. 전체 107/107 PASS (커넥터 워크트리).

## 추기 (2026-08-19, workspace#83 / P0-1 엔진) — encoding-safe DDL 재분류 + 파티션 DML root 라우팅

커넥터 규칙은 "도착한 TABLE DDL = 무조건 halt"(위 추기)로 단순 유지하고, halt
면제는 **엔진의 DDL 분류**가 담당한다: 4축 기준(행 인코딩·테이블 identity·이벤트
key identity·논리적 내용)을 하나도 바꾸지 않는 ALTER를 `execute_statement.c`
분류에서 `objtype=CDC_INDEX`로 실어 CDC가 무시하게 재분류했다(#75 D10/D11/D13).

- **CDC_INDEX 재분류 (halt 비발동)**: `ADD/DROP INDEX` 절, `REBUILD INDEX`,
  index comment/status, constraint-only `ADD CONSTRAINT`(attr 추가 없는
  FK·UNIQUE — PK 포함 시 제외), `DROP FOREIGN KEY`. 파티션에서는
  `ADD/ADD HASH/REORGANIZE/COALESCE/ANALYZE/APPLY/REMOVE PARTITION` —
  파티션 간 행 이동은 의도적 무로그지만 root의 논리적 내용이 불변이기 때문
  (`do_redistribute_partitions_data`의 `NO_SUPPLEMENTAL_LOG` 힌트 실측).
- **TABLE 유지 (halt)**: `DROP/PROMOTE PARTITION`(무로그 행 삭제·이탈 =
  TRUNCATE와 동류), PK 추가·삭제(이벤트 key identity), 일반형
  `DROP CONSTRAINT <이름>`(supplement 시점 판별 불가), 그리고 **목록 외 전부**
  (다중 절 ALTER는 전 절이 안전할 때만 재분류 — fail-safe).
- **파티션 DML root 라우팅(#75 D12)**: DML supplement에는 파티션 classoid가
  실리므로 `cdc_log_extract`가 filter/announce **전에** root를 해석해 include
  list(root 이름) 세션에서도 파티션 테이블이 캡처된다. 단 **레코드 디코딩은
  소유 클래스(파티션)의 repr 계보로** 수행한다 — root ALTER 이후 생성된
  파티션은 repr id 계보가 root와 어긋나(파티션 repr 1 = 현행, root repr 1 =
  과거) root repr로 디코딩하면 오디코딩·스트림 오염이 나기 때문
  (`cdc_make_dml_loginfo`: decode=raw classoid, 발행 entry=root classoid).
  해석 실패(드랍된 클래스의 밀린 로그)는 명시적 로그 후 filter로 처리 —
  캡처 root는 기존 error loginfo 경로 유지.
- 검증: csql 25종 DDL 분류 매트릭스 전건 일치(cdclogdump 실측), 파티션 e2e
  `run-partition-ddl.sh` PASS — include list 캡처(root 토픽), mid-stream
  ADD/REORG·인덱스 ALTER 무정지, root-ALTER-이력 후 신설 파티션 행 디코딩 정합,
  DROP PARTITION halt + 결정론적 re-halt. 기존 `run-e2e.sh` 회귀 PASS.
  CDC 세션은 단일 consumer(`cdc_Gl.conn` — 신규 START_SESSION이 기존 세션을
  대체)이므로 e2e는 실행 중 타 커넥터를 정지시킨다.
