# 이전 캠페인(호스트 변수 사전 확정, wf268-307 optdebug 설치본) CTP sql 실패 100건 — answer vs result diff (변경 행만)

출처: /home/cubrid/ctp-run-out/workspace/sql-20260921T090449Z-462794 (48건, _13_issues·enum·keylimit·analytic), sql-20260921T090324Z-459702 (19건, HV_collation), oc_workspace/sql-20260921T100635Z-489230 (33건, PL/CSQL). `-` = TC 기대(develop), `+` = 이전 캠페인 규칙의 결과.

```

### _13_issues/_10_1h/cases/bug_3256.sql
-ifnull( ?:0 , 1)    
-01/01/2010     
-
-===================================================
-ifnull( ?:0 , 1)    
-09:30:30 AM     
-
-===================================================
-ifnull( ?:0 , 1)    
-09:30:30.001 AM 01/01/2010     
-
-===================================================
-ifnull( ?:0 , 1)    
-09:30:30 AM 01/01/2010     
-
+Error:-494
+===================================================
+Error:-494
+===================================================
+Error:-494
+===================================================
+Error:-494

### _13_issues/_11_1h/cases/bug_bts_4562.sql
-2     3     
+2     3.0     
-2     3     
+2     3.0     
-1     2     
-2     4     
-3     6     
-4     8     
+1.0     2     
+2.0     4     
+3.0     6     
+4.0     8     
-Error:-181
+@int_var+@timestamp_var    
+1012:34:56 PM 01/01/2010     
+
-10.00000000000000000000000000000000000000     
+10.0     
-1     2     
-2     4     
-3     6     
+1     2.0     
+2     4.0     
+3     6.0     
-1     2     
-2     4     
-3     6     
+1     2.0     
+2     4.0     
+3     6.0     
-3     6     
-2     4     
-1     2     
+3     6.0     
+2     4.0     
+1     2.0     
-3     
-4     
-5     
+3.0     
+4.0     
+5.0     
-smallint     smallint     smallint     
+character varying (1073741823)     character varying (1073741823)     character varying (1073741823)     
-1     2     
-2     4     
-3     6     
+1     2.0     
+2     4.0     
+3     6.0     
-1     2     
-2     4     
-3     6     
+1     2.0     
+2     4.0     
+3     6.0     
-3     6     
-2     4     
-1     2     
+3     6.0     

### _13_issues/_11_1h/cases/bug_bts_4565.sql
-6.0     
+6     

### _13_issues/_11_1h/cases/bug_bts_4813.sql
+3     Ahman     086     
+4     Alcott     086     
+5     Ali     086     
+6     Bdalius     011     
+7     Bgassi     011     
+8     Bhman     011     
+9     Blcott     011     
+10     Bli     011     

### _13_issues/_11_1h/cases/bug_bts_4966.sql
-2     
-2     
-2     
-2     
-2     
-2     

### _13_issues/_11_1h/cases/bug_bts_4978.sql
-Error:-454
+Error:-494

### _13_issues/_11_2h/cases/bug_bts_5860_1.sql
-02:02:02     
+02:02:02 AM     
-2010-01-01 01:01:01.0     
+01:01:01.000 AM 01/01/2010     
-Error:-621
+addtime( ?:0 ,  ?:1 )    
+01:21:11 AM     
+

### _13_issues/_12_1h/cases/_01_case_hostvar.sql
-first     
+else     
-Error:-181
+case  ?:0  when  ?:1  then  ?:2  when  ?:3  then  ?:4  else  ?:5  end    
+else     
+
-Error:-181
+case  ?:0  when  ?:1  then  ?:2  when  ?:3  then  ?:4  else  ?:5  end    
+else     
+
-Error:-181
+case  ?:0  when  ?:1  then  ?:2  when  ?:3  then  ?:4  else  ?:5  end    
+else     
+
-Error:-181
+case  ?:0  when  ?:1  then  ?:2  when  ?:3  then  ?:4  else  ?:5  end    
+else     
+

### _13_issues/_12_1h/cases/_02_decode_hostvar.sql
-first     
+else     
-Error:-181
+decode( ?:0 ,  ?:1 ,  ?:2 ,  ?:3 ,  ?:4 ,  ?:5 )    
+else     
+
-Error:-181
+decode( ?:0 ,  ?:1 ,  ?:2 ,  ?:3 ,  ?:4 ,  ?:5 )    
+else     
+
-Error:-181
+decode( ?:0 ,  ?:1 ,  ?:2 ,  ?:3 ,  ?:4 ,  ?:5 )    
+else     
+
-Error:-181
+decode( ?:0 ,  ?:1 ,  ?:2 ,  ?:3 ,  ?:4 ,  ?:5 )    
+else     
+

### _13_issues/_12_1h/cases/bug_bts_6605.sql
-1     1     
-2     2     
-3     3     
-4     4     
+1     1.0     
+2     2.0     
+3     3.0     
+4     4.0     
-4     1     
-3     2     
-2     3     
-1     4     
+4     1.0     
+3     2.0     
+2     3.0     
+1     4.0     
-4     1     
-3     2     
-2     3     
-1     4     
+4     1.0     
+3     2.0     
+2     3.0     
+1     4.0     
-4     4     
-3     3     
-2     2     
-1     1     
+4     4.0     
+3     3.0     
+2     2.0     
+1     1.0     
-4     d     1     4d     
-3     c     2     4d3c     
-2     b     3     4d3c2b     
-1     a     4     4d3c2b1a     
+4     d     1.0     4d     
+3     c     2.0     4d3c     
+2     b     3.0     4d3c2b     
+1     a     4.0     4d3c2b1a     
-4     1     
-3     2     
-2     4     
-1     6     
+4     1.0     
+3     2.0     
+2     4.0     
+1     6.0     
-4     40     
-3     43     
-2     45     
-1     46     
+4     40.0     
+3     43.0     
+2     45.0     
+1     46.0     
-4     1     3     
-3     2     4     
-2     3     3     
-1     4     0     

### _13_issues/_12_1h/cases/bug_bts_7503.sql
-select /*+ INDEX_SS */ t?.a, t?.b, t?.c from t? t? where t?.b=@x
+select /*+ INDEX_SS */ t?.a, t?.b, t?.c from t? t? where t?.b= cast(@x as double)

### _13_issues/_12_1h/cases/bug_bts_8136.sql
-0
-?:0    ?:1 + ?:2    ?:3 + ?:4    
-10     11     OK     
-
+Error:-494
-0
-?:0    ?:1 + ?:2    ?:3 + ?:4    count(*)    
-10     11     OK     1     
-
+Error:-494

### _13_issues/_12_2h/cases/bug_bts_10057_3.sql
-1     
+1     
+1     

### _13_issues/_12_2h/cases/bug_bts_5843.sql
+3     =2.5     
-3     >2.5     
+3     =2.5f     
-3     >2.5f     
+3     =25e-1     
-3     >25e-1     
+3     =2.5     
-3     >2.5     

### _13_issues/_12_2h/cases/bug_bts_6527_03_cast_with_session_vars.sql
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494
-Error:-495
+Error:-494

### _13_issues/_12_2h/cases/bug_bts_7580.sql
-a    
-
+Error:-494

### _13_issues/_12_2h/cases/bug_bts_9072.sql
-Error:-181
+Error:-494

### _13_issues/_12_2h/cases/bug_bts_9953.sql
-trunc( ?:0 , 'default')    
-1999-12-20     
-
+Error:-494
-trunc( ?:0 , 'default')    
-1999-12-20     
-
+Error:-494
-trunc( ?:0 , 'default')    
-1999-12-20     
-
+Error:-494
-123.0     
+123.000     

### _13_issues/_13_1h/cases/bug_bts_10566.sql
-fruit    
-
+Error:-494

### _13_issues/_13_1h/cases/bug_bts_5669.sql
-Error:-181
+Error:-494

### _13_issues/_13_1h/cases/bug_bts_8789.sql
-1     1     1     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-1     1     2     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-1     2     1     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-1     2     2     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-1     2     3     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     1     1     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     1     2     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     1     3     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     1     4     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     2     1     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     2     2     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     3     1     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     3     2     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
-2     3     3     14     2.2     3.1     61.5     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+1     1     1     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+1     1     2     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+1     2     1     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+1     2     2     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+1     2     3     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     1     1     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     1     2     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     1     3     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     1     4     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     2     1     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     2     2     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     3     1     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     3     2     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     
+2     3     3     14     2.2     3.1     61.6     5.7     0.0     -0.0     0.0     0.0     0.0     0.0     

### _13_issues/_13_1h/cases/bug_bts_9889.sql
-iso88591     
+utf8     
-iso88591_bin     
+utf8_bin     
--1     
+6     

### _13_issues/_14_1h/cases/bug_bts_12132.sql
-aaa     utf8_bin     
+aaa     euckr_bin     
-abc     iso88591_bin     
+abc     utf8_bin     

### _13_issues/_14_1h/cases/bug_bts_12256.sql
-2     
+2.0     
-Error:-495
+0
--99     
+1aaa     

### _13_issues/_14_1h/cases/bug_bts_13523.sql
-12     
+3     
-12     
+3     
-Error:-181
+'abc'+ ?:0    
+abc2     
+
-Error:-181
+Error:-494
-Error:-622
+'1'+ ?:0    
+189     
+
-Error:-622
+Error:-494
-Error:-622
+'1'+ ?:0    
+131     
+
-Error:-622
+Error:-494
-1+ ?:0    
-null     
-
+Error:-494
-?:0 + ?:1    
-null     
-
+Error:-494

### _13_issues/_14_1h/cases/bug_bts_13651.sql
-Error:-1150
+a    
+
-Error:-1150
-===================================================
-Error:-1150
+a    
+1     
+
+===================================================
+a    
+1     
+

### _13_issues/_14_1h/cases/bug_bts_13653.sql
-median(c) over (partition by a)    median(d) over (partition by a)    median(a) over (partition by a)    median(b) over (partition by a)    median(c) over ()    median(d) over ()    median(a) over ()
-123.0     123.0     1.0     1.0     178.5     178.5     1.5     1.5     
-234.0     234.0     2.0     2.0     178.5     178.5     1.5     1.5     
-
+Error:-494

### _13_issues/_14_1h/cases/bug_bts_13760.sql
-Error:-622
+replace( ?:0 ,  ?:1 )    collation( replace( ?:2 ,  ?:3 ))    
+a     iso88591_en_cs     
+
-Error:-622
+replace( ?:0 ,  ?:1 )    collation( replace( ?:2 ,  ?:3 ))    
+a     iso88591_en_ci     
+
-Error:-622
+replace( ?:0 ,  ?:1 )    collation( replace( ?:2 ,  ?:3 ))    
+a     euckr_bin     
+

### _13_issues/_14_1h/cases/bug_bts_13782.sql
-iso88591_en_ci     -1     
+iso88591_en_ci     4     
-iso88591_en_ci     -1     
+iso88591_en_ci     4     
-iso88591_en_ci     -1     
+iso88591_en_ci     4     
-Error:-622
+collation    coercibility    
+iso88591_en_ci     4     
+
-iso88591_en_ci     -1     
+iso88591_en_ci     4     
-utf8_bin     -1     
+iso88591_en_ci     4     
-iso88591_en_ci     -1     
+iso88591_en_ci     4     
-utf8_bin     -1     
+utf8_bin     6     
-utf8_bin     -1     
+utf8_bin     6     
-utf8_bin     -1     
+utf8_bin     6     
-utf8_bin     -1     
+utf8_bin     6     
-utf8_bin     -1     
+utf8_bin     6     
-utf8_bin     -1     
+utf8_bin     6     
-utf8_bin     -1     
+utf8_bin     6     
-utf8_en_cs     -1     
+utf8_en_cs     4     
-utf8_en_cs     -1     
+utf8_en_cs     4     
-utf8_en_cs     -1     
+utf8_en_cs     4     
-utf8_en_cs     -1     
+utf8_en_cs     4     
-utf8_en_cs     -1     
+utf8_en_cs     4     
-utf8_bin     -1     
+utf8_en_cs     4     
-utf8_en_cs     -1     
+utf8_en_cs     4     
-euckr_bin     -1     
+euckr_bin     6     
-euckr_bin     -1     
+euckr_bin     6     
-euckr_bin     -1     
+euckr_bin     6     
-Error:-622
+collation    coercibility    
+euckr_bin     6     
+
-euckr_bin     -1     
+euckr_bin     6     
-utf8_bin     -1     
+euckr_bin     6     
-euckr_bin     -1     
+euckr_bin     6     

### _13_issues/_14_1h/cases/bug_bts_13916.sql
-median(newt.c11)    
-11.0     
-
+Error:-494
-a    median(c11)    
-1     16.5     
-2     2.0     
-3     11.0     
-4     10.0     
-
+Error:-494
-a    c11    median(c11) over (partition by a)    
-1     1.0     16.5     
-1     32.0     16.5     
-2     2.0     2.0     
-3     11.0     11.0     
-3     15.0     11.0     
-3     19.0     11.0     
-3     3.0     11.0     
-3     7.0     11.0     
-4     12.0     10.0     
-4     16.0     10.0     
-4     4.0     10.0     
-4     8.0     10.0     
-
+Error:-494
-a    median(c12)    
-1     2055-07-02 12:30:30.555     
-2     2012-02-02 02:02:02.222     
-3     2013-03-13 03:03:03.333     
-4     2014-04-11 16:04:04.444     
-
+Error:-494
-a    c12    median(c12) over (partition by a)    
-1     2011-1-1 1:1:1.111     2055-07-02 12:30:30.555     
-1     2099-12-31 23:59:59.999     2055-07-02 12:30:30.555     
-2     2012-2-2 2:2:2.222     2012-02-02 02:02:02.222     
-3     2013-3-13 3:3:3.333     2013-03-13 03:03:03.333     
-3     2013-3-18 3:3:3.333     2013-03-13 03:03:03.333     
-3     2013-3-23 3:3:3.333     2013-03-13 03:03:03.333     
-3     2013-3-3 3:3:3.333     2013-03-13 03:03:03.333     
-3     2013-3-8 3:3:3.333     2013-03-13 03:03:03.333     
-4     2014-4-14 4:4:4.444     2014-04-11 16:04:04.444     
-4     2014-4-19 4:4:4.444     2014-04-11 16:04:04.444     
-4     2014-4-4 4:4:4.444     2014-04-11 16:04:04.444     
-4     2014-4-9 4:4:4.444     2014-04-11 16:04:04.444     
-
+Error:-494
-a    median(c11)    
-1     16.5     
-2     2.0     
-3     11.0     
-4     10.0     
-5     null     
-
+Error:-494
-a    median(c12)    
-1     2055-07-02 12:30:30.555     
-2     2012-02-02 02:02:02.222     
-3     2013-03-13 03:03:03.333     

### _13_issues/_15_1h/cases/bug_bts_16039.sql
-p_cont    
-1.0     
-2.0     
-3.0     
-
-===================================================
-p_cont1    p_cont2    
-1.0     2.0     
-2.0     2.0     
-3.0     2.0     
-
-===================================================
-p_cont1    p_cont2    
-1.0     1.0     
-2.0     2.0     
-3.0     3.0     
-
-===================================================
-p_cont1    p_cont2    
-1.0     1.0     
-2.0     2.0     
-3.0     3.0     
-
+Error:-494
+===================================================
+Error:-494
+===================================================
+Error:-494
+===================================================
+Error:-494

### _13_issues/_15_2h/cases/bug_bts_14877.sql
-a     20     
-b     20     
-c     20     
-d     20     
+a     20.0     
+b     20.0     
+c     20.0     
+d     20.0     
-select @a := @a+t.a from t t
+select @a :=  cast(@a as double)+ cast(t.a as double) from t t
-select @a := @a+t.a from t t
+select @a :=  cast(@a as double)+ cast(t.a as double) from t t
-select tt.b, (select @a := @a+t.a from t t union select @a := @a+t.a from t t) order by ? desc  for orderby_num()<= ?:?  from t tt
+select tt.b, (select @a :=  cast(@a as double)+ cast(t.a as double) from t t union select @a :=  cast(@a as double)+ cast(t.a as double) from t t) order by ? desc  for orderby_num()<= ?:?  from t tt

### _13_issues/_16_1h/cases/bug_bts_20022.sql
--1     
+5     
--1     
+5     

### _13_issues/_17_1h/cases/cbrd_20769_exp.sql
-i    s    
-4     ^[a]     
-
+Error:-181
-i    s    
-
+Error:-494

### _13_issues/_19_2h/cases/cbrd_22683.sql
-2     3     
+2.0     3.0     
-4     3     
+4.0     3.0     

### _13_issues/_21_2h/cases/cbrd_24111.sql
-select count(*) from (select ? from tb? a, tb? bb where (a.a=bb.a)) a (?), (select ? from tb? b, tb? bb where (b.a=bb.a)) b (?) where (@newincr := @newincr+?)<=?
+select count(*) from (select ? from tb? a, tb? bb where (a.a=bb.a)) a (?), (select ? from tb? b, tb? bb where (b.a=bb.a)) b (?) where (@newincr :=  cast(@newincr as double)+ cast(? as double))<=?

### _13_issues/_23_1h/cases/cbrd_24598.sql
-Error:-181
+decode( ?:0 , '', c, null, c, -1)    
+-1     
+
-Error:-181
+decode( ?:0 , '', c, null, c, 'Z')    
+Z     
+

### _13_issues/_23_1h/cases/cbrd_24906_2.sql
-  rewritten query: (select /*+ ORDERED NO_MERGE */ a.col_a, a.col_b, a.col_c from [dba.tbl_a] a, [dba.tbl_b] b where a.col_a=b.col_a and  ?:?  in multiset{?, ?, ?, ?, ?} and a.col_c= ?:? )
+  rewritten query: (select /*+ ORDERED NO_MERGE */ a.col_a, a.col_b, a.col_c from [dba.tbl_a] a, [dba.tbl_b] b where a.col_a=b.col_a and  cast( ?:?  as double) in multiset{?, ?, ?, ?, ?} and a.col_c=
-  rewritten query: select count(*) from (select /*+ ORDERED NO_MERGE */ a.col_a, a.col_b, a.col_c from [dba.tbl_a] a, [dba.tbl_b] b where a.col_a=b.col_a and  ?:?  in multiset{?, ?, ?, ?, ?} and a.co
+  rewritten query: select count(*) from (select /*+ ORDERED NO_MERGE */ a.col_a, a.col_b, a.col_c from [dba.tbl_a] a, [dba.tbl_b] b where a.col_a=b.col_a and  cast( ?:?  as double) in multiset{?, ?, 

### _13_issues/_24_1h/cases/cbrd_25374.sql
-  rewritten query: select a.cola, a.colb from [dba.tbl] a left outer join [dba.tbl] b on a.cola=b.cola left outer join [dba.tbl] c on a.cola=c.cola order by ?, ? for orderby_num()> ?:? *? and orderby
+  rewritten query: select a.cola, a.colb from [dba.tbl] a left outer join [dba.tbl] b on a.cola=b.cola left outer join [dba.tbl] c on a.cola=c.cola order by ?, ? for orderby_num()> ?:? * cast(? as bi
-Query Plan:
-  SORT (order by)
-    NESTED LOOPS (left outer join)
-      NESTED LOOPS (left outer join)
-        SORT (limit)
-          TABLE SCAN (a)
-        INDEX SCAN (b.idx) (key range: a.cola=b.cola, covered: true)
-      INDEX SCAN (c.idx) (key range: a.cola=c.cola, covered: true)
-
-  rewritten query: select a.cola, a.colb from [dba.tbl] a left outer join [dba.tbl] b on a.cola=b.cola left outer join [dba.tbl] c on a.cola=c.cola order by ?, ? for orderby_num()> ?:? * ?:?  and ord
-
-    SCAN (temp time: ?, fetch: ?, ioread: ?, readrows: ?, rows: ?)
+    SCAN (table: dba.tbl), (heap time: ?, fetch: ?, ioread: ?, readrows: ?, rows: ?)
+         (parallel workers: ?, heap time: ?..?, readrows: ?..?, rows: ?..?, topnsort: true, gather: mergeable list)
-    ORDERBY (time: ?, topnsort: true)
-    SUBQUERY (uncorrelated)
-      SELECT (time: ?, fetch: ?, fetch_time: ?, ioread: ?)
-        SCAN (table: dba.tbl), (heap time: ?, fetch: ?, ioread: ?, readrows: ?, rows: ?)
-             (parallel workers: ?, heap time: ?..?, readrows: ?..?, rows: ?..?, topnsort: true, gather: mergeable list)
-        ORDERBY (time: ?, sort: true, page: ?, ioread: ?)
+    ORDERBY (time: ?, sort: true, page: ?, ioread: ?)
-Query Plan:
-  SORT (order by)
-    NESTED LOOPS (left outer join)
-      NESTED LOOPS (left outer join)
-        SORT (limit)
-          TABLE SCAN (a)
-        INDEX SCAN (b.idx) (key range: a.cola=b.cola, covered: true)
-      INDEX SCAN (c.idx) (key range: a.cola=c.cola, covered: true)
-
-  rewritten query: select a.cola, a.colb from [dba.tbl] a left outer join [dba.tbl] b on a.cola=b.cola left outer join [dba.tbl] c on a.cola=c.cola order by ?, ? for orderby_num()> ?:?  and orderby_n
-
-    SCAN (temp time: ?, fetch: ?, ioread: ?, readrows: ?, rows: ?)
+    SCAN (table: dba.tbl), (heap time: ?, fetch: ?, ioread: ?, readrows: ?, rows: ?)
+         (parallel workers: ?, heap time: ?..?, readrows: ?..?, rows: ?..?, topnsort: true, gather: mergeable list)
-    ORDERBY (time: ?, topnsort: true)
-    SUBQUERY (uncorrelated)
-      SELECT (time: ?, fetch: ?, fetch_time: ?, ioread: ?)
-        SCAN (table: dba.tbl), (heap time: ?, fetch: ?, ioread: ?, readrows: ?, rows: ?)
-             (parallel workers: ?, heap time: ?..?, readrows: ?..?, rows: ?..?, topnsort: true, gather: mergeable list)
-        ORDERBY (time: ?, sort: true, page: ?, ioread: ?)
+    ORDERBY (time: ?, sort: true, page: ?, ioread: ?)
-  rewritten query: select [dba.u].i, [dba.u].j, [dba.u].k, [dba.t].i, [dba.t].j, [dba.t].k from [dba.u] [dba.u], [dba.t] [dba.t] where [dba.u].i=[dba.t].i and ([dba.u].j> ?:? ) order by ? for orderby
+  rewritten query: select [dba.u].i, [dba.u].j, [dba.u].k, [dba.t].i, [dba.t].j, [dba.t].k from [dba.u] [dba.u], [dba.t] [dba.t] where [dba.u].i=[dba.t].i and ([dba.u].j> ?:? ) order by ? for orderby

### _13_issues/_24_2h/cases/cbrd_25567.sql
-  INDEX SCAN (dba.t.idx) (key range: ([dba.t].b<= concat( cast(@v as varchar), '?')), key filter: ([dba.t].b>= concat( cast(@v as varchar), '?')), covered: true)
+  INDEX SCAN (dba.t.idx) (key range: ([dba.t].b<= concat(@v, '?')), key filter: ([dba.t].b>= concat(@v, '?')), covered: true)
-  rewritten query: select count(*) from [dba.t] [dba.t] where ([dba.t].b>= concat( cast(@v as varchar), '?')) and ([dba.t].b<= concat( cast(@v as varchar), '?'))
+  rewritten query: select count(*) from [dba.t] [dba.t] where ([dba.t].b>= concat(@v, '?')) and ([dba.t].b<= concat(@v, '?'))

### _16_index_enhancement/_03_index_keylimit/cases/_001_index_keylimit_1.sql
-Error:-181
+Error:-494
-Error:-181
+Error:-494

### _19_apricot/_07_analytic_clause/cases/_18_host_vars.sql
-1     1     1     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-1     1     2     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-1     2     1     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-1     2     2     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-1     2     3     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     1     1     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     1     2     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     1     3     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     1     4     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     2     1     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     2     2     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     3     1     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     3     2     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-2     3     3     14     2.2     3.1     61.6     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     1     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     1     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     2     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     2     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     2     3     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     1     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     1     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     1     3     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     1     4     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     2     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     2     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     3     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     3     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     3     3     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-1     1     1     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-1     1     2     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-1     2     1     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-1     2     2     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-1     2     3     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     1     1     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     1     2     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     1     3     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     1     4     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     2     1     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     2     2     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     3     1     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     3     2     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
-2     3     3     14     2.2     3.1     61.59999999999999     5.700000000000002     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0
+1     1     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     1     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     2     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     2     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+1     2     3     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     1     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     1     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     1     3     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     1     4     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     2     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     2     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     3     1     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     3     2     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
+2     3     3     14     2.2     3.1     61.6     5.7     3.725290298461914E-9     -2.8421709430404007E-14     0.0     2.8421709430404007E-14     7.450580596923828E-9     0.0     
-1     1     1     14     2.2     3.1     61.60001     5.699999809265137     0.0     0.0     0.0     0.0     0.0     2.8421709430404007E-14     
-1     1     2     14     2.2     3.1     61.60001     5.699999809265137     0.0     0.0     0.0     0.0     0.0     2.8421709430404007E-14     
-1     2     1     14     2.2     3.1     61.60001     5.699999809265137     0.0     0.0     0.0     0.0     0.0     2.8421709430404007E-14     
-1     2     2     14     2.2     3.1     61.60001     5.699999809265137     0.0     0.0     0.0     0.0     0.0     2.8421709430404007E-14     

### _19_apricot/_10_enum_type/cases/late_binding_001.sql
-e1+ ?:0    ?:1 +e1    
-Cancel-a     a-Cancel     
-No-a     a-No     
-Yes-a     a-Yes     
-
+Error:-494
-Cancel1     2Cancel     
-No1     2No     
-Yes1     2Yes     
+2     3     
+3     4     
+4     5     
-e1+ ?:0    ?:1 +e1    
-2012-01-01 12:00:00.001     2012-01-01 12:00:00.001     
-2012-01-01 12:00:00.002     2012-01-01 12:00:00.002     
-2012-01-01 12:00:00.003     2012-01-01 12:00:00.003     
-
+Error:-494
-e1+ ?:0    ?:1 +e1    
-2012-01-02     2012-01-02     
-2012-01-03     2012-01-03     
-2012-01-04     2012-01-04     
-
+Error:-494
-e1+ ?:0    ?:1 +e1    
-13:13:14     13:13:14     
-13:13:15     13:13:15     
-13:13:16     13:13:16     
-
+Error:-494
-e1+ ?:0    ?:1 +e1    
-2012-12-21 13:13:14.0     2012-12-21 13:13:14.0     
-2012-12-21 13:13:15.0     2012-12-21 13:13:15.0     
-2012-12-21 13:13:16.0     2012-12-21 13:13:16.0     
-
+Error:-494

### _19_apricot/_10_enum_type/cases/late_binding_002.sql
-Error:-181
+Error:-494
-0.0     
-1.0     
-2.0     
+0     
+1     
+2     
-e1- ?:0    
--212192222399999     
--212192222399998     
--212192222399997     
-
+Error:-494
-Error:-552
+Error:-494
-e1- ?:0    
-10:46:48     
-10:46:49     
-10:46:50     
-
+Error:-494
-Error:-553
+Error:-494
-Error:-181
+Error:-494
--1.0     
-0.0     
-1.0     
+-1     
+0     
+1     
-?:0 -e1    
-2012-01-01 11:59:59.997     
-2012-01-01 11:59:59.998     
-2012-01-01 11:59:59.999     
-
+Error:-494
-?:0 -e1    
-2011-12-29     
-2011-12-30     
-2011-12-31     
-
+Error:-494
-?:0 -e1    
-13:13:10     
-13:13:11     
-13:13:12     
-
+Error:-494
-?:0 -e1    
-2012-12-21 13:13:10.0     
-2012-12-21 13:13:11.0     
-2012-12-21 13:13:12.0     
-
+Error:-494

### _19_apricot/_10_enum_type/cases/prepare_001.sql
-b     Cancel     Saturday     z     

### _19_apricot/_10_enum_type/cases/prepare_002.sql
-e1+ ?:0    ?:1 +e1    e1+ ?:2    e1* ?:3    e1+ ?:4    
-2     2     2.1     5     Sunday-     
-3     3     3.1     10     Monday-     
-4     4     4.1     15     Tuesday-     
-5     5     5.1     20     Wednesday-     
-6     6     6.1     25     Thursday-     
-7     7     7.1     30     Friday-     
-
+Error:-494
-Sunday     02/23/2012     11:12:09     9876     
-Monday     02/23/2012     11:12:09     9876     
-Wednesday     12/21/2012     13:13:13     9876     
-Saturday     02/23/2012     13:13:13     -34     

### _19_apricot/_10_enum_type/cases/trac_344_02.sql
-i    e1    
-1     Sunday     
-2     Monday     
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
-
+Error:-494
-i    e1    
-1     Sunday     
-2     Monday     
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
-
+Error:-494
-i    e1    
-1     Sunday     
-2     Monday     
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
-
+Error:-494
-i    e1    
-1     Sunday     
-2     Monday     
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
-
+Error:-494
+Error:-494
+===================================================
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
+Error:-494
+===================================================
-
-===================================================
-i    e1    
-6     Friday     
-8     01/01/2012     
+3     Tuesday     

### _19_apricot/_10_enum_type/cases/trac_344_03.sql
-i    e1    
-
+Error:-494
-i    e1    
-
+Error:-494
-i    e1    
-1     Sunday     
-2     Monday     
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
-
+Error:-494
-i    e1    
-1     Sunday     
-2     Monday     
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
-
+Error:-494
-i    e1    
-
+Error:-494
-i    e1    
-
+Error:-494
-i    e1    
-1     Sunday     
-2     Monday     
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
-
+Error:-494
-i    e1    
-1     Sunday     
-2     Monday     
-3     Tuesday     
-4     Wednesday     
-5     Thursday     
-6     Friday     
-7     Saturday     
-8     01/01/2012     
-
+Error:-494
-3     Tuesday     
-4     Wednesday     
+3     Tuesday     
+4     Wednesday     

### _28_features_930/issue_12129_HV_collation/cases/_01_concat.sql
-ab     utf8_bin     
+ab     iso88591_bin     
-ab     euckr_bin     
+ab     iso88591_bin     
-Error:-1150
+concat( ?:0 ,  ?:1 )    collation( concat( ?:2 ,  ?:3 ))    
+ab     iso88591_bin     
+
-Error:-1150
+concat( ?:0 ,  ?:1 )    collation( concat( ?:2 ,  ?:3 ))    
+ab     iso88591_bin     
+
-a     utf8_bin     
+a     iso88591_bin     
-a     euckr_bin     
+a     iso88591_bin     

### _28_features_930/issue_12129_HV_collation/cases/_02_nullif.sql
-A     euckr_bin     
+A     utf8_en_cs     
-Error:-1150
+nullif( ?:0 ,  ?:1 )    collation(nullif( ?:2 ,  ?:3 ))    
+A     utf8_en_cs     
+

### _28_features_930/issue_12129_HV_collation/cases/_03_plus.sql
-?:0 + ?:1    collation( ?:2 + ?:3 )    
-xy     utf8_bin     
-
+Error:-494
-?:0 + ?:1    collation( ?:2 + ?:3 )    
-xy     euckr_bin     
-
+Error:-494
-?:0 + ?:1    collation( ?:2 + ?:3 )    
-xy     iso88591_bin     
-
+Error:-494
-Error:-1150
+Error:-494
-Error:-1150
+Error:-494
-ax     utf8_bin     
+ax     iso88591_bin     
-Error:-622
+rtrim( ?:0 + ?:1 ,  ?:2 )    collation( rtrim( ?:3 + ?:4 ,  ?:5 ))    
+ax     iso88591_bin     
+
-ax     euckr_bin     
+ax     iso88591_bin     

### _28_features_930/issue_12129_HV_collation/cases/_04_group_concat.sql
-3.2     utf8_en_ci     
-4.2     utf8_en_ci     
+3.2     utf8_bin     
+4.2     utf8_bin     
-group_concat(i1+ ?:0  order by 1)    collation(group_concat(i1+ ?:1  order by 1))    
-ax     utf8_en_ci     
-bx     utf8_en_ci     
-
+Error:-494
-group_concat(i1+ ?:0  order by 1)    collation(group_concat(i1+ ?:1  order by 1))    
-ax     utf8_en_ci     
-bx     utf8_en_ci     
-
+Error:-494
-group_concat(i1+ ?:0  order by 1)    collation(group_concat(i1+ ?:1  order by 1))    
-ax     utf8_en_ci     
-bx     utf8_en_ci     
-
+Error:-494

### _28_features_930/issue_12129_HV_collation/cases/_05_insert.sql
-Error:-1150
-===================================================
-Error:-1150
-===================================================
-Error:-1150
+insert( ?:0 ,  ?:1 ,  ?:2 ,  ?:3 )    collation(insert( ?:4 ,  ?:5 ,  ?:6 ,  ?:7 ))    
+xx3456     iso88591_bin     
+
+===================================================
+insert( ?:0 ,  ?:1 ,  ?:2 ,  ?:3 )    collation(insert( ?:4 ,  ?:5 ,  ?:6 ,  ?:7 ))    
+xx3456     iso88591_bin     
+
+===================================================
+insert( ?:0 ,  ?:1 ,  ?:2 ,  ?:3 )    collation(insert( ?:4 ,  ?:5 ,  ?:6 ,  ?:7 ))    
+xx3456     iso88591_bin     
+

### _28_features_930/issue_12129_HV_collation/cases/_06_to_char.sql
-a     utf8_bin     
+a     iso88591_bin     
-a     euckr_bin     
+a     iso88591_bin     

### _28_features_930/issue_12129_HV_collation/cases/_07_session_var.sql
-4     
+4.0     
-Error:-1150
+@v+ ?:0    collation(@v+ ?:1 )    
+22     iso88591_bin     
+
-integer     
+character varying (1073741823)     
-2     
+2.0     
-integer     
+character varying (1073741823)     
-2     
+2.0     
-integer     
+character varying (1073741823)     
-bigint     
+character varying (1073741823)     

### _28_features_930/issue_12129_HV_collation/cases/_08_greatest_least.sql
-a     utf8_bin     
+a     iso88591_bin     
-Error:-1150
+greatest( ?:0 ,  ?:1 ,  ?:2 )    collation(greatest( ?:3 ,  ?:4 ,  ?:5 ))    
+b     iso88591_bin     
+
-1     utf8_bin     
+1     iso88591_bin     
-Error:-1150
+least( ?:0 ,  ?:1 ,  ?:2 )    collation(least( ?:3 ,  ?:4 ,  ?:5 ))    
+2     iso88591_bin     
+

### _28_features_930/issue_12129_HV_collation/cases/_11_between.sql
-Error:-1150
+s1    s2    
+a              a     
+A              B     
+
-Error:-1150
+s1    s2    
+a              a     
+A              B     
+
-a              a     
-A              B     
+a              a     
+A              B     
-Error:-1150
+s1    s2    
+a              a     
+A              B     
+
-Error:-1150
+s1    s2    
+a              a     
+A              B     
+
+a              a     
+A              B     
-a              a     
-A              B     

### _28_features_930/issue_12129_HV_collation/cases/_12_like.sql
-Error:-622
+s1    s2    
+
-Error:-622
+s1    s2    
+aB             ab     
+Ab             aB     
+
-Error:-622
+s1    s2    
+
-Error:-622
+s1    s2    
+aB             ab     
+Ab             aB     
+
-Error:-1150
+s1    s2    
+aB             ab     
+Ab             aB     
+
-Error:-1150
+s1    s2    
+aB             ab     
+Ab             aB     
+
-Error:-1150
+s1    s2    
+aB             ab     
+
-Error:-1150
+s1    s2    
+
-Error:-622
+s1    s2    
+aB             ab     
+Ab             aB     
+
-Error:-1150
+s1    s2    
+aB             ab     
+Ab             aB     
+

### _28_features_930/issue_12129_HV_collation/cases/_13_replace.sql
-Error:-622
+replace( ?:0 ,  ?:1 ,  ?:2 )    
+helloababaa     
+
-Error:-622
+replace( ?:0 ,  ?:1 ,  ?:2 )    
+hellobabaabb     
+
-Error:-622
+replace( ?:0 ,  ?:1 ,  ?:2 )    
+hellobaaabb     
+
-Error:-622
+replace( ?:0 ,  ?:1 ,  ?:2 )    
+helloABBBAA     
+

### _28_features_930/issue_12129_HV_collation/cases/_14_find_in_set.sql
-Error:-622
+find_in_set( ?:0 ,  ?:1 )    
+4     
+
-Error:-622
+find_in_set( ?:0 ,  ?:1 )    
+5     
+
-Error:-622
+find_in_set( ?:0 , (select  ?:1  from db_root))    
+4     
+
-Error:-622
+find_in_set( ?:0 , (select  ?:1  from db_root))    
+5     
+
-s1    find_in_set(s1,  ?:0 + ?:1 )    hex(s1)    
-Ab     1     4162     
-aB     1     6142     
-
+Error:-494
-s1    find_in_set(s1,  ?:0 + ?:1 )    hex(s1)    
-Ab     1     4162     
-aB     1     6142     
-
+Error:-494
-s1    find_in_set(s1,  ?:0 + ?:1 )    hex(s1)    
-Ab     1     4162     
-aB     1     6142     
-
+Error:-494
-s1    find_in_set(s1,  ?:0 + ?:1 )    hex(s1)    
-Ab     1     4162     
-aB     1     6142     
-
+Error:-494
-Error:-1150
+Error:-494
-Error:-1150
+Error:-494
-s2    find_in_set(s2,  ?:0 + ?:1 )    
-ab     1     
-aB     0     
-
+Error:-494
-s2    find_in_set(s2,  ?:0 + ?:1 )    
-ab     0     
-aB     0     
-
+Error:-494
-s2    find_in_set(s2,  ?:0 + ?:1 )    
-ab     0     
-aB     0     
-
+Error:-494
-s2    find_in_set(s2,  ?:0 + ?:1 )    
-ab     0     
-aB     1     
-
+Error:-494

### _28_features_930/issue_12129_HV_collation/cases/_15_position.sql
-Error:-622
+position( ?:0  in  ?:1 )    
+13     
+
-Error:-622
+position( ?:0  in  ?:1 )    
+14     
+
-Error:-622
+position( ?:0  in (select  ?:1  from db_root))    
+13     
+
-Error:-622
+position( ?:0  in (select  ?:1  from db_root))    
+14     
+
-s1    position(s1 in  ?:0 + ?:1 )    
-aB     1     
-Ab     1     
-
+Error:-494
-s1    position(s1 in  ?:0 + ?:1 )    
-aB     1     
-Ab     1     
-
+Error:-494
-s1    position(s1 in  ?:0 + ?:1 )    
-aB     1     
-Ab     1     
-
+Error:-494
-s1    position(s1 in  ?:0 + ?:1 )    
-aB     1     
-Ab     1     
-
+Error:-494
-Error:-1150
+Error:-494
-Error:-1150
+Error:-494
-s2    position(s2 in  ?:0 + ?:1 )    
-ab     1     
-aB     0     
-
+Error:-494
-s2    position(s2 in  ?:0 + ?:1 )    
-ab     0     
-aB     0     
-
+Error:-494
-s2    position(s2 in  ?:0 + ?:1 )    
-ab     0     
-aB     0     
-
+Error:-494
-s2    position(s2 in  ?:0 + ?:1 )    
-ab     0     
-aB     1     
-
+Error:-494

### _28_features_930/issue_12129_HV_collation/cases/_16_in.sql
-Error:-1150
+s1    s2    
+
-Error:-1150
+s1    s2    
+
-Error:-1150
-===================================================
-Error:-1150
-===================================================
+s1    s2    
+
+===================================================
+s1    s2    
+
+===================================================

### _28_features_930/issue_12129_HV_collation/cases/_17_case.sql
-Error:-1150
+case when  ?:0 = ?:1  then  ?:2  else  ?:3  end    
+N     
+
-Error:-1150
+case when  ?:0 = ?:1  then  ?:2  else  ?:3  end    
+Y     
+

### _28_features_930/issue_12129_HV_collation/cases/_18_nullif.sql
-Error:-1150
+nullif( ?:0 ,  ?:1 )    
+a     
+
-Error:-1150
+nullif( ?:0 ,  ?:1 )    
+a     
+
-a     b     
-B     b     
+a          
+B          
-a     B     
-B     null     
+a          
+B          
-a     b     
-B     b     
+a          
+B          
-a     B     
-B     null     
+a          
+B          
-a     b     
-B     b     
+a          
+B          
-a     B     
-B     null     
+a          
+B          
-Error:-1150
+nullif( ?:0 ,  ?:1 )    
+a     
+
-Error:-1150
+nullif( ?:0 ,  ?:1 )    
+B     
+
-a     b     
-B     b     
+a          
+B          
-a     B     
-B     null     
+a          
+B          

### _28_features_930/issue_12129_HV_collation/cases/_19_decode.sql
-Error:-1150
+decode( ?:0 ,  ?:1 ,  ?:2 )    
+null     
+
-Error:-1150
+decode( ?:0 ,  ?:1 ,  ?:2 )    
+N     
+
-s2    decode(s2,  ?:0 ,  ?:1 , nvl( ?:2 , s1),  ?:3 )    
-null     N     
-a     null     
-B     null     
-
+Error:-494

### _28_features_930/issue_12129_HV_collation/cases/_20_translate.sql
-Error:-622
+translate( ?:0 ,  ?:1 ,  ?:2 )    
+helloababaa     
+
-Error:-622
+translate( ?:0 ,  ?:1 ,  ?:2 )    
+hellobabaabb     
+
-Error:-622
+translate( ?:0 ,  ?:1 ,  ?:2 )    
+hellobaaabb     
+
-Error:-622
+translate( ?:0 ,  ?:1 ,  ?:2 )    
+helloABBBAA     
+

### _28_features_930/issue_12129_HV_collation/cases/_21_substring_index.sql
-Error:-622
+substring_index( ?:0 ,  ?:1 ,  ?:2 )    
+helloaAaAaa     
+
-Error:-622
+substring_index( ?:0 ,  ?:1 ,  ?:2 )    
+helloAa     
+
-Error:-622
+substring_index( ?:0 ,  ?:1 ,  ?:2 )    
+helloAaaa     
+

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_01_string_function/cases/04_04_03_01_bfn_string_field.sql
-3
+0

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_04_type_convert_function/cases/04_04_03_04_bfn_type_cast2.sql
-Error:-889
-Stored procedure execute error: 
-  (line 3, column 22) Semantic: Cannot coerce host var to type char. 
+    
+null     
+
+8
-Error:-889
-Stored procedure execute error: 
-  (line 3, column 22) Semantic: Cannot coerce host var to type char. 
+    
+null     
+
+-876543210
-Error:-889
-Stored procedure execute error: 
-  (line 3, column 22) Semantic: Cannot coerce host var to type char. 
+    
+null     
+
+87654321098765432109
-Error:-889
-Stored procedure execute error: 
-  (line 3, column 22) Semantic: Cannot coerce host var to type char. 
+    
+null     
+
+-87654321098765432109876543210
-Error:-889
-Stored procedure execute error: 
-  (line 3, column 22) Semantic: Cannot coerce host var to type char varying. 
+    
+null     
+
+-876543210
-Error:-889
-Stored procedure execute error: 
-  (line 3, column 22) Semantic: Cannot coerce host var to type char varying. 
+    
+null     

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_04_type_convert_function/cases/04_04_03_04_bfn_type_format.sql
--876,543,210,987,654,300.0000
+-876,543,210,987,654,321.0988
--876,543,210,987,654,300.00000000
+-876,543,210,987,654,321.09876543
--876,543,210,987,654,300.000000000000
+-876,543,210,987,654,321.098765432110
--876,543,210,987,654,300.0000000000000000
+-876,543,210,987,654,321.0987654321098765
--876,543,210,987,654,300.00000000000000000000
+-876,543,210,987,654,321.09876543210987654321

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_04_type_convert_function/cases/04_04_03_04_bfn_type_str_to_date.sql
-    
-null     
+Error:-889
+Stored procedure execute error: 
+  (line 5, column 22) Semantic: before '  from dual'
+'str_to_date ' operator is not defined on types varchar with varchar and integer. select  str_to_date( cast( ?:0  as varchar),  cast( ?:1  as ...
-
-12:00:00 PM
-12:00:00 AM
-11:30:34.000 AM 05/01/1999
-11:30:34.000 AM 05/01/1999
-11:30:34.000 AM 05/01/1999
-11:30:34.000 AM 05/01/1999
-11:30:34.000 PM 05/01/1999
-11:30:34.000 PM 05/01/1999
-11:30:34 AM
-11:30:34 AM
-11:30:34 AM
-11:49:59.123 PM 10/31/1999
-11:49:59.100 PM 10/31/1999
-11:49:59.001 PM 10/31/1999
-11:49:59.000 PM 10/31/1999
-11:49:59.000 PM 10/31/1999

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_04_type_convert_function/cases/04_04_03_04_bfn_type_to_char.sql
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-123.456
-123.456
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-11/jan/1999
-11/01/1999
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-06:41:53.733 PM 01/11/1999
-06:41:53.733 오후 01/11/1999
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-123.456
-123.456
-    
-null     
-
+Error:-889

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_04_type_convert_function/cases/04_04_03_04_bfn_type_to_date.sql
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-05/12/1999
-05/12/1999
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-05/12/1999
-05/12/1999

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_04_type_convert_function/cases/04_04_03_04_bfn_type_to_datetime.sql
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-06:41:53.733 AM 01/11/1999
-06:41:53.733 AM 01/11/1999
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-06:41:53.733 AM 01/11/1999
-06:41:53.733 AM 01/11/1999

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_04_type_convert_function/cases/04_04_03_04_bfn_type_to_time.sql
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-06:41:53 AM
-06:41:53 AM
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-06:41:53 AM
-06:41:53 AM

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_04_type_convert_function/cases/04_04_03_04_bfn_type_to_timestamp.sql
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-06:41:53 PM 01/11/1999
-06:41:53 PM 01/11/1999
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 22) Syntax: before ' ) from dual'
+The argument specifying the language must be a string literal. 
-06:41:53 PM 01/11/1999
-06:41:53 PM 01/11/1999

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_05_datetime_function/cases/check_add_func_return.sql
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 1) string does not fit in the target type's length
-adddate 1: 12:00:00.000 AM 03/12/2016
-type: datetime
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 1) string does not fit in the target type's length
-adddate 2: 01:01:01.456 AM 01/01/2008
-type: datetime
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 1) string does not fit in the target type's length
-addtime: 03:00:01 AM
-type: time
-    
-null     
-
+Error:-889
+Stored procedure execute error: 
+  (line 6, column 1) string does not fit in the target type's length
-add_months: 01/08/2024
-type: date

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_06_information_function/cases/04_04_03_06_bfn_info_coerclibility.sql
-11
+6

### _05_plcsql/_01_testspec/_04_expression/_04_function_call/_03_builtin_function/_08_comparision_function/cases/04_04_03_08_bfn_comp_coalesce.sql
-    
-null     
-
+Error:-21019
+Cannot communicate with the broker or received invalid packet
-12:00:00.000 AM 01/01/2010
-12:00:00.000 AM 01/02/2010

### _05_plcsql/_01_testspec/_04_expression/_10_relational_op/_09_type_conversion/cases/04_10_09-01_comparison_op_null.sql
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_10_relational_op/_09_type_conversion/cases/04_10_09-03_comparison_op_string.sql
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_10_relational_op/_09_type_conversion/cases/04_10_09-04_comparison_op_short.sql
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_10_relational_op/_09_type_conversion/cases/04_10_09-05_comparison_op_int.sql
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_10_relational_op/_09_type_conversion/cases/04_10_09-06_comparison_op_bigint.sql
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_10_relational_op/_09_type_conversion/cases/04_10_09-10_comparison_op_date.sql
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_10_relational_op/_09_type_conversion/cases/04_10_09-12_comparison_op_datetime.sql
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024
-big_timestamp = 11:30:45.000 PM 05/05/2024
+big_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_10_relational_op/_09_type_conversion/cases/04_10_09-13_comparison_op_timestamp.sql
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
+small_timestamp = 01:01:01 AM 01/01/2002
-big_timestamp = 11:30:45.000 PM 05/05/2024
-small_timestamp = 01:01:01.000 AM 01/01/2002
+big_timestamp = 11:30:45 PM 05/05/2024
+small_timestamp = 01:01:01 AM 01/01/2002
-small_timestamp = 01:01:01.000 AM 01/01/2002
-big_timestamp = 11:30:45.000 PM 05/05/2024
+small_timestamp = 01:01:01 AM 01/01/2002
+big_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-01_arithmetic_op_null.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-03_arithmetic_op_string.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-04_arithmetic_op_short.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-05_arithmetic_op_int.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-06_arithmetic_op_bigint.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-07_arithmetic_op_numeric.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-08_arithmetic_op_float.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-09_arithmetic_op_double.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-10_arithmetic_op_date.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-12_arithmetic_op_datetime.sql
-left_timestamp = 11:30:45.000 PM 05/05/2024
+left_timestamp = 11:30:45 PM 05/05/2024

### _05_plcsql/_01_testspec/_04_expression/_15_arithmetic_binary_op/_07_normal_type_conversion/cases/04_15_07-13_arithmetic_op_timestamp.sql
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-right_timestamp = 01:01:01.000 AM 01/01/2002
+right_timestamp = 01:01:01 AM 01/01/2002
-left_timestamp = 11:30:45.000 PM 05/05/2024
-right_timestamp = 01:01:01.000 AM 01/01/2002
+left_timestamp = 11:30:45 PM 05/05/2024
+right_timestamp = 01:01:01 AM 01/01/2002

### _05_plcsql/_01_testspec/_04_expression/_24_system_parmeters/cases/01_compat_numeric_division_scale.sql
-double div typeof:double
-double div:7.812500000000000e-03
+double div typeof:numeric
+double div:0.007812500000000000000000000000000000000000
-double div typeof:double
-double div:7.812500000000000e-03
+double div typeof:numeric
+double div:0.007812500000000000000000000000000000000000
-double div typeof:double
-double div:7.812500000000000e-03
+double div typeof:numeric
+double div:0.007812500000000000000000000000000000000000

### _35_fig_cake/plcsql/basic/cases/test_tcl.sql
-Error:-447
-Attempted to operate a query result structure already closed.
+Error:-21019
+Cannot communicate with the broker or received invalid packet
-0
+Error:-21003
+Cannot communicate with the broker
-0
+Error:-21003
+Cannot communicate with the broker
-0
+Error:-21003
+Cannot communicate with the broker
-    
-null     
-
+Error:-21003
+Cannot communicate with the broker
-code = 3, name = ccc
-code = 4, name = ddd
-0
+Error:-21003
+Cannot communicate with the broker
-code    name    
-1     aaa     
-2     bbb     
-3     ccc     
-4     ddd     
-
+Error:-21003
+Cannot communicate with the broker
-0
+Error:-21003
+Cannot communicate with the broker
-0
+Error:-21003
+Cannot communicate with the broker
+Cannot communicate with the broker[CAS INFO-localhost:33120,2,2310],[SESSION-3],[URL-jdbc:cubrid:localhost:33120:basic:dba:********:?charset=UTF-8].
```
