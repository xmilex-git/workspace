# 브로커 슬롯 회계·RESYNC 순서·서버 drain 계약 (2026-09-14, #265 축 3)

[#265](https://github.com/xmilex-git/workspace/issues/265) 권장 순서 1항의 산출물. #259가 남긴 "snapshot/delta 순서 계약"과 "ACK 지연 시 슬롯 미계상", "drain 30초 `assert`"를 한 원칙으로 닫는다. 구현 커밋 `c49af22e8`(`cas-merge`, 내부 제어 프로토콜 `PROTO_VERSION` 6→7 — 브로커·서버가 함께 배포되므로 호환 계층 없음).

## 1. 원칙 — 채널 리더 단일 적용자

| 항목 | 계약 |
|---|---|
| 슬롯 전이 주체 | 브로커의 **채널 리더 스레드**만. `HANDOFF_ACK`(+1, 토큰 저장), `RESYNC_REPLY` 항목(+1씩), `SESSION_END`(−1)을 **wire 순서대로** 적용한 뒤 요청자에게 응답을 넘긴다. 디스패치 스레드는 슬롯·토큰을 만지지 않는다 |
| ACK 본문 | `resync_token_body`(token + 서버가 등록한 client ip/port). 스냅샷 항목과 delta가 같은 레코드 — 리더가 두 경로를 한 함수(`tokens_admit`)로 처리한다 |
| 토큰 범위 | 토큰은 **허가한 채널의 세대(generation)** 로 묶인다. 채널 사망 시 그 세대의 허가만 회수(`tokens_drop_for_channel`). 같은 DB로 재다이얼된 후속 채널이 이미 RESYNC로 재구축한 표를 이전 채널의 사망 정리가 지우던 경합을 제거 |
| 모르는 토큰의 END | 무시(디버그 로그). 스냅샷 이전에 지워진 세션이거나 허가 채널이 이미 죽은 세션 — 보유 자원 없음. `orphan_ends` 집합 폐지 |
| 서버측 스냅샷 원자성 | `handle_resync`는 채널 `send_mutex`를 쥔 채 레지스트리를 스냅샷하고 응답을 쓴다. finisher는 `registry_mutex`로 erase 후 잠금 해제하고 `send_mutex`로 END를 보내므로(두 잠금을 동시에 쥐지 않음) 스냅샷에 든 토큰의 END는 wire에서 반드시 응답 뒤에 온다. 잠금 순서 `send_mutex → registry_mutex` 고정 |
| RESYNC 실패 | 스냅샷을 못 받은 채널은 즉시 폐기(`dead`+shutdown) — 미계상 상태로 운용하지 않고 다음 디스패치가 재다이얼 |
| ACK 지연 | 리더는 요청자가 이미 타임아웃(5초)했어도 ACK를 그대로 허가한다(서버가 세션을 소유하므로 live). 타임아웃은 채널을 죽이고 그 사망 정리가 같은 허가를 회수하므로 순수하게 상쇄된다. 재다이얼의 RESYNC가 live 집합을 다시 세운다 |

## 2. 서버 종료 drain (D-DRAIN)

| 항목 | 계약 |
|---|---|
| 대기 상한 | `shutdown_wait_time_in_secs`(기본 600, 하한 60) — `css_stop_all_workers`와 같은 파라미터 |
| 트랜잭션 | 즉시 interrupt(fd shutdown + `logtb_set_tran_index_interrupt`). 커밋 완료 대기 옵션은 워커 풀 경로에도 없으며 도입하지 않는다 |
| 기한 초과 | `er_log_debug`에 잔여 세션 수를 남기고 `_exit(0)` — `css_stop_all_workers`의 기한 초과와 동일. 종전의 optdebug `assert(drained)`(느린 종료마다 코어)와 release "매니저 누수 후 계속"(이후 teardown에서 UAF 위험)을 모두 제거 |

## 3. 검증

gate1(tooling `.git_ignored_dir/scratch/wf265/gate1/gate1-report.md`): 양 모드 incremental 빌드·unit 21/21·14-case smoke(양 모드)·smoke_csql/thin/jdbc(cancel 단계 포함)/gate·JDBC SSL·AUTO subset(다중 DB K1/K2·AutoCounter N32·AutoLoad N16/C4·N32/C1) + 변경 표적 probe: 브로커 재시작 전후 `brd_slots_used`가 live 세션 수와 일치하고 전원 종료 후 0 복귀(P1), `SLEEP(300)`·미커밋 세션을 둔 `cubrid server stop`이 수 초 내 종료·코어 없음(P2, 양 모드).

## 4. 남은 것(#265 유지)

취소 토큰 identity의 port=0 관용(보안 측면 #264 A절), control send·stop·drain의 진행 보장 감사, 세션 스레드 스택·깊이 가드, SHOW 통계 동기화, TLS 잔여 등 #265 본문 항목.
