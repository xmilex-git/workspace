# POC 인프라 — podman Kafka(KRaft) + Kafka Connect + ClickHouse

티켓: [#34](https://github.com/xmilex-git/workspace/issues/34)

rootless podman 단일 노드 3컨테이너. 호스트에 compose 프로바이더가 없어
순수 podman 스크립트로 고정한다 (D3). 이미지 핀은 `versions.env` 한 곳.

```bash
htap-poc/infra/up.sh      # 기동 (idempotent)
htap-poc/infra/smoke.sh   # 스모크: kafka produce/consume + CH insert/select + Connect REST
htap-poc/infra/down.sh    # 정지 (데이터 보존)
htap-poc/infra/reset.sh   # 정지 + 데이터 초기화 (plugin dir는 보존)
```

## 토폴로지

| 컨테이너 | 이미지 | 호스트 포트 | 비고 |
|---|---|---|---|
| `htap-kafka` | `versions.env:KAFKA_IMAGE` | 9092 | KRaft combined mode. 리스너 2개: 컨테이너망 `kafka:19092`(INTERNAL), 호스트 `localhost:9092`(EXTERNAL) |
| `htap-connect` | `versions.env:CONNECT_IMAGE` | 8083 | Debezium 베이스 이미지. 커스텀 커넥터 마운트 지점: `~/htap-data/connect-plugins/debezium-connector-cubrid` → `/kafka/connect/debezium-connector-cubrid` |
| `htap-clickhouse` | `versions.env:CLICKHOUSE_IMAGE` | 8123, 9000 | 데이터 `~/htap-data/clickhouse` |

- 데이터 루트: `$HTAP_DATA` (기본 `~/htap-data`) — `/tmp` 금지 규칙 준수.
- 커넥터 jar 배치 후에는 `podman restart htap-connect`.

## 호스트 제약 (검증 시 확인된 사실)

- **`--cgroupns=private` 필수**: 이 호스트는 rootless podman + cgroup v1인데 uid용
  systemd user slice가 없어 기본 cgroupns로는 runc가 즉시 실패한다. `ctp-parallel`
  스킬과 동일한 우회. 다른 호스트에서는 불필요할 수 있다.
- **reset은 `podman unshare rm`**: `:U` 마운트가 데이터를 컨테이너 매핑 UID로 chown
  하므로 호스트 사용자의 평범한 `rm -rf`는 Permission denied.
- SELinux disabled 호스트라 `:Z`는 no-op — enforcing 호스트에서는 재검증 필요.
- ClickHouse는 기본 사용자 무설정이라 `default` 유저의 원격 접속이 잠긴다
  (컨테이너 내부/localhost 사용은 정상). 외부 접속 인증은 sink 연결 티켓에서 결정.
- JNA용 `.so`는 plugin.path **밖**에 배포해야 한다(#32 결정) — 마운트 지점 추가는
  커넥터 배포 티켓에서.
