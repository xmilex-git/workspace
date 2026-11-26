import sys
W=sys.argv[1]
def rd(p): return open(W+'/'+p).read()
def wr(p,s): open(W+'/'+p,'w').write(s)
def sub(path, old, new, cnt=1):
    s=rd(path); assert s.count(old)==cnt,(path,old[:50],s.count(old)); wr(path,s.replace(old,new))
D='src/broker/cas_dispatch.c'
sub(D,'''   * request arrived too late to interrupt the previous request and still remains. */
  db_set_interrupt (0);
''','''   * request arrived too late to interrupt the previous request and still remains. Not while an upload is open: the
   * statement is still running, and the stream's next request carries the interrupt to the server, which ends it. */
  if (!ux_stream_is_open ())
    {
      db_set_interrupt (0);
    }
''')
sub(D,'''  if (func_code <= 0 || func_code >= CAS_FC_MAX)
    {
      FREE_MEM (argv);
      FREE_MEM (read_msg);
      net_write_error (sock_fd, req_info->client_version, req_info->driver_info, cas_msg_header.info_ptr, cas_info_size,
		       CAS_ERROR_INDICATOR, CAS_ER_COMMUNICATION, NULL);
      return FN_CLOSE_CONN;
    }
''','''  if (func_code <= 0 || func_code >= CAS_FC_PROBE_MAX)
    {
      FREE_MEM (argv);
      FREE_MEM (read_msg);
      net_write_error (sock_fd, req_info->client_version, req_info->driver_info, cas_msg_header.info_ptr, cas_info_size,
		       CAS_ERROR_INDICATOR, CAS_ER_COMMUNICATION, NULL);
      return FN_CLOSE_CONN;
    }
  /* a code a later release adds: answered as not implemented, and it does no work in the transaction */
  func_code_unknown = (func_code >= CAS_FC_MAX);
''')
sub(D,'''  con_status_to_restore = -1;

  if (FUNC_NEEDS_RESTORING_CON_STATUS (func_code))
''','''  ux_stream_note_status_before (is_first_request ? CON_STATUS_OUT_TRAN
				: (con_status_before_check_cas != -1 ? con_status_before_check_cas : old_con_status));

  con_status_to_restore = -1;

  if (FUNC_NEEDS_RESTORING_CON_STATUS (func_code) || ux_stream_finds_no_upload (func_code) || func_code_unknown)
''')
sub(D,'''  strcpy (as_info->log_msg, server_func_name[func_code - 1]);

  server_fn = server_fn_table[func_code - 1];
''','''  if (func_code_unknown)
    {
      strcpy (as_info->log_msg, "fn_not_supported");
      server_fn = fn_not_supported;
    }
  else
    {
      strcpy (as_info->log_msg, server_func_name[func_code - 1]);
      server_fn = server_fn_table[func_code - 1];
    }
  if (!func_code_unknown && !ux_stream_admits_request (func_code))
    {
      server_fn = fn_stream_refused;
    }
''')
sub(D,'''      as_info->con_status = con_status_to_restore;
      CON_STATUS_UNLOCK (as_info, CON_STATUS_LOCK_CAS);
    }

''','''      as_info->con_status = con_status_to_restore;
      CON_STATUS_UNLOCK (as_info, CON_STATUS_LOCK_CAS);
    }

  /* an upload given up leaves nothing in the transaction */
  con_status_to_restore = ux_stream_status_to_restore ();
  if (con_status_to_restore != -1)
    {
      CON_STATUS_LOCK (as_info, CON_STATUS_LOCK_CAS);
      as_info->con_status = con_status_to_restore;
      CON_STATUS_UNLOCK (as_info, CON_STATUS_LOCK_CAS);
    }
''')
sub(D,'''	(as_info->cci_default_autocommit & CAS_INFO_FLAG_MASK_AUTOCOMMIT);

''','''	(as_info->cci_default_autocommit & CAS_INFO_FLAG_MASK_AUTOCOMMIT);

      /* init_msg_header () leaves it at 0 */
      if (ux_stream_is_open ())
	{
	  cas_msg_header.info_ptr[CAS_INFO_ADDITIONAL_FLAG] |= CAS_INFO_FLAG_MASK_STREAM_OPEN;
	}

''')
