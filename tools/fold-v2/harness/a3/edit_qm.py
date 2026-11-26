import sys
p = sys.argv[1]; s = open(p).read()
def rep(old, new, count=1):
    global s
    n = s.count(old)
    assert n == count, (n, old[:120])
    s = s.replace(old, new)
# execute_query
rep(""" *   dbval_p(in) : array of host variables (query input parameters)
""", """ *   dbvals_p(in) : array of host variables (borrowed: never freed or kept past this call)
""")
rep("""		     void *dbval_p, QUERY_FLAG * flag_p, CACHE_TIME * client_cache_time_p,""",
    """		     DB_VALUE * dbvals_p, QUERY_FLAG * flag_p, CACHE_TIME * client_cache_time_p,""")
rep("""  QFILE_LIST_CACHE_ENTRY *list_cache_entry_p;
  DB_VALUE *dbvals_p;
#if defined (SERVER_MODE)
  DB_VALUE *dbval;
  HL_HEAPID old_pri_heap_id;
  char *data;
#endif
  int i;
""", """  QFILE_LIST_CACHE_ENTRY *list_cache_entry_p;
  int i;
""")
rep("""  list_cache_entry_p = NULL;

  dbvals_p = NULL;
#if defined (SERVER_MODE)
  data = (char *) dbval_p;
  old_pri_heap_id = 0;
#endif

""", """  list_cache_entry_p = NULL;

""")
rep("""  params.vals = NULL;

#if defined (SERVER_MODE)
  if (dbval_count)
    {
      char *ptr;

      assert (data != NULL);

      dbvals_p = (DB_VALUE *) db_private_alloc (thread_p, sizeof (DB_VALUE) * dbval_count);
      if (dbvals_p == NULL)
	{
	  goto exit_on_error;
	}

      /* unpack DB_VALUEs from the received data */
      ptr = data;
      for (i = 0, dbval = dbvals_p; i < dbval_count; i++, dbval++)
	{
	  ptr = or_unpack_db_value (ptr, dbval);
	}
    }
#else
  dbvals_p = (DB_VALUE *) dbval_p;
#endif

""", """  params.vals = NULL;

""")
free_blk = """#if defined (SERVER_MODE)
  if (dbvals_p)
    {
      for (i = 0, dbval = dbvals_p; i < dbval_count; i++, dbval++)
	{
	  pr_clear_value (dbval);
	}
      db_private_free_and_init (thread_p, dbvals_p);
    }
#endif

"""
rep(free_blk, "", 2)
# prepare_and_execute
rep(""" *   dbval_p(in)      : List of positional values
""", """ *   dbvals_p(in)      : List of positional values (borrowed: never freed or kept past this call)
""")
rep("""				 QUERY_ID * query_id_p, int dbval_count, void *dbval_p, QUERY_FLAG * flag_p,
				 int query_timeout)
{
#if defined (SERVER_MODE)
  DB_VALUE *dbval;
  HL_HEAPID old_pri_heap_id;
  char *data;
  int i;
#endif
  DB_VALUE *dbvals_p;
  QMGR_QUERY_ENTRY *query_p;""", """				 QUERY_ID * query_id_p, int dbval_count, DB_VALUE * dbvals_p, QUERY_FLAG * flag_p,
				 int query_timeout)
{
  QMGR_QUERY_ENTRY *query_p;""")
rep("""  list_id_p = NULL;

  dbvals_p = NULL;

#if defined (SERVER_MODE)""", """  list_id_p = NULL;

#if defined (SERVER_MODE)""")
rep("""#endif


#if defined (SERVER_MODE)
  data = (char *) dbval_p;
  old_pri_heap_id = 0;
#endif

  saved_is_stats_on""", """#endif

  saved_is_stats_on""")
rep("""  qmgr_set_query_exec_info_to_tdes (tran_index, query_timeout, NULL);

  if (dbval_count)
    {
      char *ptr;

      assert (data != NULL);

      dbvals_p = (DB_VALUE *) db_private_alloc (thread_p, sizeof (DB_VALUE) * dbval_count);
      if (dbvals_p == NULL)
	{
	  goto exit_on_error;
	}

      /* unpack DB_VALUEs from the received data */
      ptr = data;
      for (i = 0, dbval = dbvals_p; i < dbval_count; i++, dbval++)
	{
	  ptr = or_unpack_db_value (ptr, dbval);
	}
    }
#else
  dbvals_p = (DB_VALUE *) dbval_p;

  /* allocate""", """  qmgr_set_query_exec_info_to_tdes (tran_index, query_timeout, NULL);
#else
  /* allocate""")
open(p, 'w').write(s)
