# wf122/S0 — in-process 클라이언트 잔존 tran이 유발하는 종료 SIGABRT 메커니즘

대상: CAS 통합 맵(#112) S0 스테이지, PR xmilex-git/cubrid#181.
증상: milestone-0 tracer 실행 후 `cubrid server stop` 시 `cub_server`가
`thread_entry.cpp:564`의 assert
(`thread_p->m_status == TS_RUN || TS_CHECK`)로 SIGABRT.
재현율은 종료 3회당 약 2회(비결정적).

## 크래시 시그니처

종료 체크포인트 경로에서 사망:

```
xboot_shutdown_server → log_final → logpb_checkpoint → dwb_synchronize
  → dwb_flush_force → dwb_wait_for_block_completion
  → thread_suspend_timeout_wakeup_and_unlock_entry   ← assert
```

assert에 걸린 entry는 항상 동일 (gdb에서 `_ZN9cubthreadL12Main_entry_pE`
심볼 직접 대조로 확증):

```
thread_p == Main_entry_p   (index=0, type=TT_MASTER)
m_status   = TS_FREE       ← 본래 TS_RUN이어야 함
tran_index = 1             ← tracer의 트랜잭션 (본래 0=system)
conn_entry = NULL
```

## 진짜 메커니즘 (계측으로 확증)

1. tracer(in-process 클라이언트)는 질의 후 `db_commit_transaction()`을
   호출하지만, **커밋된 tdes는 다음 트랜잭션을 위해 즉시 ACTIVE로
   복귀**한다. 이는 로그인 상태의 모든 idle 클라이언트에 해당하는 정상
   동작이다.
2. 정상 클라이언트는 접속 종료 시 `xboot_unregister_client`가 tdes를
   해제하므로, 서버 종료가 시작될 때 트랜잭션 테이블에 클라이언트 tran이
   남지 않는다. tracer는 conn/entry만 정리하고 **로그아웃(unregister)을
   하지 않아** tran 1이 ACTIVE로 잔존했다.
3. `xboot_shutdown_server`(boot_sr.c)가 `log_abort_all_active_transaction`
   (log_manager.c)을 호출하고, 이 함수는 ACTIVE tran마다
   `css_push_external_task(css_find_conn_by_tran_index(i), …abort task…)`를
   민다.
4. 이 push는 **호출 스레드(=종료 중인 메인 스레드)에 인라인으로 동기
   실행**되며, `css_server_external_task::execute`(server_support.c)는
   건네받은 `thread_ref`(= `Main_entry_p`)에 무조건
   `conn_entry = NULL; m_status = TS_FREE;`를 찍는다. tran_index는 abort
   처리 값(1)으로 남는다.
5. 이후 종료 체크포인트의 DWB 대기가 `Main_entry_p`로 suspend를 시도하다
   TS_FREE를 보고 assert → SIGABRT.

비결정성의 원인: 3-4단계는 트랜잭션 테이블 스캔 시점의 상태에 좌우된다
(commit 직후 tdes가 ACTIVE로 재무장되는 시점과 종료 스캔의 경합).

## 기각된 가설들 (교훈)

- **고아 conn 이론**: tracer의 socketless conn이 active list에 잔존해
  종료 sweep이 처리한다는 가설. conn을 `css_free_conn`으로 제거하는
  수정(775a31d93)과 SUCCESS 로그를 teardown 뒤로 미루는 수정(160b65ab8)
  모두 **크래시를 못 막았다** — conn 수명은 위생 문제였지 원인이
  아니었다. 반증 근거: SUCCESS(=teardown 완료 보장) 후에만 stop을 날려도
  2/3 재현.
- **탐지 방법론**: gdb 하드웨어 watchpoint는 너무 느렸다. 결정타는
  `m_status` 쓰기 지점 전수조사(grep) 후 각 지점에
  `if (thread_ref.index == 0) abort();` 임시 계측 → 증분 빌드 → smoke
  1회 → **writer 지점에서 즉시 코어** → bt. (assert-driven writer hunt)

## 수정 (cas-merge 브랜치, PR #181)

`server_compile_tracer.cpp` — tracer가 conn 해제 **전에**
`boot_unregister_client(tm_Tran_index)` 호출 (5f32dc648). SERVER_MODE의
in-process 분기(`enter_server → xboot_unregister_client → exit_server`)가
tdes를 실제 disconnect와 동일하게 해제한다. `xboot_unregister_client`는
conn을 해제하지 않으므로 기존 `css_free_conn` 정리와 충돌 없음.
775a31d93(conn/entry 위생)·160b65ab8(SUCCESS-last 순서)은 원인은
아니었지만 올바른 위생으로 존치.

## 2차 지뢰: exit-시 CS 클라이언트 atexit 셧다운 (수정으로 노출됨)

tran-logout 수정(5f32dc648)으로 서버가 처음으로 정상 exit()에 도달하자,
그동안 구 크래시에 가려져 있던 두 번째 선존 결함이 3/3 재현으로 드러났다:

- in-process 부트의 `boot_client()`(boot_cl.c)가 CS 클라이언트용
  `atexit (boot_shutdown_client_at_exit)`를 **cub_server 프로세스 안에**
  등록한다.
- exit 시 이 핸들러가 `boot_shutdown_client → boot_client_all_finalize →
  db_private_free(boot_Db_full_name)`를 타는데, 이 시점엔 스레드 매니저
  teardown이 끝나 `tl_Entry_p == NULL` →
  `thread_get_thread_entry_info`의 assert(thread_manager.cpp:444)로
  SIGABRT.

수정(480e9bf10): SERVER_MODE에선 atexit 등록 자체를 스킵(핸들러 정의도
가드) — 클라이언트 컨텍스트는 종료하지 않는 게 milestone-0 계약이고
서버 프로세스의 exit는 `boot_shutdown_server_at_exit` 소유. 벨트로
tracer가 로그아웃 후 `tm_Tran_index = NULL_TRAN_INDEX` 리셋.

## 최종 검증

HEAD 480e9bf10: smoke 3회 전체 실행(케이스 3종 × 3 = 종료 9회) 전부
클린, 코어 0, OID 셀프조인 케이스 COUNT=74 일관, 무-tracer 대조
정상. 두 크래시(체크포인트 TS_FREE assert, exit-시 tl_Entry_p assert)
모두 소멸 확인.

## 구조적 후속 (B1로 이관, #138에 기록됨)

근본 문제는 "종료 경로가 abort 태스크를 **공유 Main_entry_p 위에서
인라인 실행**하며 그 entry의 상태를 오염시킬 수 있다"는 것. 접속
프런트(B1)가 conn/세션 수명을 재설계할 때 함께 다룬다. 또한 트랙 A의
이후 스테이지에서 in-process 클라이언트 컨텍스트를 만드는 모든 코드는
**"commit만으로는 로그아웃이 아니다"** — tran 해제(unregister)까지가
수명 계약임을 전제해야 한다.

## 증거물

- 결정적 bt: 툴링 리포 `.git_ignored_dir/scratch/m0smokedb-s0/gdb_instrumented_bt.txt`
- 사전 채증: `gdb_info_threads_bt.txt`, `gdb_thread3_frame_locals.txt`,
  `gdb_caseA_bt.txt`, `gdb_caseB_bt.txt`, `gdb_R1X_bt.txt` (동 디렉토리)
- 코어 파일은 분석 후 전부 삭제(위생 원칙), 트랜스크립트만 보존.
