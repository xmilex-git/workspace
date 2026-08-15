# ClickHouse 물리 테이블 + 공식 Kafka Connect Sink (ticket #39)

티켓: [#39](https://github.com/xmilex-git/workspace/issues/39) · 근거: #31 조사
([findings](https://github.com/xmilex-git/workspace/blob/research/clickhouse-sink-debezium/docs/research/clickhouse-sink-debezium.md)),
ADR 0004(`_version` 규칙), ADR 0005(snapshot `_version=0`·truncate 정리).

## 구성

| 파일 | 내용 |
|---|---|
| `ddl.sql` | `htap` DB + `t_order_local`/`t_item_local` RMT(`_version`,`_is_deleted`) + canonical `FINAL` view (`htap.t_order`/`htap.t_item`). idempotent |
| `truncate.sql` | 부분 snapshot 적재 정리 (ADR 0005 — truncate가 유일한 방법) |
| `apply-ddl.sh [--truncate]` | 컨테이너 안 clickhouse-client로 DDL (재)적용 |
| `install-sink-plugin.sh` | 공식 sink 릴리스(핀: `../infra/versions.env`의 `CLICKHOUSE_SINK_VERSION`) 다운로드 → plugin dir. 이후 `podman restart htap-connect` |
| `clickhouse-sink.json` | sink 커넥터 config — 경로 A(#31 baseline): schemaless JSON, at-least-once, `errors.tolerance=none`, `date_time_input_format=best_effort` |
| `register-sink.sh` | Connect REST에 PUT (idempotent) |
| `samples/` | 수동 produce용 post-SMT 샘플 이벤트 (I/U/D/snapshot-r) — 메시지 계약은 `samples/README.md` |
| `produce-samples.sh` | 샘플을 토픽에 produce. 재실행 = 중복 재전송 테스트 |
| `verify.sh` | 완료 조건 검증: truncate→produce→canonical 기대 상태 assert→동일 샘플 재전송→무변화 assert |

실행 순서 (인프라 `../infra/up.sh` 이후):

```bash
./install-sink-plugin.sh && podman restart htap-connect
./apply-ddl.sh
./register-sink.sh
./verify.sh        # PASS 확인 (2026-08-16 실측 통과)
```

## 이 티켓에서 확정된 사실 (2026-08-16, CH 24.8.14.39 · sink v1.4.0 실측)

- **RMT `is_deleted` 인자로 `Bool` 컬럼 허용** (#31 step-1 항목 ③).
- **문자열 → `Decimal(15,4)`/`Decimal(10,2)` parse OK** (`decimal.handling.mode=string` 경로).
- **ISO8601(`...Z`) 문자열 → `DateTime64(3,'UTC')` parse OK** — 단
  `date_time_input_format=best_effort` 필요 (sink config의 `clickhouseSettings`로 주입, #31 step-1 항목 ④).
- **`FINAL`이 `_is_deleted` 행을 자동 제거** — view의 `WHERE _is_deleted=false`는 의도 문서화용.
- **중복 재전송 수렴**: 동일 샘플 2회 produce → INSERT는 2회 모두 물리 적재
  (query_log written_rows 6+6, dedup token 상이) → `optimize_on_insert`로 블록 내
  중복이 접히고 canonical view는 byte-identical. at-least-once + 결정적 `_version`
  전제(ADR 0004)가 sink 실물에서 성립.
- **sink 인증**: CH default 유저는 원격 잠김(설계 유지) —
  `../infra/clickhouse/users.d/htap-sink.xml`의 `htap_sink` 유저(POC 평문 비밀번호,
  `GRANT SELECT, INSERT ON htap.*`)를 up.sh가 마운트.

## 결정 (traceability)

- **D1 — SMT는 소스측 유지**: #31 baseline대로 unwrap 체인은 (향후) 소스 커넥터
  config에 둔다. 따라서 토픽 계약 = post-SMT 평탄화 레코드이고, 이 티켓의 수동
  샘플도 그 형태다. SMT 자체의 실측(필드명 rename 조합 등)은 E2E 슬라이스에서.
- **D2 — 토픽 이름 `htapcdc.htapdb.<table>`**: Debezium `topic.prefix` 관례 선취.
  소스 커넥터 config 티켓에서 바꾸면 `clickhouse-sink.json`의 `topics`/`topic2TableMap`만 수정.
- **D3 — verify 대기는 consumer-group lag 기반**: RMT는 insert/merge 시점에 물리
  행수가 변하므로 raw count 대기는 신뢰 불가. offset commit 주기(60s) 때문에 4단계가
  최대 ~1분 걸리는 것이 정상.
