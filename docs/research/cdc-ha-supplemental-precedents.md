# CDC × HA — supplemental 설정 위치·failover offset 연속성 선례 조사 (CUBRID·PostgreSQL·Oracle)

지도: xmilex-git/workspace#48, 티켓: #54. 질문: CDC와 HA를 동시에 쓸 때 supplemental
logging은 master에서만 켜면 되는가, failover 후 offset은 이어지는가. 조사일 2026-08-18.

## 요약 비교

| | supplemental 설정의 위치 | failover 시 offset 연속성 | CDC의 HA 지원 수준 (Debezium 기준) |
|---|---|---|---|
| **Oracle** | DB 수준 — `ADD SUPPLEMENTAL LOG DATA`가 redo로 physical standby에 자동 전파(11.2+ 생성 DB), 역할 전환 후 유지 | 보존 — physical standby는 SCN이 primary와 동일, "failover 후 마지막 SCN을 그대로 찾을 수 있다"고 Debezium 문서 명시 | 자동 추적 없음 — 수동 절차(standby 승격 → 커넥터 재연결) 문서화. standby 직접 캡처는 3.4-dev `capture.mode=physical_standby` incubating |
| **PostgreSQL** | 노드별 — `wal_level=logical`을 primary와 모든 승격 후보 standby에 사전 설정(재시작 필요 파라미터) | PG16까지 slot 미전파 → 유실. PG17 failover slots(`sync_replication_slots`)부터 동기화, Debezium `slot.failover=true` 지원 | failover slot 미사용 시 공식 절차 = "쓰기 재개 전 새 primary에 슬롯 재생성 + `snapshot.mode=always` 재스냅샷" |
| **CUBRID** | 노드별 — `supplemental_log`(PRM_FORCE_SERVER, 서버별 cubrid.conf). slave 자기 로그의 supplemental 유무는 slave 자신의 설정에 달림 | **끊김** — 노드별 로그가 applylogdb 재반영으로 독립 생성되어 LSA 좌표계가 노드마다 다름. old master anchor는 new master에서 재생 불가 | CDC(`cubrid_log`) 매뉴얼 자체가 없고, standby 접속 거부 게이트도 없음 — 동작 미정의 |

## CUBRID 상세 (매뉴얼 + 엔진 소스 실사)

- `supplemental_log`는 `PRM_FOR_SERVER|PRM_FOR_CLIENT|PRM_FORCE_SERVER`
  (`src/base/system_parameter.c:4730`) — 실질적으로 접속한 서버 프로세스의 값이 전부.
  매뉴얼(`en/admin/config.rst`)에 HA 관련 언급 없음.
- copylogdb 사본에는 master의 supplemental record가 물리적으로 그대로 들어가지만, 그
  사본은 applylogdb 전용이다. slave cub_server **자신의** 트랜잭션 로그는 applylogdb
  재실행으로 새로 생성되며, supplemental 게이트 `check_supplemental_log()`
  (`src/storage/heap_file.c:2803`)에 applier 배제 조건이 없어 slave 설정이 켜져 있으면
  재실행분에도 생성된다(HA 환경 실측은 미확인). → failover 대비면 전 승격 후보 노드에
  설정해야 한다.
- CDC 세션 시작 `scdc_start_session()`(`network_interface_sr.cpp:11414`)의 유일한 거부
  조건은 `supplemental_log==0`(`ER_CDC_NOT_AVAILABLE` -1291). **HA 상태(active/standby)
  검사가 CDC 경로에 전혀 없다** — slave로 강등된 노드에도 접속·추출이 성립한다.
- CUBRID HA는 물리 로그 스트리밍이 아니라 "copylogdb 사본 + applylogdb 논리 재반영"
  구조 → 같은 논리 변경이라도 노드별 로그의 바이트 배치가 달라 LSA(pageid.offset)가
  일치할 메커니즘이 없다. failover 후 코드상 유일한 재시작 수단은
  `cubrid_log_find_lsa(time_t*, uint64_t*)`(시각 기반, 중복/누락은 소비자 몫).

## 결정에 끼친 함의 (ADR 0010)

1. Oracle만 "master에 켜면 자동 전파"이고 PG·CUBRID는 노드별 → 세팅 가이드에 "HA 구성
   시 전 승격 후보 노드에 `supplemental_log` 설정" 명기 필요.
2. CUBRID는 Oracle SCN 동일성·PG17 failover slot 같은 **좌표계 보존 수단이 없어**,
   failover 후 이어읽기는 엔진 보강 없이는 원천 불성립.
3. 선례들의 1.0급 "HA 지원"도 실체는 자동 추적이 아니라 **문서화된 수동 복구 절차**
   (Oracle: 승격 후 재연결 / PG: 슬롯 재생성+재스냅샷) — CUBRID 1.0이 fail-fast +
   resnapshot이면 parity가 성립한다.
4. 조용한 오염 경로 2종 발견: ① 새 master에서 old anchor가 "유효해 보이는 엉뚱한
   위치"로 해석될 가능성, ② 강등된 old master 재접속 시 anchor 재생이 **성공**해
   applylogdb 재실행 스트림(트랜잭션 경계·사용자·supplemental 유무가 원본과 다를 수
   있음)을 무경고 방출.

## 출처

- Oracle: [Data Guard logical standby 생성 문서(supplemental 전파)](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/creating-oracle-data-guard-logical-standby.html) · [Debezium Oracle connector 문서](https://debezium.io/documentation/reference/stable/connectors/oracle.html)(원본 `oracle.adoc` v3.3.0.Final/main) · [LogMiner Utility](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-logminer-utility.html)
- PostgreSQL: [47.2 Logical Decoding Concepts](https://www.postgresql.org/docs/17/logicaldecoding-explanation.html) · [29.3 Logical Replication Failover](https://www.postgresql.org/docs/17/logical-replication-failover.html) · [Debezium PostgreSQL connector 문서](https://debezium.io/documentation/reference/stable/connectors/postgresql.html) · PG 소스 `logical.c`/`slotsync.c`(REL_17_STABLE)
- CUBRID: 매뉴얼 `en/admin/config.rst`·`en/ha.rst`, 엔진 소스 `system_parameter.c`,
  `heap_file.c`, `log_applier.c`, `network_interface_sr.cpp`, `api/cubrid_log.h`
