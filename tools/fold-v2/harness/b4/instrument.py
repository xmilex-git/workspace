# TLATRACE instrumentation for docs/tla/CBRD-27430-B4 (scratch worktree only; adds lines only).
# usage: python3 instrument.py <worktree>
# cub_broker and the servers append "TLATRACE <ns> <pid> <Action> k=v ..." to $CUBRID_TLATRACE_OUT;
# events_token.py and events_domain.py rename them into the models' steps.
# Knobs that restore the behavior before this change (to record the holes, not the code under test):
#   CUBRID_TLA_B4_NO_SCAN=1     cub_broker: the dispatcher never asks the other servers again (TokenTable no_scan)
#   CUBRID_TLA_B4_NO_SID=1      cub_server: a cancel is not asked for its session id (TokenTable no_sid_check)
#   CUBRID_TLA_B4_OLD_DOMAIN=1  cub_server: a domain that holds a MOP goes to the process lists (DomainCache
#                               process_list)
import re, sys
W = sys.argv[1]
HERE = sys.argv[0].rsplit("/", 1)[0]
HDR = re.search(r"HDR = r'''(.*?)'''", open(HERE + "/../b1a/instrument.py").read(), re.S).group(1)
HDR = HDR.replace('#include <unistd.h>\n', '#include <unistd.h>\n#include <sys/syscall.h>\n#include <string.h>\n')
HDR = HDR.replace('#define tla_trace(...) tla_trace_at (tla_now (), __VA_ARGS__)',
                  '#define tla_trace(...) tla_trace_at (tla_now (), __VA_ARGS__)\n'
                  '#define TLA_TID ((int) syscall (SYS_gettid))\n'
                  'static inline int tla_knob (const char *name) { const char *v = getenv (name); return v != NULL && v[0] == \'1\'; }')
open(f"{W}/src/base/tla_trace.h", "w").write(HDR)


def edit(path, pairs):
    p = f"{W}/{path}"
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (path, s.count(o), o[:100])
        s = s.replace(o, n)
    open(p, "w").write(s)


# ---------------------------------------------------------------- the broker
edit("src/broker/broker_direct.cpp", [
  ('#include <algorithm>\n', '#include <algorithm>\n#include "tla_trace.h"\n'),
  # tokens_end: this channel's entry of the token
  ('''	    m.tokens.erase (it);
	    slots_add (m, -1);
	    brd_debug ("end db=%s gen=%llu token=%u slots=%d", ch.db_name.c_str (), (unsigned long long) ch.generation,
		       token, m.slots_used.load ());
	    return;''', '''	    m.tokens.erase (it);
	    slots_add (m, -1);
	    tla_trace ("End db=%s tok=%u", ch.db_name.c_str (), token);
	    brd_debug ("end db=%s gen=%llu token=%u slots=%d", ch.db_name.c_str (), (unsigned long long) ch.generation,
		       token, m.slots_used.load ());
	    return;'''),
  # the channel's death
  ('''    tokens_drop_for_channel (*m, *ch);
    if (published)''', '''    tokens_drop_for_channel (*m, *ch);
    tla_trace ("RDrop db=%s gen=%llu pub=%d", ch->db_name.c_str (), (unsigned long long) ch->generation,
	       published ? 1 : 0);
    if (published)'''),
  # channel_get_or_dial
  ('''      if (it != m.channels.end () && !it->second->dead.load ())
	{
	  return it->second;
	}
    }

    std::string path = adoption_socket_path (db_name.c_str ());''', '''      if (it != m.channels.end () && !it->second->dead.load ())
	{
	  tla_trace ("Dial db=%s res=live", db_name.c_str ());
	  return it->second;
	}
    }

    std::string path = adoption_socket_path (db_name.c_str ());'''),
  ('''    if (connect (fd, (struct sockaddr *) &addr, sizeof (addr)) < 0)
      {
	close (fd);
	return NULL;
      }

    std::shared_ptr<channel> ch;
    try
      {
	ch = std::make_shared<channel> ();
	ch->reply_body.resize''', '''    if (connect (fd, (struct sockaddr *) &addr, sizeof (addr)) < 0)
      {
	close (fd);
	tla_trace ("Dial db=%s res=refused", db_name.c_str ());
	return NULL;
      }

    std::shared_ptr<channel> ch;
    try
      {
	ch = std::make_shared<channel> ();
	ch->reply_body.resize'''),
  ('''	|| reply_header.length != sizeof (hello_ack) || hello_ack.proto_version != adopt::PROTO_VERSION)
      {
	channel_kill (*ch);
	return NULL;
      }''', '''	|| reply_header.length != sizeof (hello_ack) || hello_ack.proto_version != adopt::PROTO_VERSION)
      {
	channel_kill (*ch);
	tla_trace ("Dial db=%s res=noans", db_name.c_str ());
	return NULL;
      }'''),
  ('''	|| reply_header.length < sizeof (resync))
      {
	channel_kill (*ch);
	return NULL;
      }

    std::lock_guard<std::mutex> guard (m.channels_mutex);
    if (ch->dead.load ())
      {
	return NULL;	/* died after its reply: the reader already dropped it */
      }
    m.channels[db_name] = ch;
    return ch;''', '''	|| reply_header.length < sizeof (resync))
      {
	channel_kill (*ch);
	tla_trace ("Dial db=%s res=noans", db_name.c_str ());
	return NULL;
      }

    std::lock_guard<std::mutex> guard (m.channels_mutex);
    if (ch->dead.load ())
      {
	tla_trace ("Dial db=%s res=noans", db_name.c_str ());
	return NULL;	/* died after its reply: the reader already dropped it */
      }
    m.channels[db_name] = ch;
    tla_trace ("Dial db=%s res=ok gen=%llu", db_name.c_str (), (unsigned long long) ch->generation);
    return ch;'''),
  # the dispatcher
  ('''  if (m->resync_pending.exchange (false))
    {
      dial_listening_servers (*m);
    }
  std::shared_ptr<channel> ch = channel_get_or_dial (*m, db_name);''', '''  const bool tla_scan = !tla_knob ("CUBRID_TLA_B4_NO_SCAN") && m->resync_pending.exchange (false);
  tla_trace ("DStart db=%s port=%d scan=%d", db_name, (int) job->port, tla_scan ? 1 : 0);
  if (tla_scan)
    {
      dial_listening_servers (*m);
      tla_trace ("DScanEnd");
    }
  tla_trace ("DDial db=%s", db_name);
  std::shared_ptr<channel> ch = channel_get_or_dial (*m, db_name);'''),
  ('''  if (!brd_wait_for_slot (*m))
    {
      reject_client (*m, job->clt_sock_fd, CAS_ER_FREE_SERVER, job->driver_info);
      close (job->clt_sock_fd);
      return;
    }
''', '''  if (!brd_wait_for_slot (*m))
    {
      tla_trace ("DGiveUp");
      reject_client (*m, job->clt_sock_fd, CAS_ER_FREE_SERVER, job->driver_info);
      close (job->clt_sock_fd);
      return;
    }
  tla_trace ("DWait");
'''),
  ('''  if (handoff_result != 0)
    {
      brd_debug ("handoff db=%s: request failed/timeout", db_name);''', '''  if (handoff_result != 0)
    {
      tla_trace ("DSendFail db=%s", db_name);
      brd_debug ("handoff db=%s: request failed/timeout", db_name);'''),
  ('''      m->shm->brd_num_handoffs++;	/* the dispatch thread only */''', '''      {
	adopt::resync_token_body tla_ack;
	std::memcpy (&tla_ack, reply_body, sizeof (tla_ack));
	tla_trace ("DSendOk db=%s tok=%u", db_name, tla_ack.token);
      }
      m->shm->brd_num_handoffs++;	/* the dispatch thread only */'''),
  ('''  /* HANDOFF_REJECT: shutting down, the server's client capacity (#117 D3
   * backstop), or a malformed handoff — a negative ACK proves no session
   * was started, so the driver gets the retryable error */
  reject_client''', '''  tla_trace ("DSendNo db=%s", db_name);
  /* HANDOFF_REJECT: shutting down, the server's client capacity (#117 D3
   * backstop), or a malformed handoff — a negative ACK proves no session
   * was started, so the driver gets the retryable error */
  reject_client'''),
  # cancel
  ('''  token_info found;
  bool have = false;
  {
    std::lock_guard<std::mutex> guard (m.tokens_mutex);
    auto range = m.tokens.equal_range (token);''', '''  token_info found;
  bool have = false;
  {
    std::lock_guard<std::mutex> guard (m.tokens_mutex);
    auto range = m.tokens.equal_range (token);
    int tla_cands = 0;
    for (auto tla_it = range.first; tla_it != range.second; ++tla_it)
      {
	if ((clt_ip == NULL || std::memcmp (tla_it->second.clt_ip, clt_ip, 4) == 0)
	    && (clt_port == 0 || tla_it->second.clt_port == clt_port))
	  {
	    tla_cands++;
	    found = tla_it->second;
	  }
      }
    tla_trace ("CnLook tok=%u port=%d cands=%d db=%s", token, (int) clt_port, tla_cands,
	       tla_cands == 1 ? found.db_name.c_str () : "-");'''),
  ('''  adopt::session_ref_body body = { token, session_id, clt_port, (std::uint8_t) (has_session_id ? 1 : 0), 0 };
  return channel_send (*ch, adopt::msg_op::CANCEL, &body, sizeof (body)) == 0 ? 0 : -1;''', '''  adopt::session_ref_body body = { token, session_id, clt_port, (std::uint8_t) (has_session_id ? 1 : 0), 0 };
  tla_trace ("CnSend db=%s tok=%u has=%d sid=%u", ch->db_name.c_str (), token, has_session_id ? 1 : 0, session_id);
  return channel_send (*ch, adopt::msg_op::CANCEL, &body, sizeof (body)) == 0 ? 0 : -1;'''),
  ('''  std::shared_ptr<channel> ch = brd_token_channel (*m, token, clt_ip, clt_port);
  if (ch == NULL)
    {
      return -1;
    }''', '''  std::shared_ptr<channel> ch = brd_token_channel (*m, token, clt_ip, clt_port);
  if (ch == NULL)
    {
      tla_trace ("CnNone tok=%u", token);
      return -1;
    }'''),
  # the broker starts
  ('''  m->peek_thread = std::thread (peek_thread_run, m);
  brd_Manager = m;''', '''  m->peek_thread = std::thread (peek_thread_run, m);
  brd_Manager = m;
  tla_trace ("BStart broker=%s max=%d", broker_name, max_slots);'''),
])

# ---------------------------------------------------------------- the server's adoption endpoint
edit("src/connection/adoption.cpp", [
  ('#include "adoption.hpp"\n', '#include "adoption.hpp"\n#include "tla_trace.h"\n'),
  ('''	  it->second.binding->session_id = session_id;
	  it->second.binding->session_id_required = session_id_required;''', '''	  it->second.binding->session_id = session_id;
	  it->second.binding->session_id_required = session_id_required;
	  tla_trace ("SLogin db=%s tok=%u sid=%u req=%d", m->db_name.c_str (), token, session_id,
		     session_id_required ? 1 : 0);'''),
  ('''      if (pin.tran_index != NULL_TRAN_INDEX && binding_is_named_by (binding, body))
	{''', '''      tla_trace ("SCancel db=%s tok=%u hit=%d", m.db_name.c_str (), body.token,
		 pin.tran_index != NULL_TRAN_INDEX && binding_is_named_by (binding, body) ? 1 : 0);
      if (pin.tran_index != NULL_TRAN_INDEX && binding_is_named_by (binding, body))
	{'''),
  ('''      m->active_finishers.fetch_add (1);
      current_session.reset ();
''', '''      m->active_finishers.fetch_add (1);
      current_session.reset ();
      tla_trace ("SFin db=%s tok=%u", m->db_name.c_str (), token);
'''),
  ('''      if (send_message (ch, msg_op::HANDOFF_ACK, &ack, sizeof (ack)) == NO_ERROR)
	{
	  session_start_release (start, &params);''', '''      if (send_message (ch, msg_op::HANDOFF_ACK, &ack, sizeof (ack)) == NO_ERROR)
	{
	  tla_trace ("SAck db=%s tok=%u port=%d", m.db_name.c_str (), token, (int) ack.client_port);
	  session_start_release (start, &params);'''),
  ('''      std::lock_guard<std::mutex> guard (binding->mutex);
      if (ref.client_port != 0 && ref.client_port != binding->client_port)''', '''      std::lock_guard<std::mutex> guard (binding->mutex);
      if (tla_knob ("CUBRID_TLA_B4_NO_SID"))
	{
	  return true;	/* knob: the server before this change */
	}
      if (ref.client_port != 0 && ref.client_port != binding->client_port)'''),
  ('''      manager *m = new manager ();
      m->db_name = db_name;
      m->socket_path = get_adoption_domain_path (db_name);''', '''      manager *m = new manager ();
      m->db_name = db_name;
      m->socket_path = get_adoption_domain_path (db_name);
      tla_trace ("SStart db=%s", db_name);'''),
])

# ---------------------------------------------------------------- the session's thread
edit("src/connection/driver_session.cpp", [
  ('#include "driver_session.hpp"\n', '#include "driver_session.hpp"\n#include "tla_trace.h"\n'),
  ('''      registered = true;
      db_set_client_ip_addr (client_ip_str);''', '''      registered = true;
      tla_trace ("%s tid=%d csc=%p", resumed ? "Resume" : "Begin", TLA_TID, (void *) csc_current ());
      db_set_client_ip_addr (client_ip_str);'''),
  ('''	  if (!yielded && !is_xa_prepared ())
	    {
	      (void) ux_end_tran (CCI_TRAN_ROLLBACK, false, true);
	    }''', '''	  tla_trace ("%s tid=%d csc=%p xa=%d", yielded ? "Yield" : "EndRollback", TLA_TID, (void *) csc_current (),
		     is_xa_prepared () ? 1 : 0);
	  if (!yielded && !is_xa_prepared ())
	    {
	      (void) ux_end_tran (CCI_TRAN_ROLLBACK, false, true);
	    }'''),
])

# ---------------------------------------------------------------- the session's client context
edit("src/object/client_session_context.cpp", [
  ('#include "client_session_context.hpp"\n', '#include "client_session_context.hpp"\n#include "tla_trace.h"\n'),
  ('''      ws_final (false);
      /* after ws_final (): the workspace's classes point at these domains, and the domains at its MOPs */
      tp_free_sub_client_domains ();''', '''      tla_trace ("WsFinal tid=%d csc=%p", TLA_TID, (void *) ctx);
      ws_final (false);
      /* after ws_final (): the workspace's classes point at these domains, and the domains at its MOPs */
      tp_free_sub_client_domains ();
      tla_trace ("FreeLists tid=%d csc=%p", TLA_TID, (void *) ctx);'''),
  ('''  csc_activate (ctx);
  csc_teardown (ctx);
  tl_Csc_active = NULL;''', '''  csc_activate (ctx);
  tla_trace ("Retire tid=%d csc=%p", TLA_TID, (void *) ctx);
  csc_teardown (ctx);
  tl_Csc_active = NULL;'''),
])

# ---------------------------------------------------------------- the domain cache
edit("src/object/object_domain.c", [
  ('#include "client_session_context.hpp"\n', '#include "client_session_context.hpp"\n#include "tla_trace.h"\n'),
  ('#define tp_is_sub_client() csc_bracket_is_active ()',
   '#define tp_is_sub_client() (csc_bracket_is_active () && !tla_knob ("CUBRID_TLA_B4_OLD_DOMAIN"))'),
  ('''  assert (!tp_domain_list_has_class_mop (transient));''',
   '''  assert (tla_knob ("CUBRID_TLA_B4_OLD_DOMAIN") || !tp_domain_list_has_class_mop (transient));'''),
  # the sub-client lists: found or inserted
  ('''      domain = tp_is_domain_cached (*dlist, transient, TP_EXACT_MATCH, &ins_pos);
      if (domain != NULL)
	{
	  tp_domain_free (transient);
	  return domain;
	}
    }

  /*
   * Unlike the shared lists''', '''      domain = tp_is_domain_cached (*dlist, transient, TP_EXACT_MATCH, &ins_pos);
      if (domain != NULL)
	{
#if defined (SERVER_MODE)
	  if (TP_DOMAIN_TYPE (domain) == DB_TYPE_OBJECT && domain->class_mop != NULL)
	    {
	      tla_trace ("ResolveSess tid=%d csc=%p mop=%p oid=%d.%d ins=0", TLA_TID, (void *) csc_current (),
			 (void *) domain->class_mop, WS_OID (domain->class_mop)->pageid,
			 (int) WS_OID (domain->class_mop)->slotid);
	    }
#endif
	  tp_domain_free (transient);
	  return domain;
	}
    }
#if defined (SERVER_MODE)
  if (TP_DOMAIN_TYPE (transient) == DB_TYPE_OBJECT && transient->class_mop != NULL)
    {
      tla_trace ("ResolveSess tid=%d csc=%p mop=%p oid=%d.%d ins=1", TLA_TID, (void *) csc_current (),
		 (void *) transient->class_mop, WS_OID (transient->class_mop)->pageid,
		 (int) WS_OID (transient->class_mop)->slotid);
    }
#endif

  /*
   * Unlike the shared lists'''),
  # the process lists: a node inserted
  ('''   * list as they are encountered.
   */
  transient->is_cached = 1;
''', '''   * list as they are encountered.
   */
  transient->is_cached = 1;
#if defined (SERVER_MODE)
  if (TP_DOMAIN_TYPE (transient) == DB_TYPE_OBJECT && transient->class_mop != NULL)
    {
      tla_trace ("ResolveProc tid=%d csc=%p mop=%p oid=%d.%d ins=1", TLA_TID,
		 csc_bracket_is_active () ? (void *) csc_current () : NULL, (void *) transient->class_mop,
		 WS_OID (transient->class_mop)->pageid, (int) WS_OID (transient->class_mop)->slotid);
    }
#endif
'''),
  # tp_domain_find_object
  ('''  TP_DOMAIN *dom;

  /* tp_domain_find_with_classinfo */

  dom = tp_domain_get_list (type, NULL);''', '''  TP_DOMAIN *dom;
#if defined (SERVER_MODE)
  int tla_mops = 0;
  void *tla_mop0 = NULL;
#endif

  /* tp_domain_find_with_classinfo */

  dom = tp_domain_get_list (type, NULL);'''),
  ('''  for (; dom != NULL; dom = dom->next_list)
    {
      /* we MUST perform exact matches here */

      /* Always prefer comparison of MOPs */
      if (dom->class_mop != NULL && class_mop != NULL)
	{
	  if (dom->class_mop == class_mop && dom->is_desc == is_desc)''', '''  for (; dom != NULL; dom = dom->next_list)
    {
#if defined (SERVER_MODE)
      if (dom->class_mop != NULL && class_mop == NULL)
	{
	  if (tla_mops++ == 0)
	    {
	      tla_mop0 = (void *) dom->class_mop;
	    }
	}
#endif
      /* we MUST perform exact matches here */

      /* Always prefer comparison of MOPs */
      if (dom->class_mop != NULL && class_mop != NULL)
	{
	  if (dom->class_mop == class_mop && dom->is_desc == is_desc)'''),
  ('''		  break;	/* found */
		}
	    }
	}
    }

  return dom;
}

/*
 * tp_domain_find_set''', '''		  break;	/* found */
		}
	    }
	}
    }

#if defined (SERVER_MODE)
  if (type == DB_TYPE_OBJECT && class_mop == NULL && class_oid != NULL && !OID_ISNULL (class_oid))
    {
      tla_trace ("FindOid tid=%d csc=%p oid=%d.%d mops=%d mop0=%p", TLA_TID,
		 csc_bracket_is_active () ? (void *) csc_current () : NULL, class_oid->pageid, (int) class_oid->slotid,
		 tla_mops, tla_mop0);
    }
  else if (type == DB_TYPE_OBJECT && class_mop != NULL && dom != NULL && csc_bracket_is_active ())
    {
      tla_trace ("%s tid=%d csc=%p mop=%p oid=%d.%d ins=0",
		 tla_knob ("CUBRID_TLA_B4_OLD_DOMAIN") ? "ResolveProcHit" : "ResolveSess", TLA_TID,
		 (void *) csc_current (), (void *) class_mop, WS_OID (class_mop)->pageid,
		 (int) WS_OID (class_mop)->slotid);
    }
#endif

  return dom;
}

/*
 * tp_domain_find_set'''),
])
print("instrumented", W)
