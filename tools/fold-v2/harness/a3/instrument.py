# TLATRACE instrumentation of the A3 boundary for docs/tla/CBRD-27430-A3 (scratch worktree only)
import sys
W = sys.argv[1]
def edit(path, pairs):
    p = f"{W}/{path}"; s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (path, s.count(o), o[:100])
        s = s.replace(o, n)
    open(p, "w").write(s)

DECL = '''#if defined (SERVER_MODE)
extern thread_local bool tla_fold_thread;
extern thread_local const char *tla_kind;
extern thread_local bool tla_in_rr;
extern thread_local int tla_rr_waited;
extern void tla_trace (const char *fmt, ...);
#endif
'''

edit("src/transaction/server_compile_tracer.cpp", [
  ('''static void tracer_main (char *server_name, char *sql, char *out_path);''',
   '''static void tracer_main (char *server_name, char *sql, char *out_path);

thread_local bool tla_fold_thread = false;
thread_local const char *tla_kind = "read";
thread_local bool tla_in_rr = false;
thread_local int tla_rr_waited = 0;
static FILE *tla_fp = NULL;
static unsigned long tla_seq = 0;

void
tla_trace (const char *fmt, ...)
{
  if (!tla_fold_thread || tla_fp == NULL)
    {
      return;
    }
  va_list ap;
  fprintf (tla_fp, "TLATRACE seq=%lu ", ++tla_seq);
  va_start (ap, fmt);
  vfprintf (tla_fp, fmt, ap);
  va_end (ap);
  fputc ('\\n', tla_fp);
  fflush (tla_fp);
}'''),
  ('''  registered = true;
  tracer_log (fp, "M0_TRACER: in-process client registered (0-hop)");
''', '''  registered = true;
  tracer_log (fp, "M0_TRACER: in-process client registered (0-hop)");
  if (const char *tla_out = std::getenv ("CUBRID_TLATRACE_OUT"))
    {
      tla_fp = fopen (tla_out, "w");
      tla_fold_thread = (tla_fp != NULL);
    }
'''),
  ('''  if (registered)
    {
      /* log the tran out''', '''  tla_fold_thread = false;
  if (registered)
    {
      /* log the tran out'''),
])

edit("src/communication/network_interface_cl.c", [
  ('''#if defined (SERVER_MODE)
#include "network_interface_sr.h"''', DECL + '''#if defined (SERVER_MODE)
#include "network_interface_sr.h"'''),
  ('''  /* a CS client asks this of its next request with NET_HEADER_FLAG_INVALIDATE_SNAPSHOT (see net_server_request) */
  if (tm_Tran_invalidate_snapshot)
    {''', '''  /* a CS client asks this of its next request with NET_HEADER_FLAG_INVALIDATE_SNAPSHOT (see net_server_request) */
  tla_trace ("a=Enter p=S k=%s inv=%d d=%u", tla_kind, tm_Tran_invalidate_snapshot ? 1 : 0, db_on_server);
  tla_kind = "read";
  if (tm_Tran_invalidate_snapshot)
    {'''),
  ('''  if (er_errid () != NO_ERROR)
    {
      int errid;

      (void) abort_tran_on_error (const_cast < THREAD_ENTRY * >(&thread_ref), TRAN_UNACTIVE_UNKNOWN, &errid);
    }''', '''  TRAN_STATE tla_st = TRAN_UNACTIVE_UNKNOWN;
  if (er_errid () != NO_ERROR)
    {
      int errid;

      tla_st = abort_tran_on_error (const_cast < THREAD_ENTRY * >(&thread_ref), TRAN_UNACTIVE_UNKNOWN, &errid);
    }
  {
    int e = er_errid ();
    tla_trace ("a=Exit p=S e=%s abort=%d", e == NO_ERROR ? "none" : e == ER_LK_UNILATERALLY_ABORTED ? "unilat"
	       : e == ER_KILL_TR_NOT_ALLOWED ? "notallowed" : e == ER_CSS_CONN_SHUTDOWN ? "shutdown" : "other",
	       tla_st != TRAN_UNACTIVE_UNKNOWN ? 1 : 0);
  }'''),
  # lockhint
  ('''  LC_FIND_CLASSNAME allfind = LC_CLASSNAME_ERROR;

  THREAD_ENTRY *thread_p = enter_server ();

  allfind =
    xlocator_find_lockhint_class_oids''', '''  LC_FIND_CLASSNAME allfind = LC_CLASSNAME_ERROR;

#if defined (SERVER_MODE)
  const bool tla_hint = TM_TRAN_ISOLATION () >= TRAN_REPEATABLE_READ
    && (lock_rr_tran != NULL_LOCK || tm_Tran_rep_read_lock != NULL_LOCK);
  tla_kind = tla_hint ? "hint" : "read";
#endif
  THREAD_ENTRY *thread_p = enter_server ();

  allfind =
    xlocator_find_lockhint_class_oids'''),
  ('''  if (lock_rr_tran != NULL_LOCK && er_errid () != ER_LK_UNILATERALLY_ABORTED
      && LOG_FIND_CURRENT_TDES (thread_p)->tran_abort_reason == TRAN_NORMAL
      && xtran_lock_rep_read (thread_p, lock_rr_tran) != NO_ERROR)
    {
      allfind = LC_CLASSNAME_ERROR;
      er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE, ER_GENERIC_ERROR, 0);
    }''', '''  if (lock_rr_tran != NULL_LOCK && er_errid () != ER_LK_UNILATERALLY_ABORTED
      && LOG_FIND_CURRENT_TDES (thread_p)->tran_abort_reason == TRAN_NORMAL)
    {
      tla_in_rr = true;
      tla_rr_waited = 0;
      int tla_rc = xtran_lock_rep_read (thread_p, lock_rr_tran);
      tla_in_rr = false;
      if (tla_hint)
	{
	  tla_trace ("a=RRLock p=S wait=%d", tla_rr_waited != 0 ? 1 : 0);
	  if (tla_rr_waited != 0)
	    {
	      tla_trace (tla_rr_waited == 2 ? "a=Victim p=E" : "a=Grant p=E");
	    }
	}
      if (tla_rc != NO_ERROR)
	{
	  allfind = LC_CLASSNAME_ERROR;
	  er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE, ER_GENERIC_ERROR, 0);
	}
    }
  else if (tla_hint)
    {
      tla_trace ("a=RRLock p=S wait=0");
    }'''),
  # tran_lock_rep_read
  ('''  /* other sessions share the lock space, so the lock is really taken */
  THREAD_ENTRY *thread_p = enter_server ();

  int req_error = xtran_lock_rep_read (thread_p, lock_rr_tran);
''', '''  /* other sessions share the lock space, so the lock is really taken */
  tla_kind = "rr";
  THREAD_ENTRY *thread_p = enter_server ();

  tla_in_rr = true;
  tla_rr_waited = 0;
  int req_error = xtran_lock_rep_read (thread_p, lock_rr_tran);
  tla_in_rr = false;
  tla_trace ("a=RRLock p=S wait=%d", tla_rr_waited != 0 ? 1 : 0);
  if (tla_rr_waited != 0)
    {
      tla_trace (tla_rr_waited == 2 ? "a=Victim p=E" : "a=Grant p=E");
    }
'''),
  # kill
  ('''  THREAD_ENTRY *thread_p = enter_server ();

  *num_killed = 0;
  for (i = 0; i < num_tran_index; i++)
    {
      int error = xlogtb_kill_or_interrupt_tran (thread_p, tran_index_list[i], is_dba_group_member, interrupt_only);''',
   '''  tla_kind = "kill";
  THREAD_ENTRY *thread_p = enter_server ();

  *num_killed = 0;
  for (i = 0; i < num_tran_index; i++)
    {
      int error = xlogtb_kill_or_interrupt_tran (thread_p, tran_index_list[i], is_dba_group_member, interrupt_only);
      tla_trace ("a=KillStep p=S o=%s", error == NO_ERROR ? "ok" : error == ER_KILL_TR_NOT_ALLOWED ? "notallowed"
		 : "unknown");'''),
  # commit
  ('''  THREAD_ENTRY *thread_p = enter_server ();

#if defined (SERVER_MODE)
  /* the row count rides the commit request on the wire path (see stran_server_commit) */
  (void) xsession_set_row_count (thread_p, db_get_row_count_cache ());
#endif /* SERVER_MODE */

  tran_state = xtran_server_commit (thread_p, retain_lock);
''', '''#if defined (SERVER_MODE)
  tla_kind = "commit";
#endif
  THREAD_ENTRY *thread_p = enter_server ();

#if defined (SERVER_MODE)
  /* the row count rides the commit request on the wire path (see stran_server_commit) */
  (void) xsession_set_row_count (thread_p, db_get_row_count_cache ());
#endif /* SERVER_MODE */

  tran_state = xtran_server_commit (thread_p, retain_lock);
#if defined (SERVER_MODE)
  tla_trace ("a=CommitStep p=S");
#endif
'''),
])

edit("src/compat/db_vdb.c", [
  ('''void
db_invalidate_mvcc_snapshot_before_statement (void)
{''', DECL + '''void
db_invalidate_mvcc_snapshot_before_statement (void)
{
#if defined (SERVER_MODE)
  tla_trace ("a=StmtStart p=S");
#endif'''),
])

edit("src/transaction/log_tran_table.c", [
  ('''MVCC_SNAPSHOT *
logtb_get_mvcc_snapshot (THREAD_ENTRY * thread_p)
{''', DECL + '''MVCC_SNAPSHOT *
logtb_get_mvcc_snapshot (THREAD_ENTRY * thread_p)
{'''),
  ('''  if (!tdes->mvccinfo.snapshot.valid)
    {
      log_Gl.mvcc_table.build_mvcc_info (*tdes);
    }

  if (main_thread_p != NULL)''', '''#if defined (SERVER_MODE)
  tla_trace ("a=Read p=S built=%d", tdes->mvccinfo.snapshot.valid ? 0 : 1);
#endif
  if (!tdes->mvccinfo.snapshot.valid)
    {
      log_Gl.mvcc_table.build_mvcc_info (*tdes);
    }

  if (main_thread_p != NULL)'''),
])

edit("src/transaction/lock_manager.c", [
  ('''static void lock_set_tran_abort_reason (int tran_index, TRAN_ABORT_REASON abort_reason);''',
   '''static void lock_set_tran_abort_reason (int tran_index, TRAN_ABORT_REASON abort_reason);
''' + DECL),
  ('''  /* I must not be a deadlock-victim thread */
  assert (tdes->tran_abort_reason == TRAN_NORMAL);
''', '''  /* I must not be a deadlock-victim thread */
#if defined (SERVER_MODE)
  if (tla_in_rr)
    {
      tla_rr_waited = 1;
    }
  else
    {
      tla_trace ("a=LockWait p=S");
    }
#endif
  assert (tdes->tran_abort_reason == TRAN_NORMAL);
'''),
  ('''  switch ((LOCK_WAIT_STATE) (entry_ptr->thrd_entry->lockwait_state))
    {
    case LOCK_RESUMED:
      /* The lock entry has already been moved to the holder list */
      return LOCK_RESUMED;''', '''#if defined (SERVER_MODE)
  {
    const bool tla_victim = entry_ptr->thrd_entry->lockwait_state == (int) LOCK_RESUMED_ABORTED_FIRST;
    if (tla_in_rr)
      {
	tla_rr_waited = tla_victim ? 2 : 1;
      }
    else
      {
	tla_trace (tla_victim ? "a=Victim p=E" : "a=Grant p=E");
      }
  }
#endif
  switch ((LOCK_WAIT_STATE) (entry_ptr->thrd_entry->lockwait_state))
    {
    case LOCK_RESUMED:
      /* The lock entry has already been moved to the holder list */
      return LOCK_RESUMED;'''),
])
print("instrumented")
