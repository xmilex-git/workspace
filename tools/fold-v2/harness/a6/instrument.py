# TLATRACE instrumentation of A6 for docs/tla/CBRD-27430-A6 (scratch worktree only)
# usage: python3 instrument.py <worktree>
# Roles: tla_role = tracer session id. The revoker is the session CUBRID_TLATRACE_REVOKER names (events p=0);
# every other tracer session is a grantee (p=<sid>). Only steps on the class CUBRID_TLATRACE_CLASS
# ("vol|page|slot") are logged; the dropper's steps are logged for any tracer session.
import sys
W = sys.argv[1]


def edit(path, pairs):
    p = f"{W}/{path}"
    s = open(p).read()
    for o, n in pairs:
        assert s.count(o) == 1, (path, s.count(o), o[:100])
        s = s.replace(o, n)
    open(p, "w").write(s)


DECL = '''
extern thread_local int tla_role;
extern thread_local bool tla_revoking;
extern thread_local bool tla_active;
extern thread_local bool tla_stmt_checked;
extern void tla_trace (const char *fmt, ...);
extern bool tla_class_is_traced (const OID * oid);
extern bool tla_is_grantee (void);
extern bool tla_is_revoker (void);
extern void tla_set_sha1 (const SHA1Hash * sha1);
extern bool tla_sha1_is (const SHA1Hash * sha1);
'''

edit("src/object/client_session_context.cpp", [
  ('''static thread_local client_session_context *tl_Csc_active = NULL;
''', '''static thread_local client_session_context *tl_Csc_active = NULL;

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>
#include "sha1.h"

thread_local int tla_role = 0;
thread_local bool tla_revoking = false;
thread_local bool tla_active = false;
thread_local bool tla_stmt_checked = false;
static thread_local SHA1Hash tla_Sha1;
static thread_local bool tla_Sha1_set = false;
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
  va_start (ap, fmt);
  fprintf (tla_Fp, "TLATRACE seq=%lu ", ++tla_Seq);
  vfprintf (tla_Fp, fmt, ap);
  fputc ('\\n', tla_Fp);
  fflush (tla_Fp);
  va_end (ap);
}

bool
tla_class_is_traced (const OID * oid)
{
  static int vol = -2, page, slot;
  if (vol == -2)
    {
      const char *c = getenv ("CUBRID_TLATRACE_CLASS");
      if (c == NULL || sscanf (c, "%d|%d|%d", &vol, &page, &slot) != 3)
	{
	  vol = -1;
	}
    }
  return oid != NULL && vol >= 0 && oid->volid == vol && oid->pageid == page && oid->slotid == slot;
}

bool
tla_is_revoker (void)
{
  const char *r = getenv ("CUBRID_TLATRACE_REVOKER");
  return tla_role != 0 && r != NULL && atoi (r) == tla_role;
}

bool
tla_is_grantee (void)
{
  return tla_role != 0 && !tla_is_revoker ();
}

void
tla_set_sha1 (const SHA1Hash * sha1)
{
  tla_Sha1 = *sha1;
  tla_Sha1_set = true;
}

bool
tla_sha1_is (const SHA1Hash * sha1)
{
  return tla_Sha1_set && memcmp (&tla_Sha1, sha1, sizeof (tla_Sha1)) == 0;
}
'''),
])

# the tracer session's role
edit("src/transaction/server_compile_tracer.cpp", [
  ('''  ctx = new client_session_context ();
  csc_activate (ctx);
''', '''  ctx = new client_session_context ();
  tla_role = sid;
  csc_activate (ctx);
'''),
  ('''// XXX: SHOULD BE THE LAST INCLUDE HEADER
''', '''#include "oid.h"
#include "sha1.h"
''' + DECL + '''// XXX: SHOULD BE THE LAST INCLUDE HEADER
'''),
])

# revoker: RUpdate (grants updated under X on the authorization instance)
edit("src/object/authenticate_grant.cpp", [
  ('''		      Au_cache.reset_cache_for_user_and_class (classobj);
''', '''		      Au_cache.reset_cache_for_user_and_class (classobj);
#if defined (SERVER_MODE)
		      if (tla_is_revoker () && tla_class_is_traced (ws_oid (class_mop)))
			{
			  tla_revoking = true;
			  tla_trace ("a=RUpdate p=0");
			}
#endif
'''),
  ('''#include "jsp_cl.h"
''', '''#include "jsp_cl.h"
#if defined (SERVER_MODE)
#include "sha1.h"
''' + DECL + '''#endif
'''),
])

# revoker: RTouch (the class flush removes the entries)
edit("src/transaction/locator_sr.c", [
  ('''      /* system class do not include foreign keys. we need not check here. */

      /* remove XASL cache entries which is relevant with that class */
      if (!OID_IS_ROOTOID (oid))
	{
	  xcache_remove_by_oid (thread_p, oid);
	}
''', '''      /* system class do not include foreign keys. we need not check here. */

      /* remove XASL cache entries which is relevant with that class */
      if (!OID_IS_ROOTOID (oid))
	{
	  xcache_remove_by_oid (thread_p, oid);
#if defined (SERVER_MODE)
	  if (tla_revoking && tla_class_is_traced (oid))
	    {
	      tla_trace ("a=RTouch p=0");
	    }
#endif
	}
'''),
  ('''// XXX: SHOULD BE THE LAST INCLUDE HEADER
''', '''#if defined (SERVER_MODE)
#include "sha1.h"
''' + DECL + '''#endif
// XXX: SHOULD BE THE LAST INCLUDE HEADER
'''),
])

# commit: SCommit (grantee, before the locks go), RCommit, RCleanup, RUnlock (revoker)
edit("src/transaction/log_manager.c", [
  ('''log_commit_local (THREAD_ENTRY * thread_p, LOG_TDES * tdes, bool retain_lock, bool is_local_tran)
{
''', '''log_commit_local (THREAD_ENTRY * thread_p, LOG_TDES * tdes, bool retain_lock, bool is_local_tran)
{
#if defined (SERVER_MODE)
  if (tla_active && tla_is_grantee ())
    {
      tla_trace ("a=SCommit p=%d", tla_role);
      tla_active = false;
    }
#endif
'''),
  ('''  logtb_complete_mvcc (thread_p, tdes, true);
''', '''  logtb_complete_mvcc (thread_p, tdes, true);
#if defined (SERVER_MODE)
  if (tla_revoking)
    {
      tla_trace ("a=RCommit p=0");
    }
#endif
'''),
  ('''  /* remove XASL cache entries which are relevant with this class */
  xcache_remove_by_oid (thread_p, &t.m_class_oid);
''', '''  /* remove XASL cache entries which are relevant with this class */
  xcache_remove_by_oid (thread_p, &t.m_class_oid);
#if defined (SERVER_MODE)
  if (tla_revoking && tla_class_is_traced (&t.m_class_oid))
    {
      tla_trace ("a=RCleanup p=0");
    }
#endif
'''),
  ('''	  if (retain_lock != true)
	    {
	      lock_unlock_all (thread_p);
	    }

	  /* Flush commit log and change the transaction state. */''', '''	  if (retain_lock != true)
	    {
	      lock_unlock_all (thread_p);
	    }
#if defined (SERVER_MODE)
	  if (tla_revoking)
	    {
	      tla_trace ("a=RUnlock p=0");
	      tla_revoking = false;
	    }
#endif

	  /* Flush commit log and change the transaction state. */'''),
  ('''// XXX: SHOULD BE THE LAST INCLUDE HEADER
''', '''#if defined (SERVER_MODE)
#include "sha1.h"
''' + DECL + '''#endif
// XXX: SHOULD BE THE LAST INCLUDE HEADER
'''),
])

# grantee compile: SPLock + SAu at the first check of t in a compile (its class lock is already held)
edit("src/compat/db_vdb.c", [
  ('''db_compile_statement_local (DB_SESSION * session)
{
  PARSER_CONTEXT *parser;
''', '''db_compile_statement_local (DB_SESSION * session)
{
#if defined (SERVER_MODE)
  tla_stmt_checked = false;
#endif
  PARSER_CONTEXT *parser;
'''),
  ('''// XXX: SHOULD BE THE LAST INCLUDE HEADER
''', '''#if defined (SERVER_MODE)
#include "sha1.h"
''' + DECL + '''#endif
// XXX: SHOULD BE THE LAST INCLUDE HEADER
'''),
])

edit("src/object/authenticate_access_class.cpp", [
  ('''	      error = appropriate_error (*bits, type);
	      er_set (ER_WARNING_SEVERITY, ARG_FILE_LINE, error, 0);
	    }
	}
    }

  return error;
}
''', '''	      error = appropriate_error (*bits, type);
	      er_set (ER_WARNING_SEVERITY, ARG_FILE_LINE, error, 0);
	    }
	}
    }

#if defined (SERVER_MODE)
  if (!tla_stmt_checked && tla_is_grantee () && tla_class_is_traced (ws_oid (classobj)))
    {
      tla_stmt_checked = true;
      tla_active = true;
      tla_trace ("a=SPLock p=%d", tla_role);
      tla_trace ("a=SAu p=%d ok=%d", tla_role, error == NO_ERROR ? 1 : 0);
    }
#endif
  return error;
}
'''),
  ('''#include "schema_system_catalog.hpp" /* sm_is_system_class () */
''', '''#include "schema_system_catalog.hpp" /* sm_is_system_class () */
#if defined (SERVER_MODE)
#include "sha1.h"
''' + DECL + '''#endif
'''),
])

# grantee prepare: SIns (found = 0 / inserted = 1)
edit("src/query/query_manager.c", [
  ('''	      /* Found entry. */
	      XASL_ID_COPY (stream->xasl_id, &cache_entry_p->xasl_id);
''', '''	      /* Found entry. */
	      XASL_ID_COPY (stream->xasl_id, &cache_entry_p->xasl_id);
	      if (tla_is_grantee ())
		{
		  for (int k = 0; k < cache_entry_p->n_related_objects; k++)
		    {
		      if (tla_class_is_traced (&cache_entry_p->related_objects[k].oid))
			{
			  tla_set_sha1 (&context->sha1);
			  tla_trace ("a=SIns p=%d new=0", tla_role);
			  break;
			}
		    }
		}
'''),
  ('''  XASL_ID_COPY (stream->xasl_id, &cache_entry_p->xasl_id);
  xcache_unfix (thread_p, cache_entry_p);

exit_on_end:''', '''  XASL_ID_COPY (stream->xasl_id, &cache_entry_p->xasl_id);
  if (tla_is_grantee ())
    {
      for (int k = 0; k < n_oid_list; k++)
	{
	  if (tla_class_is_traced (&class_oid_list_p[k]))
	    {
	      tla_set_sha1 (&context->sha1);
	      tla_trace ("a=SIns p=%d new=1", tla_role);
	      break;
	    }
	}
    }
  xcache_unfix (thread_p, cache_entry_p);

exit_on_end:'''),
  ('''// XXX: SHOULD BE THE LAST INCLUDE HEADER
''', '''#if defined (SERVER_MODE)
#include "sha1.h"
''' + DECL + '''#endif
// XXX: SHOULD BE THE LAST INCLUDE HEADER
'''),
])

# grantee execute: SELook (found 0/1), SELock, SECheck (run 0/1)
edit("src/query/xasl_cache.c", [
  ('''  if (*xcache_entry == NULL)
    {
      /* No entry was found. */
      if (recompile_due_to_threshold == XASL_CACHE_RECOMPILE_EXECUTE)''', '''  bool tla_t = tla_is_grantee () && tla_sha1_is (&xid->sha1);
  if (*xcache_entry == NULL)
    {
      /* No entry was found. */
      if (tla_t)
	{
	  tla_trace ("a=SELook p=%d found=0", tla_role);
	}
      if (recompile_due_to_threshold == XASL_CACHE_RECOMPILE_EXECUTE)'''),
  ('''      xcache_unfix (thread_p, *xcache_entry);
      *xcache_entry = NULL;

      /* TODO:''', '''      xcache_unfix (thread_p, *xcache_entry);
      *xcache_entry = NULL;
      if (tla_t)
	{
	  tla_trace ("a=SELook p=%d found=0", tla_role);
	}

      /* TODO:'''),
  ('''  assert ((*xcache_entry) != NULL);

  /* set xasl_id to tdes before getting locks */''', '''  assert ((*xcache_entry) != NULL);
  if (tla_t)
    {
      tla_trace ("a=SELook p=%d found=1", tla_role);
      tla_active = true;
    }

  /* set xasl_id to tdes before getting locks */'''),
  ('''  /* Check the entry is still valid.  Uses atomic to prevent any code reordering */
  if (ATOMIC_INC_32 (&((*xcache_entry)->xasl_id.cache_flag), 0) & XCACHE_ENTRY_MARK_DELETED)
    {''', '''  if (tla_t)
    {
      tla_trace ("a=SELock p=%d", tla_role);
    }
  /* Check the entry is still valid.  Uses atomic to prevent any code reordering */
  if (ATOMIC_INC_32 (&((*xcache_entry)->xasl_id.cache_flag), 0) & XCACHE_ENTRY_MARK_DELETED)
    {
      if (tla_t)
	{
	  tla_trace ("a=SECheck p=%d run=0", tla_role);
	}'''),
  ('''  assert ((*xcache_entry) != NULL);

  if (xcache_uses_clones ())''', '''  assert ((*xcache_entry) != NULL);
  if (tla_t)
    {
      tla_trace ("a=SECheck p=%d run=1", tla_role);
    }

  if (xcache_uses_clones ())'''),
  ('''// XXX: SHOULD BE THE LAST INCLUDE HEADER
''', '''#if defined (SERVER_MODE)
#include "sha1.h"
''' + DECL + '''#endif
// XXX: SHOULD BE THE LAST INCLUDE HEADER
'''),
])

# dropper: DRevoke (revoke-all, touching), DFree (disk structures freed)
edit("src/object/schema_manager.c", [
  ('''  AU_SET_USER (save_user);

  /* free any indexes, unique btids, or other associated disk structures */
  error = transfer_disk_structures (op, class_, NULL);
  if (error != NO_ERROR)
    {
      goto end;
    }
''', '''  AU_SET_USER (save_user);
#if defined (SERVER_MODE)
  if (tla_role != 0)
    {
      tla_trace ("a=DRevoke p=0");
    }
#endif

  /* free any indexes, unique btids, or other associated disk structures */
  error = transfer_disk_structures (op, class_, NULL);
  if (error != NO_ERROR)
    {
      goto end;
    }
#if defined (SERVER_MODE)
  if (tla_role != 0)
    {
      tla_trace ("a=DFree p=0");
    }
#endif
'''),
  ('''#include "boot_cl.h"
''', '''#include "boot_cl.h"
#if defined (SERVER_MODE)
#include "sha1.h"
''' + DECL + '''#endif
'''),
])
print("instrumented")
