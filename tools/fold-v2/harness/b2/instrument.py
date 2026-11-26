# TLATRACE instrumentation for docs/tla/CBRD-27430-B2 (scratch worktree only; adds lines only).
# usage: python3 instrument.py <worktree>
# Every process appends "TLATRACE <ns> <pid> <tid> <Action> k=v ..." to $CUBRID_TLATRACE_OUT; events.py splits the
# file into one log per model (ConfigPush, AclTable, LogLease, StatsKill, SslAck).
import sys
W = sys.argv[1]

HDR = r'''/* scratch TLATRACE helper (CBRD-27430 B2 trace validation) */
#ifndef _TLA_TRACE_H_
#define _TLA_TRACE_H_
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>
static inline void
tla_trace (const char *fmt, ...)
{
  const char *path = getenv ("CUBRID_TLATRACE_OUT");
  char buf[1024];
  int n;
  va_list ap;
  int fd;
  struct timespec ts;
  if (path == NULL || path[0] == '\0')
    {
      return;
    }
  clock_gettime (CLOCK_MONOTONIC, &ts);
  n = snprintf (buf, sizeof (buf), "TLATRACE %lld %d %ld ", (long long) ts.tv_sec * 1000000000LL + ts.tv_nsec,
		(int) getpid (), (long) syscall (SYS_gettid));
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
#endif
'''
open(f"{W}/src/base/tla_trace.h", "w").write(HDR)


FAILED = []


def edit(path, pairs):
    p = f"{W}/{path}"
    s = open(p).read()
    bad = 0
    for o, n in pairs:
        if s.count(o) != 1:
            print("ANCHOR", path, s.count(o), repr(o[:160]))
            bad += 1
            continue
        assert o in n, (path, "not additive", o[:80])
        s = s.replace(o, n)
    if bad:
        FAILED.append(path)
    else:
        open(p, "w").write(s)


def after(o, add):
    return (o, o + add)


def before(o, add):
    return (o, add + o)


# ---------------------------------------------------------------- broker
edit("src/broker/broker_direct.cpp", [
  after('#include "broker_direct.h"\n', '#include "tla_trace.h"\n'),
  after('  m->ssl_db = ssl_db;\n', '  tla_trace ("BInit");\n'),
  after('    config.long_query_time = shm->long_query_time;\n',
        '    tla_trace ("Snap seq=%llu v=%d", (unsigned long long) config.seq, (int) config.long_query_time);\n'),
  before('	    std::int32_t result = control_broadcast (*m, op);\n',
         '	    if (op == BRD_CONTROL_CONFIG)\n	      {\n		tla_trace ("CStart");\n	      }\n'),
  before('    adopt::session_config config;\n    config_snapshot (m, config);\n',
         '    if (op == BRD_CONTROL_CONFIG)\n      {\n	tla_trace ("CDial n=%d", (int) targets.size ());\n      }\n'),
  before('	adopt::msg_header header;\n	adopt::session_change_reply reply = { 0 };\n', '	tla_trace ("CSend");\n'),
  after('	    || (adopt::msg_op) header.op != adopt::msg_op::SESSION_CONFIG_REPLY || header.length != sizeof (reply))\n	  {\n',
        '	    tla_trace ("CTimeout");\n'),
  after('	affected += reply.affected;\n', '	tla_trace ("CReply");\n'),
  before('    return incomplete ? -1 : affected;\n',
         '    if (op == BRD_CONTROL_CONFIG)\n      {\n	tla_trace ("CDone ok=%d", incomplete ? 0 : 1);\n      }\n'),
  # the SSL park, the cleartext park (after its ack), the peek's end
  before('      parked_client *ssl_pc = new parked_client ();\n',
         '      tla_trace ("BPark cp=%d ssl=1", (int) job->port);\n'),
  before('  int flags = fcntl (clt_sock_fd, F_GETFL, 0);\n', '  tla_trace ("BPark cp=%d ssl=0", (int) job->port);\n'),
  after('  park_drop (manager &m, parked_client *pc)\n  {\n', '    tla_trace ("BPeekTimeout cp=%d", (int) pc->job.port);\n'),
  after('''  park_complete (manager &m, parked_client *pc)
  {
''', '    tla_trace ("BPeeked cp=%d", (int) pc->job.port);\n'),
  # the dispatch job
  after('''brd_dispatch_job (T_MAX_HEAP_NODE * job)
{
  manager *m = brd_Manager;
  if (m == NULL)
    {
      return;
    }
''', '  tla_trace ("BDequeue cp=%d ssl=%d", (int) job->port, IS_SSL_CLIENT (job->driver_info) ? 1 : 0);\n'),
  after('''  std::shared_ptr<channel> ch = channel_get_or_dial (*m, db_name);
''', '  tla_trace ("BDial cp=%d up=%d", (int) job->port, ch == NULL ? 0 : 1);\n'),
  after('''	     m->slots_used.load (), m->max_slots);
  if (!brd_wait_for_slot (*m))
    {
''', '      tla_trace ("BSlot cp=%d got=0", (int) job->port);\n'),
  before('  adopt::handoff_body body;\n  std::memset (&body, 0, sizeof (body));\n',
         '  tla_trace ("BSlot cp=%d got=1", (int) job->port);\n  tla_trace ("DStart cp=%d", (int) job->port);\n'),
  before('  adopt::msg_header reply_header;\n  char reply_body[64];\n  bool fd_transferred = false;\n',
         '  tla_trace ("DSend cp=%d", (int) job->port);\n'),
  after('''  if (handoff_result != 0)
    {
''', '      tla_trace ("DTimeout cp=%d sent=%d", (int) job->port, fd_transferred ? 1 : 0);\n'),
  after('''      && reply_header.length == sizeof (adopt::resync_token_body))
    {
''', '      tla_trace ("DReply cp=%d ack=1", (int) job->port);\n'),
  before('''  send_error_code_to_driver (job->clt_sock_fd, CAS_ER_FREE_SERVER, job->driver_info);
  close (job->clt_sock_fd);
}
''', '  tla_trace ("DReply cp=%d ack=0", (int) job->port);\n'),
])

edit("src/broker/broker_admin_pub.c", [
  after('#include <stdio.h>\n', '#include "tla_trace.h"\n'),
  after('''  struct timeval timeout = { 60, 0 };
  int fd, result = -1;
''', '''  if (op == BRD_CONTROL_CONFIG)
    {
      tla_trace ("AChange");
    }
'''),
])

# ---------------------------------------------------------------- server: the registry
edit("src/connection/adoption.cpp", [
  after('#include "adoption.hpp"\n', '#include "tla_trace.h"\n'),
  after('	    m.registry.emplace (token, entry);\n',
        '	    tla_trace ("SHandoff b=%p cp=%d fd=%d mseq=%llu seq=%llu v=%d", (void *) binding.get (), (int) body.client_port,\n'
        '		       client_fd, (unsigned long long) body.config.seq, (unsigned long long) binding->config.seq,\n'
        '		       (int) binding->config.long_query_time);\n'),
  after('''      if (refused)
	{
''', '	  tla_trace ("SRefuse cp=%d", (int) body.client_port);\n'),
  after('''	  if (config.seq > latest.seq)
	    {
	      latest = config;
	    }
''', '	  tla_trace ("SCfgBegin seq=%llu v=%d", (unsigned long long) config.seq, (int) config.long_query_time);\n'),
  after('''		if (config.seq <= binding.config.seq)
		  {
''', '		    tla_trace ("SWrite b=%p take=0", (void *) &binding);\n'),
  after('		binding.config = config;\n', '		tla_trace ("SWrite b=%p take=1", (void *) &binding);\n'),
  ('''	      binding.config_changed.store (true);
	    }
''', '''	      binding.config_changed.store (true);
	      tla_trace ("SFlag b=%p", (void *) &binding);
	    }
	  tla_trace ("SCfgEnd seq=%llu", (unsigned long long) config.seq);
'''),
  after('''      if (current_session == nullptr || !current_session->config_changed.exchange (false))
	{
	  return false;
	}
''', '      tla_trace ("TClear b=%p", (void *) current_session.get ());\n'),
  after('      config = current_session->config;\n',
        '      tla_trace ("TRead b=%p seq=%llu v=%d", (void *) current_session.get (), (unsigned long long) config.seq,\n'
        '		 (int) config.long_query_time);\n'),
  before('	    m->registry.erase (it);\n', '	    tla_trace ("SErase b=%p", (void *) it->second.binding.get ());\n'),
  after('	  binding->closing = true;\n', '	  tla_trace ("SCleanup b=%p", (void *) binding.get ());\n'),
  after('''	  binding->client_fd = -1;
	  binding->wake_fd = -1;
''', '	  tla_trace ("SDrain b=%p", (void *) binding.get ());\n'),
  after('	  current_session->stats_published = true;\n',
        '	  tla_trace ("SPublish b=%p req=%d q=%d", (void *) current_session.get (), (int) row.num_requests,\n'
        '		     (int) row.num_queries);\n'),
  after('	      rows[count++] = binding.stats;\n',
        '	      tla_trace ("RRow b=%p req=%d q=%d", (void *) &binding, (int) binding.stats.num_requests,\n'
        '			 (int) binding.stats.num_queries);\n'),
  before('      return count;\n    }\n\n    bool\n    registry_shutdown_session (int tran_index)\n', '      tla_trace ("REnd");\n'),
  after('''	      /* the read side only: a statement the kill interrupted still sends its error to the driver */
''', '	      tla_trace ("KPin b=%p fd=%d", (void *) pair.second.binding.get (), pin.client_fd);\n'),
  after('	      shutdown (pin.client_fd, SHUT_RD);\n', '	      tla_trace ("KShut fd=%d", pin.client_fd);\n	      tla_trace ("KEnd");\n'),
])
# the two scans begin under registry_mutex: the lock line is not unique, so each is placed by its loop
p = f"{W}/src/connection/adoption.cpp"
s = open(p).read()
o = '''      std::lock_guard<std::mutex> guard (m->registry_mutex);
      for (const auto &pair : m->registry)
	{
	  if (count >= max_rows)
'''
assert s.count(o) == 1
s = s.replace(o, o.replace('      for (const auto &pair : m->registry)\n', '      tla_trace ("RBegin");\n      for (const auto &pair : m->registry)\n'))
o = '''      std::lock_guard<std::mutex> guard (m->registry_mutex);
      for (const auto &pair : m->registry)
	{
	  /* the pin holds the session's cleanup back: the descriptor is still the session's connection */
'''
assert s.count(o) == 1
s = s.replace(o, o.replace('      for (const auto &pair : m->registry)\n', '      tla_trace ("KBegin tran=%d", tran_index);\n      for (const auto &pair : m->registry)\n'))
o = '''	      return true;
	    }
	}
      return false;
    }

    static void
    wake_session ('''
assert s.count(o) == 1
s = s.replace(o, o.replace('      return false;\n', '      tla_trace ("KEnd");\n      return false;\n'))
open(p, "w").write(s)

# ---------------------------------------------------------------- server: the session thread
edit("src/connection/driver_session.cpp", [
  after('#include "driver_session.hpp"\n', '#include "tla_trace.h"\n'),
  after('      const bool is_ssl = IS_SSL_CLIENT (params.driver_header);\n',
        '      tla_trace ("SThread cp=%d ssl=%d", (int) params.client_port, is_ssl ? 1 : 0);\n'),
  after('      cas_slow_log_open (broker_name);\n', '      tla_trace ("LOpen");\n'),
  after('''	  cas_log_close (true);
	  cas_slow_log_close ();
	}
      cas_server_session_slot_end ();
''', '      tla_trace ("LDone");\n'),
  after('''	  logddl_destroy ();
	  cas_log_close (true);
	  cas_slow_log_close ();
''', '	  tla_trace ("LClose");\n'),
  before('''      close (params.client_fd);
    }
  }				/* namespace adoption */
''', '      tla_trace ("SClose fd=%d", params.client_fd);\n'),
])

edit("src/broker/cas_dispatch.c", [
  after('#include <stdio.h>\n', '#include "tla_trace.h"\n'),
  after('  func_code_unknown = (func_code >= CAS_FC_MAX);\n', '  tla_trace ("SReqA fc=%d", func_code);\n'),
  after('exit_on_end:\n', '  tla_trace ("SReqB");\n'),
])

# ---------------------------------------------------------------- server: the log lease and the access control table
edit("src/broker/cas_server_support.cpp", [
  after('#include <signal.h>\n', '#include "tla_trace.h"\n'),
  after('''  assert (cas_Log_lease_fd < 0);
''', '  tla_trace ("LBegin");\n'),
  after('''      if (result == 0)
	{
''', '	  tla_trace ("LTry idx=%d got=1", index + 1);\n'),
  after('''      const int lock_errno = errno;
      close (fd);
''', '      tla_trace ("LTry idx=%d got=0", index + 1);\n'),
  after('''      if (cas_Log_lease_fd >= 0)
	{
''', '	  tla_trace ("LRelease");\n'),
  after('  std::lock_guard<std::mutex> load_guard (cas_Acl_load_mutex);\n', '  tla_trace ("LStart");\n'),
  before('  std::lock_guard<std::mutex> guard (cas_Acl_mutex);\n  if (ok)\n',
         '  int tla_n = 0;\n  for (const auto &tla_pair : table)\n    {\n      tla_n += (int) tla_pair.second.size ();\n    }\n'
         '  tla_trace ("LParse ok=%d n=%d", ok ? 1 : 0, tla_n);\n'),
  after('''  cas_Acl_load_failed = !ok;
  cas_Acl_loaded = true;
''', '  tla_trace ("LSwap ok=%d n=%d", ok ? 1 : 0, ok ? tla_n : 0);\n'),
  before('''  if (cas_Acl_load_failed)
    {
      return -1;
    }

  auto it = cas_Acl_table.find (section);
''', '''  {
    int tla_c = 0;
    for (const auto &tla_pair : cas_Acl_table)
      {
	tla_c += (int) tla_pair.second.size ();
      }
    tla_trace ("CCheck failed=%d n=%d", cas_Acl_load_failed ? 1 : 0, tla_c);
  }
'''),
])
print("instrumented" if not FAILED else "FAILED %s" % FAILED)
