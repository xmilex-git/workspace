---
status: accepted
date: 2026-11-17
---

# 폴드 세션의 연결은 자기 로그인의 비밀번호 증명을 스스로 기록한다

develop의 CBRD-27445(`97a8309ce`)부터 서버는 연결이 사용자의 비밀번호를 증명한 뒤에만 클라이언트를 등록한다(`xboot_register_client`의 `css_consume_auth_proof`). CS 클라이언트는 등록 전에 일회용 challenge에 답한다(`au_prove_password` → `NET_SERVER_AU_CHALLENGE`/`_RESPONSE`). CAS 폴드(CBRD-27430, PR 7837)의 세션은 client 절반이 서버 스레드 안에서 돌고 wire가 없어서, 머지 직후에는 드라이버의 새 로그인과 보관 세션의 재개 로그인이 모두 -171로 거절됐다.

결정: 폴드 경계(`boot_register_client`의 SERVER_MODE 분기)가 등록 직전에 세션 자신의 연결에 증명을 기록한다(`css_set_auth_proof`). 비밀번호 검사는 지금까지처럼 등록 직후 같은 프로세스에서 client 절반의 로그인(`perform_login`)이 하고, 실패하면 등록을 해제한다. 증명이 막으려는 것은 서버가 믿을 수 없는 클라이언트의 자기 신고인데, 폴드의 client 절반은 서버 자신의 코드이고 드라이버는 로그인이 끝나기 전에 다른 요청을 넣을 수 없다. develop의 검사 코드는 바꾸지 않았다.

세션 안의 사용자 전환(`CALL login`)과 CAS 재연결 경로는 x 함수를 직접 부르므로 wire 쪽 검사(`slogin_user`, `ssession_find_or_create_session`의 `auth_may_switch_user`)를 지나지 않는다. 거기서도 비밀번호는 in-process `perform_login`이 검사한다(비DBA의 틀린 비밀번호는 -1385, DBA 그룹은 비밀번호 없이 전환).

로그인 단계의 순서가 바뀌지 않으므로 B1b 모델(`AutoSession`의 `Auth`)의 step은 그대로다.

검증(`cas-fold-v2` `3b377107d`): 머지만 한 빌드에서 폴드 로그인 전부 -171, 수정 뒤 맞는 비밀번호 통과·틀린 비밀번호/없는 사용자 -1385·거절 14회 뒤 남은 트랜잭션 0·CS csql의 wire 로그인·세션 안 사용자 전환(툴링 scratch `fold-v2/m647/smoke_m647.sh`, optdebug·release·메모리 검사).

## Considered Options

- **in-process 증명(저장된 비밀번호 형식을 서버에서 읽어 client 절반의 형식과 비교한 뒤 기록)**: 기각 — 등록 전에 검사한다는 순서는 얻지만 같은 검사를 `perform_login`이 바로 뒤에 또 하고, 저장 형식 4종의 비교 코드를 한 벌 더 둔다. 폴드 세션은 그 시점에 이미 핸드오프 슬롯과 스레드를 쥐고 있어서 트랜잭션 인덱스를 늦게 주는 이득이 없다.
- **`xboot_register_client`의 검사에서 폴드 연결을 예외로 두기**: 기각 — develop의 보안 검사 조건을 고치게 되고 develop 추종 때마다 겹친다.
