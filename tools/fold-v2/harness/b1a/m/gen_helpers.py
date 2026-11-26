import re
ours=open('cas_common_main.c.ours').read(); base=open('cas_common_main.c.base').read()
old=open('cas_conn_helpers.c.old').read()
names=['restart_is_needed','net_read_header_keep_con_on','net_read_int_keep_con_auto','cas_get_graceful_down_timeout','set_hang_check_time','unset_hang_check_time','query_seq_num_next_value','query_seq_num_current_value','cas_get_client_version','cas_set_db_connect_status','cas_get_db_connect_status']
def span(src,name,withcomment=True):
    m=re.search(r'^'+name+r' \(', src, re.M)
    if not m: return None
    a=src.rfind('\n',0,m.start()-1)+1
    if withcomment:
        # absorb directly preceding /* ... */ comment block
        pre=src[:a]
        if pre.endswith(' */\n'):
            c=pre.rfind('/*'); 
            if pre.rfind('\n}\n',0,len(pre)) < c: a=pre.rfind('\n',0,c)+1
    b=src.index('\n}\n',m.start())+3
    return a,b
new=old; c=ours
for n in names:
    so=span(ours,n); sb=span(base,n); sn=span(new,n,False)
    print(n, 'ours' if so else '-', 'base' if sb else '-', 'old' if sn else '-', 'devchg' if so and sb and ours[so[0]:so[1]]!=base[sb[0]:sb[1]] else '')
    if so and sn:
        body=ours[so[0]:so[1]]
        # strip leading comment for the helpers file? keep as old file: replace only function part
        fo=span(ours,n,False); new=new[:sn[0]]+ours[fo[0]:fo[1]]+new[sn[1]:]
    if so:
        so=span(c,n); c=c[:so[0]]+c[so[1]:]
open('cas_conn_helpers.c.new','w').write(new); open('cas_common_main.c.new','w').write(c)
