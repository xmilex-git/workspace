import sys,re
W=sys.argv[1]
def sub(path, old, new):
    p=W+'/'+path; s=open(p).read()
    assert s.count(old)==1,(path,old[:40],s.count(old))
    open(p,'w').write(s.replace(old,new))
sub('src/parser/csql_grammar.y','''<<<<<<< HEAD
/* this block is copied verbatim into the generated csql_grammar.h,
 * so the TLS marker must be defined here for both copies */
#include "csql_parser_tls.h"

extern CSQL_PARSER_TLS int g_msg[1024];
extern CSQL_PARSER_TLS int msg_ptr;
extern CSQL_PARSER_TLS int is_dblink_query_string;
extern CSQL_PARSER_TLS int expecting_pl_lang_spec;
=======
extern int g_msg[1024];
extern int msg_ptr;
extern int is_dblink_query_string;
extern int expecting_pl_lang_spec;
extern int expecting_trigger_plcsql_block;
>>>>>>> origin/develop
''','''/* this block is copied verbatim into the generated csql_grammar.h,
 * so the TLS marker must be defined here for both copies */
#include "csql_parser_tls.h"

extern CSQL_PARSER_TLS int g_msg[1024];
extern CSQL_PARSER_TLS int msg_ptr;
extern CSQL_PARSER_TLS int is_dblink_query_string;
extern CSQL_PARSER_TLS int expecting_pl_lang_spec;
extern CSQL_PARSER_TLS int expecting_trigger_plcsql_block;
''')
sub('src/parser/csql_grammar.y','''<<<<<<< HEAD
static CSQL_PARSER_TLS int g_plcsql_text_pos;
=======
static char *pt_read_input_file(int start, int end);
static PT_NODE *pt_make_trigger_plcsql_block(PT_NODE* node, int end);
static int g_plcsql_text_pos;
>>>>>>> origin/develop
''','''static char *pt_read_input_file(int start, int end);
static PT_NODE *pt_make_trigger_plcsql_block(PT_NODE* node, int end);
static CSQL_PARSER_TLS int g_plcsql_text_pos;
''')
sub('src/parser/csql_lexer.l','''<<<<<<< HEAD
CSQL_PARSER_TLS int yybuffer_pos;
CSQL_PARSER_TLS int is_dblink_query_string = 0;
CSQL_PARSER_TLS int expecting_pl_lang_spec = 0;
=======
int yybuffer_pos;
int is_dblink_query_string = 0;
int expecting_pl_lang_spec = 0;
int expecting_trigger_plcsql_block = 0;
>>>>>>> origin/develop
''','''CSQL_PARSER_TLS int yybuffer_pos;
CSQL_PARSER_TLS int is_dblink_query_string = 0;
CSQL_PARSER_TLS int expecting_pl_lang_spec = 0;
CSQL_PARSER_TLS int expecting_trigger_plcsql_block = 0;
''')
