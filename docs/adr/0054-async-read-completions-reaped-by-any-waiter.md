---
status: kept as the recorded alternative (the mechanism it belongs to, io_uring, was not chosen: ADR 0055)
date: 2026-11-10
issue: CBRD-28005 (`docs/tla/CBRD-28005/`)
---

# 비동기 페이지 읽기의 완료 처리는 ring 주인과, 그 페이지를 기다리는 스레드가 한다

io_uring 기반 앞서 읽기에서는 I/O를 발행한 스레드가 그 페이지를 기다리지 않고 다른 일을 한다. 발행 스레드가 래치나 락을 기다리며 잠들면, 끝난 I/O의 완료가 그 스레드의 ring에 놓인 채 아무도 처리하지 않는 상태가 생긴다. 그 페이지를 fix하려는 다른 스레드가 발행 스레드가 기다리는 래치를 쥐고 있으면 둘 다 멈춘다.

사용자 결정(2026-11-10 그릴링 Q3, Q7, Q8, Q9):

- 스레드마다 ring을 하나 둔다. 완료 처리는 ring 주인이 하고, 그 ring에 걸린 페이지를 기다리며 잠든 스레드도 ring의 완료 mutex를 잡고 대신 한다.
- 다른 스레드가 ring을 처리해야 하므로 `IORING_SETUP_DEFER_TASKRUN`, `IORING_SETUP_SINGLE_ISSUER`는 쓰지 않는다.
- 스레드는 staged SQE를 남긴 채 잠들지 않는다. 앞서 읽기 호출 하나가 자기가 staged한 것을 반환 전에 모두 submit하는 구조로 지킨다.
- 스레드는 질의 종료, 인터럽트, 에러로 스레드 풀에 돌아가기 전에 자기 ring을 submit하고 비운다.
- I/O가 진행 중인 프레임은 victim이 되지 않는다.

## Considered Options

- **발행 스레드만 완료 처리**: 기각. TLC 반례(`AsyncRead.mutant-owner-only`): T2가 p1을 앞서 읽고 X를 기다리며 잠들고, X를 쥔 T1이 p1을 기다리며 잠든다. 완료는 T2의 ring에 있고 T2만 처리할 수 있어, 질의가 취소될 때까지 멈춘다.
- **전용 완료 데몬**: 검증은 통과(`AsyncRead.option-daemon.cfg`, `AsyncRead.option-daemon-live.cfg`)했으나 채택하지 않음. 완료마다 데몬을 거치는 문맥 전환이 끼고, 고IOPS에서 데몬 한 곳이 병목이 된다. 데몬의 장점(종료 시 ring 비우기 규칙이 필요 없음, 아무도 안 기다리는 I/O도 완료됨)은 위의 "풀 복귀 전 ring 비우기"로 얻는다.
- **앞서 읽기 호출이 SQE를 staged로 남긴 채 반환하기(쌓기와 submit의 분리)**: 기각. staged SQE를 둔 채 잠드는 스레드가 하나라도 있으면 그 페이지를 기다리는 스레드가 멈춘다(`mutant-block-with-staged`, `mutant-daemon-block-with-staged`). 잃는 성능은 없다. PostgreSQL의 batch mode도 look-ahead 호출 하나의 시작에서 켜고 끝에서 끈다(`read_stream.c:666`, `:745`). 한 번의 창 채우기가 SQE를 모두 쌓고 한 번에 submit하는 범위는 같다. PostgreSQL은 그 사이에 블록 번호 콜백(임의의 코드)이 돌기 때문에 "submit 없이 블록 금지"를 콜백 작성 규약과 opt-in 플래그로 지키고, CUBRID는 페이지 공급원이 메모리의 섹터 목록이라 함수 출구의 assert로 지킨다.

## Consequences

- 검증: `docs/tla/CBRD-28005/` `RESULT: OK`(2026-11-10, run `async-io-20261110-150012-2964341`). C2(기다리는 I/O는 결국 완료되고 풀 복귀 뒤 읽기 중 프레임이 남지 않는다)는 2스레드 경계에서 TLC liveness로, C1(I/O 중 프레임 재사용 없음)은 IndInv의 귀납성(Apalache)으로 확인했다.
- 구현 전 설계라 trace validation은 없다. 구현 spec이 이 spec을 refine해야 한다.
- 용어: GLOSSARY "앞서 읽기", "완료 처리".
