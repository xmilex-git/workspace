# 샘플 이벤트 (ticket #39)

수동 produce용 Debezium 이벤트 샘플. #31 baseline이 **소스측**
`ExtractNewRecordState`(`delete.tombstone.handling.mode=rewrite`) +
`add.fields` rename을 확정했으므로, 토픽에 실제로 흐르는 것은 평탄화된
레코드다 — 이 샘플들은 I/U/D envelope에 그 SMT 체인을 적용한 **결과물**
형태로 작성했다 (Kafka tombstone은 rewrite 모드가 제거하므로 없음).

메시지 계약 (커스텀 소스 커넥터가 지켜야 할 것, #31·ADR 0004·ADR 0005):

| 필드 | 값 |
|---|---|
| row 컬럼 | 평탄화. DECIMAL은 string(`decimal.handling.mode=string`), DATETIME은 ISO8601 UTC string(ZonedTimestamp) |
| `_op` | `c`/`u`/`d`/`r` (`op` rename) |
| `_version` | UInt64 숫자 = `epoch[16] \| event_counter[48]` (`source.lsn` rename). snapshot row(`_op=r`)는 0 |
| `_is_deleted` | JSON boolean. delete는 full before-image 행 + `true` (rewrite `__deleted` rename) |
| Kafka key | PK JSON string (POC sink는 `StringConverter`라 내용 무관) |

파일 형식: `key<TAB>value` JSONL — `kafka-console-producer`의
`parse.key=true` 입력. 시나리오:

- `t_order.jsonl` — I(id=1), I(id=2), snapshot r(id=3, `_version=0`),
  U(id=1), D(id=2, tombstone-rewrite), U(id=3: CDC가 snapshot 0을 이김)
- `t_item.jsonl` — I(A), I(B), U(A), D(B)

기대 canonical 상태는 `../verify.sh`의 expected 블록 참조.
