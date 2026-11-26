import sys
W=sys.argv[1]
def rd(p): return open(W+'/'+p).read()
def wr(p,s): open(W+'/'+p,'w').write(s)
def sub(path, old, new, cnt=1):
    s=rd(path); assert s.count(old)==cnt,(path,old[:50],s.count(old)); wr(path,s.replace(old,new))
E='src/broker/cas_execute.c'
for n in ['bool stream_Deferred_auto_commit','bool stream_Release_commit_owed','int stream_Status_before_request','int stream_Status_before_upload','int stream_Status_to_restore']:
    sub(E,'static '+n,'static CAS_TLS '+n)
sub(E,'''static struct
{
  bool open;
  int kind;
  int chunks;
  INT64 bytes;
  struct timeval open_time;
} stream_Log;''','''static CAS_TLS struct
{
  bool open;
  int kind;
  int chunks;
  INT64 bytes;
  struct timeval open_time;
} stream_Log;''')
sub('src/connection/driver_session.cpp','''	  db_set_keep_session (yielded);
	  (void) ux_end_session ();
''','''	  db_set_keep_session (yielded);
	  (void) ux_end_session ();
	  if (!yielded)
	    {
	      /* the server session, and with it any stream session it held, is gone */
	      ux_stream_reset ();
	    }
''')
