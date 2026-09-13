# QA handoff — client initialization ownership

Scope: boot_restart_client shared/session separation on cas-merge, workspace ticket “CAS 통합 제품화 준비 — 코드·아키텍처 6대 과제 통합”. These are scenario requirements for the final map-level test.md; no testcase repository additions.

1. Start a fresh server and immediately connect multiple valid and invalid credentials concurrently. Successful connections see their own identity and can create, insert, query, and drop objects. Invalid credentials fail without aborting any other session.
2. Repeat enough waves to exceed max_clients cumulatively, with concurrent live connections below that limit. After the last connection closes, reconnect and use SHOW metadata; no session/normal slot/FD growth attributable to completed connections.
3. Hold two sessions with different compiler/session settings while a third fails authentication. Verify both surviving sessions retain settings and workspace objects, including temporary OID allocation and transaction isolation.
4. With an active CSC but no registered client transaction (SHOW bootstrap / pre-registration ws_init), induce the workspace OOM callback and verify it does not attempt to abort the server main transaction. Induce failure at workspace heap/table creation, root MOP creation, authorization, session object creation, session parameter array creation, and trigger map creation. Verify bounded error response, transaction/session cleanup, continued service for a control connection, and successful next connection. Record which boundaries were actually injected; don't equate an ordinary bad password with OOM coverage.
5. Induce shared initialization failure (allocator area, SHOW metadata, builtin method entry/name); server must fail startup before opening adoption, release partial allocations, and then start successfully with the fault removed. No partially linked method entry remains.
6. Verify shared SHOW metadata is allocated before any connection, survives repeated first/last session turnover, and is released before common areas/domains at server shutdown.
7. Observe entry/exit of boot_restart_client under concurrent initial connections. At least two initializations overlap; report observed overlap and phase/lock timing. Do not infer overlap solely from total client wall time, or report a speedup without baseline measurements.
8. Run existing optdebug/release server_compile unit and smoke suites, plus SA create/query/shutdown and CS utility-channel operation. Check native builtin methods and locale defaults as part of compatibility coverage.

Boundaries: native METHOD support/reentrancy policy, new admission limits, AUTO session yield, and new session pools remain separately unresolved in the same productization ticket.
