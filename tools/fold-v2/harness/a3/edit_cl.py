import sys
p = sys.argv[1]; s = open(p).read()
def rep(o, n, c=1):
    global s
    assert s.count(o) == c, (s.count(o), o[:160])
    s = s.replace(o, n)

# includes
rep("""#include "vacuum.h"
#include "serial.h"
#endif /* defined (SA_MODE) */
""", """#include "vacuum.h"
#include "serial.h"
#if defined (SERVER_MODE)
#include "network_interface_sr.h"
#include "log_impl.h"
#include "schema_manager.h"
#endif /* SERVER_MODE */
#endif /* defined (SA_MODE) */
""")

# enter_server: RC snapshot invalidation as the wire header flag does it
rep("""static THREAD_ENTRY *
enter_server ()
{
  enter_server_no_thread_entry ();
  return thread_get_thread_entry_info ();
}
""", """static THREAD_ENTRY *
enter_server ()
{
  enter_server_no_thread_entry ();
#if defined (SERVER_MODE)
  THREAD_ENTRY *thread_p = thread_get_thread_entry_info ();

  /* a CS client asks this of its next request with NET_HEADER_FLAG_INVALIDATE_SNAPSHOT (see net_server_request) */
  if (tm_Tran_invalidate_snapshot)
    {
      (void) logtb_invalidate_snapshot_data (thread_p);
      tm_Tran_invalidate_snapshot = 0;
    }
  return thread_p;
#else
  return thread_get_thread_entry_info ();
#endif
}
""")

# exit_server: the deadlock-victim rollback return_error_to_client does on the wire
rep("""static void
exit_server (const THREAD_ENTRY & thread_ref)
{
  (void) thread_ref;		// not really used; just to force caller declare obtain thread entry

  exit_server_no_thread_entry ();
}
""", """static void
exit_server (const THREAD_ENTRY & thread_ref)
{
#if defined (SERVER_MODE)
  /* a CS client gets a failed request's error through return_error_to_client, which first rolls back a transaction
   * the request left to be aborted */
  if (er_errid () != NO_ERROR)
    {
      int errid;

      (void) abort_tran_on_error (const_cast < THREAD_ENTRY * >(&thread_ref), TRAN_UNACTIVE_UNKNOWN, &errid);
    }
#else
  (void) thread_ref;		// not really used; just to force caller declare obtain thread entry
#endif

  exit_server_no_thread_entry ();
}
""")

# RR lock riding the lockhint request
rep("""    xlocator_find_lockhint_class_oids (thread_p, num_classes, many_classnames, many_locks, many_need_subclasses,
				       many_flags, guessed_class_oids, guessed_class_chns, quit_on_errors, lockhint,
				       fetch_copyarea);

  exit_server (*thread_p);
""", """    xlocator_find_lockhint_class_oids (thread_p, num_classes, many_classnames, many_locks, many_need_subclasses,
				       many_flags, guessed_class_oids, guessed_class_chns, quit_on_errors, lockhint,
				       fetch_copyarea);

#if defined (SERVER_MODE)
  /* the RR transaction lock rides this request on the wire path (see slocator_find_lockhint_class_oids) */
  if (lock_rr_tran != NULL_LOCK && xtran_lock_rep_read (thread_p, lock_rr_tran) != NO_ERROR)
    {
      allfind = LC_CLASSNAME_ERROR;
      er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE, ER_GENERIC_ERROR, 0);
    }
  tm_Tran_rep_read_lock = lock_rr_tran;
#endif /* SERVER_MODE */

  exit_server (*thread_p);
""")

# commit carries the row count
rep("""  THREAD_ENTRY *thread_p = enter_server ();

  tran_state = xtran_server_commit (thread_p, retain_lock);
""", """  THREAD_ENTRY *thread_p = enter_server ();

#if defined (SERVER_MODE)
  /* the row count rides the commit request on the wire path (see stran_server_commit) */
  (void) xsession_set_row_count (thread_p, db_get_row_count_cache ());
#endif /* SERVER_MODE */

  tran_state = xtran_server_commit (thread_p, retain_lock);
""")

# btree_load_index: per-request values and the online loader's scratch btid
rep("""  THREAD_ENTRY *thread_p = enter_server ();

  if (index_status == SM_ONLINE_INDEX_BUILDING_IN_PROGRESS)
    {
      btid =
	xbtree_load_online_index (thread_p, btid, bt_name, key_type, class_oids, n_classes, n_attrs, attr_ids,
				  attrs_prefix_length, hfids, unique_pk, not_null_flag, fk_refcls_oid,
				  fk_refcls_pk_btid, fk_name, pred_stream, pred_stream_size, expr_stream,
				  expr_stream_size, func_col_id, func_attr_index_start, 1);
    }
  else
    {
      btid =
	xbtree_load_index (thread_p, btid, bt_name, key_type, class_oids, n_classes, n_attrs, attr_ids,
			   attrs_prefix_length, hfids, unique_pk, not_null_flag, fk_refcls_oid, fk_refcls_pk_btid,
			   fk_name, pred_stream, pred_stream_size, expr_stream, expr_stream_size, func_col_id,
			   func_attr_index_start, false);
    }
""", """#if defined (SERVER_MODE)
  /* the values the CS client sends with the request */
  const int ib_thread_count = ib_get_thread_count ();
  const bool no_logging_index = btree_Load_no_logging_index;
#else
  const int ib_thread_count = 1;
  const bool no_logging_index = false;
#endif

  THREAD_ENTRY *thread_p = enter_server ();

  if (index_status == SM_ONLINE_INDEX_BUILDING_IN_PROGRESS)
    {
      /* the online loader rewrites its btid for each class in turn; like the CS path, keep the caller's btid */
      BTID local_btid = *btid;

      if (xbtree_load_online_index (thread_p, &local_btid, bt_name, key_type, class_oids, n_classes, n_attrs,
				    attr_ids, attrs_prefix_length, hfids, unique_pk, not_null_flag, fk_refcls_oid,
				    fk_refcls_pk_btid, fk_name, pred_stream, pred_stream_size, expr_stream,
				    expr_stream_size, func_col_id, func_attr_index_start, ib_thread_count) == NULL)
	{
	  btid = NULL;
	}
    }
  else
    {
      btid =
	xbtree_load_index (thread_p, btid, bt_name, key_type, class_oids, n_classes, n_attrs, attr_ids,
			   attrs_prefix_length, hfids, unique_pk, not_null_flag, fk_refcls_oid, fk_refcls_pk_btid,
			   fk_name, pred_stream, pred_stream_size, expr_stream, expr_stream_size, func_col_id,
			   func_attr_index_start, no_logging_index);
    }
""")

# KILL TRANSACTION / KILL QUERY
rep("""#else /* CS_MODE */
  er_log_debug (ARG_FILE_LINE, "thread_kill_or_interrupt_tran: THIS IS ONLY a C/S function");
  return ER_FAILED;
#endif /* !CS_MODE */""", """#elif defined (SERVER_MODE)
  /* the loop of sthread_kill_or_interrupt_tran; the victims' errors land on this thread, not on a request worker */
  int success = NO_ERROR;
  int i;

  THREAD_ENTRY *thread_p = enter_server ();

  *num_killed = 0;
  for (i = 0; i < num_tran_index; i++)
    {
      int error = xlogtb_kill_or_interrupt_tran (thread_p, tran_index_list[i], is_dba_group_member, interrupt_only);
      if (error == ER_KILL_TR_NOT_ALLOWED)
	{
	  success = error;
	  break;
	}
      if (error == NO_ERROR)
	{
	  (*num_killed)++;
	}
      er_clear ();
    }

  exit_server (*thread_p);

  return success;
#else /* SA_MODE */
  er_log_debug (ARG_FILE_LINE, "thread_kill_or_interrupt_tran: THIS IS ONLY a C/S function");
  return ER_FAILED;
#endif /* SA_MODE */""")

# tran_lock_rep_read
rep("""  if (req_error == NO_ERROR)
    {
      tm_Tran_rep_read_lock = lock_rr_tran;
    }
  return req_error;
#else /* CS_MODE */
  return NO_ERROR;		/* No need to lock */
#endif /* !CS_MODE */""", """  if (req_error == NO_ERROR)
    {
      tm_Tran_rep_read_lock = lock_rr_tran;
    }
  return req_error;
#elif defined (SERVER_MODE)
  /* other sessions share the lock space, so the lock is really taken */
  THREAD_ENTRY *thread_p = enter_server ();

  int req_error = xtran_lock_rep_read (thread_p, lock_rr_tran);

  exit_server (*thread_p);

  if (req_error == NO_ERROR)
    {
      tm_Tran_rep_read_lock = lock_rr_tran;
    }
  return req_error;
#else /* SA_MODE */
  return NO_ERROR;		/* No need to lock */
#endif /* SA_MODE */""")

# DROP USER guard
rep("""#else /* CS_MODE */

  /* in SA_MODE, no other active user */
  *existed = false;
  return NO_ERROR;
#endif /* !CS_MODE */""", """#elif defined (SERVER_MODE)
  THREAD_ENTRY *thread_p = enter_server ();

  *existed = xlogtb_does_active_user_exist (thread_p, user_name);

  exit_server (*thread_p);

  return NO_ERROR;
#else /* SA_MODE */
  /* in SA_MODE, no other active user */
  *existed = false;
  return NO_ERROR;
#endif /* SA_MODE */""")

# CDC supplemental log of a DDL
rep("""  free_and_init (request);

  return rep_error;
#endif // CS_MODE
  return ER_NOT_IN_STANDALONE;
}""", """  free_and_init (request);

  return rep_error;
#elif defined (SERVER_MODE)
  THREAD_ENTRY *thread_p = enter_server ();

  int error = xlog_supplement_statement (thread_p, ddl_type, objtype, classoid, objoid, stmt_text);

  exit_server (*thread_p);

  return error;
#else
  return ER_NOT_IN_STANDALONE;
#endif
}""")

# DDL start time and text on the tdes
rep("""  net_client_request (NET_SERVER_TDES_SET_QUERY_START_INFO, request, request_len, NULL, 0, NULL, 0, NULL, 0);

  free_and_init (request);
#endif /* !CS_MODE */
}""", """  net_client_request (NET_SERVER_TDES_SET_QUERY_START_INFO, request, request_len, NULL, 0, NULL, 0, NULL, 0);

  free_and_init (request);
#elif defined (SERVER_MODE)
  THREAD_ENTRY *thread_p = enter_server ();

  xtdes_set_query_start_info (thread_p, sql_user_text);

  exit_server (*thread_p);
#endif
}""")
rep("""      net_client_request (NET_SERVER_TDES_RESET_QUERY_START_INFO, NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    }
#endif
}""", """      net_client_request (NET_SERVER_TDES_RESET_QUERY_START_INFO, NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    }
#elif defined (SERVER_MODE)
  if (pt_is_ddl_statement (node))
    {
      THREAD_ENTRY *thread_p = enter_server ();

      xtdes_reset_query_start_info (thread_p);

      exit_server (*thread_p);
    }
#endif
}""")

# UPDATE STATISTICS ON ALL CLASSES progress in the event log
rep("""  er_stack_push ();
  (void) net_client_request (NET_SERVER_QST_LOG_STATS_PROGRESS, request, OR_ALIGNED_BUF_SIZE (a_request), reply,
			     OR_ALIGNED_BUF_SIZE (a_reply), NULL, 0, NULL, 0);
  er_stack_pop ();
#endif /* CS_MODE */""", """  er_stack_push ();
  (void) net_client_request (NET_SERVER_QST_LOG_STATS_PROGRESS, request, OR_ALIGNED_BUF_SIZE (a_request), reply,
			     OR_ALIGNED_BUF_SIZE (a_reply), NULL, 0, NULL, 0);
  er_stack_pop ();
#elif defined (SERVER_MODE)
  INT64 now = stats_progress_clock_msec ();
  int class_ms = (int) std::min (now - class_start_msec, (INT64) INT_MAX);
  int elapsed_ms = (int) std::min (now - run_start_msec, (INT64) INT_MAX);

  THREAD_ENTRY *thread_p = enter_server ();

  xqst_log_stats_progress (thread_p, WS_OID (classop), phase, state, seq, total, class_ms, elapsed_ms, error);

  exit_server (*thread_p);
#endif /* SERVER_MODE */""")
open(p, 'w').write(s)
