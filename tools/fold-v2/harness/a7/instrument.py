# TLATRACE instrumentation of the A7 dispatch for docs/tla/CBRD-27430-A7 (scratch worktree only).
# usage: python3 instrument.py <worktree>
# Events (tracer threads only, p = session id): Call (method_dispatch entered; deep=1 refused), Query1/Query2 (a
# query nested in a dispatch starts / ends in qmgr_process_query), Commit (a transaction end inside a dispatch),
# Exit (method_dispatch returns; drain=1 freed deferred handles). The A4 lifecycle is not logged (hidden steps).
import sys
W = sys.argv[1]


def edit(path, pairs):
    p = f"{W}/{path}"
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (path, s.count(o), o[:100])
        s = s.replace(o, n)
    open(p, "w").write(s)


DECL = '''#if defined (SERVER_MODE)
extern thread_local int tla_role;
extern void tla_trace (const char *fmt, ...);
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
static std::mutex tla_Mutex;
static FILE *tla_Fp = NULL;
static unsigned long tla_Seq = 0;

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

edit("src/transaction/server_compile_tracer.cpp", [
  ("""  ctx = new client_session_context ();
  csc_activate (ctx);
""", """  ctx = new client_session_context ();
  tla_role = sid;
  csc_activate (ctx);
"""),
  (LAST, DECL + LAST),
])

edit("src/method/query_method.cpp", [
  ("""  if (error == NO_ERROR)
    {
      error = method_dispatch_internal (unpacker);
    }

  tran_end_libcas_function ();

  /* the outermost exit""", """  if (tla_role != 0)
    {
      tla_trace ("a=Call p=%d deep=%d", tla_role, error != NO_ERROR ? 1 : 0);
    }

  if (error == NO_ERROR)
    {
      error = method_dispatch_internal (unpacker);
    }

  tran_end_libcas_function ();
  int tla_drain = 0;

  /* the outermost exit"""),
  ("""	  er_stack_push ();
	  h->free_deferred_query_handler ();
	  er_stack_pop ();""", """	  er_stack_push ();
	  h->free_deferred_query_handler ();
	  er_stack_pop ();
	  tla_drain = 1;"""),
  ("""  db_on_server = save_on_server;
  return error;
}

/* csc_teardown""", """  db_on_server = save_on_server;
  if (tla_role != 0)
    {
      tla_trace ("a=Exit p=%d drain=%d", tla_role, tla_drain);
    }
  return error;
}

/* csc_teardown"""),
  (LAST, DECL + LAST),
])

edit("src/query/query_manager.c", [
  ("""  XASL_UNPACK_INFO *outer_unpack_info = get_xasl_unpack_info_ptr (thread_p);
  QFILE_LIST_ID *list_id;
""", """  XASL_UNPACK_INFO *outer_unpack_info = get_xasl_unpack_info_ptr (thread_p);
  QFILE_LIST_ID *list_id;
#if defined (SERVER_MODE)
  const bool tla_nested = tla_role != 0 && csc_in_method_dispatch ();
#else
  const bool tla_nested = false;
#endif
#if defined (SERVER_MODE)
  if (tla_nested)
    {
      tla_trace ("a=Query1 p=%d", tla_role);
    }
#endif
"""),
  ("""  set_xasl_unpack_info_ptr (thread_p, outer_unpack_info);

  return list_id;
""", """  set_xasl_unpack_info_ptr (thread_p, outer_unpack_info);
#if defined (SERVER_MODE)
  if (tla_nested)
    {
      tla_trace ("a=Query2 p=%d", tla_role);
    }
#endif

  return list_id;
"""),
  (LAST, DECL + LAST),
])

edit("src/storage/page_buffer.c", [
  ("""  if (csc_in_method_dispatch ())
    {
      return;
    }""", """  if (csc_in_method_dispatch ())
    {
      if (tla_role != 0)
	{
	  tla_trace ("a=Commit p=%d", tla_role);
	}
      return;
    }"""),
  (LAST, DECL + LAST),
])
print("instrumented", W)
