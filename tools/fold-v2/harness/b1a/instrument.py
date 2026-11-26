# TLATRACE instrumentation for docs/tla/CBRD-27430-B1a (scratch worktree only).
# usage: python3 instrument.py <worktree>
# Every event is one line "TLATRACE <ns> <pid> <Action> k=v ..." appended to $CUBRID_TLATRACE_OUT by the broker
# and the server alike; <ns> is CLOCK_MONOTONIC, taken before a send for the events whose message the peer reads
# (so a receive never sorts before its send). tla_trace_events.py turns the merged log into a trace data module.
import sys
W = sys.argv[1]


def edit(path, pairs):
    p = f"{W}/{path}"
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (path, s.count(o), o[:120])
        s = s.replace(o, n)
    open(p, "w").write(s)


HDR = r'''/* scratch TLATRACE helper (CBRD-27430 B1a trace validation) */
#ifndef _TLA_TRACE_H_
#define _TLA_TRACE_H_
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
static inline long long
tla_now (void)
{
  struct timespec ts;
  clock_gettime (CLOCK_MONOTONIC, &ts);
  return (long long) ts.tv_sec * 1000000000LL + ts.tv_nsec;
}
static inline void
tla_trace_at (long long ns, const char *fmt, ...)
{
  const char *path = getenv ("CUBRID_TLATRACE_OUT");
  char buf[1024];
  int n;
  va_list ap;
  int fd;
  if (path == NULL || path[0] == '\0')
    {
      return;
    }
  n = snprintf (buf, sizeof (buf), "TLATRACE %lld %d ", ns, (int) getpid ());
  va_start (ap, fmt);
  n += vsnprintf (buf + n, sizeof (buf) - n - 1, fmt, ap);
  va_end (ap);
  buf[n++] = '\n';
  fd = open (path, O_WRONLY | O_APPEND | O_CREAT, 0644);
  if (fd >= 0)
    {
      (void) write (fd, buf, n);
      close (fd);
    }
}
#define tla_trace(...) tla_trace_at (tla_now (), __VA_ARGS__)
#endif
'''
open(f"{W}/src/base/tla_trace.h", "w").write(HDR)

# ---------------------------------------------------------------- broker
edit("src/broker/broker_direct.cpp", [
  ('#include <algorithm>\n', '#include <algorithm>\n#include "tla_trace.h"\n'),
  # reader: END
  ('''	if (it->second.channel_gen == ch.generation)
	  {
	    m.tokens.erase (it);
	    slots_add (m, -1);''', '''	if (it->second.channel_gen == ch.generation)
	  {
	    m.tokens.erase (it);
	    slots_add (m, -1);
	    tla_trace ("RRecv gen=%llu op=END tok=%u", (unsigned long long) ch.generation, token);'''),
  ('''    brd_debug ("session end db=%s: token=%u unknown", ch.db_name.c_str (), token);''',
   '''    brd_debug ("session end db=%s: token=%u unknown", ch.db_name.c_str (), token);
    tla_trace ("RRecv gen=%llu op=END tok=%u", (unsigned long long) ch.generation, token);'''),
  # drop
  ('''  static void
  tokens_drop_for_channel (manager &m, const channel &ch)
  {
    std::lock_guard<std::mutex> guard (m.tokens_mutex);''', '''  static void
  tokens_drop_for_channel (manager &m, const channel &ch)
  {
    std::lock_guard<std::mutex> guard (m.tokens_mutex);
    tla_trace ("RDrop gen=%llu", (unsigned long long) ch.generation);'''),
  # reader: replies, logged before the requester can see them
  ('''	/* request reply: hand to the waiting requester */
	{''', '''	{
	  const char *opn = "OTHER";
	  switch ((adopt::msg_op) header.op)
	    {
	    case adopt::msg_op::HELLO_ACK: opn = "HELLO_ACK"; break;
	    case adopt::msg_op::HANDOFF_ACK: opn = "ACK"; break;
	    case adopt::msg_op::HANDOFF_REJECT: opn = "REJECT"; break;
	    case adopt::msg_op::RESYNC_REPLY: opn = "RESYNC_REPLY"; break;
	    default: break;
	    }
	  unsigned int ttok = 0;
	  if ((adopt::msg_op) header.op == adopt::msg_op::HANDOFF_ACK)
	    {
	      std::memcpy (&ttok, body.data (), sizeof (ttok));
	    }
	  else if ((adopt::msg_op) header.op == adopt::msg_op::RESYNC_REPLY)
	    {
	      std::memcpy (&ttok, body.data (), sizeof (ttok));	/* live_count */
	    }
	  tla_trace ("RRecv gen=%llu op=%s tok=%u", (unsigned long long) ch->generation, opn, ttok);
	}
	/* request reply: hand to the waiting requester */
	{'''),
  # reader death
  ('''    ch->dead.store (true);
    ch->reply_cv.notify_all ();
    /* invalidate under send_mutex''', '''    long long tla_die = tla_now ();
    ch->dead.store (true);
    ch->reply_cv.notify_all ();
    tla_trace_at (tla_die, "RDie gen=%llu", (unsigned long long) ch->generation);
    /* invalidate under send_mutex'''),
  # timeout flag
  ('''	/* a late reply must never satisfy a LATER request on this channel:
	 * kill it — the next use redials (codex F5) */
	lock.unlock ();''', '''	/* a late reply must never satisfy a LATER request on this channel:
	 * kill it — the next use redials (codex F5) */
	tla_last_timeout = true;
	lock.unlock ();'''),
  ('''  static int
  channel_request (channel &ch,''', '''  static thread_local bool tla_last_timeout = false;
  static thread_local bool tla_in_cancel = false;
  static thread_local bool tla_looked = false;
  static int
  channel_request (channel &ch,'''),
  ('''    std::lock_guard<std::mutex> request_guard (ch.request_mutex);
''', '''    std::lock_guard<std::mutex> request_guard (ch.request_mutex);
    tla_last_timeout = false;
'''),
  # get or dial
  ('''      if (it != m.channels.end () && !it->second->dead.load ())
	{
	  return it->second;
	}
    }

    std::string path''', '''      if (it != m.channels.end () && !it->second->dead.load ())
	{
	  tla_trace ("DGetCh pub=%llu", (unsigned long long) it->second->generation);
	  return it->second;
	}
    }

    long long tla_dial = tla_now ();
    std::string path'''),
  ('''    if (connect (fd, (struct sockaddr *) &addr, sizeof (addr)) < 0)
      {
	close (fd);
	return NULL;
      }''', '''    if (connect (fd, (struct sockaddr *) &addr, sizeof (addr)) < 0)
      {
	close (fd);
	tla_trace_at (tla_dial, "DGetCh nosrv=1");
	return NULL;
      }
    tla_trace_at (tla_dial, "DGetCh dial=%llu", (unsigned long long) m.next_channel_gen);'''),
  ('''	|| reply_header.length != sizeof (hello_ack) || hello_ack.proto_version != adopt::PROTO_VERSION)
      {
	channel_kill (*ch);
	return NULL;
      }''', '''	|| reply_header.length != sizeof (hello_ack) || hello_ack.proto_version != adopt::PROTO_VERSION)
      {
	tla_trace ("DDialFail gen=%llu to=%d", (unsigned long long) ch->generation, tla_last_timeout ? 1 : 0);
	channel_kill (*ch);
	return NULL;
      }
    tla_trace ("DHello gen=%llu", (unsigned long long) ch->generation);'''),
  ('''	|| reply_header.length < sizeof (resync))
      {
	channel_kill (*ch);
	return NULL;
      }''', '''	|| reply_header.length < sizeof (resync))
      {
	tla_trace ("DDialFail gen=%llu to=%d", (unsigned long long) ch->generation, tla_last_timeout ? 1 : 0);
	channel_kill (*ch);
	return NULL;
      }'''),
  ('''    if (ch->dead.load ())
      {
	return NULL;	/* died after its reply: the reader already dropped it */
      }
    m.channels[db_name] = ch;''', '''    if (ch->dead.load ())
      {
	tla_trace ("DDialFail gen=%llu to=0", (unsigned long long) ch->generation);
	return NULL;	/* died after its reply: the reader already dropped it */
      }
    m.channels[db_name] = ch;
    tla_trace ("DResync gen=%llu", (unsigned long long) ch->generation);'''),
  # dispatch
  ('''  /* the channel first: its RESYNC may admit survivors of a broker restart,
   * and the admission below must count them */''', '''  tla_trace ("DStart");
  /* CUBRID_TLA_B1A_OLD_ADMIT=1: the old order (admission before the dial and its RESYNC), fail-before of H8 */
  const bool tla_old_admit = getenv ("CUBRID_TLA_B1A_OLD_ADMIT") != NULL;
  if (tla_old_admit)
    {
      std::unique_lock<std::mutex> guard (m->slots_mutex);
      bool ok = m->slots_cv.wait_for (guard, std::chrono::seconds (DB_INFO_PEEK_TIMEOUT_SEC),
				      [m] { return m->slots_used.load () < m->max_slots || m->stopping.load (); });
      tla_trace ("DAdmit ok=%d", ok ? 1 : 0);
    }
  /* the channel first: its RESYNC may admit survivors of a broker restart,
   * and the admission below must count them */'''),
  ('''  {
    std::unique_lock<std::mutex> guard (m->slots_mutex);
    if (!m->slots_cv.wait_for (guard, std::chrono::seconds (DB_INFO_PEEK_TIMEOUT_SEC),
			       [m] { return m->slots_used.load () < m->max_slots || m->stopping.load (); })
	|| m->stopping.load ())
      {
	guard.unlock ();''', '''  if (!tla_old_admit)
  {
    std::unique_lock<std::mutex> guard (m->slots_mutex);
    if (!m->slots_cv.wait_for (guard, std::chrono::seconds (DB_INFO_PEEK_TIMEOUT_SEC),
			       [m] { return m->slots_used.load () < m->max_slots || m->stopping.load (); })
	|| m->stopping.load ())
      {
	tla_trace ("DAdmit ok=0");
	guard.unlock ();'''),
  ('''  adopt::handoff_body body;
  std::memset (&body, 0, sizeof (body));
  std::memcpy (&body.client_ip, job->ip_addr, 4);''', '''  if (!tla_old_admit)
    {
      tla_trace ("DAdmit ok=1");
    }
  adopt::handoff_body body;
  std::memset (&body, 0, sizeof (body));
  std::memcpy (&body.client_ip, job->ip_addr, 4);'''),
  ('''  bool fd_transferred = false;
  if (channel_request (*ch, adopt::msg_op::HANDOFF,''', '''  bool fd_transferred = false;
  long long tla_send = tla_now ();
  int tla_rc = 0;
  if ((tla_rc = channel_request (*ch, adopt::msg_op::HANDOFF,'''),
  ('''		       &reply_header, reply_body, sizeof (reply_body), &fd_transferred) != 0)
    {
      brd_debug ("handoff db=%s: request failed/timeout", db_name);''', '''		       &reply_header, reply_body, sizeof (reply_body), &fd_transferred)) != 0 || true)
    {
      tla_trace_at (tla_send, "DSend gen=%llu ok=%d", (unsigned long long) ch->generation, fd_transferred ? 1 : 0);
    }
  if (tla_rc == 0)
    {
      tla_trace ("DWait op=%s", (adopt::msg_op) reply_header.op == adopt::msg_op::HANDOFF_ACK ? "ACK" : "REJECT");
    }
  else if (fd_transferred)
    {
      tla_trace ("DWait op=%s", tla_last_timeout ? "timeout" : "dead");
    }
  if (tla_rc != 0)
    {
      brd_debug ("handoff db=%s: request failed/timeout", db_name);'''),
  # cancel
  ('''	    found = it->second;
	    have = true;''', '''	    found = it->second;
	    have = true;
	    if (tla_in_cancel)
	      {
		tla_trace ("CnLook tok=%u gen=%llu", token, (unsigned long long) it->second.channel_gen);
		tla_looked = true;
	      }'''),
  ('''  std::shared_ptr<channel> ch = brd_token_channel (*m, token, clt_ip, clt_port);
  if (ch == NULL)
    {
      return -1;
    }
  adopt::token_body body;
  body.token = token;
  return channel_send (*ch, adopt::msg_op::CANCEL, &body, sizeof (body)) == 0 ? 0 : -1;''', '''  tla_in_cancel = true;
  tla_looked = false;
  std::shared_ptr<channel> ch = brd_token_channel (*m, token, clt_ip, clt_port);
  tla_in_cancel = false;
  if (ch == NULL)
    {
      if (tla_looked)
	{
	  tla_trace ("CnSend gen=0");
	}
      return -1;
    }
  adopt::token_body body;
  body.token = token;
  tla_trace ("CnSend gen=%llu", (unsigned long long) ch->generation);
  return channel_send (*ch, adopt::msg_op::CANCEL, &body, sizeof (body)) == 0 ? 0 : -1;'''),
])
edit("src/broker/broker.c", [
  ('''#include "broker_direct.h"
#endif''', '''#include "broker_direct.h"
#include "tla_trace.h"
#endif'''),
  ('''cleanup (int signo)
{
  signal (signo, SIG_IGN);
''', '''cleanup (int signo)
{
  signal (signo, SIG_IGN);
#if !defined(WINDOWS)
  tla_trace ("BRestart");
#endif
'''),
])

# ---------------------------------------------------------------- server
edit("src/connection/adoption.cpp", [
  ('#include "adoption.hpp"\n', '#include "adoption.hpp"\n#include "tla_trace.h"\n'),
  ('''	  it->second.binding->tran_index = tran_index;''', '''	  it->second.binding->tran_index = tran_index;
	  tla_trace ("SLogin tok=%u tran=%d", token, tran_index);'''),
  ('''	  binding->closing = true;
	  binding->drained.wait (guard, [&binding] { return binding->users == 0; });''', '''	  binding->closing = true;
	  if (!tla_undo)
	    {
	      tla_trace ("SEnd tok=%u", token);
	    }
	  binding->drained.wait (guard, [&binding] { return binding->users == 0; });
	  if (!tla_undo)
	    {
	      tla_trace ("SClean tok=%u", token);
	    }'''),
  ('''    static manager *adoption_Manager = NULL;
''', '''    static manager *adoption_Manager = NULL;
    static thread_local bool tla_undo = false;
'''),
  ('''	    m->registry.erase (it);
	    found = true;''', '''	    m->registry.erase (it);
	    found = true;
	    tla_trace ("SErase tok=%u", token);'''),
  ('''	    auto it = m->channels.find (latest->second);
	    if (it != m->channels.end ())
	      {
		ch = it->second;
	      }
	  }
      }''', '''	    auto it = m->channels.find (latest->second);
	    if (it != m->channels.end ())
	      {
		ch = it->second;
	      }
	  }
	tla_trace ("SPick tok=%u ch=%llu", token, ch != NULL ? (unsigned long long) ch->id : 0ULL);
      }'''),
  ('''	  token_body body;
	  body.token = token;
	  (void) send_message (*ch, msg_op::SESSION_END, &body, sizeof (body));
	}
      m->active_finishers.fetch_sub (1);''', '''	  token_body body;
	  body.token = token;
	  tla_trace ("SSendEnd tok=%u", token);
	  (void) send_message (*ch, msg_op::SESSION_END, &body, sizeof (body));
	}
      else
	{
	  tla_trace ("SSendEnd tok=%u", token);
	}
      m->active_finishers.fetch_sub (1);'''),
  # handoff check
  ('''      if (m.stopping.load ())
	{
	  reject.reason = (std::int32_t) reject_reason::SHUTDOWN;''', '''      if (m.stopping.load ())
	{
	  tla_trace ("SHCheck ch=%llu ok=0", (unsigned long long) ch.id);
	  reject.reason = (std::int32_t) reject_reason::SHUTDOWN;'''),
  ('''      if (css_increment_num_conn (DB_CLIENT_TYPE_DEFAULT) != NO_ERROR)
	{
	  er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE, ER_CSS_CLIENTS_EXCEEDED, 1, NUM_NORMAL_TRANS);''', '''      if (css_increment_num_conn (DB_CLIENT_TYPE_DEFAULT) != NO_ERROR)
	{
	  tla_trace ("SHCheck ch=%llu ok=0", (unsigned long long) ch.id);
	  er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE, ER_CSS_CLIENTS_EXCEEDED, 1, NUM_NORMAL_TRANS);'''),
  ('''      session_params params;
      params.client_fd = client_fd;
      params.slot_idx = body.slot_idx;''', '''      tla_trace ("SHCheck ch=%llu ok=1", (unsigned long long) ch.id);
      session_params params;
      params.client_fd = client_fd;
      params.slot_idx = body.slot_idx;'''),
  ('''	if (m.stopping.load ())
	  {
	    refused = true;
	  }''', '''	if (m.stopping.load ())
	  {
	    refused = true;
	    tla_trace ("SHReg ch=%llu refused=1", (unsigned long long) ch.id);
	  }'''),
  ('''	    m.registry.emplace (token, entry);''', '''	    m.registry.emplace (token, entry);
	    tla_trace ("SHReg ch=%llu tok=%u", (unsigned long long) ch.id, token);'''),
  ('''      if (send_message (ch, msg_op::HANDOFF_ACK, &ack, sizeof (ack)) == NO_ERROR)
	{''', '''      long long tla_ack = tla_now ();
      int tla_ack_rc = send_message (ch, msg_op::HANDOFF_ACK, &ack, sizeof (ack));
      tla_trace_at (tla_ack, "SHAck ch=%llu tok=%u ok=%d", (unsigned long long) ch.id, token, tla_ack_rc == NO_ERROR);
      if (tla_ack_rc == NO_ERROR)
	{'''),
  ('''	      std::thread session_thread (driver_session_run, std::move (params));
	      session_thread.detach ();''', '''	      long long tla_spawn = tla_now ();
	      std::thread session_thread (driver_session_run, std::move (params));
	      session_thread.detach ();
	      tla_trace_at (tla_spawn, "SHSpawn ch=%llu tok=%u", (unsigned long long) ch.id, token);'''),
  ('''      registry_begin_session_cleanup (token);
      css_decrement_num_conn (DB_CLIENT_TYPE_DEFAULT);
      registry_session_finished (token);
      close (client_fd);''', '''      tla_undo = true;
      registry_begin_session_cleanup (token);
      tla_undo = false;
      css_decrement_num_conn (DB_CLIENT_TYPE_DEFAULT);
      registry_session_finished (token);
      close (client_fd);
      tla_trace ("SClose tok=%u", token);'''),
  # cancel
  ('''      binding_pin pin (binding);
      if (pin.tran_index != NULL_TRAN_INDEX)
	{''', '''      binding_pin pin (binding);
      tla_trace ("CLook tok=%u found=%d tran=%d", body.token, binding != nullptr, pin.tran_index);
      if (pin.tran_index != NULL_TRAN_INDEX)
	{'''),
  ('''	  (void) logtb_set_tran_index_interrupt (NULL, pin.tran_index, true);
	}
    }

    static void
    handle_status''', '''	  (void) logtb_set_tran_index_interrupt (NULL, pin.tran_index, true);
	  tla_trace ("CInt tran=%d", pin.tran_index);
	}
    }

    static void
    handle_status'''),
  ('''      (void) send_message_locked (ch, msg_op::RESYNC_REPLY, buf.data (), buf.size ());''',
   '''      tla_trace ("SResync ch=%llu n=%u", (unsigned long long) ch.id, live_count);
      (void) send_message_locked (ch, msg_op::RESYNC_REPLY, buf.data (), buf.size ());'''),
  # recv
  ('''	  switch ((msg_op) header.op)
	    {
	    case msg_op::HELLO:''', '''	  {
	    const char *opn = "OTHER";
	    switch ((msg_op) header.op)
	      {
	      case msg_op::HELLO: opn = "HELLO"; break;
	      case msg_op::HANDOFF: opn = "HANDOFF"; break;
	      case msg_op::CANCEL: opn = "CANCEL"; break;
	      case msg_op::RESYNC: opn = "RESYNC"; break;
	      default: break;
	      }
	    tla_trace ("SRecv ch=%llu op=%s", (unsigned long long) ch->id, opn);
	  }
	  switch ((msg_op) header.op)
	    {
	    case msg_op::HELLO:'''),
  ('''      {
	std::lock_guard<std::mutex> guard (ch->send_mutex);
	close (ch->fd);
	ch->fd = -1;
      }
      ch->dead.store (true);''', '''      {
	std::lock_guard<std::mutex> guard (ch->send_mutex);
	close (ch->fd);
	ch->fd = -1;
	tla_trace ("SEof ch=%llu", (unsigned long long) ch->id);
      }
      ch->dead.store (true);'''),
  ('''		ch->id = m->next_channel_id++;
		m->channels.emplace (ch->id, ch);''', '''		ch->id = m->next_channel_id++;
		m->channels.emplace (ch->id, ch);
		tla_trace ("SAccept ch=%llu", (unsigned long long) ch->id);'''),
  # stop
  ('''      m->stopping.store (true);

      /* wake the accept thread */''', '''      tla_trace ("StopBegin");
      m->stopping.store (true);

      /* wake the accept thread */'''),
  ('''      /* wake the control-channel readers; their (joinable) threads mark''', '''      tla_trace ("StopShutCh");
      /* wake the control-channel readers; their (joinable) threads mark'''),
  ('''	drained = m->registry_cv.wait_for (lock, std::chrono::seconds (wait_secs),
					   [m] { return m->registry.empty (); });''', '''	drained = m->registry_cv.wait_for (lock, std::chrono::seconds (wait_secs),
					   [m] { return m->registry.empty (); });
	tla_trace ("StopDrain ok=%d", drained ? 1 : 0);'''),
  ('''      while (m->active_finishers.load () > 0)
	{
	  std::this_thread::sleep_for (std::chrono::milliseconds (10));
	}
''', '''      while (m->active_finishers.load () > 0)
	{
	  std::this_thread::sleep_for (std::chrono::milliseconds (10));
	}
      tla_trace ("StopFinWait");
'''),
  ('''      channels.clear ();
''', '''      channels.clear ();
      tla_trace ("StopJoin");
'''),
  ('''      unlink (m->socket_path.c_str ());
      adoption_Manager = NULL;
      delete m;
    }''', '''      unlink (m->socket_path.c_str ());
      tla_trace ("StopFree");
      adoption_Manager = NULL;
      delete m;
    }'''),
  ('''	std::unique_lock<std::mutex> lock (m->registry_mutex);
	for (auto &pair : m->registry)
	  {
	    binding_pin pin (pair.second.binding);''', '''	std::unique_lock<std::mutex> lock (m->registry_mutex);
	tla_trace ("StopShutSess");
	for (auto &pair : m->registry)
	  {
	    binding_pin pin (pair.second.binding);'''),
])
edit("src/connection/driver_session.cpp", [
  ('#include "driver_session.hpp"\n', '#include "driver_session.hpp"\n#include "tla_trace.h"\n'),
  ('''      registry_session_finished (params.token);
      close (params.client_fd);
    }''', '''      registry_session_finished (params.token);
      close (params.client_fd);
      tla_trace ("SClose tok=%u", params.token);
    }'''),
])
print("instrumented", W)
