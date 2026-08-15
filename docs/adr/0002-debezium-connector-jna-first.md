# CUBRID Debezium 커넥터의 CDC 접근은 JNA-first

CUBRID→ClickHouse HTAP POC(지도: xmilex-git/workspace#30)에서 CUBRID CDC를 읽는 주체를
자체 C++ agent가 아닌 **정식 Debezium 소스 커넥터**(`debezium-connector-cubrid`,
xmilex-git/debezium fork)로 정했고, 그 커넥터가 CUBRID CDC에 닿는 방법으로 **JNA로
`libcubrid_log`(C 클라이언트 라이브러리)를 래핑**하는 쪽을 택했다. `cubrid_log.c`(2,123줄)는
자체 소켓이 아니라 CUBRID 내부 css 네트워크 계층(`css_connect_to_log_server` + OR_ 패킹)에
올라타 있어, 순수 Java로 가려면 그 프레이밍·언패킹 전체를 재구현해야 한다. POC의 목적은
"경로가 무조건 동작함"의 증명이므로 도달 확실성(검증된 C 코드 재사용, 서버 프로토콜 드리프트
없음)을 우선했다.

## Considered Options

- **순수 Java 프로토콜 재구현**: Debezium의 정석(MySQL 커넥터의 binlog 클라이언트처럼
  네이티브 의존성 제로)이고 upstream 제출이 가능한 유일한 모양. 기각이 아니라 **연기** —
  css 프레이밍 + 로그 아이템 언패킹 ~2천 줄 상당 포팅과 서버 내부 프로토콜 변경 추적 부담이
  POC 단계에서 정당화되지 않는다. JNA 커넥터가 동작해 CDC semantics가 실측으로 고정된 뒤에
  포팅하면, 그 실측 덤프가 포팅의 테스트 픽스처가 된다.
- **C++ 자체 agent가 Debezium envelope 포맷만 흉내**: Kafka 이후 생태계는 재사용하지만
  Debezium 프레임워크(스냅샷, offset 관리, SMT, Connect 운영) 밖에 살고, "debezium repo에
  CUBRID 커넥터가 존재한다"는 목적 자체에 닿지 못해 기각.

## Consequences

- Connect 워커에 `libcubrid_log.so`(및 그 의존)를 배포해야 하며, 커넥터는 CUBRID 빌드
  산출물에 플랫폼-결합된다. upstream 제출은 이 ADR을 뒤집는(순수 Java 포팅) 별도 노력 이후에만
  가능하다 — 그때 topic 포맷과 offset 스키마는 그대로 유지되므로 하류(sink, ClickHouse)는
  무변경이다.
