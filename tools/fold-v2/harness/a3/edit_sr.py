import sys
p = sys.argv[1]; s = open(p).read()
def rep(o, n, c=1):
    global s
    assert s.count(o) == c, (s.count(o), o[:160])
    s = s.replace(o, n)

# --- abort decision shared with the in-process boundary
rep("""/*
 * return_error_to_client -
 *
 * return: state of operation
 *
 *   rid(in):
 *
 * NOTE:
 */
TRAN_STATE
return_error_to_client (THREAD_ENTRY *thread_p, unsigned int rid)
{
  LOG_TDES *tdes;
  int errid;
  bool flag_abort = false;
  char *area;""", """/*
 * abort_tran_on_error - before a failed request's error reaches its caller, roll back the transaction the request
 *                       left to be aborted and clear its abort reason
 *
 * return: the transaction state after the rollback, or tran_state when nothing was rolled back
 *
 *   thread_p(in): thread entry
 *   tran_state(in): the transaction state to return when nothing is rolled back
 *   errid(out): the latest error code
 */
TRAN_STATE
abort_tran_on_error (THREAD_ENTRY *thread_p, TRAN_STATE tran_state, int *errid)
{
  LOG_TDES *tdes = LOG_FIND_CURRENT_TDES (thread_p);

  /*
   * ER_LK_UNILATERALLY_ABORTED may have occurred due to deadlock.
   * If it happened, do server-side rollback of the transaction.
   * If ER_DB_NO_MODIFICATIONS error is occurred in server-side,
   * it means that the user tried to update the database
   * when the server was disabled to modify. (aka standby mode)
   */
  if (need_to_abort_tran (thread_p, errid) == true)
    {
      /* need to hide the previous error, ER_LK_UNILATERALLY_ABORTED to rollback the current transaction. */
      er_stack_push ();
      tran_state = tran_server_unilaterally_abort_tran (thread_p);
      er_stack_pop ();
    }

  if (tdes != NULL)
    {
      tdes->tran_abort_reason = TRAN_NORMAL;
    }

  return tran_state;
}

/*
 * return_error_to_client -
 *
 * return: state of operation
 *
 *   rid(in):
 *
 * NOTE:
 */
TRAN_STATE
return_error_to_client (THREAD_ENTRY *thread_p, unsigned int rid)
{
  LOG_TDES *tdes;
  int errid;
  char *area;""")
rep("""      tran_state = tdes->state;
    }
  flag_abort = need_to_abort_tran (thread_p, &errid);

  /* check some errors which require special actions */
  /*
   * ER_LK_UNILATERALLY_ABORTED may have occurred due to deadlock.
   * If it happened, do server-side rollback of the transaction.
   * If ER_DB_NO_MODIFICATIONS error is occurred in server-side,
   * it means that the user tried to update the database
   * when the server was disabled to modify. (aka standby mode)
   */
  if (flag_abort == true)
    {
      /* need to hide the previous error, ER_LK_UNILATERALLY_ABORTED to rollback the current transaction. */
      er_stack_push ();
      tran_state = tran_server_unilaterally_abort_tran (thread_p);
      er_stack_pop ();
    }

  if (errid == ER_DB_NO_MODIFICATIONS)""", """      tran_state = tdes->state;
    }
  tran_state = abort_tran_on_error (thread_p, tran_state, &errid);

  if (errid == ER_DB_NO_MODIFICATIONS)""")
rep("""      css_send_error_to_client (conn, rid, area, length);
      conn->db_error = 0;
    }

  if (tdes != NULL)
    {
      tdes->tran_abort_reason = TRAN_NORMAL;
    }

  return tran_state;
}""", """      css_send_error_to_client (conn, rid, area, length);
      conn->db_error = 0;
    }

  return tran_state;
}""")

# --- CDC supplemental log of a DDL
rep("""void
slog_supplement_statement (THREAD_ENTRY *thread_p, unsigned int rid, char *request, int reqlen)
{
  int success = NO_ERROR;
  OR_ALIGNED_BUF (OR_INT_SIZE) a_reply;
  char *reply = OR_ALIGNED_BUF_START (a_reply);
  char *ptr, *start_ptr;

  int ddl_type;
  int obj_type;
  OID classoid;
  OID oid;
  char *stmt_text;

  char *supplemental_data;
  int data_len;
  LOG_TDES *tdes;

  /* CAS and Server are able to have different parameter value, when broker restarted with changed parameter value */
  if (prm_get_integer_value (PRM_ID_SUPPLEMENTAL_LOG) == 1)
    {
      ptr = or_unpack_int (request, &ddl_type);
      ptr = or_unpack_int (ptr, &obj_type);

      ptr = or_unpack_oid (ptr, &classoid);
      ptr = or_unpack_oid (ptr, &oid);

      or_unpack_string_nocopy (ptr, &stmt_text);

      /* ddl_type | obj_type | class OID | OID | stmt_text len | stmt_text */""", """/*
 * xlog_supplement_statement - append the supplemental log record of a DDL statement
 *
 * return: error code
 */
int
xlog_supplement_statement (THREAD_ENTRY *thread_p, int ddl_type, int obj_type, const OID *classoid, const OID *oid,
			   const char *stmt_text)
{
  char *ptr, *start_ptr;
  char *supplemental_data;
  int data_len;
  LOG_TDES *tdes;

  /* CAS and Server are able to have different parameter value, when broker restarted with changed parameter value */
  if (prm_get_integer_value (PRM_ID_SUPPLEMENTAL_LOG) == 1)
    {
      /* ddl_type | obj_type | class OID | OID | stmt_text len | stmt_text */""")
rep("""      supplemental_data = (char *) malloc (data_len + MAX_ALIGNMENT);
      if (supplemental_data == NULL)
	{
	  success = ER_OUT_OF_VIRTUAL_MEMORY;
	  goto end;
	}

      ptr = start_ptr = supplemental_data;

      ptr = or_pack_int (ptr, ddl_type);
      ptr = or_pack_int (ptr, obj_type);
      ptr = or_pack_oid (ptr, &classoid);
      ptr = or_pack_oid (ptr, &oid);""", """      supplemental_data = (char *) malloc (data_len + MAX_ALIGNMENT);
      if (supplemental_data == NULL)
	{
	  return ER_OUT_OF_VIRTUAL_MEMORY;
	}

      ptr = start_ptr = supplemental_data;

      ptr = or_pack_int (ptr, ddl_type);
      ptr = or_pack_int (ptr, obj_type);
      ptr = or_pack_oid (ptr, classoid);
      ptr = or_pack_oid (ptr, oid);""")
rep("""      log_append_supplemental_info (thread_p, LOG_SUPPLEMENT_DDL, data_len, (void *) supplemental_data);

      free_and_init (supplemental_data);
    }

end:
  (void) or_pack_int (reply, success);
""", """      log_append_supplemental_info (thread_p, LOG_SUPPLEMENT_DDL, data_len, (void *) supplemental_data);

      free_and_init (supplemental_data);
    }

  return NO_ERROR;
}

void
slog_supplement_statement (THREAD_ENTRY *thread_p, unsigned int rid, char *request, int reqlen)
{
  int success = NO_ERROR;
  OR_ALIGNED_BUF (OR_INT_SIZE) a_reply;
  char *reply = OR_ALIGNED_BUF_START (a_reply);
  char *ptr;

  int ddl_type;
  int obj_type;
  OID classoid;
  OID oid;
  char *stmt_text;

  if (prm_get_integer_value (PRM_ID_SUPPLEMENTAL_LOG) == 1)
    {
      ptr = or_unpack_int (request, &ddl_type);
      ptr = or_unpack_int (ptr, &obj_type);

      ptr = or_unpack_oid (ptr, &classoid);
      ptr = or_unpack_oid (ptr, &oid);

      or_unpack_string_nocopy (ptr, &stmt_text);

      success = xlog_supplement_statement (thread_p, ddl_type, obj_type, &classoid, &oid, stmt_text);
    }

  (void) or_pack_int (reply, success);
""")

# --- UPDATE STATISTICS progress
rep("""void
sqst_log_stats_progress (THREAD_ENTRY *thread_p, unsigned int rid, char *request, int reqlen)
{
  OID classoid;
  int phase, state, seq, total, class_ms, elapsed_ms, error;
  char *class_name = NULL;
  FILE *log_fp;
  int indent = 2;
  char *ptr;
  OR_ALIGNED_BUF (OR_INT_SIZE) a_reply;
  char *reply = OR_ALIGNED_BUF_START (a_reply);

  if (reqlen >= OR_OID_SIZE + OR_INT_SIZE * 7)
    {
      ptr = or_unpack_oid (request, &classoid);
      ptr = or_unpack_int (ptr, &phase);
      ptr = or_unpack_int (ptr, &state);
      ptr = or_unpack_int (ptr, &seq);
      ptr = or_unpack_int (ptr, &total);
      ptr = or_unpack_int (ptr, &class_ms);
      ptr = or_unpack_int (ptr, &elapsed_ms);
      ptr = or_unpack_int (ptr, &error);

      /* keep whatever the logging sets (e.g. the event log file cannot be reopened) away from the caller */
      er_stack_push ();

      if (heap_get_class_name (thread_p, &classoid, &class_name) != NO_ERROR)
	{
	  class_name = NULL;
	}
""", """void
xqst_log_stats_progress (THREAD_ENTRY *thread_p, const OID *classoid, int phase, int state, int seq, int total,
			 int class_ms, int elapsed_ms, int error)
{
  char *class_name = NULL;
  FILE *log_fp;
  int indent = 2;

  /* keep whatever the logging sets (e.g. the event log file cannot be reopened) away from the caller */
  er_stack_push ();

  if (heap_get_class_name (thread_p, classoid, &class_name) != NO_ERROR)
    {
      class_name = NULL;
    }
""")
rep("""      log_fp = event_log_start (thread_p, "UPDATE_STATISTICS");
      if (log_fp != NULL)
	{
	  event_log_print_client_info (LOG_FIND_THREAD_TRAN_INDEX (thread_p), indent);
	  fprintf (log_fp, "%*cclass: %s\\n", indent, ' ', class_name ? class_name : "*UNKNOWN-CLASS*");
	  if (state == STATS_PROGRESS_STARTED)
	    {
	      fprintf (log_fp, "%*cprogress: %s started %d/%d, elapsed: %.3f sec\\n\\n", indent, ' ',
		       phase == STATS_PROGRESS_HISTOGRAM ? "histogram" : "statistics", seq, total, elapsed_ms / 1000.0);
	    }
	  else
	    {
	      fprintf (log_fp, "%*cprogress: %s finished %d/%d, error: %d, time: %.3f sec, elapsed: %.3f sec\\n\\n",
		       indent, ' ', phase == STATS_PROGRESS_HISTOGRAM ? "histogram" : "statistics", seq, total, error,
		       class_ms / 1000.0, elapsed_ms / 1000.0);
	    }
	  event_log_end (thread_p);
	}

      if (class_name != NULL)
	{
	  free_and_init (class_name);
	}

      er_stack_pop ();
    }
""", """  log_fp = event_log_start (thread_p, "UPDATE_STATISTICS");
  if (log_fp != NULL)
    {
      event_log_print_client_info (LOG_FIND_THREAD_TRAN_INDEX (thread_p), indent);
      fprintf (log_fp, "%*cclass: %s\\n", indent, ' ', class_name ? class_name : "*UNKNOWN-CLASS*");
      if (state == STATS_PROGRESS_STARTED)
	{
	  fprintf (log_fp, "%*cprogress: %s started %d/%d, elapsed: %.3f sec\\n\\n", indent, ' ',
		   phase == STATS_PROGRESS_HISTOGRAM ? "histogram" : "statistics", seq, total, elapsed_ms / 1000.0);
	}
      else
	{
	  fprintf (log_fp, "%*cprogress: %s finished %d/%d, error: %d, time: %.3f sec, elapsed: %.3f sec\\n\\n",
		   indent, ' ', phase == STATS_PROGRESS_HISTOGRAM ? "histogram" : "statistics", seq, total, error,
		   class_ms / 1000.0, elapsed_ms / 1000.0);
	}
      event_log_end (thread_p);
    }

  if (class_name != NULL)
    {
      free_and_init (class_name);
    }

  er_stack_pop ();
}

void
sqst_log_stats_progress (THREAD_ENTRY *thread_p, unsigned int rid, char *request, int reqlen)
{
  OID classoid;
  int phase, state, seq, total, class_ms, elapsed_ms, error;
  char *ptr;
  OR_ALIGNED_BUF (OR_INT_SIZE) a_reply;
  char *reply = OR_ALIGNED_BUF_START (a_reply);

  if (reqlen >= OR_OID_SIZE + OR_INT_SIZE * 7)
    {
      ptr = or_unpack_oid (request, &classoid);
      ptr = or_unpack_int (ptr, &phase);
      ptr = or_unpack_int (ptr, &state);
      ptr = or_unpack_int (ptr, &seq);
      ptr = or_unpack_int (ptr, &total);
      ptr = or_unpack_int (ptr, &class_ms);
      ptr = or_unpack_int (ptr, &elapsed_ms);
      ptr = or_unpack_int (ptr, &error);

      xqst_log_stats_progress (thread_p, &classoid, phase, state, seq, total, class_ms, elapsed_ms, error);
    }
""")

# --- DDL start time and text on the tdes
rep("""void
stdes_set_query_start_info (THREAD_ENTRY *thread_p, unsigned int rid, char *request, int reqlen)
{
  char *sql_user_text = NULL;
  int tran_index = -1;
  LOG_TDES *tdes_p;

  or_unpack_string_nocopy (request, &sql_user_text);
  tran_index = LOG_FIND_THREAD_TRAN_INDEX (thread_p);
""", """void
xtdes_set_query_start_info (THREAD_ENTRY *thread_p, const char *sql_user_text)
{
  int tran_index = -1;
  LOG_TDES *tdes_p;

  tran_index = LOG_FIND_THREAD_TRAN_INDEX (thread_p);
""")
rep("""      if (sql_user_text)
	{
	  tdes_p->ddl_sql_user_text = strdup (sql_user_text);
	}
    }

  css_send_data_to_client (thread_p->conn_entry, rid, NULL, 0);
}""", """      if (sql_user_text)
	{
	  tdes_p->ddl_sql_user_text = strdup (sql_user_text);
	}
    }
}

void
stdes_set_query_start_info (THREAD_ENTRY *thread_p, unsigned int rid, char *request, int reqlen)
{
  char *sql_user_text = NULL;

  or_unpack_string_nocopy (request, &sql_user_text);
  xtdes_set_query_start_info (thread_p, sql_user_text);

  css_send_data_to_client (thread_p->conn_entry, rid, NULL, 0);
}""")
rep("""void
stdes_reset_query_start_info (THREAD_ENTRY *thread_p, unsigned int rid, char *request, int reqlen)
{
  int tran_index = -1;""", """void
xtdes_reset_query_start_info (THREAD_ENTRY *thread_p)
{
  int tran_index = -1;""")
rep("""	  free_and_init (tdes_p->ddl_sql_user_text);
	}
    }

  css_send_data_to_client (thread_p->conn_entry, rid, NULL, 0);
}""", """	  free_and_init (tdes_p->ddl_sql_user_text);
	}
    }
}

void
stdes_reset_query_start_info (THREAD_ENTRY *thread_p, unsigned int rid, char *request, int reqlen)
{
  xtdes_reset_query_start_info (thread_p);

  css_send_data_to_client (thread_p->conn_entry, rid, NULL, 0);
}""")
open(p, 'w').write(s)
