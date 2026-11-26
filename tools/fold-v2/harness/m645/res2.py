import sys
W=sys.argv[1]
def sub(path, old, new):
    p=W+'/'+path; s=open(p).read()
    assert s.count(old)==1,(path,old[:40],s.count(old))
    open(p,'w').write(s.replace(old,new))
sub('src/sp/jsp_cl.cpp','''<<<<<<< HEAD
#endif
#if defined (CS_MODE) || defined (SERVER_MODE)
	if (directive & SP_DIRECTIVE_ENUM::SP_DIRECTIVE_DETERMINISTIC)
	  {
	    sig.is_deterministic = true;
	  }
	else
	  {
	    sig.is_deterministic = false;
	  }

=======
>>>>>>> origin/develop
''','''#endif
#if defined (CS_MODE) || defined (SERVER_MODE)
''')
sub('src/sp/pl_signature.cpp','''#if defined (CS_MODE) || defined (SERVER_MODE)
    is_deterministic = false;
#endif
''','')
sub('src/sp/pl_signature.hpp','''<<<<<<< HEAD
#if defined (CS_MODE) || defined (SERVER_MODE)
    /* compile side only, not packed: the folded server compiles as a CS client does */
    bool is_deterministic; // DETERMINISTIC
#endif
    /* PARALLEL_ENABLE. Unlike is_deterministic this one is packed, because the server has to
=======
    /* PARALLEL_ENABLE. Packed, because the server has to
>>>>>>> origin/develop
''','''    /* PARALLEL_ENABLE. Packed, because the server has to
''')
sub('src/parser/xasl_generation.c','''<<<<<<< HEAD
	  /* The value of regu_src->value.sp_ptr->sig->is_deterministic is interpreted as follows
	   * 0: PT_AUTHID_OWNER + PT_NOT_DETERMINISTIC
	   * 1: PT_AUTHID_CALLER + PT_NOT_DETERMINISTIC
	   * 2: PT_AUTHID_OWNER + PT_DETERMINISTIC
	   * 3: PT_AUTHID_CALLER + PT_DETERMINISTIC
	   */
#if defined (CS_MODE) || defined (SERVER_MODE)
	  if (regu_src->value.sp_ptr->sig->is_deterministic == false)
	    {
	      return ER_FAILED;
	    }
#endif

=======
''','')
sub('src/parser/xasl_generation.c','''	  /* a stored function not DETERMINISTIC was refused before, in CS and SA alike (pt_is_result_reuse_safe ()) */
>>>>>>> origin/develop
''','''	  /* a stored function not DETERMINISTIC was refused before, in CS and SA alike (pt_is_result_reuse_safe ()) */
''')
