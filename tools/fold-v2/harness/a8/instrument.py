# TLATRACE instrumentation + AREA failure injection for docs/tla/CBRD-27430-A8 (scratch worktree only).
# usage: python3 instrument.py <worktree>
# Injection (env, read per allocation):
#   CUBRID_TLA_A8_HAT=client|server|dispatch   the half of the tracer thread whose allocations fail
#   CUBRID_TLA_A8_SKIP=n    matching allocations to let through first (default 0)
#   CUBRID_TLA_A8_COUNT=k   allocations to fail (default 1); after the first, any allocation inside the abort fails too
#   CUBRID_TLA_A8_AREA=name only this AREA (area->name), any if unset
#   CUBRID_TLA_A8_WORKER=1  fail instead the first matching allocation of a worker thread with no bracket
#   CUBRID_TLA_A8_OLD_GATE=1  the old A8 decision (any bracket aborts): fail-before of the server-half hole
#   CUBRID_TLA_A8_NULL_GATE=1 no abort at all (the server before A8): fail-before of C2
# Events (p = tracer session id, 99 = the worker): Fail h=, AbortFail, Gate go=, Guard, AbortEffect h=, Ret h= e=,
# Enter, Exit (db_on_server 0<->1 outside a dispatch and outside the abort), DispatchIn, DispatchOut (libcas depth 0<->1).
import sys
W = sys.argv[1]


def edit(path, pairs):
    p = f"{W}/{path}"
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (path, s.count(o), o[:100])
        s = s.replace(o, n)
    open(p, "w").write(s)


DECL = '''#include "client_session_context.hpp"
#include <atomic>
#if defined (SERVER_MODE)
extern std::atomic<bool> tla_a8_worker_arm;
extern thread_local int tla_role;
extern thread_local bool tla_a8_armed;
extern thread_local bool tla_a8_in_abort;
extern const char *tla_a8_hat (void);
extern void tla_trace (const char *fmt, ...);
#else
static thread_local int tla_role = 0;
static thread_local bool tla_a8_armed = false;
static thread_local bool tla_a8_in_abort = false;
static inline const char *tla_a8_hat (void) { return "client"; }
static inline void tla_trace (const char *, ...) {}
#endif
'''
LAST = '''// XXX: SHOULD BE THE LAST INCLUDE HEADER
#include "memory_wrapper.hpp"
'''

edit("src/object/client_session_context.cpp", [
  ('''static thread_local client_session_context *tl_Csc_active = NULL;
''', '''static thread_local client_session_context *tl_Csc_active = NULL;

#include <cstdarg>
#include <cstdio>

thread_local int tla_role = 0;
thread_local bool tla_a8_armed = false;
thread_local bool tla_a8_in_abort = false;
std::atomic<bool> tla_a8_worker_arm (false);
static std::mutex tla_Mutex;
static FILE *tla_Fp = NULL;
static unsigned long tla_Seq = 0;
extern thread_local unsigned int db_on_server;

const char *
tla_a8_hat (void)
{
  return db_on_server > 0 ? "server" : (tl_Csc_active != NULL && tl_Csc_active->tm.libcas_depth > 0) ? "dispatch" : "client";
}

void
tla_trace (const char *fmt, ...)
{
  std::lock_guard<std::mutex> guard (tla_Mutex);
  if (tla_Fp == NULL)
    {
      const char *path = getenv ("CUBRID_TLATRACE_OUT");
      if (path == NULL || (tla_Fp = fopen (path, "w")) == NULL)
	{
	  return;
	}
    }
  va_list ap;
  fprintf (tla_Fp, "TLATRACE seq=%lu ", ++tla_Seq);
  va_start (ap, fmt);
  vfprintf (tla_Fp, fmt, ap);
  va_end (ap);
  fputc ('\\n', tla_Fp);
  fflush (tla_Fp);
}
'''),
])

# the tracer thread: role, armed from the case's compile to its commit
edit("src/transaction/server_compile_tracer.cpp", [
  ("""  ctx = new client_session_context ();
  csc_activate (ctx);
""", """  ctx = new client_session_context ();
  tla_role = sid;
  csc_activate (ctx);
"""),
  ("""    int stmt_id = db_compile_statement (session);
    if (stmt_id < 0)""", """    tla_a8_armed = true;
    int stmt_id = db_compile_statement (session);
    if (stmt_id < 0)"""),
  ("""  csc_deactivate ();
""", """  tla_a8_armed = false;
  tla_a8_worker_arm = true;
  csc_deactivate ();
"""),
  (LAST, DECL + LAST),
])

# injection: the slow path of area_alloc failing its malloc (lock, er_set, unlock, callback, NULL)
edit("src/base/area_alloc.c", [
  ("""static AREA_BLOCK *area_find_block (AREA * area, const void *ptr);
""", """static AREA_BLOCK *area_find_block (AREA * area, const void *ptr);

#if defined (SERVER_MODE)
#include "client_session_context.hpp"
#include <atomic>
extern thread_local int tla_role;
extern thread_local bool tla_a8_armed;
extern thread_local bool tla_a8_in_abort;
extern const char *tla_a8_hat (void);
extern void tla_trace (const char *fmt, ...);
static thread_local int tla_a8_skip = -1;
static thread_local int tla_a8_left = -1;
static std::atomic<int> tla_a8_worker_done (0);
extern std::atomic<bool> tla_a8_worker_arm;

/* 1 = fail this allocation on the traced tracer thread, 2 = on the worker */
static int
tla_a8_should_fail (AREA * area)
{
  const char *only = getenv ("CUBRID_TLA_A8_AREA");
  if (only != NULL && strcmp (only, area->name) != 0)
    {
      return 0;
    }
  if (getenv ("CUBRID_TLA_A8_WORKER") != NULL)
    {
      /* a thread with no bracket: run with CUBRID_TLA_A8_AREA naming an AREA only a CS request's query uses */
      if (!csc_bracket_is_active () && tla_a8_worker_arm && tla_a8_worker_done.exchange (1) == 0)
	{
	  return 2;
	}
      return 0;
    }
  if (tla_role == 0 || !tla_a8_armed)
    {
      return 0;
    }
  if (tla_a8_left < 0)
    {
      const char *s = getenv ("CUBRID_TLA_A8_SKIP");
      const char *c = getenv ("CUBRID_TLA_A8_COUNT");
      tla_a8_skip = s != NULL ? atoi (s) : 0;
      tla_a8_left = c != NULL ? atoi (c) : 1;
    }
  if (tla_a8_left == 0)
    {
      return 0;
    }
  if (!tla_a8_in_abort)
    {
      const char *hat = getenv ("CUBRID_TLA_A8_HAT");
      if (hat == NULL || strcmp (hat, tla_a8_hat ()) != 0)
	{
	  return 0;
	}
      if (tla_a8_skip > 0)
	{
	  tla_a8_skip--;
	  return 0;
	}
    }
  tla_a8_left--;
  return 1;
}
#endif
"""),
  ("""  assert (area != NULL);

  /* Step 1: find a free entry from the hint block */
""", """  assert (area != NULL);

#if defined (SERVER_MODE)
  int tla_fail = tla_a8_should_fail (area);
  if (tla_fail != 0)
    {
      const int tla_save_role = tla_role;
      if (tla_fail == 2)
	{
	  tla_role = 99;
	}
      const bool tla_inner = tla_a8_in_abort;
      pthread_mutex_lock (&area->area_mutex);
      er_set (ER_ERROR_SEVERITY, ARG_FILE_LINE, ER_OUT_OF_VIRTUAL_MEMORY, 1, area->block_size);
      pthread_mutex_unlock (&area->area_mutex);
      if (tla_inner)
	{
	  tla_trace ("a=AbortFail p=%d", tla_role);
	}
      else
	{
	  tla_trace ("a=Fail p=%d h=%s", tla_role, tla_a8_hat ());
	}
      area_call_failure_function (area);
      if (!tla_inner)
	{
	  tla_trace ("a=Ret p=%d h=%s e=%s", tla_role, tla_a8_hat (),
		     er_errid () == ER_LK_UNILATERALLY_ABORTED ? "unilat" : "oom");
	}
      tla_role = tla_save_role;
      return NULL;
    }
#endif

  /* Step 1: find a free entry from the hint block */
"""),
])

edit("src/object/work_space.c", [
  ("""  static thread_local bool ws_abort_in_progress = false;

#if defined (SERVER_MODE)
""", """  static thread_local bool ws_abort_in_progress = false;
  const bool tla_inner = tla_a8_in_abort;
  if (tla_role != 0 && tla_inner)
    {
      tla_trace ("a=Guard p=%d", tla_role);
    }

#if defined (SERVER_MODE)
"""),
  ("""  if (!csc_bracket_is_active () || tm_Tran_index == NULL_TRAN_INDEX || db_on_server != 0)
    {
      return;
    }""", """  if (getenv ("CUBRID_TLA_A8_NULL_GATE") != NULL || !csc_bracket_is_active () || (getenv ("CUBRID_TLA_A8_OLD_GATE") == NULL
				       && (tm_Tran_index == NULL_TRAN_INDEX || db_on_server != 0)))
    {
      if (tla_role != 0 && !tla_inner)
	{
	  tla_trace ("a=Gate p=%d go=0", tla_role);
	}
      return;
    }"""),
  ("""  ws_abort_in_progress = true;
""", """  ws_abort_in_progress = true;
  tla_a8_in_abort = true;
  if (tla_role != 0)
    {
      tla_trace ("a=Gate p=%d go=1", tla_role);
    }
"""),
  ("""      (void) tran_unilaterally_abort ();
""", """      (void) tran_unilaterally_abort ();
      if (tla_role != 0)
	{
	  tla_trace ("a=AbortEffect p=%d h=%s", tla_role, tla_a8_hat ());
	}
"""),
  ("""  ws_abort_in_progress = false;
}""", """  ws_abort_in_progress = false;
  tla_a8_in_abort = false;
}"""),
  (LAST, DECL + LAST),
])

edit("src/communication/network_interface_cl.c", [
  ("""  db_on_server++;
  er_stack_push_if_exists ();
""", """  db_on_server++;
  if (db_on_server == 1 && tla_role != 0 && tla_a8_armed && !tla_a8_in_abort && !csc_in_method_dispatch ())
    {
      tla_trace ("a=Enter p=%d", tla_role);
    }
  er_stack_push_if_exists ();
"""),
  ("""  er_restore_last_error ();
  db_on_server--;
""", """  er_restore_last_error ();
  if (db_on_server == 1 && tla_role != 0 && tla_a8_armed && !tla_a8_in_abort && !csc_in_method_dispatch ())
    {
      tla_trace ("a=Exit p=%d", tla_role);
    }
  db_on_server--;
"""),
  (LAST, DECL + LAST),
])

edit("src/method/query_method.cpp", [
  ("""  csc->er_dispatch_floor = er_stack_depth ();

  tran_begin_libcas_function ();
  int depth = tran_get_libcas_depth ();
""", """  csc->er_dispatch_floor = er_stack_depth ();

  tran_begin_libcas_function ();
  int depth = tran_get_libcas_depth ();
  if (depth == 1 && tla_role != 0 && tla_a8_armed && !tla_a8_in_abort)
    {
      tla_trace ("a=DispatchIn p=%d", tla_role);
    }
"""),
  ("""  tran_end_libcas_function ();

  /* the outermost exit""", """  tran_end_libcas_function ();
  if (!tran_is_in_libcas () && tla_role != 0 && tla_a8_armed && !tla_a8_in_abort)
    {
      tla_trace ("a=DispatchOut p=%d", tla_role);
    }

  /* the outermost exit"""),
  (LAST, DECL + LAST),
])
print("instrumented", W)
