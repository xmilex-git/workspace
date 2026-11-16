---
status: accepted
date: 2026-11-16
issue: CBRD-28126 (`docs/tla/px-subquery-join/`, D1–D15, C1–C6, model `PxSubqueryJoin`; TLC: every pass cfg, 14 mutants and 7 witnesses as expected, IndInv on every reachable state; inductive check not established — closed without RESULT: OK, MAP.md "Result"); engine PR CUBRID/cubrid#8556 (`b22001002`)
---

# 병렬 부질의 실행기는 문장마다 깨움 이벤트 하나에서 기다리고, root가 끝나도 큐를 닫지 않는다

병렬 부질의 실행기의 `run_jobs`는 자기 job을 끝낸 뒤 `join_context::m_mutex`를 바퀴마다 두 번 잡으며 남은 job 수를 읽고 `try_pop`을 되풀이했다. TPC-H Q21(`parallelism=1`)에서 서버 `instructions:u`의 31%가 이 루프였다(oracle-gap#20). 또 root의 `run_jobs`가 끝날 때 `push_last`로 큐를 닫아서, 그 뒤에 도는 실행기(WHERE 스칼라 부질의 등)의 job이 버려지고 그 실행기는 끝나지 않았다(CBRD-27823).

- 실행기마다 남은 job 수는 atomic으로 센다. 문장마다 깨움 이벤트(epoch + mutex + cv) 하나를 root 실행기가 만들고 지운다(D3).
- 기다리는 스레드는 실행기의 `run_jobs`이든 워커든 같은 고리를 돈다. 큐가 빌 때까지 아무 실행기의 job이든 꺼내 돕고(D9), epoch를 읽고, 남은 수와 큐를 다시 본 뒤 epoch가 그대로면 잔다.
- push마다, 실행기의 마지막 job이 끝날 때마다, root가 끝날 때 깨우는 쪽은 이벤트 mutex를 잡고 epoch를 올려 `notify_all`한다(D5). 마지막 job은 `fetch_sub` 전에 이벤트 포인터를 읽어 둔다.
- root의 `run_jobs` 끝은 워커에게 그만두라고만 알리고 큐를 닫지 않는다(D14). 늦게 도는 실행기는 job을 넣고 자기가 꺼내 실행한다. 큐는 root 실행기를 지울 때 닫는다.
- `add_job`은 큐가 받은 job만 센다(D15). `push_slow`는 interrupt가 걸리면 job을 받지 않는다.

문장이 쥐는 워커 수(묶음 예약, 탄력 워커)는 이 결정과 따로 정한다(xmilex-git/workspace#644, `docs/tla/px-worker-group/` draft).

## Considered Options

- **이슈의 방향 2(첫 `try_pop` 실패에서 루프를 나와 실행기의 cv에서 기다림)**: 중첩 실행기가 나중에 넣는 job을 아무도 꺼내지 않아 교착한다(`mutant-exit-on-empty`).
- **실행기마다 깨움 객체**: 마지막 job이 깨우는 순간 그 실행기가 이미 지워졌을 수 있다(`mutant-wake-via-exec`, use-after-free).
- **잠든 스레드가 있을 때만 notify, 또는 notify_one**: notify_one은 둘 이상 잘 때 교착한다(`mutant-wake-one`). 등록 수를 세는 방식은 순서 조건이 더 많아 이득이 없다.
- **늦은 실행기를 위해 워커를 다시 띄움**: 워커 예약은 workspace#644의 묶음 결정과 얽혀 있다. 늦은 실행기의 job은 메인 스레드가 직렬로 실행한다.
- **CBRD-27823을 따로 고침**: 같은 기다림 코드의 같은 종류 결함(job을 잃고 수가 남음)이라, 사용자 결정으로 여기서 함께 고쳤다.

## Consequences

- 워커의 대기도 큐의 `pop_slow`(`m_not_empty`)를 떠나 같은 이벤트로 옮긴다. develop의 fast push는 큐 mutex 없이 notify해서 워커가 push를 놓치고 잘 수 있었는데(`mutant-develop-lost-wakeup`), 이 구멍도 함께 닫힌다.
- root 실행기의 소멸자는 워커를 멈추고 끝나기를 기다린 **뒤에** 큐와 이벤트를 지운다(develop은 큐를 지운 뒤 `release_workers`를 불렀다).
- 실측(develop `4bf2b2e32` 대비, release, TPC-H SF1 Q21, `parallelism=1`): `instructions:u` 중앙값 24.14G → 16.09G, mutex lock/unlock 샘플 35.6% → 1.2%, 결과 100행 동일.
- inline aptr가 push 뒤에 실패해 `run_jobs`를 건너뛰는 develop 결함(xmilex-git/workspace#643)은 따로 고친다. 고치지 않으면 새 설계에서도 use-after-free다(`mutant-inline-fail`).
- 구현의 trace 검증은 하지 않았다. 리파인먼트 맵(MAP.md)이 모델과 코드를 잇는다.
