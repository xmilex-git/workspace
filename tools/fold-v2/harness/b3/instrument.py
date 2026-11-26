# TLATRACE instrumentation for docs/tla/CBRD-27430-B3 (scratch worktree only; adds lines only).
# usage: python3 instrument.py <worktree>
# The server appends "TLATRACE <ns> <pid> <Action> tid=<thread> k=v ..." to $CUBRID_TLATRACE_OUT; events.py
# renames the session threads into the model's sessions.
# Stimulus (not the code under test): with CUBRID_TLA_B3_HB set, `cubrid changemode` skips its ha_mode check
# and the server runs the requested change as the heartbeat would (css_change_ha_server_state, heartbeat=true).
import re, sys
W = sys.argv[1]
HERE = sys.argv[0].rsplit("/", 1)[0]
HDR = re.search(r"HDR = r'''(.*?)'''", open(HERE + "/../b1a/instrument.py").read(), re.S).group(1)
HDR = HDR.replace('#include <unistd.h>\n', '#include <unistd.h>\n#include <sys/syscall.h>\n#include <string.h>\n')
HDR = HDR.replace('#define tla_trace(...) tla_trace_at (tla_now (), __VA_ARGS__)',
                  '#define tla_trace(...) tla_trace_at (tla_now (), __VA_ARGS__)\n'
                  '#define TLA_TID ((int) syscall (SYS_gettid))\n'
                  '#define TLA_BASE(f) (strrchr ((f), \'/\') ? strrchr ((f), \'/\') + 1 : (f))')
open(f"{W}/src/base/tla_trace.h", "w").write(HDR)


def edit(path, pairs):
    p = f"{W}/{path}"
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (path, s.count(o), o[:100])
        s = s.replace(o, n)
    open(p, "w").write(s)


# ---------------------------------------------------------------- the HA state changer
edit("src/connection/server_support.c", [
  ('#include "server_support.h"\n', '#include "server_support.h"\n#include "tla_trace.h"\n'),
  ('''      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_ACTIVE);
      if (state == HA_SERVER_STATE_NA)
	{
	  break;
	}
''', '''      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_ACTIVE);
      if (state == HA_SERVER_STATE_NA)
	{
	  break;
	}
      tla_trace ("Promote1 tid=%d st=%d", TLA_TID, (int) state);
'''),
  ('''	  state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_ACTIVE);
	  assert (state == HA_SERVER_STATE_ACTIVE);
	}
''', '''	  state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_ACTIVE);
	  assert (state == HA_SERVER_STATE_ACTIVE);
	  tla_trace ("Promote2 tid=%d st=%d", TLA_TID, (int) state);
	}
'''),
  ('''      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_STANDBY);
      if (state == HA_SERVER_STATE_NA)
	{
	  break;
	}
''', '''      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_STANDBY);
      if (state == HA_SERVER_STATE_NA)
	{
	  break;
	}
      tla_trace ("Demote1 tid=%d st=%d", TLA_TID, (int) state);
'''),
  ('''	      er_log_debug (ARG_FILE_LINE, "css_change_ha_server_state: " "logtb_count_clients () = 0\\n");
	      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_STANDBY);
	      assert (state == HA_SERVER_STATE_STANDBY);
	    }
''', '''	      er_log_debug (ARG_FILE_LINE, "css_change_ha_server_state: " "logtb_count_clients () = 0\\n");
	      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_STANDBY);
	      assert (state == HA_SERVER_STATE_STANDBY);
	    }
	  tla_trace ("Demote2 tid=%d st=%d", TLA_TID, (int) state);
'''),
  ('''      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_MAINTENANCE);
      if (state == HA_SERVER_STATE_NA)
	{
	  break;
	}
''', '''      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_MAINTENANCE);
      if (state == HA_SERVER_STATE_NA)
	{
	  break;
	}
      tla_trace ("Maint tid=%d st=%d", TLA_TID, (int) state);
'''),
  ('''	      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_STANDBY);
	      assert (state == HA_SERVER_STATE_STANDBY);
	      if (state == HA_SERVER_STATE_STANDBY)
		{
''', '''	      state = css_transit_ha_server_state (thread_p, HA_SERVER_STATE_STANDBY);
	      assert (state == HA_SERVER_STATE_STANDBY);
	      tla_trace ("LeaveTransit tid=%d st=%d", TLA_TID, (int) state);
	      if (state == HA_SERVER_STATE_STANDBY)
		{
'''),
])
edit("src/transaction/log_tran_table.c", [
  ('#include "log_impl.h"\n', '#include "log_impl.h"\n#include "tla_trace.h"\n'),
  ('''  db_Disable_modifications = 1;
''', '''  db_Disable_modifications = 1;
  tla_trace ("GateDis tid=%d", TLA_TID);
'''),
  ('''  db_Disable_modifications = 0;
''', '''  db_Disable_modifications = 0;
  tla_trace ("GateEn tid=%d", TLA_TID);
'''),
])
edit("src/communication/network_interface_sr.cpp", [
  ('''      if (css_change_ha_server_state (thread_p, state, force, timeout, false) != NO_ERROR)
''', '''      if (getenv ("CUBRID_TLA_B3_HB") != NULL)
	{
	  (void) css_change_ha_server_state (thread_p, state, force, timeout, true);
	}
      if (css_change_ha_server_state (thread_p, state, force, timeout, false) != NO_ERROR)
'''),
])
edit("src/executables/util_cs.c", [
  ('''  if (HA_DISABLED ())
    {
      PRINT_AND_LOG_ERR_MSG (msgcat_message (MSGCAT_CATALOG_UTILS, MSGCAT_UTIL_SET_CHANGEMODE,
					     CHANGEMODE_MSG_NOT_HA_MODE));
''', '''  if (getenv ("CUBRID_TLA_B3_HB") == NULL)
  if (HA_DISABLED ())
    {
      PRINT_AND_LOG_ERR_MSG (msgcat_message (MSGCAT_CATALOG_UTILS, MSGCAT_UTIL_SET_CHANGEMODE,
					     CHANGEMODE_MSG_NOT_HA_MODE));
'''),
])

# ---------------------------------------------------------------- the session
edit("src/connection/driver_session.cpp", [
  ('#include "driver_session.hpp"\n', '#include "driver_session.hpp"\n#include "tla_trace.h"\n'),
  ('''    admission_check (int client_type, int ha_state, bool is_replica_server, bool repl_delayed)
    {
''', '''    admission_check (int client_type, int ha_state, bool is_replica_server, bool repl_delayed)
    {
      tla_trace ("AdmitIn tid=%d type=%d ha=%d d=%d", TLA_TID, client_type, ha_state, repl_delayed ? 1 : 0);
'''),
  ('''				 HA_GET_MODE () == HA_MODE_REPLICA, css_is_ha_repl_delayed ());
''', '''				 HA_GET_MODE () == HA_MODE_REPLICA, css_is_ha_repl_delayed ());
	tla_trace ("Admit tid=%d rej=%d", TLA_TID, deny != NULL ? 1 : 0);
	if (deny == NULL && getenv ("CUBRID_TLA_B3_ADMIT_DELAY_MS") != NULL)
	  {
	    usleep (1000 * atoi (getenv ("CUBRID_TLA_B3_ADMIT_DELAY_MS")));	/* widens the admission-to-registration window */
	  }
'''),
  ('''      if (err != NO_ERROR)
	{
	  /* cas_db_connect failure path: DBMS error straight to the driver, and its line in the SQL and slow
	   * logs */
''', '''      tla_trace ("Register tid=%d ok=%d retry=%d resumed=%d cnt=%d base=%d sid=%u", TLA_TID, err == NO_ERROR ? 1 : 0,
		 err == ERR_CSS_ERROR_FROM_SERVER ? 1 : 0, resumed ? 1 : 0, db_Client_disable_modifications,
		 err == NO_ERROR ? logtb_is_tran_modification_disabled (entry_p) : 0, (unsigned) db_get_session_id ());
      if (err != NO_ERROR)
	{
	  /* cas_db_connect failure path: DBMS error straight to the driver, and its line in the SQL and slow
	   * logs */
'''),
  ('''	  (void) boot_unregister_client (tm_Tran_index);
	  tm_Tran_index = NULL_TRAN_INDEX;
''', '''	  (void) boot_unregister_client (tm_Tran_index);
	  tm_Tran_index = NULL_TRAN_INDEX;
	  tla_trace ("Leave tid=%d y=%d ha=%d", TLA_TID, yielded ? 1 : 0, (int) css_ha_server_state ());
'''),
])
edit("src/compat/db_admin.c", [
  ('#include "db.h"\n', '#include "db.h"\n#include "tla_trace.h"\n'),
  ('''  db_Client_disable_modifications++;
''', '''  db_Client_disable_modifications++;
#if defined (SERVER_MODE)
  tla_trace ("MBegin tid=%d cnt=%d", TLA_TID, db_Client_disable_modifications);
#endif
'''),
  ('''  db_Client_disable_modifications--;
''', '''  db_Client_disable_modifications--;
#if defined (SERVER_MODE)
  tla_trace ("MEnd tid=%d cnt=%d", TLA_TID, db_Client_disable_modifications);
#endif
'''),
])
# the client half's refusals: every CHECK_MODIFICATION_* macro of db.h
p = f"{W}/src/compat/db.h"
s = open(p).read()
a = s.index('/* CHECK MODIFICATION */'); b = s.index('#endif /* CHECK_MODIFICATION_NO_RETURN */')
seg = s[a:b]
n0 = seg.count('er_set(ER_ERROR_SEVERITY, ARG_FILE_LINE, ER_DB_NO_MODIFICATIONS, 0);')
assert n0 == 3, n0
seg = "\n".join(("    TLA_CLREF (); \\\n" + l) if 'er_set(ER_ERROR_SEVERITY, ARG_FILE_LINE, ER_DB_NO_MODIFICATIONS, 0);' in l else l
                for l in seg.split("\n"))
s = s[:a] + '''#include "tla_trace.h"
#if defined (SERVER_MODE)
#define TLA_CLREF() tla_trace ("ClRef tid=%d f=%s", TLA_TID, TLA_BASE (__FILE__))
#else
#define TLA_CLREF()
#endif
''' + seg + s[b:]
open(p, "w").write(s)
# the server's checks: wire dispatch (CS clients), the fold boundary, the executor, the serial code
edit("src/transaction/log_impl.h", [
  ('''      mod_disabled = logtb_is_tran_modification_disabled (thread_p); \\
''', '''      mod_disabled = logtb_is_tran_modification_disabled (thread_p); \\
      tla_trace ("SrvChk tid=%d f=%s ref=%d", TLA_TID, TLA_BASE (__FILE__), mod_disabled); \\
'''),
  ('#ifndef CHECK_MODIFICATION_NO_RETURN\n', '#include "tla_trace.h"\n#ifndef CHECK_MODIFICATION_NO_RETURN\n'),
])
edit("src/communication/network_interface_cl.c", [
  ('''#if defined (SERVER_MODE)
  const bool has_updated = logtb_has_updated (thread_p);

  /* net_server_request refuses the commit of a transaction that wrote and may not write any more */
''', '''#if defined (SERVER_MODE)
  const bool has_updated = logtb_has_updated (thread_p);

  tla_trace ("End0 tid=%d", TLA_TID);
  /* net_server_request refuses the commit of a transaction that wrote and may not write any more */
'''),
  ('''  tran_state = xtran_server_commit (thread_p, retain_lock);

#if defined (SERVER_MODE)
''', '''  tran_state = xtran_server_commit (thread_p, retain_lock);

#if defined (SERVER_MODE)
  tla_trace ("End1 tid=%d hu=%d base=%d", TLA_TID, has_updated ? 1 : 0, logtb_is_tran_modification_disabled (thread_p));
'''),
  ('''  tran_state = xtran_server_abort (thread_p);

#if defined (SERVER_MODE)
''', '''  tran_state = xtran_server_abort (thread_p);

#if defined (SERVER_MODE)
  tla_trace ("End1 tid=%d hu=%d base=%d", TLA_TID, has_updated ? 1 : 0, logtb_is_tran_modification_disabled (thread_p));
'''),
])
edit("src/transaction/transaction_sr.c", [
  ('#include "transaction_sr.h"\n', '#include "transaction_sr.h"\n#include "tla_trace.h"\n'),
  ('''  return should_conn_reset;
}
''', '''  tla_trace ("End2 tid=%d type=%d ha=%d d=%d r=%d roc=%d", TLA_TID, client_type, (int) ha_state,
	     css_is_ha_repl_delayed ()? 1 : 0, should_conn_reset ? 1 : 0,
	     (thread_p->conn_entry != NULL && thread_p->conn_entry->reset_on_commit) ? 1 : 0);
  return should_conn_reset;
}
'''),
])
print("instrumented")
