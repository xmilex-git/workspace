# HTAP POC — CUBRID → Debezium → Kafka → ClickHouse

지도: [HTAP 지도: CUBRID → Debezium → Kafka → ClickHouse Compact POC (#30)](https://github.com/xmilex-git/workspace/issues/30)

| 디렉토리 | 티켓 | 내용 |
|---|---|---|
| `harness/` | [#33](https://github.com/xmilex-git/workspace/issues/33) | `cubrid_log` C dump 유틸(`cdclogdump`) + DB 셋업 + 트랜잭션 시나리오 러너 |
| `dumps/` | [#33](https://github.com/xmilex-git/workspace/issues/33) | 시나리오별 CDC 이벤트 덤프 (후속 결정 티켓들의 1차 증거) |
| `infra/` | [#34](https://github.com/xmilex-git/workspace/issues/34) | rootless podman — Kafka(KRaft) + Kafka Connect + ClickHouse 단일 노드 |

공통 규칙: 스크래치/데이터는 `/tmp` 금지. 하네스 스크래치는 이 repo의
`.git_ignored_dir/scratch/`, DB는 `~/htap-cdc/`, 인프라 데이터는 `~/htap-data/`.
