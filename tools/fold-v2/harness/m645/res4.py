import sys
W=sys.argv[1]
def rd(p): return open(W+'/'+p).read()
def wr(p,s): open(W+'/'+p,'w').write(s)
def sub(path, old, new, cnt=1):
    s=rd(path); assert s.count(old)==cnt,(path,old[:50],s.count(old)); wr(path,s.replace(old,new))
A='''static_assert (sizeof (server_fn_table) / sizeof (server_fn_table[0]) == CAS_FC_MAX - 1,
	       "server_fn_table must have one entry per CAS function code");
static_assert (sizeof (server_func_name) / sizeof (server_func_name[0]) == CAS_FC_MAX - 1,
	       "server_func_name must have one entry per CAS function code");
'''
sub('src/broker/cas.c','''#include "cas_ssl.h"


/* ========================================================================
 * Function Tables
 * ======================================================================== */

'''+A,'''#include "cas_ssl.h"

// XXX: SHOULD BE THE LAST INCLUDE HEADER
#include "memory_wrapper.hpp"

''')
D='src/broker/cas_dispatch.c'
sub(D,'''  fn_set_cas_change_mode	/* CAS_FC_SET_CAS_CHANGE_MODE */
};''','''  fn_set_cas_change_mode,	/* CAS_FC_SET_CAS_CHANGE_MODE */
  fn_stream_send_data,		/* CAS_FC_STREAM_SEND_DATA */
  fn_stream_end,		/* CAS_FC_STREAM_END */
  fn_stream_init,		/* CAS_FC_STREAM_INIT */
  fn_stream_abort,		/* CAS_FC_STREAM_ABORT */
  fn_stream_read_open,		/* CAS_FC_STREAM_READ_OPEN */
  fn_stream_read,		/* CAS_FC_STREAM_READ */
  fn_stream_release		/* CAS_FC_STREAM_RELEASE */
};''')
sub(D,'''  "fn_set_cas_change_mode"
};
''','''  "fn_set_cas_change_mode",
  "fn_stream_send_data",
  "fn_stream_end",
  "fn_stream_init",
  "fn_stream_abort",
  "fn_stream_read_open",
  "fn_stream_read",
  "fn_stream_release"
};

'''+A)
sub(D,'''  FN_RETURN fn_ret = FN_KEEP_CONN;

  error_info_clear ();''','''  FN_RETURN fn_ret = FN_KEEP_CONN;
  bool func_code_unknown;

  error_info_clear ();''')
s=rd(D)
i=s.index('  db_set_interrupt (0);'); j=s.rfind('/*',0,i)
print(repr(s[j:i+40]))
