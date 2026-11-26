import sys,re
W=sys.argv[1]
def rd(p): return open(W+'/'+p).read()
def wr(p,s): open(W+'/'+p,'w').write(s)
def sub(path, old, new, cnt=1):
    s=rd(path); assert s.count(old)==cnt,(path,old[:50],s.count(old)); wr(path,s.replace(old,new))
def take(path, side, nth=None):
    # resolve every conflict hunk in path by taking 'ours', 'theirs' or 'both'
    s=rd(path)
    pat=re.compile(r'<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> origin/develop\n', re.S)
    def r(m):
        return {'ours':m.group(1),'theirs':m.group(2),'both':m.group(1)+m.group(2)}[side]
    s,n=pat.subn(r,s); assert n>=1,(path,n); wr(path,s); print(path,side,n)
take('src/session/session.c','both')
take('src/communication/network_interface_cl.c','theirs')
take('src/communication/network_interface_sr.cpp','ours')
take('src/broker/cas.c','ours')
sub('src/communication/network_interface_sr.cpp','''      er_stack_push ();
      tran_state = tran_server_unilaterally_abort_tran (thread_p);
      er_stack_pop ();
    }

  if (tdes != NULL)
    {
      tdes->tran_abort_reason = TRAN_NORMAL;''','''      er_stack_push ();

      /* This is the one transaction end that does not arrive as a commit/abort request: a deadlock
       * victim is rolled back here, on its own worker. The stream session has to go with it for the
       * same reason as in stran_server_abort_internal () -- the next chunk would otherwise build on work
       * that was already rolled back. Before the rollback, so the session never sees a transaction
       * that has ended, and inside the pushed stack, because the error being reported to the client is
       * the one that has to survive whatever the stream's abort () sets. A request of the connection
       * still running on the session is waited for (session_take_stream_session). */
      session_end_stream_session (thread_p);

      tran_state = tran_server_unilaterally_abort_tran (thread_p);
      er_stack_pop ();
    }

  if (tdes != NULL)
    {
      tdes->tran_abort_reason = TRAN_NORMAL;''')
