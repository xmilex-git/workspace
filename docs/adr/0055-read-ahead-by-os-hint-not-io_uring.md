---
status: accepted
date: 2026-11-10
issue: CBRD-28005 (`docs/tla/CBRD-28005/`)
---

# 미리 읽기는 OS 힌트(`posix_fadvise`)로 하고, io_uring은 쓰지 않는다

스캔이 곧 읽을 페이지를 장치가 한꺼번에 읽게 하려는 것이 목적이다. io_uring으로 버퍼 프레임에 직접 비동기 읽기를 내는 방식을 먼저 설계하고(ADR 0054) 1단계까지 구현해 검증했으나, 채택하지 않는다. 대신 버퍼에 없는 페이지에 `posix_fadvise (POSIX_FADV_WILLNEED)` 힌트만 보내고, 읽기는 지금의 동기 경로를 그대로 쓴다.

사용자 결정(2026-11-10 그릴링 Q48, Q49). 근거는 흩어진 16KB 읽기의 실측이다(`docs/research/async-io-read-ahead-sizing.md` "흩어진 읽기").

- SATA SSD에서는 힌트와 io_uring이 같은 값(장치 한계)이다.
- NVMe에서는 힌트가 io_uring 기본형과 같거나 빠르다. io_uring이 이기는 경우는 `IOSQE_ASYNC`를 켠 스레드 하나뿐이고(초당 18만 페이지 대 10~12만), 커널 워커가 복사를 대신하는 대가로 CPU를 약 3배 쓴다. 힌트 방식의 한계는 I/O가 아니라 스레드 하나의 복사 CPU이며, 실제 스캔(TPC-H Q1 직렬이 초당 약 3만 페이지)은 그 한계에 닿지 않는다.
- 파일 순서로 읽는 경로(섹터 순서 힙 스캔, 표시가 촘촘한 전체 범위 묶음)는 OS read-ahead만으로 이미 장치의 순차 속도가 나온다.

## Considered Options

- **io_uring으로 버퍼 프레임에 직접 읽기**: 구현과 검증을 마친 뒤 기각. 스레드별 ring, 버퍼의 "읽기 중" 항목, 완료를 누가 처리하느냐(ADR 0054), 풀 복귀 전 비우기, liburing 의존성, 커널 조건(성능 서버의 4.18은 io_uring 없음)이 따라오는데, 실측 이득이 위와 같다. 기록: `docs/tla/CBRD-28005/io_uring-alternative/`의 패치 두 개, `AsyncRead` 모델과 실행 기록, ADR 0054. 버퍼드 I/O를 그만두거나(O_DIRECT) 스레드 하나가 복사에 묶이는 작업이 생기면 다시 본다.

## Consequences

- 힌트한 페이지에는 프레임도, 주인도, 완료도 없다. ADR 0054의 규칙(누가 완료를 처리하나, staged 요청을 둔 채 잠들지 않기, 풀 복귀 전 비우기)과 claim C1, C2는 io_uring 대안에만 해당한다.
- 힌트는 OS 페이지 캐시를 거치는 버퍼드 I/O에서만 뜻이 있다(D2).
- 이미 버퍼에 있는 페이지는 힌트하지 않는다. 힌트하면 버퍼가 가진 내용을 장치에서 다시 읽게 된다.
- 시스템 파라미터 `read_ahead_hint`(기본 no)로 켠다.
