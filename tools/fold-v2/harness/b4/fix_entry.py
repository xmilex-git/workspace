# fix_entry.py <worktree>: a fold session's thread clears the session's private LRU from its thread entry before
# it gives the entry back.
import sys
p = sys.argv[1] + '/src/connection/driver_session.cpp'; s = open(p).read()
old = '''      entry_p->tran_index = NULL_TRAN_INDEX;
      entry_p->m_status = cubthread::entry::status::TS_DEAD;
      csc_deactivate ();
'''
new = '''      entry_p->tran_index = NULL_TRAN_INDEX;
      entry_p->m_status = cubthread::entry::status::TS_DEAD;
      /* the session's private LRU list must not reach the thread that claims this entry next (a request worker
       * serving a connection that has no session yet) */
      entry_p->private_lru_index = -1;
      entry_p->m_is_private_lru_enabled = false;
      csc_deactivate ();
'''
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
