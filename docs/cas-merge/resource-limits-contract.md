# 자원 상한·admission·native METHOD 계약 (2026-09-14 사용자 결정)

[#259](https://github.com/xmilex-git/workspace/issues/259) 축 4·5의 제품 계약. 사용자 결정: **축 5 native C METHOD 미지원 확정**, **축 4 현재 동작을 계약으로 확정하고 파라미터로 노출**. 구현 커밋 `87ddc35f7`(축 5), `25f048de3`·`917ab7975`(축 4).

## 1. 축 5 — 사용자 정의 native C METHOD

| 항목 | 계약 |
|---|---|
| 지원 범위 | 내장(static) 메서드, Java SP, PL/CSQL만 지원. 사용자 .so를 dlopen하는 native METHOD(`METHOD ... FILE '...'`)는 **cub_server에서 미지원** |
| 거절 시점 | `sm_dynamic_link_class`가 미해결 링크가 있으면 method file 확장·dlopen 전에 `ER_SM_DYNAMIC_LINK_PROBLEMS`(-237)로 실패 |
| 근거 | 서버 스레드·static 상태·exit/abort·heap을 공유하는 사용자 코드는 로더 mutex만으로 안전해지지 않는다(티켓 완료 조건) |
| 스키마 | `ADD METHOD ... FILE` 정의 자체는 카탈로그에 남을 수 있으나 호출은 항상 거절된다. CS/SA 클라이언트 빌드는 기존대로 동적 링크 |

## 2. 축 4 — 수치 계약과 파라미터

| 계약 | 값 | 노출 | 초과 시 |
|---|---|---|---|
| 요청 본문 상한 | 기본 1 GiB(`DB_MAX_STRING_LENGTH`+framing), 하한 16 MiB | 서버 `driver_request_max_size`(size unit, cubrid.conf) | `CAS_ER_COMMUNICATION` 응답 후 연결 종료 |
| 접속 단계 본문 상한 | 16 MiB 고정(프로토콜) | 없음 | 접속 거절 |
| handoff 슬롯 대기 | 기본 60초 | 브로커 `DIRECT_HANDOFF_WAIT_TIMEOUT`(time string, cubrid_broker.conf) | `CAS_ER_FREE_SERVER` |
| 인증 전 단계(TLS·db_info·인증) | 브로커 `SESSION_TIMEOUT` 재사용 | 기존 파라미터 | 소켓 타임아웃으로 접속 실패, 세션·슬롯 미보유 |
| 요청 idle / IN_TRAN | 기존 `SESSION_TIMEOUT`/`MAX_QUERY_TIMEOUT` | 기존 | 기존 동작 |
| byte budget(요청/세션/서버) | **미도입** — #237 예산 확정 후 별도 | — | — |
| 컴파일 취소 / monotonic deadline | 기존 query timeout·cancel 경로 유지, 파서 깊이 제한(093a5b3b2) | — | — |

AUTO 수용성: 슬롯 초과 시 idle 세션 양보(D-ADOPT, `thread_connection_pooling=yes`). 서버 backstop은 `max_clients`.

## 3. 검증

gate7(양 모드 incremental, 스모크, AUTO subset)과 계약별 probe: native METHOD 호출 거절(-237)·내장 메서드 정상, `driver_request_max_size` paramdump·16M 설정 후 20 MiB 헤더 거절, `DIRECT_HANDOFF_WAIT_TIMEOUT=2sec` K1 포화 시 약 2초 내 거절, `SESSION_TIMEOUT=3sec`에서 header만 보내고 멈춘 접속이 약 3초 내 종료.
