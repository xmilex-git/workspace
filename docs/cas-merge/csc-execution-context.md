# 실행 문맥(CSC) 인터페이스 — 연결·요청·PL 재진입·utility의 상태 연결과 자원 귀속

대상: `cas-merge` d6f184c8d 이후. [#259](https://github.com/xmilex-git/workspace/issues/259) 축 6 "기존 CSC를 기반으로 top-level/PL 재진입/utility의 TLS·db_on_server·allocator·인증·에러 스택·취소 상태 연결/복원을 명시한다"의 정본. 소스 위치는 이 문서 작성 시점 기준이다.

## 1. 단위와 소유자

| 단위 | 정의 | 소유자 | 수명 |
|---|---|---|---|
| **CSC** (`client_session_context`, `client_session_context.hpp`) | 폴드된 클라이언트 반쪽의 세션 상태 전부: 인증 컨텍스트, workspace(MOP 테이블·dirty 리스트·lea heap), 클라이언트 트랜잭션 상태, 스키마/트리거 캐시, 서버 credential, 임시 OID 번호, 접속 옵션, 실행 계획 dump, 옵티마이저 override·비용 정책, 드라이버 기본값, method callback handler, 런타임 인자, label table | 등록된 서버 세션(`session_adopt_client_context`) | 세션 수명. AUTO 양보 시 detach 상태로 보존되고 resume에서 재부착 |
| **bracket** | 한 스레드가 CSC를 활성화한 구간(`csc_activate`/`csc_deactivate`). 중첩 불가, `bracket_mutex`를 구간 내내 보유 | 활성화한 스레드 | 연결 처리 스레드는 연결 수명 동안 하나의 bracket; utility/boot 컨텍스트는 호출 구간 |
| **요청 scope** | bracket 안에서 CAS 요청 하나(`cas_process_request`)의 처리 | 같은 스레드 | 요청 수명. `registry_auto_ready`로 idle/busy 전이 |
| **executor(E)** | 연결을 처리하는 OS 스레드(`adoption.cpp` executor). 재사용 시 다음 연결로 넘어가며 engine entry/transaction은 반환 | `adoption::manager` | pooling=yes: idle timeout까지; no: 연결 수명 |

원칙: 사용자 상태는 CSC, 실행 자원(thread entry·transaction index·connection entry·CAS TLS)은 E와 연결에 귀속한다. server private heap 포인터는 E 경계를 넘지 않는다.

## 2. 진입 경로별 연결/복원 계약

### 2.1 top-level 드라이버 연결 (`driver_session.cpp`)

| 단계 | 연결 | 복원 |
|---|---|---|
| 스레드 진입 | `net_reset_connection`·`ux_reset_adopted_connection`·`unset_xa_prepare_flag`·autocommit/cancel TLS 초기화, `db_on_server = 0` (클라이언트 반쪽 할당 라우팅) | retire에서 `entry_p->tran_index = NULL`, conn entry 반환 |
| CSC | 신규: `new client_session_context` + `csc_activate`; AUTO resume: `session_auto_claim` 성공 후 임시 ctx를 `csc_retire_and_delete`, 보존 ctx를 `csc_activate` | 정상 종료: `session_auto_detach`(양보) 또는 `ux_end_session`; 미채택(adopted=false) ctx는 `csc_retire_and_delete` |
| 인증 | `db_restart_ex`(신규) / `boot_resume_client`(resume, 재인증 필수) → `registry_set_session_id` | `boot_unregister_client` |
| 에러 스택 | thread entry의 error context를 세션 스레드가 등록 | retire에서 `deregister_thread_local` |
| 취소 | `registry_set_tran_index`로 binding에 index 게시; 브로커 CANCEL은 `binding_pin` 하에서 `logtb_set_tran_index_interrupt` | `registry_begin_session_cleanup`이 pin drain 후 index를 NULL로 만든 뒤 `boot_unregister_client`가 index 반환 → 재사용 index 취소 불가 |
| 드라이버 기본값 | 신규: `ux_get_default_setting` 결과를 CSC에 저장 / resume: CSC 값으로 CAS TLS 복원 | — |

### 2.2 PL/method 재진입 (`query_method.cpp::method_dispatch`)

서버 executor 스레드(`db_on_server == 1`)가 같은 세션의 클라이언트 반쪽으로 재진입한다. bracket은 이미 활성(연결 스레드 = 실행 스레드)이며 새 bracket을 만들지 않는다.

| 항목 | 계약 |
|---|---|
| allocator | `db_on_server` 저장 후 0으로 → 종료 시 복원 |
| 에러 스택 | `er_stack_push`로 격리 프레임; `csc->er_dispatch_floor = er_stack_depth()`. 클라이언트 반쪽의 `er_stack_clearall`은 floor 아래를 지우지 않음. 중첩 dispatch는 floor를 재설정·복원 |
| 깊이 | `tran_begin_libcas_function`/`tran_end_libcas_function`; `METHOD_MAX_RECURSION_DEPTH` 초과 시 `ER_SP_TOO_MANY_NESTED_CALL` |
| 보관 자원 | 최외곽 dispatch 종료(`!tran_is_in_libcas`)에서 deferred query handler 회수. `has_retained_resources()`가 true인 동안 AUTO 양보·qlist 검사 생략 |
| 취소 | 부모 트랜잭션 index를 공유(별도 permit 없음). 부모 interrupt가 그대로 전파 |

### 2.3 utility / boot 컨텍스트

- 서버 기동 시 공용 초기화(`boot_initialize_client_modules`, `showstmt_scan_init`)와 `show_meta.c`·`deduplicate_key.c`는 고정 boot CSC를 호출 구간에서만 `csc_activate`한다. 사용자 상태를 담지 않는다.
- `server_compile_tracer.cpp`(utility plane)는 socketless conn entry(`css_make_conn(INVALID_SOCKET)`)와 자체 CSC를 만들고, 등록 후 서버 세션이 CSC를 입양한다. teardown은 `session_state_uninit`이 수행한다.

## 3. teardown 순서 (`csc_teardown`)

`db_on_server`를 0으로 고정 → 실행 계획·preferred hosts·method error msg → label table → method callback/runtime args → `sm_final` → `db_final_client_query_results` → `ws_final`(MOP 테이블·classname 캐시·lea heap; 공용 area는 유지) → `tp_session_domains_final`(workspace 해제 후에만) → `db_on_server` 복원. 스스로의 bracket 안에서 retire가 요청되면 `orphaned`로 표시하고 bracket 종료 시점에 teardown·delete한다(self-deadlock 회피).

## 4. 경계를 넘는 객체의 소유권

| 객체 | 생성 | 소유자 | 해제 | 경계 규칙 |
|---|---|---|---|---|
| `DB_VALUE` (요청 인자·결과) | CAS 요청 파서(`net_decode_str`는 원본 버퍼 포인터만 보관) | 요청 scope | `db_value_clear`/요청 종료 | 요청 밖으로 살아남는 값은 CSC(`method_runtime_args`)에 복사돼야 함 |
| prepared statement / srv_handle | `hm_new_srv_handle` | 세션(`srv_handle_table`, `cas_handle.c`) | 요청별 close, 세션 종료 `hm_srv_handle_table_final` | E 재사용 시 반드시 비어 있음(양보 조건 `num_holdable_results == 0`, `has_retained_resources()==false`) |
| list file / cursor (`QFILE_LIST_ID`) | 서버 실행기 | 트랜잭션/세션 | 문장 종료 또는 holdable 종료 | 스레드별 qlist 균형은 보관 자원이 있을 때만 생략(b4072bbe7) |
| workspace MOP / 도메인 노드 | `ws_*` / `tp_domain_*` | CSC | `ws_final` 뒤 `tp_session_domains_final` | 서버 상태로 넘어가는 OBJECT 값은 OID로 정규화(868acaba9) |
| method callback query handler | `get_callback_handler()` lazily | CSC | teardown의 `method_callback_session_final` (ws_final 이전) | E 경계 이동 금지 |
| 서버 세션 키·nonce | `xboot_get_server_session_key`/`session_auto_enable` | 서버 세션 | 세션 만료 | resume은 key+session id+nonce+재인증 모두 요구 |

## 5. 검증 근거와 남은 것

- 단위: `test_server_compile`의 bracket/ws rebind/domain scope/CAS slot/세션 static 격리 테스트(1f7d97e8d), `session_static_gate` POST_BUILD.
- 실행: 초기화 실패 7개 경계(99bf777af 기록), AUTO resume/yield probe·AutoCounter(중복/누락 0), PL 활성 smoke.
- 남은 것: SHOW 세션 통계 snapshot의 writer/reader 동기화(현재 best-effort), 요청 단계·바이트 사용량·대기/거절 사유의 진단 연결(축 4 수치 계약 확정 후).
