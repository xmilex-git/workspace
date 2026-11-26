# TLATRACE instrumentation for docs/tla/CBRD-27430-B1b (scratch worktree only; adds lines only).
# usage: python3 instrument.py <worktree>
# Broker and server append "TLATRACE <ns> <pid> <Action> k=v ..." to $CUBRID_TLATRACE_OUT; events.py merges them.
import re, sys
W = sys.argv[1]
HERE = sys.argv[0].rsplit("/", 1)[0]
HDR = re.search(r"HDR = r'''(.*?)'''", open(HERE + "/../b1a/instrument.py").read(), re.S).group(1)
open(f"{W}/src/base/tla_trace.h", "w").write(HDR)


def edit(path, pairs):
    p = f"{W}/{path}"
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (path, s.count(o), o[:100])
        assert n.startswith(o) or n.endswith(o) or o in n, (path, o[:60])
        s = s.replace(o, n)
    open(p, "w").write(s)


# ---------------------------------------------------------------- broker
edit("src/broker/broker_direct.cpp", [
  ('#include <algorithm>\n', '#include <algorithm>\n#include "tla_trace.h"\n'),
  ('''  for (;;)
    {
      std::uint64_t seen_hint;
      {
	std::lock_guard<std::mutex> guard (m.slots_mutex);
''', '''  bool tla_skip = false;
  for (;;)
    {
      std::uint64_t seen_hint;
      {
	std::lock_guard<std::mutex> guard (m.slots_mutex);
	if (!tla_skip)
	  {
	    tla_trace ("BTop full=%d", ready () ? 0 : 1);
	  }
'''),
  ('''	      adopt::token_body reply = { 0 };
	      if (channel_request (*ch, adopt::msg_op::YIELD_TRY''', '''	      adopt::token_body reply = { 0 };
	      tla_trace ("BTry");
	      if (channel_request (*ch, adopt::msg_op::YIELD_TRY'''),
  ('''		{
		  claimed = true;
		  break;
		}
''', '''		{
		  tla_trace ("BTryRep rep=1");
		  claimed = true;
		  break;
		}
	      tla_trace ("BTryRep rep=0");
'''),
  ('''	  adopt::token_body on = { 1 };
''', '''	  adopt::token_body on = { 1 };
	  tla_trace ("BWatch");
'''),
  ('''      if (watching)
	{
	  adopt::token_body off = { 0 };
''', '''      if (!awakened)
	{
	  tla_trace ("BTimeout");
	}
      else if (ready ())
	{
	  tla_trace ("BSlot");
	  tla_skip = true;
	}
      else
	{
	  tla_trace ("BHint");
	}
      if (watching)
	{
	  adopt::token_body off = { 0 };
'''),
  ('''  if (!brd_wait_for_slot (*m))
''', '''  tla_trace ("BStart");
  if (!brd_wait_for_slot (*m))
'''),
])

# ---------------------------------------------------------------- server: adoption
edit("src/connection/adoption.cpp", [
  ('#include "adoption.hpp"\n', '#include "adoption.hpp"\n#include "tla_trace.h"\n'),
  ('''    static thread_local std::shared_ptr<auto_group> current_group;
''', '''    static thread_local std::shared_ptr<auto_group> current_group;
    static thread_local unsigned tla_tok = 0;
    unsigned tla_tok_get (void)
    {
      return tla_tok;
    }
'''),
  ('''	  current_binding->wake_fd = wake_fd;
	  return true;
''', '''	  current_binding->wake_fd = wake_fd;
	  tla_tok = token;
	  return true;
'''),
  ('''      current_binding->state.store (execution_state::idle);
      if (current_binding->reset_requested.load ())
	{
	  execution_state expected = execution_state::idle;
	  (void) current_binding->state.compare_exchange_strong (expected, execution_state::yielded);
	  wake_session (current_binding);
	  return;
	}
''', '''      current_binding->state.store (execution_state::idle);
      tla_trace ("Top tok=%u clean=1", tla_tok);
      if (current_binding->reset_requested.load ())
	{
	  execution_state expected = execution_state::idle;
	  (void) current_binding->state.compare_exchange_strong (expected, execution_state::yielded);
	  wake_session (current_binding);
	  tla_trace ("Rst tok=%u rreq=1", tla_tok);
	  return;
	}
      tla_trace ("Rst tok=%u rreq=0", tla_tok);
      tla_trace ("Wch tok=%u go=%d", tla_tok, (current_group->watch_requested.load ()
					       && current_binding->state.load () == execution_state::idle) ? 1 : 0);
'''),
  ('''	  && current_group->watch_requested.exchange (false))
	{
	  send_idle_hint (*current_group);
''', '''	  && current_group->watch_requested.exchange (false))
	{
	  tla_trace ("Wx tok=%u", tla_tok);
	  send_idle_hint (*current_group);
'''),
  ('''      const bool yielded = current_binding->state.exchange (execution_state::closing) == execution_state::yielded;
''', '''      const bool yielded = current_binding->state.exchange (execution_state::closing) == execution_state::yielded;
      tla_trace ("Finish tok=%u yld=%d", tla_tok, yielded ? 1 : 0);
'''),
  ('''      std::shared_ptr<session_binding> binding;
      {
	std::lock_guard<std::mutex> guard (m.registry_mutex);
	for (const auto &pair : m.registry)
	  {
	    execution_state expected = execution_state::idle;
''', '''      std::shared_ptr<session_binding> binding;
      {
	std::lock_guard<std::mutex> guard (m.registry_mutex);
	tla_trace ("CStart op=try");
	for (const auto &pair : m.registry)
	  {
	    execution_state expected = execution_state::idle;
	    if (std::strncmp (pair.second.broker_name, ch.broker_name, BROKER_NAME_MAX) == 0)
	      {
		tla_trace ("TCasTry tok=%u", pair.first);
	      }
'''),
  ('''	      {
		binding = pair.second.binding;
		break;
	      }
	  }
      }
      token_body reply = { binding != nullptr ? 1u : 0u };
      if (binding != nullptr)
	{
	  wake_session (binding);
	}
''', '''	      {
		tla_trace ("TCasOk tok=%u", pair.first);
		binding = pair.second.binding;
		break;
	      }
	  }
	tla_trace ("TEnd rep=%d", binding != nullptr ? 1 : 0);
      }
      token_body reply = { binding != nullptr ? 1u : 0u };
      if (binding != nullptr)
	{
	  wake_session (binding);
	  tla_trace ("TWake");
	}
'''),
  ('''	  group->watch_requested.store (enabled);
	  if (!enabled)
	    {
	      return;
	    }
''', '''	  if (enabled)
	    {
	      tla_trace ("CStart op=w1");
	    }
	  group->watch_requested.store (enabled);
	  tla_trace (enabled ? "CW1" : "CStart op=w0");
	  if (!enabled)
	    {
	      return;
	    }
'''),
  ('''      catch (const std::bad_alloc &)
	{
	  return;		/* no hint: the dispatcher's wait ends at its deadline */
	}
      if (idle && group->watch_requested.exchange (false))
	{
''', '''      catch (const std::bad_alloc &)
	{
	  return;		/* no hint: the dispatcher's wait ends at its deadline */
	}
      tla_trace ("CWScan idle=%d", idle ? 1 : 0);
      if (idle)
	{
	  tla_trace ("CWX");
	}
      if (idle && group->watch_requested.exchange (false))
	{
'''),
  ('''      std::lock_guard<std::mutex> guard (m.registry_mutex);
      for (const auto &pair : m.registry)
	{
	  const std::shared_ptr<session_binding> &binding = pair.second.binding;
''', '''      std::lock_guard<std::mutex> guard (m.registry_mutex);
      tla_trace ("CStart op=reset");
      for (const auto &pair : m.registry)
	{
	  const std::shared_ptr<session_binding> &binding = pair.second.binding;
'''),
  ('''	  binding->reset_requested.store (true);
	  execution_state expected = execution_state::idle;
	  if (binding->state.compare_exchange_strong (expected, execution_state::yielded))
	    {
	      wake_session (binding);	/* registry -> binding is the lock order of registry_set_tran_index */
	    }
''', '''	  binding->reset_requested.store (true);
	  tla_trace ("RMark tok=%u", pair.first);
	  execution_state expected = execution_state::idle;
	  if (binding->state.compare_exchange_strong (expected, execution_state::yielded))
	    {
	      wake_session (binding);	/* registry -> binding is the lock order of registry_set_tran_index */
	    }
	  tla_trace ("RCas tok=%u", pair.first);
'''),
  ('''	    std::memcpy (owner_broker, it->second.broker_name, sizeof (owner_broker));
	    m->registry.erase (it);
''', '''	    std::memcpy (owner_broker, it->second.broker_name, sizeof (owner_broker));
	    m->registry.erase (it);
	    tla_trace ("Send tok=%u", token);
'''),
])

# ---------------------------------------------------------------- server: the CAS read path
edit("src/broker/cas_conn_helpers.c", [
  ('#include "adoption.hpp"\n', '''#include "adoption.hpp"
#include "tla_trace.h"
namespace cubconn { namespace adoption { unsigned tla_tok_get (void); } }
'''),
  ('''  if (!cubconn::adoption::registry_auto_begin_request ())
    {
      as_info->con_status = CON_STATUS_CLOSE_AND_CONNECT;
    }
''', '''  if (!cubconn::adoption::registry_auto_begin_request ())
    {
      as_info->con_status = CON_STATUS_CLOSE_AND_CONNECT;
    }
  tla_trace ("Rd tok=%u ret=%d ok=%d", cubconn::adoption::tla_tok_get (), ret_value,
	     as_info->con_status == CON_STATUS_CLOSE_AND_CONNECT ? 0 : 1);
'''),
])
edit("src/broker/cas_network.c", [
  ('#include "adoption.hpp"\n', '''#include "adoption.hpp"
#include "tla_trace.h"
namespace cubconn { namespace adoption { unsigned tla_tok_get (void); } }
'''),
  ('''	  if (!cubconn::adoption::registry_auto_is_yielded ())
	    {
	      goto retry_poll;
	    }
''', '''	  if (!cubconn::adoption::registry_auto_is_yielded ())
	    {
	      goto retry_poll;
	    }
	  tla_trace ("WakeSeen tok=%u", cubconn::adoption::tla_tok_get ());
'''),
])

# ---------------------------------------------------------------- server: the session thread
edit("src/connection/driver_session.cpp", [
  ('#include "driver_session.hpp"\n', '#include "driver_session.hpp"\n#include "tla_trace.h"\n'),
  ('''	      /* nothing of this connection outlives a detach here: the session may be yielded while it waits */
	      registry_auto_ready ();
	    }
	  fn_ret = cas_process_request (fd, &net_buf, &req_info, wake_fd);
''', '''	      /* nothing of this connection outlives a detach here: the session may be yielded while it waits */
	      registry_auto_ready ();
	    }
	  else if (wake_fd >= 0)
	    {
	      tla_trace ("Top tok=%u clean=0", tla_tok_get ());
	    }
	  fn_ret = cas_process_request (fd, &net_buf, &req_info, wake_fd);
	  if (wake_fd >= 0)
	    {
	      tla_trace ("Ret tok=%u keep=%d", tla_tok_get (), fn_ret == FN_KEEP_CONN ? 1 : 0);
	    }
'''),
  ('''    static void
    request_loop (int fd, int client_version''', '''    unsigned tla_tok_get (void);
    static void
    request_loop (int fd, int client_version'''),
  ('''						&kept);
''', '''						&kept);
	      tla_trace ("Claim tok=%u sid=%u res=%s", params.token, (unsigned) session_id,
			 err == NO_ERROR ? "ok" : err == ER_SES_SESSION_EXPIRED ? "expired"
			 : err == ER_SES_SESSION_SECRET_MISMATCH ? "secret" : "busy");
'''),
  ('''		  csc_activate (ctx);
		  adopted = true;
		  resumed = true;
''', '''		  csc_activate (ctx);
		  tla_trace ("Swap tok=%u", params.token);
		  adopted = true;
		  resumed = true;
'''),
  ('''	  err = boot_resume_client (&credential, info.db_passwd);
''', '''	  err = boot_resume_client (&credential, info.db_passwd);
	  tla_trace ("Auth tok=%u ok=%d", params.token, err == NO_ERROR ? 1 : 0);
'''),
  ('''	  err = db_restart_ex ("driver_session", info.db_name, info.db_user, info.db_passwd, NULL,
			       DB_CLIENT_TYPE_DEFAULT);
''', '''	  err = db_restart_ex ("driver_session", info.db_name, info.db_user, info.db_passwd, NULL,
			       DB_CLIENT_TYPE_DEFAULT);
	  if (params.keep_con_auto)
	    {
	      tla_trace ("Create tok=%u ok=%d sid=%u", params.token, err == NO_ERROR ? 1 : 0,
			 (unsigned) db_get_session_id ());
	    }
'''),
  ('''	  db_set_keep_session (yielded);
	  (void) ux_end_session ();
''', '''	  db_set_keep_session (yielded);
	  (void) ux_end_session ();
	  tla_trace ("End tok=%u", params.token);
'''),
  ('''	  session_rekeep_client_context (entry_p);
''', '''	  session_rekeep_client_context (entry_p);
	  tla_trace ("End tok=%u", params.token);
'''),
  ('''	  css_free_conn (conn);	/* decrements the conn-rule counter by client_type */
''', '''	  css_free_conn (conn);	/* decrements the conn-rule counter by client_type */
	  tla_trace ("Free tok=%u", params.token);
'''),
  ('''      csc_deactivate ();
      if (!adopted)
''', '''      csc_deactivate ();
      tla_trace ("Deact tok=%u", params.token);
      if (!adopted)
'''),
])

# ---------------------------------------------------------------- server: the session control daemon
edit("src/session/session.c", [
  ('#include "boot_sr.h"\n', '#include "boot_sr.h"\n#include "tla_trace.h"\n'),
  ('''	  if (is_expired)
	    {
	      /* Destroy this session after the iteration.''', '''	  if (is_expired)
	    {
	      tla_trace ("XScan sid=%u", (unsigned) state->id);
	      /* Destroy this session after the iteration.'''),
  ('''	      /* ended in the meantime */
''', '''	      /* ended in the meantime */
	      tla_trace ("XRecheck sid=%u exp=0", (unsigned) expired_sid_buffer[sid_index]);
'''),
  ('''	  if (!is_expired)
	    {
	      pthread_mutex_unlock (&state->mutex);
	      continue;
	    }
''', '''	  tla_trace ("XRecheck sid=%u exp=%d", (unsigned) expired_sid_buffer[sid_index], is_expired ? 1 : 0);
	  if (!is_expired)
	    {
	      pthread_mutex_unlock (&state->mutex);
	      continue;
	    }
'''),
  ('''	  (void) session_state_uninit (state);

	  if (!sessions.states_hashmap.erase_locked (thread_p, expired_sid_buffer[sid_index], state))
''', '''	  (void) session_state_uninit (state);
	  tla_trace ("XTear sid=%u", (unsigned) expired_sid_buffer[sid_index]);

	  if (!sessions.states_hashmap.erase_locked (thread_p, expired_sid_buffer[sid_index], state))
'''),
  ('''exit_on_end:
  if (active_sessions.session_ids != NULL)
    {
      assert (active_sessions.count > 0);
''', '''exit_on_end:
  tla_trace ("XEnd");
  if (active_sessions.session_ids != NULL)
    {
      assert (active_sessions.count > 0);
'''),
])
print("instrumented", W)
