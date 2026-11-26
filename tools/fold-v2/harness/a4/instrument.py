# TLATRACE instrumentation of the A4 context lifecycle for docs/tla/CBRD-27430-A4 (scratch worktree only)
# usage: python3 instrument.py <worktree>
# Roles: p=<sid> on a tracer session thread (1..N), p=0 on any other thread (session-control daemon, shutdown).
# Only contexts a tracer created (tla_id != 0) are logged.
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

edit("src/object/client_session_context.hpp", [
  ('''    bool orphaned = false;
''', '''    bool orphaned = false;

    int tla_id = 0;		/* TLATRACE: the tracer session that created it */
'''),
  ('''extern void csc_retire_and_delete (client_session_context *ctx);
''', '''extern void csc_retire_and_delete (client_session_context *ctx);

extern thread_local int tla_role;
extern void tla_trace (const char *fmt, ...);
'''),
])

edit("src/object/client_session_context.cpp", [
  ('''static thread_local client_session_context *tl_Csc_active = NULL;
''', '''static thread_local client_session_context *tl_Csc_active = NULL;

#include <cstdarg>
#include <cstdio>
#include <mutex>

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
  ('''  ctx->bracket_mutex.lock ();
  tl_Csc_active = ctx;
}''', '''  ctx->bracket_mutex.lock ();
  tl_Csc_active = ctx;
  if (ctx->tla_id != 0)
    {
      tla_trace ("a=Acquire p=%d c=%d", tla_role, ctx->tla_id);
    }
}'''),
  ('''  if (orphaned)
    {
      csc_teardown (ctx);
    }
  tl_Csc_active = NULL;
  ctx->bracket_mutex.unlock ();
  if (orphaned)
    {
      /* the session is gone, so no other thread can reach this context */
      delete ctx;
    }''', '''  if (orphaned)
    {
      csc_teardown (ctx);
    }
  tl_Csc_active = NULL;
  const int tla_id = ctx->tla_id;
  if (tla_id != 0)
    {
      tla_trace ("a=Deact p=%d c=%d orph=%d", tla_role, tla_id, orphaned ? 1 : 0);
      tla_trace ("a=Unlock p=%d c=%d", tla_role, tla_id);
    }
  ctx->bracket_mutex.unlock ();
  if (orphaned)
    {
      /* the session is gone, so no other thread can reach this context */
      delete ctx;
    }
  if (tla_id != 0)
    {
      tla_trace ("a=Del p=%d c=%d del=%d", tla_role, tla_id, orphaned ? 1 : 0);
    }'''),
  ('''      ctx->orphaned = true;
      return;''', '''      ctx->orphaned = true;
      if (ctx->tla_id != 0)
	{
	  tla_trace ("a=End2 p=%d c=%d orph=1", tla_role, ctx->tla_id);
	}
      return;'''),
  ('''  csc_activate (ctx);
  csc_teardown (ctx);
  tl_Csc_active = NULL;
  ctx->bracket_mutex.unlock ();
  delete ctx;''', '''  csc_activate (ctx);
  csc_teardown (ctx);
  tl_Csc_active = NULL;
  const int tla_id = ctx->tla_id;
  if (tla_id != 0)
    {
      tla_trace ("a=Tear p=%d c=%d", tla_role, tla_id);
    }
  ctx->bracket_mutex.unlock ();
  delete ctx;
  if (tla_id != 0 && tla_role == 0)
    {
      /* the creator's retire (TRTear) deletes in the same model step */
      tla_trace ("a=DDel p=%d c=%d", tla_role, tla_id);
    }'''),
])

edit("src/session/session.c", [
  ('''#if defined (SERVER_MODE)
  if (session->csc_p != NULL)
    {''', '''#if defined (SERVER_MODE)
  const int tla_id = session->csc_p != NULL ? session->csc_p->tla_id : 0;
  if (tla_id != 0 && tla_role == 0)
    {
      tla_trace ("a=Scan p=0 c=%d", tla_id);
      tla_trace ("a=Uninit p=0 c=%d", tla_id);
    }
  if (session->csc_p != NULL)
    {'''),
  ('''      csc_retire_and_delete (session->csc_p);
      session->csc_p = NULL;
    }
#endif''', '''      csc_retire_and_delete (session->csc_p);
      session->csc_p = NULL;
    }
  if (tla_id != 0 && tla_role == 0)
    {
      tla_trace ("a=Erase p=0 c=%d", tla_id);
    }
#endif'''),
  ('''#if defined (SERVER_MODE)
  thread_p->conn_entry->session_p = NULL;
  thread_p->conn_entry->session_id = DB_EMPTY_SESSION;
''', '''#if defined (SERVER_MODE)
  if (session_p->csc_p != NULL && session_p->csc_p->tla_id != 0)
    {
      tla_trace ("a=End1 p=%d c=%d", tla_role, session_p->csc_p->tla_id);
    }
  thread_p->conn_entry->session_p = NULL;
  thread_p->conn_entry->session_id = DB_EMPTY_SESSION;
'''),
  ('''      /* This session_state is busy, I can't remove */
      pthread_mutex_unlock (&session_p->mutex);
''', '''      /* This session_state is busy, I can't remove */
      if (session_p->csc_p != NULL && session_p->csc_p->tla_id != 0)
	{
	  tla_trace ("a=End2 p=%d c=%d orph=0", tla_role, session_p->csc_p->tla_id);
	}
      pthread_mutex_unlock (&session_p->mutex);
'''),
])

edit("src/object/work_space.c", [
  ('''int
ws_area_init (void)
{
#if defined (SERVER_MODE)
  if (Objlist_area != NULL)''', '''int
ws_area_init (void)
{
#if defined (SERVER_MODE)
  if (tla_role != 0)
    {
      tla_trace ("a=AreaCheck p=%d saw=%d", tla_role, Objlist_area != NULL ? 1 : 0);
      tla_trace ("a=AreaMake p=%d", tla_role);
    }
  if (Objlist_area != NULL)'''),
  ('''#if defined (SERVER_MODE)
/* the workspace state lives''', DECL + '''#if defined (SERVER_MODE)
/* the workspace state lives'''),
])

edit("src/transaction/server_compile_tracer.cpp", [
  ('''  ctx = new client_session_context ();
  csc_activate (ctx);
''', '''  ctx = new client_session_context ();
  ctx->tla_id = sid;
  tla_role = sid;
  tla_trace ("a=New p=%d", sid);
  csc_activate (ctx);
'''),
  ('''  {
    std::lock_guard<std::mutex> boot_guard (tracer_Boot_mutex);
    err = db_restart_ex ("m0_tracer", server_name, "DBA", "", NULL, DB_CLIENT_TYPE_DEFAULT);
  }''', '''  {
    std::lock_guard<std::mutex> boot_guard (tracer_Boot_mutex);
    tla_trace ("a=BootLock p=%d", sid);
    err = db_restart_ex ("m0_tracer", server_name, "DBA", "", NULL, DB_CLIENT_TYPE_DEFAULT);
    if (err == NO_ERROR)
      {
	tla_trace ("a=Reg p=%d", sid);
      }
  }'''),
  ('''  adopted = true;
''', '''  adopted = true;
  tla_trace ("a=Adopt p=%d", sid);
'''),
  ('''      entry_p->conn_entry = NULL;
      css_free_conn (conn);
''', '''      entry_p->conn_entry = NULL;
      css_free_conn (conn);
      tla_trace ("a=Unreg p=%d", sid);
'''),
])
print("instrumented", W)
