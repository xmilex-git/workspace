import re
ours=open('cas.c.ours').read()
old=open('cas_dispatch.c.old').read()
def take(src, name, kind='func'):
    # return (start,end) span of a top-level definition including its leading return-type line
    if kind=='table':
        m=re.search(r'^static [^\n]*\b'+name+r'\[\] = \{\n', src, re.M)
        a=m.start(); b=src.index('\n};\n',a)+4; return a,b
    m=re.search(r'^'+name+r' \(', src, re.M)
    a=src.rfind('\n',0,m.start()-1)+1   # return type line
    # include a leading comment block directly above?
    b=src.index('\n}\n',m.start())+3
    return a,b
names=['net_read_process','set_db_connection_info','clear_db_connection_info','need_database_reconnect','process_request','set_db_parameter']
tables=['server_fn_table','server_func_name']
bodies={}
for t in tables:
    a,b=take(ours,t,'table'); bodies[t]=ours[a:b]
for n in names:
    a,b=take(ours,n); bodies[n]=ours[a:b]
# build new dispatch from old: replace each old definition with ours'
new=old
for t in tables:
    a,b=take(new,t,'table'); new=new[:a]+bodies[t]+new[b:]
for n in names:
    on='cas_process_request' if n=='process_request' else n
    a,b=take(new,on)
    body=bodies[n]
    if n=='process_request':
        body=body.replace('static FN_RETURN\nprocess_request (','FN_RETURN\ncas_process_request (')
    else:
        body=re.sub(r'^static ', '', body, count=1) if n in ('net_read_process','set_db_connection_info','clear_db_connection_info','need_database_reconnect') else body
    new=new[:a]+body+new[b:]
open('cas_dispatch.c.new','w').write(new)
# cas.c: remove moved pieces from ours
c=ours
for t in tables:
    a,b=take(c,t,'table'); c=c[:a]+c[b:]
for n in names:
    a,b=take(c,n); c=c[:a]+c[b:]
for d in ['static void set_db_connection_info (void);\n','static void clear_db_connection_info (void);\n','static bool need_database_reconnect (void);\n',
          'static void set_db_parameter (void);\n']:
    assert d in c, d; c=c.replace(d,'',1)
c=re.sub(r'static FN_RETURN process_request \(SOCKET sock_fd, T_NET_BUF \* net_buf, T_REQ_INFO \* req_info, SOCKET srv_sock_fd\);\n','',c)
c=re.sub(r'static int net_read_process \(SOCKET proxy_sock_fd, MSG_HEADER \* client_msg_header, T_REQ_INFO \* req_info\);\n','',c)
for v in ['static char cas_db_name[MAX_HA_DBINFO_LENGTH];\n','static char cas_db_user[SRV_CON_DBUSER_SIZE];\n','static char cas_db_passwd[SRV_CON_DBPASSWD_SIZE];\n']:
    assert v in c, v; c=c.replace(v,'',1)
c=c.replace('    .process_request = process_request,','    .process_request = cas_process_request,')
c=re.sub(r'fn_ret = process_request \(','fn_ret = cas_process_request (',c)
open('cas.c.new','w').write(c)
print(len(new.split('\n')), len(c.split('\n')))
